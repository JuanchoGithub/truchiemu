import Foundation

enum HLTBError: LocalizedError {
    case disabled
    case unavailable
    case noMatch
    case invalidInput
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .disabled: return "HowLongToBeat lookups are disabled."
        case .unavailable: return "Couldn't reach HowLongToBeat."
        case .noMatch: return "No matching game found on HowLongToBeat."
        case .invalidInput: return "Invalid HowLongToBeat URL or ID."
        case .network(let e): return e.localizedDescription
        }
    }
}

/// A candidate or resolved HowLongToBeat entry. Times are in hours.
struct HLTBMatch: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let platform: String?
    let mainStory: Double?
    let mainPlusExtras: Double?
    let completionist: Double?
    let allStyles: Double?
}

protocol HLTBDataProvider {
    func search(query: String, platform: String?) async throws -> [HLTBMatch]
    func fetchTimes(gameID: Int) async throws -> HLTBMatch
}

/// Talks directly to howlongtobeat.com.
///
/// HLTB has no official API and is fronted by Cloudflare. The search endpoint path
/// (`/api/s`, `/api/finder/v2`, `/api/search/site`, …) changes over time, so this
/// provider **discovers** the current path by scraping the homepage's Next.js JS
/// chunks. It then fetches an auth token from `<path>/init?t=<ms>` and POSTs the
/// search with full browser Client-Hints headers (required to pass Cloudflare bot
/// protection). Game detail pages are public HTML and fetched without a token.
final class DirectHLTBProvider: HLTBDataProvider {
    private let session: URLSession
    private let base = "https://howlongtobeat.com"

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"

    // Caches for the lifetime of the process.
    private var cachedSearchPath: String?
    private var cachedAuth: (token: String, hpKey: String, hpVal: String)?

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "\(base)/",
            "Origin": base,
            "Sec-Ch-Ua": "\"Not;A Brand\";v=\"99\", \"Google Chrome\";v=\"115\", \"Chromium\";v=\"115\"",
            "Sec-Ch-Ua-Mobile": "?0",
            "Sec-Ch-Ua-Platform": "\"macOS\"",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Dest": "empty",
            "DNT": "1"
        ]
        cfg.timeoutIntervalForRequest = 25
        session = URLSession(configuration: cfg)
    }

    // MARK: - Public API

    func search(query: String, platform: String?) async throws -> [HLTBMatch] {
        let path = await resolveSearchPath()
        let auth = try await resolveAuth(for: path)

        var body = Self.basePayload(query: query, platform: platform ?? "")
        body[auth.hpKey] = auth.hpVal

        let (data, resp) = try await postJSON(path: path, body: body, auth: auth)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        // 403 => token expired (the JS refreshes and retries). Do the same once.
        if status == 403 {
            LoggerService.debug(category: "HowLongToBeat", "search 403; refreshing auth and retrying")
            cachedAuth = nil
            let fresh = try await resolveAuth(for: path)
            cachedAuth = (token: fresh.token, hpKey: fresh.hpKey, hpVal: fresh.hpVal)
            var retryBody = Self.basePayload(query: query, platform: platform ?? "")
            retryBody[fresh.hpKey] = fresh.hpVal
            let (data2, resp2) = try await postJSON(path: path, body: retryBody, auth: fresh)
            guard let http2 = resp2 as? HTTPURLResponse, http2.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]] else {
                LoggerService.debug(category: "HowLongToBeat", "search retry failed (status=\((resp2 as? HTTPURLResponse)?.statusCode ?? 0))")
                throw HLTBError.noMatch
            }
            LoggerService.debug(category: "HowLongToBeat", "search retry OK: \(arr.count) results")
            return Self.parseMatches(arr)
        }

        guard status == 200 else {
            LoggerService.debug(category: "HowLongToBeat", "search non-200 status=\(status) path=\(path)")
            throw HLTBError.unavailable
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            LoggerService.debug(category: "HowLongToBeat", "search response not JSON or missing data array")
            throw HLTBError.noMatch
        }
        LoggerService.debug(category: "HowLongToBeat", "search OK: \(arr.count) results for query=\(query)")
        return Self.parseMatches(arr)
    }

    func fetchTimes(gameID: Int) async throws -> HLTBMatch {
        guard let url = URL(string: "\(base)/game/\(gameID)") else { throw HLTBError.invalidInput }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw HLTBError.unavailable
        }
        guard let html = String(data: data, encoding: .utf8) else { throw HLTBError.unavailable }
        return Self.parse(html: html, gameID: gameID)
    }

    // MARK: - Endpoint discovery

    /// Fetch the homepage, extract `/_next/static/chunks/*.js`, find the first
    /// `fetch("/api/...", { method: "POST", ... })` to learn the current search path.
    /// Falls back to `/api/search/site` (verified working) if discovery fails.
    private func resolveSearchPath() async -> String {
        if let cached = cachedSearchPath { return cached }
        var discovered: String? = nil

        if let homepage = try? await fetchHomepage(),
           let chunkURLs = extractChunkURLs(from: homepage) {
            for url in chunkURLs {
                if let script = try? await fetchText(url: url),
                   let path = discoverPath(in: script) {
                    discovered = path
                    break
                }
            }
        }

        let path = discovered ?? "/api/search/site"
        cachedSearchPath = path
        LoggerService.debug(category: "HowLongToBeat", "search path: \(path) (discovered=\(discovered != nil))")
        return path
    }

    private func fetchHomepage() async throws -> String {
        let url = URL(string: "\(base)/")!
        let (data, _) = try await session.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static let chunkRegex = try? NSRegularExpression(
        pattern: #"<script[^>]+src="(/_next/static/chunks/[^"]+\.js)""#,
        options: []
    )

    private func extractChunkURLs(from html: String) -> [URL]? {
        guard let regex = Self.chunkRegex else { return nil }
        var urls: [URL] = []
        regex.enumerateMatches(in: html, range: NSRange(html.startIndex..., in: html)) { match, _, _ in
            guard let match,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let url = URL(string: "https://howlongtobeat.com\(html[pathRange])") else { return }
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
    }

    private static let fetchPathRegex = try? NSRegularExpression(
        pattern: #"fetch\s*\(\s*["\']/api/([a-zA-Z0-9_/]+)[^"\']*["\']\s*,\s*\{[^}]*method\s*:\s*["\']POST["\'][^}]*\}"#,
        options: []
    )

    private func discoverPath(in script: String) -> String? {
        guard let regex = Self.fetchPathRegex,
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              match.numberOfRanges > 1 else { return nil }
        let ns = script as NSString
        let suffix = ns.substring(with: match.range(at: 1))
        return "/api/\(suffix)"
    }

    private func fetchText(url: URL) async throws -> String {
        let (data, _) = try await session.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Auth

    private struct Auth {
        let token: String
        let hpKey: String
        let hpVal: String
    }

    private func resolveAuth(for path: String) async throws -> Auth {
        if let cached = cachedAuth {
            return Auth(token: cached.token, hpKey: cached.hpKey, hpVal: cached.hpVal)
        }
        var comps = URLComponents(url: URL(string: "\(base)\(path)/init")!, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        let url = comps.url!

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            LoggerService.debug(category: "HowLongToBeat", "init failed: status=\((resp as? HTTPURLResponse)?.statusCode ?? 0) path=\(path)")
            throw HLTBError.unavailable
        }

        // Init JSON: {"token": "...", "hpKey": "ign_...", "hpVal": "..."}.
        guard let token = json["token"] as? String else { throw HLTBError.unavailable }
        let hpKey = json.first { $0.key.lowercased().contains("key") && $0.key.lowercased() != "token" }?.value as? String
        let hpVal = json.first { $0.key.lowercased().contains("val") && $0.key.lowercased() != "token" }?.value as? String
        guard let hpKey, let hpVal else { throw HLTBError.unavailable }

        let auth = Auth(token: token, hpKey: hpKey, hpVal: hpVal)
        cachedAuth = (token: token, hpKey: hpKey, hpVal: hpVal)
        return auth
    }

    private func postJSON(path: String, body: [String: Any], auth: Auth) async throws -> (Data, URLResponse) {
        let url = URL(string: "\(base)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        req.setValue(auth.token, forHTTPHeaderField: "x-auth-token")
        req.setValue(auth.hpKey, forHTTPHeaderField: "x-hp-key")
        req.setValue(auth.hpVal, forHTTPHeaderField: "x-hp-val")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await session.data(for: req)
    }

    private static func basePayload(query: String, platform: String) -> [String: Any] {
        [
            "searchType": "games",
            "searchTerms": query.split(separator: " ").map(String.init),
            "searchPage": 1,
            "size": 20,
            "searchOptions": [
                "games": [
                    "userId": 0,
                    "platform": platform,
                    "sortCategory": "popular",
                    "rangeCategory": "main",
                    "rangeTime": ["min": 0, "max": 0],
                    "gameplay": ["perspective": "", "flow": "", "genre": "", "difficulty": ""],
                    "rangeYear": ["min": "", "max": ""],
                    "modifier": ""
                ],
                "users": ["sortCategory": "postcount"],
                "lists": ["sortCategory": "follows"],
                "filter": "",
                "sort": 0,
                "randomizer": 0
            ],
            "useCache": true
        ]
    }

    /// Search response: comp_* fields are **seconds**, not hours.
    private static func parseMatches(_ arr: [[String: Any]]) -> [HLTBMatch] {
        arr.compactMap { d in
            guard let gid = d["game_id"] as? Int,
                  let name = d["game_name"] as? String else { return nil }
            return HLTBMatch(
                id: gid,
                title: name.htmlDecoded,
                platform: d["profile_platform"] as? String,
                mainStory: secondsToHours(d["comp_main"]),
                mainPlusExtras: secondsToHours(d["comp_plus"]),
                completionist: secondsToHours(d["comp_100"]),
                allStyles: secondsToHours(d["comp_all"])
            )
        }
    }

    private static func secondsToHours(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber { return n.doubleValue / 3600.0 }
        if let d = raw as? Double { return d / 3600.0 }
        if let i = raw as? Int { return Double(i) / 3600.0 }
        return nil
    }

    // MARK: - HTML parsing (game detail page)

    private static let statRegex = try? NSRegularExpression(
        pattern: #"<h4>(Main Story|Main \+ Sides|Main \+ Extras|Completionist)</h4>\s*<h5>([^<]+)</h5>"#,
        options: []
    )

    static func parse(html: String, gameID: Int) -> HLTBMatch {
        var title = ""
        if let m = html.firstMatch(of: #/<meta property="og:title" content="([^"]+)"[^>]*>/#) {
            var raw = String(m.1).htmlDecoded
            if let range = raw.range(of: " | HowLongToBeat") { raw.removeSubrange(range) }
            if raw.hasPrefix("How long is ") { raw.removeFirst("How long is ".count) }
            if raw.hasSuffix("?") { raw.removeLast() }
            title = raw
        }

        var mainStory: Double?, mainPlusExtras: Double?, completionist: Double?
        if let regex = statRegex {
            let ns = html as NSString
            let matches = regex.matches(
                in: html,
                range: NSRange(html.startIndex..., in: html)
            )
            for mm in matches {
                let label = ns.substring(with: mm.range(at: 1))
                let value = ns.substring(with: mm.range(at: 2))
                let hours = parseHours(value)
                switch label {
                case "Main Story": mainStory = hours
                case "Main + Sides", "Main + Extras": mainPlusExtras = hours
                case "Completionist": completionist = hours
                default: break
                }
            }
        }

        return HLTBMatch(
            id: gameID,
            title: title,
            platform: nil,
            mainStory: mainStory,
            mainPlusExtras: mainPlusExtras,
            completionist: completionist,
            allStyles: nil
        )
    }

    /// "8½ Hours" -> 8.5, "14 Hours" -> 14, "8h 51m" -> 8.85, "8h" -> 8.
    static func parseHours(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.contains("½") {
            let base = s.replacingOccurrences(of: "½", with: "")
                .replacingOccurrences(of: "hours", with: "")
                .trimmingCharacters(in: .whitespaces)
            return (Double(base) ?? 0) + 0.5
        }
        if let m = s.firstMatch(of: #/(\d+)\s*h\s*(\d+)?\s*m?/#) {
            let h = Double(m.1) ?? 0
            let min = m.2.map { Double($0) ?? 0 } ?? 0
            return h + min / 60.0
        }
        let stripped = s.replacingOccurrences(of: "hours", with: "")
            .replacingOccurrences(of: "h", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(stripped)
    }
}

@MainActor
final class HowLongToBeatService: ObservableObject {
    static let shared = HowLongToBeatService()

    private let provider: HLTBDataProvider = DirectHLTBProvider()
    private var timesCache: [Int: HLTBMatch] = [:]

    static var isEnabled: Bool {
        AppSettings.getBool("hltbEnabled", defaultValue: true)
    }

    /// Best-effort automatic match by title + platform.
    ///
    /// Honors a 15-day negative cache: if a recent search for this ROM found nothing
    /// on HLTB, repeated lookups return `.noMatch` without any network call until the
    /// freshness window expires (or `force` is set).
    func searchCandidates(for rom: ROM, library: ROMLibrary, force: Bool = false) async -> Result<[HLTBMatch], HLTBError> {
        guard Self.isEnabled else { return .failure(.disabled) }

        // Negative cache: skip the search if we recently learned this ROM isn't on HLTB.
        if !force,
           let lastNotFound = rom.metadata?.hltbLastNotFoundAt,
           Date().timeIntervalSince(lastNotFound) < Self.notFoundFreshness {
            LoggerService.debug(category: "HowLongToBeat", "searchCandidates: negative cache hit (age=\(Int(Date().timeIntervalSince(lastNotFound)))s)")
            return .failure(.noMatch)
        }

        let rawTitle = (rom.metadata?.title ?? rom.displayName)
        let queries = Self.searchQueryVariants(for: rawTitle)
        guard !queries.isEmpty else { return .failure(.invalidInput) }
        let platform = Self.platformString(for: rom.systemID)

        for query in queries {
            do {
                let matches = try await provider.search(query: query, platform: platform)
                if !matches.isEmpty {
                    LoggerService.debug(category: "HowLongToBeat", "searchCandidates: matched on variant '\(query)' (\(matches.count) results)")
                    return .success(matches)
                }
                LoggerService.debug(category: "HowLongToBeat", "searchCandidates: variant '\(query)' returned 0 results, trying next")
            } catch let e as HLTBError {
                LoggerService.debug(category: "HowLongToBeat", "searchCandidates: variant '\(query)' failed: \(e.localizedDescription)")
                return .failure(e)
            } catch {
                return .failure(.network(error))
            }
        }

        // All variants returned 0 results — remember that so we don't re-query for 15 days.
        LoggerService.debug(category: "HowLongToBeat", "searchCandidates: no matches for any variant; recording not-found timestamp")
        markNotFound(rom: rom, library: library)
        return .failure(.noMatch)
    }

    /// Build a ranked list of HLTB search queries for fuzzy matching.
    /// HLTB often uses different punctuation than ROM filenames (e.g. "Baldur's Gate:
    /// Dark Alliance" vs "Baldur's Gate - Dark Alliance"), and accepts different
    /// numbering (2 / II / Two). We try the cleaned title, then punctuation
    /// variations, then a number/roman variant, returning the first with results.
    static func searchQueryVariants(for rawTitle: String) -> [String] {
        let base = GameNameFormatter.stripTags(rawTitle).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return [] }

        var variants: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2, !variants.contains(t) else { return }
            variants.append(t)
        }

        add(base)

        // Swap dash/colon between words (covers the common "X - Y" vs "X: Y" mismatch).
        let dashToColon = base.replacingOccurrences(
            of: #"\s+[-–—]\s+"#,
            with: ": ",
            options: .regularExpression
        )
        if dashToColon != base { add(dashToColon) }

        let colonToDash = base.replacingOccurrences(
            of: #":\s+"#,
            with: " - ",
            options: .regularExpression
        )
        if colonToDash != base { add(colonToDash) }

        // Looser: drop dash/colon/quote punctuation entirely.
        let noPunct = base.replacingOccurrences(
            of: #"[-–—:']+"#,
            with: " ",
            options: .regularExpression
        )
        let noPunctClean = GameNameFormatter.cleanWhitespace(noPunct)
        if noPunctClean != base { add(noPunctClean) }

        // If there's a subtitle, try the leading segment only (e.g. "Baldur's Gate").
        for separator in [" - ", ": "] {
            if let range = base.range(of: separator) {
                let head = String(base[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if head.count >= 4 { add(head) }
                break
            }
        }

        // Number variants (II/2, III/3, Two, Three, ...) on the primary and the
        // dash-to-colon variant.
        for seed in [base, dashToColon] where seed != base {
            for v in ROMIdentifierService.romanNumeralVariants(of: seed) {
                add(v)
                if variants.count >= 6 { return Array(variants.prefix(6)) }
            }
        }

        return Array(variants.prefix(6))
    }

    /// Loads completion times for an HLTB game id with a 30-day freshness policy.
    /// - If `force` is true, always hits the network (manual override).
    /// - If a fresh cached entry exists (<30 days), returns it without any network call.
    /// - If a stale cached entry exists (>=30 days), attempts a network refresh;
    ///   on success, updates the cache and the ROM's metadata. On failure, returns
    ///   the stale entry so the UI keeps showing the old data.
    /// - With no cached entry, fetches from the network. On success, caches and
    ///   updates the ROM's metadata. On failure, returns the error.
    ///
    /// Every success path writes the times into the ROM's metadata via `apply` so
    /// the card transitions to the fully-populated dataCard (not stuck on the
    /// "picked but no times" state when the cache is fresh and the ROM was just
    /// updated with a candidate by `persistCandidate`).
    func loadTimes(gameID: Int, rom: ROM, library: ROMLibrary, force: Bool = false) async -> Result<HLTBMatch, HLTBError> {
        guard Self.isEnabled else { return .failure(.disabled) }

        let now = Date()
        let cached = cachedEntry(for: gameID)
        let isFresh = cached.map { now.timeIntervalSince($0.fetchedAt) < Self.resolvedFreshness } ?? false

        if !force, let entry = cached, isFresh {
            LoggerService.debug(category: "HowLongToBeat", "loadTimes: fresh cache for id=\(gameID) age=\(Int(now.timeIntervalSince(entry.fetchedAt)))s")
            timesCache[gameID] = entry.match
            apply(entry.match, to: rom, library: library)
            return .success(entry.match)
        }

        // Network fetch (forced or stale/missing).
        do {
            let match = try await provider.fetchTimes(gameID: gameID)
            timesCache[gameID] = match
            Self.persistedTimes[gameID] = CachedTimeEntry(match: match, fetchedAt: now)
            apply(match, to: rom, library: library)
            LoggerService.debug(category: "HowLongToBeat", "loadTimes: refreshed id=\(gameID) force=\(force) wasStale=\(cached != nil)")
            return .success(match)
        } catch let e as HLTBError {
            // Keep old data on failure if we have a stale cache.
            if let entry = cached {
                LoggerService.debug(category: "HowLongToBeat", "loadTimes: refresh failed (\(e.localizedDescription)); keeping stale cache for id=\(gameID)")
                timesCache[gameID] = entry.match
                apply(entry.match, to: rom, library: library)
                return .success(entry.match)
            }
            return .failure(e)
        } catch {
            if let entry = cached {
                LoggerService.debug(category: "HowLongToBeat", "loadTimes: network error; keeping stale cache for id=\(gameID)")
                timesCache[gameID] = entry.match
                apply(entry.match, to: rom, library: library)
                return .success(entry.match)
            }
            return .failure(.network(error))
        }
    }

    /// Low-level: fetch a single game id from the network, ignoring the cache.
    /// Used by the manual-paste path before the candidate is even persisted.
    func fetchTimes(gameID: Int) async -> Result<HLTBMatch, HLTBError> {
        guard Self.isEnabled else { return .failure(.disabled) }
        do {
            let match = try await provider.fetchTimes(gameID: gameID)
            timesCache[gameID] = match
            Self.persistedTimes[gameID] = CachedTimeEntry(match: match, fetchedAt: Date())
            return .success(match)
        } catch let e as HLTBError {
            return .failure(e)
        } catch {
            return .failure(.network(error))
        }
    }

    /// Writes the chosen HLTB candidate (game ID + title) into the ROM's metadata
    /// **before** fetching completion times, so the search result is never lost
    /// — even if the user closes the detail view mid-fetch or relaunches the app.
    func persistCandidate(_ match: HLTBMatch, to rom: ROM, library: ROMLibrary) {
        var updated = rom
        var meta = updated.metadata ?? ROMMetadata()
        meta.hltbGameID = match.id
        // Keep any existing title if the new match has no title (e.g. manual paste).
        if !match.title.isEmpty {
            meta.hltbMatchedTitle = match.title
        } else if meta.hltbMatchedTitle == nil {
            meta.hltbMatchedTitle = ""
        }
        updated.metadata = meta
        library.updateROM(updated)
    }

    // MARK: - Persisted times cache (AppSettings)

    /// Freshness policy.
    static let resolvedFreshness: TimeInterval = 30 * 24 * 60 * 60   // 30 days
    static let notFoundFreshness: TimeInterval = 15 * 24 * 60 * 60   // 15 days

    private static let persistedTimesKey = "hltbTimesCache"

    /// Cached HLTB entry plus the time it was fetched. The fetchedAt drives the
    /// 30-day re-check policy; if a refresh fails we keep serving the old entry.
    struct CachedTimeEntry: Codable {
        var match: HLTBMatch
        var fetchedAt: Date
    }

    /// On-disk cache of `CachedTimeEntry` keyed by HLTB game id. Survives app
    /// relaunches so the public game-page scrape is done at most once per id
    /// per freshness window. Tolerates the older `[Int: HLTBMatch]` format by
    /// treating its entries as stale (forces a one-time refresh).
    private static var persistedTimes: [Int: CachedTimeEntry] {
        get {
            guard let data = AppSettings.getData(persistedTimesKey) else { return [:] }
            if let dict = try? JSONDecoder().decode([String: CachedTimeEntry].self, from: data) {
                var out: [Int: CachedTimeEntry] = [:]
                for (k, v) in dict { if let id = Int(k) { out[id] = v } }
                return out
            }
            // Legacy format: [Int: HLTBMatch] — treat as stale so we refresh once.
            if let dict = try? JSONDecoder().decode([String: HLTBMatch].self, from: data) {
                let staleDate = Date(timeIntervalSince1970: 0)
                var out: [Int: CachedTimeEntry] = [:]
                for (k, v) in dict { if let id = Int(k) { out[id] = CachedTimeEntry(match: v, fetchedAt: staleDate) } }
                return out
            }
            return [:]
        }
        set {
            let dict = Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })
            if let data = try? JSONEncoder().encode(dict) {
                AppSettings.setData(persistedTimesKey, value: data)
            }
        }
    }

    private func cachedEntry(for gameID: Int) -> CachedTimeEntry? {
        if let m = timesCache[gameID] {
            return CachedTimeEntry(match: m, fetchedAt: Date())
        }
        return Self.persistedTimes[gameID]
    }

    /// Extracts a numeric game ID from a pasted HLTB URL or raw ID.
    func parseGameID(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = trimmed.firstMatch(of: #/game\/(\d+)/#) {
            return Int(m.1)
        }
        return Int(trimmed)
    }

    /// Writes resolved times into the ROM's metadata and persists through the library.
    func apply(_ match: HLTBMatch, to rom: ROM, library: ROMLibrary) {
        var updated = rom
        var meta = updated.metadata ?? ROMMetadata()
        meta.hltbGameID = match.id
        meta.hltbMatchedTitle = match.title
        meta.hltbMainStoryHours = match.mainStory
        meta.hltbMainPlusExtrasHours = match.mainPlusExtras
        meta.hltbCompletionistHours = match.completionist
        meta.hltbAllStylesHours = match.allStyles
        // A successful apply means we have data — clear the "not found" timestamp.
        meta.hltbLastNotFoundAt = nil
        updated.metadata = meta
        library.updateROM(updated)
        timesCache[match.id] = match
        // Preserve the original fetchedAt if we already have a cached entry; else stamp now.
        let now = Date()
        if Self.persistedTimes[match.id] == nil {
            Self.persistedTimes[match.id] = CachedTimeEntry(match: match, fetchedAt: now)
        } else {
            // Update the match fields but keep the original fetchedAt so the freshness window
            // measures "when we last verified against the network", not "when we last wrote".
            var entry = Self.persistedTimes[match.id]!
            entry.match = match
            Self.persistedTimes[match.id] = entry
            _ = now
        }
    }

    /// Records that the most recent HLTB search for this ROM returned no results,
    /// so we can throttle future lookups (15-day freshness).
    func markNotFound(rom: ROM, library: ROMLibrary) {
        var updated = rom
        var meta = updated.metadata ?? ROMMetadata()
        meta.hltbLastNotFoundAt = Date()
        updated.metadata = meta
        library.updateROM(updated)
    }

    /// Maps a TruchiEmu system ID to the closest HLTB platform filter string.
    static func platformString(for systemID: String?) -> String? {
        guard let id = systemID?.lowercased() else { return nil }
        let map: [String: String] = [
            "nes": "NES",
            "snes": "Super Nintendo",
            "n64": "Nintendo 64",
            "gc": "Nintendo GameCube",
            "wii": "Nintendo Wii",
            "wiiu": "Nintendo Wii U",
            "switch": "Nintendo Switch",
            "gb": "Game Boy",
            "gbc": "Game Boy Color",
            "gba": "Game Boy Advance",
            "nds": "Nintendo DS",
            "3ds": "Nintendo 3DS",
            "virtualboy": "Virtual Boy",
            "genesis": "Sega Genesis",
            "megadrive": "Sega Genesis",
            "segacd": "Sega CD",
            "sega32x": "Sega 32X",
            "saturn": "Sega Saturn",
            "dreamcast": "Sega Dreamcast",
            "gamegear": "Sega Game Gear",
            "sms": "Sega Master System",
            "psx": "PlayStation",
            "psp": "PlayStation Portable",
            "ps2": "PlayStation 2",
            "ps3": "PlayStation 3",
            "ps4": "PlayStation 4",
            "psvita": "PlayStation Vita",
            "atari2600": "Atari 2600",
            "atari7800": "Atari 7800",
            "lynx": "Atari Lynx",
            "jaguar": "Atari Jaguar",
            "neogeo": "Neo Geo",
            "ngp": "Neo Geo Pocket",
            "ngpc": "Neo Geo Pocket Color",
            "wonderswan": "WonderSwan",
            "pce": "PC Engine",
            "pcfx": "PC-FX",
            "mame": "Arcade",
            "arcade": "Arcade",
            "fba": "Arcade",
            "msx": "MSX",
            "dos": "PC",
            "pc": "PC",
            "xbox": "Xbox",
            "xbox360": "Xbox 360"
        ]
        return map[id]
    }
}

// MARK: - HTML entity decoding

private let numericEntityRegex = try! NSRegularExpression(
    pattern: #"&#(x?)([0-9A-Fa-f]+);"#
)

extension String {
    /// Decodes the common HTML entities that HLTB serves inside its API and
    /// detail-page strings (e.g. `Baldur&#x27;s Gate` → `Baldur's Gate`).
    /// Handles named entities (`&amp;`, `&quot;`, `&lt;`, `&gt;`, `&apos;`,
    /// `&nbsp;`) plus numeric decimal `&#NNN;` and hex `&#xHH;` forms.
    var htmlDecoded: String {
        guard contains("&") else { return self }

        // 1) Named entities (literal replacements; do these first).
        var s = self
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&apos;", "'"),
            ("&quot;", "\""),
            ("&lt;", "<"),
            ("&gt;", ">")
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }

        // 2) Numeric entities (&#NNN; / &#xHH;) — build the result manually so we
        //    can turn the captured codepoint into the actual character.
        let ns = s as NSString
        let matches = numericEntityRegex.matches(
            in: s,
            range: NSRange(s.startIndex..., in: s)
        )
        guard !matches.isEmpty else {
            // No numeric entities left; finish with &amp; (must be last so the
            // ampersands the numeric step would have introduced stay literal).
            return s.replacingOccurrences(of: "&amp;", with: "&")
        }

        var out = ""
        var cursor = s.startIndex
        for match in matches {
            let matchRange = Range(match.range, in: s)!
            let prefixRange = cursor..<matchRange.lowerBound
            out.append(contentsOf: s[prefixRange])
            let isHex = match.range(at: 1).location != NSNotFound
                && ns.substring(with: match.range(at: 1)) == "x"
            let digits = ns.substring(with: match.range(at: 2))
            let radix = isHex ? 16 : 10
            if let value = UInt32(digits, radix: radix),
               let scalar = Unicode.Scalar(value) {
                out.unicodeScalars.append(scalar)
            }
            // If the entity is malformed, just drop it.
            cursor = matchRange.upperBound
        }
        out.append(contentsOf: s[cursor..<s.endIndex])
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}

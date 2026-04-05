import Foundation
import AppKit

// MARK: - LaunchBox GamesDB Platform Mapping

/// Maps internal system IDs to LaunchBox GamesDB display platform names.
enum LaunchBoxPlatformMapper {
    static func launchBoxPlatformName(for systemID: String) -> String? {
        let map: [String: String] = [
            "nes": "Nintendo Entertainment System",
            "snes": "Super Nintendo Entertainment System",
            "n64": "Nintendo 64",
            "gba": "Nintendo Game Boy Advance",
            "gb": "Nintendo Game Boy",
            "gbc": "Nintendo Game Boy Color",
            "nds": "Nintendo DS",
            "genesis": "Sega Genesis",
            "sms": "Sega Master System",
            "gamegear": "Sega Game Gear",
            "saturn": "Sega Saturn",
            "dreamcast": "Sega Dreamcast",
            "psx": "Sony Playstation",
            "ps2": "Sony Playstation 2",
            "psp": "Sony Playstation Portable",
            "mame": "Arcade",
            "fba": "Arcade",
            "atari2600": "Atari 2600",
            "atari5200": "Atari 5200",
            "atari7800": "Atari 7800",
            "lynx": "Atari Lynx",
            "ngp": "Neo Geo Pocket",
            "pce": "TurboGrafx-16",
            "pcfx": "PC-FX",
        ]
        return map[systemID.lowercased()]
    }
}

// MARK: - LaunchBox GamesDB Search Result
struct LaunchBoxGameResult {
    let title: String
    let gameId: Int
    let boxartURL: URL?
    let detailURL: URL?
}

// MARK: - Media Types
enum LaunchBoxMediaType: String {
    case boxart = "BoxartScreenshotImage"
    case titleScreen = "TitleScreenImage"
    case clearLogo = "ClearLogoImage"
    case banner = "BannerImage"
    case cartridge = "CartridgeImage"
}

// MARK: - LaunchBox GamesDB Media Service

/// Fetches boxart and game metadata from the LaunchBox GamesDB (gamesdb.launchbox-app.com).
/// Uses web scraping and HTML parsing to discover game entries and their media URLs.
@MainActor
class LaunchBoxGamesDBService: ObservableObject {
    static let shared = LaunchBoxGamesDBService()

    private let baseURL = URL(string: "https://gamesdb.launchbox-app.com")!

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Settings (AppSettings)

    private let keyUseLaunchBox = "launchbox_use_for_boxart"
    private let keyDownloadBoxartAfterScan = "launchbox_download_after_scan"

    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0
    @Published var syncStatus: String = ""

    var isEnabled: Bool {
        get { AppSettings.getBool(keyUseLaunchBox, defaultValue: false) }
        set { AppSettings.setBool(keyUseLaunchBox, value: newValue) }
    }

    var downloadAfterScan: Bool {
        get { AppSettings.getBool(keyDownloadBoxartAfterScan, defaultValue: true) }
        set { AppSettings.setBool(keyDownloadBoxartAfterScan, value: newValue) }
    }

    // MARK: - Primary: Fetch BoxArt for a ROM

    /// Search LaunchBox GamesDB and return boxart URL for a ROM.
    /// Uses CRC-identified name when available, otherwise sanitizes filename.
    func fetchBoxArt(for rom: ROM) async -> URL? {
        guard isEnabled else {
            LoggerService.debug(category: "LaunchBoxDB", "LaunchBox GamesDB is disabled in settings")
            return nil
        }

        LoggerService.info(category: "LaunchBoxDB", "Starting LaunchBox search for '\(rom.name)' (systemID: \(rom.systemID ?? "unknown"))")

        var titleToSearch = ""
        if let crcName = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !crcName.isEmpty {
            titleToSearch = crcName
            LoggerService.debug(category: "LaunchBoxDB", "Using CRC-identified title: '\(titleToSearch)'")
        } else {
            let stem = rom.path.deletingPathExtension().lastPathComponent
            titleToSearch = LibretroThumbnailResolver.stripRomFilenameTags(stem)
            LoggerService.debug(category: "LaunchBoxDB", "Using filename-derived title: '\(titleToSearch)' (orig stem: '\(stem)')")
        }

        guard !titleToSearch.isEmpty else {
            LoggerService.debug(category: "LaunchBoxDB", "Empty title after processing, aborting search")
            return nil
        }

        let platformName = rom.systemID.flatMap { LaunchBoxPlatformMapper.launchBoxPlatformName(for: $0) }
        LoggerService.info(category: "LaunchBoxDB", "Searching for '\(titleToSearch)' on platform [\(platformName ?? "any")]")

        // Try direct game search page
        LoggerService.debug(category: "LaunchBoxDB", "Step 1: Web search for games")
        let results = await searchGamesWeb(title: titleToSearch, platformName: platformName)
        LoggerService.debug(category: "LaunchBoxDB", "Web search returned \(results.count) results")
        for (idx, result) in results.enumerated() {
            LoggerService.debug(category: "LaunchBoxDB", "  Result #\(idx+1): title='\(result.title)', gameId=\(result.gameId), boxartURL=\(result.boxartURL?.absoluteString ?? "nil")")
        }

        for result in results {
            if let boxartURL = result.boxartURL {
                LoggerService.debug(category: "LaunchBoxDB", "Attempting to download boxart from \(boxartURL.absoluteString)")
                if let cached = await downloadAndCache(artURL: boxartURL, for: rom) {
                    LoggerService.info(category: "LaunchBoxDB", "SUCCESS: cached boxart from search results")
                    return cached
                }
            }
        }

        // Try detail pages if search results had no direct boxart
        if let firstGame = results.first {
            LoggerService.debug(category: "LaunchBoxDB", "Step 2: Checking detail page for gameId=\(firstGame.gameId)")
            if let detailBoxart = await fetchBoxArtFromDetailWeb(gameId: firstGame.gameId, rom: rom) {
                LoggerService.info(category: "LaunchBoxDB", "SUCCESS: found boxart from detail page gameId=\(firstGame.gameId)")
                return detailBoxart
            }
        }

        // Try alternate title variants
        let alternateTitle = Self.cleanAlternateTitle(titleToSearch)
        if alternateTitle != titleToSearch {
            LoggerService.info(category: "LaunchBoxDB", "Trying alternate title: '\(alternateTitle)'")
            let altResults = await searchGamesWeb(title: alternateTitle, platformName: platformName)
            LoggerService.debug(category: "LaunchBoxDB", "Alternate search returned \(altResults.count) results")
            for result in altResults {
                if let boxartURL = result.boxartURL {
                    if let cached = await downloadAndCache(artURL: boxartURL, for: rom) {
                        LoggerService.info(category: "LaunchBoxDB", "SUCCESS: found boxart from alternate title search")
                        return cached
                    }
                }
            }
            if let firstGame = altResults.first {
                LoggerService.debug(category: "LaunchBoxDB", "Checking detail page for alternate result gameId=\(firstGame.gameId)")
                if let detailBoxart = await fetchBoxArtFromDetailWeb(gameId: firstGame.gameId, rom: rom) {
                    LoggerService.info(category: "LaunchBoxDB", "SUCCESS: found boxart from alternate detail page gameId=\(firstGame.gameId)")
                    return detailBoxart
                }
            }
        } else {
            LoggerService.debug(category: "LaunchBoxDB", "No alternate title variant (cleaned title same as original)")
        }

        LoggerService.info(category: "LaunchBoxDB", "LaunchBox search COMPLETE — no boxart found for '\(rom.name)'")
        return nil
    }

    /// Clean and create alternate title search for better matching.
    nonisolated private static func cleanAlternateTitle(_ title: String) -> String {
        var cleaned = title
        // Remove region tags in parentheses
        cleaned = cleaned.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        // Remove version suffixes
        cleaned = cleaned.replacingOccurrences(of: "\\(v[0-9.]+\\)$", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Web Search

    /// Search LaunchBox GamesDB web interface for games.
    private func searchGamesWeb(title: String, platformName: String?) async -> [LaunchBoxGameResult] {
        var results: [LaunchBoxGameResult] = []

        let searchURL = baseURL
            .appendingPathComponent("games")
            .appendingPathComponent("search")

        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "query", value: title)]
        if let platform = platformName {
            components?.queryItems?.append(URLQueryItem(name: "platformId", value: platform))
        }

        guard let url = components?.url else {
            LoggerService.debug(category: "LaunchBoxDB", "searchGamesWeb: failed to construct URL for title='\(title)', platform=\(platformName ?? "nil")")
            return []
        }

        LoggerService.debug(category: "LaunchBoxDB", "searchGamesWeb: fetching \(url.absoluteString)")

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                LoggerService.debug(category: "LaunchBoxDB", "searchGamesWeb: response status \(statusCode) or encoding error for \(url.absoluteString)")
                return []
            }

            results = parseGameSearchResults(html)
            LoggerService.debug(category: "LaunchBoxDB", "searchGamesWeb: parsed \(results.count) results from \(results.count > 0 ? "first" : "no") page for '\(title)'")
        } catch {
            LoggerService.warning(category: "LaunchBoxDB", "searchGamesWeb: network error for \(url.absoluteString): \(error.localizedDescription)")
        }

        // Retry without platform if nothing found
        if results.isEmpty && platformName != nil {
            LoggerService.debug(category: "LaunchBoxDB", "searchGamesWeb: no results with platform, retrying without platform filter")
            results = await searchGamesWeb(title: title, platformName: nil)
        }

        return results
    }

    /// Parse game search result entries from HTML.
    private func parseGameSearchResults(_ html: String) -> [LaunchBoxGameResult] {
        var results: [LaunchBoxGameResult] = []

        // Pattern: game detail links - <a href="/games/details/12345">Game Title</a>
        let linkPattern = "href=[\"']/games/details/(\\d+)[\"'][^>]*>([^<]+)<" 
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, options: [], range: nsRange) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 3 else { return }
                if let idRange = Range(match.range(at: 1), in: html),
                   let titleRange = Range(match.range(at: 2), in: html) {
                    let idStr = String(html[idRange])
                    let titleStr = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let gameId = Int(idStr), !titleStr.isEmpty, titleStr.count > 1 {
                        // Try to find boxart URL near this entry
                        let entryStart = match.range.location
                        let searchRange = NSRange(location: max(0, entryStart - 2000),
                                                  length: min(4000, html.utf16.count - max(0, entryStart - 2000)))
                        let boxartURL = extractFirstBoxartURL(in: html, range: searchRange)
                        results.append(LaunchBoxGameResult(title: titleStr, gameId: gameId, boxartURL: boxartURL, detailURL: nil))
                    }
                }
            }
        }

        return results
    }

    /// Extract first boxart/cover image URL from an HTML range.
    private func extractFirstBoxartURL(in html: String, range: NSRange) -> URL? {
        let subRange = Range(range, in: html) ?? html.startIndex..<html.endIndex
        let sub = String(html[subRange])

        // Patterns for boxart images
        let patterns = [
            // CDN boxart images
            "(https://[^\"'>\\s]+[bB]oxart[^\"'>\\s]*\\.(?:jpg|png|jpeg))" ,
            "(https://[^\"'>\\s]+[cC]over[^\"'>\\s]*\\.(?:jpg|png|jpeg))" ,
            // Any CDN image (fallback)
            "(https://cdn\\.launchbox-app\\.com[^\"'>\\s]+\\.(?:jpg|png|jpeg))" ,
            // Generic images that could be boxart
            "(https://[^\"'>\\s]+/images/[^\"'>\\s]+\\.(?:jpg|png|jpeg))" ,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(sub.startIndex..., in: sub)
                if let match = regex.firstMatch(in: sub, options: [], range: nsRange) {
                    if let urlRange = Range(match.range(at: 1), in: sub) {
                        let urlString = String(sub[urlRange])
                        if let url = URL(string: urlString) {
                            return url
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Fetch BoxArt from Game Detail Page

    private func fetchBoxArtFromDetailWeb(gameId: Int, rom: ROM) async -> URL? {
        let url = baseURL
            .appendingPathComponent("games")
            .appendingPathComponent("details")
            .appendingPathComponent(String(gameId))

        LoggerService.debug(category: "LaunchBoxDB", "fetchBoxArtFromDetailWeb: fetching \(url.absoluteString)")

        do {
            var request = URLRequest(url: url)
            request.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                LoggerService.debug(category: "LaunchBoxDB", "fetchBoxArtFromDetailWeb: response status \(statusCode) or encoding error for \(url.absoluteString)")
                return nil
            }

            LoggerService.debug(category: "LaunchBoxDB", "fetchBoxArtFromDetailWeb: page received (\(data.count) bytes), scanning for boxart images")

            // Extract images from detail page
            if let boxartURL = extractBoxartFromDetailHTML(html) {
                LoggerService.debug(category: "LaunchBoxDB", "fetchBoxArtFromDetailWeb: found boxart URL in detail page HTML")
                return await downloadAndCache(artURL: boxartURL, for: rom)
            } else {
                LoggerService.debug(category: "LaunchBoxDB", "fetchBoxArtFromDetailWeb: no boxart images found in detail page HTML")
            }
        } catch {
            LoggerService.warning(category: "LaunchBoxDB", "fetchBoxArtFromDetailWeb: network error for game \(gameId): \(error.localizedDescription)")
        }
        return nil
    }

    /// Extract boxart URL from game detail page HTML.
    private func extractBoxartFromDetailHTML(_ html: String) -> URL? {
        // LaunchBox GamesDB detail pages include images with specific class names or patterns
        let patterns = [
            // Image tags with boxart/cover in filename or class
            "<img[^>]+(?:class|src)=[\"'][^\"']*(?:boxart|cover|Boxart|Cover)[^\"']*(?:src|class)=[\"']([^\"'>\\s]+\\.(?:jpg|png|jpeg))[\"'][^>]*>",
            // Generic img tags - first image that looks like artwork
            "<img[^>]+src=[\"'](https://[^\"'>\\s]+\\.(?:jpg|png|jpeg))[\"'][^>]*>",
            // Data-src lazy loaded images
            "data-src=[\"'](https://[^\"'>\\s]+\\.(?:jpg|png|jpeg))[\"']",
            // Meta og:image
            "property=[\"']og:image[\"']\\s+content=[\"'](https://[^\"']+)[\"']",
            // Background image
            "background-image:\\s*url\\([\"']?(https://[^\"'>\\s]+\\.(?:jpg|png|jpeg))[\"']?\\)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: nsRange) {
                    let urlIndex = match.numberOfRanges > 1 ? 1 : 0
                    if let urlRange = Range(match.range(at: urlIndex), in: html) {
                        let urlString = String(html[urlRange])
                        if let url = URL(string: urlString) {
                            // Validate it is CDN or media URL
                            if urlString.contains("cdn") || urlString.contains("media") || urlString.contains("launchbox") || urlString.contains("://") {
                                return url
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Download & Cache

    /// Download boxart image and cache it locally for a ROM.
    private func downloadAndCache(artURL: URL, for rom: ROM) async -> URL? {
        let localURL = rom.boxArtLocalPath
        let folder = localURL.deletingLastPathComponent()

        LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: downloading \(artURL.absoluteString) → target \(localURL.path)")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: ensured folder \(folder.path)")

        if FileManager.default.fileExists(atPath: localURL.path) {
            LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: removing existing file at \(localURL.path)")
            try? FileManager.default.removeItem(at: localURL)
        }

        do {
            LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: starting download")
            let (tmpURL, response) = try await urlSession.download(from: artURL)

            // Verify it is actually an image
            if let httpResponse = response as? HTTPURLResponse {
                let mimeType = httpResponse.mimeType ?? "unknown"
                LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: HTTP \(httpResponse.statusCode), MIME type: \(mimeType), size: \(httpResponse.expectedContentLength) bytes")
                if !mimeType.hasPrefix("image/") {
                    LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: skipping non-image content type '\(mimeType)'")
                    try? FileManager.default.removeItem(at: tmpURL)
                    return nil
                }
            }

            // Verify file is valid image
            if NSImage(contentsOf: tmpURL) != nil {
                try FileManager.default.moveItem(at: tmpURL, to: localURL)
                await ImageCache.shared.removeImage(for: localURL)
                LoggerService.info(category: "LaunchBoxDB", "downloadAndCache: successfully cached boxart for '\(rom.name)' at \(localURL.path)")
                return localURL
            } else {
                LoggerService.debug(category: "LaunchBoxDB", "downloadAndCache: downloaded file is not a valid image")
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }
        } catch {
            LoggerService.warning(category: "LaunchBoxDB", "downloadAndCache: error downloading from \(artURL.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Batch Download

    /// Batch download boxart from LaunchBox GamesDB for multiple ROMs.
    /// First cleans broken boxarts, then downloads for all ROMs missing valid art.
    func batchDownloadBoxArt(for roms: [ROM], library: ROMLibrary, onItemProgress: ((Int, Int, String) -> Void)? = nil) async {
        guard isEnabled else { return }

        // Clean broken boxarts first
        let broken = BoxArtService.shared.findBrokenBoxArts(in: roms)
        if !broken.isEmpty {
            LoggerService.info(category: "LaunchBoxDB", "Found \(broken.count) broken boxart(s), cleaning before download...")
            let cleaned = await BoxArtService.shared.cleanBrokenBoxArts(for: broken)
            LoggerService.info(category: "LaunchBoxDB", "Cleaned \(cleaned.count) broken boxart(s)")
        }

        // Find all ROMs needing boxart (missing + broken)
        let needsArt = BoxArtService.shared.romsNeedingBoxArt(in: roms)

        guard !needsArt.isEmpty else {
            LoggerService.info(category: "LaunchBoxDB", "No ROMs missing or with broken boxart, skipping LaunchBox batch.")
            return
        }

        LoggerService.info(category: "LaunchBoxDB", "Starting LaunchBox batch for \(needsArt.count) ROMs...")
        let total = needsArt.count

        await MainActor.run {
            BoxArtService.shared.downloadQueueCount = total
            BoxArtService.shared.downloadedCount = 0
            BoxArtService.shared.isDownloadingBatch = true
        }

        let maxConcurrent = 1 // Ultra-conservative for UI responsiveness
        var completed = 0

        await withTaskGroup(of: (ROM, URL?).self) { group in
            var active = 0
            var iter = needsArt.makeIterator()

            while active < maxConcurrent, let rom = iter.next() {
                group.addTask { [weak self] in
                    @MainActor func fetch() async -> (ROM, URL?) {
                        if let s = self {
                            let url = await s.fetchBoxArtInner(for: rom)
                            return (rom, url)
                        }
                        return (rom, nil)
                    }
                    return await fetch()
                }
                active += 1
            }

            for await result in group {
                active -= 1
                var (completedRom, url) = result

                if let savedURL = url {
                    completedRom.boxArtPath = savedURL
                    await MainActor.run { library.updateROM(completedRom) }
                }

                completed += 1
                let label = "\(completedRom.displayName).png"

                // Throttle: 750ms + yield between requests to keep app responsive
                try? await Task.sleep(nanoseconds: 750_000_000)
                await Task.yield()

                await MainActor.run {
                    BoxArtService.shared.downloadedCount = completed
                    onItemProgress?(completed, total, label)
                }

                if let next = iter.next() {
                    group.addTask { [weak self] in
                        @MainActor func fetch() async -> (ROM, URL?) {
                            if let s = self {
                                let url = await s.fetchBoxArtInner(for: next)
                                return (next, url)
                            }
                            return (next, nil)
                        }
                        return await fetch()
                    }
                    active += 1
                }
            }
        }

        await MainActor.run {
            BoxArtService.shared.isDownloadingBatch = false
        }

        LoggerService.info(category: "LaunchBoxDB", "LaunchBox batch complete. \(completed)/\(total) processed.")
    }

    /// Internal fetch helper for batch downloads - called via MainActor.
    private func fetchBoxArtInner(for rom: ROM) async -> URL? {
        var titleToSearch = ""
        if let crcName = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !crcName.isEmpty {
            titleToSearch = crcName
        } else {
            let stem = rom.path.deletingPathExtension().lastPathComponent
            titleToSearch = LibretroThumbnailResolver.stripRomFilenameTags(stem)
        }

        guard !titleToSearch.isEmpty else { return nil }

        let platformName = rom.systemID.flatMap { LaunchBoxPlatformMapper.launchBoxPlatformName(for: $0) }

        // Search web
        let results = await searchGamesWeb(title: titleToSearch, platformName: platformName)
        for result in results {
            if let boxartURL = result.boxartURL {
                if let cached = await downloadAndCache(artURL: boxartURL, for: rom) {
                    return cached
                }
            }
        }

        if let firstGame = results.first {
            if let detailBoxart = await fetchBoxArtFromDetailWeb(gameId: firstGame.gameId, rom: rom) {
                return detailBoxart
            }
        }

        // Alternate title
        let alternateTitle = Self.cleanAlternateTitle(titleToSearch)
        if alternateTitle != titleToSearch {
            let altResults = await searchGamesWeb(title: alternateTitle, platformName: platformName)
            for result in altResults {
                if let boxartURL = result.boxartURL {
                    if let cached = await downloadAndCache(artURL: boxartURL, for: rom) {
                        return cached
                    }
                }
            }
            if let firstGame = altResults.first {
                if let detailBoxart = await fetchBoxArtFromDetailWeb(gameId: firstGame.gameId, rom: rom) {
                    return detailBoxart
                }
            }
        }

        return nil
    }

    // MARK: - Metadata Sync (used by MetadataSyncCoordinator)

    /// Set enabled/disabled state and persist.
    func setEnabled(_ enabled: Bool) {
        AppSettings.setBool(keyUseLaunchBox, value: enabled)
    }

    /// Last sync date stored in SQLite settings.
    var lastSyncDate: Date? {
        let interval = AppSettings.getDouble("launchbox_last_sync", defaultValue: 0); guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    /// Record the current sync time.
    func recordSyncDate() {
        AppSettings.setDouble("launchbox_last_sync", value: Date().timeIntervalSince1970)
    }

    /// Fetch and apply metadata for a single ROM.
    func fetchAndApplyMetadata(for rom: ROM, library: ROMLibrary) async -> Bool {
        guard let boxArtURL = await fetchBoxArt(for: rom) else { return false }
        await MainActor.run {
            var updated = rom
            updated.boxArtPath = boxArtURL
            library.updateROM(updated)
        }
        return true
    }

    /// Batch-sync the entire library with a progress callback.
    func batchSyncLibrary(library: ROMLibrary, onProgress: @escaping (Int, Int, String) -> Void) async {
        guard isEnabled else { return }

        let allRoms = library.roms
        let total = allRoms.count
        guard total > 0 else { return }

        let maxConcurrent = 1
        var completed = 0

        await withTaskGroup(of: (ROM, URL?).self) { group in
            var iter = allRoms.makeIterator()
            var active = 0

            while active < maxConcurrent, let rom = iter.next() {
                group.addTask { @MainActor [weak self] in
                    if let s = self {
                        let url = await s.fetchBoxArtInner(for: rom)
                        return (rom, url)
                    }
                    return (rom, nil)
                }
                active += 1
            }

            for await (completedRom, url) in group {
                active -= 1
                completed += 1
                if let savedURL = url {
                    var updated = completedRom
                    updated.boxArtPath = savedURL
                    await MainActor.run { library.updateROM(updated) }
                }
                // Throttle: 750ms + yield between requests to keep app responsive
                try? await Task.sleep(nanoseconds: 750_000_000)
                await Task.yield()

                onProgress(completed, total, completedRom.displayName)
                if let next = iter.next() {
                    group.addTask { @MainActor [weak self] in
                        if let s = self {
                            let url = await s.fetchBoxArtInner(for: next)
                            return (next, url)
                        }
                        return (next, nil)
                    }
                    active += 1
                }
            }
        }

        recordSyncDate()
    }
}

import Foundation
import Combine

@MainActor
class BoxArtService: ObservableObject {
    static let shared = BoxArtService()

    @Published var credentials: ScreenScraperCredentials? = nil

    private let cacheBase: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("TruchieEmu/BoxArt", isDirectory: true)
    }()

    private let defaults = UserDefaults.standard
    private let credKey = "screenscraper_credentials"

    private let keyThumbnailBaseURL = "thumbnail_server_url"
    private let keyThumbnailPriority = "thumbnail_priority_type"
    private let keyUseCRCMatching = "thumbnail_use_crc_matching"
    private let keyFallbackFilename = "thumbnail_fallback_filename"
    private let keyUseLibretroThumbnails = "thumbnail_use_libretro"
    private let keyHeadBeforeDownload = "thumbnail_use_head_check"

    /// Libretro CDN base URL (default: https://thumbnails.libretro.com/)
    var thumbnailServerURL: URL {
        get {
            if let s = defaults.string(forKey: keyThumbnailBaseURL), let u = URL(string: s), u.scheme != nil {
                return u
            }
            return LibretroThumbnailResolver.defaultBaseURL
        }
        set {
            defaults.set(newValue.absoluteString, forKey: keyThumbnailBaseURL)
        }
    }

    var thumbnailPriority: LibretroThumbnailPriority {
        get {
            let raw = defaults.string(forKey: keyThumbnailPriority) ?? LibretroThumbnailPriority.boxart.rawValue
            return LibretroThumbnailPriority(rawValue: raw) ?? .boxart
        }
        set {
            defaults.set(newValue.rawValue, forKey: keyThumbnailPriority)
        }
    }

    var useCRCMatchingForThumbnails: Bool {
        get { defaults.object(forKey: keyUseCRCMatching) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keyUseCRCMatching) }
    }

    var fallbackToFilenameForThumbnails: Bool {
        get { defaults.object(forKey: keyFallbackFilename) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keyFallbackFilename) }
    }

    var useLibretroThumbnails: Bool {
        get { defaults.object(forKey: keyUseLibretroThumbnails) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keyUseLibretroThumbnails) }
    }

    var useHeadBeforeThumbnailDownload: Bool {
        get { defaults.bool(forKey: keyHeadBeforeDownload) }
        set { defaults.set(newValue, forKey: keyHeadBeforeDownload) }
    }

    private lazy var thumbnailURLSession: URLSession = {
        let config = URLSessionConfiguration.default
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.httpAdditionalHeaders = [
            "User-Agent": "TruchieEmu/\(version) (TruchieEmu macOS)"
        ]
        return URLSession(configuration: config)
    }()

    init() {
        try? FileManager.default.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        loadCredentials()
    }

    // MARK: - Credentials

    struct ScreenScraperCredentials: Codable {
        var username: String
        var password: String
    }

    func saveCredentials(_ creds: ScreenScraperCredentials) {
        credentials = creds
        if let data = try? JSONEncoder().encode(creds) {
            defaults.set(data, forKey: credKey)
        }
    }

    private func loadCredentials() {
        guard let data = defaults.data(forKey: credKey),
              let creds = try? JSONDecoder().decode(ScreenScraperCredentials.self, from: data) else { return }
        credentials = creds
    }

    // MARK: - Art Fetching

    func fetchBoxArt(for rom: ROM) async -> URL? {
        if useLibretroThumbnails,
           let lib = await fetchBoxArtLibretro(for: rom) {
            return lib
        }
        guard let creds = credentials else { return nil }
        let systemID = rom.systemID ?? ""
        let ssSystemID = screenScraperSystemID(for: systemID)

        LoggerService.debug(category: "BoxArt", "Searching ScreenScraper for \(rom.name)...")

        let query = rom.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlStr = "https://www.screenscraper.fr/api2/jeuRecherche.php"
        urlStr += "?devid=truchiemu&devpassword=truchiemu_dev"
        urlStr += "&ssid=\(creds.username)&sspassword=\(creds.password)"
        urlStr += "&softname=TruchieEmu&output=json"
        urlStr += "&systemeid=\(ssSystemID)&romnom=\(query)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else {
            LoggerService.debug(category: "BoxArt", "ScreenScraper API request failed for \(rom.name)")
            return nil
        }

        guard let jeu = response["jeu"] as? [String: Any],
              let medias = jeu["medias"] as? [[String: Any]] else {
            LoggerService.debug(category: "BoxArt", "No results found on ScreenScraper for \(rom.name)")
            return nil
        }

        // Find box-2D image
        let box = medias.first(where: { ($0["type"] as? String) == "box-2D" })
        guard let urlString = box?["url"] as? String,
              let artURL = URL(string: urlString) else {
            LoggerService.debug(category: "BoxArt", "No box-2D art found on ScreenScraper for \(rom.name)")
            return nil
        }

        LoggerService.debug(category: "BoxArt", "Found ScreenScraper boxart URL for \(rom.name): \(urlString)")
        return await downloadAndCache(artURL: artURL, for: rom)
    }

    func searchBoxArt(query: String, systemID: String) async -> [BoxArtCandidate] {
        guard let creds = credentials else { return [] }
        let ssID = screenScraperSystemID(for: systemID)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlStr = "https://www.screenscraper.fr/api2/jeuRecherche.php"
        urlStr += "?devid=truchiemu&devpassword=truchiemu_dev"
        urlStr += "&ssid=\(creds.username)&sspassword=\(creds.password)"
        urlStr += "&softname=TruchieEmu&output=json"
        urlStr += "&systemeid=\(ssID)&romnom=\(q)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let jeux = response["jeux"] as? [[String: Any]] else { return [] }

        var candidates: [BoxArtCandidate] = []
        for jeu in jeux {
            let title = (jeu["nom"] as? String) ?? "Unknown"
            let medias = (jeu["medias"] as? [[String: Any]]) ?? []
            if let box = medias.first(where: { ($0["type"] as? String) == "box-2D" }),
               let urlString = box["url"] as? String,
               let artURL = URL(string: urlString) {
                candidates.append(BoxArtCandidate(title: title, thumbnailURL: artURL))
            }
        }
        return candidates
    }

    func downloadAndCache(artURL: URL, for rom: ROM, session: URLSession? = nil) async -> URL? {
        let sess = session ?? URLSession.shared
        let localURL = rom.boxArtLocalPath
        let folder = localURL.deletingLastPathComponent()
        
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }

        do {
            let (tmpURL, _) = try await sess.download(from: artURL)
            try FileManager.default.moveItem(at: tmpURL, to: localURL)
            await ImageCache.shared.removeImage(for: localURL)
            LoggerService.debug(category: "BoxArt", "Successfully cached boxart for \(rom.name) at \(localURL.lastPathComponent)")
            return localURL
        } catch {
            LoggerService.debug(category: "BoxArt", "Error downloading boxart for \(rom.name): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Libretro thumbnails CDN

    func fetchBoxArtLibretro(for rom: ROM) async -> URL? {
        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom),
              let folder = LibretroThumbnailResolver.libretroFolderName(forSystemID: sysID) else {
            return nil
        }

        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom,
            useCRC: useCRCMatchingForThumbnails,
            fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else {
            LoggerService.debug(category: "BoxArt", "Libretro thumbnails: could not resolve title for \(rom.name)")
            return nil
        }

        let localBoxArtDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let safeStem = LibretroThumbnailResolver.libretroFilesystemSafeName(gameTitle)
        for stem in [gameTitle, safeStem] where !stem.isEmpty {
            if let local = LibretroThumbnailResolver.resolveLocalThumbnail(named: stem, in: localBoxArtDir) {
                LoggerService.debug(category: "BoxArt", "Using local boxart \(local.lastPathComponent) for \(rom.name)")
                return local
            }
        }

        let candidates = LibretroThumbnailResolver.candidateURLs(
            base: thumbnailServerURL,
            systemFolder: folder,
            gameTitle: gameTitle,
            priority: thumbnailPriority
        )

        for url in candidates {
            if useHeadBeforeThumbnailDownload {
                guard await httpStatus(for: url, method: "HEAD", session: thumbnailURLSession) == 200 else {
                    continue
                }
            }
            if let saved = await downloadAndCache(artURL: url, for: rom, session: thumbnailURLSession) {
                return saved
            }
        }

        LoggerService.debug(category: "BoxArt", "Libretro thumbnails: no asset found for \(rom.name) (\(gameTitle))")
        return nil
    }

    private func httpStatus(for url: URL, method: String, session: URLSession) async -> Int {
        var req = URLRequest(url: url)
        req.httpMethod = method
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return -1
        }
        return http.statusCode
    }

    /// Batch download from libretro CDN (3–5 concurrent). Skips ROMs that already have cached art on disk.
    /// `onItemProgress` is invoked on the caller's executor after each finished download (`completed` 1...total).
    func batchDownloadBoxArtLibretro(
        for roms: [ROM],
        library: ROMLibrary,
        onItemProgress: ((Int, Int, String) -> Void)? = nil
    ) async {
        let missing = roms.filter { rom in
            !FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path)
        }
        guard !missing.isEmpty else {
            LoggerService.debug(category: "BoxArt", "No ROMs missing boxart cache, skipping Libretro batch.")
            return
        }

        let total = missing.count

        await MainActor.run {
            self.downloadQueueCount = total
            self.downloadedCount = 0
            self.isDownloadingBatch = true
        }

        let maxConcurrent = 4
        var completed = 0
        await withTaskGroup(of: (ROM, URL?).self) { group in
            var active = 0
            var iter = missing.makeIterator()

            while active < maxConcurrent, let rom = iter.next() {
                group.addTask {
                    let url = await self.fetchBoxArtLibretro(for: rom)
                    return (rom, url)
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
                await MainActor.run {
                    self.downloadedCount = completed
                    onItemProgress?(completed, total, label)
                }
                if let next = iter.next() {
                    group.addTask {
                        let url = await self.fetchBoxArtLibretro(for: next)
                        return (next, url)
                    }
                    active += 1
                }
            }
        }

        await MainActor.run { self.isDownloadingBatch = false }
    }

    // MARK: - Google Image Search Fallback
    
    @Published var isDownloadingBatch = false
    @Published var downloadedCount = 0
    @Published var downloadQueueCount = 0
    
    func batchDownloadBoxArtGoogle(for roms: [ROM], library: ROMLibrary) async {
        let missingRoms = roms.filter { $0.boxArtPath == nil }
        guard !missingRoms.isEmpty else { 
            LoggerService.info(category: "BoxArt", "No ROMs missing boxart, skipping batch download.")
            return 
        }
        
        LoggerService.info(category: "BoxArt", "Starting batch boxart download for \(missingRoms.count) ROMs...")
        
        await MainActor.run {
            self.downloadQueueCount = missingRoms.count
            self.downloadedCount = 0
            self.isDownloadingBatch = true
        }
        
        let maxConcurrent = 20
        await withTaskGroup(of: (ROM, URL?).self) { group in
            var activeTasks = 0
            var iterator = missingRoms.makeIterator()
            
            while activeTasks < maxConcurrent, let rom = iterator.next() {
                group.addTask {
                    let url = await self.fetchBoxArtGoogle(for: rom)
                    return (rom, url)
                }
                activeTasks += 1
            }
            
            for await result in group {
                activeTasks -= 1
                var (completedRom, url) = result
                
                if let savedURL = url {
                    completedRom.boxArtPath = savedURL
                    // Force an update to the reference type in the library to trigger redraw.
                    await MainActor.run { library.updateROM(completedRom) }
                }
                await MainActor.run { self.downloadedCount += 1 }
                
                if let nextRom = iterator.next() {
                    group.addTask {
                        let url = await self.fetchBoxArtGoogle(for: nextRom)
                        return (nextRom, url)
                    }
                    activeTasks += 1
                }
            }
        }
        
        await MainActor.run { self.isDownloadingBatch = false }
    }
    
    func fetchBoxArtGoogle(for rom: ROM) async -> URL? {
        let systemIdentifier = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom)?.uppercased() ?? ""
        let cleanName = rom.name.replacingOccurrences(of: "_", with: " ")
        let query = "\(cleanName) \(systemIdentifier) BoxArt"
        LoggerService.debug(category: "BoxArt", "Searching Google for \(rom.name): \"\(query)\"")
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)&num=1&udm=2&source=lnt&tbs=isz:m") else {
            LoggerService.debug(category: "BoxArt", "Failed to encode query for \(rom.name)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        var attempts = 0
        let maxAttempts = 3
        var html: String? = nil
        
        while attempts < maxAttempts {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let decodedHtml = String(data: data, encoding: .utf8) {
                html = decodedHtml
                break
            }
            attempts += 1
            if attempts < maxAttempts {
                let delay = UInt64(pow(2.0, Double(attempts)) * 1_000_000_000)
                LoggerService.debug(category: "BoxArt", "Google search throttled or failed for \(rom.name), retrying in \(Int(pow(2.0, Double(attempts))))s...")
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        
        guard let html = html else { 
            LoggerService.debug(category: "BoxArt", "Failed to fetch Google Search results for \(rom.name) after \(maxAttempts) attempts.")
            return nil 
        }
        
        // Find first image URL - try multiple patterns
        let patterns = [
            "https://encrypted-tbn0\\.gstatic\\.com/images[^\"]+",
            "https://www\\.google\\.com/imgres\\?imgurl=([^&]+)",
            "\"(https://[^\"]+\\.(jpg|png|jpeg))\""
        ]
        
        var imageUrlString: String? = nil
        
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               let range = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: html) {
                imageUrlString = String(html[range])
                break
            }
        }
        
        guard var finalUrl = imageUrlString else { 
            LoggerService.debug(category: "BoxArt", "No boxart image URL found in Google results for \(rom.name)")
            return nil 
        }
        
        finalUrl = finalUrl.replacingOccurrences(of: "\\u003d", with: "=")
        finalUrl = finalUrl.replacingOccurrences(of: "\\u0026", with: "&")
        finalUrl = finalUrl.removingPercentEncoding ?? finalUrl
        
        LoggerService.debug(category: "BoxArt", "Found image URL for \(rom.name)")
        
        guard let artURL = URL(string: finalUrl) else { 
            LoggerService.debug(category: "BoxArt", "Malformed image URL for \(rom.name): \(finalUrl)")
            return nil 
        }
        
        return await downloadAndCache(artURL: artURL, for: rom)
    }
    
    func fetchBoxArtCandidates(query: String, systemID: String) async -> [URL] {
        var candidates: [URL] = []
        let systemIdentifier = systemID.uppercased()
        let cleanQuery = query.replacingOccurrences(of: "_", with: " ")
        let fullQuery = "\(cleanQuery) \(systemIdentifier) BoxArt"
        guard let encodedQuery = fullQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }

        // Fetch Google (2 images)
        if let gUrl = URL(string: "https://www.google.com/search?q=\(encodedQuery)&num=5&udm=2&source=lnt&tbs=isz:m") {
            var request = URLRequest(url: gUrl)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let html = String(data: data, encoding: .utf8),
               let regex = try? NSRegularExpression(pattern: "https://encrypted-tbn0\\.gstatic\\.com/images[^\"]+", options: []) {
                let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
                for match in matches.prefix(2) {
                    if let range = Range(match.range, in: html) {
                        let imgStr = String(html[range]).replacingOccurrences(of: "\\u003d", with: "=").replacingOccurrences(of: "\\u0026", with: "&")
                        if let u = URL(string: imgStr) { candidates.append(u) }
                    }
                }
            }
        }
        
        // Fetch DDG (2 images)
        if let ddgReqUrl = URL(string: "https://duckduckgo.com/?q=\(encodedQuery)") {
            var req = URLRequest(url: ddgReqUrl)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let html = String(data: data, encoding: .utf8),
               let regex = try? NSRegularExpression(pattern: "vqd=([a-zA-Z0-9-]+)", options: []),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               let range = Range(match.range(at: 1), in: html) {
                let vqd = String(html[range])
                if let api = URL(string: "https://duckduckgo.com/i.js?l=us-en&o=json&q=\(encodedQuery)&vqd=\(vqd)") {
                    var apiReq = URLRequest(url: api)
                    apiReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
                    if let (apiData, _) = try? await URLSession.shared.data(for: apiReq),
                       let json = try? JSONSerialization.jsonObject(with: apiData) as? [String: Any],
                       let results = json["results"] as? [[String: Any]] {
                        for item in results.prefix(2) {
                            if let img = item["image"] as? String, let u = URL(string: img) {
                                candidates.append(u)
                            }
                        }
                    }
                }
            }
        }
        
        return candidates
    }

    // MARK: - ScreenScraper System ID mapping

    private func screenScraperSystemID(for id: String) -> Int {
        let map: [String: Int] = [
            "nes": 3, "snes": 4, "n64": 14, "gba": 12, "gb": 9, "gbc": 10, "nds": 15,
            "genesis": 1, "sms": 2, "gamegear": 21, "saturn": 22, "dreamcast": 23,
            "psx": 57, "ps2": 58, "psp": 61,
            "mame": 75, "fba": 75,
            "atari2600": 26, "atari5200": 66, "atari7800": 41, "lynx": 28,
            "ngp": 25, "pce": 31, "pcfx": 72
        ]
        return map[id] ?? 0
    }
}

struct BoxArtCandidate: Identifiable {
    var id = UUID()
    var title: String
    var thumbnailURL: URL
}

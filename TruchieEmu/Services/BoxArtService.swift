import Foundation
import Combine
import SwiftData

@MainActor
class BoxArtService: ObservableObject {
    static let shared = BoxArtService()

    @Published var credentials: ScreenScraperCredentials? = nil
    
    /// Updated whenever box art is fetched or changed — observe this to trigger UI refresh
    @Published var boxArtUpdated: UUID = UUID()

    private let cacheBase: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("TruchieEmu/BoxArt", isDirectory: true)
    }()
    private let credKey = "screenscraper_credentials"

    private var cacheRepo: ResourceCacheRepository {
        ResourceCacheRepository(context: SwiftDataContainer.shared.mainContext)
    }

    private let keyThumbnailBaseURL = "thumbnail_server_url"
    private let keyThumbnailPriority = "thumbnail_priority_type"
    private let keyUseCRCMatching = "thumbnail_use_crc_matching"
    private let keyFallbackFilename = "thumbnail_fallback_filename"
    private let keyUseLibretroThumbnails = "thumbnail_use_libretro"
    private let keyHeadBeforeDownload = "thumbnail_use_head_check"

    /// Libretro CDN base URL (default: https://thumbnails.libretro.com/)
    var thumbnailServerURL: URL {
        get {
            if let s = AppSettings.get(keyThumbnailBaseURL, type: String.self), let u = URL(string: s), u.scheme != nil {
                return u
            }
            return LibretroThumbnailResolver.defaultBaseURL
        }
        set {
            AppSettings.set(keyThumbnailBaseURL, value: newValue.absoluteString)
        }
    }

    var thumbnailPriority: LibretroThumbnailPriority {
        get {
            let raw = AppSettings.get(keyThumbnailPriority, type: String.self) ?? LibretroThumbnailPriority.boxart.rawValue
            return LibretroThumbnailPriority(rawValue: raw) ?? .boxart
        }
        set {
            AppSettings.set(keyThumbnailPriority, value: newValue.rawValue)
        }
    }

    var useCRCMatchingForThumbnails: Bool {
        get { AppSettings.getBool(keyUseCRCMatching, defaultValue: true) }
        set { AppSettings.setBool(keyUseCRCMatching, value: newValue) }
    }

    var fallbackToFilenameForThumbnails: Bool {
        get { AppSettings.getBool(keyFallbackFilename, defaultValue: true) }
        set { AppSettings.setBool(keyFallbackFilename, value: newValue) }
    }

    var useLibretroThumbnails: Bool {
        get { AppSettings.getBool(keyUseLibretroThumbnails, defaultValue: true) }
        set { AppSettings.setBool(keyUseLibretroThumbnails, value: newValue) }
    }

    var useHeadBeforeThumbnailDownload: Bool {
        get { AppSettings.getBool(keyHeadBeforeDownload, defaultValue: true) }
        set { AppSettings.setBool(keyHeadBeforeDownload, value: newValue) }
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
            AppSettings.setData(credKey, value: data)
        }
    }

    private func loadCredentials() {
        guard let data = AppSettings.getData(credKey),
              let creds = try? JSONDecoder().decode(ScreenScraperCredentials.self, from: data) else { return }
        credentials = creds
    }

    // MARK: - Local BoxArt Resolution

    /// Lazily resolves local boxart for a single ROM on-demand.
    @MainActor
    func resolveLocalBoxArtIfNeeded(for rom: ROM, library: ROMLibrary) -> URL? {
        if rom.hasBoxArt { return rom.boxArtLocalPath }

        if let localURL = resolveLocalBoxArt(for: rom) {
            var updated = rom
            updated.hasBoxArt = true
            library.updateROM(updated, persist: false)
            LoggerService.info(category: "BoxArt", "✅ Local boxart found: \(localURL.lastPathComponent) for '\(rom.displayName)'")
            return localURL
        }
        return nil
    }

    /// Scans the local /boxart subfolder for an existing image matching this ROM.
    /// Returns the local file URL if found, nil otherwise. Does NOT download from CDN.
    nonisolated func resolveLocalBoxArt(for rom: ROM) -> URL? {
        let localBoxArtDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let imageExtensions = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]
        
        var candidateStems: [String] = []
        let romFileName = rom.path.lastPathComponent
        candidateStems.append("\(romFileName)_boxart")
        
        let romFileStem = rom.path.deletingPathExtension().lastPathComponent
        candidateStems.append("\(romFileStem)_boxart")
        
        if rom.name != romFileStem && !rom.name.isEmpty {
            candidateStems.append("\(rom.name)_boxart")
        }
        
        let sanitized = romFileStem
            .replacingOccurrences(of: " \\(.*?\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: " \\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized != romFileStem && !sanitized.isEmpty {
            candidateStems.append("\(sanitized)_boxart")
        }
        
        var seen = Set<String>()
        let uniqueStems = candidateStems.filter { stem in
            let normalized = stem.lowercased()
            if seen.contains(normalized) { return false }
            seen.insert(normalized)
            return true
        }
        
        for stem in uniqueStems {
            for ext in imageExtensions {
                let candidate = localBoxArtDir.appendingPathComponent("\(stem).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path), isValidImageFile(at: candidate) {
                    return candidate
                }
            }
        }
        
        // Fallback: check the app's own naming convention
        if FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path), isValidImageFile(at: rom.boxArtLocalPath) {
            return rom.boxArtLocalPath
        }
        
        return nil
    }

    nonisolated func resolveLocalBoxArtBatch(for roms: [ROM]) -> [ROM] {
        var found: [ROM] = []
        for rom in roms {
            if resolveLocalBoxArt(for: rom) != nil {
                var updated = rom
                updated.hasBoxArt = true
                found.append(updated)
            }
        }
        return found
    }

    func resolveAllLocalBoxArtAndPersist(library: ROMLibrary) {
        let romsWithoutArt = library.roms.filter { !$0.hasBoxArt }
        guard !romsWithoutArt.isEmpty else { return }

        let found = resolveLocalBoxArtBatch(for: romsWithoutArt)
        if !found.isEmpty {
            let modifiedIDs = found.map { $0.id }
            for rom in found { library.updateROM(rom, persist: false) }
            library.saveROMsToDatabase(only: modifiedIDs)
            signalBoxArtUpdated(for: UUID())
        }
    }

    // MARK: - Art Fetching

    func fetchBoxArt(for rom: ROM) async -> URL? {
        // === OPTIMIZATION 1: Instant Local Check ===
        // Before hitting the network or identifying the ROM, check if we already have it locally!
        if let localArt = resolveLocalBoxArt(for: rom) {
            LoggerService.info(category: "BoxArt", "Fast Path: Found local boxart for '\(rom.name)' at \(localArt.lastPathComponent)")
            return localArt
        }

        LoggerService.info(category: "BoxArt", "Starting boxart search for '\(rom.name)'")

        // 1. Libretro Thumbnails CDN (primary)
        if useLibretroThumbnails {
            if let lib = await fetchBoxArtLibretro(for: rom) {
                return lib
            }
        }

        // 2. ScreenScraper (if credentials configured)
        if let creds = credentials {
            let ssSystemID = screenScraperSystemID(for: rom.systemID ?? "")
            let query = rom.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            var urlStr = "https://www.screenscraper.fr/api2/jeuRecherche.php"
            urlStr += "?devid=truchiemu&devpassword=truchiemu_dev"
            urlStr += "&ssid=\(creds.username)&sspassword=***"
            urlStr += "&softname=TruchieEmu&output=json"
            urlStr += "&systemeid=\(ssSystemID)&romnom=\(query)"

            if let url = URL(string: urlStr),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? [String: Any],
               let jeu = response["jeu"] as? [String: Any],
               let medias = jeu["medias"] as? [[String: Any]] {
                let box = medias.first(where: { ($0["type"] as? String) == "box-2D" })
                if let urlString = box?["url"] as? String, let artURL = URL(string: urlString) {
                    return await downloadAndCache(artURL: artURL, for: rom)
                }
            }
        }

        // 3. LaunchBox GamesDB (third-party fallback)
        if let launchBoxArt = await LaunchBoxGamesDBService.shared.fetchBoxArt(for: rom) {
            return launchBoxArt
        }

        return nil
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
            let (tmpURL, response) = try await sess.download(from: artURL)
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else { return nil }
                let validImageTypes = ["image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp", "image/bmp"]
                guard validImageTypes.contains((httpResponse.mimeType ?? "").lowercased()) else { return nil }
            }
            try FileManager.default.moveItem(at: tmpURL, to: localURL)
            await ImageCache.shared.removeImage(for: localURL)
            return localURL
        } catch {
            return nil
        }
    }

    // MARK: - Libretro thumbnails CDN

    func fetchBoxArtLibretro(for rom: ROM) async -> URL? {
        let romPathKey = rom.path.deletingPathExtension().lastPathComponent
        let source = "libretro"

        // === OPTIMIZATION 2: Fast Cache Hit ===
        // Skip heavy CRC hashing completely if we already downloaded this boxart successfully.
        if let cached = cacheRepo.getBoxArtResolution(romPathKey: romPathKey, source: source),
           cached.isValid,
           FileManager.default.fileExists(atPath: cached.resolvedURL) {
            LoggerService.info(category: "BoxArt", "Libretro: Fast cache hit for '\(rom.name)'. Skipping CRC.")
            return URL(fileURLWithPath: cached.resolvedURL)
        }

        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom),
              let folder = LibretroThumbnailResolver.libretroFolderName(forSystemID: sysID) else { return nil }

        // This is the heavy CRC calculation
        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom,
            useCRC: useCRCMatchingForThumbnails,
            fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else { return nil }

        let knownVariants: [String]
        if useCRCMatchingForThumbnails, let romSystemID = rom.systemID {
            knownVariants = await LibretroDatabaseLibrary.shared.findVariantEntries(for: gameTitle, systemID: romSystemID)
        } else {
            knownVariants = []
        }

        let localBoxArtDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let safeStem = LibretroThumbnailResolver.libretroFilesystemSafeName(gameTitle)
        
        for stem in [gameTitle, safeStem] where !stem.isEmpty {
            if let local = LibretroThumbnailResolver.resolveLocalThumbnail(named: stem, in: localBoxArtDir) {
                if isValidImageFile(at: local) { return local } 
                else { try? FileManager.default.removeItem(at: local) }
            }
        }

        let candidates = LibretroThumbnailResolver.candidateURLs(
            base: thumbnailServerURL, systemFolder: folder, gameTitle: gameTitle,
            knownVariants: knownVariants, priority: thumbnailPriority
        )

        for url in candidates {
            if let cached = cacheRepo.getBoxArtResolution(romPathKey: romPathKey, source: source) {
                if cached.resolvedURL == url.absoluteString && !cached.isValid && cached.httpStatus != 0 { continue }
            }
            
            let exists = await LibretroThumbnailManifestService.shared.existsInManifest(url: url, folderName: folder)
            guard exists else { continue }
            
            var headStatusCode = -1
            if useHeadBeforeThumbnailDownload {
                headStatusCode = await httpStatus(for: url, method: "HEAD", session: thumbnailURLSession)
                guard headStatusCode == 200 else {
                    cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: headStatusCode, isValid: false)
                    continue
                }
            }
            
            if let saved = await downloadAndCache(artURL: url, for: rom, session: thumbnailURLSession) {
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return saved
            } else {
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: headStatusCode == -1 ? 0 : headStatusCode, isValid: false)
            }
        }

        return nil
    }

    private func httpStatus(for url: URL, method: String, session: URLSession) async -> Int {
        var req = URLRequest(url: url)
        req.httpMethod = method
        guard let (_, resp) = try? await session.data(for: req), let http = resp as? HTTPURLResponse else { return -1 }
        return http.statusCode
    }

    nonisolated private func isValidImageFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        if let firstBytes = String(data: data.prefix(512), encoding: .utf8)?.lowercased(),
           firstBytes.contains("<!doctype") || firstBytes.contains("<html") || firstBytes.contains("<!html") { return false }
        if data.count < 2 { return false }
        if data.starts(with: [0x89, 0x50]) { return true }
        if data.count >= 3 && data.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if data.count >= 4 && data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        if data.starts(with: [0x42, 0x4D]) { return true }
        if data.count >= 12 && data.starts(with: [0x52, 0x49, 0x46, 0x46]) && data[8...11].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return true }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "webp"]
        return imageExtensions.contains(url.pathExtension.lowercased()) && data.count > 100
    }

    func isBoxArtBroken(rom: ROM) -> Bool {
        let path = rom.boxArtLocalPath
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        return !isValidImageFile(at: path)
    }

    func findBrokenBoxArts(in roms: [ROM]) -> [ROM] { roms.filter { isBoxArtBroken(rom: $0) } }

    func cleanBrokenBoxArts(for roms: [ROM]) async -> [ROM] {
        var cleaned: [ROM] = []
        for rom in roms {
            let path = rom.boxArtLocalPath
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            if !isValidImageFile(at: path) {
                try? FileManager.default.removeItem(at: path)
                cleaned.append(rom)
            }
        }
        return cleaned
    }

    func romsNeedingBoxArt(in roms: [ROM]) -> [ROM] { roms.filter { !$0.hasBoxArt } }

    func batchDownloadBoxArtLibretro(for roms: [ROM], library: ROMLibrary, onItemProgress: ((Int, Int, String) -> Void)? = nil) async {
        let broken = findBrokenBoxArts(in: roms)
        if !broken.isEmpty { _ = await cleanBrokenBoxArts(for: broken) }

        let needsArt = romsNeedingBoxArt(in: roms)
        guard !needsArt.isEmpty else { return }

        let total = needsArt.count
        await MainActor.run { self.downloadQueueCount = total; self.downloadedCount = 0; self.isDownloadingBatch = true }

        let maxConcurrent = 1
        var completed = 0
        var modifiedIDs: [UUID] = []
        
        await withTaskGroup(of: (ROM, URL?).self) { group in
            var active = 0
            var iter = needsArt.makeIterator()

            while active < maxConcurrent, let rom = iter.next() {
                group.addTask {
                    // Fast local check inside batch queue too!
                    if let local = self.resolveLocalBoxArt(for: rom) { return (rom, local) }
                    return (rom, await self.fetchBoxArtLibretro(for: rom))
                }
                active += 1
            }

            for await result in group {
                active -= 1
                var (completedRom, url) = result
                if url != nil {
                    completedRom.hasBoxArt = true
                    modifiedIDs.append(completedRom.id)
                    await MainActor.run { library.updateROM(completedRom, persist: false) }
                }
                completed += 1
                let label = "\(completedRom.displayName).png"
                await MainActor.run { self.downloadedCount = completed; onItemProgress?(completed, total, label) }
                
                if let next = iter.next() {
                    group.addTask {
                        if let local = self.resolveLocalBoxArt(for: next) { return (next, local) }
                        return (next, await self.fetchBoxArtLibretro(for: next))
                    }
                    active += 1
                }
                try? await Task.sleep(nanoseconds: 10_000_000) // Small yield
            }
        }

        await MainActor.run { library.saveROMsToDatabase(only: modifiedIDs); self.isDownloadingBatch = false }
        signalBoxArtUpdated(for: UUID())
    }

    // MARK: - Google Image Search Fallback
    
    @Published var isDownloadingBatch = false
    @Published var downloadedCount = 0
    @Published var downloadQueueCount = 0
    var downloadProgress: Double {
        guard downloadQueueCount > 0 else { return 0 }
        return Double(downloadedCount) / Double(downloadQueueCount)
    }
    
    func batchDownloadBoxArtGoogle(for roms: [ROM], library: ROMLibrary) async {
        let broken = findBrokenBoxArts(in: roms)
        if !broken.isEmpty { _ = await cleanBrokenBoxArts(for: broken) }

        let needsArt = romsNeedingBoxArt(in: roms)
        guard !needsArt.isEmpty else { return }

        await MainActor.run { self.downloadQueueCount = needsArt.count; self.downloadedCount = 0; self.isDownloadingBatch = true }

        let maxConcurrent = 2
        var modifiedIDs: [UUID] = []
        
        await withTaskGroup(of: (ROM, URL?).self) { group in
            var activeTasks = 0
            var iterator = needsArt.makeIterator()
            
            while activeTasks < maxConcurrent, let rom = iterator.next() {
                group.addTask {
                    if let local = self.resolveLocalBoxArt(for: rom) { return (rom, local) }
                    return (rom, await self.fetchBoxArtGoogle(for: rom))
                }
                activeTasks += 1
            }
            
            for await result in group {
                activeTasks -= 1
                var (completedRom, url) = result
                if url != nil {
                    completedRom.hasBoxArt = true
                    modifiedIDs.append(completedRom.id)
                    await MainActor.run { library.updateROM(completedRom, persist: false) }
                }
                await MainActor.run { self.downloadedCount += 1 }
                
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Throttle Google
                
                if let nextRom = iterator.next() {
                    group.addTask {
                        if let local = self.resolveLocalBoxArt(for: nextRom) { return (nextRom, local) }
                        return (nextRom, await self.fetchBoxArtGoogle(for: nextRom))
                    }
                    activeTasks += 1
                }
            }
        }
        
        await MainActor.run { library.saveROMsToDatabase(only: modifiedIDs); self.isDownloadingBatch = false }
    }
    
    func fetchBoxArtGoogle(for rom: ROM) async -> URL? {
        let systemIdentifier = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom)?.uppercased() ?? ""
        let cleanName = rom.name.replacingOccurrences(of: "_", with: " ")
        let query = "\(cleanName) \(systemIdentifier) BoxArt"
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)&num=1&udm=2&source=lnt&tbs=isz:m") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        var attempts = 0
        let maxAttempts = 3
        var html: String? = nil
        
        while attempts < maxAttempts {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let decodedHtml = String(data: data, encoding: .utf8) {
                html = decodedHtml; break
            }
            attempts += 1
            if attempts < maxAttempts { try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempts)) * 1_000_000_000)) }
        }
        
        guard let html = html else { return nil }
        
        let patterns = [ "https://encrypted-tbn0\\.gstatic\\.com/images[^\"]+", "https://www\\.google\\.com/imgres\\?imgurl=([^&]+)", "\"(https://[^\"]+\\.(jpg|png|jpeg))\"" ]
        var imageUrlString: String? = nil
        
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               let range = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: html) {
                imageUrlString = String(html[range]); break
            }
        }
        
        guard var finalUrl = imageUrlString else { return nil }
        finalUrl = finalUrl.replacingOccurrences(of: "\\u003d", with: "=").replacingOccurrences(of: "\\u0026", with: "&").removingPercentEncoding ?? finalUrl
        
        guard let artURL = URL(string: finalUrl) else { return nil }
        return await downloadAndCache(artURL: artURL, for: rom)
    }

    func signalBoxArtUpdated(for romID: UUID, boxArtURL: URL? = nil) {
        if let url = boxArtURL {
            Task { await ImageCache.shared.removeImage(for: url); await ImageCache.shared.removeThumbnail(for: url) }
        }
        boxArtUpdated = UUID()
    }

    private func screenScraperSystemID(for id: String) -> Int {
        let map: [String: Int] = [
            "nes": 3, "snes": 4, "n64": 14, "gba": 12, "gb": 9, "gbc": 10, "nds": 15,
            "genesis": 1, "sms": 2, "gamegear": 21, "saturn": 22, "dreamcast": 23,
            "psx": 57, "ps2": 58, "psp": 61, "mame": 75, "fba": 75,
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
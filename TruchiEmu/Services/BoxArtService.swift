import Foundation
import Combine
import SwiftData

@MainActor
class BoxArtService: ObservableObject {
    static let shared = BoxArtService()

    @Published var credentials: ScreenScraperCredentials? = nil
    
    // Updated whenever box art is fetched or changed — observe this to trigger UI refresh
    @Published var boxArtUpdated: UUID = UUID()

    private let cacheBase: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("TruchiEmu/BoxArt", isDirectory: true)
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

    // Libretro CDN base URL (default: https://thumbnails.libretro.com/)
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
            "User-Agent": "TruchiEmu/\(version) (TruchiEmu macOS)"
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

    // Lazily resolves local boxart for a single ROM on-demand.
    @MainActor
    func resolveLocalBoxArtIfNeeded(for rom: ROM, library: ROMLibrary) -> URL? {
        if rom.hasBoxArt, FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path) {
            return rom.boxArtLocalPath
        }

        if let localURL = resolveLocalBoxArt(for: rom) {
            var updated = rom
            updated.hasBoxArt = true
            library.updateROM(updated, persist: false)
            LoggerService.info(category: "BoxArt", "✅ Local boxart found: \(localURL.lastPathComponent) for '\(rom.displayName)'")
            return localURL
        }
        return nil
    }

    // Scans the local /boxart subfolder for an existing image matching this ROM.
    // Returns the local file URL if found, nil otherwise. Does NOT download from CDN.
    // Results are memoized per-ROM until invalidateResolvedBoxArtCache is called —
    // this avoids repeating a directory listing every time a card scrolls into view.
    nonisolated func resolveLocalBoxArt(for rom: ROM) -> URL? {
        // Per-ROM cache: stops art-less cards from re-listing their /boxart dir
        // on every scroll appear. NSLock-guarded because resolveLocalBoxArt can
        // be called from non-MainActor contexts (grid prefetch Tasks).
        if let cached = ResultCache.shared.get(rom.id) {
            return cached
        }
        let result = self.resolveLocalBoxArtUncached(for: rom)
        ResultCache.shared.set(rom.id, result)
        return result
    }

    /// Clear any cached resolveLocalBoxArt() result for a given rom. Call after
    /// boxart is downloaded/deleted for a rom so subsequent resolves re-scan.
    @MainActor
    func invalidateResolvedBoxArtCache(for romID: UUID) {
        ResultCache.shared.remove(romID)
    }

    private nonisolated func resolveLocalBoxArtUncached(for rom: ROM) -> URL? {
        let localBoxArtDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "bmp"]

        // Listing the directory once (1 syscall) is dramatically cheaper than N×1 syscalls
        // where N is the number of candidate (stem, extension) pairs. For a single
        // ROM, that's typically 30+ FileManager.fileExists() calls; across 30 visible
        // cards that's 900+ sequential stat calls. One directory read replaces all of it.
        let dirContents: [URL]
        do {
            dirContents = try FileManager.default.contentsOfDirectory(
                at: localBoxArtDir,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            // Fall through: dir doesn't exist (very common — most ROMs have no /boxart).
            dirContents = []
        }

        let dirNamesLowercase: Set<String> = Set(dirContents.map { $0.lastPathComponent.lowercased() })

        var candidateStems: [String] = []
        if let inner = rom.innerROMPath {
            let innerStem = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
            candidateStems.append("\(innerStem)_boxart")
            if rom.name != innerStem && !rom.name.isEmpty {
                candidateStems.append("\(rom.name)_boxart")
            }
        } else {
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
        }

        var seen = Set<String>()
        let uniqueStems = candidateStems.filter { stem in
            let normalized = stem.lowercased()
            if seen.contains(normalized) { return false }
            seen.insert(normalized)
            return true
        }

        // Match: for each stem, find any file in the directory whose name matches
        // "{stem}.{png|jpg|jpeg|webp|gif|bmp}" (case-insensitive). Validate magic bytes
        // on the first hit only (rather than one read per candidate).
        for stem in uniqueStems {
            for ext in imageExtensions {
                let targetLower = "\(stem).\(ext)".lowercased()
                if dirNamesLowercase.contains(targetLower),
                   let match = dirContents.first(where: { $0.lastPathComponent.lowercased() == targetLower }),
                   isValidImageFile(at: match) {
                    return match
                }
            }
        }

        // Fallback: the app's own naming convention (`rom.boxArtLocalPath`).
        // That path may live outside the /boxart directory (e.g. a flat sidecar
        // image next to the ROM), so check it explicitly with one stat + validate.
        let fallback = rom.boxArtLocalPath
        if FileManager.default.fileExists(atPath: fallback.path), isValidImageFile(at: fallback) {
            return fallback
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
            let regionSuffix = SystemPreferences.shared.systemLanguage.regionSuffix
            let (lib, _) = await fetchBoxArtLibretro(for: rom, regionSuffix: regionSuffix)
            if let lib = lib {
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
            urlStr += "&softname=TruchiEmu&output=json"
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

        // 3. LaunchBox GamesDB (CDN-backed via Metadata.xml)
        if LaunchBoxGamesDBService.shared.isEnabled,
           let platformName = LaunchBoxPlatformMapper.launchBoxPlatformName(for: rom.systemID ?? ""),
           let match = await LaunchBoxMetadataService.shared.bestMatch(
            for: rom.displayName,
            platformName: platformName
           ),
           let imageRef = LaunchBoxMetadataService.shared.boxArtRef(for: match) {
            let cdnURL = LaunchBoxMetadataService.cdnURL(for: imageRef)
            return await downloadAndCache(artURL: cdnURL, for: rom)
        }

        return nil
    }

    func downloadAndCache(artURL: URL, for rom: ROM, session: URLSession? = nil) async -> URL? {
        await downloadAndCache(artURL: artURL, for: rom, to: rom.boxArtLocalPath, session: session)
    }

    // Same as downloadAndCache(artURL:for:) but saves to a custom destination URL.
    // Used for title screens ({stem}_title.png) and in-game screenshots ({stem}_snap_N.png)
    // which share the boxart directory but use different filenames.
    func downloadAndCache(artURL: URL, for rom: ROM, to localURL: URL, session: URLSession? = nil) async -> URL? {
        let sess = session ?? URLSession.shared
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
            if localURL == rom.boxArtLocalPath {
                BoxArtThumbnailService.deleteThumbnails(for: localURL)
                await ImageCache.shared.removeImage(for: localURL)
                await ImageCache.shared.removeThumbnail(for: localURL)
                BoxArtThumbnailService.generateThumbnailsSynchronously(forOriginal: localURL)
            } else {
                await ImageCache.shared.removeImage(for: localURL)
            }
            return localURL
        } catch {
            return nil
        }
    }

    // MARK: - Libretro thumbnails CDN

    // Returns (localFileURL, resolvedRegionTag). The region tag is extracted from the CDN URL
    // (e.g., "(USA)"), NOT from the local file path. Returns (nil, nil) on failure.
    func fetchBoxArtLibretro(for rom: ROM, regionSuffix: String? = nil) async -> (URL?, String?) {
        let romPathKey: String
        if let inner = rom.innerROMPath {
            romPathKey = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romPathKey = rom.path.deletingPathExtension().lastPathComponent
        }
        let source = "libretro"

        // === OPTIMIZATION 2: Fast Cache Hit ===
        // Skip heavy CRC hashing completely if we already downloaded this boxart successfully
        // AND the region matches. Bypass cache when the region has changed so we re-download.
        let regionMatches = rom.boxArtRequestedRegion == regionSuffix
        if regionMatches,
           let cached = cacheRepo.getBoxArtResolution(romPathKey: romPathKey, source: source),
           cached.isValid,
           FileManager.default.fileExists(atPath: cached.resolvedURL) {
            LoggerService.info(category: "BoxArt", "Libretro: Fast cache hit for '\(rom.name)'. Skipping CRC.")
            return (URL(fileURLWithPath: cached.resolvedURL), nil)
        }

        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom) else { return (nil, nil) }

        // Resolve working folders (probes once, then cached)
        let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
        guard !folders.isEmpty else { return (nil, nil) }

        // This is the heavy CRC calculation
        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom,
            useCRC: useCRCMatchingForThumbnails,
            fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else { return (nil, nil) }

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
                if isValidImageFile(at: local) { return (local, nil) }
                else { try? FileManager.default.removeItem(at: local) }
            }
        }

        // Step 1: Try manifest-based region-preference matching first.
        // This finds ALL files in the manifest matching the game title, then picks
        // the one with the best region match (e.g. "(Japan)" over "(USA)").
        let regionPreference = SystemPreferences.shared.systemLanguage.noIntroRegionPreference
        let manifestMatches = await LibretroThumbnailResolver.bestMatchingURLs(
            for: gameTitle,
            systemFolders: folders,
            base: thumbnailServerURL,
            priority: thumbnailPriority,
            regionPreference: regionPreference
        )

        for (_, url, regionTag) in manifestMatches {
            if let cached = cacheRepo.getBoxArtResolution(romPathKey: romPathKey, source: source) {
                if cached.resolvedURL == url.absoluteString && !cached.isValid && cached.httpStatus != 0 { continue }
            }

            // Skip HEAD check for manifest-confirmed URLs — the manifest is authoritative,
            // so we avoid an extra CDN hit. Go straight to download.
            if let saved = await downloadAndCache(artURL: url, for: rom, session: thumbnailURLSession) {
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return (saved, regionTag)
            } else {
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: 0, isValid: false)
            }
        }

        // Step 2: Fallback to candidate URL generation when manifest is unavailable
        // or had no matches. This covers edge cases and systems without manifest data.
        var allCandidates: [(folder: String, url: URL)] = []
        for folder in folders {
            let urls = LibretroThumbnailResolver.candidateURLs(
                base: thumbnailServerURL, systemFolder: folder, gameTitle: gameTitle,
                knownVariants: knownVariants, priority: thumbnailPriority,
                regionSuffix: regionSuffix
            )
            for url in urls {
                allCandidates.append((folder, url))
            }
        }

        for (folder, url) in allCandidates {
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
                let resolvedRegionTag = LibretroThumbnailResolver.regionTag(from: url)
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return (saved, resolvedRegionTag)
            } else {
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: headStatusCode == -1 ? 0 : headStatusCode, isValid: false)
            }
        }

        return (nil, nil)
    }

    // MARK: - Named_Titles / Named_Snaps (title screens & in-game screenshots)

    // Generic libretro CDN fetch for a single Named_* type folder that saves to a
    // caller-supplied local destination. Returns the local URL on success.
    private func fetchThumbnailLibretro(
        for rom: ROM,
        typeFolder: String,
        regionSuffix: String?,
        localDestination: URL,
        localStem: String
    ) async -> (URL?, String?) {
        let source = "libretro_\(typeFolder)"
        let romPathKey = localStem

        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom) else { return (nil, nil) }

        let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
        guard !folders.isEmpty else { return (nil, nil) }

        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom,
            useCRC: useCRCMatchingForThumbnails,
            fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else { return (nil, nil) }

        let regionPreference = SystemPreferences.shared.systemLanguage.noIntroRegionPreference
        let manifestMatches = await LibretroThumbnailResolver.bestMatchingURLs(
            forType: typeFolder,
            gameTitle: gameTitle,
            systemFolders: folders,
            base: thumbnailServerURL,
            regionPreference: regionPreference
        )

        for (_, url, regionTag) in manifestMatches {
            if let saved = await downloadAndCache(artURL: url, for: rom, to: localDestination, session: thumbnailURLSession) {
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return (saved, regionTag)
            }
        }
        return (nil, nil)
    }

    // Downloads the libretro "Named_Titles" title screen to {stem}_title.png in the boxart dir.
    func downloadTitleScreen(for rom: ROM) async -> URL? {
        let romPathKey: String
        if let inner = rom.innerROMPath {
            romPathKey = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romPathKey = rom.path.deletingPathExtension().lastPathComponent
        }
        let boxartDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let stem = "\(romPathKey)_title"
        let localURL = boxartDir.appendingPathComponent("\(stem).png")
        let (saved, _) = await fetchThumbnailLibretro(
            for: rom, typeFolder: "Named_Titles", regionSuffix: SystemPreferences.shared.systemLanguage.regionSuffix,
            localDestination: localURL, localStem: romPathKey
        )
        return saved
    }

    // Downloads up to `cap` libretro "Named_Snaps" in-game screenshots to
    // {stem}_snap_0.png, {stem}_snap_1.png, ... in the boxart dir.
    // Returns the on-disk URLs that were successfully downloaded.
    func downloadScreenshots(for rom: ROM, cap: Int = 4) async -> [URL] {
        let romPathKey: String
        if let inner = rom.innerROMPath {
            romPathKey = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romPathKey = rom.path.deletingPathExtension().lastPathComponent
        }
        let boxartDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let stem = "\(romPathKey)_snap"

        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom) else { return [] }
        let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
        guard !folders.isEmpty else { return [] }
        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom, useCRC: useCRCMatchingForThumbnails, fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else { return [] }

        let regionPreference = SystemPreferences.shared.systemLanguage.noIntroRegionPreference
        let matches = await LibretroThumbnailResolver.bestMatchingURLs(
            forType: "Named_Snaps",
            gameTitle: gameTitle,
            systemFolders: folders,
            base: thumbnailServerURL,
            regionPreference: regionPreference
        )

        var results: [URL] = []
        for (index, (_, url, _)) in matches.enumerated() where index < cap {
            let localURL = boxartDir.appendingPathComponent("\(stem)_\(index).png")
            if let saved = await downloadAndCache(artURL: url, for: rom, to: localURL, session: thumbnailURLSession) {
                results.append(saved)
            }
        }
        return results
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

    // Returns ROMs whose boxart was fetched for a different region than the current one.
    // ROMs with existing boxart but nil region (pre-region-tracking) are treated as stale.
    func romsWithStaleRegion(in roms: [ROM], currentRegionSuffix: String?) -> [ROM] {
        guard let currentRegion = currentRegionSuffix, !currentRegion.isEmpty else { return [] }
        return roms.filter {
            guard $0.hasBoxArt else { return false }
            guard let requested = $0.boxArtRequestedRegion else { return true }
            return requested != currentRegion
        }
    }

    // Returns ROMs whose boxart was fetched recently (within 7 days) for the current region.
    func romsWithRecentBoxArt(in roms: [ROM], currentRegionSuffix: String?) -> [ROM] {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        return roms.filter {
            guard $0.hasBoxArt, let fetched = $0.boxArtFetchedAt else { return false }
            if let region = $0.boxArtRequestedRegion, region == currentRegionSuffix {
                return fetched > sevenDaysAgo
            }
            return false
        }
    }

    func batchDownloadBoxArtLibretro(for roms: [ROM], library: ROMLibrary, reDownloadForNewRegion: Bool = false, onItemProgress: ((Int, Int, String, URL?) -> Void)? = nil) async {
        let broken = findBrokenBoxArts(in: roms)
        if !broken.isEmpty { _ = await cleanBrokenBoxArts(for: broken) }

        let regionSuffix = SystemPreferences.shared.systemLanguage.regionSuffix

        var candidates: [ROM]
        if reDownloadForNewRegion {
            let stale = romsWithStaleRegion(in: roms, currentRegionSuffix: regionSuffix)
            let staleIDs = Set(stale.map { $0.id })
            candidates = roms.filter { !$0.hasBoxArt || staleIDs.contains($0.id) }
        } else {
            // Same region: skip recently fetched ones, only download truly missing
            let recent = romsWithRecentBoxArt(in: roms, currentRegionSuffix: regionSuffix)
            let recentIDs = Set(recent.map { $0.id })
            let needsArt = romsNeedingBoxArt(in: roms)
            candidates = needsArt.filter { !recentIDs.contains($0.id) }
        }

        guard !candidates.isEmpty else { return }

        // Pre-warm manifest caches: fetch once per unique system so all individual
        // fetchBoxArtLibretro calls use cached in-memory data instead of hitting GitHub.
        // This must run on MainActor since workingFolders uses @MainActor.
        await withTaskGroup(of: Void.self) { warmupGroup in
            var seenSystems = Set<String>()
            for rom in candidates {
                guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom),
                      !seenSystems.contains(sysID) else { continue }
                seenSystems.insert(sysID)
                let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
                for folder in folders {
                    let repoName = LibretroThumbnailResolver.githubRepoName(for: folder)
                    warmupGroup.addTask {
                        _ = try? await LibretroThumbnailManifestService.shared.getManifestFileSet(for: repoName)
                    }
                }
            }
        }

        let maxConcurrent = 2
        var modifiedIDs: [UUID] = []
        let total = candidates.count
        
        await withTaskGroup(of: (ROM, URL?, String?).self) { group in
            var activeTasks = 0
            var completed = 0
            var iterator = candidates.makeIterator()
            
            while activeTasks < maxConcurrent, let rom = iterator.next() {
                group.addTask {
                    if let local = self.resolveLocalBoxArt(for: rom) { return (rom, local, nil) }
                    let (url, regionTag) = await self.fetchBoxArtLibretro(for: rom, regionSuffix: regionSuffix)
                    return (rom, url, regionTag)
                }
                activeTasks += 1
            }
            
            for await result in group {
                activeTasks -= 1
                completed += 1
                var (completedRom, url, regionTag) = result
                if let _ = url {
                    completedRom.hasBoxArt = true
                    completedRom.boxArtRequestedRegion = regionSuffix
                    completedRom.boxArtRegionTag = regionTag
                    completedRom.boxArtFetchedAt = Date()
                    modifiedIDs.append(completedRom.id)
                    await MainActor.run { library.updateROM(completedRom, persist: false) }
                }
                onItemProgress?(completed, total, completedRom.displayName, url)
                if let nextRom = iterator.next() {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    group.addTask {
                        if let local = self.resolveLocalBoxArt(for: nextRom) { return (nextRom, local, nil) }
                        let (url, regionTag) = await self.fetchBoxArtLibretro(for: nextRom, regionSuffix: regionSuffix)
                        return (nextRom, url, regionTag)
                    }
                    activeTasks += 1
                }
            }
        }
        
        await MainActor.run {
            library.saveROMsToDatabase(only: modifiedIDs)
            if !modifiedIDs.isEmpty { signalBoxArtUpdated(for: UUID()) }
        }

        // Pre-generate on-disk thumbnails for the ROMs we just fetched so the
        // next scroll paints them from the fast disk-thumb path instead of
        // decoding the full original. Runs on the thumbnail service queue.
        if !modifiedIDs.isEmpty {
            let fetched = roms.filter { modifiedIDs.contains($0.id) }
            BoxArtThumbnailService.shared.warmThumbnails(for: fetched)
        }

        // Post-pass: also fetch libretro Named_Titles (title screen) and Named_Snaps
        // (in-game screenshots). These complement the box art on the game detail
        // overview. We fetch them for every passed ROM that is still missing them,
        // independent of whether box art downloaded (a game can have box art but no
        // title screen, or vice-versa). Failures are silently ignored.
        let needTitle = roms.filter { !$0.hasTitleScreen || $0.screenshotPaths.isEmpty }
        guard !needTitle.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            var iterator = needTitle.makeIterator()
            while active < 2, let rom = iterator.next() {
                group.addTask { await self.downloadTitleAndScreenshots(for: rom, library: library) }
                active += 1
            }
            for await _ in group {
                active -= 1
                if let next = iterator.next() {
                    group.addTask { await self.downloadTitleAndScreenshots(for: next, library: library) }
                    active += 1
                }
            }
        }
    }

    // Fetches the title screen (Named_Titles) and up to 4 in-game screenshots
    // (Named_Snaps) for a single ROM, persisting the results onto the ROM
    // (hasTitleScreen / hasScreenshots / screenshotPaths) without forcing a DB save.
    // Public so the Game Detail view can lazily fetch art that the scan-time pass missed.
    func downloadTitleAndScreenshots(for rom: ROM, library: ROMLibrary) async {
        var updated = rom
        if let titleURL = await downloadTitleScreen(for: rom) {
            updated.hasTitleScreen = true
            updated.titleScreenLocalPath = titleURL
        }
        let snaps = await downloadScreenshots(for: rom)
        if !snaps.isEmpty {
            updated.hasScreenshots = true
            updated.screenshotPaths = snaps
        }
        guard updated.hasTitleScreen || updated.hasScreenshots else { return }
        await MainActor.run { library.updateROM(updated, persist: false) }
        await MainActor.run { library.saveROMsToDatabase(only: [updated.id]) }
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
            BoxArtThumbnailService.deleteThumbnails(for: url)
            BoxArtThumbnailService.generateThumbnailsSynchronously(forOriginal: url)
            Task { await ImageCache.shared.removeImage(for: url); await ImageCache.shared.removeThumbnail(for: url) }
        }
        // Invalidate the per-ROM resolve cache so the next resolve re-scans.
        // Legacy callers pass UUID() (junk); we just skip invalidation in
        // that case — the cards' .task keyed on rom.hasBoxArt will re-fire
        // when library.updateROM mutates the affected rom(s).
        if romID != UUID() {
            ResultCache.shared.remove(romID)
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

// MARK: - resolveLocalBoxArt per-ROM memoization

/// Thread-safe per-ROM cache for BoxArtService.resolveLocalBoxArt(). Stores
/// results keyed by ROM id so that art-less cards scrolling in and out of view
/// don't re-list their /boxart directory on every appearance. A nil value is
/// a valid cache entry (meaning "we looked, there's nothing there").
private final class ResultCache: @unchecked Sendable {
    static let shared = ResultCache()
    private var cache: [UUID: URL?] = [:]
    private let lock = NSLock()

    func get(_ id: UUID) -> URL?? {
        lock.lock(); defer { lock.unlock() }
        return cache[id]
    }

    func set(_ id: UUID, _ value: URL?) {
        lock.lock(); defer { lock.unlock() }
        cache[id] = value
    }

    func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: id)
    }
}
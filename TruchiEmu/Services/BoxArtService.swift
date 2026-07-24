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
            let (libResult, _) = await fetchBoxArtLibretro(for: rom, regionSuffix: regionSuffix)
            if case .success(let lib) = libResult {
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
           let match = LaunchBoxMetadataService.shared.bestMatch(
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
        if case .success(let url) = await downloadAndCache(artURL: artURL, for: rom, to: rom.boxArtLocalPath, session: session) {
            return url
        }
        return nil
    }

    // Same as downloadAndCache(artURL:for:) but saves to a custom destination URL.
    // Used for title screens ({stem}_title.png) and in-game screenshots ({stem}_snap_N.png)
    // which share the boxart directory but use different filenames.
    // Result of a single artwork download, carrying the *reason* for failure so
    // callers can cache negative results with the right TTL:
    //  - .success:       file on disk (valid image).
    //  - .notFound:      definitively absent — 404, or non-image content. Safe to
    //                    remember for a long time (CDN genuinely has no art).
    //  - .transient:     network error / timeout / 429 / 5xx. Retry soon; do not
    //                    treat as permanent absence (API throttling, blip, etc.).
    enum ArtDownloadResult: Equatable {
        case success(URL)
        case notFound
        case transient
    }

    func downloadAndCache(artURL: URL, for rom: ROM, to localURL: URL, session: URLSession? = nil) async -> ArtDownloadResult {
        let sess = session ?? URLSession.shared
        let folder = localURL.deletingLastPathComponent()

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Disk is the source of truth: if the art file already exists and is a
        // valid image, never delete-and-re-download it. This prevents re-fetching
        // (and clobbering) art we already have on every re-scan, for box art,
        // title screens, and screenshots alike.
        if FileManager.default.fileExists(atPath: localURL.path), isValidImageFile(at: localURL) {
            if localURL == rom.boxArtLocalPath {
                BoxArtThumbnailService.deleteThumbnails(for: localURL)
                await ImageCache.shared.removeImage(for: localURL)
                await ImageCache.shared.removeThumbnail(for: localURL)
                BoxArtThumbnailService.generateThumbnailsSynchronously(forOriginal: localURL)
            } else {
                await ImageCache.shared.removeImage(for: localURL)
            }
            return .success(localURL)
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            try? FileManager.default.removeItem(at: localURL)
        }

        do {
            let (tmpURL, response) = try await sess.download(from: artURL)
            if let httpResponse = response as? HTTPURLResponse {
                let status = httpResponse.statusCode
                guard (200...299).contains(status) else {
                    // 404 = definitively no art; everything else (429/5xx/403) is
                    // transient (throttling / server error) and should be retried.
                    return status == 404 ? .notFound : .transient
                }
                let validImageTypes = ["image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp", "image/bmp"]
                guard validImageTypes.contains((httpResponse.mimeType ?? "").lowercased()) else { return .notFound }
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
            return .success(localURL)
        } catch {
            // Timeout, connection drop, DNS failure — transient, retry soon.
            return .transient
        }
    }

    // MARK: - Libretro thumbnails CDN

    // Returns (localFileURL, resolvedRegionTag). The region tag is extracted from the CDN URL
    // (e.g., "(USA)"), NOT from the local file path. Returns (.notFound, nil) on
    // definitive failure, (.transient, nil) on network/transient failure.
    func fetchBoxArtLibretro(for rom: ROM, regionSuffix: String? = nil) async -> (ArtDownloadResult, String?) {
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
             return (.success(URL(fileURLWithPath: cached.resolvedURL)), nil)
         }

         guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom) else { return (.notFound, nil) }

         // Resolve working folders (probes once, then cached)
         let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
         guard !folders.isEmpty else { return (.notFound, nil) }

         // This is the heavy CRC calculation
         guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
             for: rom,
             useCRC: useCRCMatchingForThumbnails,
             fallbackFilename: fallbackToFilenameForThumbnails
         ), !gameTitle.isEmpty else { return (.notFound, nil) }

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
                 if isValidImageFile(at: local) { return (.success(local), nil) }
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

        var sawTransient = false
        for (_, url, regionTag) in manifestMatches {
            if let cached = cacheRepo.getBoxArtResolution(romPathKey: romPathKey, source: source) {
                if cached.resolvedURL == url.absoluteString && !cached.isValid && cached.httpStatus != 0 { continue }
            }

            // Skip HEAD check for manifest-confirmed URLs — the manifest is authoritative,
            // so we avoid an extra CDN hit. Go straight to download.
            switch await downloadAndCache(artURL: url, for: rom, to: rom.boxArtLocalPath, session: thumbnailURLSession) {
            case .success(let saved):
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return (.success(saved), regionTag)
            case .transient:
                sawTransient = true
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: 0, isValid: false)
            case .notFound:
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

            switch await downloadAndCache(artURL: url, for: rom, to: rom.boxArtLocalPath, session: thumbnailURLSession) {
            case .success(let saved):
                let resolvedRegionTag = LibretroThumbnailResolver.regionTag(from: url)
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return (.success(saved), resolvedRegionTag)
            case .transient:
                sawTransient = true
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: headStatusCode == -1 ? 0 : headStatusCode, isValid: false)
            case .notFound:
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: headStatusCode == -1 ? 0 : headStatusCode, isValid: false)
            }
        }

        // No candidate produced a file. If any attempt was a transient (throttled /
        // network) failure, report that so the caller retries soon; otherwise the
        // art is definitively absent.
        return (sawTransient ? .transient : .notFound, nil)
    }

    // MARK: - Named_Titles / Named_Snaps (title screens & in-game screenshots)

    // Generic libretro CDN fetch for a single Named_* type folder that saves to a
    // caller-supplied local destination. Returns the result (carrying failure reason).
    private func fetchThumbnailLibretro(
        for rom: ROM,
        typeFolder: String,
        regionSuffix: String?,
        localDestination: URL,
        localStem: String
    ) async -> ArtDownloadResult {
        let source = "libretro_\(typeFolder)"
        let romPathKey = localStem

        // Disk is the source of truth: if the title/screenshot file already exists
        // and is a valid image, return it immediately. This skips the per-ROM
        // CRC + network manifest lookup that otherwise burns ~66ms per ROM on
        // every re-scan even when the art is already on disk.
        if FileManager.default.fileExists(atPath: localDestination.path), isValidImageFile(at: localDestination) {
            return .success(localDestination)
        }

        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom) else { return .notFound }

        let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
        guard !folders.isEmpty else { return .notFound }

        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom,
            useCRC: useCRCMatchingForThumbnails,
            fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else { return .notFound }

        let regionPreference = SystemPreferences.shared.systemLanguage.noIntroRegionPreference
        let manifestMatches = await LibretroThumbnailResolver.bestMatchingURLs(
            forType: typeFolder,
            gameTitle: gameTitle,
            systemFolders: folders,
            base: thumbnailServerURL,
            regionPreference: regionPreference
        )

        var sawTransient = false
        for (_, url, _) in manifestMatches {
            switch await downloadAndCache(artURL: url, for: rom, to: localDestination, session: thumbnailURLSession) {
            case .success(let saved):
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: saved.path, source: source, httpStatus: 200, isValid: true)
                return .success(saved)
            case .transient:
                sawTransient = true
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: 0, isValid: false)
            case .notFound:
                cacheRepo.storeBoxArtResolution(romPathKey: romPathKey, systemID: sysID, gameTitle: gameTitle, resolvedURL: url.absoluteString, source: source, httpStatus: 0, isValid: false)
            }
        }
        return sawTransient ? .transient : .notFound
    }

    // Downloads the libretro "Named_Titles" title screen to {stem}_title.png in the boxart dir.
    func downloadTitleScreen(for rom: ROM) async -> ArtDownloadResult {
        let romPathKey: String
        if let inner = rom.innerROMPath {
            romPathKey = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romPathKey = rom.path.deletingPathExtension().lastPathComponent
        }
        let boxartDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let stem = "\(romPathKey)_title"
        let localURL = boxartDir.appendingPathComponent("\(stem).png")
        return await fetchThumbnailLibretro(
            for: rom, typeFolder: "Named_Titles", regionSuffix: SystemPreferences.shared.systemLanguage.regionSuffix,
            localDestination: localURL, localStem: romPathKey
        )
    }

    // Downloads up to `cap` libretro "Named_Snaps" in-game screenshots to
    // {stem}_snap_0.png, {stem}_snap_1.png, ... in the boxart dir.
    // Returns the on-disk URLs that were successfully downloaded.
    func downloadScreenshots(for rom: ROM, cap: Int = 4) async -> ([URL], ArtDownloadResult) {
        let romPathKey: String
        if let inner = rom.innerROMPath {
            romPathKey = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romPathKey = rom.path.deletingPathExtension().lastPathComponent
        }
        let boxartDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let stem = "\(romPathKey)_snap"

        // Disk is the source of truth: if the requested screenshot files already
        // exist on disk, return them immediately — skip the per-ROM CRC hash and
        // network manifest lookup that otherwise burn ~670ms per ROM every re-scan
        // (even when the art is already present).
        let existing = (0..<cap).compactMap { i -> URL? in
            let url = boxartDir.appendingPathComponent("\(stem)_\(i).png")
            return FileManager.default.fileExists(atPath: url.path) && isValidImageFile(at: url) ? url : nil
        }
        if !existing.isEmpty { return (existing, .success(existing[0])) }

        guard let sysID = LibretroThumbnailResolver.effectiveThumbnailSystemID(for: rom) else { return ([], .notFound) }
        let folders = await LibretroThumbnailResolver.workingFolders(forSystemID: sysID)
        guard !folders.isEmpty else { return ([], .notFound) }
        guard let gameTitle = await LibretroThumbnailResolver.resolveGameTitle(
            for: rom, useCRC: useCRCMatchingForThumbnails, fallbackFilename: fallbackToFilenameForThumbnails
        ), !gameTitle.isEmpty else { return ([], .notFound) }

        let regionPreference = SystemPreferences.shared.systemLanguage.noIntroRegionPreference
        let matches = await LibretroThumbnailResolver.bestMatchingURLs(
            forType: "Named_Snaps",
            gameTitle: gameTitle,
            systemFolders: folders,
            base: thumbnailServerURL,
            regionPreference: regionPreference
        )

        var results: [URL] = []
        var sawTransient = false
        for (index, (_, url, _)) in matches.enumerated() where index < cap {
            let localURL = boxartDir.appendingPathComponent("\(stem)_\(index).png")
            switch await downloadAndCache(artURL: url, for: rom, to: localURL, session: thumbnailURLSession) {
            case .success(let saved): results.append(saved)
            case .transient: sawTransient = true
            case .notFound: break
            }
        }
        let result: ArtDownloadResult = results.isEmpty ? (sawTransient ? .transient : .notFound) : .success(results[0])
        return (results, result)
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
            // Same region: only download truly missing art. Disk is the source of
            // truth — if the box art file already exists locally (valid image, not
            // the 7-day cache window or a region flag), skip it. This prevents
            // re-downloading art we already have on every re-scan.
            let recent = romsWithRecentBoxArt(in: roms, currentRegionSuffix: regionSuffix)
            let recentIDs = Set(recent.map { $0.id })
            let needsArt = romsNeedingBoxArt(in: roms)
            candidates = needsArt.filter { !recentIDs.contains($0.id) }
        }

        // Hard gate: drop any candidate whose box art file already exists on disk.
        // Covers art fetched >7 days ago, region-flag churn, or in-memory flag
        // drift — if the file is there, we never re-download it.
        let preDiskGate = candidates.count
        candidates = candidates.filter { !FileManager.default.fileExists(atPath: $0.boxArtLocalPath.path) }

        #if LOG_DEBUG
        LoggerService.info(category: "BoxArt", "batch: input=\(roms.count) preDiskGate=\(preDiskGate) postDiskGate=\(candidates.count) (needArt=\(romsNeedingBoxArt(in: roms).count) recent=\(romsWithRecentBoxArt(in: roms, currentRegionSuffix: regionSuffix).count))")
        #endif

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

        let maxConcurrent = 8
        var modifiedIDs: [UUID] = []
        let total = candidates.count
        
        await withTaskGroup(of: (ROM, ArtDownloadResult, String?).self) { group in
            var activeTasks = 0
            var completed = 0
            var iterator = candidates.makeIterator()
            
            while activeTasks < maxConcurrent, let rom = iterator.next() {
                group.addTask {
                    if let local = self.resolveLocalBoxArt(for: rom) { return (rom, .success(local), nil) }
                    let (result, regionTag) = await self.fetchBoxArtLibretro(for: rom, regionSuffix: regionSuffix)
                    return (rom, result, regionTag)
                }
                activeTasks += 1
            }
            
            for await result in group {
                activeTasks -= 1
                completed += 1
                var (completedRom, artResult, regionTag) = result
                if case .success = artResult {
                    completedRom.hasBoxArt = true
                    completedRom.boxArtRequestedRegion = regionSuffix
                    completedRom.boxArtRegionTag = regionTag
                    completedRom.boxArtFetchedAt = Date()
                    modifiedIDs.append(completedRom.id)
                    await MainActor.run { library.updateROM(completedRom, persist: false) }
                }
                let reportedURL: URL? = if case .success(let u) = artResult { u } else { nil }
                onItemProgress?(completed, total, completedRom.displayName, reportedURL)
                if let nextRom = iterator.next() {
                    group.addTask {
                        if let local = self.resolveLocalBoxArt(for: nextRom) { return (nextRom, .success(local), nil) }
                        let (r, regionTag) = await self.fetchBoxArtLibretro(for: nextRom, regionSuffix: regionSuffix)
                        return (nextRom, r, regionTag)
                    }
                    activeTasks += 1
                }
            }
        }
        
        await MainActor.run {
            library.saveROMsToDatabase(only: modifiedIDs)
            if !modifiedIDs.isEmpty { signalBoxArtUpdated(for: UUID()) }
        }

        // Let the UI advance past the final "100% — <rom>" line so it doesn't
        // appear frozen while we persist and build thumbnails.
        onItemProgress?(total, total, LocalizationManager.shared.localized("library.automation.savingLibrary"), nil)

        // Pre-generate on-disk thumbnails for the ROMs we just fetched so the
        // next scroll paints them from the fast disk-thumb path instead of
        // decoding the full original. Runs on the thumbnail service queue.
        if !modifiedIDs.isEmpty {
            let fetched = roms.filter { modifiedIDs.contains($0.id) }
            BoxArtThumbnailService.shared.warmThumbnails(for: fetched)
        }

        // NOTE: Title screens and in-game screenshots are intentionally NOT fetched
        // here. The scan only downloads box art; title/snaps are fetched lazily when
        // the user opens a game's info view (GameDetailView calls
        // downloadTitleAndScreenshots). Fetching them for the whole library at scan
        // time added ~140s of CDN lookups (incl. 9s timeouts for ROMs with no art on
        // the libretro CDN) for art the user may never look at.
    }

    // Fetches the title screen (Named_Titles) and up to 4 in-game screenshots
    // (Named_Snaps) for a single ROM, persisting the results onto the ROM
    // (hasTitleScreen / hasScreenshots / screenshotPaths) without forcing a DB save.
    // Public so the Game Detail view can lazily fetch art that the scan-time pass missed.
    func downloadTitleAndScreenshots(for rom: ROM, library: ROMLibrary) async {
        // Disk is the source of truth: if the title screen and at least one
        // screenshot already exist on disk, skip all network lookups. This keeps
        // re-scans from re-fetching (and re-listing manifests for) art we already have.
        let romPathKey: String
        if let inner = rom.innerROMPath {
            romPathKey = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romPathKey = rom.path.deletingPathExtension().lastPathComponent
        }
        let boxartDir = rom.path.deletingLastPathComponent().appendingPathComponent("boxart", isDirectory: true)
        let titleExists = FileManager.default.fileExists(atPath: boxartDir.appendingPathComponent("\(romPathKey)_title.png").path)
        let snapExists = (0..<4).contains {
            FileManager.default.fileExists(atPath: boxartDir.appendingPathComponent("\(romPathKey)_snap_\($0).png").path)
        }
        if titleExists && snapExists {
            LoggerService.info(category: "BoxArtProf", "PROF skip \(romPathKey): title+snap on disk")
            return
        }

        // Negative-result cache with reason-specific TTLs. We distinguish WHY a fetch
        // failed so we don't conflate "CDN definitively has no art" with "network
        // blip / API throttling":
        //  - .notFound  (404 / non-image): the art genuinely doesn't exist → remember
        //                for a long time (7 days). Safe; CDN won't suddenly gain it.
        //  - .transient (timeout / 429 / 5xx): retry soon (6h) so a throttle or blip
        //                doesn't permanently block art that's actually available.
        // A successful fetch always wins and clears any negative entry.
        let pathKey = rom.path.path
        let notFoundTTL: TimeInterval = 7 * 24 * 3600
        let transientTTL: TimeInterval = 6 * 3600
        let notFoundCache: [String: Date] = {
            guard let data = AppSettings.getData("boxart_titleSnap_notFound"),
                  let map = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
            return map
        }()
        let transientCache: [String: Date] = {
            guard let data = AppSettings.getData("boxart_titleSnap_transient"),
                  let map = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
            return map
        }()
        if let cachedAt = notFoundCache[pathKey], Date().timeIntervalSince(cachedAt) < notFoundTTL {
            LoggerService.info(category: "BoxArtProf", "PROF skip \(romPathKey): CDN notFound cached")
            return
        }
        if let cachedAt = transientCache[pathKey], Date().timeIntervalSince(cachedAt) < transientTTL {
            LoggerService.info(category: "BoxArtProf", "PROF skip \(romPathKey): CDN transient cached")
            return
        }

        var updated = rom
        var titleResult: ArtDownloadResult = .notFound
        var snapResult: ArtDownloadResult = .notFound
        if !titleExists {
            let tt = Date()
            titleResult = await downloadTitleScreen(for: rom)
            let exists = if case .success = titleResult { true } else { false }
            LoggerService.info(category: "BoxArtProf", "PROF title '\(romPathKey)' took \(String(format: "%.2f", Date().timeIntervalSince(tt)))s (exists=\(exists))")
            if case .success(let url) = titleResult {
                updated.hasTitleScreen = true; updated.titleScreenLocalPath = url
            }
        }
        if !snapExists {
            let ts = Date()
            let (snaps, result) = await downloadScreenshots(for: rom)
            snapResult = result
            LoggerService.info(category: "BoxArtProf", "PROF snap '\(romPathKey)' took \(String(format: "%.2f", Date().timeIntervalSince(ts)))s (count=\(snaps.count))")
            if !snaps.isEmpty {
                updated.hasScreenshots = true
                updated.screenshotPaths = snaps
            }
        }
        // Remember the worst failure reason so we re-check with the right TTL.
        // .transient outranks .notFound (a transient failure should retry sooner).
        let worst: ArtDownloadResult = (titleResult == .transient || snapResult == .transient) ? .transient : .notFound
        let hasAnySuccess = if case .success = titleResult { true } else if case .success = snapResult { true } else { false }
        if !hasAnySuccess {
            let now = Date()
            if worst == .transient {
                var map = transientCache; map[pathKey] = now
                if let data = try? JSONEncoder().encode(map) { AppSettings.setData("boxart_titleSnap_transient", value: data) }
            } else {
                var map = notFoundCache; map[pathKey] = now
                if let data = try? JSONEncoder().encode(map) { AppSettings.setData("boxart_titleSnap_notFound", value: data) }
            }
            return
        }
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
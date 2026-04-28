import Foundation

// Logger for ROMScanner - routes through LoggerService for timestamped file logging.
private enum ROMScannerLog {
    static func debug(_ message: String) { LoggerService.debug(category: "ROMScanner", message) }
}

// MARK: - Helper Actor for Thread-Safe Progress
private actor ProgressTracker {
    private var processed: Int = 0
    private let total: Int
    private let progressHandler: (Double) -> Void
    private var lastUpdate = DispatchTime.now().uptimeNanoseconds
    private let throttleNanos: UInt64 = 50_000_000 // 50ms

    init(total: Int, progressHandler: @escaping (Double) -> Void) {
        self.total = total
        self.progressHandler = progressHandler
    }

    func incrementAndReport() {
        processed += 1
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastUpdate >= throttleNanos || processed == total {
            lastUpdate = now
            progressHandler(Double(processed) / Double(max(total, 1)))
        }
    }
}

actor ROMScanner {

    // Cancellation flag
    private var isCancelled = false

    func cancel() {
        isCancelled = true
    }

    private func resetCancellation() {
        isCancelled = false
    }

    // Static Set is much faster than recreating it per file
    private static let nonROMExtensions: Set<String> = [
        "txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
        "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
        "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"
    ]

    // MARK: - Bulk MAME Identification
    func bulkIdentifyMAME(urls: [URL]) async -> (mameURLs: Set<URL>, remainingURLs: [URL]) {
        await MAMEUnifiedService.shared.ensureLoaded()
        
        var zipURLs: [URL] = []
        var remainingURLs: [URL] = []
        
        // 1. Separate ZIPs from direct files (.nes, .sfc, etc.)
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                zipURLs.append(url)
            } else {
                remainingURLs.append(url)
            }
        }
        
        var mameURLs = Set<URL>()
        var playableMameURLs = Set<URL>()
        
        // 2. Identify which ZIPs belong to MAME
        for url in zipURLs {
            let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
            
            // If the Master Lookup Table contains this key, it is a MAME asset.
            // It doesn't matter if it's a BIOS, a Game, or Unplayable—it belongs to MAME.
            LoggerService.debug(category: "MAMEUnifiedService", "Lookup for \(shortName)")
            if MAMEUnifiedService.shared.lookup(shortName: shortName) != nil {
                LoggerService.debug(category: "MAMEUnifiedService", "Lookup for \(shortName)... found: \(url)")
                mameURLs.insert(url)
            } else {
                // If MAME doesn't know what this is, it's likely a zipped console ROM (SNES/Genesis)
                // Pass it to the Deep Scan to be unzipped and analyzed.
                LoggerService.debug(category: "MAMEUnifiedService", "Lookup for \(shortName)... NOT found: \(url)")
                remainingURLs.append(url)
            }
            // Actual runnable mame roms
            if MAMEUnifiedService.shared.isRunnable(shortName: shortName) {
                LoggerService.debug(category: "MAMEUnifiedService", "Lookup for \(shortName)... Playable: \(url)")
                playableMameURLs.insert(url)
            }
        }   
        
        LoggerService.debug(category: "ROMScanner", "Bulk Matrix Op: Identified \(urls.count) files, \(zipURLs.count) zips. Then \(mameURLs.count) MAME assets and \(playableMameURLs.count) playable. Passing \(remainingURLs.count) unknown ZIPs/files to deep scan.")
        
        return (playableMameURLs, remainingURLs)
    }

    // MARK: - Core Scanning Logic

    func scan(folder: URL, cancellationToken: ScanCancellationToken? = nil, progress: @escaping (Double) -> Void) async -> [ROM] {
        LoggerService.info(category: "ROMScanner", "=== SCAN STARTED: \(folder.path) ===")
        resetCancellation()
        
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return[] }
        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        
        return await unifiedScan(urls: allURLs, cancellationToken: cancellationToken, progress: progress)
    }
    
    func scan(urls: [URL], progress: @escaping (Double) -> Void) async ->[ROM] {
        LoggerService.info(category: "ROMScanner", "=== SCAN STARTED (URLs): \(urls.count) files ===")
        resetCancellation()
        return await unifiedScan(urls: urls, cancellationToken: nil, progress: progress)
    }
    
    private func unifiedScan(urls:[URL], cancellationToken: ScanCancellationToken?, progress: @escaping (Double) -> Void) async -> [ROM] {
        let scanStart = Date()
        let totalFiles = urls.count
        
        let uniqueFolders = Set(urls.map { $0.deletingLastPathComponent() })
        
        // 1. Build Ignore List & Pre-load XML Meta
        let ignoredURLs = await buildIgnoreList(for: urls, in: uniqueFolders)
        var xmlCache: [URL: [String: ROMMetadata]] = [:]
        for folder in uniqueFolders {
            xmlCache[folder] = loadFolderMetadata(folder: folder)
        }
        
        // 2. MAME Matrix
        let (mameURLs, deepScanURLs) = await bulkIdentifyMAME(urls: urls)
        
        let progressTracker = ProgressTracker(total: totalFiles, progressHandler: progress)
        var found: [ROM] = []
        found.reserveCapacity(totalFiles)
        
        var zipCount = 0
        var unknownCount = 0
        let mameSystem = SystemDatabase.system(forID: "mame")
        
        // 3. Process Instant MAME ROMs
        for url in mameURLs {
            if isCancelled || (cancellationToken?.isCancelled ?? false) { break }
            await progressTracker.incrementAndReport()
            zipCount += 1
            
            let name = url.deletingPathExtension().lastPathComponent
            let folder = url.deletingLastPathComponent()
            var mameROM = ROM(id: UUID(), name: name, path: url, systemID: mameSystem?.id)
            
            mameROM.metadata = xmlCache[folder]?[url.lastPathComponent]
            await applyMAMEIdentification(to: &mameROM, url: url)
            
            mameROM.refreshDerivedFields()
            if !mameROM.isBios && FileManager.default.fileExists(atPath: mameROM.boxArtLocalPath.path) {
                mameROM.hasBoxArt = true
                mameROM.refreshDerivedFields()
            }
            
            found.append(mameROM)
        }
        
        // 4. Concurrently Deep Scan the Rest
        let maxConcurrentTasks = 16
        await withTaskGroup(of: ROM?.self) { group in
            var iterator = deepScanURLs.makeIterator()
            
            // Enqueue initial batch of tasks
            for _ in 0..<maxConcurrentTasks {
                if let nextURL = iterator.next() {
                    group.addTask { await self.processSingleFile(url: nextURL, ignoredURLs: ignoredURLs, xmlCache: xmlCache, progressTracker: progressTracker, cancellationToken: cancellationToken) }
                }
            }
            
            // Keep feeding the task group until empty
            for await result in group {
                if let rom = result {
                    found.append(rom)
                    let ext = rom.path.pathExtension.lowercased()
                    if ext == "zip" || ext == "7z" { zipCount += 1 }
                    if rom.systemID == "unknown" { unknownCount += 1 }
                }
                
                if isCancelled || (cancellationToken?.isCancelled ?? false) { continue }
                
                if let nextURL = iterator.next() {
                    group.addTask { await self.processSingleFile(url: nextURL, ignoredURLs: ignoredURLs, xmlCache: xmlCache, progressTracker: progressTracker, cancellationToken: cancellationToken) }
                }
            }
        }
        
        if unknownCount > 0 { LoggerService.info(category: "ROMScanner", "Unknown system files: \(unknownCount)") }
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMScanner", "=== SCAN COMPLETE: \(found.count) ROMs found in \(String(format: "%.2f", scanTime))s ===")
        LoggerService.info(category: "ROMScanner", "ZIPs processed: \(zipCount)")
        
        progress(1.0)
        return found
    }

    private func processSingleFile(
        url: URL,
        ignoredURLs: Set<String>,
        xmlCache: [URL: [String: ROMMetadata]],
        progressTracker: ProgressTracker,
        cancellationToken: ScanCancellationToken?
    ) async -> ROM? {
        await progressTracker.incrementAndReport()
        
        if isCancelled || (cancellationToken?.isCancelled ?? false) { return nil }
        if ignoredURLs.contains(url.standardized.path) { return nil }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, !shouldSkipExtension(ext) else { return nil }
        if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { return nil }
        
        let filename = url.lastPathComponent.lowercased()
        
        // Ignore specific PS1 BIOS files
        if filename == "scph5500.bin" || filename == "scph5501.bin" || filename == "scph5502.bin" { return nil }
        
        let system = await identifySystem(url: url, extension: ext)
        let name = url.deletingPathExtension().lastPathComponent
        var rom = ROM(id: UUID(), name: name, path: url, systemID: system?.id)
        
        if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
            rom.isBios = true
            rom.isHidden = true
            rom.category = "bios"
        }
        
        if system?.id == "mame" {
            await applyMAMEIdentification(to: &rom, url: url)
        }
        
        let folder = url.deletingLastPathComponent()
        rom.metadata = xmlCache[folder]?[url.lastPathComponent]
        
        rom.refreshDerivedFields()
        if !rom.isBios && FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path) {
            rom.hasBoxArt = true
            rom.refreshDerivedFields()
        }
        
        return rom
    }
    
    private func buildIgnoreList(for urls: [URL], in uniqueFolders: Set<URL>) async -> Set<String> {
        var ignoredURLs = Set<String>()
        var containerURLs = urls.filter { $0.pathExtension.lowercased() == "cue" || $0.pathExtension.lowercased() == "m3u" }
        
        // Include sibling containers not explicitly passed (Useful for Drag & Drop files without their .cue)
        let fm = FileManager.default
        for folder in uniqueFolders {
            if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                for file in files {
                    let ext = file.pathExtension.lowercased()
                    if (ext == "cue" || ext == "m3u") && !containerURLs.contains(file) {
                        containerURLs.append(file)
                    }
                }
            }
        }
        
        for url in containerURLs {
            let system = await identifySystem(url: url, extension: url.pathExtension.lowercased())
            // If it's a disk-based system OR we know it's a container (cue/m3u), ignore its references
            if system?.isDiskBased == true || url.pathExtension.lowercased() == "cue" || url.pathExtension.lowercased() == "m3u" {
                for ref in getReferencedFiles(in: url) {
                    ignoredURLs.insert(ref.standardized.path)
                }
            }
        }
        
        return ignoredURLs
    }

    // MARK: - MAME ROM Identification
    
    nonisolated private func applyMAMEIdentification(to rom: inout ROM, url: URL) async {
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        if let unifiedEntry = await MAMEUnifiedService.shared.lookup(shortName: shortName) {
            await applyUnifiedMAMEIdentification(to: &rom, entry: unifiedEntry, shortName: shortName)
        }
    }
    
    nonisolated private func applyUnifiedMAMEIdentification(to rom: inout ROM, entry: MAMEUnifiedEntry, shortName: String) async {
        if entry.isBIOS {
            rom.mameRomType = "bios"
            rom.name = entry.description
            rom.isHidden = false
            rom.isBios = true
            rom.category = "bios"
            ROMScannerLog.debug("MAME BIOS '\(shortName)' → '\(entry.description)'")
        } else if entry.isRunnableInAnyCore {
            rom.mameRomType = "game"
            rom.name = entry.description
            rom.isHidden = false
            rom.category = "game"
            
            if rom.metadata == nil { rom.metadata = ROMMetadata() }
            rom.metadata?.title = entry.description
            rom.metadata?.year = entry.year
            rom.metadata?.developer = entry.manufacturer
            rom.metadata?.publisher = entry.manufacturer
            if let players = entry.players { rom.metadata?.players = players }
            
            if entry.isVertical { rom.metadata?.orientation = "vertical" }
            else if let orientation = entry.orientation { rom.metadata?.orientation = orientation }
            
            if let aspectX = entry.aspectX, let aspectY = entry.aspectY {
                rom.metadata?.aspectX = aspectX
                rom.metadata?.aspectY = aspectY
            }
            
            rom.metadata?.screenWidth = entry.width
            rom.metadata?.screenHeight = entry.height
            rom.metadata?.refreshRate = entry.refreshRate
            rom.metadata?.screenType = entry.screenType
            rom.metadata?.cpuName = entry.cpu
            rom.metadata?.audioChips = entry.audio
        } else {
            rom.mameRomType = "unplayable"
            rom.isHidden = true
            rom.category = "unplayable"
        }
    }
    
    nonisolated private func shouldSkipExtension(_ ext: String) -> Bool {
        Self.nonROMExtensions.contains(ext)
    }

    // MARK: - System Identification & Container Logic
    
    nonisolated private func identifySystem(url: URL, extension ext: String) async -> SystemInfo? {
        await ROMIdentifier.identifySystem(url: url, extension: ext)
    }

    nonisolated func getReferencedFiles(in url: URL) ->[URL] {
        ROMIdentifier.getReferencedFiles(in: url)
    }
    
    nonisolated func getIgnoredFiles(in folder: URL) async -> Set<String> {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return[] }
        var ignored = Set<String>()
        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "cue" || ext == "m3u" {
                let system = await identifySystem(url: file, extension: ext)
                if system?.isDiskBased == true {
                    for ref in getReferencedFiles(in: file) { ignored.insert(ref.standardized.path) }
                }
            }
        }
        return ignored
    }

    // MARK: - XML Parsing Optimization
    
    nonisolated private func loadFolderMetadata(folder: URL) -> [String: ROMMetadata] {
        let xmlPath = folder.appendingPathComponent("games.xml")
        var metadataMap:[String: ROMMetadata] = [:]
        
        guard FileManager.default.fileExists(atPath: xmlPath.path),
              let doc = try? XMLDocument(contentsOf: xmlPath, options:[]),
              let root = doc.rootElement(),
              let games = root.children as? [XMLElement] else {
            return [:]
        }
        
        for gameNode in games {
            guard gameNode.name == "game",
                  let relativePath = gameNode.elements(forName: "path").first?.stringValue else { continue }
            
            let filename = relativePath.replacingOccurrences(of: "./", with: "")
            
            var meta = ROMMetadata()
            meta.title = gameNode.elements(forName: "name").first?.stringValue
            meta.year = gameNode.elements(forName: "year").first?.stringValue
            meta.publisher = gameNode.elements(forName: "publisher").first?.stringValue
            meta.developer = gameNode.elements(forName: "developer").first?.stringValue
            meta.genre = gameNode.elements(forName: "genre").first?.stringValue
            meta.description = gameNode.elements(forName: "desc").first?.stringValue
            
            metadataMap[filename] = meta
        }
        
        return metadataMap
    }

    // MARK: - Utility Functions
    
    func downloadDatsForDiscoveredSystems(_ systems: Set<String>) async {
        for sysID in systems {
            if let system = SystemDatabase.system(forID: sysID) {
                _ = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
            }
        }
    }

    func getROMFiles(in folder: URL, progress: @escaping (Double) -> Void) async -> [URL] {
        LoggerService.info(category: "ROMScanner", "=== LIGHTWEIGHT SCAN STARTED: \(folder.path) ===")
        resetCancellation()
        
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return[] }
        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        
        let ignoredURLs = await buildIgnoreList(for: allURLs, in: [folder])
        let progressTracker = ProgressTracker(total: allURLs.count, progressHandler: progress)
        var found: [URL] = []
        
        for url in allURLs {
            if isCancelled { break }
            await progressTracker.incrementAndReport()
            
            if ignoredURLs.contains(url.standardized.path) { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            
            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty, !shouldSkipExtension(ext) else { continue }
            if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { continue }
            
            found.append(url)
        }
        
        progress(1.0)
        return found
    }

    let romExtensions = Set(SystemDatabase.systems.flatMap { $0.extensions })

    func findFoldersWithROMs(baseURL: URL, maxDepth: Int) async -> [URL] {
        var foldersWithROMs:[URL] = []
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options:[.skipsHiddenFiles]) else { return[] }
        
        while let item = enumerator.nextObject() as? URL {
            guard let resourceValues = try? item.resourceValues(forKeys:[.isDirectoryKey, .isRegularFileKey]) else { continue }
            
            if resourceValues.isDirectory == true {
                let relativePath = item.path.replacingOccurrences(of: baseURL.path, with: "")
                let segments = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
                guard segments.count <= maxDepth else { continue }
                
                var hasROMFiles = false
                do {
                    let contents = try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    for file in contents {
                        let ext = file.pathExtension.lowercased()
                        if romExtensions.contains(ext) && !shouldSkipExtension(ext) {
                            hasROMFiles = true
                            break
                        }
                    }
                } catch { continue }
                
                if hasROMFiles { foldersWithROMs.append(item) }
            }
        }
        
        return foldersWithROMs.sorted { $0.path < $1.path }
    }
}

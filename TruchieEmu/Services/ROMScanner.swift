import Foundation

/// Logger for ROMScanner - routes through LoggerService for timestamped file logging.
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

    // Call from UI to cancel an ongoing scan
    func cancel() {
        isCancelled = true
    }

    // Reset cancellation before starting a new scan
    private func resetCancellation() {
        isCancelled = false
    }

    // MARK: - Full Folder Scan
    
    func scan(folder: URL, cancellationToken: ScanCancellationToken? = nil, progress: @escaping (Double) -> Void) async -> [ROM] {
        let scanStart = Date()
        LoggerService.info(category: "ROMScanner", "=== SCAN STARTED: \(folder.path) ===")
        
        resetCancellation()
        let fm = FileManager.default

        // 1. Enumeration Phase
        let enumStart = Date()
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        let enumTime = Date().timeIntervalSince(enumStart)
        LoggerService.info(category: "ROMScanner", "Enumeration: \(allURLs.count) files found in \(String(format: "%.2f", enumTime))s")
        
        // 2. Optimized Ignored Files & Sort Phase
        let ignoredStart = Date()
        var ignoredURLs = Set<String>()
        var zipURLs: [URL] = []
        var nonZipURLs: [URL] = []
        
        for url in allURLs {
            let ext = url.pathExtension.lowercased()
            
             // Only search for references inside known container files (Huge speedup)
             if ext == "cue" || ext == "m3u" {
                 let system = self.identifySystem(url: url, extension: ext)
                 if system?.isDiskBased == true {
                     let refs = getReferencedFiles(in: url)
                     for ref in refs {
                        LoggerService.debug(category: "ROMScanner", "Ignoring referenced file included in \(url.lastPathComponent): \(ref.path)")
                        ignoredURLs.insert(ref.standardized.path)
                     }
                 }
             }
            
            if ext == "zip" || ext == "7z" {
                zipURLs.append(url)
            } else {
                nonZipURLs.append(url)
            }
        }
        
        let orderedURLs = nonZipURLs + zipURLs
        let totalFiles = orderedURLs.count
        
        // 3. Pre-load XML Metadata (O(1) lookup map for the whole folder)
        let xmlMetadataCache = loadFolderMetadata(folder: folder)

        // 4. Concurrent Processing Phase
        let progressTracker = ProgressTracker(total: totalFiles, progressHandler: progress)
        var found: [ROM] = []
        found.reserveCapacity(totalFiles)
        
        var zipCount = 0
        var unknownCount = 0
        
        await withTaskGroup(of: ROM?.self) { group in
            for url in orderedURLs {
                if isCancelled || (cancellationToken?.isCancelled ?? false) { break }
                
                group.addTask {
                    await progressTracker.incrementAndReport()
                    
                    // Skip ignored files
                    if ignoredURLs.contains(url.standardized.path) { return nil }

                    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }

                    let ext = url.pathExtension.lowercased()
                    guard !ext.isEmpty, !self.shouldSkipExtension(ext) else { return nil }
                    
                    if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { return nil }

                    let system = self.identifySystem(url: url, extension: ext)

                    // Ignore specific PS1 BIOS files if they are identified as PS1/PSX
                    let filename = url.lastPathComponent.lowercased()
                    if (filename == "scph5500.bin" || filename == "scph5501.bin" || filename == "scph5502.bin") &&
                       (system?.id == "ps1" || system?.id == "psx") {
                        return nil
                    }

                    let name = url.deletingPathExtension().lastPathComponent

                    var rom = ROM(id: UUID(), name: name, path: url, systemID: system?.id)

                    // BIOS Detection
                    if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
                        rom.isBios = true
                        rom.isHidden = true
                        rom.category = "bios"
                    }

                    // MAME ROM Identification
                    if system?.id == "mame" {
                        self.applyMAMEIdentification(to: &rom, url: url)
                    }

                     // Attach cached metadata
                     rom.metadata = xmlMetadataCache[url.lastPathComponent]
                     
                     // Populate derived fields
                     rom.refreshDerivedFields()
                     
                     // Check local boxart and refresh if found
                     if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                         rom.hasBoxArt = true
                         rom.refreshDerivedFields()
                     }

                    return rom
                }
            }
            
            for await result in group {
                if let rom = result {
                    found.append(rom)
                    let ext = rom.path.pathExtension.lowercased()
                    if ext == "zip" || ext == "7z" { zipCount += 1 }
                    if rom.systemID == "unknown" { unknownCount += 1 }
                }
            }
        }
        
        if unknownCount > 0 {
            LoggerService.info(category: "ROMScanner", "Unknown system files: \(unknownCount)")
        }

        progress(1.0)
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMScanner", "=== SCAN COMPLETE: \(found.count) ROMs found in \(String(format: "%.2f", scanTime))s ===")
        LoggerService.info(category: "ROMScanner", "ZIPs processed: \(zipCount)")
        return found
    }

    // MARK: - Smart URL Scan (For specific files)
    
    func scan(urls: [URL], progress: @escaping (Double) -> Void) async -> [ROM] {
        let scanStart = Date()
        LoggerService.info(category: "ROMScanner", "=== SCAN STARTED (URLs): \(urls.count) files ===")
        resetCancellation()

        let fm = FileManager.default
        let totalFiles = urls.count
        
        // 1. Pre-calculate caches for unique parent folders to prevent redundant lookups
        let uniqueFolders = Set(urls.map { $0.deletingLastPathComponent() })
        var xmlCache: [URL: [String: ROMMetadata]] = [:]
        var folderRefsCache: [URL: Set<String>] = [:]
        
        for folder in uniqueFolders {
            xmlCache[folder] = loadFolderMetadata(folder: folder)
            folderRefsCache[folder] = getIgnoredFiles(in: folder)
        }

        // 2. Concurrent Processing
        let progressTracker = ProgressTracker(total: totalFiles, progressHandler: progress)
        var found: [ROM] = []
        found.reserveCapacity(totalFiles)
        
        await withTaskGroup(of: ROM?.self) { group in
            for url in urls {
                if isCancelled { break }
                
                group.addTask {
                    await progressTracker.incrementAndReport()
                    
                    let folder = url.deletingLastPathComponent()
                    let ignored = folderRefsCache[folder] ?? []
                    
                    if ignored.contains(url.standardized.path) { return nil }
                    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }

                    let ext = url.pathExtension.lowercased()
                    guard !ext.isEmpty, !self.shouldSkipExtension(ext) else { return nil }
                    if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { return nil }

                    let system = self.identifySystem(url: url, extension: ext)

                    // Ignore specific PS1 BIOS files if they are identified as PS1/PSX
                    let filename = url.lastPathComponent.lowercased()
                    if (filename == "scph5500.bin" || filename == "scph5501.bin" || filename == "scph5502.bin") &&
                       (system?.id == "ps1" || system?.id == "psx") {
                        return nil
                    }

                    let name = url.deletingPathExtension().lastPathComponent

                    var rom = ROM(id: UUID(), name: name, path: url, systemID: system?.id)

                    // BIOS
                    if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
                        rom.isBios = true
                        rom.isHidden = true
                        rom.category = "bios"
                    }

                     // Metadata
                     if let folderMetadata = xmlCache[folder] {
                         rom.metadata = folderMetadata[url.lastPathComponent]
                     }
                     
                     // Populate derived fields
                     rom.refreshDerivedFields()
                     
                     // Boxart: check local and refresh if found
                     if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                         rom.hasBoxArt = true
                         rom.refreshDerivedFields()
                     }

                    return rom
                }
            }
            
            for await result in group {
                if let rom = result { found.append(rom) }
            }
        }

        progress(1.0)
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMScanner", "=== SCAN COMPLETE (URLs): \(found.count) ROMs found in \(String(format: "%.2f", scanTime))s ===")
        return found
    }

    // MARK: - MAME ROM Identification

    nonisolated private func applyMAMEIdentification(to rom: inout ROM, url: URL) {
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        
        if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
            applyUnifiedMAMEIdentification(to: &rom, entry: unifiedEntry, shortName: shortName)
            return
        }
        
        ROMScannerLog.debug("MAME lookup MISS for '\(shortName)' — not in any database, tagging as MAME Unplayable")
        rom.mameRomType = "unplayable"
        rom.isHidden = true
        rom.category = "unplayable"
    }
    
    nonisolated private func applyUnifiedMAMEIdentification(to rom: inout ROM, entry: MAMEUnifiedEntry, shortName: String) {
        if entry.isBIOS {
            rom.mameRomType = "bios"
            rom.name = entry.description
            rom.isHidden = false
            rom.isBios = true
            rom.category = "bios"
            ROMScannerLog.debug("MAME BIOS '\(shortName)' → '\(entry.description)' [cores: \(entry.compatibleCores.joined(separator: ", "))]")
        } else if entry.isRunnableInAnyCore {
            rom.mameRomType = "game"
            rom.name = entry.description
            rom.isHidden = false
            rom.category = "game"
            
            let bestCore = MAMEUnifiedService.shared.bestCore(for: shortName) ?? entry.compatibleCores.first ?? "mame"
            ROMScannerLog.debug("MAME SELECT '\(shortName)' → '\(entry.description)' [core:\(bestCore) compatible, cores: \(entry.compatibleCores.joined(separator: ", "))]")
            
            if rom.metadata == nil { rom.metadata = ROMMetadata() }
            rom.metadata?.title = entry.description
            rom.metadata?.year = entry.year
            rom.metadata?.developer = entry.manufacturer
            rom.metadata?.publisher = entry.manufacturer
            if let players = entry.players { rom.metadata?.players = players }
            
            if entry.isVertical {
                rom.metadata?.orientation = "vertical"
            } else if let orientation = entry.orientation {
                rom.metadata?.orientation = orientation
            }
            
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
            ROMScannerLog.debug("MAME HIDE '\(shortName)' → '\(entry.description)' [MAME Unplayable]")
        }
    }
    
    // MARK: - Extension Filtering
    
    private let nonROMExtensions: Set<String> = [
        "txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
        "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
        "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"
    ]
    
    nonisolated private func shouldSkipExtension(_ ext: String) -> Bool {
        // Safe to recreate locally for parallel nonisolated calls to avoid actor data isolation errors
        let nonROM: Set<String> = [
            "txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
            "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
            "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"
        ]
        return nonROM.contains(ext)
    }

    // MARK: - System Identification & Container Logic
    
    nonisolated private func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        ROMIdentifier.identifySystem(url: url, extension: ext)
    }

    // ACCESSIBLE FROM ROMLIBRARY
    nonisolated func getReferencedFiles(in url: URL) -> [URL] {
        ROMIdentifier.getReferencedFiles(in: url)
    }
    
    // ACCESSIBLE FROM ROMLIBRARY
    nonisolated func getIgnoredFiles(in folder: URL) -> Set<String> {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        var ignored = Set<String>()
         for file in files {
             let ext = file.pathExtension.lowercased()
             if ext == "cue" || ext == "m3u" {
                 let system = self.identifySystem(url: file, extension: ext)
                 if system?.isDiskBased == true {
                     let refs = ROMIdentifier.getReferencedFiles(in: file)
                     for ref in refs {
                         ignored.insert(ref.standardized.path)
                     }
                 }
             }
         }
        return ignored
    }

    // MARK: - XML Parsing Optimization
    
    nonisolated private func loadFolderMetadata(folder: URL) -> [String: ROMMetadata] {
        LoggerService.debug(category: "ROMScanner", "Loading XML metadata for folder: \(folder.path)")
        let xmlPath = folder.appendingPathComponent("games.xml")
        var metadataMap: [String: ROMMetadata] = [:]
        
        guard FileManager.default.fileExists(atPath: xmlPath.path),
              let doc = try? XMLDocument(contentsOf: xmlPath, options: []),
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
        let scanStart = Date()
        LoggerService.info(category: "ROMScanner", "=== LIGHTWEIGHT SCAN STARTED: \(folder.path) ===")

        resetCancellation()
        var found: [URL] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        let totalFiles = allURLs.count
        
        // Build ignored files efficiently
        var ignoredURLs = Set<String>()
        for url in allURLs {
            let ext = url.pathExtension.lowercased()
            if ext == "cue" || ext == "m3u" {
                let system = self.identifySystem(url: url, extension: ext)
                if system?.isDiskBased == true {
                    let refs = getReferencedFiles(in: url)
                    LoggerService.debug(category: "ROMScanner", "Found container file: \(url.lastPathComponent) referencing \(refs.count) files")
                    for ref in refs {
                        LoggerService.debug(category: "ROMScanner", "Ignoring referenced file inside \(url.lastPathComponent): \(ref.path)")
                        ignoredURLs.insert(ref.standardized.path)
                    }
                }
            }
        }

        let progressTracker = ProgressTracker(total: totalFiles, progressHandler: progress)

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
        LoggerService.info(category: "ROMScanner", "=== LIGHTWEIGHT SCAN COMPLETE: \(found.count) ROM files found in \(String(format: "%.2f", Date().timeIntervalSince(scanStart)))s ===")
        return found
    }
    // get a distinct list from all the extensions from all the systems in SystemDatabase.systems
    let romExtensions = Set(SystemDatabase.systems.flatMap { $0.extensions })

    func findFoldersWithROMs(baseURL: URL, maxDepth: Int) async -> [URL] {
        var foldersWithROMs: [URL] = []
        let fm = FileManager.default
        
        self.romExtensions
        
        guard let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        while let item = enumerator.nextObject() as? URL {
            guard let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else { continue }
            
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
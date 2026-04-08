import Foundation

/// Logger for ROMScanner - routes through LoggerService for timestamped file logging.
private enum ROMScannerLog {
    static func debug(_ message: String) { LoggerService.debug(category: "ROMScanner", message) }
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

    func scan(folder: URL, cancellationToken: ScanCancellationToken? = nil, progress: @escaping (Double) -> Void) async -> [ROM] {
        let scanStart = Date()
        LoggerService.info(category: "ROMScanner", "=== SCAN STARTED: \(folder.path) ===")
        
        resetCancellation()
        var found: [ROM] = []
        let fm = FileManager.default

        let enumStart = Date()
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        let enumTime = Date().timeIntervalSince(enumStart)
        LoggerService.info(category: "ROMScanner", "Enumeration: \(allURLs.count) files found in \(String(format: "%.2f", enumTime))s")
        
        // Split files: non-ZIPs first (fast), ZIPs last (slower due to fingerprinting)
        var nonZipURLs: [URL] = []
        var zipURLs: [URL] = []
        for url in allURLs {
            let ext = url.pathExtension.lowercased()
            if ext == "zip" || ext == "7z" {
                zipURLs.append(url)
            } else {
                nonZipURLs.append(url)
            }
        }
        // Process non-ZIPs first, then ZIPs
        let orderedURLs = nonZipURLs + zipURLs
        
        // --- NEW: Identify all referenced files to skip redundant entries (e.g., .bin files referenced by .cue) ---
        let ignoredStart = Date()
        var ignoredURLs = Set<String>()
        for url in allURLs {
            let refs = getReferencedFiles(in: url)
            for ref in refs {
                ignoredURLs.insert(ref.standardized.path)
            }
        }
        let ignoredTime = Date().timeIntervalSince(ignoredStart)
        LoggerService.info(category: "ROMScanner", "Ignored files build: \(ignoredURLs.count) ignored in \(String(format: "%.2f", ignoredTime))s")
        // --- END ---

        let total = Double(orderedURLs.count)
        var processed = 0

        // Throttle progress updates (every 50ms)
        var lastProgressUpdate = DispatchTime.now()
        let throttleNanos: UInt64 = 50_000_000 // 50ms
        
        // Timing counters
        var identifyTimeTotal: TimeInterval = 0
        var zipCount = 0
        var unknownCount = 0

        for url in orderedURLs {
            if isCancelled || (cancellationToken?.isCancelled ?? false) { break }

            processed += 1
            
            // --- NEW: Skip ignored files ---
            if ignoredURLs.contains(url.standardized.path) {
                continue
            }
            // --- END ---

            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastProgressUpdate.uptimeNanoseconds >= throttleNanos || processed == Int(total) {
                lastProgressUpdate = now
                progress(Double(processed) / max(total, 1))
            }

            // Use cached isRegularFile from enumerator properties
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Skip obviously non-ROM files (using static Set for O(1) lookup)
            if Self.shouldSkipExtension(ext) { continue }
            
            // Skip files inside .app bundles
            if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { continue }

            let identifyStart = Date()
            let system = identifySystem(url: url, extension: ext)
            let identifyTime = Date().timeIntervalSince(identifyStart)
            identifyTimeTotal += identifyTime
            
            if ext == "zip" || ext == "7z" { zipCount += 1 }
            
            let name = url.deletingPathExtension().lastPathComponent

            var rom = ROM(
                id: UUID(),
                name: name,
                path: url,
                systemID: system?.id
            )

            // Track unknown system files
            if system?.id == "unknown" {
                unknownCount += 1
            }

            // MARK: - BIOS Detection
            if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
                rom.isBios = true
                rom.isHidden = true
                rom.category = "bios"
            }

            // MARK: - MAME ROM Identification
            if system?.id == "mame" {
                applyMAMEIdentification(to: &rom, url: url)
            }

            rom.metadata = loadFromGamesXML(at: url)
            
            // Check for local boxart (skip for BIOS files)
            if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                rom.hasBoxArt = true
            }

            found.append(rom)
        }
        
        if unknownCount > 0 {
            LoggerService.info(category: "ROMScanner", "Unknown system files: \(unknownCount)")
        }

        // Final progress update
        progress(1.0)
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMScanner", "=== SCAN COMPLETE: \(found.count) ROMs found in \(String(format: "%.2f", scanTime))s ===")
        LoggerService.info(category: "ROMScanner", "Total identify time: \(String(format: "%.2f", identifyTimeTotal))s")
        LoggerService.info(category: "ROMScanner", "ZIPs processed: \(zipCount)")
        return found
    }

    // MARK: - MAME ROM Identification

    /// Apply MAME-specific identification using the unified mame_unified.json database.
    /// This uses fast O(1) shortname lookup and supports ALL MAME cores.
    ///
    /// Tagging rules:
    /// - If in any core and runnable → tag as "core:{bestCore} compatible", show in library
    /// - If BIOS → show in library, mark as BIOS
    /// - If not in any core OR not runnable in any core → hide, tag as "MAME Unplayable"
    private func applyMAMEIdentification(to rom: inout ROM, url: URL) {
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        
        // Try the unified MAME database first
        if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
            applyUnifiedMAMEIdentification(to: &rom, entry: unifiedEntry, shortName: shortName)
            return
        }
        
        // Not found in unified database - tag as unplayable
        ROMScannerLog.debug("MAME lookup MISS for '\(shortName)' — not in any database, tagging as MAME Unplayable")
        rom.mameRomType = "unplayable"
        rom.isHidden = true
        rom.category = "unplayable"
    }
    
    /// Apply identification using the unified MAME database (multi-core).
    private func applyUnifiedMAMEIdentification(to rom: inout ROM, entry: MAMEUnifiedEntry, shortName: String) {
        // Determine the type based on unified data
        if entry.isBIOS {
            rom.mameRomType = "bios"
            rom.name = entry.description
            rom.isHidden = false
            rom.isBios = true
            rom.category = "bios"
            ROMScannerLog.debug("MAME BIOS '\(shortName)' → '\(entry.description)' [cores: \(entry.compatibleCores.joined(separator: ", "))]")
        } else if entry.isRunnableInAnyCore {
            // Runnable in at least one core - show it
            rom.mameRomType = "game"
            rom.name = entry.description
            rom.isHidden = false
            rom.category = "game"
            
            // Find the best core (first runnable one)
            let bestCore = MAMEUnifiedService.shared.bestCore(for: shortName) ?? entry.compatibleCores.first ?? "mame"
            ROMScannerLog.debug("MAME SELECT '\(shortName)' → '\(entry.description)' [core:\(bestCore) compatible, cores: \(entry.compatibleCores.joined(separator: ", "))]")
            
            // Set metadata from unified database
            if rom.metadata == nil {
                rom.metadata = ROMMetadata()
            }
            rom.metadata?.title = entry.description
            rom.metadata?.year = entry.year
            rom.metadata?.developer = entry.manufacturer
            rom.metadata?.publisher = entry.manufacturer
            if let players = entry.players {
                rom.metadata?.players = players
            }
            
            // Store orientation info
            if entry.isVertical {
                rom.metadata?.orientation = "vertical"
            } else if let orientation = entry.orientation {
                rom.metadata?.orientation = orientation
            }
            
            // Store aspect ratio
            if let aspectX = entry.aspectX, let aspectY = entry.aspectY {
                rom.metadata?.aspectX = aspectX
                rom.metadata?.aspectY = aspectY
            }
            
            // Store screen dimensions
            rom.metadata?.screenWidth = entry.width
            rom.metadata?.screenHeight = entry.height
            rom.metadata?.refreshRate = entry.refreshRate
            rom.metadata?.screenType = entry.screenType
            
            // Store CPU info
            rom.metadata?.cpuName = entry.cpu
            rom.metadata?.audioChips = entry.audio
        } else {
            // Not runnable in any core - hide it
            rom.mameRomType = "unplayable"
            rom.isHidden = true
            rom.category = "unplayable"
            ROMScannerLog.debug("MAME HIDE '\(shortName)' → '\(entry.description)' [MAME Unplayable, cores: \(entry.compatibleCores.isEmpty ? "none" : entry.compatibleCores.joined(separator: ", "))]")
        }
    }
    
    // MARK: - Non-ROM File Extensions (static Set for O(1) lookup)
    
    private static let nonROMExtensions: Set<String> = [
        "txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
        "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
        "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"
    ]
    
    /// Returns true if this extension should be skipped during ROM scanning.
    private static func shouldSkipExtension(_ ext: String) -> Bool {
        nonROMExtensions.contains(ext)
    }
    
    // New: Trigger DAT download for any newly discovered systems
    func downloadDatsForDiscoveredSystems(_ systems: Set<String>) async {
        for sysID in systems {
            if let system = SystemDatabase.system(forID: sysID) {
                _ = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
            }
        }
    }

    // MARK: - System Identification (delegates to shared ROMIdentifier)

    private func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        ROMIdentifier.identifySystem(url: url, extension: ext)
    }

    // MARK: - Container Logic

    func getReferencedFiles(in url: URL) -> [URL] {
        ROMIdentifier.getReferencedFiles(in: url)
    }

    func getIgnoredFiles(in folder: URL) -> Set<String> {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        var ignored = Set<String>()
        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "cue" || ext == "m3u" {
                let refs = getReferencedFiles(in: file)
                for ref in refs {
                    ignored.insert(ref.standardized.path)
                }
            }
        }
        return ignored
    }

    // Scan only specific URLs (for smart rescan)
    func scan(urls: [URL], progress: @escaping (Double) -> Void) async -> [ROM] {
        let scanStart = Date()
        LoggerService.info(category: "ROMScanner", "=== SCAN STARTED (URLs): \(urls.count) files ===")
        resetCancellation()

        var found: [ROM] = []
        let total = Double(urls.count)
        var processed = 0
        let fm = FileManager.default

        // Throttle progress updates (every 50ms)
        var lastProgressUpdate = DispatchTime.now()
        let throttleNanos: UInt64 = 50_000_000 // 50ms

        var folderRefsCache: [URL: Set<String>] = [:]

        for url in urls {
            if isCancelled { break }

            processed += 1
            
            // --- NEW: Check if this file is referenced by a container in its folder ---
            let folder = url.deletingLastPathComponent()
            let ignored = folderRefsCache[folder] ?? {
                let refs = getIgnoredFiles(in: folder)
                folderRefsCache[folder] = refs
                return refs
            }()
            
            if ignored.contains(url.standardized.path) {
                continue
            }
            // --- END ---

            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastProgressUpdate.uptimeNanoseconds >= throttleNanos || processed == Int(total) {
                lastProgressUpdate = now
                progress(Double(processed) / max(total, 1))
            }

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Skip obviously non-ROM files
            let skip = ["txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
                        "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
                        "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"]
            if skip.contains(ext) { continue }
            
            // Skip files inside .app bundles
            if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { continue }

            let system = identifySystem(url: url, extension: ext)
            let name = url.deletingPathExtension().lastPathComponent

            var rom = ROM(
                id: UUID(),
                name: name,
                path: url,
                systemID: system?.id
            )

            // MARK: - BIOS Detection
            if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
                rom.isBios = true
                rom.isHidden = true
                rom.category = "bios"
            }

            rom.metadata = loadFromGamesXML(at: url)
            
            // Check for local boxart (skip for BIOS files)
            if !rom.isBios && fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                rom.hasBoxArt = true
            }

            found.append(rom)
        }

        // Final progress update
        progress(1.0)
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMScanner", "=== SCAN COMPLETE (URLs): \(found.count) ROMs found in \(String(format: "%.2f", scanTime))s ===")
        return found
    }

    // MARK: - Lightweight File Enumeration (for refresh)

    /// Returns file URLs in a folder that look like ROM files (extension-based filtering only).
    /// Performs NO system identification, MAME lookups, or metadata loading.
    /// Intended for refresh operations that only need to compare file paths.
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
            LoggerService.info(category: "ROMScanner", "=== LIGHTWEIGHT SCAN COMPLETE: 0 files (enumerator failed) ===")
            return []
        }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        let total = Double(allURLs.count)
        var processed = 0

        // Throttle progress updates (every 50ms)
        var lastProgressUpdate = DispatchTime.now()
        let throttleNanos: UInt64 = 50_000_000 // 50ms

        // Build set of referenced files to skip (from .cue/.m3u containers)
        let ignoredURLs = {
            var ignored = Set<String>()
            for url in allURLs {
                let refs = getReferencedFiles(in: url)
                for ref in refs {
                    ignored.insert(ref.standardized.path)
                }
            }
            return ignored
        }()

        for url in allURLs {
            if isCancelled { break }

            processed += 1

            // Throttled progress update
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastProgressUpdate.uptimeNanoseconds >= throttleNanos || processed == Int(total) {
                lastProgressUpdate = now
                progress(Double(processed) / max(total, 1))
            }

            // Skip referenced files
            if ignoredURLs.contains(url.standardized.path) {
                continue
            }

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Skip non-ROM extensions (same as full scan)
            let skip = ["txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
                        "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
                        "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"]
            if skip.contains(ext) { continue }

            // Skip files inside .app bundles
            if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { continue }

            found.append(url)
        }

        // Final progress update
        progress(1.0)
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMScanner", "=== LIGHTWEIGHT SCAN COMPLETE: \(found.count) ROM files found in \(String(format: "%.2f", scanTime))s ===")
        return found
    }

    // MARK: - Folder Discovery
    
    /// Find all subfolders (up to maxDepth levels deep) that contain at least one file
    /// that looks like it could be a ROM file.
    /// This is used to discover subfolders when a user adds a parent folder.
    func findFoldersWithROMs(baseURL: URL, maxDepth: Int) async -> [URL] {
        var foldersWithROMs: [URL] = []
        let fm = FileManager.default
        
        // Known extensions that indicate ROM files
        let romExtensions = Set([
            "nes", "sfc", "smc", "fig", "gb", "gbc", "gba", "md", "gen", "smd",
            "sms", "gg", "sg", "n64", "z64", "v64", "nds", "3ds", "psx", "cue",
            "bin", "iso", "img", "chd", "zip", "7z", "rom", "mgx", "st", "msa",
            "pce", "sgx", "ngp", "ngc", "ws", "wsc", "vb", "col", "rom", "a26",
            "a52", "a78", "lnx", "j64", "jag", "suf", "bs", "gcm", "rvz",
            "dos", "dosz", "conf", "bat", "com", "exe", "sou", "000", "001",
            "flac", "ogg", "wav", "scr", "dsk", "m3u"
        ])
        
        // Skip non-ROM extensions
        let skipExtensions = Set([
            "txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3",
            "mp4", "avi", "mkv", "nfo", "dat", "db", "json", "ico", "svg",
            "html", "css", "js", "py", "pyc", "pyo", "md", "pdf", "doc", "docx"
        ])
        
        guard let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        while let item = enumerator.nextObject() as? URL {
            // Get resource values to determine if it's a directory or file
            guard let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else { continue }
            
            if resourceValues.isDirectory == true {
                // Calculate depth from base URL
                let relativePath = item.path.replacingOccurrences(of: baseURL.path, with: "")
                let segments = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }
                guard segments.count <= maxDepth else { continue }
                
                // Check if this folder contains ROM files (shallow check - only direct children)
                var hasROMFiles = false
                do {
                    let contents = try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    for file in contents {
                        let ext = file.pathExtension.lowercased()
                        if romExtensions.contains(ext) && !skipExtensions.contains(ext) {
                            hasROMFiles = true
                            break
                        }
                        // For ZIP files, also count them as potential ROMs
                        if ext == "zip" || ext == "7z" {
                            hasROMFiles = true
                            break
                        }
                    }
                } catch {
                    continue
                }
                
                if hasROMFiles {
                    foldersWithROMs.append(item)
                }
            }
        }
        
        return foldersWithROMs.sorted { $0.path < $1.path }
    }

    private func loadFromGamesXML(at romURL: URL) -> ROMMetadata? {
        let folder = romURL.deletingLastPathComponent()
        let xmlPath = folder.appendingPathComponent("games.xml")
        guard let doc = try? XMLDocument(contentsOf: xmlPath, options: []),
              let root = doc.rootElement(),
              let games = root.children as? [XMLElement] else { return nil }
        
        let relPath = "./\(romURL.lastPathComponent)"
        
        guard let gameNode = games.first(where: { node in
            node.name == "game" && node.elements(forName: "path").first?.stringValue == relPath
        }) else { return nil }
        
        var meta = ROMMetadata()
        meta.title = gameNode.elements(forName: "name").first?.stringValue
        meta.year = gameNode.elements(forName: "year").first?.stringValue
        meta.publisher = gameNode.elements(forName: "publisher").first?.stringValue
        meta.developer = gameNode.elements(forName: "developer").first?.stringValue
        meta.genre = gameNode.elements(forName: "genre").first?.stringValue
        meta.description = gameNode.elements(forName: "desc").first?.stringValue
        
        return meta
    }
}

import Foundation

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

    func scan(folder: URL, progress: @escaping (Double) -> Void) async -> [ROM] {
        resetCancellation()
        var found: [ROM] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        
        // --- NEW: Identify all referenced files to skip redundant entries (e.g., .bin files referenced by .cue) ---
        var ignoredURLs = Set<String>()
        for url in allURLs {
            let refs = getReferencedFiles(in: url)
            for ref in refs {
                ignoredURLs.insert(ref.standardized.path)
            }
        }
        // --- END ---

        let total = Double(allURLs.count)
        var processed = 0

        // Throttle progress updates (every 50ms)
        var lastProgressUpdate = DispatchTime.now()
        let throttleNanos: UInt64 = 50_000_000 // 50ms

        for url in allURLs {
            if isCancelled { break }

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

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            // Skip obviously non-ROM files
            let skip = ["txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json"]
            if skip.contains(ext) { continue }

            let system = identifySystem(url: url, extension: ext)
            let name = url.deletingPathExtension().lastPathComponent

            var rom = ROM(
                id: UUID(),
                name: name,
                path: url,
                systemID: system?.id
            )

            // Load local metadata if exists
            if let data = try? Data(contentsOf: rom.infoLocalPath) {
                if let meta = try? JSONDecoder().decode(ROMMetadata.self, from: data) {
                    rom.metadata = meta
                }
            }
            
            // Try games.xml if no individual JSON found
            if rom.metadata == nil {
                rom.metadata = loadFromGamesXML(at: url)
            }
            
            // Check for local boxart
            if fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                rom.boxArtPath = rom.boxArtLocalPath
            }

            found.append(rom)
        }

        // Final progress update
        progress(1.0)
        return found
    }

    // New: Look for .dat files in the folder and its subfolders to register them
    func registerDats(in folderURL: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "dat" {
                // Try to infer system from filename
                let filename = url.lastPathComponent.lowercased()
                for system in SystemDatabase.systems {
                    if filename.contains(system.id.lowercased()) || filename.contains(system.name.lowercased()) {
                        ROMIdentifierService.shared.loadDatFile(url: url, forSystem: system.id)
                    }
                }
            }
        }
    }

    // MARK: - System Identification

    private func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        // 1. For ZIP files, peek inside to determine if it's MAME or a known compressed ROM
        if ext == "zip" || ext == "7z" {
            return identifyArchive(url: url)
        }

        // 2. Try to identify by filename hints (e.g. "(PS1)" or "SLES-00918")
        if let systemID = detectSystemFromFilename(url.lastPathComponent) {
            if let system = SystemDatabase.system(forID: systemID) {
                return system
            }
        }

        // 3. For CD-based or ambiguous extensions, peek at the header
        let ambiguous = ["cue", "bin", "iso", "img"]
        if ambiguous.contains(ext) {
            if let systemID = peekSystemID(url: url) {
                if let system = SystemDatabase.system(forID: systemID) {
                    return system
                }
            }
        }

        // 4. Fallback to extension matching
        return SystemDatabase.system(forExtension: ext)
    }

    private func detectSystemFromFilename(_ filename: String) -> String? {
        let upper = filename.uppercased()
        
        // Explicit tags
        if upper.contains("(PS1)") || upper.contains("[PS1]") || upper.contains("(PSX)") {
            return "psx"
        }
        if upper.contains("(SATURN)") || upper.contains("[SATURN]") {
            return "saturn"
        }
        if upper.contains("(GENESIS)") || upper.contains("(MEGA DRIVE)") {
            return "genesis"
        }
        
        // PS1 Serials: SCES, SLES, SLUS, SCUS, SLPS, SLPM, SCPH followed by 5 digits
        let ps1Regex = try? NSRegularExpression(pattern: "(S[CL][EP][SM]|SCPH)-\\d{5}", options: [])
        if let regex = ps1Regex, regex.firstMatch(in: upper, options: [], range: NSRange(location: 0, length: upper.count)) != nil {
            return "psx"
        }
        
        return nil
    }

    private func peekSystemID(url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        
        if ext == "cue" {
            // Read cue and find first file
            let referenced = getReferencedFiles(in: url)
            if let firstBin = referenced.first {
                debugPrint("Checking bin found in cue: \(firstBin.path)")
                return peekHeader(url: firstBin)
            }
        } else {
            return peekHeader(url: url)
        }
        return nil
    }

    // MARK: - Container Logic

    private func getReferencedFiles(in url: URL) -> [URL] {
        let ext = url.pathExtension.lowercased()
        var referenced: [URL] = []
        
        if ext == "cue" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.uppercased().hasPrefix("FILE") {
                    let scanner = Scanner(string: trimmed)
                    _ = scanner.scanString("FILE")
                    var filename: NSString?
                    if scanner.scanString("\"") != nil {
                        _ = scanner.scanUpTo("\"", into: &filename)
                    } else {
                        // Fallback to reading until next whitespace or end
                        var temp: String = ""
                        while !scanner.isAtEnd {
                            if let char = scanner.scanCharacter() {
                                if char.isWhitespace && !temp.isEmpty { break }
                                if !char.isWhitespace { temp.append(char) }
                            } else { break }
                        }
                        filename = temp as NSString
                    }
                    
                    if let name = filename as String? {
                        let fileURL = url.deletingLastPathComponent().appendingPathComponent(name)
                        referenced.append(fileURL)
                    }
                }
            }
        } else if ext == "m3u" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    let fileURL = url.deletingLastPathComponent().appendingPathComponent(trimmed)
                    referenced.append(fileURL)
                }
            }
        }
        
        return referenced
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

    private func peekHeader(url: URL) -> String? {
        // Ensure file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }
        
        // Read up to 0x9400 bytes to cover both 2048 and 2352 sector sizes for PS1
        guard let data = try? fileHandle.read(upToCount: 0x9400) else { return nil }
        
        // 1. Check Sega Saturn (at 0x0) - "SEGA SEGASATURN"
        let saturnMagic = "SEGA SEGASATURN"
        if data.count >= saturnMagic.count {
            if let str = String(data: data.prefix(saturnMagic.count), encoding: .ascii),
               str == saturnMagic {
                return "saturn"
            }
        }
        
        // 2. Check Sega Genesis (at 0x100) - "SEGA"
        if data.count >= 0x104 {
            let genesisMagic = "SEGA"
            let slice = data[0x100..<0x104]
            if let str = String(data: slice, encoding: .ascii),
               str == genesisMagic {
                return "genesis"
            }
        }
        
        // 3. Check PS1 (at 0x8008 or 0x9318) - "PLAYSTATION"
        let ps1Magic = "PLAYSTATION"
        // Check 2048 sector PVD
        if data.count >= 0x8008 + ps1Magic.count {
            let slice = data[0x8008..<0x8008 + ps1Magic.count]
            if let str = String(data: slice, encoding: .ascii),
               str.contains(ps1Magic) {
                return "psx"
            }
        }
        // Check 2352 sector PVD
        if data.count >= 0x9318 + ps1Magic.count {
            let slice = data[0x9318..<0x9318 + ps1Magic.count]
            if let str = String(data: slice, encoding: .ascii),
               str.contains(ps1Magic) {
                return "psx"
            }
        }
        
        return nil
    }


    private func identifyArchive(url: URL) -> SystemInfo? {
        // Check if zip is in a folder named after a known MAME system
        let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
        if parentName.contains("mame") || parentName.contains("arcade") || parentName.contains("fba") {
            return SystemDatabase.system(forID: "mame")
        }

        // Try to peek at zip contents for known inner extensions
        if let innerExt = peekInsideZip(url: url) {
            return SystemDatabase.system(forExtension: innerExt)
        }

        // Default ZIP to MAME (arcade) since that's most common for ZIPs
        return SystemDatabase.system(forID: "mame")
    }

    private func peekInsideZip(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 30 else { return nil }

        // Helpers to read little-endian integers safely without alignment assumptions
        func readLEUInt16(_ start: Int) -> UInt16? {
            guard start + 2 <= data.count else { return nil }
            var value: UInt16 = 0
            for i in 0..<2 { value |= UInt16(data[start + i]) << (8 * i) }
            return value
        }

        func readLEUInt32(_ start: Int) -> UInt32? {
            guard start + 4 <= data.count else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 { value |= UInt32(data[start + i]) << (8 * i) }
            return value
        }

        var offset = 0
        let localHeaderSig: UInt32 = 0x04034b50 // ZIP local file header signature

        while true {
            guard offset + 30 <= data.count else { break }
            guard let sig = readLEUInt32(offset), sig == localHeaderSig else { break }

            // Local file header fields
            guard let compressedSize = readLEUInt32(offset + 18),
                  let fileNameLen = readLEUInt16(offset + 26),
                  let extraLen = readLEUInt16(offset + 28) else { break }

            let nameLen = Int(fileNameLen)
            let extra = Int(extraLen)
            let comp = Int(compressedSize)

            // Validate bounds for filename
            guard offset + 30 + nameLen <= data.count else { break }
            let nameData = data[offset + 30 ..< offset + 30 + nameLen]
            if let name = String(data: nameData, encoding: .utf8) {
                let innerExt = URL(fileURLWithPath: name).pathExtension.lowercased()
                if !innerExt.isEmpty, let system = SystemDatabase.system(forExtension: innerExt) {
                    return system.extensions.first
                }
            }

            // Advance to next header: fixed(30) + name + extra + data
            let next = offset + 30 + nameLen + extra + comp
            guard next > offset else { break } // avoid infinite loops on malformed input
            offset = next
        }

        return nil
    }

    // Scan only specific URLs (for smart rescan)
    func scan(urls: [URL], progress: @escaping (Double) -> Void) async -> [ROM] {
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
            let skip = ["txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json"]
            if skip.contains(ext) { continue }

            let system = identifySystem(url: url, extension: ext)
            let name = url.deletingPathExtension().lastPathComponent

            var rom = ROM(
                id: UUID(),
                name: name,
                path: url,
                systemID: system?.id
            )

            // Load local metadata if exists
            if let data = try? Data(contentsOf: rom.infoLocalPath) {
                if let meta = try? JSONDecoder().decode(ROMMetadata.self, from: data) {
                    rom.metadata = meta
                }
            }
            
            // Try games.xml if no individual JSON found
            if rom.metadata == nil {
                rom.metadata = loadFromGamesXML(at: url)
            }
            
            // Check for local boxart
            if fm.fileExists(atPath: rom.boxArtLocalPath.path) {
                rom.boxArtPath = rom.boxArtLocalPath
            }

            found.append(rom)
        }

        // Final progress update
        progress(1.0)
        return found
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

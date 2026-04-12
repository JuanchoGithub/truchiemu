import Foundation

/// Shared ROM system identification utility that both ROMScanner and ROMLibrary use.
/// Uses a weighted scoring system to determine the most likely system based on 
/// Magic Headers, Unique Extensions, Filename Patterns, and Path Context.
enum ROMIdentifier {

    // MARK: - Public Entry Point

    static func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        let filename = url.lastPathComponent.lowercased()
        let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
        let extLower = ext.lowercased()
        
        // Dictionary to track potential matches: [SystemID: ConfidenceScore]
        var candidates: [String: Int] = [:]

        // --- TIER 1: Magic Headers (Highest Confidence: 100 pts) ---
        // We check headers for ambiguous extensions (ISO, BIN, CUE, etc.)
        let ambiguous = ["cue", "bin", "iso", "img"]
        if ambiguous.contains(extLower) {
            if let headerID = peekSystemID(url: url) {
                candidates[headerID, default: 0] += 100
                LoggerService.debug(category: "ROMIdentifier", "Magic Header match for \(url.lastPathComponent): \(headerID)")
            }
        }

        // --- TIER 2: Archive Analysis (High Confidence: 90 pts) ---
        if extLower == "zip" || extLower == "7z" {
            if let archiveSystem = identifyArchive(url: url) {
                candidates[archiveSystem.id, default: 0] += 90
                LoggerService.debug(category: "ROMIdentifier", "Archive match for \(url.lastPathComponent): \(archiveSystem.id)")
            }
        }

        // --- TIER 3: Iterative Scoring via SystemDatabase ---
        // We loop through all known systems to accumulate scores based on metadata
        let allSystems: [systemsROMFindInfo] = SystemDatabase.loadsystemsROMFindInfo()
        
        for system in allSystems {
            // 1. Extension Matching (Weights: 80 for unique, 40 for shared)
            if system.extensions.contains(extLower) {
                let isUnique = allSystems.filter { $0.extensions.contains(extLower) }.count == 1
                candidates[system.id, default: 0] += isUnique ? 80 : 40
            }
            
            // 2. Path Contextual Matching
            // Instead of relying on a pre-defined list, let's treat the folder 
            // name as a direct match for the System ID itself (Weight: 70)
            if parentName == system.id.lowercased() {
                candidates[system.id, default: 0] += 70
                LoggerService.debug(category: "ROMIdentifier", "Folder name matches System ID: \(system.id)")
            } else {
                // Fallback to checking keywords if the folder name isn't an exact ID match
                for keyword in system.pathKeywords {
                    if parentName.contains(keyword.lowercased()) {
                        LoggerService.debug(category: "ROMIdentifier", "Path keyword match for \(url.lastPathComponent): \(system.id)")
                        candidates[system.id, default: 0] += 30
                        break
                    }
                }
            }
            
            // 3. Filename Pattern Matching (Weight: 50)
            for pattern in system.filenamePatterns {
                if filename.contains(pattern.lowercased()) {
                    LoggerService.debug(category: "ROMIdentifier", "Filename pattern match for \(url.lastPathComponent): \(system.id)")
                    candidates[system.id, default: 0] += 50
                    break 
                }
            }
        }

        // --- TIER 4: MAME Lookup (Specialized: 90 pts) ---
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        if let mameEntry = MAMEUnifiedService.shared.lookup(shortName: shortName), 
           mameEntry.isRunnableInAnyCore && !mameEntry.isBIOS {
            candidates["mame", default: 0] += 90
            LoggerService.debug(category: "ROMIdentifier", "MAME lookup match for \(url.lastPathComponent): \(mameEntry.shortName)")
        }

        // --- FINAL DECISION ---
        // Sort candidates by score descending
        let sortedCandidates = candidates.sorted { $0.value > $1.value }
        
        if let winner = sortedCandidates.first, winner.value >= 30 {
            // If we found a high-confidence match, return it
            LoggerService.debug(category: "ROMIdentifier", "High confidence match for \(url.lastPathComponent): \(winner.key) with score \(winner.value)")
            return SystemDatabase.system(forID: winner.key)
        }

        // NEW FALLBACK: Check if the parent folder name is a valid System ID
        if let folderSystem = SystemDatabase.system(forID: parentName) {
            LoggerService.debug(category: "ROMIdentifier", "No scoring match, but folder name '\(parentName)' is a valid System ID.")
            return folderSystem
        }

        // Fallback: If no high-confidence match, try the standard extension lookup
        LoggerService.debug(category: "ROMIdentifier", "No high confidence match for \(url.lastPathComponent), trying standard extension lookup")
        return SystemDatabase.system(forExtension: extLower)
    }

    // MARK: - Archive Identification

    private static func identifyArchive(url: URL) -> SystemInfo? {
        let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()

        // Quick Path Check for Archives
        if parentName.contains("mame") || parentName.contains("arcade") || parentName.contains("fba") || parentName.contains("fbneo") {
            LoggerService.debug(category: "ROMIdentifier", "Archive path match for \(url.lastPathComponent): mame")
            return SystemDatabase.system(forID: "mame")
        }
        if parentName.contains("dos") || parentName.contains("dosbox") || parentName.contains("pc") {
            LoggerService.debug(category: "ROMIdentifier", "Archive path match for \(url.lastPathComponent): dos")
            return SystemDatabase.system(forID: "dos")
        }
        if parentName.contains("scummvm") || parentName.contains("scumm") {
            LoggerService.debug(category: "ROMIdentifier", "Archive path match for \(url.lastPathComponent): scummvm")
            return SystemDatabase.system(forID: "scummvm")
        }
        if parentName.contains("32x") || parentName.contains("genesis32x") || parentName.contains("sega32x") {
            LoggerService.debug(category: "ROMIdentifier", "Archive path match for \(url.lastPathComponent): 32x")
            return SystemDatabase.system(forID: "32x")
        }

        if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
            LoggerService.debug(category: "ROMIdentifier", "Archive path match for \(url.lastPathComponent): BIOS")
            return nil
        }

        // Deep inspection of archive contents
        return fingerprintArchive(url: url)
    }

    // MARK: - Content Fingerprinting

    private static func fingerprintArchive(url: URL) -> SystemInfo? {
        guard let files = peekInsideZipFiles(url: url) else { return nil }

        let systemDB = SystemDatabase.loadSystems()
        let consoleExts = Set(systemDB.flatMap { $0.extensions })
        
        for file in files {
            let fileExt = URL(fileURLWithPath: file).pathExtension.lowercased()
            // find the extension using the unique list from consoleExts
            if consoleExts.contains(fileExt) {
                if let system = systemDB.first(where: { $0.extensions.contains(fileExt) }) {
                    LoggerService.debug(category: "ROMIdentifier", "Archive file extension match for \(url.lastPathComponent): \(system.id)")
                    return system
                }
            }
        }

        // ScummVM Specific Detection
        let scummvmInnerExtensions: Set<String> = ["sou", "000", "001", "flac", "ogg", "wav"]
        let scummvmGameIndicators: Set<String> = [
            "HE", "MI", "SAM", "DAY", "DIG", "TENTACLE", "COMI", "MONKEY", "INDY",
            "MANIAC", "ZAK", "LOOM", "GROUSE", "FULLTHROTTLE", "CURSE", "GRIM",
            "ESCAPE", "BENEATH", "BEYOND", "LAURA", "DRACI"
        ]
        
        for file in files {
            let fileURL = URL(fileURLWithPath: file)
            let ext = fileURL.pathExtension.lowercased()
            let nameWithoutExt = fileURL.deletingPathExtension().lastPathComponent.uppercased()

            if scummvmInnerExtensions.contains(ext) { 
                LoggerService.debug(category: "ROMIdentifier", "Archive file extension match for \(url.lastPathComponent): scummvm")
                return SystemDatabase.system(forID: "scummvm") 
            }
            if scummvmGameIndicators.contains(where: { nameWithoutExt.contains($0) }) { 
                LoggerService.debug(category: "ROMIdentifier", "Archive file name match for \(url.lastPathComponent): scummvm")
                return SystemDatabase.system(forID: "scummvm") 
            }
        }

        // MAME Style Detection (lots of tiny files, often no extension)
        let mameInnerExtensions: Set<String> = ["bin", "rom", "a", "b", "c", "d", "e", "f"]
        let mameStyleCount = files.filter { file in
            let fileURL = URL(fileURLWithPath: file)
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            LoggerService.debug(category: "ROMIdentifier", "Archive file extension match for \(url.lastPathComponent): \(ext)")
            return (name.count <= 15 && ext.isEmpty) || ext == "bin" || ext == "rom" || mameInnerExtensions.contains(ext)
        }.count

        if mameStyleCount > 1 { return SystemDatabase.system(forID: "mame") }
        
        return nil
    }

    // MARK: - Fast Header Peeking

    private static func peekSystemID(url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        if ext == "cue" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.uppercased().hasPrefix("FILE") {
                    let scanner = Scanner(string: trimmed)
                    _ = scanner.scanString("FILE")
                    var filename: NSString?
                    if scanner.scanString("\"") != nil {
                        if let scanned = scanner.scanUpToString("\"") { filename = scanned as NSString }
                    }
                    if let name = filename as String? {
                        let fileURL = url.deletingLastPathComponent().appendingPathComponent(name)
                        return peekHeader(url: fileURL)
                    }
                }
            }
            return nil
        } else {
            LoggerService.debug(category: "ROMIdentifier", "Checking file header for \(url.lastPathComponent),")
            return peekHeader(url: url)
        }
    }

    private static func peekHeader(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            // Check Saturn at 0x0
            if let data = try handle.read(upToCount: 15), String(data: data, encoding: .ascii) == "SEGA SEGASATURN" {
                LoggerService.debug(category: "ROMIdentifier", "Saturn header match for \(url.lastPathComponent)")
                return "saturn"
            }

            // Check 32X & Genesis at 0x100
            try handle.seek(toOffset: 0x100)
            if let data = try handle.read(upToCount: 8) {
                if data.count >= 8, String(data: data, encoding: .ascii) == "SEGA 32X" { 
                    LoggerService.debug(category: "ROMIdentifier", "32X header match for \(url.lastPathComponent)")
                    return "32x" 
                    }
                if data.count >= 4, String(data: data.prefix(4), encoding: .ascii) == "SEGA" { 
                    LoggerService.debug(category: "ROMIdentifier", "Genesis header match for \(url.lastPathComponent)")
                    return "genesis" 
                }
            }

            // Check PS1 at 0x8008 or 0x9318
            let ps1Offsets: [UInt64] = [0x8008, 0x9318]
            for offset in ps1Offsets {
                try handle.seek(toOffset: offset)
                if let data = try handle.read(upToCount: 11), String(data: data, encoding: .ascii) == "PLAYSTATION" {
                    LoggerService.debug(category: "ROMIdentifier", "PS1 header match for \(url.lastPathComponent)")
                    return "psx"
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Fast ZIP Peeking

    private static func peekInsideZipFiles(url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 65536), data.count >= 30 else { return nil }

        func readLEUInt16(_ start: Int) -> UInt16? {
            guard start + 2 <= data.count else { return nil }
            var value: UInt16 = 0
            for i in 0..<2 { value |= UInt16(data[start + i]) << (8 * i) }
            LoggerService.extreme(category: "ROMIdentifier", "Read LE UInt16 at offset \(start): \(value)")
            return value
        }

        func readLEUInt32(_ start: Int) -> UInt32? {
            guard start + 4 <= data.count else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 { value |= UInt32(data[start + i]) << (8 * i) }
            LoggerService.extreme(category: "ROMIdentifier", "Read LE UInt32 at offset \(start): \(value)")
            return value
        }

        var filenames: [String] = []
        var offset = 0
        let localHeaderSig: UInt32 = 0x04034b50
        let maxEntries = 50

        while filenames.count < maxEntries {
            guard offset + 30 <= data.count else { break }
            guard let sig = readLEUInt32(offset), sig == localHeaderSig else { break }

            guard let fileNameLen = readLEUInt16(offset + 26),
                  let extraLen = readLEUInt16(offset + 28),
                  let compressedSize = readLEUInt32(offset + 18) else { break }

            let nameLen = Int(fileNameLen)
            let extra = Int(extraLen)
            let comp = Int(compressedSize)

            guard offset + 30 + nameLen <= data.count else { break }
            let nameData = data[offset + 30 ..< offset + 30 + nameLen]
            if let name = String(data: nameData, encoding: .utf8), !name.hasSuffix("/") {
                LoggerService.extreme(category: "ROMIdentifier", "Read filename at offset \(offset + 30): \(name)")
                filenames.append(name)
            }

            let next = offset + 30 + nameLen + extra + comp
            guard next > offset else { break }
            offset = next
        }

        LoggerService.extreme(category: "ROMIdentifier", "Read filenames: \(filenames)")
        return filenames.isEmpty ? nil : filenames
    }

    // MARK: - Container Logic

    static func getReferencedFiles(in url: URL) -> [URL] {
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
                        if let scanned = scanner.scanUpToString("\"") { filename = scanned as NSString }
                    } else {
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
}

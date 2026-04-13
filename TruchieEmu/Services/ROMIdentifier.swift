import Foundation

/// Shared ROM system identification utility that both ROMScanner and ROMLibrary use.
/// Uses a weighted scoring system to determine the most likely system based on 
/// Magic Headers, Unique Extensions, Filename Patterns, and Path Context.
enum ROMIdentifier {

    // MARK: - Private Properties

    private static let cachedSystems:[SystemInfo] = {
        let systems = SystemDatabase.systems
        return systems.isEmpty ? SystemDatabase.loadSystems() : systems
    }()

    private static func normalize(extension ext: String) -> String {
        return ext.lowercased().replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cached set of extensions that are shared by more than one system.
    private static let ambiguousExtensions: Set<String> = {
        let counts = cachedSystems.flatMap { $0.extensions }.reduce(into: [String: Int]()) { counts, ext in
            counts[normalize(extension: ext), default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.map { $0.key })
    }()

    // MARK: - Public Entry Point

    static func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        let filename = url.lastPathComponent.lowercased()
        let extLower = normalize(extension: ext)
        
        // Get all parent folder names for path context
        let parentNames = url.deletingLastPathComponent().pathComponents.map { $0.lowercased() }
        LoggerService.debug(category: "ROMIdentifier", "Analyzing \(filename) (ext: \(extLower)) with parents: \(parentNames)")
        
        // Dictionary to track potential matches: [SystemID: ConfidenceScore]
        var candidates: [String: Int] = [:]

        // 1. Magic Headers (Highest Confidence: 100 pts)
        let ambiguousSystems = cachedSystems.filter { system in 
            system.extensions.contains { normalize(extension: $0) == extLower }
        }
        let isAmbiguous = ambiguousSystems.count > 1
        LoggerService.debug(category: "ROMIdentifier", "Extension for file \(filename): '\(extLower)' is \(isAmbiguous ? "ambiguous" : "unique") with \(ambiguousSystems.count) matching systems: \(ambiguousSystems.map { $0.id })")
        if isAmbiguous {
            if let headerID = peekSystemID(url: url, systems: ambiguousSystems) {
                candidates[headerID, default: 0] += 100
                LoggerService.debug(category: "ROMIdentifier", "Magic Header match for \(filename): \(headerID)")
            }
        } else {
            LoggerService.debug(category: "ROMIdentifier", "Skipping magic header check for \(filename) due to unique extension '\(extLower)'")
        }

        // 2. Archive Analysis (High Confidence: 90 pts)
        let archiveFormats = ["zip", "7z"]
        if archiveFormats.contains(extLower) {
            if let archiveSystem = identifyArchive(url: url) {
                candidates[archiveSystem.id, default: 0] += 90
                LoggerService.debug(category: "ROMIdentifier", "Archive match for \(filename): \(archiveSystem.id)")
            }
        } else {
            LoggerService.debug(category: "ROMIdentifier", "Skipping archive analysis for \(filename) since it's not a recognized archive (\(archiveFormats.joined(separator: ", "))) format ('\(extLower)')")
        }

        // 3. Metadata Scoring (Extension & Path)
        scoreByMetadata(url: url, extLower: extLower, parentNames: parentNames, candidates: &candidates)
        
        //3.5 CD-based System Detection (PS1/PS2) via SYSTEM.CNF
        if ["bin", "iso", "img", "cue"].contains(extLower) {
            LoggerService.debug(category: "ROMIdentifier", "File \(filename) has CD-based extension '\(extLower)', attempting disc-based system identification")
            identifyDiscSystem(url: url, candidates: &candidates)
        } else {
            LoggerService.debug(category: "ROMIdentifier", "Skipping disc-based system identification for \(filename) since it's not a CD-based extension")
        }

        // 4. MAME Lookup (Specialized: 90 pts)
        if extLower == "zip" {
            scoreByMAME(url: url, candidates: &candidates)
        } else {
            LoggerService.debug(category: "ROMIdentifier", "Skipping MAME lookup for \(filename) since it's not a ZIP archive (extension: '\(extLower)')")
        }

        // --- FINAL DECISION ---
        var sortedCandidates = candidates.sorted { $0.value > $1.value }
        LoggerService.debug(category: "ROMIdentifier", "Candidate scores for \(filename): \(sortedCandidates)")

        //if the order of candidates is MAME then NeoGeo, choose NeoGeo
        if sortedCandidates.first?.key == "mame", let second = sortedCandidates.dropFirst().first, second.key == "neogeo" {
            // swap scores to prefer Neo Geo
            candidates["neogeo", default: 0] += candidates["mame", default: 0] + 10 // give Neo Geo a boost over MAME
            sortedCandidates = candidates.sorted { $0.value > $1.value }
            LoggerService.debug(category: "ROMIdentifier", "Adjusting scores for \(filename) to prefer Neo Geo over MAME when both are present, new scores: \(sortedCandidates)")
        }

        
        if let winner = sortedCandidates.first, winner.value >= 30 {
            LoggerService.debug(category: "ROMIdentifier", "High confidence match for \(filename): \(winner.key) (\(winner.value) pts)")
            return cachedSystems.first { $0.id == winner.key } ?? SystemDatabase.system(forID: winner.key)
        }

        // Fallback 1: Check if any parent folder name is a valid System ID
        if let folderSystem = parentNames.lazy.compactMap({ name in cachedSystems.first(where: { $0.id.lowercased() == name }) }).first {
            LoggerService.debug(category: "ROMIdentifier", "Fallback: Folder name match for \(filename): \(folderSystem.id)")
            return folderSystem
        }

        // Fallback 2: Standard extension lookup
        LoggerService.debug(category: "ROMIdentifier", "Fallback: Standard extension lookup for \(filename)")
        return cachedSystems.first { system in
            system.extensions.contains { normalize(extension: $0) == extLower }
        } ?? SystemDatabase.system(forExtension: extLower)
    }

// MARK: - ISO Scanning for CD-based Systems
struct ISOScanner {
    
    /// Reads the ISO and attempts to locate and extract the content of "SYSTEM.CNF"
    static func extractSystemConfig(from url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }
        
        // ISO9660 Directory Records start after the Primary Volume Descriptor.
        // For most PS1/PS2 images, we can scan the first 1MB for the "SYSTEM.CNF" filename.
        // It's a crude but highly effective "cheat" method.
        let scanRange = 1_024 * 1_024 // 1MB scan
        guard let data = try? fileHandle.read(upToCount: scanRange) else { return nil }
        
        let targetName = "SYSTEM.CNF;1".data(using: .ascii)!
        
        // Search for the filename string in the raw data
        guard let range = data.range(of: targetName) else {
            LoggerService.debug(category: "ROMIdentifier", "SYSTEM.CNF not found in first 1MB of ISO \(url.lastPathComponent)")
            return nil
        }
        
        // The Directory Record contains the Logical Block Number (LBN) 
        // where the file starts. In ISO9660, the LBN is at a specific offset 
        // relative to the filename.
        let lbnOffset = range.lowerBound - 10
        guard lbnOffset > 0 else { return nil }
        
        // Extract the 4-byte LBN (Little Endian)
        let lbnData = data.subdata(in: lbnOffset..<lbnOffset+4)
        let lbn = lbnData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // The ISO9660 block size is 2048 bytes
        let fileOffset = UInt64(lbn) * 2048
        
        // Seek to that offset and read the file
        try? fileHandle.seek(toOffset: fileOffset)
        guard let fileData = try? fileHandle.read(upToCount: 2048) else { return nil }
        LoggerService.debug(category: "ROMIdentifier", "Extracted SYSTEM.CNF from ISO \(url.lastPathComponent) at offset \(fileOffset), file data: \(fileData)")
        return String(data: fileData, encoding: .ascii)
    }
}

static func identifyDiscSystem(url: URL, candidates: inout [String: Int]) -> String? {
    LoggerService.debug(category: "ROMIdentifier", "Attempting disc-based system identification for \(url.lastPathComponent)")
    guard let config = ISOScanner.extractSystemConfig(from: url) else {
        // If SYSTEM.CNF is missing, check for PARAM.SFO (PSP)
        if hasPSPParameterFile(url: url) { 
            LoggerService.debug(category: "ROMIdentifier", "PARAM.SFO found in ISO \(url.lastPathComponent) without SYSTEM.CNF, strongly indicating PSP")
            candidates["psp", default: 0] += 100
            return "psp" 
        }
        return nil
    }
    
    // hardcoded for PS1 and PS2
    if config.contains("BOOT2") {
        LoggerService.debug(category: "ROMIdentifier", "Identified SYSTEM.CNF with BOOT2 for \(url.lastPathComponent), strongly indicating PS2 -> \(config)")
        candidates["ps2", default: 0] += 100
        return "ps2"
    } else if config.contains("BOOT") {
        LoggerService.debug(category: "ROMIdentifier", "Identified SYSTEM.CNF with BOOT for \(url.lastPathComponent), strongly indicating PS1 (but could be PS2) -> \(config)")
        candidates["ps1", default: 0] += 70
        candidates["psx", default: 0] += 70
        return "psx"
    }
    LoggerService.debug(category: "ROMIdentifier", "SYSTEM.CNF found in \(url.lastPathComponent) but no clear BOOT indicators. Unable to confidently identify system.")
    return nil
}

/// Checks for a PSP "PARAM.SFO" file within an ISO/Disc image
private static func hasPSPParameterFile(url: URL) -> Bool {
    LoggerService.debug(category: "ROMIdentifier", "Checking for PARAM.SFO in ISO \(url.lastPathComponent) to identify potential PSP disc image")
    guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? fileHandle.close() }
    
    // PARAM.SFO is a small file usually located in the PSP_GAME folder.
    // Reading the first 500KB is usually enough to find the directory entry.
    guard let data = try? fileHandle.read(upToCount: 500_000) else { return false }
    
    // 1. Search for the string "PARAM.SFO" in the directory records
    let targetName = "PARAM.SFO".data(using: .ascii)!
    guard let range = data.range(of: targetName) else {
        LoggerService.debug(category: "ROMIdentifier", "PARAM.SFO not found in ISO \(url.lastPathComponent)")
        return false
    }
    
    // 2. ISO9660 Directory record logic:
    // The LBN (Logical Block Number) is located 10 bytes before the filename.
    let lbnOffset = range.lowerBound - 10
    guard lbnOffset > 0 && lbnOffset + 4 < data.count else { return false }
    
    let lbn = data.subdata(in: lbnOffset..<lbnOffset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
    
    // 3. Seek to the block (LBN * 2048) and verify the file starts with "\0PSF"
    let fileOffset = UInt64(lbn) * 2048
    try? fileHandle.seek(toOffset: fileOffset)
    
    if let header = try? fileHandle.read(upToCount: 4) {
        // Verify "\0PSF" (00 50 53 46)
        LoggerService.debug(category: "ROMIdentifier", "Checking PARAM.SFO header in ISO \(url.lastPathComponent) at offset \(fileOffset)")
        let pspMagic: [UInt8] = [0x00, 0x50, 0x53, 0x46]
        return Array(header) == pspMagic
    }
    
    return false
}

    // MARK: - Scoring Methods
private static func scoreByMetadata(url: URL, extLower: String, parentNames: [String], candidates: inout [String: Int]) {
        let allSystems = cachedSystems
        
        // A. Extension Matching
        let systemsWithExt = allSystems.filter { system in 
            system.extensions.contains { normalize(extension: $0) == extLower } 
        }
        let isUniqueExt = systemsWithExt.count == 1
        LoggerService.debug(category: "ROMIdentifier", "File \(url.lastPathComponent): extension '\(extLower)' matches \(systemsWithExt.count) systems: \(systemsWithExt.map { $0.id })")
        
        for system in systemsWithExt {
            candidates[system.id, default: 0] += isUniqueExt ? 80 : 40
        }

        // B. Path Contextual Matching
        for system in allSystems {
            var pathScore = 0
            
            for parentName in parentNames {
                // Normalize parent by stripping spaces and common separators
                let normalizedParent = parentName.replacingOccurrences(of: " ", with: "")
                                                 .replacingOccurrences(of: "-", with: "")
                                                 .replacingOccurrences(of: "_", with: "")
                
                let exactMatch = system.pathKeywords.contains { keyword in
                    let normalizedKeyword = keyword.lowercased()
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: "_", with: "")
                    return normalizedKeyword == normalizedParent
                }
                
                let substringMatch = system.pathKeywords.contains { keyword in
                    let normalizedKeyword = keyword.lowercased()
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: "_", with: "")
                    return !normalizedKeyword.isEmpty && normalizedParent.contains(normalizedKeyword)
                }
                
                // Strong match: Parent name matches System ID or is an exact keyword
                if system.id.lowercased() == parentName || exactMatch {
                    pathScore += 70
                    LoggerService.debug(category: "ROMIdentifier", "Strong path match for \(url.lastPathComponent): \(system.id) (parent: \(parentName))")
                } 
                // Weaker match: Parent name contains the keyword as a substring
                else if substringMatch {
                    pathScore += 30
                    LoggerService.debug(category: "ROMIdentifier", "Weak path match for \(url.lastPathComponent): \(system.id) (parent: \(parentName))")
                }
            }
            
            if pathScore > 0 {
                candidates[system.id, default: 0] += pathScore
                LoggerService.debug(category: "ROMIdentifier", "Total path score for \(url.lastPathComponent) and system \(system.id): \(pathScore) pts")
            }
        }
    }

    private static func scoreByMAME(url: URL, candidates: inout [String: Int]) {
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        LoggerService.debug(category: "ROMIdentifier", "Performing MAME lookup for \(url.lastPathComponent) with short name: \(shortName)")
        if let mameEntry = MAMEUnifiedService.shared.lookup(shortName: shortName), 
           mameEntry.isRunnableInAnyCore && !mameEntry.isBIOS {
            candidates["mame", default: 0] += 90
            LoggerService.debug(category: "ROMIdentifier", "MAME lookup match for \(url.lastPathComponent): \(mameEntry.shortName)")
        }
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
        //return fingerprintArchive(url: url)
        return nil
    }

    // MARK: - Content Fingerprinting

    private static func fingerprintArchive(url: URL) -> SystemInfo? {
        guard let files = peekInsideZipFiles(url: url) else { return nil }
        
        // 1. Scoring Registry
        var scores: [String: Int] = [:]
        
        let systemDB = SystemDatabase.loadSystems()
        
        // 2. Analyze files
        for file in files {
            let fileURL = URL(fileURLWithPath: file)
            let ext = fileURL.pathExtension.lowercased()
            let fileName = fileURL.lastPathComponent.uppercased()
            
            // --- System Extension/ID Scoring ---
            for system in systemDB {
                // Strong match: Specific unique extensions (e.g., .smc, .fds) get higher weight than generic ones (.bin)
                if system.extensions.contains(ext) {
                    let weight = (ext == "bin" || ext == "rom") ? 1 : 3
                    scores[system.id, default: 0] += weight
                }
            }
            
            // --- ScummVM Structural Analysis ---
            if ["sou", "000", "001", "flac", "ogg"].contains(ext) {
                scores["scummvm", default: 0] += 10
            }
        }
        
        // 3. Structural Heuristics (The "Not just an extension" checks)
        
        // MAME: High file count + low extension diversity/common ROM extensions
        let mameRelevantFiles = files.filter { 
            let ext = URL(fileURLWithPath: $0).pathExtension.lowercased()
            return ext == "bin" || ext == "rom" || ext.isEmpty
        }
        if mameRelevantFiles.count > 3 {
            scores["mame", default: 0] += 8
        }
        
        // ScummVM: Known indicator keywords
        let scummvmGameIndicators = ["HE", "MI", "SAM", "DAY", "DIG", "COMI", "MONKEY"]
        for file in files {
            let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent.uppercased()
            if scummvmGameIndicators.contains(where: { name.contains($0) }) {
                scores["scummvm", default: 0] += 5
            }
        }

        // 4. Resolve Winner
        // Sort by score descending and ensure we meet a minimum confidence threshold
        if let bestMatch = scores.sorted(by: { $0.value > $1.value }).first, bestMatch.value >= 3 {
            LoggerService.debug(category: "ROMIdentifier", "Archive \(url.lastPathComponent) identified as \(bestMatch.key) (Score: \(bestMatch.value))")
            return SystemDatabase.system(forID: bestMatch.key)
        }
        
        return nil
    }

    // MARK: - Fast Header Peeking

    private static func peekSystemID(url: URL, systems: [SystemInfo]) -> String? {
        let ext = url.pathExtension.lowercased()
        LoggerService.debug(category: "ROMIdentifier", "Attempting to peek header for \(url.lastPathComponent) with extension: \(ext)")

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
                        LoggerService.debug(category: "ROMIdentifier", "Found a .cue file. Checking file header for \(fileURL.lastPathComponent) from CUE sheet,")
                        return peekHeader(url: fileURL, systems: systems)
                    }
                }
            }
            return nil
        } else {
            LoggerService.debug(category: "ROMIdentifier", "Checking file header for \(url.lastPathComponent),")
            return peekHeader(url: url, systems: systems)
        }
    }

    // MARK: - Improved Header Peeking

    private static func peekHeader(url: URL, systems: [SystemInfo]) -> String? {
        LoggerService.debug(category: "ROMIdentifier", "Peeking header for \(url.lastPathComponent)")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        LoggerService.debug(category: "ROMIdentifier", "Successfully opened file handle for \(url.lastPathComponent)")
        defer { try? handle.close() }
        LoggerService.debug(category: "ROMIdentifier", "Starting magic header checks for \(url.lastPathComponent) against \(systems.count) systems")

        do {
            LoggerService.debug(category: "ROMIdentifier", "Checking magic headers for \(url.lastPathComponent) against \(systems.count) candi date systems")
            for system in systems {
                LoggerService.debug(category: "ROMIdentifier", "Evaluating system \(system) for file \(url.lastPathComponent)")
                if system.magicHeaders.isEmpty {
                    LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): System \(system.id) has no magic headers defined \(system.magicHeaders). Skipping.")
                    continue
                } else {
                    LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): System \(system.id) has \(system.magicHeaders.count) magic headers to check.")
                }
                // what if system does not have magicHeaders or is nul?
                let magicHeaders = system.magicHeaders

                if magicHeaders.isEmpty {
                    LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): System \(system.id) has no magic headers defined. Skipping.")
                    continue
                }
                for magicHeader in magicHeaders {
                    LoggerService.debug(category: "ROMIdentifier", "Checking magic header for system \(system.id) at offset \(magicHeader.offset) and bytes: \(magicHeader.bytes ?? "nil") in file \(url.lastPathComponent)")
                    // 1. Convert the JSON string into actual raw bytes
                    let headerBytes = magicHeader.bytes
                    let offset = magicHeader.offset 
                    
                    let expectedData = parseHeaderBytes(headerBytes ?? "", url.lastPathComponent ?? "")
                    LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): Parsed magic header bytes for system \(system.id) at offset \(offset): \(expectedData as NSData)")
                    if expectedData.isEmpty { continue }

                    // 2. Seek to the offset
                    try handle.seek(toOffset: UInt64(offset))
                    LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): Seeking to offset \(offset) for system \(system.id) in file \(url.lastPathComponent)")
                    
                    // 3. Read exactly the number of bytes needed
                    let data = try handle.read(upToCount: expectedData.count) ?? Data()
                    LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): Read data at offset \(offset) for system \(system.id) in file \(url.lastPathComponent): \(data as NSData) vs expected: \(expectedData as NSData)")
                    if data == expectedData {
                        LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): Magic header match for \(url.lastPathComponent): \(system.id)")
                        return system.id
                    } else {
                        LoggerService.debug(category: "ROMIdentifier", "For \(url.lastPathComponent): No match at offset \(offset) for system \(system.id) in file \(url.lastPathComponent). Read data: \(data as NSData), expected: \(expectedData as NSData)")
                    }
                }
            }
        } catch {
            LoggerService.error(category: "ROMIdentifier", "Error peeking header for file \(url.lastPathComponent): \(error)")
            return nil
        }
        return nil
    }

    /// Converts a variety of string formats into actual Data
    /// Supports: 
    /// - Hex strings: "24 FF AE"
    /// - Escaped strings: "AGB\x1A"
    /// - Plain strings: "GBAX"
    private static func parseHeaderBytes(_ input: String, _ fileURL: String) -> Data {
        // Case 1: It's a Hex String (contains spaces or is purely hex characters)
        // Check if it looks like "AA BB CC" or "AABBCC"
        let hexPattern = "^[0-9A-Fa-f\\s]+$"
        LoggerService.debug(category: "ROMIdentifier", "For \(fileURL): Parsing magic header string: '\(input)'")
        if input.range(of: hexPattern, options: .regularExpression) != nil && input.contains(" ") {
            let hexComponents = input.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var data = Data()
            for hex in hexComponents {
                if let byte = UInt8(hex, radix: 16) {
                    data.append(byte)
                }
            }
            LoggerService.debug(category: "ROMIdentifier", "For \(fileURL): Parsed hex string \(input) into data: \(data as NSData)")
            return data
        }

        // Case 2: It contains escaped hex characters like \x1A
        // We need to manually parse these if the JSON parser didn't do it automatically
        if input.contains("\\x") {
            var data = Data()
            let components = input.components(separatedBy: "\\x")
            
            // The first component is the "prefix" string (e.g., "AGB")
            if let prefixData = components[0].data(using: .utf8) {
                data.append(prefixData)
            }
            
            // Subsequent components are the hex values (e.g., "1A")
            for i in 1..<components.count {
                // The component might have trailing text if it wasn't just the hex
                // We split by non-hex characters to isolate the two digits
                let hexPart = components[i].prefix(2) 
                if let byte = UInt8(hexPart, radix: 16) {
                    data.append(byte)
                }
            }
            LoggerService.debug(category: "ROMIdentifier", "For \(fileURL): Parsed escaped hex string \(input) into data: \(data as NSData)")
            return data
        }
        let data = input.data(using: .utf8) ?? Data()
        LoggerService.debug(category: "ROMIdentifier", "For \(fileURL): Treating magic header \(data as NSData) as plain text: '\(input)'")
        // Case 3: It's a standard literal string
        return data
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

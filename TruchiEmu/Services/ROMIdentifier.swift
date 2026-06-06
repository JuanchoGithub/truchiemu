import Foundation

// Shared ROM system identification utility that both ROMScanner and ROMLibrary use.
// Uses a weighted scoring system to determine the most likely system based on 
// Magic Headers, Unique Extensions, Filename Patterns, and Path Context.
// MARK: - Data Extension for LE Integer Reading

private extension Data {
    func readLEUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func readLEUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}

enum ROMIdentifier {

    // MARK: - Private Properties

    private static let cachedSystems:[SystemInfo] = {
        let systems = SystemDatabaseWrapper.shared.systems
        return systems.isEmpty ? SystemDatabase._loadSystems() : systems
    }()

    // Cache normalized path keywords to avoid millions of expensive string 
    // operations during metadata scoring
    private static let normalizedSystemKeywords: [String: [String]] = {
        var dict: [String: [String]] = [:]
        for system in cachedSystems {
            dict[system.id] = system.pathKeywords.map {
                $0.lowercased()
                  .replacingOccurrences(of: " ", with: "")
                  .replacingOccurrences(of: "-", with: "")
                  .replacingOccurrences(of: "_", with: "")
            }.filter { !$0.isEmpty }
        }
        return dict
    }()

    private static func normalize(extension ext: String) -> String {
        return ext.lowercased().replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Cached set of extensions that are shared by more than one system.
    private static let ambiguousExtensions: Set<String> = {
        let counts = cachedSystems.flatMap { $0.extensions }.reduce(into: [String: Int]()) { counts, ext in
            counts[normalize(extension: ext), default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.map { $0.key })
    }()

    // MARK: - Public Entry Point

    static func identifySystem(url: URL, extension ext: String) async -> SystemInfo? {
        let filename = url.lastPathComponent.lowercased()
        let extLower = normalize(extension: ext)
        
        LoggerService.debug(category: "ROMIdentifier", "Analyzing \(filename)")

        // Reject .dat files smaller than 10 MB — these are never game ROMs
        // (high score files, config data, etc.) and only pollute system listings.
        // Legitimate .dat files are NAOMI NullDC legacy ROMs (typically 2-100+ MB).
        if extLower == "dat" {
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues?.fileSize, fileSize < 10_000_000 {
                LoggerService.debug(category: "ROMIdentifier", "Skipping \(filename): .dat file is too small (\(fileSize) bytes) to be a game ROM")
                return nil
            }
        }

        // 🚀 FAST PATH: Unique Extensions
        // If the extension belongs to exactly ONE system, we can instantly return it
        // and bypass all string allocations, path parsing, and I/O reads entirely.
        if !ambiguousExtensions.contains(extLower) {
            if let uniqueSystem = cachedSystems.first(where: { system in
                system.extensions.contains { normalize(extension: $0) == extLower }
            }) {
                LoggerService.debug(category: "ROMIdentifier", "Fast Path: \(filename) exactly matched \(uniqueSystem.id) via unique extension '.\(extLower)'")
                return uniqueSystem
            }
        }
        
        // Get all parent folder names for path context (Deferred until after the fast path to save CPU)
        let parentNames = url.deletingLastPathComponent().pathComponents.map { $0.lowercased() }
        
        // Dictionary to track potential matches: [SystemID: ConfidenceScore]
        var candidates: [String: Int] = [:]

        // 1. Metadata Scoring (Fast, No I/O: 80 pts for ext, 70 for path)
        scoreByMetadata(url: url, extLower: extLower, parentNames: parentNames, candidates: &candidates)

        var currentBestScore = candidates.values.max() ?? 0

        // 2. MAME Lookup (Potentially slow I/O: 90 pts)
        // Only perform if we don't have a very strong candidate from metadata matching
        if currentBestScore < 90 && extLower == "zip" {
            scoreByMAME(url: url, candidates: &candidates)
            currentBestScore = candidates.values.max() ?? 0
        }

        // 3. Magic Headers (Expensive I/O: 100 pts)
        if currentBestScore < 90 {
            let ambiguousSystems = cachedSystems.filter { system in 
                system.extensions.contains { normalize(extension: $0) == extLower }
            }
            if !ambiguousSystems.isEmpty {
                if let headerID = peekSystemID(url: url, systems: ambiguousSystems) {
                    candidates[headerID, default: 0] += 100
                    currentBestScore = candidates.values.max() ?? 0
                }
            }
        }

        // 4. Archive Analysis (Expensive I/O: 90 pts)
        if currentBestScore < 90 {
            let archiveFormats = ["zip", "7z", "rar"]
            if archiveFormats.contains(extLower) {
                if let archiveSystem = identifyArchive(url: url) {
                    candidates[archiveSystem.id, default: 0] += 90
                    LoggerService.debug(category: "ROMIdentifier", "Archive match for \(filename): \(archiveSystem.id)")
                    currentBestScore = candidates.values.max() ?? 0
                }
            }
        }

    // 5. CD-based System Detection (Expensive I/O: 70-100 pts)
    if currentBestScore < 90 && ["bin", "iso", "img", "cue", "chd"].contains(extLower) {
        if extLower == "cue" || extLower == "m3u" {
            // For container files, we don't scan for SYSTEM.CNF.
            // Instead, we rely on the fact that these extensions are primarily used for disk-based systems.
            // We'll trigger a boost for common disc-based systems.
            let discSystems = ["psx", "ps1", "ps2", "saturn", "dreamcast", "3do", "psp"]
            for sysID in discSystems {
                if cachedSystems.contains(where: { $0.id == sysID }) {
                    candidates[sysID, default: 0] += 50 // Significant boost to suggest a disc-based system
                }
            }
        } else {
            _ = identifyDiscSystem(url: url, candidates: &candidates)
        }
    }


        // --- FINAL DECISION ---
        var sortedCandidates = candidates.sorted { $0.value > $1.value }

        // if the order of candidates is MAME then NeoGeo, choose NeoGeo
        if sortedCandidates.first?.key == "mame", let second = sortedCandidates.dropFirst().first, second.key == "neogeo" {
            // swap scores to prefer Neo Geo
            candidates["neogeo", default: 0] += candidates["mame", default: 0] + 10 // give Neo Geo a boost over MAME
            sortedCandidates = candidates.sorted { $0.value > $1.value }
        }
        
        if let winner = sortedCandidates.first, winner.value >= 30 {
            // Log only the winner and top 3 candidates to avoid massive string concatenation overhead
            let topCandidates = sortedCandidates.prefix(3).map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            LoggerService.debug(category: "ROMIdentifier", "Winner for \(filename) is \(winner.key). Top candidates:[\(topCandidates)]")
            return cachedSystems.first { $0.id == winner.key } ?? SystemDatabase.system(forID: winner.key)
        } else {
            let topCandidates = sortedCandidates.prefix(3).map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            LoggerService.debug(category: "ROMIdentifier", "No clear winner for \(filename). Top candidates: [\(topCandidates)]")
        }

        // Fallback 1: Check if any parent folder name is a valid System ID
        // AND that system actually supports this extension
        if let folderSystem = parentNames.lazy.compactMap({ name in
            cachedSystems.first(where: {
                $0.id.lowercased() == name &&
                $0.extensions.contains { normalize(extension: $0) == extLower }
            })
        }).first {
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

    // CD images come in three sector layouts:
    //  • cooked (.iso) — 2048-byte user-data sectors, data at LBN * 2048
    //  • raw Mode 1   — 2352-byte sectors, user data at LBN * 2352 + 16
    //  • raw Mode 2   — 2352-byte sectors, 8-byte subheader before user data, so LBN * 2352 + 24
    // Discriminates by checking the first 12 bytes for the CD sync pattern (00 FF×10 00)
    // and byte 15 (the mode byte in the sector header).
    enum CDSectorFormat {
        case cooked2048
        case raw2352Mode1
        case raw2352Mode2

        func lbnToFileOffset(_ lbn: UInt32) -> UInt64 {
            switch self {
            case .cooked2048:   return UInt64(lbn) * 2048
            case .raw2352Mode1: return UInt64(lbn) * 2352 + 16
            case .raw2352Mode2: return UInt64(lbn) * 2352 + 24
            }
        }
    }

    static func detectFormat(at url: URL) -> CDSectorFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .cooked2048 }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), header.count == 16 else { return .cooked2048 }
        let isRawCD = header[0] == 0x00 && header[1] == 0xFF && header[2] == 0xFF && header[3] == 0xFF &&
                      header[4] == 0xFF && header[5] == 0xFF && header[6] == 0xFF && header[7] == 0xFF &&
                      header[8] == 0xFF && header[9] == 0xFF && header[10] == 0xFF && header[11] == 0x00
        guard isRawCD else { return .cooked2048 }
        // Byte 15 of a raw sector is the mode field from the 4-byte header (bytes 12–15).
        return header[15] == 0x02 ? .raw2352Mode2 : .raw2352Mode1
    }

        // Searches `scanData` for an ISO9660 directory record whose leaf filename matches
        // `leafName` and returns the 4-byte little-endian LBN pointing to the file's data extent.
        // ISO9660 directory records put the LBN at byte 2 of the record, while the identifier
        // (leaf filename) starts at byte 33 — so the offset from identifier start to LBN start
        // is -31 regardless of filename length.
        static func locateLBN(in scanData: Data, forLeafName leafName: String) -> UInt32? {
            guard let target = leafName.data(using: .ascii) else { return nil }
            guard let range = scanData.range(of: target) else { return nil }
            let lbnOffset = range.lowerBound - 31
            guard lbnOffset > 0, lbnOffset + 4 <= scanData.count else { return nil }
            return scanData.subdata(in: lbnOffset..<lbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
        }

        // Like `locateLBN` but also returns the file's data length (32-bit little-endian) from
        // the same directory record. Both values are read directly from the raw record, so the
        // caller doesn't need to re-scan or guess file sizes.
        static func locateLBNAndSize(in scanData: Data, forLeafName leafName: String) -> (lbn: UInt32, size: UInt32)? {
            guard let target = leafName.data(using: .ascii) else { return nil }
            guard let range = scanData.range(of: target) else { return nil }
            let lbnOffset = range.lowerBound - 31
            let sizeOffset = range.lowerBound - 23
            guard lbnOffset > 0, lbnOffset + 4 <= scanData.count,
                  sizeOffset > 0, sizeOffset + 4 <= scanData.count else { return nil }
            let lbn = scanData.subdata(in: lbnOffset..<lbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            let size = scanData.subdata(in: sizeOffset..<sizeOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            return (lbn, size)
        }

        // Reads the ISO and attempts to locate and extract the content of "SYSTEM.CNF"
        static func extractSystemConfig(from url: URL) -> String? {
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? fileHandle.close() }

            // ISO9660 Directory Records start after the Primary Volume Descriptor.
            // For most PS1/PS2 images, we can scan the first 1MB for the "SYSTEM.CNF" filename.
            // It's a crude but highly effective "cheat" method.
            let scanRange = 1_024 * 1_024 // 1MB scan
            guard let data = try? fileHandle.read(upToCount: scanRange) else { return nil }

            guard let lbn = locateLBN(in: data, forLeafName: "SYSTEM.CNF;1") else { return nil }

            let format = detectFormat(at: url)
            let fileOffset = format.lbnToFileOffset(lbn)
            try? fileHandle.seek(toOffset: fileOffset)
            guard let fileData = try? fileHandle.read(upToCount: 2048) else { return nil }
            // SYSTEM.CNF files start with a few bytes of binary header (file length
            // fields), so we decode as ISO Latin 1 to preserve the BOOT= lines that
            // follow — callers locate the BOOT= substring rather than parsing from byte 0.
            return String(data: fileData, encoding: .isoLatin1)
        }
    }

    static func identifyDiscSystem(url: URL, candidates: inout [String: Int]) -> String? {
        LoggerService.extreme(category: "ROMIdentifier", "Attempting disc-based system identification for \(url.lastPathComponent)")
        guard let config = ISOScanner.extractSystemConfig(from: url) else {
            // If SYSTEM.CNF is missing, check for PARAM.SFO (PSP)
            if hasPSPParameterFile(url: url) { 
                candidates["psp", default: 0] += 100
                return "psp" 
            }
            return nil
        }
        
        // hardcoded for PS1 and PS2
        if config.contains("BOOT2") {
            candidates["ps2", default: 0] += 100
            return "ps2"
        } else if config.contains("BOOT") {
            candidates["ps1", default: 0] += 70
            candidates["psx", default: 0] += 70
            return "psx"
        }
        return nil
    }

    // Checks for a PSP "PARAM.SFO" file within an ISO/Disc image
    private static func hasPSPParameterFile(url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fileHandle.close() }
        
        // PARAM.SFO is a small file usually located in the PSP_GAME folder.
        // Reading the first 500KB is usually enough to find the directory entry.
        guard let data = try? fileHandle.read(upToCount: 500_000) else { return false }
        
        // 1. Search for the string "PARAM.SFO" in the directory records
        guard let lbn = ISOScanner.locateLBN(in: data, forLeafName: "PARAM.SFO;1")
                ?? ISOScanner.locateLBN(in: data, forLeafName: "PARAM.SFO") else {
            return false
        }

        // 3. Seek to the block and verify the file starts with "\0PSF"
        let fileOffset = ISOScanner.detectFormat(at: url).lbnToFileOffset(lbn)
        try? fileHandle.seek(toOffset: fileOffset)
        
        if let header = try? fileHandle.read(upToCount: 4) {
            // Verify "\0PSF" (00 50 53 46)
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
        
        for system in systemsWithExt {
            candidates[system.id, default: 0] += isUniqueExt ? 80 : 40
        }

        // Pre-normalize parent names to avoid doing it inside the loop
        let normalizedParents = parentNames.map {
            $0.replacingOccurrences(of: " ", with: "")
              .replacingOccurrences(of: "-", with: "")
              .replacingOccurrences(of: "_", with: "")
        }

            // B. Path Contextual Matching
            for system in systemsWithExt {
            var pathScore = 0
            let keywords = normalizedSystemKeywords[system.id] ?? []
            
            for (index, parentName) in parentNames.enumerated() {
                let normalizedParent = normalizedParents[index]
                
                let exactMatch = keywords.contains(normalizedParent)
                let substringMatch = !exactMatch && keywords.contains { normalizedParent.contains($0) }
                
                // Strong match: Parent name matches System ID or is an exact keyword
                if system.id.lowercased() == parentName || exactMatch {
                    pathScore += 70
                } 
                // Weaker match: Parent name contains the keyword as a substring
                else if substringMatch {
                    pathScore += 30
                }
            }
            
            if pathScore > 0 {
                candidates[system.id, default: 0] += pathScore
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
            return SystemDatabase.system(forID: "mame")
        }
        if parentName.contains("dos") || parentName.contains("dosbox") || parentName.contains("pc") {
            return SystemDatabase.system(forID: "dos")
        }
        if parentName.contains("scummvm") || parentName.contains("scumm") {
            return SystemDatabase.system(forID: "scummvm")
        }
        if parentName.contains("32x") || parentName.contains("genesis32x") || parentName.contains("sega32x") {
            return SystemDatabase.system(forID: "32x")
        }

        if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
            return nil
        }

        return fingerprintArchive(url: url)
    }

    // MARK: - Content Fingerprinting

    private static let distinctiveArchiveExtensions: [String: Set<String>] = [
        "amiga": Set(["adf", "dms", "adz", "hdf", "hdz", "rp9", "slave", "uae", "lha", "info", "wrp", "nrg"]),
        "commodore_64": Set(["d64", "d71", "d81", "d80", "d82", "t64", "prg", "p00", "crt", "g64", "g41", "x64", "d2m", "d4m", "d6z", "d7z", "d8z", "g4z", "g6z", "nbz", "tap", "vfl", "vsf", "x6z"]),
        "commodore_vic20": Set(["20", "40", "60", "a0", "b0"]),
        "commodore_c64_supercpu": Set(["lnx", "lyx"]),
        "ngpc": Set(["ngp", "ngc", "ngpc", "npc"]),
        "neogeo": Set(["neo"]),
        "zx_spectrum": Set(["tzx", "z80", "scl", "szx", "trd", "dck", "rzx"]),
        "atari_st": Set(["msa", "stx", "dim", "gem", "ide"]),
        "pc_98": Set(["hdi", "nhd", "thd", "xdf", "98d", "d98", "fdd", "hdd", "hdn"]),
        "cpc": Set(["cdt", "cpr"]),
        "game_music": Set(["nsf", "nsfe", "spc", "vgm", "vgz", "gbs", "hes", "ay", "gym", "kss", "sap", "cdg"]),
        "dreamcast": Set(["cdi", "gdi"]),
        "saturn": Set(["toc"]),
        "epochcv": Set(["bin777", "ptn777"]),
        "mac68k": Set(["hvf"]),
        "sharp_x1": Set(["dx1"]),
        "dos": Set(["dosz"]),
        "scummvm": Set(["scummvm"]),
        "intellivision": Set(["int", "intv"])
    ]

    private static let scummVMDataExtensions: Set<String> = [
        "sou", "lfl", "hex",
        "flc", "flx", "san", "bun", "ws6",
        "stk", "gdr",
        "ald", "alg", "als",
        "rsc", "dfw", "blk", "gme",
        "pak", "tlk"
    ]

    private static let dosExecutableExtensions: Set<String> = [
        "exe", "bat", "com"
    ]

    private static let scummVMResourceExtensions: Set<String> = [
        "000", "001", "002", "003", "004", "005"
    ]

    private static let coktelVisionComboExtensions: Set<String> = [
        "itk", "ltk", "ask"
    ]

    private static let teenAgentMarkerFiles: Set<String> = [
        "varia.res", "unlogic.res", "mmm.res", "ons.res", "sdr.res"
    ]

    private static let scummVMSpecificFiles: Set<String> = [
        "queen.1", "queen.tbl", "lgop2.prj", "touche.dat", "touche.sof"
    ]

    private static func fingerprintArchive(url: URL) -> SystemInfo? {
        guard let files = peekInsideZipFiles(url: url) else { return nil }
        var scores: [String: Int] = [:]

        let fileEntries = files.filter { !$0.hasSuffix("/") }
        let fileBasenameSet = Set(fileEntries.map { $0.lowercased().split(separator: "/").last.map(String.init) ?? "" })
        let fileExts = fileEntries.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        let extSet = Set(fileExts)
        let rootFiles = fileEntries.filter { !$0.contains("/") }
        let rootExtSet = Set(rootFiles.map { URL(fileURLWithPath: $0).pathExtension.lowercased() })

 // Tier 1: Distinctive archive extensions
 for (systemID, distinctSet) in distinctiveArchiveExtensions {
 let matches = distinctSet.intersection(extSet)
 if !matches.isEmpty {
 scores[systemID, default: 0] += matches.count * 15
 }
 }

        // Tier 2: ScummVM extension-based detection

        // 2a: Single unique ScummVM data extensions
        let scummvmDataMatches = scummVMDataExtensions.intersection(extSet)
        if !scummvmDataMatches.isEmpty {
            scores["scummvm", default: 0] += scummvmDataMatches.count * 15
        }

        // 2b: Resource numbered files (root level only — avoids DOS level data like LEVEL001/COLOURS.000)
        let rootResMatches = scummVMResourceExtensions.intersection(rootExtSet)
        if !rootResMatches.isEmpty {
            scores["scummvm", default: 0] += 15
        }

        // 2b-alt: RESOURCE.MAP + RESOURCE.NNN anywhere (SCI games in subdirs like "Castle of Dr. Brain/")
        let hasResourceMap = fileBasenameSet.contains("resource.map")
        let hasResourceNumbered = fileBasenameSet.contains { basename in
            guard basename.hasPrefix("resource.") else { return false }
            let ext = basename.suffix(from: basename.index(basename.startIndex, offsetBy: 9))
            return scummVMResourceExtensions.contains(String(ext))
        }
        if hasResourceMap && hasResourceNumbered {
            scores["scummvm", default: 0] += 15
        }

        // 2c: Coktel Vision combo (.itk/.ltk/.ask must co-occur with .stk)
        let coktelComboMatches = coktelVisionComboExtensions.intersection(extSet)
        if extSet.contains("stk") && !coktelComboMatches.isEmpty {
            scores["scummvm", default: 0] += coktelComboMatches.count * 15 + 15
        }

        // 2d: MADS engine combo (.cnv + .tab both required)
        if extSet.contains("cnv") && extSet.contains("tab") {
            scores["scummvm", default: 0] += 30
        }

        // 2e: AGOS engine (many .vga files — Adventure Soft games have 100+)
        let vgaCount = fileExts.filter { $0 == "vga" }.count
        if vgaCount >= 10 {
            scores["scummvm", default: 0] += 30
        }

        // Tier 3: ScummVM structural signatures

        // 3a: AGI engine (Sierra old-style — OBJECT + WORDS.TOK)
        if fileBasenameSet.contains("object") && fileBasenameSet.contains("words.tok") {
            scores["scummvm", default: 0] += 30
        }

        // 3b: SCI engine (Sierra — RESOURCE.MAP + RESOURCE.CFG + RESOURCE.NNN)
        let hasSCIConfig = fileBasenameSet.contains("resource.cfg")
        if hasResourceMap && hasSCIConfig && hasResourceNumbered {
            scores["scummvm", default: 0] += 30
        }

        // 3c: Delphine engine (VOL.CNF or DELPHINE.CFG)
        if fileBasenameSet.contains("vol.cnf") || fileBasenameSet.contains("delphine.cfg") {
            scores["scummvm", default: 0] += 30
        }

        // 3c-alt: Delphine alt pattern (VOL.N files + .PRC — Future Wars, Operation Stealth)
        let hasVolNumbered = fileBasenameSet.contains { $0.range(of: "^vol\\.\\d+$", options: .regularExpression) != nil }
        let hasPRC = fileBasenameSet.contains { $0.hasSuffix(".prc") }
        if hasVolNumbered && hasPRC {
            scores["scummvm", default: 0] += 30
        }

        // 3d: Tinsel engine — Discworld 1 (many .SCN + .MDI + .DIG)
        let scnCount = fileExts.filter { $0 == "scn" }.count
        if scnCount >= 20 && extSet.contains("mdi") && extSet.contains("dig") {
            scores["scummvm", default: 0] += 30
        }

        // 3d-alt: Tinsel engine — Discworld 2 (many .SCN + .BMV + .CDP)
        if scnCount >= 20 && extSet.contains("bmv") && extSet.contains("cdp") {
            scores["scummvm", default: 0] += 30
        }

        // 3e: Personal Nightmare (many .OUT + .DBM)
        let outCount = fileExts.filter { $0 == "out" }.count
        if outCount >= 20 && extSet.contains("dbm") {
            scores["scummvm", default: 0] += 30
        }

        // 3f: Lure of the Temptress (Disk1.vga, Disk2.vga — Revolution engine)
        let hasDiskVGA = fileBasenameSet.contains { $0.range(of: "^disk\\d+\\.vga$", options: .regularExpression) != nil }
        if hasDiskVGA {
            scores["scummvm", default: 0] += 30
        }

        // 3g: TeenAgent (specific .RES filenames — avoids false positives from generic .res counts)
        let teenAgentMatches = teenAgentMarkerFiles.intersection(fileBasenameSet)
        if teenAgentMatches.count >= 2 {
            scores["scummvm", default: 0] += 30
        }

        // 3h: AGOS file markers (GAMEPC/GAME32 + many .VGA)
        if (fileBasenameSet.contains("gamepc") || fileBasenameSet.contains("game32")) && vgaCount >= 10 {
            scores["scummvm", default: 0] += 15
        }

        // 3i: Specific ScummVM game files
        let specificFileMatches = scummVMSpecificFiles.intersection(fileBasenameSet)
        if !specificFileMatches.isEmpty {
            scores["scummvm", default: 0] += 30
        }

        // Tier 4: DOS fallback (only when no ScummVM or other system signal)
        let hasScummVMSignal = scores["scummvm", default: 0] > 0
        let hasOtherSystemSignal = scores.keys.filter { $0 != "scummvm" && $0 != "dos" }.contains { scores[$0]! > 0 }
        if !hasOtherSystemSignal && !hasScummVMSignal {
            let dosMatches = dosExecutableExtensions.intersection(extSet)
            if !dosMatches.isEmpty {
                scores["dos", default: 0] += 15
            }
        }

        // Tier 5: .iso inside zip — likely DOS/PC game
        if extSet.contains("iso") {
            scores["dos", default: 0] += 15
        }

        // Tier 6: DOSBOX directory
        let hasDOSBOXDir = files.contains { $0.lowercased().contains("dosbox") && $0.hasSuffix("/") }
        if hasDOSBOXDir {
            scores["dos", default: 0] += 20
        }

        // Tier 7: MAME heuristic
        let mameRelevantCount = fileExts.filter { $0 == "bin" || $0 == "rom" || $0.isEmpty }.count
        if mameRelevantCount > 3 {
            scores["mame", default: 0] += 8
        }

        // Tier 8: ScummVM game code directory matching (fallback for weak signals)
        let topNonScummVM = scores.filter { $0.key != "scummvm" }.values.max() ?? 0
        let scummVMScore = scores["scummvm", default: 0]
        if scummVMScore > 0 && scummVMScore >= topNonScummVM && scummVMScore < 30 {
            if let gameCodes = loadScummVMGameCodes() {
                let dirNames = extractDirectoryNames(from: files)
                for dirName in dirNames {
                    if gameCodes.contains(dirName) {
                        scores["scummvm", default: 0] += 20
                        LoggerService.debug(category: "ROMIdentifier", "ScummVM game code directory match: \(dirName)")
                        break
                    }
                }
            }
        }

        if let bestMatch = scores.sorted(by: { $0.value > $1.value }).first, bestMatch.value >= 15 {
            LoggerService.debug(category: "ROMIdentifier", "Fingerprint winner: \(bestMatch.key) (\(bestMatch.value) pts) from \(files.count) files")
            return SystemDatabase.system(forID: bestMatch.key)
        }

        return nil
    }

    private static func extractDirectoryNames(from files: [String]) -> [String] {
        var dirNames = Set<String>()
        for file in files {
            let components = file.split(separator: "/", omittingEmptySubsequences: true)
            for component in components.dropLast() {
                let dir = String(component).lowercased()
                if dir.count >= 4 && dir.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                    dirNames.insert(dir.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: ""))
                }
            }
        }
        return Array(dirNames)
    }

    private static var _scummVMGameCodes: Set<String>?
    private static let _scummVMGameCodesLock = NSLock()

    private static func loadScummVMGameCodes() -> Set<String>? {
        _scummVMGameCodesLock.lock()
        defer { _scummVMGameCodesLock.unlock() }

        if let cached = _scummVMGameCodes {
            return cached
        }

        guard let datURL = Bundle.main.url(forResource: "ScummVM", withExtension: "dat", subdirectory: "Data/LibretroDats") else {
            LoggerService.debug(category: "ROMIdentifier", "ScummVM.dat not found in bundle")
            return nil
        }

        guard let content = try? String(contentsOf: datURL, encoding: .utf8) else {
            LoggerService.debug(category: "ROMIdentifier", "Failed to read ScummVM.dat")
            return nil
        }

        var codes = Set<String>()
        let pattern = try? NSRegularExpression(pattern: "code\\s+\"([^\"]+)\"")
        if let regex = pattern {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let range = Range(match.range(at: 1), in: content) {
                    let code = String(content[range]).lowercased()
                    if code.count >= 4 {
                        codes.insert(code)
                    }
                }
            }
        }

        LoggerService.debug(category: "ROMIdentifier", "Loaded \(codes.count) ScummVM game codes (length >= 4)")
        _scummVMGameCodes = codes
        return codes
    }

    // MARK: - Fast Header Peeking

    private static func peekSystemID(url: URL, systems: [SystemInfo]) -> String? {
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
                        return peekHeader(url: fileURL, systems: systems)
                    }
                }
            }
            return nil
        } else {
            return peekHeader(url: url, systems: systems)
        }
    }

    // MARK: - Improved Header Peeking

    private static func peekHeader(url: URL, systems: [SystemInfo]) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            for system in systems {
                for magicHeader in system.magicHeaders {
                    // 1. Convert the JSON string into actual raw bytes
                    let headerBytes = magicHeader.bytes
                    let offset = magicHeader.offset 
                    
                    let expectedData = parseHeaderBytes(headerBytes ?? "", url.lastPathComponent)
                    if expectedData.isEmpty { continue }

                    // 2. Seek to the offset
                    try handle.seek(toOffset: UInt64(offset))
                    
                    // 3. Read exactly the number of bytes needed
                    let data = try handle.read(upToCount: expectedData.count) ?? Data()
                    if data == expectedData {
                        return system.id
                    } 
                }
            }
        } catch {
            LoggerService.error(category: "ROMIdentifier", "Error peeking header for file \(url.lastPathComponent): \(error)")
            return nil
        }
        return nil
    }

    // Converts a variety of string formats into actual Data
    // Supports: 
    // - Hex strings: "24 FF AE"
    // - Escaped strings: "AGB\x1A"
    // - Plain strings: "GBAX"
    private static func parseHeaderBytes(_ input: String, _ fileURL: String) -> Data {
        // Case 1: It's a Hex String (contains spaces or is purely hex characters)
        // Check if it looks like "AA BB CC" or "AABBCC"
        let hexPattern = "^[0-9A-Fa-f\\s]+$"
        if input.range(of: hexPattern, options: .regularExpression) != nil && input.contains(" ") {
            let hexComponents = input.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var data = Data()
            for hex in hexComponents {
                if let byte = UInt8(hex, radix: 16) {
                    data.append(byte)
                }
            }
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
            return data
        }
        let data = input.data(using: .utf8) ?? Data()
        // Case 3: It's a standard literal string
        return data
    }

    // MARK: - Fast ZIP Peeking

    private static func peekInsideZipFiles(url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: 0)

        // Try central directory first (lists all filenames without reading compressed data)
        if let names = readZipCentralDirectory(handle: handle, fileSize: fileSize) {
            return names.isEmpty ? nil : names
        }

        // Fallback: sequential local header scan (works for non-standard ZIPs)
        try? handle.seek(toOffset: 0)
        return readZipLocalHeaders(handle: handle)
    }

    private static func readZipCentralDirectory(handle: FileHandle, fileSize: UInt64) -> [String]? {
        let eocdSearchSize: UInt64 = 65536
        let readStart = fileSize > eocdSearchSize ? fileSize - eocdSearchSize : 0
        let readLen = Int(fileSize - readStart)

        try? handle.seek(toOffset: readStart)
        guard let tailData = try? handle.read(upToCount: readLen), tailData.count >= 22 else { return nil }

        // Find End of Central Directory record (EOCD signature: 0x06054b50)
        let eocdSig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard let eocdRange = tailData.range(of: Data(eocdSig), options: .backwards) else { return nil }
        let eocdRangeLower = eocdRange.lowerBound

        guard eocdRangeLower + 22 <= tailData.count else { return nil }

        let cdSize = tailData.readLEUInt32(at: eocdRangeLower + 12)
        let cdOffset = tailData.readLEUInt32(at: eocdRangeLower + 16)
        let numEntries = tailData.readLEUInt16(at: eocdRangeLower + 10)

        guard cdSize > 0, cdOffset < fileSize, numEntries > 0 else { return nil }

        try? handle.seek(toOffset: UInt64(cdOffset))
        let readSize = min(Int(cdSize), 1_048_576)
        guard let cdData = try? handle.read(upToCount: readSize) else { return nil }

        var filenames: [String] = []
        var offset = 0
        let cdSig: UInt32 = 0x02014b50
        let maxEntries = 200

        while filenames.count < maxEntries {
            guard offset + 46 <= cdData.count else { break }
            let sig = cdData.readLEUInt32(at: offset)
            guard sig == cdSig else { break }

            let nameLen = Int(cdData.readLEUInt16(at: offset + 28))
            let extraLen = Int(cdData.readLEUInt16(at: offset + 30))
            let commentLen = Int(cdData.readLEUInt16(at: offset + 32))

            guard offset + 46 + nameLen <= cdData.count else { break }
            let nameData = cdData[offset + 46 ..< offset + 46 + nameLen]
            if let name = String(data: nameData, encoding: .utf8) {
                filenames.append(name)
            }

            offset += 46 + nameLen + extraLen + commentLen
        }

        return filenames
    }

    private static func readZipLocalHeaders(handle: FileHandle) -> [String]? {
        try? handle.seek(toOffset: 0)
        guard let data = try? handle.read(upToCount: 65536), data.count >= 30 else { return nil }

        var filenames: [String] = []
        var offset = 0
        let localHeaderSig: UInt32 = 0x04034b50
        let maxEntries = 200

        while filenames.count < maxEntries {
            guard offset + 30 <= data.count else { break }
            let sig = data.readLEUInt32(at: offset)
            guard sig == localHeaderSig else { break }

            let fileNameLen = Int(data.readLEUInt16(at: offset + 26))
            let extraLen = Int(data.readLEUInt16(at: offset + 28))
            let compressedSize = Int(data.readLEUInt32(at: offset + 18))

            guard offset + 30 + fileNameLen <= data.count else { break }
            let nameData = data[offset + 30 ..< offset + 30 + fileNameLen]
            if let name = String(data: nameData, encoding: .utf8) {
                filenames.append(name)
            }

            let next = offset + 30 + fileNameLen + extraLen + compressedSize
            guard next > offset else { break }
            offset = next
        }

        return filenames.isEmpty ? nil : filenames
    }

    // MARK: - Container Logic

    static func getReferencedFiles(in url: URL) -> [URL] {
        let ext = url.pathExtension.lowercased()
        var referenced: [URL] = []

        if ext == "cue" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return[] }
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
                        let fileURL = url.deletingLastPathComponent().appendingPathComponent(name).standardized
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
                    let fileURL = url.deletingLastPathComponent().appendingPathComponent(trimmed).standardized
                    referenced.append(fileURL)
                }
            }
        } else if ext == "gdi" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let lines = content.components(separatedBy: .newlines)
            // First line is track count, subsequent lines reference track files
            for (index, line) in lines.enumerated() {
                if index == 0 { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                // Each line: track sector mode size "filename" offset
                // Extract quoted filename
                if let quoteStart = trimmed.firstIndex(of: "\""),
                   let quoteEnd = trimmed[trimmed.index(after: quoteStart)...].firstIndex(of: "\"") {
                    let filename = String(trimmed[trimmed.index(after: quoteStart)..<quoteEnd])
                    let fileURL = url.deletingLastPathComponent().appendingPathComponent(filename).standardized
                    referenced.append(fileURL)
                }
            }
        } else if ext == "ccd" || ext == "toc" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.uppercased().hasPrefix("IMAGE") {
                    let scanner = Scanner(string: trimmed)
                    _ = scanner.scanString("IMAGE")
                    var filename: NSString?
                    if scanner.scanString("=\"") != nil {
                        if let scanned = scanner.scanUpToString("\"") { filename = scanned as NSString }
                    } else if scanner.scanString("=\"") != nil {
                        if let scanned = scanner.scanUpToString("\"") { filename = scanned as NSString }
                    }
                    if let name = filename as String? {
                        let fileURL = url.deletingLastPathComponent().appendingPathComponent(name).standardized
                        referenced.append(fileURL)
                    }
                }
            }
        } else if ext == "mds" {
            // MDS references an MDF file with the same base name
            let mdfName = url.deletingPathExtension().lastPathComponent + ".mdf"
            let fileURL = url.deletingLastPathComponent().appendingPathComponent(mdfName).standardized
            referenced.append(fileURL)
        }

        return referenced
    }
}

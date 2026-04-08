import Foundation

/// Shared ROM system identification utility that both ROMScanner and ROMLibrary use.
/// This eliminates duplicated logic between the two scanning paths.
enum ROMIdentifier {

    // MARK: - Public Entry Point

    /// Identify the system for a given file URL.
    /// This is the single source of truth for ROM system identification.
    static func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        // 1. For ZIP files, determine the system by inspecting content
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

    // MARK: - Archive Identification

    private static func identifyArchive(url: URL) -> SystemInfo? {
        // TIER 1: Path-based context (folder name)
        let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()

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

        // TIER 1.5: MAME database lookup (fast O(1) shortname check)
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
            if unifiedEntry.isRunnableInAnyCore && !unifiedEntry.isBIOS {
                return SystemDatabase.system(forID: "mame")
            } else {
                // It's a BIOS, device, or mechanical ROM — hide it
                return nil
            }
        }

        // TIER 2: BIOS exclusion from scan results
        if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
            return nil
        }

        // TIER 3: Content fingerprinting (peek inside ZIP)
        if let detected = fingerprintArchive(url: url) {
            return detected
        }

        // TIER 4: Route to Unknown System for ambiguous ZIPs
        return SystemDatabase.system(forID: "unknown")
    }

    // MARK: - Content Fingerprinting

    private static func fingerprintArchive(url: URL) -> SystemInfo? {
        guard let files = peekInsideZipFiles(url: url) else { return nil }

        // Check for console ROM extensions inside ZIP (these are compressed console ROMs)
        let consoleExts = ["32x", "nes", "sfc", "smc", "fig", "gb", "gbc", "gba", "md", "gen", "smd", "sms", "gg", "sg"]
        for file in files {
            let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
            if consoleExts.contains(ext), let system = SystemDatabase.system(forExtension: ext) {
                return system
            }
        }

        // Check for DOS executables
        let dosInnerExtensions: Set<String> = ["exe", "com", "bat", "dos", "dosz", "conf", "ins"]
        if files.contains(where: { dosInnerExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
            return SystemDatabase.system(forID: "dos")
        }

        // Check for ScummVM indicators
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
                return SystemDatabase.system(forID: "scummvm")
            }
            if scummvmGameIndicators.contains(where: { nameWithoutExt.contains($0) }) {
                return SystemDatabase.system(forID: "scummvm")
            }
        }

        // Check for MAME-style naming (short cryptic filenames, .bin/.rom files)
        let mameInnerExtensions: Set<String> = ["bin", "rom", "a", "b", "c", "d", "e", "f"]
        let mameStyleCount = files.filter { file in
            let fileURL = URL(fileURLWithPath: file)
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            return (name.count <= 15 && ext.isEmpty) || ext == "bin" || ext == "rom" || mameInnerExtensions.contains(ext)
        }.count

        if mameStyleCount > 1 {
            return SystemDatabase.system(forID: "mame")
        }

        return nil
    }

    // MARK: - Filename Detection

    private static func detectSystemFromFilename(_ filename: String) -> String? {
        let upper = filename.uppercased()

        // Explicit tags
        if upper.contains("(PS1)") || upper.contains("[PS1]") || upper.contains("(PSX)") {
            return "psx"
        }
        if upper.contains("(SATURN)") || upper.contains("[SATURN]") {
            return "saturn"
        }
        if upper.contains("(32X)") || upper.contains("[32X]") {
            return "32x"
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

    // MARK: - Header Peeking

    private static func peekSystemID(url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        if ext == "cue" {
            // Read cue and find first file
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.uppercased().hasPrefix("FILE") {
                    let scanner = Scanner(string: trimmed)
                    _ = scanner.scanString("FILE")
                    var filename: NSString?
                    if scanner.scanString("\"") != nil {
                        if let scanned = scanner.scanUpToString("\"") {
                            filename = scanned as NSString
                        }
                    }
                    if let name = filename as String? {
                        let fileURL = url.deletingLastPathComponent().appendingPathComponent(name)
                        return peekHeader(url: fileURL)
                    }
                }
            }
            return nil
        } else {
            return peekHeader(url: url)
        }
    }

    private static func peekHeader(url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        // Sega Saturn (at 0x0) - "SEGA SEGASATURN"
        let saturnMagic = "SEGA SEGASATURN"
        if data.count >= saturnMagic.count,
           let str = String(data: data.prefix(saturnMagic.count), encoding: .ascii),
           str == saturnMagic {
            return "saturn"
        }

        // Sega 32X (at 0x100) - "SEGA 32X"
        let _32xMagic = "SEGA 32X"
        if data.count >= 0x100 + _32xMagic.count,
           let str = String(data: data[0x100..<0x100 + _32xMagic.count], encoding: .ascii),
           str == _32xMagic {
            return "32x"
        }

        // Sega Genesis (at 0x100) - "SEGA"
        if data.count >= 0x104 {
            let slice = data[0x100..<0x104]
            if let str = String(data: slice, encoding: .ascii), str == "SEGA" {
                return "genesis"
            }
        }

        // PS1 (at 0x8008 or 0x9318) - "PLAYSTATION"
        let ps1Magic = "PLAYSTATION"
        if data.count >= 0x8008 + ps1Magic.count,
           let str = String(data: data[0x8008..<0x8008 + ps1Magic.count], encoding: .ascii),
           str.contains(ps1Magic) {
            return "psx"
        }
        if data.count >= 0x9318 + ps1Magic.count,
           let str = String(data: data[0x9318..<0x9318 + ps1Magic.count], encoding: .ascii),
           str.contains(ps1Magic) {
            return "psx"
        }

        return nil
    }

    // MARK: - ZIP File Peeking

    private static func peekInsideZipFiles(url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 30 else { return nil }

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
            if let name = String(data: nameData, encoding: .utf8) {
                if !name.hasSuffix("/") {
                    filenames.append(name)
                }
            }

            let next = offset + 30 + nameLen + extra + comp
            guard next > offset else { break }
            offset = next
        }

        return filenames.isEmpty ? nil : filenames
    }

    // MARK: - Referenced Files (for .cue/.m3u containers)

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
                        if let scanned = scanner.scanUpToString("\"") {
                            filename = scanned as NSString
                        }
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
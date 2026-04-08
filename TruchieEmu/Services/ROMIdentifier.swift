import Foundation

/// Shared ROM system identification utility that both ROMScanner and ROMLibrary use.
/// This eliminates duplicated logic between the two scanning paths.
enum ROMIdentifier {

    // MARK: - Public Entry Point

    static func identifySystem(url: URL, extension ext: String) -> SystemInfo? {
        // TIER 0: Strong path-based context (folder name)
        let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
        let sysIDMap: [String: String] = [
            "ps2": "ps2", "playstation2": "ps2", "playstation 2": "ps2",
            "psp": "psp", "playstation portable": "psp",
            "saturn": "saturn", "sega saturn": "saturn",
            "dreamcast": "dreamcast", "sega dreamcast": "dreamcast",
            "psx": "psx", "ps1": "psx", "playstation": "psx",
            "3do": "3do",
            "jaguar": "jaguar", "atari jaguar": "jaguar",
            "gamecube": "gc", "gc": "gc"
        ]
        
        if let hardID = sysIDMap[parentName], let system = SystemDatabase.system(forID: hardID) {
            return system
        }
        
        // 1. For ZIP files, determine the system by inspecting content
        if ext == "zip" || ext == "7z" {
            return identifyArchive(url: url)
        }

        // 2. Try to identify by filename hints
        if let systemID = detectSystemFromFilename(url.lastPathComponent), let system = SystemDatabase.system(forID: systemID) {
            return system
        }

        // 3. For CD-based or ambiguous extensions, peek at the header
        let ambiguous = ["cue", "bin", "iso", "img"]
        if ambiguous.contains(ext) {
            if let systemID = peekSystemID(url: url), let system = SystemDatabase.system(forID: systemID) {
                return system
            }
        }

        // 4. Fallback to extension matching
        return SystemDatabase.system(forExtension: ext)
    }

    // MARK: - Archive Identification

    private static func identifyArchive(url: URL) -> SystemInfo? {
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
                return nil
            }
        }

        if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
            return nil
        }

        if let detected = fingerprintArchive(url: url) {
            return detected
        }

        return SystemDatabase.system(forID: "unknown")
    }

    // MARK: - Content Fingerprinting

    private static func fingerprintArchive(url: URL) -> SystemInfo? {
        guard let files = peekInsideZipFiles(url: url) else { return nil }

        let consoleExts = ["32x", "nes", "sfc", "smc", "fig", "gb", "gbc", "gba", "md", "gen", "smd", "sms", "gg", "sg"]
        for file in files {
            let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
            if consoleExts.contains(ext), let system = SystemDatabase.system(forExtension: ext) {
                return system
            }
        }

        let dosInnerExtensions: Set<String> = ["exe", "com", "bat", "dos", "dosz", "conf", "ins"]
        if files.contains(where: { dosInnerExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
            return SystemDatabase.system(forID: "dos")
        }

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

            if scummvmInnerExtensions.contains(ext) { return SystemDatabase.system(forID: "scummvm") }
            if scummvmGameIndicators.contains(where: { nameWithoutExt.contains($0) }) { return SystemDatabase.system(forID: "scummvm") }
        }

        let mameInnerExtensions: Set<String> = ["bin", "rom", "a", "b", "c", "d", "e", "f"]
        let mameStyleCount = files.filter { file in
            let fileURL = URL(fileURLWithPath: file)
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            return (name.count <= 15 && ext.isEmpty) || ext == "bin" || ext == "rom" || mameInnerExtensions.contains(ext)
        }.count

        if mameStyleCount > 1 { return SystemDatabase.system(forID: "mame") }
        return nil
    }

    // MARK: - Filename Detection

    private static func detectSystemFromFilename(_ filename: String) -> String? {
        let upper = filename.uppercased()
        if upper.contains("DC_BOOT") || upper.contains("DC_FLASH") { return "dreamcast" }
        if upper.contains("(PS1)") || upper.contains("[PS1]") || upper.contains("(PSX)") { return "psx" }
        if upper.contains("(SATURN)") || upper.contains("[SATURN]") { return "saturn" }
        if upper.contains("(32X)") || upper.contains("[32X]") { return "32x" }
        if upper.contains("(GENESIS)") || upper.contains("(MEGA DRIVE)") { return "genesis" }

        let ps1Regex = try? NSRegularExpression(pattern: "(S[CL][EP][SM]|SCPH)-\\d{5}", options: [])
        if let regex = ps1Regex, regex.firstMatch(in: upper, options: [], range: NSRange(location: 0, length: upper.count)) != nil {
            return "psx"
        }
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
            return peekHeader(url: url)
        }
    }

    /// Optimized: Uses FileHandle to instantly read only the tiny chunks of bytes needed instead of memory mapping large ISOs
    private static func peekHeader(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            // Check Saturn at 0x0
            if let data = try handle.read(upToCount: 15), String(data: data, encoding: .ascii) == "SEGA SEGASATURN" {
                return "saturn"
            }

            // Check 32X & Genesis at 0x100
            try handle.seek(toOffset: 0x100)
            if let data = try handle.read(upToCount: 8) {
                if data.count >= 8, String(data: data, encoding: .ascii) == "SEGA 32X" { return "32x" }
                if data.count >= 4, String(data: data.prefix(4), encoding: .ascii) == "SEGA" { return "genesis" }
            }

            // Check PS1 at 0x8008
            try handle.seek(toOffset: 0x8008)
            if let data = try handle.read(upToCount: 11), String(data: data, encoding: .ascii) == "PLAYSTATION" {
                return "psx"
            }

            // Check PS1 alternate at 0x9318
            try handle.seek(toOffset: 0x9318)
            if let data = try handle.read(upToCount: 11), String(data: data, encoding: .ascii) == "PLAYSTATION" {
                return "psx"
            }
        } catch {
            return nil
        }

        return nil
    }

    // MARK: - Fast ZIP Peeking

    /// Optimized: Only loads the first 64KB of the ZIP into memory to scan Local File Headers. Extremely fast.
    private static func peekInsideZipFiles(url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // 64KB is generally enough to capture the local file headers for ROM contents without slowing down I/O
        guard let data = try? handle.read(upToCount: 65536), data.count >= 30 else { return nil }

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
            if let name = String(data: nameData, encoding: .utf8), !name.hasSuffix("/") {
                filenames.append(name)
            }

            let next = offset + 30 + nameLen + extra + comp
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
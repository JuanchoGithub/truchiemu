import Foundation
import zlib // <-- ADD THIS

// MARK: - I/O Bottleneck Controller
// Limits heavy file reading to 4 concurrent operations to prevent SSD/HDD I/O thrashing.
private let diskIOQueue = DispatchQueue(label: "com.truchiemu.diskIO", attributes: .concurrent)
private let diskIOSemaphore = DispatchSemaphore(value: 4) // Max 4 concurrent disk reads

// MARK: - Hardware-Accelerated CRC32
struct CRC32 {
    // Computes CRC32 using the highly optimized, C-based zlib library included in macOS/iOS
    static func compute(url: URL, offset: UInt64 = 0) -> String? {
        // Wait in line so we don't choke the SSD
        diskIOSemaphore.wait()
        defer { diskIOSemaphore.signal() }
        
        guard let inputStream = InputStream(url: url) else { return nil }
        inputStream.open()
        defer { inputStream.close() }
        
        // Skip header if needed
        if offset > 0 {
            // InputStream doesn't have a direct 'seek', so we read and discard the offset bytes
            var remainingToSkip = Int(offset)
            let skipBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: min(remainingToSkip, 32768))
            defer { skipBuffer.deallocate() }
            
            while remainingToSkip > 0 {
                let toRead = min(remainingToSkip, 32768)
                let bytesRead = inputStream.read(skipBuffer, maxLength: toRead)
                if bytesRead <= 0 { break }
                remainingToSkip -= bytesRead
            }
        }
        
        // Use a reusable 128KB buffer (Zero-copy allocations)
        let bufferSize = 131072 // 128 KB
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        // Initialize zlib CRC32
        var crc = crc32(0, nil, 0)
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                // Instantly calculate CRC on the buffer using C/SIMD instructions
                crc = crc32(crc, buffer, uInt(bytesRead))
            } else if bytesRead < 0 {
                return nil // Read error
            } else {
                break // EOF
            }
        }
        
        // Format as an 8-character uppercase Hex string
        return String(format: "%08X", crc)
    }
}

struct GameInfo: Equatable {
    let name: String
    let year: String?
    let publisher: String?
    let developer: String?
    let genre: String?
    let crc: String
    let thumbnailLookupSystemID: String?
}

enum ROMIdentifyResult: Equatable {
    case identified(GameInfo)
    case identifiedFromName(GameInfo)
    case crcNotInDatabase(crc: String)
    case databaseUnavailable
    case romReadFailed(String)
    case noSystem
    case identificationCleared
}

// MARK: - LoggerService bridging helpers
extension LoggerService {
    static func romIdentify(_ message: String) {
        info(category: "ROMIdentify", message)
    }

    static func libretroDB(_ message: String) {
        info(category: "LibretroDB", message)
    }

    static func romIdentifyWarn(_ message: String) {
        warning(category: "ROMIdentify", message)
    }

    static func romIdentifyError(_ message: String) {
        error(category: "ROMIdentify", message)
    }

    static func libretroDBWarn(_ message: String) {
        warning(category: "LibretroDB", message)
    }

    static func libretroDBError(_ message: String) {
        error(category: "LibretroDB", message)
    }

    // MARK: - MAME Categories
    static func mameDeps(_ message: String) {
        info(category: "MAMEDeps", message)
    }

    static func mameDepsWarn(_ message: String) {
        warning(category: "MAMEDeps", message)
    }

    static func mameDepsError(_ message: String) {
        error(category: "MAMEDeps", message)
    }

    static func mameImport(_ message: String) {
        info(category: "MAMEImport", message)
    }

    static func mameImportWarn(_ message: String) {
        warning(category: "MAMEImport", message)
    }

    static func mameImportError(_ message: String) {
        error(category: "MAMEImport", message)
    }

    static func mameVerify(_ message: String) {
        info(category: "MAMEVerify", message)
    }

    static func mameVerifyWarn(_ message: String) {
        warning(category: "MAMEVerify", message)
    }

    static func mameVerifyError(_ message: String) {
        error(category: "MAMEVerify", message)
    }
}

final class SystemSearchIndex {
    let exactMap: [String: [GameInfo]]
    let aggressiveMap: [String: [GameInfo]]
    let allEntries: [GameInfo]
    
    init(database: [String: GameInfo]) {
        var exact: [String: [GameInfo]] = [:]
        var aggressive: [String: [GameInfo]] = [:]
        var all: [GameInfo] = []
        
        for info in database.values {
            all.append(info)
            let datBase = ROMIdentifierService.normalizedComparableTitle(info.name)
            exact[datBase, default: []].append(info)
            
            let datAggressive = ROMIdentifierService.aggressivelyNormalizedTitle(info.name)
            aggressive[datAggressive, default: []].append(info)
        }
        self.exactMap = exact
        self.aggressiveMap = aggressive
        self.allEntries = all
    }
}

final class ROMIdentifierService: @unchecked Sendable {
    static let shared = ROMIdentifierService()
    private let indexCache = NSCache<NSString, SystemSearchIndex>()

    func identify(rom: ROM, preferNameMatch: Bool = false) async -> ROMIdentifyResult {
        LoggerService.debug(category: "ROMIdentifier","Identify \(rom.name): START (preferNameMatch=\(preferNameMatch))")
        guard let systemID = rom.systemID,
              let system = SystemDatabase.system(forID: systemID) else {
            LoggerService.error(category: "ROMIdentifier", "Identify: no system for ROM \(rom.path.lastPathComponent)")
            return .noSystem
        }

        if systemID == "mame" {
            LoggerService.debug(category: "ROMIdentifier","Identify \(rom.name): MAME ROM detected, attempting unified database lookup...")
            let shortName = rom.path.deletingPathExtension().lastPathComponent.lowercased()
            
            // Ensure MAME database is loaded before lookup
            await MAMEUnifiedService.shared.ensureLoaded()
            
            // First: try the unified MAME database (multi-core, 50K+ entries)
            if let unifiedEntry = await MAMEUnifiedService.shared.lookup(shortName: shortName) {
                let isRunnable = MAMEUnifiedService.shared.isRunnable(shortName: shortName) 
                let isBIOS = MAMEUnifiedService.shared.isBIOS(shortName: shortName) 
                if isRunnable && !isBIOS {
                    LoggerService.debug(category: "ROMIdentifier","Identify \(rom.name): MAME game → \(unifiedEntry.description) [cores: \(unifiedEntry.compatibleCores.joined(separator: ", "))]")
                    return .identified(GameInfo(
                        name: unifiedEntry.description,
                        year: unifiedEntry.year,
                        publisher: unifiedEntry.manufacturer,
                        developer: unifiedEntry.manufacturer,
                        genre: nil,
                        crc: "",
                        thumbnailLookupSystemID: nil
                    ))
                } else if isBIOS {
                    LoggerService.debug(category: "ROMIdentifier","Identify \(rom.name): MAME BIOS → \(unifiedEntry.description)")
                    return .identified(GameInfo(
                        name: unifiedEntry.description,
                        year: unifiedEntry.year,
                        publisher: unifiedEntry.manufacturer,
                        developer: unifiedEntry.manufacturer,
                        genre: nil,
                        crc: "",
                        thumbnailLookupSystemID: nil
                    ))
                } else {
                    LoggerService.debug(category: "ROMIdentifier","Identify \(rom.name): MAME game '\(shortName)' found but not runnable in any core → \(unifiedEntry.description)")
                    return .crcNotInDatabase(crc: shortName)
                }
            }
            
            // Not in any MAME database — no point searching libretro DAT (bundled MAME DBs are more comprehensive)
            LoggerService.debug(category: "ROMIdentifier","Identify \(rom.name): MAME game '\(shortName)' not in MAME database — hiding")
            return .crcNotInDatabase(crc: shortName)
        }

        LoggerService.debug(category: "ROMIdentifier","Identify: START system=\(systemID) file=\(rom.path.lastPathComponent) (preferNameMatch=\(preferNameMatch))")

        let db = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
        if db.isEmpty {
            LoggerService.error(category: "ROMIdentifier", "Identify \(rom.name): empty database for system \(systemID), identification skipped.")
            return .databaseUnavailable
        }

        let romPath = rom.path
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: romPath.path)[.size] as? Int64) ?? 0
        let isLargeFile = fileSize > 50 * 1024 * 1024 // > 50MB
        
        // PASS 1: Sony Serial Extraction (Fastest)
        // Optimization: For Sony CD-based systems, try serial extraction (FASTEST)
        if ["psx", "ps2", "psp"].contains(systemID) {
            LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): Game is Playstation (1/2/P) \(systemID)...")
            if let serial = await extractSonySerial(from: romPath) {
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): Checking database for serial '\(serial)'...")
                let normalizedSerial = serial.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: ".", with: "").lowercased()
                
                for info in db.values {
                    let infoName = info.name.lowercased()
                    // Many DATs include the serial in the title, e.g. "Game Name (USA) (SLUS-20071)"
                    if infoName.contains(normalizedSerial) || infoName.contains(serial.lowercased()) {
                        LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): SUCCESS (Serial Path) → \(info.name) matched serial \(serial)")
                        return .identified(info)
                    }
                }
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): Serial '\(serial)' not found.")
            } else {
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): No serial found.")
            }
        }

        // PASS 2: Name-based identification
        // Optimization: Try name-based search first if requested OR if file is large.
        // If we find an exact match by name, we can skip the heavy CRC calculation.
        if preferNameMatch || isLargeFile {
            LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): Attempting name-based search (preferNameMatch=\(preferNameMatch), isLargeFile=\(isLargeFile))...")
            let language = Self.currentEmulatorLanguage()
            if let byName = identifyByName(rom: rom, database: db, language: language) {
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): SUCCESS (Name Path) → \(byName.name) found by name, skipping CRC.")
                return .identifiedFromName(byName)
            }
            LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): Name-based search failed for '\(rom.name)', falling back to CRC hashing...")
        }

        // PASS 3: CRC-based identification (Heavy)
        // Perform heavy file I/O and hashing on a background thread to avoid blocking the MainActor.
        guard let crc = await Task.detached(priority: .userInitiated, operation: {
            self.computeCRC(for: romPath, systemID: systemID)
        }).value else {
            LoggerService.error(category: "ROMIdentifier", "Identify \(rom.name): CRC read failed for \(rom.path.path)")
            return .romReadFailed("Could not read the ROM file. If the library is on a removable drive or you moved files, re-add the folder in Settings.")
        }

        let key = crc.uppercased()
        LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): ROM CRC=\(key)")

        if let info = db[key] {
            if let thumb = info.thumbnailLookupSystemID, thumb != systemID {
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): CRC HIT → \(info.name) (thumbnails: use system \(thumb), ROM is \(systemID))")
            } else {
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): CRC HIT → \(info.name)")
            }
            return .identified(info)
        }

        // PASS 4: Name-based fallback (if we haven't tried it yet)
        if !preferNameMatch && !isLargeFile {
            LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): no CRC match for \(key), falling back to name search...")
            let language = Self.currentEmulatorLanguage()
            if let byName = identifyByName(rom: rom, database: db, language: language) {
                LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): NAME MATCH → \(byName.name) (language=\(language.name))")
                return .identifiedFromName(byName)
            }
        }

        LoggerService.debug(category: "ROMIdentifier", "Identify \(rom.name): NOT FOUND — CRC \(key) not in database and name search found 0 matches for \(systemID)")
        
        // --- INTEGRATION START ---
        // Trigger RA sync as a side effect of identification.
        // We use a Task to avoid blocking the primary identification result.
        Task {
            await RetroAchievementsService.shared.syncROMWithRA(rom: rom)
        }
        // --- INTEGRATION END ---
        
        return .crcNotInDatabase(crc: key)
    }

    func identifyReturningGameInfo(rom: ROM) async -> GameInfo? {
        switch await identify(rom: rom) {
        case .identified(let info), .identifiedFromName(let info):
            return info
        default:
            return nil
        }
    }

    private static func currentEmulatorLanguage() -> EmulatorLanguage {
        let raw = SystemPreferences.shared.systemLanguage.rawValue
        return EmulatorLanguage(rawValue: raw) ?? .english
    }

    private static let commonRomTags: Set<String> = [
        "(world)", "(usa)", "(europe)", "(japan)", "(korea)", "(china)", "(brazil)", "(australia)",
        "(canada)", "(france)", "(germany)", "(spain)", "(italy)", "(netherlands)", "(sweden)",
        "(eu)", "(jp)", "(us)", "(uk)", "(kr)", "(cn)", "(br)", "(au)", "(ca)", "(fr)", "(de)",
        "(es)", "(it)", "(nl)", "(se)", "(dk)", "(no)", "(fi)", "(ru)", "(pt)", "(gr)", "(tr)",
        "(en)", "(ja)", "(fr)", "(de)", "(es)", "(it)", "(nl)", "(pt)", "(ru)", "(ko)", "(zh)",
        "(beta)", "(alpha)", "(demo)", "(proto)", "(rev a)", "(rev b)", "(v1.0)", "(v2.0)",
    ]

    static func aggressivelyNormalizedTitle(_ s: String) -> String {
            var result = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(s)
            while let r = result.range(of: "\\[([^\\]]*)\\]", options: .regularExpression) {
                result.removeSubrange(r)
            }
            while let r = result.range(of: "\\{([^\\}]*)\\}", options: .regularExpression) {
                result.removeSubrange(r)
            }
            result = result.replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*", with: " ", options: .regularExpression)
            result = result.replacingOccurrences(of: "\\s*\\[[^\\]]*\\]\\s*", with: " ", options: .regularExpression)
            
            // Lowercase and handle specific characters
            result = result.lowercased()
            result = result.replacingOccurrences(of: "'", with: "")
            result = result.replacingOccurrences(of: "&", with: "and")
            
            // Replace all remaining punctuation/symbols with spaces
            result = result.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
            
            return result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

    static func normalizedComparableTitle(_ s: String) -> String {
        let stripped = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(s)
        return stripped.lowercased().replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

static func titleFromDatGame(name: String, description: String) -> String {
        guard !description.isEmpty else { return name }
        guard name != description else { return name }
        
        // In Arcade DATs (MAME/FBNeo), 'name' is often a short romset code (e.g., "sf2")
        // and 'description' holds the actual game title ("Street Fighter II").
        // A typical romset code has no spaces, is fully lowercase, and is relatively short.
        let isLikelyRomCode = !name.contains(" ") && name == name.lowercased() && name.count <= 16
        
        if isLikelyRomCode || name.isEmpty {
            return description
        }
        
        // For proper DATs (ScummVM, No-Intro, Redump), 'name' is already the correct full title.
        // The 'description' field might be actual flavor text, so we ignore it and keep the real name.
        return name
    }

    private static func regionPreferenceRank(fullName: String, language: EmulatorLanguage) -> Int {
        let prefs = language.noIntroRegionPreference
        for (idx, tag) in prefs.enumerated() where fullName.contains(tag) { return idx }
        return prefs.count
    }

    private static func regionTieBreakOrdinal(fullName: String, language: EmulatorLanguage) -> Int {
        if language == .japanese {
            if fullName.contains("(Japan)") || fullName.contains("(JP)") { return 0 }
            return 50
        }
        if fullName.contains("(World)") { return 0 }
        if fullName.contains("(USA)") || fullName.contains("(Canada)") { return 2 }
        if fullName.contains("(Europe)") || fullName.contains("(EU)") { return 3 }
        if fullName.contains("(Japan)") || fullName.contains("(JP)") { return 30 }
        return 15
    }

    // MARK: - Article Reordering

    private static let leadingArticles = ["a ", "an ", "the "]

    static func moveArticleToEnd(_ title: String) -> String? {
        let lowercased = title.lowercased()
        for article in leadingArticles {
            if lowercased.hasPrefix(article) {
                _ = title.prefix(article.count)
                let rest = title.dropFirst(article.count).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rest.isEmpty else { return nil }
                let capitalizedArticle = article.trimmingCharacters(in: .whitespaces).capitalized
                return "\(rest), \(capitalizedArticle)"
            }
        }
        return nil
    }

    static func articleVariants(of title: String) -> [String] {
        var variants: [String] = []

        // Forward: "The Legend of Zelda" → "Legend of Zelda, The"
        if let movedToEnd = Self.moveArticleToEnd(title) {
            variants.append(movedToEnd)
        }

        // Backward: "Legend of Zelda, The" → "The Legend of Zelda"
        if let range = title.range(of: ",\\s*(a|an|the)$", options: .regularExpression, range: nil, locale: nil) {
            let commaIndex = range.lowerBound
            let prefix = title[..<commaIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let article = String(title[range]).replacingOccurrences(of: "^,\\s*", with: "", options: .regularExpression)

            guard !prefix.isEmpty, !article.isEmpty else { return variants }
            let reordered = "\(article.capitalized) \(prefix)"
            variants.append(reordered)
        }

        return variants
    }

    static func romanNumeralVariants(of normalized: String) -> [String] {
        guard normalized.count >= 2 else { return [] }
        var variants: Set<String> = []
        let arabicToRoman: [Int: String] = [1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI", 7: "VII", 8: "VIII", 9: "IX", 10: "X", 11: "XI", 12: "XII", 13: "XIII", 14: "XIV", 15: "XV", 16: "XVI", 17: "XVII", 18: "XVIII", 19: "XIX"]
        let arabicToText: [Int: String] = [1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten", 11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen", 15: "fifteen", 16: "sixteen", 17: "seventeen", 18: "eighteen", 19: "nineteen"]
        let romanToArabic: [String: Int] = { var d: [String: Int] = [:]; for (a, r) in arabicToRoman { d[r.lowercased()] = a; d[r] = a }; return d }()
        let textToArabic: [String: Int] = { var d: [String: Int] = [:]; for (a, t) in arabicToText { d[t] = a; let cap = t.prefix(1).uppercased() + t.dropFirst(); d[cap] = a }; return d }()
        for (a, r) in arabicToRoman { let p = "(?<![a-zA-Z])\\b" + String(a) + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: r, options: .regularExpression); if s != normalized { variants.insert(s) } }
        for (a, t) in arabicToText { let p = "(?<![a-zA-Z])\\b" + String(a) + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: t, options: .regularExpression); if s != normalized { variants.insert(s) } }
        for (r, a) in romanToArabic { let esc = NSRegularExpression.escapedPattern(for: r); let p = r.count == 1 ? "(?<![a-zA-Z])\\b" + esc + "\\b(?![-'a-zA-Z0-9])" : "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: String(a), options: .regularExpression); if s != normalized { variants.insert(s) } }
        for (r, a) in romanToArabic { if let tf = arabicToText[a] { let esc = NSRegularExpression.escapedPattern(for: r); let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: tf, options: .regularExpression); if s != normalized { variants.insert(s) } } }
        for (t, a) in textToArabic { let esc = NSRegularExpression.escapedPattern(for: t); let p = "(?<![a-zA-Z])\\b" + String(a) + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: String(a), options: .regularExpression); if s != normalized { variants.insert(s) } }
        for (t, a) in textToArabic { if let rf = arabicToRoman[a] { let esc = NSRegularExpression.escapedPattern(for: t); let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: rf, options: .regularExpression); if s != normalized { variants.insert(s) } } } // wait, typo here in the source content provided by error
        let t = normalized.trimmingCharacters(in: .whitespaces)
        for pat in [" 1$", " (?i:i)(?-i)$", " (?i:one)(?-i)$"] { let s = t.replacingOccurrences(of: pat, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces); if s != t && s.count >= 2 { variants.insert(s) } }
        return Array(variants)
    }

    private func identifyByName(rom: ROM, database: [String: GameInfo], language: EmulatorLanguage) -> GameInfo? {
        LoggerService.info(category: "ROMIdentifier", "IdentifyByName \(rom.name): START for ROM '\(rom.name)'")
        let stem = rom.path.deletingPathExtension().lastPathComponent
        var cleaned = LibretroThumbnailResolver.stripRomFilenameTags(stem)
        cleaned = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(cleaned)
        let queryBase = Self.normalizedComparableTitle(cleaned)
        guard queryBase.count >= 2 else {
            LoggerService.error(category: "ROMIdentifier", "IdentifyByName \(rom.name): name search skipped — queryBase='\(queryBase)' too short (<2 chars)")
            return nil
        }

        let systemID = rom.systemID ?? "unknown"
        let index: SystemSearchIndex
        if let cached = indexCache.object(forKey: systemID as NSString) {
            index = cached
        } else {
            index = SystemSearchIndex(database: database)
            indexCache.setObject(index, forKey: systemID as NSString)
        }

        // PASS 1: Exact normalized match (Dictionary lookup)
        LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 1 — exact match on queryBase='\(queryBase)'")
        var exact: [GameInfo] = index.exactMap[queryBase] ?? []
        if !exact.isEmpty { LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 1 FOUND \(exact.count) exact match(es)") }

        if exact.isEmpty {
            let variants = Self.romanNumeralVariants(of: queryBase)
            LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 2 — number variants (\(variants.count) variants generated)")
            if !variants.isEmpty {
                for variant in variants {
                    if let found = index.exactMap[variant] {
                        exact.append(contentsOf: found)
                        LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 2 matched variant='\(variant)' → \(found.count) entries")
                        break
                    }
                }
            }
            if exact.isEmpty { LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 2 found 0 matches") }
        }

        if exact.isEmpty {
            let aggressiveQuery = Self.aggressivelyNormalizedTitle(stem)
            LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 3 — aggressive normalization")
            LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 3 query='\(stem)' → '\(aggressiveQuery)'")
            if !aggressiveQuery.isEmpty && aggressiveQuery.count >= 2 {
                if let found = index.aggressiveMap[aggressiveQuery] {
                    exact.append(contentsOf: found)
                    LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 3 matched aggressive query → \(found.count) entries")
                }
                
                if exact.isEmpty {
                    let aggressiveVariants = Self.romanNumeralVariants(of: aggressiveQuery)
                    for variant in aggressiveVariants {
                        if let found = index.aggressiveMap[variant] {
                            exact.append(contentsOf: found)
                            LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 3 matched aggressive variant='\(variant)'")
                            break
                        }
                    }
                }
            }
        }

        var candidates = exact
        if candidates.isEmpty {
            LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 4 — substring/fuzzy matching")
            var pass4Candidates:[(info: GameInfo, score: Double)] = []
            
            // Gather the query and all its aggressively normalized/roman numeral variants
            let aggressiveQuery = Self.aggressivelyNormalizedTitle(stem)
            var queryVariants = Set([queryBase, aggressiveQuery])
            queryVariants.formUnion(Self.romanNumeralVariants(of: queryBase))
            queryVariants.formUnion(Self.romanNumeralVariants(of: aggressiveQuery))
            
            // Filter out short queries and pre-tokenize them into sets of words
            let validQueries = queryVariants.filter { $0.count >= 3 }
            let queryTokensList = validQueries.map { q -> Set<String> in
                // FIX: Ensure the query (and any generated Roman Numerals) are completely lowercased before tokenizing
                let sanitized = q.lowercased().replacingOccurrences(of: "'", with: "").components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
                return Set(sanitized.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
            }
            
            for info in index.allEntries {
                let datBase = Self.normalizedComparableTitle(info.name).lowercased()
                guard datBase.count >= 3 else { continue }
                
                // Keep the existing protection against "Sonic" matching "Sonic 2"
                if validQueries.contains(where: { Self.isProblematicNumberSuffixPartialMatch(query: $0.lowercased(), candidate: datBase) }) {
                    continue
                }
                
                var bestScore: Double = 0.0
                
// 1) Token Overlap Matching (Highly resilient to subtitles and out-of-order words)
                let sanitizedC = datBase.replacingOccurrences(of: "'", with: "").components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: " ")
                let cTokens = Set(sanitizedC.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
                
                if !cTokens.isEmpty {
                    for qTokens in queryTokensList {
                        guard !qTokens.isEmpty else { continue }
                        let intersection = qTokens.intersection(cTokens)
                        if intersection.isEmpty { continue }
                        
                        let candidateMatchRatio = Double(intersection.count) / Double(cTokens.count)
                        
                        // Use Sørensen–Dice coefficient for balanced length weighting
                        var score = (2.0 * Double(intersection.count)) / Double(qTokens.count + cTokens.count)
                        
                        // Subset Bonus: If the database title's words are completely contained within the query
                        if candidateMatchRatio == 1.0 {
                            if cTokens.count >= 2 {
                                score += 0.3 // Strong bonus for multi-word exact subsets (handles Base Game + Subtitle)
                            } else {
                                score += 0.1 // Minor bonus for single-word exact subsets
                            }
                        }
                        
                        score = min(1.0, score) // Cap at 1.0
                        if score > bestScore { bestScore = score }
                    }
                }
                
                // 1.5) Space-Agnostic Exact Match (Catches "Open Quest" vs "OpenQuest")
                for q in validQueries {
                    let qNoSpaces = q.lowercased().replacingOccurrences(of: " ", with: "")
                    let cNoSpaces = datBase.replacingOccurrences(of: " ", with: "")
                    if qNoSpaces == cNoSpaces && qNoSpaces.count >= 4 {
                        bestScore = 1.0
                        break
                    }
                }
                
                // 2) Word-Bounded Substring Fallback (Prevents "ace quest" from triggering inside "space quest")
                for q in validQueries {
                    let qLower = q.lowercased()
                    if datBase.contains(qLower) || qLower.contains(datBase) {
                        let isWordBounded = datBase.range(of: "\\b" + NSRegularExpression.escapedPattern(for: qLower) + "\\b", options:[.regularExpression, .caseInsensitive]) != nil
                        let reverseWordBounded = qLower.range(of: "\\b" + NSRegularExpression.escapedPattern(for: datBase) + "\\b", options:[.regularExpression, .caseInsensitive]) != nil
                        
                        if isWordBounded || reverseWordBounded {
                            let minLen = Double(min(qLower.count, datBase.count))
                            let maxLen = Double(max(qLower.count, datBase.count))
                            let lengthRatio = maxLen > 0 ? (minLen / maxLen) : 0
                            
                            // Base score of 0.2, up to 0.95 for a near-identical string
                            var substringScore = 0.2 + (0.75 * lengthRatio)
                            
                            // Prefix Bonus: Base games often act as literal prefixes to their subtitled versions
                            if qLower.hasPrefix(datBase + " ") || datBase.hasPrefix(qLower + " ") || 
                               qLower.hasPrefix(datBase + ":") || datBase.hasPrefix(qLower + ":") {
                                substringScore += 0.35
                            } else if qLower.hasPrefix(datBase) || datBase.hasPrefix(qLower) {
                                substringScore += 0.25
                            }
                            
                            substringScore = min(1.0, substringScore) // Cap at 1.0
                            if substringScore > bestScore { bestScore = substringScore }
                        }
                    }
                }
                
                // Threshold: Needs at least a 65% overlap score to be considered a viable match
                if bestScore >= 0.65 {
                    pass4Candidates.append((info: info, score: bestScore))
                }
            }
            
            if !pass4Candidates.isEmpty {
                let maxScore = pass4Candidates.map { $0.score }.max() ?? 0.0
                // Keep only matches within 5% of the top score. 
                // This prevents the subsequent region tie-breaker from favoring a low-quality fuzzy match just because it has a (USA) tag.
                let topCandidates = pass4Candidates.filter { maxScore - $0.score <= 0.05 }
                candidates = topCandidates.map { $0.info }
                LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 4 found \(pass4Candidates.count) fuzzy match(es), sending top \(candidates.count) (score ~\(String(format: "%.2f", maxScore))) to region tie-breaker.")
            } else {
                LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): PASS 4 found 0 valid fuzzy matches.")
            }
        }

        guard !candidates.isEmpty else { return nil }
        let prefs = language.noIntroRegionPreference
        let sorted = candidates.sorted { a, b in
            let ra = Self.regionPreferenceRank(fullName: a.name, language: language)
            let rb = Self.regionPreferenceRank(fullName: b.name, language: language)
            if ra != rb { return ra < rb }
            let ta = Self.regionTieBreakOrdinal(fullName: a.name, language: language)
            let tb = Self.regionTieBreakOrdinal(fullName: b.name, language: language)
            if ta != tb { return ta < tb }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.name < b.name
        }
        if let best = sorted.first {
            let rank = Self.regionPreferenceRank(fullName: best.name, language: language)
            if rank >= prefs.count { LoggerService.debug(category: "ROMIdentifier", "IdentifyByName \(rom.name): name match without preferred region tag; used worldwide/Japan tie-break then length/lex order") }
        }
        return sorted.first
    }

    func computeCRC(for url: URL, systemID: String) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        
        var offset: UInt64 = 0
        
        // Header handling
        if systemID == "nes" {
            if let handle = try? FileHandle(forReadingFrom: url) {
                if let header = try? handle.read(upToCount: 4), header == Data([0x4E, 0x45, 53, 0x1A]) {
                    offset = 16
                }
                try? handle.close()
            }
        } else if ["genesis", "sms", "gamegear", "32x", "sg1000"].contains(systemID) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            if fileSize > 512 {
                let validSizes: Set<UInt64> = [131072, 262144, 393216, 524288, 655360, 786432, 1048576, 1310720, 1572864, 2097152, 2621440, 3145728, 4194304]
                let isPowerOfTwo = (fileSize > 0) && (fileSize & (fileSize - 1) == 0)
                if !validSizes.contains(fileSize) && !isPowerOfTwo {
                    let strippedSize = fileSize - 512
                    let isStrippedPowerOfTwo = (strippedSize > 0) && (strippedSize & (strippedSize - 1) == 0)
                    if validSizes.contains(strippedSize) || isStrippedPowerOfTwo {
                        offset = 512
                    }
                }
            }
        }
        
        // We offload the heavy hashing to a global concurrent queue so it obeys the 4-thread Semaphore limit, 
        // completely freeing up the swift async Task pool for fast string matching.
        return CRC32.compute(url: url, offset: offset)
    }
    
    private func stripGenesisHeaderIfNeeded(from data: Data) -> Data {
        let fileSize = data.count
        guard fileSize > 512 else { return data }
        let validSizes = [131072, 262144, 393216, 524288, 655360, 786432, 1048576, 1310720, 1572864, 2097152, 2621440, 3145728, 4194304]
        if validSizes.contains(fileSize) || isPowerOfTwo(fileSize) { return data }
        let strippedSize = fileSize - 512
        if validSizes.contains(strippedSize) || isPowerOfTwo(strippedSize) {
            LoggerService.debug(category: "ROMIdentifier", "Stripped 512-byte SMD header from ROM (original: \(fileSize) bytes → stripped: \(strippedSize) bytes)")
            return data.dropFirst(512)
        }
        return data
    }

    private func isPowerOfTwo(_ n: Int) -> Bool { guard n > 0 else { return false }; return (n & (n - 1)) == 0 }

    private static let numberWords: Set<String> = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]

    private static let romanNumeralPatterns: Set<String> = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix"]

    private static let trailingNumberSuffixPattern = try! NSRegularExpression(pattern: "\\s+(\\d+|[ivxIVX]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)$", options: .caseInsensitive)

    static func isProblematicNumberSuffixPartialMatch(query: String, candidate: String) -> Bool {
        guard query != candidate else { return false }
        let queryLower = query.lowercased()
        let candidateLower = candidate.lowercased()
        let longer: String, shorter: String
        if queryLower.count > candidateLower.count { longer = queryLower; shorter = candidateLower } else { longer = candidateLower; shorter = queryLower }
        guard longer.contains(shorter) else { return false }
        let hasTrailingNumberSuffix = trailingNumberSuffixPattern.firstMatch(in: longer, range: NSRange(longer.startIndex..., in: longer)) != nil
        if hasTrailingNumberSuffix { return true }
        let extraPart = longer.replacingOccurrences(of: shorter, with: "").trimmingCharacters(in: .whitespaces)
        let acceptedArticles: Set<String> = ["the", "a", "an", "of", "and", "le", "la", "les", "el", "de", "del", "los", "las", "il", "un", "une"]
        let extraWords = extraPart.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if extraWords.allSatisfy({ acceptedArticles.contains($0) }) { return false }
        return false
    }
    
    // MARK: - Disc Serial Extraction
    
    // Attempts to extract a PlayStation serial (PS1, PS2, PSP) from a disc image.
    // This is much faster than hashing a multi-GB ISO.
    func extractSonySerial(from url: URL) async -> String? {
        let romPath = url
        return await Task.detached(priority: .userInitiated) {
            let scoped = romPath.startAccessingSecurityScopedResource()
            defer { if scoped { romPath.stopAccessingSecurityScopedResource() } }
            
            guard let fileHandle = try? FileHandle(forReadingFrom: romPath) else { return nil }
            defer { try? fileHandle.close() }
            
            // We scan the first 2MB of the file for common Sony serial patterns.
            // SYSTEM.CNF and PARAM.SFO are almost always located within the first 1-2MB of an ISO.
            do {
                if #available(macOS 10.15.4, *) {
                    try fileHandle.seek(toOffset: 0)
                    let data = try fileHandle.read(upToCount: 2048 * 1024) ?? Data() // Read 2MB
                    
                    if let string = String(data: data, encoding: .ascii) {
                        // Pattern 1: PS1/PS2 executables in SYSTEM.CNF (e.g., SLUS_200.71;1)
                        // Note: Some use _ and . while others use - and .
                        let ps2Pattern = "[A-Z]{4}[_-][0-9]{3}[.][0-9]{2}"
                        if let regex = try? NSRegularExpression(pattern: ps2Pattern, options: []),
                           let match = regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.count)) {
                            if let range = Range(match.range, in: string) {
                                let serial = String(string[range]).replacingOccurrences(of: "_", with: "-")
                                LoggerService.debug(category: "ROMIdentifier", "For \(url): Found Sony serial candidate: \(serial)")
                                return serial
                            }
                        }
                        
                        // Pattern 2: PSP PARAM.SFO (e.g., ULUS-10001)
                        let pspPattern = "[A-Z]{4}-[0-9]{5}"
                        if let regex = try? NSRegularExpression(pattern: pspPattern, options: []),
                           let match = regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.count)) {
                            if let range = Range(match.range, in: string) {
                                let serial = String(string[range])
                                LoggerService.debug(category: "ROMIdentifier", "For \(url): Found PSP serial candidate: \(serial)")
                                return serial
                            }
                        }
                    }
                }
            } catch {
                LoggerService.debug(category: "ROMIdentifier", "For \(url): Error reading disc for serial: \(error.localizedDescription)")
            }
            return nil
        }.value
    }
}

struct LibretroDatGame {
    var name: String = ""
    var description: String = ""
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var crcs: [String] = []
}

actor LibretroDatabaseLibrary {
    static let shared = LibretroDatabaseLibrary()
    private static let gbFamilyCacheKey = "gb+gbc"

    private static func isGbFamily(_ systemID: String) -> Bool { systemID == "gb" || systemID == "gbc" }

    private static func tagGameInfo(_ info: GameInfo, thumbnailLookupSystemID: String) -> GameInfo {
        GameInfo(name: info.name, year: info.year, publisher: info.publisher, developer: info.developer, genre: info.genre, crc: info.crc, thumbnailLookupSystemID: thumbnailLookupSystemID)
    }

    // TODO: make this dynamic
    private static let libretroDatBasenameOverrides: [String: String] = [
        "nes": "Nintendo - Nintendo Entertainment System.dat", "snes": "Nintendo - Super Nintendo Entertainment System.dat",
        "n64": "Nintendo - Nintendo 64.dat", "nds": "Nintendo - Nintendo DS.dat", "gb": "Nintendo - Game Boy.dat",
        "gbc": "Nintendo - Game Boy Color.dat", "gba": "Nintendo - Game Boy Advance.dat", "genesis": "Sega - Mega Drive - Genesis.dat",
        "sms": "Sega - Master System - Mark III.dat", "gamegear": "Sega - Game Gear.dat", "32x": "Sega - 32X.dat",
        "psx": "Sony - PlayStation.dat", "atari2600": "Atari - 2600.dat", "atari5200": "Atari - 5200.dat", "atari7800": "Atari - 7800.dat",
        "lynx": "Atari - Lynx.dat", "jaguar": "Atari - Jaguar.dat", "mame": "MAME.dat", "pce": "NEC - PC Engine - TurboGrafx 16.dat",
        "wonderswan": "Bandai - WonderSwan.dat", "wswanc": "Bandai - WonderSwan Color.dat",
    ]

    // TODO: make this dynamic
    private static let redumpOnlySystems: Set<String> = ["psx", "ps2", "psp", "psvita", "ps3", "segacd", "pcecd", "pcfx", "pc98", "jaguar_cd", "cd32", "cdtv", "wii", "gcn"]

    private static let mameRdbBasenames: [String] = ["MAME.rdb", "MAME 2016.rdb", "MAME 2015.rdb", "MAME 2010.rdb", "MAME 2003-Plus.rdb", "MAME 2003.rdb", "MAME 2000.rdb"]

    private var databases: [String: [String: GameInfo]] = [:]

    private func datBasenamesToTry(for system: SystemInfo) -> [String] {
        var ordered: [String] = []; var seen = Set<String>()
        func append(_ name: String) { guard !seen.contains(name) else { return }; seen.insert(name); ordered.append(name) }
        if let exact = Self.libretroDatBasenameOverrides[system.id] { append(exact) }
        var primary = "\(system.name).dat"
        if !system.manufacturer.isEmpty && system.manufacturer != "Various" {
            let nameLower = system.name.lowercased(), mfrLower = system.manufacturer.lowercased()
            if nameLower.hasPrefix(mfrLower) {
                let remainder = system.name.dropFirst(mfrLower.count).trimmingCharacters(in: .whitespaces)
                if remainder.isEmpty { primary = "\(system.name).dat"  } else { primary = "\(system.manufacturer) - \(remainder).dat" }
            } else { primary = "\(system.manufacturer) - \(system.name).dat" }
        }
        append(primary); append("\(system.name).dat"); append("\(system.manufacturer.isEmpty ? "" : "\(system.manufacturer) ")\(system.name).dat")
        return ordered
    }

    private func rdbBasenamesToTry(for system: SystemInfo) -> [String] {
        if system.id == "mame" { return Self.mameRdbBasenames }
        return datBasenamesToTry(for: system).map { ($0 as NSString).deletingPathExtension + ".rdb" }
    }

    func parseDat(contentsOf url: URL) -> [String: GameInfo] {
        LoggerService.debug(category: "LibretroDB", "Parsing DAT file: \(url.path)")
        guard let lines = try? String(contentsOf: url).components(separatedBy: .newlines) else {
            LoggerService.libretroDBWarn("Failed to read DAT file: \(url.path)"); return [:]
        }
        LoggerService.debug(category: "LibretroDB", "DAT file has \(lines.count) lines")
        var database: [String: GameInfo] = [:]; var currentGame: LibretroDatGame?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("game (") || trimmed.hasPrefix("machine (") { currentGame = LibretroDatGame() }
            else if trimmed == ")" && currentGame != nil {
                let nameToUse = ROMIdentifierService.titleFromDatGame(name: currentGame!.name, description: currentGame!.description)
                for crc in currentGame!.crcs { database[crc.uppercased()] = GameInfo(name: nameToUse, year: currentGame?.year, publisher: currentGame?.publisher ?? currentGame?.developer, developer: currentGame?.developer, genre: currentGame?.genre, crc: crc.uppercased(), thumbnailLookupSystemID: nil) }
                currentGame = nil
            } else if currentGame != nil {
                if trimmed.hasPrefix("name ") { currentGame?.name = extractQuotes(trimmed) ?? "" }
                else if trimmed.hasPrefix("description ") { currentGame?.description = extractQuotes(trimmed) ?? "" }
                else if trimmed.hasPrefix("comment ") && (currentGame?.description.isEmpty ?? true) { currentGame?.description = extractQuotes(trimmed) ?? "" }
                else if trimmed.hasPrefix("year ") { currentGame?.year = extractQuotes(trimmed) }
                else if trimmed.hasPrefix("developer ") { currentGame?.developer = extractQuotes(trimmed) }
                else if trimmed.hasPrefix("publisher ") { currentGame?.publisher = extractQuotes(trimmed) }
                else if trimmed.hasPrefix("genre ") || trimmed.hasPrefix("category ") { currentGame?.genre = extractQuotes(trimmed) }
                else if trimmed.hasPrefix("rom (") || trimmed.hasPrefix("disk (") {
                    if let crcRange = trimmed.range(of: "crc ") {
                        let substring = trimmed[crcRange.upperBound...]
                        if let firstWord = substring.components(separatedBy: .whitespaces).first { currentGame?.crcs.append(firstWord.trimmingCharacters(in: CharacterSet(charactersIn: ")")).uppercased()) }
                    }
                }
            }
        }
        LoggerService.debug(category: "LibretroDB", "Parsed DAT \(url.lastPathComponent) → \(database.count) CRC entries")
        return database
    }

    private func extractQuotes(_ string: String) -> String? {
        if let start = string.firstIndex(of: "\""), let end = string[string.index(after: start)...].firstIndex(of: "\"") { return String(string[string.index(after: start)..<end]) }
        return nil
    }

    func findVariantEntries(for gameName: String, systemID: String) async -> [String] {
        guard let system = SystemDatabase.system(forID: systemID) else { return [] }
        let fullDb = await fetchAndLoadDat(for: system)
        let baseTitle = ROMIdentifierService.normalizedComparableTitle(gameName)
        guard baseTitle.count >= 2 else { return [] }
        var variants: [String] = []
        for (_, info) in fullDb { if ROMIdentifierService.normalizedComparableTitle(info.name) == baseTitle { variants.append(info.name) } }
        return variants
    }

    private func fetchAndLoadDat(forSystemID systemID: String) async -> [String: GameInfo] {
        if let db = databases[systemID] { return db }
        if systemID == "gb" || systemID == "gbc" { if let merged = databases[LibretroDatabaseLibrary.gbFamilyCacheKey] { return merged } }
        return [:]
    }

    func fetchAndLoadDat(for system: SystemInfo) async -> [String: GameInfo] {
        LoggerService.debug(category: "LibretroDB", "fetchAndLoadDat called for systemID=\(system.id) (displayName=\(system.name))")
        if Self.isGbFamily(system.id) {
            if let merged = databases[Self.gbFamilyCacheKey] { LoggerService.debug(category: "LibretroDB", "Cache hit: merged GB+GBC (\(merged.count) CRC entries)"); return merged }
            let partnerID = system.id == "gb" ? "gbc" : "gb"
            guard let partner = SystemDatabase.system(forID: partnerID) else { LoggerService.libretroDBError("GB family merge failed — missing partner system \(partnerID)"); return await loadSingleSystemDatabase(for: system) }
            let primary = await loadSingleSystemDatabase(for: system); LoggerService.debug(category: "LibretroDB", "Primary \(system.id) → \(primary.count) CRC entries")
            let secondary = await loadSingleSystemDatabase(for: partner); LoggerService.debug(category: "LibretroDB", "Partner \(partnerID) → \(secondary.count) CRC entries")
            var merged: [String: GameInfo] = [:]
            for (crc, info) in primary { merged[crc] = Self.tagGameInfo(info, thumbnailLookupSystemID: system.id) }
            var overlap = 0
            for (crc, info) in secondary { if merged[crc] != nil { overlap += 1 } else { merged[crc] = Self.tagGameInfo(info, thumbnailLookupSystemID: partner.id) } }
            LoggerService.debug(category: "LibretroDB", "Merged GB+GBC → \(merged.count) unique CRCs (\(overlap) overlapping)")
            databases[Self.gbFamilyCacheKey] = merged; databases["gb"] = merged; databases["gbc"] = merged
            return merged
        }
        if let db = databases[system.id] { LoggerService.debug(category: "LibretroDB", "Cache hit: \(system.id) (\(db.count) CRC entries)"); return db }
        LoggerService.debug(category: "LibretroDB", "Cache miss for \(system.id), loading...")
        let loaded = await loadSingleSystemDatabase(for: system); databases[system.id] = loaded; return loaded
    }

    private func loadSingleSystemDatabase(for system: SystemInfo) async -> [String: GameInfo] {
        LoggerService.debug(category: "LibretroDB", "loadSingleSystemDatabase called for systemID=\(system.id) name=\(system.name)")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // First we ensure the local directories exist, even if they may be empty. This way we can reliably log the paths we're using and avoid confusion about where files should be stored.
        let datsDir = appSupport.appendingPathComponent("TruchieEmu/Dats", isDirectory: true)
        let rdbDir = appSupport.appendingPathComponent("TruchieEmu/Rdb", isDirectory: true)
        try? FileManager.default.createDirectory(at: datsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rdbDir, withIntermediateDirectories: true)
        LoggerService.debug(category: "LibretroDB", "DATs directory: \(datsDir.path)"); LoggerService.debug(category: "LibretroDB", "RDBs directory: \(rdbDir.path)")
        let localNames = datBasenamesToTry(for: system)
        let baseUrl = "https://raw.githubusercontent.com/libretro/libretro-database/master/"
        LoggerService.debug(category: "LibretroDB", "=== STEP 1: Scanning local DATs in \(datsDir.path) ===")
        for fileName in localNames {
            let localUrl = datsDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: localUrl.path) {
                LoggerService.debug(category: "LibretroDB", "Found local DAT file: \(localUrl.path)")
                let db = parseDat(contentsOf: localUrl)
                if db.isEmpty { 
                    LoggerService.libretroDBWarn("Local DAT \(fileName) exists but parsed 0 entries — continuing") 
                } else { 
                    LoggerService.debug(category: "LibretroDB", "Step 1: SUCCESS — loaded local DAT with \(db.count) entries"); 
                    return db 
                }
            } 
        }
        LoggerService.debug(category: "LibretroDB", "No local DAT found for systemID=\(system.id) (tried: \(localNames.joined(separator: ", ")))")  

        LoggerService.debug(category: "LibretroDB", "=== STEP 2: Looking for resource bundle dats at \(Bundle.main.resourcePath) ===")
        // Get the dat from the resources <system.id>.dat if it exists, and write it to the datsDir for future use. This is because some of the older DATs are not available in the main libretro-database repo but are still very useful for identification.
        for fileName in localNames {
            // strip extension for resource lookup since bundled resources don's have to match the exact filename
            let expectedResourcePath = (fileName as NSString).deletingPathExtension
            if let resourceUrl = Bundle.main.url(forResource: expectedResourcePath, withExtension: "dat") {
                LoggerService.debug(category: "LibretroDB", "Found bundled DAT resource: \(expectedResourcePath) at \(resourceUrl.path)")
                let db = parseDat(contentsOf: resourceUrl)
                if !db.isEmpty {
                    LoggerService.debug(category: "LibretroDB", "Step 2: SUCCESS — loaded bundled DAT \(expectedResourcePath) with \(db.count) entries")
                    return db 
                } else {
                    LoggerService.libretroDBWarn("Bundled DAT \(expectedResourcePath) found but parsed 0 entries — continuing")
                }   
            } 
        }
        LoggerService.debug(category: "LibretroDB", "No bundled DAT found for systemID=\(system.id) (tried: \(localNames.joined(separator: ", ")))")


        LoggerService.debug(category: "LibretroDB", "=== STEP 3: Downloading No-Intro DAT (metadat/no-intro) from \(baseUrl) ===")
        let noIntroOnly = ["metadat/no-intro"]
        if let db = await downloadDatRemote(systemID: system.id, names: localNames, remotePaths: noIntroOnly, datsDir: datsDir, baseUrl: baseUrl) { 
            LoggerService.debug(category: "LibretroDB", "Step 3: SUCCESS — downloaded No-Intro DAT with \(db.count) entries"); 
            return db 
        }

        LoggerService.debug(category: "LibretroDB", "=== STEP 4: Downloading other DAT trees from \(baseUrl) ===")
        let otherDatPaths = ["metadat/redump", "metadat/mame", "metadat/fba", "metadat/fbneo-split", "dat"]
        if let db = await downloadDatRemote(systemID: system.id, names: localNames, remotePaths: otherDatPaths, datsDir: datsDir, baseUrl: baseUrl) { 
            LoggerService.debug(category: "LibretroDB", "Step 4: SUCCESS — downloaded DAT with \(db.count) entries"); 
            return db 
        }

        LoggerService.debug(category: "LibretroDB", "=== STEP 5: Loading RDB (local then remote) from \(baseUrl) ===")
        if let db = await downloadRdbRemote(systemID: system.id, names: rdbBasenamesToTry(for: system), rdbDir: rdbDir, baseUrl: baseUrl) { 
            LoggerService.debug(category: "LibretroDB", "Step 5: SUCCESS — loaded RDB with \(db.count) entries"); 
            return db 
        }

        LoggerService.libretroDBError("=== FAILED === No usable DAT or RDB for systemID=\(system.id) (tried: \(localNames.joined(separator: ", ")))")
        return [:]
    }

    private func downloadDatRemote(systemID: String, names: [String], remotePaths: [String], datsDir: URL, baseUrl: String) async -> [String: GameInfo]? {
        for fileName in names {
            guard let encodedFile = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            for path in remotePaths {
                let checkUrlStr = baseUrl + path + "/" + encodedFile
                guard let checkUrl = URL(string: checkUrlStr) else { continue }
                guard let data = try? await URLSession.shared.data(from: checkUrl).0 else { continue }
                guard data.count > 100 else { continue }
                guard let stringContent = String(data: data, encoding: .utf8), stringContent.contains("game (") || stringContent.contains("machine (") else { continue }
                let localUrl = datsDir.appendingPathComponent(fileName)
                try? data.write(to: localUrl)
                let db = parseDat(contentsOf: localUrl)
                if !db.isEmpty { return db }
            }
        }
        return nil
    }

    private func downloadRdbRemote(systemID: String, names: [String], rdbDir: URL, baseUrl: String) async -> [String: GameInfo]? {
        for fileName in names {
            let localUrl = rdbDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: localUrl.path), let data = try? Data(contentsOf: localUrl), data.count > 32 { let db = LibretroRDBParser.buildCRCIndex(data: data); if !db.isEmpty { return db } }
        }
        for fileName in names {
            guard let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            let checkUrlStr = baseUrl + "rdb/" + encoded; guard let checkUrl = URL(string: checkUrlStr) else { continue }
            guard let data = try? await URLSession.shared.data(from: checkUrl).0 else { continue }
            guard data.count > 100 else { continue }
            guard data.starts(with: Data("RARCHDB\0".utf8)) else { continue }
            let localUrl = rdbDir.appendingPathComponent(fileName); try? data.write(to: localUrl)
            let db = LibretroRDBParser.buildCRCIndex(data: data); if !db.isEmpty { return db }
        }
        return nil
    }
}

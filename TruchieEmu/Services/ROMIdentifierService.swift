import Foundation

struct CRC32 {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
            table[i] = crc
        }
        return table
    }()

    static func compute(_ data: Data) -> String {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return String(format: "%08X", crc ^ 0xFFFFFFFF)
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

final class ROMIdentifierService: Sendable {
    static let shared = ROMIdentifierService()

    func identify(rom: ROM) async -> ROMIdentifyResult {
        guard let systemID = rom.systemID,
              let system = SystemDatabase.system(forID: systemID) else {
            LoggerService.romIdentifyWarn("Identify: no system for ROM \(rom.path.lastPathComponent)")
            return .noSystem
        }

        if systemID == "mame" {
            let shortName = rom.path.deletingPathExtension().lastPathComponent.lowercased()
            
            // First: try the unified MAME database (multi-core, 50K+ entries)
            if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
                if unifiedEntry.isRunnableInAnyCore && !unifiedEntry.isBIOS {
                    LoggerService.romIdentify("Identify: MAME game identified via unified database → \(unifiedEntry.description) [cores: \(unifiedEntry.compatibleCores.joined(separator: ", "))]")
                    return .identified(GameInfo(
                        name: unifiedEntry.description,
                        year: unifiedEntry.year,
                        publisher: unifiedEntry.manufacturer,
                        developer: unifiedEntry.manufacturer,
                        genre: nil,
                        crc: "",
                        thumbnailLookupSystemID: nil
                    ))
                } else if unifiedEntry.isBIOS {
                    LoggerService.romIdentify("Identify: MAME BIOS identified via unified database → \(unifiedEntry.description)")
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
                    LoggerService.romIdentifyWarn("Identify: MAME game '\(shortName)' found in unified database but not runnable in any core → \(unifiedEntry.description)")
                    return .crcNotInDatabase(crc: shortName)
                }
            }
            
            // Not in any MAME database — no point searching libretro DAT (bundled MAME DBs are more comprehensive)
            LoggerService.romIdentify("Identify: MAME game '\(shortName)' not in bundled database — hiding")
            return .crcNotInDatabase(crc: shortName)
        }

        LoggerService.romIdentify("Identify: START system=\(systemID) file=\(rom.path.lastPathComponent)")

        let db = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
        if db.isEmpty {
            LoggerService.romIdentifyError("Identify: empty database for system \(systemID)")
            return .databaseUnavailable
        }
        LoggerService.romIdentify("Identify: database loaded — \(db.count) CRC entries for \(systemID)")

        let romPath = rom.path
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: romPath.path)[.size] as? Int64) ?? 0
        let isLargeFile = fileSize > 50 * 1024 * 1024 // > 50MB
        
        // Optimization: For Sony CD-based systems, try serial extraction (FASTEST)
        if ["psx", "ps2", "psp"].contains(systemID) {
            if let serial = await extractSonySerial(from: romPath) {
                LoggerService.romIdentify("Identify: Checking database for serial '\(serial)'...")
                let normalizedSerial = serial.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: ".", with: "").lowercased()
                
                for info in db.values {
                    let infoName = info.name.lowercased()
                    // Many DATs include the serial in the title, e.g. "Game Name (USA) (SLUS-20071)"
                    if infoName.contains(normalizedSerial) || infoName.contains(serial.lowercased()) {
                        LoggerService.romIdentify("Identify: SUCCESS (Serial Path) → \(info.name) matched serial \(serial)")
                        return .identified(info)
                    }
                }
                LoggerService.romIdentify("Identify: Serial '\(serial)' not found in Libretro DB, falling back...")
            }
        }

        // Optimization: For large files (ISOs, big ROMs), try name-based identification first.
        // If we find an exact match by name, we can skip the multi-gigabyte CRC calculation.
        if isLargeFile {
            LoggerService.romIdentify("Identify: Large file detected (\(fileSize / 1024 / 1024)MB). Trying name-based search first...")
            let language = Self.currentEmulatorLanguage()
            if let byName = identifyByName(rom: rom, database: db, language: language) {
                LoggerService.romIdentify("Identify: SUCCESS (Name Path) → \(byName.name) found by name, skipping CRC.")
                return .identifiedFromName(byName)
            }
            LoggerService.romIdentify("Identify: Name-based search failed for large file, falling back to CRC hashing...")
        }

        // Perform heavy file I/O and hashing on a background thread to avoid blocking the MainActor.
        guard let crc = await Task.detached(priority: .userInitiated, operation: {
            self.computeCRC(for: romPath, systemID: systemID)
        }).value else {
            LoggerService.romIdentifyError("Identify: CRC read failed for \(rom.path.path)")
            return .romReadFailed("Could not read the ROM file. If the library is on a removable drive or you moved files, re-add the folder in Settings.")
        }

        let key = crc.uppercased()
        LoggerService.romIdentify("Identify: ROM CRC=\(key)")

        if let info = db[key] {
            if let thumb = info.thumbnailLookupSystemID, thumb != systemID {
                LoggerService.romIdentify("Identify: CRC HIT → \(info.name) (thumbnails: use system \(thumb), ROM is \(systemID))")
            } else {
                LoggerService.romIdentify("Identify: CRC HIT → \(info.name)")
            }
            return .identified(info)
        }

        LoggerService.romIdentify("Identify: no CRC match for \(key), falling back to name search...")
        let language = Self.currentEmulatorLanguage()
        if let byName = identifyByName(rom: rom, database: db, language: language) {
            LoggerService.romIdentify("Identify: NAME MATCH → \(byName.name) (language=\(language.name))")
            return .identifiedFromName(byName)
        }

        LoggerService.romIdentifyWarn("Identify: NOT FOUND — CRC \(key) not in database and name search found 0 matches for \(systemID)")
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
        return result.lowercased().replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedComparableTitle(_ s: String) -> String {
        let stripped = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(s)
        return stripped.lowercased().replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func titleFromDatGame(name: String, description: String) -> String {
        guard !description.isEmpty else { return name }
        if description.count > 150 { return name }
        let sentenceEndCount = description.split(whereSeparator: { $0.isNewline }).filter { line in
            line.contains(".") || line.contains("!") || line.contains("?")
        }.count
        if sentenceEndCount >= 2 { return name }
        return description
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
        for (t, a) in textToArabic { let esc = NSRegularExpression.escapedPattern(for: t); let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: String(a), options: .regularExpression); if s != normalized { variants.insert(s) } }
        for (t, a) in textToArabic { if let rf = arabicToRoman[a] { let esc = NSRegularExpression.escapedPattern(for: t); let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"; let s = normalized.replacingOccurrences(of: p, with: rf, options: .regularExpression); if s != normalized { variants.insert(s) } } }
        let t = normalized.trimmingCharacters(in: .whitespaces)
        for pat in [" 1$", " (?i:i)(?-i)$", " (?i:one)(?-i)$"] { let s = t.replacingOccurrences(of: pat, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces); if s != t && s.count >= 2 { variants.insert(s) } }
        return Array(variants)
    }

    private func identifyByName(rom: ROM, database: [String: GameInfo], language: EmulatorLanguage) -> GameInfo? {
        let stem = rom.path.deletingPathExtension().lastPathComponent
        var cleaned = LibretroThumbnailResolver.stripRomFilenameTags(stem)
        cleaned = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(cleaned)
        let queryBase = Self.normalizedComparableTitle(cleaned)
        guard queryBase.count >= 2 else {
            LoggerService.romIdentifyWarn("Identify: name search skipped — queryBase='\(queryBase)' too short (<2 chars)")
            return nil
        }

        LoggerService.romIdentify("Identify: name search START — file='\(stem)', cleaned='\(cleaned)', queryBase='\(queryBase)'")
        LoggerService.romIdentify("Identify: database has \(database.count) entries to search")

        LoggerService.romIdentify("Identify: PASS 1 — exact match on queryBase='\(queryBase)'")
        var exact: [GameInfo] = []
        var pass1Checked = 0
        for info in database.values {
            let datBase = Self.normalizedComparableTitle(info.name)
            pass1Checked += 1
            if datBase == queryBase {
                exact.append(info)
                if exact.count <= 3 {
                    LoggerService.romIdentify("Identify: PASS 1 matched → '\(info.name)'")
                }
            }
        }
        if exact.count > 3 { LoggerService.romIdentify("Identify: PASS 1 matched \(exact.count - 3) more entry(ies)") }
        if !exact.isEmpty { LoggerService.romIdentify("Identify: PASS 1 FOUND \(exact.count) exact match(es)") }
        else { LoggerService.romIdentify("Identify: PASS 1 found 0 matches (checked \(pass1Checked) entries)") }

        if exact.isEmpty {
            let variants = Self.romanNumeralVariants(of: queryBase)
            LoggerService.romIdentify("Identify: PASS 2 — number variants (\(variants.count) variants generated)")
            if !variants.isEmpty {
                for variant in variants {
                    LoggerService.romIdentify("Identify: PASS 2 trying variant='\(variant)'")
                    var hit = false
                    for info in database.values {
                        if Self.normalizedComparableTitle(info.name) == variant { exact.append(info); LoggerService.romIdentify("Identify: PASS 2 matched variant='\(variant)' → '\(info.name)'"); hit = true }
                    }
                    if hit { break }
                }
            } else { LoggerService.romIdentify("Identify: PASS 2 skipped — no variants generated") }
            if exact.isEmpty { LoggerService.romIdentify("Identify: PASS 2 found 0 matches") }
        }

        if exact.isEmpty {
            let aggressiveQuery = Self.aggressivelyNormalizedTitle(stem)
            LoggerService.romIdentify("Identify: PASS 3 — aggressive normalization")
            LoggerService.romIdentify("Identify: PASS 3 query='\(stem)' → '\(aggressiveQuery)'")
            if !aggressiveQuery.isEmpty && aggressiveQuery.count >= 2 {
                var pass3Checked = 0
                for info in database.values { let datAggressive = Self.aggressivelyNormalizedTitle(info.name); pass3Checked += 1; if datAggressive == aggressiveQuery { exact.append(info); LoggerService.romIdentify("Identify: PASS 3 matched aggressive query → '\(info.name)'") } }
                if exact.isEmpty {
                    let aggressiveVariants = Self.romanNumeralVariants(of: aggressiveQuery)
                    LoggerService.romIdentify("Identify: PASS 3 generated \(aggressiveVariants.count) number variants for aggressive query='\(aggressiveQuery)'")
                    for variant in aggressiveVariants {
                        LoggerService.romIdentify("Identify: PASS 3 trying aggressive variant='\(variant)'")
                        for info in database.values { if Self.aggressivelyNormalizedTitle(info.name) == variant { exact.append(info); LoggerService.romIdentify("Identify: PASS 3 matched aggressive variant='\(variant)' → '\(info.name)'"); break } }; if !exact.isEmpty { break }
                    }
                }
            } else { LoggerService.romIdentify("Identify: PASS 3 skipped — aggressiveQuery too short or empty") }
            if exact.isEmpty { LoggerService.romIdentify("Identify: PASS 3 found 0 matches") }
        }

        var candidates = exact
        if candidates.isEmpty {
            LoggerService.romIdentify("Identify: PASS 4 — substring/fuzzy matching (base query)")
            var pass4BaseChecked = 0, pass4BaseMatched = 0
            for info in database.values {
                let datBase = Self.normalizedComparableTitle(info.name)
                guard datBase.count >= 3, queryBase.count >= 3 else { continue }
                pass4BaseChecked += 1
                if Self.isProblematicNumberSuffixPartialMatch(query: queryBase, candidate: datBase) { continue }
                let lenRatio = Double(queryBase.count) / Double(datBase.count)
                if queryBase.contains(datBase) && lenRatio > 1.5 { continue }
                if datBase.contains(queryBase) || queryBase.contains(datBase) {
                    candidates.append(info)
                    pass4BaseMatched += 1
                    if pass4BaseMatched <= 3 {
                        LoggerService.romIdentify("Identify: PASS 4 substring match → '\(info.name)'")
                    }
                }
            }
            if pass4BaseMatched > 3 { LoggerService.romIdentify("Identify: PASS 4 matched \(pass4BaseMatched - 3) more entry(ies)") }
            LoggerService.romIdentify("Identify: PASS 4 (base query) checked \(pass4BaseChecked) entries, found \(pass4BaseMatched) substring match(es)")
            if candidates.isEmpty {
                let variants = Self.romanNumeralVariants(of: queryBase)
                LoggerService.romIdentify("Identify: PASS 4 (Roman variants) — trying \(variants.count) variants")
                for variant in variants {
                    guard variant.count >= 3 else { continue }
                    LoggerService.romIdentify("Identify: PASS 4 trying Roman variant='\(variant)'")
                    for info in database.values {
                        let datBase = Self.normalizedComparableTitle(info.name)
                        guard datBase.count >= 3 else { continue }
                        if Self.isProblematicNumberSuffixPartialMatch(query: variant, candidate: datBase) { continue }
                        if datBase.contains(variant) || variant.contains(datBase) { candidates.append(info); LoggerService.romIdentify("Identify: PASS 4 matched Roman variant='\(variant)' → '\(info.name)'"); break }
                    }
                    if !candidates.isEmpty { break }
                }
                if candidates.isEmpty { LoggerService.romIdentify("Identify: PASS 4 (Roman variants) found 0 matches") }
            }
            if candidates.isEmpty {
                let aggressiveQuery = Self.aggressivelyNormalizedTitle(stem)
                if !aggressiveQuery.isEmpty && aggressiveQuery.count >= 3 {
                    LoggerService.romIdentify("Identify: PASS 4 (last resort) — aggressive substring match")
                    var pass4AggChecked = 0, pass4AggMatched = 0
                    for info in database.values {
                        let datAggressive = Self.aggressivelyNormalizedTitle(info.name)
                        guard datAggressive.count >= 3 else { continue }
                        pass4AggChecked += 1
                        if Self.isProblematicNumberSuffixPartialMatch(query: aggressiveQuery, candidate: datAggressive) { continue }
                        if datAggressive.contains(aggressiveQuery) || aggressiveQuery.contains(datAggressive) {
                            candidates.append(info)
                            pass4AggMatched += 1
                            if pass4AggMatched <= 3 {
                                LoggerService.romIdentify("Identify: PASS 4 aggressive substring match → '\(info.name)'")
                            }
                        }
                    }
                    if pass4AggMatched > 3 { LoggerService.romIdentify("Identify: PASS 4 matched \(pass4AggMatched - 3) more aggressive entries") }
                    if pass4AggMatched > 0 { LoggerService.romIdentify("Identify: PASS 4 (last resort) found \(pass4AggMatched) aggressive substring match(es)") }
                    else { LoggerService.romIdentify("Identify: PASS 4 (last resort) found 0 matches (checked \(pass4AggChecked) entries)") }
                } else { LoggerService.romIdentify("Identify: PASS 4 (last resort) skipped — aggressiveQuery too short or empty") }
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
            if rank >= prefs.count { LoggerService.romIdentifyWarn("Identify: name match without preferred region tag; used worldwide/Japan tie-break then length/lex order") }
        }
        return sorted.first
    }

    func computeCRC(for url: URL, systemID: String) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let fullData = try Data(contentsOf: url, options: .mappedIfSafe)
            let dataToHash: Data
            switch systemID {
            case "nes":
                if fullData.count >= 16 && fullData.prefix(4) == Data([0x4E, 0x45, 0x53, 0x1A]) { dataToHash = fullData.dropFirst(16) } else { dataToHash = fullData }
            case "genesis", "sms", "gamegear", "32x", "sg1000":
                dataToHash = stripGenesisHeaderIfNeeded(from: fullData)
            default:
                dataToHash = fullData
            }
            return CRC32.compute(dataToHash)
        } catch {
            LoggerService.romIdentifyError("CRC read error: \(error.localizedDescription)")
            return nil
        }
    }

    private func stripGenesisHeaderIfNeeded(from data: Data) -> Data {
        let fileSize = data.count
        guard fileSize > 512 else { return data }
        let validSizes = [131072, 262144, 393216, 524288, 655360, 786432, 1048576, 1310720, 1572864, 2097152, 2621440, 3145728, 4194304]
        if validSizes.contains(fileSize) || isPowerOfTwo(fileSize) { return data }
        let strippedSize = fileSize - 512
        if validSizes.contains(strippedSize) || isPowerOfTwo(strippedSize) {
            LoggerService.romIdentify("Stripped 512-byte SMD header from ROM (original: \(fileSize) bytes → stripped: \(strippedSize) bytes)")
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
    
    /// Attempts to extract a PlayStation serial (PS1, PS2, PSP) from a disc image.
    /// This is much faster than hashing a multi-GB ISO.
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
                                LoggerService.romIdentify("Found Sony serial candidate: \(serial)")
                                return serial
                            }
                        }
                        
                        // Pattern 2: PSP PARAM.SFO (e.g., ULUS-10001)
                        let pspPattern = "[A-Z]{4}-[0-9]{5}"
                        if let regex = try? NSRegularExpression(pattern: pspPattern, options: []),
                           let match = regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.count)) {
                            if let range = Range(match.range, in: string) {
                                let serial = String(string[range])
                                LoggerService.romIdentify("Found PSP serial candidate: \(serial)")
                                return serial
                            }
                        }
                    }
                }
            } catch {
                LoggerService.romIdentifyWarn("Error reading disc for serial: \(error.localizedDescription)")
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

    private static let libretroDatBasenameOverrides: [String: String] = [
        "nes": "Nintendo - Nintendo Entertainment System.dat", "snes": "Nintendo - Super Nintendo Entertainment System.dat",
        "n64": "Nintendo - Nintendo 64.dat", "nds": "Nintendo - Nintendo DS.dat", "gb": "Nintendo - Game Boy.dat",
        "gbc": "Nintendo - Game Boy Color.dat", "gba": "Nintendo - Game Boy Advance.dat", "genesis": "Sega - Mega Drive - Genesis.dat",
        "sms": "Sega - Master System - Mark III.dat", "gamegear": "Sega - Game Gear.dat", "32x": "Sega - 32X.dat",
        "psx": "Sony - PlayStation.dat", "atari2600": "Atari - 2600.dat", "atari5200": "Atari - 5200.dat", "atari7800": "Atari - 7800.dat",
        "lynx": "Atari - Lynx.dat", "jaguar": "Atari - Jaguar.dat", "mame": "MAME.dat", "pce": "NEC - PC Engine - TurboGrafx 16.dat",
        "wonderswan": "Bandai - WonderSwan.dat", "wswanc": "Bandai - WonderSwan Color.dat",
    ]

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
        LoggerService.libretroDB("Parsing DAT file: \(url.path)")
        guard let lines = try? String(contentsOf: url).components(separatedBy: .newlines) else {
            LoggerService.libretroDBWarn("Failed to read DAT file: \(url.path)"); return [:]
        }
        LoggerService.libretroDB("DAT file has \(lines.count) lines")
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
        LoggerService.libretroDB("Parsed DAT \(url.lastPathComponent) → \(database.count) CRC entries")
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
        LoggerService.libretroDB("fetchAndLoadDat called for systemID=\(system.id) (displayName=\(system.name))")
        if Self.isGbFamily(system.id) {
            LoggerService.libretroDB("GB family detected (systemID=\(system.id)), checking merged cache")
            if let merged = databases[Self.gbFamilyCacheKey] { LoggerService.libretroDB("Cache hit: merged GB+GBC (\(merged.count) CRC entries)"); return merged }
            LoggerService.libretroDB("GB+GBC cache MISS, loading both databases and merging")
            let partnerID = system.id == "gb" ? "gbc" : "gb"
            guard let partner = SystemDatabase.system(forID: partnerID) else { LoggerService.libretroDBError("GB family merge failed — missing partner system \(partnerID)"); return await loadSingleSystemDatabase(for: system) }
            LoggerService.libretroDB("Loading primary system \(system.id), then partner \(partnerID)")
            LoggerService.libretroDB("Loading primary \(system.id) then partner \(partnerID), then merging")
            let primary = await loadSingleSystemDatabase(for: system); LoggerService.libretroDB("Primary \(system.id) → \(primary.count) CRC entries")
            let secondary = await loadSingleSystemDatabase(for: partner); LoggerService.libretroDB("Partner \(partnerID) → \(secondary.count) CRC entries")
            var merged: [String: GameInfo] = [:]
            for (crc, info) in primary { merged[crc] = Self.tagGameInfo(info, thumbnailLookupSystemID: system.id) }
            var overlap = 0
            for (crc, info) in secondary { if merged[crc] != nil { overlap += 1 } else { merged[crc] = Self.tagGameInfo(info, thumbnailLookupSystemID: partner.id) } }
            LoggerService.libretroDB("Merged GB+GBC → \(merged.count) unique CRCs (overlap=\(overlap)))")
            LoggerService.libretroDB("Merged GB+GBC → \(merged.count) unique CRCs (\(overlap) overlapping)")
            databases[Self.gbFamilyCacheKey] = merged; databases["gb"] = merged; databases["gbc"] = merged
            return merged
        }
        if let db = databases[system.id] { LoggerService.libretroDB("Cache hit: \(system.id) (\(db.count) CRC entries)"); return db }
        LoggerService.libretroDB("Cache miss for \(system.id), loading...")
        let loaded = await loadSingleSystemDatabase(for: system); databases[system.id] = loaded; return loaded
    }

    private func loadSingleSystemDatabase(for system: SystemInfo) async -> [String: GameInfo] {
        LoggerService.libretroDB("loadSingleSystemDatabase called for systemID=\(system.id) name=\(system.name)")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let datsDir = appSupport.appendingPathComponent("TruchieEmu/Dats", isDirectory: true)
        let rdbDir = appSupport.appendingPathComponent("TruchieEmu/Rdb", isDirectory: true)
        try? FileManager.default.createDirectory(at: datsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rdbDir, withIntermediateDirectories: true)
        LoggerService.libretroDB("DATs directory: \(datsDir.path)"); LoggerService.libretroDB("RDBs directory: \(rdbDir.path)")
        let localNames = datBasenamesToTry(for: system)
        let baseUrl = "https://raw.githubusercontent.com/libretro/libretro-database/master/"
        LoggerService.info(category: "LibretroDB", "Step 1/4: Scanning local DATs in \(datsDir.path)")
        LoggerService.libretroDB("=== STEP 1: Scanning local DATs ===")
        LoggerService.libretroDB("Trying DAT filenames: \(localNames.joined(separator: ", "))")
        for fileName in localNames {
            let localUrl = datsDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: localUrl.path) {
                LoggerService.libretroDB("Found local DAT file: \(localUrl.path)")
                let db = parseDat(contentsOf: localUrl)
                if db.isEmpty { LoggerService.libretroDBWarn("Local DAT \(fileName) exists but parsed 0 entries — continuing") }
                else { LoggerService.libretroDB("Step 1: FOUND local DAT \(fileName) with \(db.count) entries"); return db }
            } else { LoggerService.libretroDB("Local DAT not found: \(localUrl.path)") }
        }
        LoggerService.libretroDB("Step 1 complete: no usable local DAT found")
        LoggerService.info(category: "LibretroDB", "Step 2/4: Downloading No-Intro DAT")
        LoggerService.libretroDB("=== STEP 2: Downloading No-Intro DAT (metadat/no-intro) ===")
        let noIntroOnly = ["metadat/no-intro"]
        if let db = await downloadDatRemote(systemID: system.id, names: localNames, remotePaths: noIntroOnly, datsDir: datsDir, baseUrl: baseUrl) { LoggerService.libretroDB("Step 2: SUCCESS — downloaded No-Intro DAT with \(db.count) entries"); return db }
        LoggerService.libretroDB("Step 2 complete: No-Intro DAT not found or failed")
        LoggerService.info(category: "LibretroDB", "Step 3/4: Downloading other DAT trees")
        LoggerService.libretroDB("=== STEP 3: Downloading other DAT trees ===")
        let otherDatPaths = ["metadat/redump", "metadat/mame", "metadat/fba", "metadat/fbneo-split", "dat"]
        if let db = await downloadDatRemote(systemID: system.id, names: localNames, remotePaths: otherDatPaths, datsDir: datsDir, baseUrl: baseUrl) { LoggerService.libretroDB("Step 3: SUCCESS — downloaded DAT with \(db.count) entries"); return db }
        LoggerService.libretroDB("Step 3 complete: other DAT trees not found or failed")
        LoggerService.info(category: "LibretroDB", "Step 4/4: Loading RDB")
        LoggerService.libretroDB("=== STEP 4: Loading RDB (local then remote) ===")
        if let db = await downloadRdbRemote(systemID: system.id, names: rdbBasenamesToTry(for: system), rdbDir: rdbDir, baseUrl: baseUrl) { LoggerService.libretroDB("Step 4: SUCCESS — loaded RDB with \(db.count) entries"); return db }
        LoggerService.libretroDB("Step 4 complete: RDB not found or failed")
        LoggerService.warning(category: "LibretroDB", "ALL STEPS FAILED: No usable DAT or RDB found for systemID='\(system.id)' (tried: \(localNames.joined(separator: ", ")))")
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
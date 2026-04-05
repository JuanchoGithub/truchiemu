import Foundation
import os.log

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
    /// When set (e.g. merged GB+GBC DB), Libretro thumbnails use this system folder (`gb` vs `gbc`) instead of the ROM’s `systemID`.
    let thumbnailLookupSystemID: String?
}

enum ROMIdentifyResult: Equatable {
    /// Metadata was written to the ROM entry (CRC matched in DAT).
    case identified(GameInfo)
    /// Matched by sanitized filename vs DAT titles; region chosen using emulator language preference.
    case identifiedFromName(GameInfo)
    /// CRC was computed but no game in the No-Intro DAT uses that hash, and name search found nothing.
    case crcNotInDatabase(crc: String)
    /// DAT file missing, empty, or could not be downloaded.
    case databaseUnavailable
    /// ROM file could not be read (permissions, missing file, etc.).
    case romReadFailed(String)
    case noSystem
    /// Explicit request to clear/remove any existing identification — the ROM should revert to filename-based display.
    case identificationCleared
}

private let identifyLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "ROMIdentify")
private let databaseLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "LibretroDB")

// MARK: - LoggerService bridging helpers for ROMIdentify / LibretroDB
// These use the public LoggerService API (info/debug/warning/error) so they
// are always written to the log file regardless of the user's log level setting.
extension LoggerService {
    /// Always-log for ROM identification (bypasses log-level gating).
    static func romIdentify(_ message: String) {
        // Use info() which always logs (goes to file + print + OSLog)
        info(category: "ROMIdentify", message)
    }

    /// Always-log for libretro database operations (bypasses log-level gating).
    static func libretroDB(_ message: String) {
        info(category: "LibretroDB", message)
    }

    /// Warning-level for ROM identify (always written to file via warning())
    static func romIdentifyWarn(_ message: String) {
        warning(category: "ROMIdentify", message)
    }

    /// Error-level for ROM identify (always written to file via error())
    static func romIdentifyError(_ message: String) {
        error(category: "ROMIdentify", message)
    }

    /// Warning-level for libretro DB (always written to file)
    static func libretroDBWarn(_ message: String) {
        warning(category: "LibretroDB", message)
    }

    /// Error-level for libretro DB (always written to file)
    static func libretroDBError(_ message: String) {
        error(category: "LibretroDB", message)
    }
}

class ROMIdentifierService {
    static let shared = ROMIdentifierService()

    func identify(rom: ROM) async -> ROMIdentifyResult {
        guard let systemID = rom.systemID,
              let system = SystemDatabase.system(forID: systemID) else {
            identifyLog.warning("Identify: no system for ROM \(rom.path.lastPathComponent, privacy: .public)")
            return .noSystem
        }

        identifyLog.info("Identify: START system=\(systemID, privacy: .public) file=\(rom.path.lastPathComponent, privacy: .public)")

        let db = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
        if db.isEmpty {
            identifyLog.error("Identify: empty database for system \(systemID, privacy: .public)")
            return .databaseUnavailable
        }
        identifyLog.info("Identify: database loaded — \(db.count, privacy: .public) CRC entries for \(systemID, privacy: .public)")

        guard let crc = computeCRC(for: rom.path, systemID: systemID) else {
            identifyLog.error("Identify: CRC read failed for \(rom.path.path, privacy: .public)")
            return .romReadFailed("Could not read the ROM file. If the library is on a removable drive or you moved files, re-add the folder in Settings.")
        }

        let key = crc.uppercased()
        identifyLog.info("Identify: ROM CRC=\(key, privacy: .public)")

        if let info = db[key] {
            if let thumb = info.thumbnailLookupSystemID, thumb != systemID {
                identifyLog.info("Identify: CRC HIT → \(info.name, privacy: .public) (thumbnails: use system \(thumb, privacy: .public), ROM is \(systemID, privacy: .public))")
            } else {
                identifyLog.info("Identify: CRC HIT → \(info.name, privacy: .public)")
            }
            return .identified(info)
        }

        identifyLog.info("Identify: no CRC match for \(key, privacy: .public), falling back to name search...")
        let language = Self.currentEmulatorLanguage()
        if let byName = identifyByName(rom: rom, database: db, language: language) {
            identifyLog.info("Identify: NAME MATCH → \(byName.name, privacy: .public) (language=\(language.name, privacy: .public))")
            return .identifiedFromName(byName)
        }

        identifyLog.notice("Identify: NOT FOUND — CRC \(key, privacy: .public) not in database and name search found 0 matches for \(systemID, privacy: .public)")
        return .crcNotInDatabase(crc: key)
    }

    /// Legacy helper for code that only needs a successful match.
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

    // Common ROM tags that appear in parentheses — used for aggressive stripping during name matching.
    // These cover region, version, revision, and other common No-Intro/Romset tags.
    private static let commonRomTags: Set<String> = [
        // Regions
        "(world)", "(usa)", "(europe)", "(japan)", "(korea)", "(china)", "(brazil)", "(australia)",
        "(canada)", "(france)", "(germany)", "(spain)", "(italy)", "(netherlands)", "(sweden)",
        "(denmark)", "(norway)", "(finland)", "(russia)", "(portugal)", "(greece)", "(turkey)",
        "(hong kong)", "(taiwan)", "(singapore)", "(mexico)", "(argentina)", "(chile)", "(colombia)",
        "(eu)", "(jp)", "(us)", "(uk)", "(kr)", "(cn)", "(br)", "(au)", "(ca)", "(fr)", "(de)",
        "(es)", "(it)", "(nl)", "(se)", "(dk)", "(no)", "(fi)", "(ru)", "(pt)", "(gr)", "(tr)",
        "(hk)", "(tw)", "(sg)", "(mx)", "(ar)", "(cl)", "(co)",
        // Languages
        "(en)", "(ja)", "(fr)", "(de)", "(es)", "(it)", "(nl)", "(pt)", "(ru)", "(ko)", "(zh)",
        "(sv)", "(da)", "(no)", "(fi)", "(pl)", "(cs)", "(hu)", "(el)", "(tr)", "(ar)", "(he)",
        "(en,fr)", "(en,ja)", "(en,de)", "(en,es)", "(en,fr,de,es,it)", "(en,fr,de,es,it,pt,da,se)",
        "(en,fr,de,es,it,nl,sv,da,fi)", "(ja,en)", "(fr,en)", "(de,en)", "(es,en)", "(pt,en)",
        "(en,fr,de)", "(en,fr,de,es)", "(en,fr,de,es,it,pt)", "(pt,br)", "(ru,pl)", "(zh,en)",
        "(ko,en)", "(ja,en,fr,de,es,it)", "(multi)", "(multilanguage)", "(multi-lang)", "(multi-5)",
        "(multi-6)", "(multi-7)", "(multi-8)", "(lang-5)", "(lang-6)", "(lang-7)", "(lang-8)",
        // Version/Revision
        "(beta)", "(alpha)", "(demo)", "(proto)", "(prototype)", "(sample)", "(rev a)", "(rev b)",
        "(rev c)", "(rev d)", "(rev e)", "(rev f)", "(rev g)", "(rev h)", "(rev i)", "(rev j)",
        "(rev k)", "(rev l)", "(rev m)", "(rev n)", "(rev 1)", "(rev 2)", "(rev 3)", "(rev 4)",
        "(rev 5)", "(rev 6)", "(rev 7)", "(rev 8)", "(rev 9)", "(revision 1)", "(revision 2)",
        "(v1.0)", "(v1.1)", "(v1.2)", "(v1.3)", "(v1.4)", "(v2.0)", "(v2.1)", "(version 1)",
        "(version 2)", "(unl)", "(unlicensed)", "(alt)", "(alternative)", "(aftermarket)",
        "(homebrew)", "(hack)", "(translated)", "(translation)", "(patched)", "(fixed)",
        // Special
        "(enabling chip)", "(sufami)", "(satellaview)", "(bs)", "(event)", "(kiosk)", "(test)",
        "(debug)", "(debug version)", "(debug mode)", "(crc bad)", "(bad dump)", "(alt 1)",
        "(alt 2)", "(alt 3)", "(o)", "(!)", "[!]", "[b]", "[f]", "[h]", "[t]", "[x]",
        "(disc 1)", "(disc 2)", "(disc 3)", "(disc 4)", "(side a)", "(side b)", "(cart)",
        "(3m)", "(5m)", "(6m)", "(7.5m)", "(8m)", "(9m)", "(11m)", "(12m)", "(16m)",
        "(24m)", "(32m)", "(48m)", "(64m)", "(128m)",
    ]

    /// Aggressively normalize a title for name matching by stripping ALL parenthetical tags
    /// and common ROM release tags, then lowercasing and collapsing whitespace.
    /// This is more aggressive than normalizedComparableTitle and is used as a last resort
    /// when CRC matching fails.
    /// Visible for testing.
    static func aggressivelyNormalizedTitle(_ s: String) -> String {
        // First use the existing parenthesis stripping
        var result = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(s)
        
        // Additionally strip known tags that might appear in brackets
        while let r = result.range(of: "\\[([^\\]]*)\\]", options: .regularExpression) {
            result.removeSubrange(r)
        }
        
        // Also strip curly braces tags {like these}
        while let r = result.range(of: "\\{([^\\}]*)\\}", options: .regularExpression) {
            result.removeSubrange(r)
        }
        
        // Handle common parenthetical patterns that might remain (strip at word boundaries)
        // This catches things like " (World)" that might be at the start or middle
        result = result.replacingOccurrences(
            of: "\\s*\\([^)]*\\)\\s*",
            with: " ",
            options: .regularExpression
        )
        
        // Remove any remaining bracket content
        result = result.replacingOccurrences(
            of: "\\s*\\[[^\\]]*\\]\\s*",
            with: " ",
            options: .regularExpression
        )
        
        return result
            .lowercased()
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compare No-Intro titles after stripping region/version parentheticals.
    /// Visible for testing.
    static func normalizedComparableTitle(_ s: String) -> String {
        let stripped = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(s)
        return stripped
            .lowercased()
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Heuristic: No-Intro DATs use `description` as the game title and `name` as
    /// an internal ROM filename.  ScummVM/MAME DATs use `name` as the title and
    /// `description` as a long prose paragraph.  Pick whichever looks like a real title.
    /// Visible for testing.
    static func titleFromDatGame(name: String, description: String) -> String {
        guard !description.isEmpty else { return name }
        // Long descriptions are prose paragraphs → use `name` (ScummVM / MAME style)
        if description.count > 150 { return name }
        // Count sentence-ending punctuation (.!?)
        let sentenceEndCount = description.split(whereSeparator: { $0.isNewline }).filter { line in
            line.contains(".") || line.contains("!") || line.contains("?") || line.hasSuffix(".") || line.hasSuffix("!") || line.hasSuffix("?")
        }.count
        if sentenceEndCount >= 2 { return name }
        // Short description = likely the actual title (No-Intro style)
        return description
    }

    /// Lower index = stronger preference when multiple DAT entries share the same base title.
    private static func regionPreferenceRank(fullName: String, language: EmulatorLanguage) -> Int {
        let prefs = language.noIntroRegionPreference
        for (idx, tag) in prefs.enumerated() where fullName.contains(tag) {
            return idx
        }
        return prefs.count
    }

    /// When `regionPreferenceRank` ties (e.g. no tag matched), avoid lexicographic tiebreak where `(Japan)` sorts before `(World)`.
    private static func regionTieBreakOrdinal(fullName: String, language: EmulatorLanguage) -> Int {
        if language == .japanese {
            if fullName.contains("(Japan)") || fullName.contains("(JP)") || fullName.contains("(Ja)") { return 0 }
            return 50
        }
        if fullName.contains("(World)") { return 0 }
        if fullName.contains("(USA)") || fullName.contains("(Canada)") { return 2 }
        if fullName.contains("(Europe)") || fullName.contains("(EU)") { return 3 }
        if fullName.contains("(Japan)") || fullName.contains("(JP)") { return 30 }
        return 15
    }

    // MARK: – Number variant generation (Arabic, Roman, and text numbers)
    // Produces alternate forms of a normalised title where standalone Arabic
    // numerals 1-19 are replaced with their Roman equivalent AND text number
    // equivalent (e.g., "3" → "III" → "three"), and vice versa.
    // This ensures "Double Dragon 3" matches "Double Dragon III" or "Double Dragon Three".
    // Also strips a trailing number variant for first-game-in-series edge cases.
    /// Visible for testing.
    static func romanNumeralVariants(of normalized: String) -> [String] {
        guard normalized.count >= 2 else { return [] }
        var variants: Set<String> = []

        // Arabic ↔ Roman ↔ Text number mappings
        let arabicToRoman: [Int: String] = [
            1: "I",   2: "II",   3: "III",   4: "IV",
            5: "V",   6: "VI",   7: "VII",   8: "VIII",
            9: "IX",  10: "X",   11: "XI",   12: "XII",
            13: "XIII", 14: "XIV", 15: "XV",
            16: "XVI",  17: "XVII", 18: "XVIII", 19: "XIX",
        ]
        let arabicToText: [Int: String] = [
            1: "one",   2: "two",   3: "three",  4: "four",
            5: "five",  6: "six",   7: "seven",  8: "eight",
            9: "nine",  10: "ten",  11: "eleven", 12: "twelve",
            13: "thirteen", 14: "fourteen", 15: "fifteen",
            16: "sixteen", 17: "seventeen", 18: "eighteen", 19: "nineteen",
        ]

        // Build Roman → Arabic lookup
        let romanToArabic: [String: Int] = {
            var d: [String: Int] = [:]
            for (a, r) in arabicToRoman {
                d[r.lowercased()] = a
                d[r] = a
            }
            return d
        }()

        // Build text → Arabic lookup
        let textToArabic: [String: Int] = {
            var d: [String: Int] = [:]
            for (a, t) in arabicToText {
                d[t] = a
                // Also add capitalized versions
                let capitalized = t.prefix(1).uppercased() + t.dropFirst()
                d[capitalized] = a
            }
            return d
        }()

        // Arabic → Roman
        for (a, r) in arabicToRoman {
            let p = "(?<![a-zA-Z])\\b" + String(a) + "\\b(?![a-zA-Z0-9])"
            let s = normalized.replacingOccurrences(of: p, with: r, options: .regularExpression)
            if s != normalized { variants.insert(s) }
        }

        // Arabic → Text number
        for (a, t) in arabicToText {
            let p = "(?<![a-zA-Z])\\b" + String(a) + "\\b(?![a-zA-Z0-9])"
            let s = normalized.replacingOccurrences(of: p, with: t, options: .regularExpression)
            if s != normalized { variants.insert(s) }
        }

        // Roman → Arabic
        for (r, a) in romanToArabic {
            let esc = NSRegularExpression.escapedPattern(for: r)
            // For single-char romans (I, V, X), require that they're NOT followed by dash or apostrophe
            // to avoid matching "X-Men", but still match "X" in standalone context like "Final Fantasy X"
            let p: String
            if r.count == 1 {
                // Single-char: don't match if followed by dash or apostrophe (e.g. "X-Men", "I'll")
                p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![-'a-zA-Z0-9])"
            } else {
                p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"
            }
            let s = normalized.replacingOccurrences(of: p, with: String(a), options: .regularExpression)
            if s != normalized { variants.insert(s) }
        }

        // Roman → Text number (Roman → Arabic → Text)
        for (r, a) in romanToArabic {
            if let textForm = arabicToText[a] {
                let esc = NSRegularExpression.escapedPattern(for: r)
                let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"
                let s = normalized.replacingOccurrences(of: p, with: textForm, options: .regularExpression)
                if s != normalized { variants.insert(s) }
            }
        }

        // Text number → Arabic
        for (t, a) in textToArabic {
            let esc = NSRegularExpression.escapedPattern(for: t)
            let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"
            let s = normalized.replacingOccurrences(of: p, with: String(a), options: .regularExpression)
            if s != normalized { variants.insert(s) }
        }

        // Text number → Roman (Text → Arabic → Roman)
        for (t, a) in textToArabic {
            if let romanForm = arabicToRoman[a] {
                let esc = NSRegularExpression.escapedPattern(for: t)
                let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"
                let s = normalized.replacingOccurrences(of: p, with: romanForm, options: .regularExpression)
                if s != normalized { variants.insert(s) }
            }
        }

        // Strip trailing number variants for first-game-in-series edge cases
        // E.g., "Ecco the Dolphin 1" → "Ecco the Dolphin", " Ecco the Dolphin I" → "Ecco the Dolphin"
        // This handles cases where the user's file has the number but the DB entry doesn't.
        let t = normalized.trimmingCharacters(in: .whitespaces)
        // Case-insensitive patterns for 1, I, one
        for pat in [" 1$", " (?i:i)(?-i)$", " (?i:one)(?-i)$"] {
            let s = t.replacingOccurrences(of: pat, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if s != t && s.count >= 2 { variants.insert(s) }
        }

        return Array(variants)
    }

    private func identifyByName(rom: ROM, database: [String: GameInfo], language: EmulatorLanguage) -> GameInfo? {
        let stem = rom.path.deletingPathExtension().lastPathComponent
        var cleaned = LibretroThumbnailResolver.stripRomFilenameTags(stem)
        cleaned = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(cleaned)
        let queryBase = Self.normalizedComparableTitle(cleaned)
        guard queryBase.count >= 2 else {
            identifyLog.warning("Identify: name search skipped — queryBase='\(queryBase, privacy: .public)' too short (<2 chars)")
            return nil
        }

        identifyLog.info("Identify: name search START — file='\(stem, privacy: .public)', cleaned='\(cleaned, privacy: .public)', queryBase='\(queryBase, privacy: .public)'")
        identifyLog.info("Identify: database has \(database.count, privacy: .public) entries to search")

        // --- Pass 1: exact match on base query (normalizedComparableTitle strips parentheses) ---
        identifyLog.info("Identify: PASS 1 — exact match on queryBase='\(queryBase, privacy: .public)' (normalizedComparableTitle)")
        var exact: [GameInfo] = []
        var pass1Checked = 0
        for info in database.values {
            let datBase = Self.normalizedComparableTitle(info.name)
            pass1Checked += 1
            if datBase == queryBase {
                exact.append(info)
                identifyLog.debug("Identify: PASS 1 matched → '\(info.name, privacy: .public)'")
            }
        }
        if !exact.isEmpty {
            identifyLog.info("Identify: PASS 1 FOUND \(exact.count) exact match(es)")
        } else {
            identifyLog.info("Identify: PASS 1 found 0 matches (checked \(pass1Checked, privacy: .public) entries)")
        }

        // --- Pass 2: exact match on Roman-numeral / trailing-number variants ---
        if exact.isEmpty {
            let variants = Self.romanNumeralVariants(of: queryBase)
            identifyLog.info("Identify: PASS 2 — number variants (\(variants.count, privacy: .public) variants generated)")
            if !variants.isEmpty {
                for variant in variants {
                    identifyLog.debug("Identify: PASS 2 trying variant='\(variant, privacy: .public)'")
                    var hit = false
                    for info in database.values {
                        let datBase = Self.normalizedComparableTitle(info.name)
                        if datBase == variant {
                            exact.append(info)
                            identifyLog.info("Identify: PASS 2 matched variant='\(variant, privacy: .public)' → '\(info.name, privacy: .public)'")
                            hit = true
                        }
                    }
                    if hit { break }
                }
            } else {
                identifyLog.debug("Identify: PASS 2 skipped — no variants generated for queryBase='\(queryBase, privacy: .public)'")
            }
            if exact.isEmpty {
                identifyLog.info("Identify: PASS 2 found 0 matches")
            }
        }

        // --- Pass 3: aggressive normalization — strip ALL tags including [brackets], {braces}, parentheses ---
        // This is the user-requested feature: strip (World), (USA), (Beta), etc. from both ROM name and DB entries
        if exact.isEmpty {
            let aggressiveQuery = Self.aggressivelyNormalizedTitle(stem)
            identifyLog.info("Identify: PASS 3 — aggressive normalization")
            identifyLog.info("Identify: PASS 3 query='\(stem, privacy: .public)' → '\(aggressiveQuery, privacy: .public)'")
            if !aggressiveQuery.isEmpty && aggressiveQuery.count >= 2 {
                // Try exact aggressive match first
                var pass3Checked = 0
                for info in database.values {
                    let datAggressive = Self.aggressivelyNormalizedTitle(info.name)
                    pass3Checked += 1
                    if datAggressive == aggressiveQuery {
                        exact.append(info)
                        identifyLog.info("Identify: PASS 3 matched aggressive query → '\(info.name, privacy: .public)'")
                    }
                }
                // If no exact match, try with number variants (3 → III → three)
                if exact.isEmpty {
                    let aggressiveVariants = Self.romanNumeralVariants(of: aggressiveQuery)
                    identifyLog.debug("Identify: PASS 3 generated \(aggressiveVariants.count, privacy: .public) number variants for aggressive query='\(aggressiveQuery, privacy: .public)'")
                    for variant in aggressiveVariants {
                        identifyLog.debug("Identify: PASS 3 trying aggressive variant='\(variant, privacy: .public)'")
                        for info in database.values {
                            let datAggressive = Self.aggressivelyNormalizedTitle(info.name)
                            if datAggressive == variant {
                                exact.append(info)
                                identifyLog.info("Identify: PASS 3 matched aggressive variant='\(variant, privacy: .public)' → '\(info.name, privacy: .public)'")
                                break
                            }
                        }
                        if !exact.isEmpty { break }
                    }
                }
            } else {
                identifyLog.debug("Identify: PASS 3 skipped — aggressiveQuery too short or empty")
            }
            if exact.isEmpty {
                identifyLog.info("Identify: PASS 3 found 0 matches")
            }
        }

        // --- Pass 4: substring / prefix containment (original fuzzy) ---
        // IMPORTANT: Avoid partial matches where the query has a number suffix that the DB entry lacks.
        // E.g., "double dragon 3" should NOT match "double dragon" just because one contains the other.
        // Only allow partial matches when the difference is a minor article/preposition like "the".
        var candidates = exact
        if candidates.isEmpty {
            identifyLog.info("Identify: PASS 4 — substring/fuzzy matching (base query)")
            var pass4BaseChecked = 0
            var pass4BaseMatched = 0
            for info in database.values {
                let datBase = Self.normalizedComparableTitle(info.name)
                guard datBase.count >= 3, queryBase.count >= 3 else { continue }
                pass4BaseChecked += 1

                // Check if this would be a problematic partial match (query has trailing number)
                let wouldBeBadPartialMatch = Self.isProblematicNumberSuffixPartialMatch(query: queryBase, candidate: datBase)
                guard !wouldBeBadPartialMatch else { continue }

                // Reject substring match when candidate is much shorter than query
                // (e.g. "x-men" should NOT match "spiderman and x-men - arcade's revenge")
                // Allow if query is at most 2x the length of candidate, or if match ratio is high
                let lenRatio = Double(queryBase.count) / Double(datBase.count)
                if queryBase.contains(datBase) && lenRatio > 1.5 {
                    // Query contains candidate but candidate is much shorter → likely false positive
                    // e.g. "x-men" (7) vs "spiderman and x-men..." (40) → ratio 5.7x → reject
                    continue
                }

                if datBase.contains(queryBase) || queryBase.contains(datBase) {
                    candidates.append(info)
                    pass4BaseMatched += 1
                    identifyLog.debug("Identify: PASS 4 substring match → '\(info.name, privacy: .public)'")
                }
            }
            identifyLog.info("Identify: PASS 4 (base query) checked \(pass4BaseChecked, privacy: .public) entries, found \(pass4BaseMatched, privacy: .public) substring match(es)")

            // Final fallback: containment using Roman-numeral variants of the query
            if candidates.isEmpty {
                let variants = Self.romanNumeralVariants(of: queryBase)
                identifyLog.info("Identify: PASS 4 (Roman variants) — trying \(variants.count, privacy: .public) variants")
                for variant in variants {
                    guard variant.count >= 3 else { continue }
                    identifyLog.debug("Identify: PASS 4 trying Roman variant='\(variant, privacy: .public)'")
                    for info in database.values {
                        let datBase = Self.normalizedComparableTitle(info.name)
                        guard datBase.count >= 3 else { continue }

                        let wouldBeBadPartialMatch = Self.isProblematicNumberSuffixPartialMatch(query: variant, candidate: datBase)
                        guard !wouldBeBadPartialMatch else { continue }

                        if datBase.contains(variant) || variant.contains(datBase) {
                            candidates.append(info)
                            identifyLog.info("Identify: PASS 4 matched Roman variant='\(variant, privacy: .public)' → '\(info.name, privacy: .public)'")
                            break
                        }
                    }
                    if !candidates.isEmpty { break }
                }
                if candidates.isEmpty {
                    identifyLog.info("Identify: PASS 4 (Roman variants) found 0 matches")
                }
            }

            // Last resort: aggressive substring match (with same number-suffix protection)
            if candidates.isEmpty {
                let aggressiveQuery = Self.aggressivelyNormalizedTitle(stem)
                if !aggressiveQuery.isEmpty && aggressiveQuery.count >= 3 {
                    identifyLog.info("Identify: PASS 4 (last resort) — aggressive substring match")
                    var pass4AggChecked = 0
                    var pass4AggMatched = 0
                    for info in database.values {
                        let datAggressive = Self.aggressivelyNormalizedTitle(info.name)
                        guard datAggressive.count >= 3 else { continue }
                        pass4AggChecked += 1

                        let wouldBeBadPartialMatch = Self.isProblematicNumberSuffixPartialMatch(query: aggressiveQuery, candidate: datAggressive)
                        guard !wouldBeBadPartialMatch else { continue }

                        if datAggressive.contains(aggressiveQuery) || aggressiveQuery.contains(datAggressive) {
                            candidates.append(info)
                            pass4AggMatched += 1
                            identifyLog.debug("Identify: PASS 4 aggressive substring match → '\(info.name, privacy: .public)'")
                        }
                    }
                    if pass4AggMatched > 0 {
                        identifyLog.info("Identify: PASS 4 (last resort) found \(pass4AggMatched) aggressive substring match(es)")
                    } else {
                        identifyLog.info("Identify: PASS 4 (last resort) found 0 matches (checked \(pass4AggChecked, privacy: .public) entries)")
                    }
                } else {
                    identifyLog.debug("Identify: PASS 4 (last resort) skipped — aggressiveQuery too short or empty")
                }
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
            if rank >= prefs.count {
                identifyLog.notice("Identify: name match without preferred region tag; used worldwide/Japan tie-break then length/lex order")
            }
        }
        return sorted.first
    }
    
    func computeCRC(for url: URL, systemID: String) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let fullData = try Data(contentsOf: url, options: .mappedIfSafe)
            let dataToHash: Data

            switch systemID {
            case "nes":
                // No-Intro hashes NES WITHOUT the 16-byte iNES header when present
                if fullData.count >= 16 && fullData.prefix(4) == Data([0x4E, 0x45, 0x53, 0x1A]) {
                    dataToHash = fullData.dropFirst(16)
                } else {
                    dataToHash = fullData
                }
            case "genesis", "sms", "gamegear", "32x", "sg1000":
                // SMD files often have a 512-byte header that must be stripped for CRC to match
                // No-Intro uses clean dumps without this header
                dataToHash = stripGenesisHeaderIfNeeded(from: fullData)
            default:
                // Full file (No-Intro uses clean dumps for SNES, etc.)
                dataToHash = fullData
            }

            return CRC32.compute(dataToHash)
        } catch {
            identifyLog.error("CRC read error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Strips the 512-byte header from SMD Genesis ROMs when present.
    /// SMD files from early copiers (like Pro Action Replay/Game Doctor) often include
    /// a 512-byte header that prevents CRC matching with No-Intro database.
    /// Heuristic: If file size > 512 bytes and (size - 512) is a valid ROM size, strip the header.
    private func stripGenesisHeaderIfNeeded(from data: Data) -> Data {
        let fileSize = data.count

        // If file is too small to have a header
        guard fileSize > 512 else { return data }

        // Check if file already has a valid ROM size (power of 2, or common ROM sizes)
        // Valid Genesis ROM sizes are typically powers of 2: 128KB, 256KB, 512KB, 1MB, 2MB, 4MB
        let validSizes = [
            131072,    // 128 KB
            262144,    // 256 KB
            393216,    // 384 KB (some games)
            524288,    // 512 KB
            655360,    // 640 KB
            786432,    // 768 KB
            1048576,   // 1 MB
            1310720,   // 1.25 MB
            1572864,   // 1.5 MB
            2097152,   // 2 MB
            2621440,   // 2.5 MB
            3145728,   // 3 MB
            4194304,   // 4 MB
        ]

        // If current size is already valid, don't strip
        if validSizes.contains(fileSize) || isPowerOfTwo(fileSize) {
            return data
        }

        // Try stripping 512 bytes
        let strippedSize = fileSize - 512

        // Check if stripped size is valid
        if validSizes.contains(strippedSize) || isPowerOfTwo(strippedSize) {
            identifyLog.info("Stripped 512-byte SMD header from ROM (original: \(fileSize) bytes → stripped: \(strippedSize) bytes)")
            return data.dropFirst(512)
        }

        // Also check for interleaved ROMs (common in Genesis):
        // Some SMD files are interleaved with 512-byte header at specific patterns
        // If stripping 512 doesn't yield valid size, return original
        return data
    }

    /// Check if a number is a power of 2
    private func isPowerOfTwo(_ n: Int) -> Bool {
        guard n > 0 else { return false }
        return (n & (n - 1)) == 0
    }

    // MARK: - Partial match protection

    /// Numbers as text forms (1-19)
    private static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]

    /// Roman numeral patterns (1-19)
    private static let romanNumeralPatterns: Set<String> = [
        "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x",
        "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix",
    ]

    /// Regex pattern that matches a trailing number suffix (Arabic, Roman, or text)
    private static let trailingNumberSuffixPattern = try! NSRegularExpression(
        pattern: "\\s+(\\d+|[ivxIVX]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)$",
        options: .caseInsensitive
    )

    /// Detects problematic partial matches where the query has a number suffix but the candidate doesn't.
    /// E.g., query="double dragon 3" should NOT match candidate="double dragon" (different game!)
    /// But query="the double dragon" CAN match candidate="double dragon" (article difference is OK).
    ///
    /// Returns `true` if this would be a bad match that should be skipped.
    static func isProblematicNumberSuffixPartialMatch(query: String, candidate: String) -> Bool {
        // Only relevant when query contains candidate or vice versa (partial match scenario)
        guard query != candidate else { return false }

        let queryLower = query.lowercased()
        let candidateLower = candidate.lowercased()

        // Determine which is longer (the one with the extra suffix)
        let longer: String
        let shorter: String
        if queryLower.count > candidateLower.count {
            longer = queryLower
            shorter = candidateLower
        } else {
            longer = candidateLower
            shorter = queryLower
        }

        // Only proceed if the longer contains the shorter as a substring
        guard longer.contains(shorter) else { return false }

        // Check if the longer has a trailing number suffix that the shorter lacks
        let hasTrailingNumberSuffix = trailingNumberSuffixPattern.firstMatch(
            in: longer,
            range: NSRange(longer.startIndex..., in: longer)
        ) != nil

        if hasTrailingNumberSuffix {
            // The difference is a number — this is a problematic match
            // E.g., "double dragon 3" vs "double dragon" → BAD
            return true
        }

        // Check if the difference is just a minor article/preposition (acceptable)
        // Extract what the longer has extra beyond the shorter
        let extraPart = longer.replacingOccurrences(of: shorter, with: "")
            .trimmingCharacters(in: .whitespaces)

        // Allow if the extra is only minor articles/prepositions
        let acceptedArticles: Set<String> = [
            "the", "a", "an", "of", "and", "le", "la", "les", "el", "de", "del",
            "los", "las", "il", "un", "une",
        ]

        // Split extra into words and check if they're all articles
        let extraWords = extraPart.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        if extraWords.allSatisfy({ acceptedArticles.contains($0) }) {
            return false  // Only articles differ → OK to match
        }

        // There's a substantive difference that's not a number suffix → use normal matching
        return false
    }
}

struct LibretroDatGame {
    var name: String = ""
    var description: String = ""
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var crcs: [String] = []  // A game can have multiple roms/crcs
}

/// Downloads and parses libretro-database sources: No-Intro `.dat` first, then other `.dat` trees, then compiled `rdb/` (RARCHDB + MessagePack).
actor LibretroDatabaseLibrary {
    static let shared = LibretroDatabaseLibrary()

    /// Game Boy and Game Boy Color sets overlap; we always merge both for CRC/name lookup.
    private static let gbFamilyCacheKey = "gb+gbc"

    private static func isGbFamily(_ systemID: String) -> Bool {
        systemID == "gb" || systemID == "gbc"
    }

    private static func tagGameInfo(_ info: GameInfo, thumbnailLookupSystemID: String) -> GameInfo {
        GameInfo(
            name: info.name,
            year: info.year,
            publisher: info.publisher,
            developer: info.developer,
            genre: info.genre,
            crc: info.crc,
            thumbnailLookupSystemID: thumbnailLookupSystemID
        )
    }

    /// Exact `.dat` basenames as in [libretro-database](https://github.com/libretro/libretro-database) (`metadat/no-intro`, `metadat/redump`, etc.).
    /// Use when `"\(manufacturer) - \(name).dat"` does not match upstream (short display names vs official No-Intro set names).
    /// Mappings verified against actual GitHub repository filenames — see docs/LIBRETRO_DATABASE_NAMING_DICTIONARY.md.
    private static let libretroDatBasenameOverrides: [String: String] = [
        // Nintendo (No-Intro)
        "nes": "Nintendo - Nintendo Entertainment System.dat",
        "snes": "Nintendo - Super Nintendo Entertainment System.dat",
        "n64": "Nintendo - Nintendo 64.dat",
        "nds": "Nintendo - Nintendo DS.dat",
        "ndsi": "Nintendo - Nintendo DSi.dat",
        "gb": "Nintendo - Game Boy.dat",
        "gbc": "Nintendo - Game Boy Color.dat",
        "gba": "Nintendo - Game Boy Advance.dat",
        "vb": "Nintendo - Virtual Boy.dat",
        "fds": "Nintendo - Family Computer Disk System.dat",
        "sufami": "Nintendo - Sufami Turbo.dat",
        "satellaview": "Nintendo - Satellaview.dat",
        "n64dd": "Nintendo - Nintendo 64DD.dat",
        "pokemon_mini": "Nintendo - Pokemon Mini.dat",
        "ereader": "Nintendo - e-Reader.dat",
        // Sega (No-Intro)
        "genesis": "Sega - Mega Drive - Genesis.dat",
        "sms": "Sega - Master System - Mark III.dat",
        "gamegear": "Sega - Game Gear.dat",
        "32x": "Sega - 32X.dat",
        "saturn": "Sega - Saturn.dat",
        "dreamcast": "Sega - Dreamcast.dat",
        "sg1000": "Sega - SG-1000.dat",
        "pico": "Sega - PICO.dat",
        "beenab": "Sega - Beena.dat",
        // Sony (Redump — files use Sony - not Sega convention)
        "psx": "Sony - PlayStation.dat",
        "ps2": "Sony - PlayStation 2.dat",
        "psp": "Sony - PlayStation Portable.dat",
        "ps3": "Sony - PlayStation 3.dat",
        "psvita": "Sony - PlayStation Vita.dat",
        // Atari (No-Intro)
        "atari2600": "Atari - 2600.dat",
        "atari5200": "Atari - 5200.dat",
        "atari7800": "Atari - 7800.dat",
        "lynx": "Atari - Lynx.dat",
        "jaguar": "Atari - Jaguar.dat",
        "atari8": "Atari - 8-bit Family.dat",
        "atarist": "Atari - ST.dat",
        // Arcade
        "mame": "MAME.dat",
        // SNK / Neo Geo (No-Intro)
        "ngp": "SNK - Neo Geo Pocket.dat",
        "ngc": "SNK - Neo Geo Pocket Color.dat",
        // NEC (No-Intro)
        "pce": "NEC - PC Engine - TurboGrafx 16.dat",
        "supergrafx": "NEC - PC Engine SuperGrafx.dat",
        "pc98": "NEC - PC-98.dat",
        "pc88": "NEC - PC-8001 - PC-8801.dat",
        "x1": "Sharp - X1.dat",
        // Bandai / WonderSwan
        "wonderswan": "Bandai - WonderSwan.dat",
        "wswanc": "Bandai - WonderSwan Color.dat",
        // Microsoft / Commodore / Sinclair
        "c64": "Commodore - 64.dat",
        "amiga": "Commodore - Amiga.dat",
        "msx": "Microsoft - MSX.dat",
        "msx2": "Microsoft - MSX2.dat",
        "zx_spectrum": "Sinclair - ZX Spectrum +3.dat",
        "x68000": "Sharp - X68000.dat",
        // Nintendo (wii — Redump, 3ds — No-Intro)
        "wii": "Nintendo - Wii.dat",
        "3ds": "Nintendo - Nintendo 3DS.dat",
        // Disc-based Redump systems (only in metadat/redump/)
        "segacd": "Sega - Mega-CD - Sega CD.dat",
        "pcecd": "NEC - PC Engine CD - TurboGrafx-CD.dat",
        "pcfx": "NEC - PC-FX.dat",
        "jaguar_cd": "Atari - Jaguar CD.dat",
        "cd32": "Commodore - CD32.dat",
        "cdtv": "Commodore - CDTV.dat",
    ]

    /// Systems whose DAT files only exist in Redump (not No-Intro). These are disc-based systems.
    private static let redumpOnlySystems: Set<String> = [
        "psx", "ps2", "psp", "psvita", "ps3",
        "segacd", "pcecd",
        "pcfx", "pc98",
        "jaguar_cd",
        "cd32", "cdtv",
        "wii",
        "gcn",
    ]

    /// [libretro-database `rdb/`](https://github.com/libretro/libretro-database/tree/master/rdb): `MAME.rdb` plus per-core `MAME *.rdb` files.
    private static let mameRdbBasenames: [String] = [
        "MAME.rdb",
        "MAME 2016.rdb",
        "MAME 2015.rdb",
        "MAME 2010.rdb",
        "MAME 2003-Plus.rdb",
        "MAME 2003.rdb",
        "MAME 2000.rdb",
    ]

    // Cache for loaded databases: [systemID: [CRC: GameInfo]]
    private var databases: [String: [String: GameInfo]] = [:]

    /// Ordered unique basenames to try locally and on GitHub raw URLs.
    private func datBasenamesToTry(for system: SystemInfo) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func append(_ name: String) {
            guard !seen.contains(name) else { return }
            seen.insert(name)
            ordered.append(name)
        }

        if let exact = Self.libretroDatBasenameOverrides[system.id] {
            append(exact)
        }

        var primary = "\(system.name).dat"
        if !system.manufacturer.isEmpty && system.manufacturer != "Various" {
            // If the system name already starts with the manufacturer (case-insensitive),
            // avoid creating duplicates like "Sega - Sega 32X.dat".
            let nameLower = system.name.lowercased()
            let mfrLower = system.manufacturer.lowercased()
            if nameLower.hasPrefix(mfrLower) {
                // name already contains manufacturer; check if what follows makes sense
                // e.g. "Sega 32X" starts with "sega", remainder " 32X" → basename "Sega - 32X.dat"
                let remainder = system.name.dropFirst(mfrLower.count).trimmingCharacters(in: .whitespaces)
                if remainder.isEmpty {
                    // name == manufacturer exactly, just use plain name
                    primary = "\(system.name).dat"
                } else {
                    // Use manufacturer + remainder, e.g. "Sega - 32X"
                    primary = "\(system.manufacturer) - \(remainder).dat"
                }
            } else {
                primary = "\(system.manufacturer) - \(system.name).dat"
            }
        }
        append(primary)
        append("\(system.name).dat")

        let spacedVendor = "\(system.manufacturer.isEmpty ? "" : "\(system.manufacturer) ")\(system.name).dat"
        append(spacedVendor)

        return ordered
    }

    /// Same basenames as DAT but with `.rdb` (see `rdb/` on GitHub). Arcade/MAME uses `MAME.rdb` and `MAME *.rdb`, not `Various - Arcade (MAME).rdb`.
    private func rdbBasenamesToTry(for system: SystemInfo) -> [String] {
        if system.id == "mame" {
            return Self.mameRdbBasenames
        }
        return datBasenamesToTry(for: system).map { ($0 as NSString).deletingPathExtension + ".rdb" }
    }
    
    /// Parses a ClrMamePro formatted DAT file into a dictionary grouped by CRC.
    func parseDat(contentsOf url: URL) -> [String: GameInfo] {
        LoggerService.libretroDB("Parsing DAT file: \(url.path)")
        guard let lines = try? String(contentsOf: url).components(separatedBy: .newlines) else {
            LoggerService.libretroDBWarn("Failed to read DAT file: \(url.path)")
            return [:]
        }
        
        LoggerService.libretroDB("DAT file has \(lines.count) lines")
        
        var database: [String: GameInfo] = [:]
        var currentGame: LibretroDatGame?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("game (") || trimmed.hasPrefix("machine (") {
                currentGame = LibretroDatGame()
            } else if trimmed == ")" && currentGame != nil {
                let nameToUse = ROMIdentifierService.titleFromDatGame(name: currentGame!.name, description: currentGame!.description)
                for crc in currentGame!.crcs {
                    database[crc.uppercased()] = GameInfo(
                        name: nameToUse,
                        year: currentGame?.year,
                        publisher: currentGame?.publisher ?? currentGame?.developer,
                        developer: currentGame?.developer,
                        genre: currentGame?.genre,
                        crc: crc.uppercased(),
                        thumbnailLookupSystemID: nil
                    )
                }
                currentGame = nil
            } else if currentGame != nil {
                // inside game block
                if trimmed.hasPrefix("name ") {
                    currentGame?.name = extractQuotes(trimmed) ?? ""
                } else if trimmed.hasPrefix("description ") {
                    currentGame?.description = extractQuotes(trimmed) ?? ""
                } else if trimmed.hasPrefix("comment ") && (currentGame?.description.isEmpty ?? true) {
                    currentGame?.description = extractQuotes(trimmed) ?? ""
                } else if trimmed.hasPrefix("year ") {
                    currentGame?.year = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("developer ") {
                    currentGame?.developer = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("publisher ") {
                    currentGame?.publisher = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("genre ") || trimmed.hasPrefix("category ") {
                    currentGame?.genre = extractQuotes(trimmed)
                } else if trimmed.hasPrefix("rom (") || trimmed.hasPrefix("disk (") {
                    if let crcRange = trimmed.range(of: "crc ") {
                        let substring = trimmed[crcRange.upperBound...]
                        if let firstWord = substring.components(separatedBy: .whitespaces).first {
                            let finalCrc = firstWord.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
                            currentGame?.crcs.append(finalCrc.uppercased())
                        }
                    }
                }
            }
        }
        
        LoggerService.libretroDB("Parsed DAT \(url.lastPathComponent) → \(database.count) CRC entries")
        databaseLog.info("Parsed DAT \(url.lastPathComponent, privacy: .public) → \(database.count) CRC entries")
        return database
    }
    
    private func extractQuotes(_ string: String) -> String? {
        if let start = string.firstIndex(of: "\""),
           let end = string[string.index(after: start)...].firstIndex(of: "\"") {
            return String(string[string.index(after: start)..<end])
        }
        return nil
    }
    
    /// Find all DAT entries that share the same base title as the given game name.
    /// Strips region/variant tags (parentheticals) and matches on exact base title only.
    /// Sequels (e.g. "Columns II") and different games (e.g. "Super Columns") are NOT matched.
    func findVariantEntries(for gameName: String, systemID: String) async -> [String] {
        guard let system = SystemDatabase.system(forID: systemID) else { return [] }
        // Ensure db is loaded for this system
        let fullDb = await fetchAndLoadDat(for: system)

        // Compute the base title by stripping parentheticals
        let baseTitle = ROMIdentifierService.normalizedComparableTitle(gameName)
        guard baseTitle.count >= 2 else { return [] }

        var variants: [String] = []
        for (_, info) in fullDb {
            let entryBase = ROMIdentifierService.normalizedComparableTitle(info.name)
            // Exact match on base title only — "columns" != "columns ii", "super columns", etc.
            if entryBase == baseTitle {
                variants.append(info.name)
            }
        }
        return variants
    }

    /// Fetch and load DAT by systemID only (convenience when SystemInfo is not available).
    private func fetchAndLoadDat(forSystemID systemID: String) async -> [String: GameInfo] {
        if let db = databases[systemID] {
            return db
        }
        if systemID == "gb" || systemID == "gbc" {
            if let merged = databases[LibretroDatabaseLibrary.gbFamilyCacheKey] {
                return merged
            }
        }
        return [:]
    }

    /// Ensures we have the database locally, optionally downloading it from GitHub. Order: **No-Intro `.dat`** → **other `.dat` trees** → **`rdb/` RDB** (compiled libretrodb).
    /// For **Game Boy** and **Game Boy Color**, loads and merges **both** sets (mixed libraries).
    func fetchAndLoadDat(for system: SystemInfo) async -> [String: GameInfo] {
        LoggerService.info(category: "LibretroDB", "fetchAndLoadDat() called for systemID=\(system.id)")
        LoggerService.libretroDB("fetchAndLoadDat called for systemID=\(system.id) (displayName=\(system.name))")

        if Self.isGbFamily(system.id) {
            LoggerService.libretroDB("GB family detected (systemID=\(system.id)), checking merged cache")
            if let merged = databases[Self.gbFamilyCacheKey] {
                databaseLog.info("LibretroDB: cache hit merged Game Boy + Game Boy Color (\(merged.count) CRC entries)")
                LoggerService.info(category: "LibretroDB", "CACHE HIT: merged GB+GBC (\(merged.count) CRC entries)")
                LoggerService.libretroDB("Cache hit: merged GB+GBC (\(merged.count) CRC entries)")
                return merged
            }
            LoggerService.libretroDB("GB+GBC cache MISS, loading both databases and merging")
            let partnerID = system.id == "gb" ? "gbc" : "gb"
            guard let partner = SystemDatabase.system(forID: partnerID) else {
                LoggerService.libretroDBError("GB family merge failed — missing partner system \(partnerID)")
                databaseLog.error("LibretroDB: GB family merge failed — missing partner system \(partnerID, privacy: .public)")
                return await loadSingleSystemDatabase(for: system)
            }

            LoggerService.debug(category: "LibretroDB", "Loading primary system \(system.id), then partner \(partnerID)")
            databaseLog.info("LibretroDB: Game Boy family — loading \(system.id, privacy: .public) then \(partnerID, privacy: .public), then merging")
            LoggerService.libretroDB("Loading primary \(system.id) then partner \(partnerID), then merging")

            let primary = await loadSingleSystemDatabase(for: system)
            LoggerService.libretroDB("Primary \(system.id) → \(primary.count) CRC entries")
            databaseLog.info("LibretroDB: primary \(system.id, privacy: .public) → \(primary.count) CRC entries")

            let secondary = await loadSingleSystemDatabase(for: partner)
            LoggerService.libretroDB("Partner \(partnerID) → \(secondary.count) CRC entries")
            databaseLog.info("LibretroDB: partner \(partnerID, privacy: .public) → \(secondary.count) CRC entries")

            var merged: [String: GameInfo] = [:]
            for (crc, info) in primary {
                merged[crc] = Self.tagGameInfo(info, thumbnailLookupSystemID: system.id)
            }
            var overlap = 0
            for (crc, info) in secondary {
                if merged[crc] != nil {
                    overlap += 1
                } else {
                    merged[crc] = Self.tagGameInfo(info, thumbnailLookupSystemID: partner.id)
                }
            }
            LoggerService.libretroDB("Merged GB+GBC → \(merged.count) unique CRCs (overlap=\(overlap)))")
            databaseLog.info("LibretroDB: merged GB+GBC → \(merged.count) unique CRCs (\(overlap) CRCs present in both sets; primary \(system.id, privacy: .public) wins on overlap); entries tagged for thumbnail CDN folder")
            LoggerService.info(category: "LibretroDB", "Merged GB+GBC → \(merged.count) unique CRCs (\(overlap) overlapping)")

            databases[Self.gbFamilyCacheKey] = merged
            databases["gb"] = merged
            databases["gbc"] = merged
            return merged
        }

        // Non-GB-family systems
        if let db = databases[system.id] {
            LoggerService.info(category: "LibretroDB", "CACHE HIT: \(system.id) (\(db.count) CRC entries)")
            LoggerService.libretroDB("Cache hit: \(system.id) (\(db.count) CRC entries)")
            databaseLog.info("LibretroDB: cache hit \(system.id, privacy: .public) (\(db.count) CRC entries)")
            return db
        }

        LoggerService.info(category: "LibretroDB", "Cache MISS for \(system.id), loading...")
        LoggerService.libretroDB("Cache miss for \(system.id), calling loadSingleSystemDatabase")
        let loaded = await loadSingleSystemDatabase(for: system)
        databases[system.id] = loaded
        return loaded
    }

    /// One libretro system: local DAT → No-Intro DAT → other DAT trees → RDB (no GB/GBC merge).
    private func loadSingleSystemDatabase(for system: SystemInfo) async -> [String: GameInfo] {
        LoggerService.info(category: "LibretroDB", "loadSingleSystemDatabase: loading database for systemID='\(system.id)' (\(system.name))")
        LoggerService.libretroDB("loadSingleSystemDatabase called for systemID=\(system.id) name=\(system.name)")

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let datsDir = appSupport.appendingPathComponent("TruchieEmu/Dats", isDirectory: true)
        let rdbDir = appSupport.appendingPathComponent("TruchieEmu/Rdb", isDirectory: true)
        try? FileManager.default.createDirectory(at: datsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rdbDir, withIntermediateDirectories: true)

        LoggerService.libretroDB("DATs directory: \(datsDir.path)")
        LoggerService.libretroDB("RDBs directory: \(rdbDir.path)")

        let localNames = datBasenamesToTry(for: system)
        let baseUrl = "https://raw.githubusercontent.com/libretro/libretro-database/master/"

        LoggerService.info(category: "LibretroDB", "Step 1/4: Scanning local DATs in \(datsDir.path)")
        LoggerService.libretroDB("=== STEP 1: Scanning local DATs ===")
        LoggerService.libretroDB("Trying DAT filenames: \(localNames.joined(separator: ", "))")
        databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] Step 1 — scan local DATs in \(datsDir.path, privacy: .public)")

        for fileName in localNames {
            let localUrl = datsDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: localUrl.path) {
                LoggerService.libretroDB("Found local DAT file: \(localUrl.path)")
                let db = parseDat(contentsOf: localUrl)
                if db.isEmpty {
                    LoggerService.libretroDBWarn("Local DAT \(fileName) exists but parsed 0 entries — continuing")
                    databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] local DAT \(fileName, privacy: .public) exists but parsed 0 entries — continuing")
                } else {
                    LoggerService.info(category: "LibretroDB", "Step 1: FOUND local DAT \(fileName) with \(db.count) entries")
                    LoggerService.libretroDB("Local DAT \(fileName) OK — \(db.count) CRC entries")
                    databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] using local DAT \(fileName, privacy: .public) (\(db.count) entries)")
                    return db
                }
            } else {
                LoggerService.debug(category: "LibretroDB", "Local DAT not found: \(localUrl.path)")
                LoggerService.libretroDB("Local DAT not found: \(localUrl.path)")
                databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] no local file \(fileName, privacy: .public)")
            }
        }
        LoggerService.libretroDB("Step 1 complete: no usable local DAT found")

        LoggerService.info(category: "LibretroDB", "Step 2/4: Downloading No-Intro DAT")
        LoggerService.libretroDB("=== STEP 2: Downloading No-Intro DAT (metadat/no-intro) ===")
        databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] Step 2 — download No-Intro DAT (metadat/no-intro)")
        let noIntroOnly = ["metadat/no-intro"]
        if let db = await downloadDatRemote(systemID: system.id, names: localNames, remotePaths: noIntroOnly, datsDir: datsDir, baseUrl: baseUrl) {
            LoggerService.info(category: "LibretroDB", "Step 2: SUCCESS — downloaded No-Intro DAT with \(db.count) entries")
            LoggerService.libretroDB("No-Intro DAT download OK — \(db.count) CRC entries")
            return db
        }
        LoggerService.libretroDB("Step 2 complete: No-Intro DAT not found or failed")

        LoggerService.info(category: "LibretroDB", "Step 3/4: Downloading other DAT trees")
        LoggerService.libretroDB("=== STEP 3: Downloading other DAT trees ===")
        databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] Step 3 — download other DAT trees (redump, mame, …)")
        let otherDatPaths = ["metadat/redump", "metadat/mame", "metadat/fba", "metadat/fbneo-split", "dat"]
        if let db = await downloadDatRemote(systemID: system.id, names: localNames, remotePaths: otherDatPaths, datsDir: datsDir, baseUrl: baseUrl) {
            LoggerService.info(category: "LibretroDB", "Step 3: SUCCESS — downloaded DAT with \(db.count) entries")
            LoggerService.libretroDB("Other DAT download OK — \(db.count) CRC entries")
            return db
        }
        LoggerService.libretroDB("Step 3 complete: other DAT trees not found or failed")

        LoggerService.info(category: "LibretroDB", "Step 4/4: Loading RDB")
        LoggerService.libretroDB("=== STEP 4: Loading RDB (local then remote) ===")
        databaseLog.info("LibretroDB: [\(system.id, privacy: .public)] Step 4 — load RDB (local cache then rdb/ on GitHub)")
        if let db = await downloadRdbRemote(systemID: system.id, names: rdbBasenamesToTry(for: system), rdbDir: rdbDir, baseUrl: baseUrl) {
            LoggerService.info(category: "LibretroDB", "Step 4: SUCCESS — loaded RDB with \(db.count) entries")
            LoggerService.libretroDB("RDB load OK — \(db.count) CRC entries")
            return db
        }
        LoggerService.libretroDB("Step 4 complete: RDB not found or failed")

        LoggerService.warning(category: "LibretroDB", "ALL STEPS FAILED: No usable DAT or RDB found for systemID='\(system.id)' (tried: \(localNames.joined(separator: ", ")))")
        LoggerService.libretroDBError("=== FAILED === No usable DAT or RDB for systemID=\(system.id) (tried: \(localNames.joined(separator: ", ")))")
        databaseLog.error("LibretroDB: [\(system.id, privacy: .public)] Step 5 — FAILED — no usable DAT or RDB (tried DAT names: \(localNames.joined(separator: ", "), privacy: .public))")
        return [:]
    }

    private func downloadDatRemote(systemID: String, names: [String], remotePaths: [String], datsDir: URL, baseUrl: String) async -> [String: GameInfo]? {
        for fileName in names {
            guard let encodedFile = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] skip DAT (bad encoding): \(fileName, privacy: .public)")
                continue
            }
            for path in remotePaths {
                let checkUrlStr = baseUrl + path + "/" + encodedFile
                guard let checkUrl = URL(string: checkUrlStr) else {
                    databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] bad URL for \(fileName, privacy: .public)")
                    continue
                }
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] GET DAT \(checkUrlStr, privacy: .public)")
                guard let data = try? await URLSession.shared.data(from: checkUrl).0 else {
                    databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] GET failed (no data) \(checkUrlStr, privacy: .public)")
                    continue
                }
                guard data.count > 100 else {
                    databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] response too small (\(data.count) bytes) \(checkUrlStr, privacy: .public)")
                    continue
                }
                guard let stringContent = String(data: data, encoding: .utf8),
                      stringContent.contains("game (") || stringContent.contains("machine (") else {
                    databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] not a ClrMamePro DAT (no game/machine blocks) \(checkUrlStr, privacy: .public)")
                    continue
                }
                let localUrl = datsDir.appendingPathComponent(fileName)
                try? data.write(to: localUrl)
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] saved DAT \(localUrl.lastPathComponent, privacy: .public) (\(data.count) bytes)")
                let db = parseDat(contentsOf: localUrl)
                if !db.isEmpty {
                    databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] DAT OK → \(db.count) CRC entries from \(fileName, privacy: .public)")
                    return db
                }
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] parsed 0 entries from \(fileName, privacy: .public)")
            }
        }
        return nil
    }

    private func downloadRdbRemote(systemID: String, names: [String], rdbDir: URL, baseUrl: String) async -> [String: GameInfo]? {
        for fileName in names {
            let localUrl = rdbDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: localUrl.path),
               let data = try? Data(contentsOf: localUrl),
               data.count > 32 {
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] read local RDB \(fileName, privacy: .public) (\(data.count) bytes)")
                let db = LibretroRDBParser.buildCRCIndex(data: data)
                if !db.isEmpty {
                    databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] RDB OK (local) → \(db.count) CRC entries")
                    return db
                }
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] local RDB \(fileName, privacy: .public) parsed 0 entries")
            }
        }
        for fileName in names {
            guard let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            let checkUrlStr = baseUrl + "rdb/" + encoded
            guard let checkUrl = URL(string: checkUrlStr) else { continue }
            databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] GET RDB \(checkUrlStr, privacy: .public)")
            guard let data = try? await URLSession.shared.data(from: checkUrl).0 else {
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] GET failed (no data) \(checkUrlStr, privacy: .public)")
                continue
            }
            guard data.count > 100 else {
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] RDB response too small (\(data.count) bytes) \(checkUrlStr, privacy: .public)")
                continue
            }
            guard data.starts(with: Data("RARCHDB\0".utf8)) else {
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] not RARCHDB magic \(checkUrlStr, privacy: .public)")
                continue
            }
            let localUrl = rdbDir.appendingPathComponent(fileName)
            try? data.write(to: localUrl)
            databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] saved RDB \(localUrl.lastPathComponent, privacy: .public) (\(data.count) bytes)")
            let db = LibretroRDBParser.buildCRCIndex(data: data)
            if !db.isEmpty {
                databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] RDB OK (remote) → \(db.count) CRC entries")
                return db
            }
            databaseLog.info("LibretroDB: [\(systemID, privacy: .public)] RDB parsed 0 entries \(fileName, privacy: .public)")
        }
        return nil
    }
}

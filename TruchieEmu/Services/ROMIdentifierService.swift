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
            LoggerService.romIdentifyWarn("No system for ROM: \(rom.path.lastPathComponent) — path=\(rom.path.path)")
            return .noSystem
        }

        LoggerService.info(category: "ROMIdentify", "Identify START: systemID=\(systemID), file=\(rom.path.lastPathComponent)")
        LoggerService.romIdentify("Identify START: systemID=\(systemID), path=\(rom.path.path)")
        identifyLog.info("Identify: start system=\(systemID, privacy: .public) file=\(rom.path.lastPathComponent, privacy: .public)")

        LoggerService.debug(category: "ROMIdentify", "Fetching/loading DAT for system=\(systemID)")
        let db = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)
        if db.isEmpty {
            LoggerService.warning(category: "ROMIdentify", "Empty/missing database for system \(systemID)")
            LoggerService.romIdentifyWarn("Empty database for system \(systemID)")
            identifyLog.error("Identify: empty database for system \(systemID, privacy: .public)")
            return .databaseUnavailable
        }
        LoggerService.info(category: "ROMIdentify", "Database loaded for \(systemID): \(db.count) CRC entries")
        LoggerService.romIdentify("Database loaded: \(db.count) CRC entries for \(systemID)")
        identifyLog.info("Identify: database has \(db.count) CRC entries for lookup")

        LoggerService.debug(category: "ROMIdentify", "Computing CRC for \(rom.path.path)")
        guard let crc = computeCRC(for: rom.path, systemID: systemID) else {
            LoggerService.error(category: "ROMIdentify", "CRC read failed for \(rom.path.path)")
            LoggerService.romIdentifyError("CRC read failed for path=\(rom.path.path)")
            identifyLog.error("Identify: CRC read failed for \(rom.path.path, privacy: .public)")
            return .romReadFailed("Could not read the ROM file. If the library is on a removable drive or you moved files, re-add the folder in Settings.")
        }

        let key = crc.uppercased()
        LoggerService.info(category: "ROMIdentify", "ROM CRC=\(key)")
        LoggerService.romIdentify("ROM CRC=\(key)")
        identifyLog.info("Identify: ROM CRC \(key, privacy: .public)")

        if let info = db[key] {
            if let thumb = info.thumbnailLookupSystemID, thumb != systemID {
                LoggerService.info(category: "ROMIdentify", "CRC HIT: '\(info.name)' (thumbnail system override: \(thumb) — ROM system is \(systemID))")
                LoggerService.romIdentify("CRC match → \(info.name) (thumbnails: use system \(thumb), ROM is \(systemID))")
                identifyLog.info("Identify: CRC match → \(info.name, privacy: .public) (thumbnails: use system \(thumb, privacy: .public), ROM is \(systemID, privacy: .public))")
            } else {
                LoggerService.info(category: "ROMIdentify", "CRC HIT: '\(info.name)'")
                LoggerService.romIdentify("CRC match → \(info.name)")
                identifyLog.info("Identify: CRC match → \(info.name, privacy: .public)")
            }
            return .identified(info)
        }

        LoggerService.debug(category: "ROMIdentify", "No CRC match for \(key), trying identifyByName...")
        LoggerService.romIdentify("No CRC match for \(key), trying name match")
        let language = Self.currentEmulatorLanguage()
        if let byName = identifyByName(rom: rom, database: db, language: language) {
            LoggerService.info(category: "ROMIdentify", "NAME MATCH: '\(byName.name)' (language=\(language.name))")
            LoggerService.romIdentify("Filename match → \(byName.name) (language \(language.name))")
            identifyLog.info("Identify: filename match → \(byName.name, privacy: .public) (language \(language.name, privacy: .public))")
            return .identifiedFromName(byName)
        }

        LoggerService.info(category: "ROMIdentify", "NOT IDENTIFIED: CRC \(key) not in database and no filename match for system=\(systemID)")
        LoggerService.romIdentify("CRC \(key) not in database and no filename match for \(systemID)")
        identifyLog.notice("Identify: CRC \(key, privacy: .public) not in database and no filename match for \(systemID, privacy: .public)")
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

    /// Compare No-Intro titles after stripping region/version parentheticals.
    private static func normalizedComparableTitle(_ s: String) -> String {
        let stripped = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(s)
        return stripped
            .lowercased()
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Heuristic: No-Intro DATs use `description` as the game title and `name` as
    /// an internal ROM filename.  ScummVM/MAME DATs use `name` as the title and
    /// `description` as a long prose paragraph.  Pick whichever looks like a real title.
    fileprivate static func titleFromDatGame(name: String, description: String) -> String {
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

    // MARK: – Roman-numeral variant generation
    // Produces alternate forms of a normalised title where standalone Arabic
    // numerals 1-19 are replaced with their Roman equivalent, and vice versa.
    // Also strips a trailing " 1" or " i" because many ROM sets omit the
    // number for the first entry in a series (Road Rash 1 → Road Rash).
    private static func romanNumeralVariants(of normalized: String) -> [String] {
        guard normalized.count >= 2 else { return [] }
        var variants: Set<String> = []
        let arabicToRoman: [Int: String] = [
            1: "I",   2: "II",   3: "III",   4: "IV",
            5: "V",   6: "VI",   7: "VII",   8: "VIII",
            9: "IX",  10: "X",   11: "XI",   12: "XII",
            13: "XIII", 14: "XIV", 15: "XV",
            16: "XVI",  17: "XVII", 18: "XVIII", 19: "XIX",
        ]
        let romanToArabic: [String: Int] = {
            var d: [String: Int] = [:]
            for (a, r) in arabicToRoman {
                d[r.lowercased()] = a
                d[r] = a
            }
            return d
        }()
        // Arabic → Roman  (word-boundary match: not preceded by a letter, not followed by one)
        for (a, r) in arabicToRoman {
            let p = "(?<![a-zA-Z])\\b" + String(a) + "\\b(?![a-zA-Z0-9])"
            let s = normalized.replacingOccurrences(of: p, with: r, options: .regularExpression)
            if s != normalized { variants.insert(s) }
        }
        // Roman → Arabic
        for (r, a) in romanToArabic {
            let esc = NSRegularExpression.escapedPattern(for: r)
            let p = "(?<![a-zA-Z])\\b" + esc + "\\b(?![a-zA-Z0-9])"
            let s = normalized.replacingOccurrences(of: p, with: String(a), options: .regularExpression)
            if s != normalized { variants.insert(s) }
        }
        // Strip trailing " 1" or " i" for first-game-in-series
        let t = normalized.trimmingCharacters(in: .whitespaces)
        for pat in [" 1$", " i$"] {
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
        guard queryBase.count >= 2 else { return nil }

        // --- pass 1: exact match on base query ---
        var exact: [GameInfo] = []
        for info in database.values {
            let datBase = Self.normalizedComparableTitle(info.name)
            if datBase == queryBase {
                exact.append(info)
            }
        }

        // --- pass 2: exact match on Roman-numeral / trailing-number variants ---
        if exact.isEmpty {
            for variant in Self.romanNumeralVariants(of: queryBase) {
                for info in database.values {
                    let datBase = Self.normalizedComparableTitle(info.name)
                    if datBase == variant {
                        exact.append(info)
                    }
                }
                if !exact.isEmpty { break }
            }
        }

        // --- pass 3: substring / prefix containment (original fuzzy) ---
        var candidates = exact
        if candidates.isEmpty {
            for info in database.values {
                let datBase = Self.normalizedComparableTitle(info.name)
                guard datBase.count >= 3, queryBase.count >= 3 else { continue }
                if datBase.contains(queryBase) || queryBase.contains(datBase) {
                    candidates.append(info)
                }
            }
            // Final fallback: containment using Roman-numeral variants of the query
            if candidates.isEmpty {
                for variant in Self.romanNumeralVariants(of: queryBase) {
                    guard variant.count >= 3 else { continue }
                    for info in database.values {
                        let datBase = Self.normalizedComparableTitle(info.name)
                        guard datBase.count >= 3 else { continue }
                        if datBase.contains(variant) || variant.contains(datBase) {
                            candidates.append(info)
                        }
                    }
                    if !candidates.isEmpty { break }
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
            default:
                // Full file (No-Intro uses clean dumps for SNES, Genesis, etc.)
                dataToHash = fullData
            }

            return CRC32.compute(dataToHash)
        } catch {
            identifyLog.error("CRC read error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
    private static let libretroDatBasenameOverrides: [String: String] = [
        "snes": "Nintendo - Super Nintendo Entertainment System.dat",
        "genesis": "Sega - Mega Drive - Genesis.dat",
        "pce": "NEC - PC Engine - TurboGrafx 16.dat",
        "sms": "Sega - Master System - Mark III.dat",
        "gamegear": "Sega - Game Gear.dat",
        "saturn": "Sega - Saturn.dat",
        "32x": "Sega - 32X.dat",
        "dreamcast": "Sega - Dreamcast.dat",
        "atari2600": "Atari - 2600.dat",
        "atari5200": "Atari - 5200.dat",
        "atari7800": "Atari - 7800.dat",
        "lynx": "Atari - Lynx.dat",
        "gb": "Nintendo - Game Boy.dat",
        "gbc": "Nintendo - Game Boy Color.dat",
        "gba": "Nintendo - Game Boy Advance.dat",
        // libretro-database metadat/mame/MAME.dat
        "mame": "MAME.dat",
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

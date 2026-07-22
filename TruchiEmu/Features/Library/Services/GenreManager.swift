import Foundation
import SwiftUI

@MainActor
final class GenreManager: ObservableObject {
    static let shared = GenreManager()

    private let settingsKey = "genreMappings"
    private let tier2Key = "genreTier2Overrides"
    private let tier1Key = "genreTier1Overrides"
    private let hiddenGenresKey = "hiddenGenreDisplayNames"
    private let groupingKey = "genreGrouping"

    /// Full effective mapping (preset + overrides), kept for backward‑compat consumers.
    @Published private(set) var mappings: [String: String] = [:]
    @Published private(set) var tier2Overrides: [String: String] = [:]
    @Published private(set) var tier1Overrides: [String: String] = [:]
    @Published private(set) var hiddenGenres: Set<String> = []

    @Published var genreGrouping: GenreGrouping = .raw {
        didSet {
            AppSettings.set(groupingKey, value: genreGrouping.rawValue)
        }
    }

    private init() {
        genreGrouping = loadGrouping()
        loadAllMappings()
        loadHiddenGenres()
    }



    /// Separators that indicate a raw genre string contains multiple genres:
    /// comma, slash, pipe, semicolon.
    private static let genreSeparators = CharacterSet(charactersIn: ",/|;")

    /// Splits a raw multi-genre string into individual components.
    func splitGenreString(_ raw: String) -> [String] {
        raw.components(separatedBy: Self.genreSeparators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Returns display names for a raw genre string.
    /// Splits on separators (`,`, `/`, `|`, `;`) and maps each component.
    /// In minimal mode, chains through detailed mappings first (Tier 3 → Tier 2 → Tier 1).
    /// Uses the preset as fallback; user overrides in `mappings` take precedence.
    func effectiveDisplayNames(for original: String?) -> [String] {
        guard let genre = original, !genre.isEmpty else { return ["Unknown"] }
        let components = splitGenreString(genre)
        if components.isEmpty { return [resolveDisplay(for: genre)] }
        var results: [String] = []
        for comp in components {
            results.append(resolveDisplay(for: comp))
        }
        return results.isEmpty ? [genre] : Array(Set(results)).sorted()
    }

    /// Resolves a single genre component through the mapping chain.
    /// - `.minimal`:  user Tier 2 override → preset detailed → identity (Tier 2 name)
    ///                → user Tier 1 override → preset minimal → identity
    /// - `.detailed`: user Tier 2 override → preset detailed → identity
    /// - `.raw`:      identity
    /// - `.custom`:   same chain as minimal (overrides + presets)
    private func resolveDisplay(for comp: String) -> String {
        switch genreGrouping {
        case .minimal, .custom:
            let tier2 = tier2Overrides[comp] ?? Self.detailedMappings[comp] ?? comp
            return tier1Overrides[tier2] ?? Self.minimalMappings[tier2] ?? tier2
        case .detailed:
            return tier2Overrides[comp] ?? Self.detailedMappings[comp] ?? comp
        case .raw:
            return comp
        }
    }

    /// Convenience: flattened string for legacy callers that expect a single display name.
    func effectiveDisplayName(for original: String?) -> String {
        effectiveDisplayNames(for: original).joined(separator: " / ")
    }

    /// Returns the Tier 2 (detailed) display name for a raw genre component.
    /// Considers user overrides first, then preset detailed mappings.
    /// In detailed/raw modes, returns the original as-is.
    func subGenreDisplayName(for original: String) -> String {
        switch genreGrouping {
        case .minimal:
            tier2Overrides[original] ?? Self.detailedMappings[original] ?? original
        default:
            original
        }
    }

    func getAllDisplayGenres(from roms: [ROM]) -> [String] {
        let names = roms.flatMap { effectiveDisplayNames(for: $0.metadata?.genre) }
        return Array(Set(names)).sorted()
    }

    func getVisibleDisplayGenres(from roms: [ROM]) -> [String] {
        getAllDisplayGenres(from: roms).filter { !hiddenGenres.contains($0) }
    }

    /// Resolves a ROM's effective display genres for filtering.
    func displayGenres(for rom: ROM) -> [String] {
        effectiveDisplayNames(for: rom.metadata?.genre)
    }

    var allMappings: [(original: String, display: String)] {
        var seen: Set<String> = []
        var result: [(String, String)] = []
        for (k, v) in tier2Overrides { result.append((k, v)); seen.insert(k) }
        for (k, v) in tier1Overrides where !seen.contains(k) { result.append((k, v)); seen.insert(k) }
        for (k, v) in Self.detailedMappings where !seen.contains(k) { result.append((k, v)) }
        // Only include minimal preset entries for .minimal mode
        if genreGrouping == .minimal {
            for (k, v) in Self.minimalMappings where !seen.contains(k) { result.append((k, v)) }
        }
        return result
    }

    /// Merges raw genre components into a display group.
    /// In minimal/detailed modes, adds a Tier 2 override.
    /// In custom mode, stores a flat mapping in `mappings`.
    func mergeGenres(from originals: Set<String>, to display: String) {
        if genreGrouping == .custom {
            for original in originals {
                mappings[original] = display
            }
        } else {
            for original in originals {
                tier2Overrides[original] = display
            }
        }
        saveAllMappings()
        objectWillChange.send()
    }

    /// Merges a Tier 2 sub‑group into a different Tier 1 group (minimal mode only).
    func mergeTier2Into(_ tier2Name: String, tier1Name: String) {
        tier1Overrides[tier2Name] = tier1Name
        saveAllMappings()
        objectWillChange.send()
    }

    func removeMapping(for original: String) {
        if genreGrouping == .custom {
            mappings.removeValue(forKey: original)
        } else if tier2Overrides.keys.contains(original) || tier1Overrides.keys.contains(original) {
            // User had an explicit override → remove it (restore preset or identity).
            tier2Overrides.removeValue(forKey: original)
            tier1Overrides.removeValue(forKey: original)
        } else {
            // Genre is grouped purely by a preset → opt out via identity override.
            tier2Overrides[original] = original
        }
        saveAllMappings()
        objectWillChange.send()
    }

    func isHidden(_ displayName: String) -> Bool {
        hiddenGenres.contains(displayName)
    }

    func toggleHidden(_ displayName: String) {
        if hiddenGenres.contains(displayName) {
            hiddenGenres.remove(displayName)
        } else {
            hiddenGenres.insert(displayName)
        }
        saveHiddenGenres()
    }

    var hiddenDisplayNames: [String] {
        hiddenGenres.sorted()
    }

    /// Switches to a grouping mode without clearing user overrides.
    /// Call `resetOverrides()` if the user wants to start fresh.
    func applyGrouping(_ grouping: GenreGrouping) {
        genreGrouping = grouping
        if grouping == .custom {
            // Load the old flat mapping; if none exists, start empty.
            if let loaded: [String: String] = AppSettings.get(settingsKey, type: [String: String].self) {
                mappings = loaded
            } else {
                mappings = [:]
            }
        } else {
            mappings = [:]
        }
        objectWillChange.send()
    }

    /// True only when the user explicitly picked the Custom mode.
    var isCustom: Bool {
        genreGrouping == .custom
    }

    /// True when the user has made overrides while in a preset mode.
    var hasOverrides: Bool {
        !tier2Overrides.isEmpty || !tier1Overrides.isEmpty
    }

    /// Clears all user overrides but keeps the current grouping mode.
    func resetOverrides() {
        tier2Overrides = [:]
        tier1Overrides = [:]
        mappings = [:]
        saveAllMappings()
        objectWillChange.send()
    }

    // MARK: - Persistence

    private func loadGrouping() -> GenreGrouping {
        if let raw: String = AppSettings.get(groupingKey, type: String.self),
           let g = GenreGrouping(rawValue: raw) {
            return g
        }
        return .detailed
    }

    /// Loads all mapping data, with backward compatibility for the old single‑dict format.
    private func loadAllMappings() {
        // Try new two‑dict format first.
        if let t2: [String: String] = AppSettings.get(tier2Key, type: [String: String].self) {
            tier2Overrides = t2
        }
        if let t1: [String: String] = AppSettings.get(tier1Key, type: [String: String].self) {
            tier1Overrides = t1
        }

        // Legacy: load old flat mappings.
        if let old: [String: String] = AppSettings.get(settingsKey, type: [String: String].self) {
            // If new overrides exist, old format is a leftover — ignore it.
            if tier2Overrides.isEmpty && tier1Overrides.isEmpty {
                if genreGrouping == .custom {
                    mappings = old
                }
                // For preset modes, ignore the old preset dump (the presets themselves are the source).
            }
        }

    }

    private func saveAllMappings() {
        AppSettings.set(tier2Key, value: tier2Overrides)
        AppSettings.set(tier1Key, value: tier1Overrides)
    }

    private func loadHiddenGenres() {
        if let loaded: [String] = AppSettings.get(hiddenGenresKey, type: [String].self) {
            hiddenGenres = Set(loaded)
        }
    }

    private func saveHiddenGenres() {
        AppSettings.set(hiddenGenresKey, value: Array(hiddenGenres))
    }
}

// MARK: - Genre Grouping

enum GenreGrouping: String, Codable {
    case minimal
    case detailed
    case raw
    case custom
}

// MARK: - Genre Presets

extension GenreManager {
    /// Detailed preset: maps raw genre strings to Tier 2 sub‑genre display names.
    static let detailedMappings: [String: String] = {
        var m: [String: String] = [:]

        // ── Action ──────────────────────────────────────────
        // Shoot 'em Up (Shmup)
        m["Shoot'em Up"]           = "Shoot 'em Up (Shmup)"
        m["Shoot 'em Up"]          = "Shoot 'em Up (Shmup)"
        m["Flying Vertical"]       = "Shoot 'em Up (Shmup)"
        m["Flying Horizontal"]     = "Shoot 'em Up (Shmup)"
        m["Misc. Vertical"]        = "Shoot 'em Up (Shmup)"
        m["Misc. Horizontal"]      = "Shoot 'em Up (Shmup)"
        m["Driving Vertical"]      = "Shoot 'em Up (Shmup)"
        m["Driving Horizontal"]    = "Shoot 'em Up (Shmup)"
        m["Driving Diagonal"]      = "Shoot 'em Up (Shmup)"

        // Run and Gun
        m["Walking"]               = "Run and Gun"
        m["Commando"]              = "Run and Gun"

        // Beat 'em Up
        m["Beat'em Up"]            = "Beat 'em Up"
        m["Beat 'em Up"]           = "Beat 'em Up"
        m["Fighter Scrolling"]     = "Beat 'em Up"
        m["Brawler"]               = "Beat 'em Up"
        m["Shooter Scrolling"]     = "Beat 'em Up"

        // Fighting
        m["Fighting"]              = "Fighting"
        m["Fighter"]               = "Fighting"
        m["Versus"]                = "Fighting"
        m["2.5D"]                  = "Fighting"
        m["2D"]                    = "Fighting"
        m["Vertical"]              = "Fighting"

        // First-Person Shooter
        m["1st Person"]            = "First-Person Shooter"
        m["Flying 1st Person"]     = "First-Person Shooter"
        m["Driving 1st Person"]    = "First-Person Shooter"

        // Hack and Slash
        m["Hack and Slash"]        = "Hack and Slash"

        // Light Gun
        m["Lightgun Shooter"]      = "Light Gun"
        m["Light Gun"]             = "Light Gun"
        m["Gun"]                   = "Light Gun"

        // Stealth
        m["Stealth"]               = "Stealth"

        // Shooter (generic libretro parent → subgenre)
        m["Shooter"]               = "First-Person Shooter"

        // ── Platformer ──────────────────────────────────────
        m["Platform"]              = "2D Platformer"
        m["Platformer"]            = "2D Platformer"
        m["Run Jump"]              = "2D Platformer"
        m["Run, Jump & Scrolling"] = "2D Platformer"
        m["Run Jump & Scrolling"]  = "2D Platformer"
        m["Climbing"]              = "2D Platformer"
        m["Building"]              = "2D Platformer"

        // ── RPG ─────────────────────────────────────────────
        m["Role-playing (RPG)"]    = "Turn-Based RPG"
        m["Role-Playing"]          = "Turn-Based RPG"
        m["RPG"]                   = "Turn-Based RPG"
        m["Action RPG"]            = "Action RPG"
        m["Tactical RPG"]          = "Tactical RPG"
        m["Dungeon Crawler"]       = "Dungeon Crawler"

        // ── Sports ──────────────────────────────────────────
        // Racing / Driving
        m["Racing"]                = "Racing / Driving"
        m["Driving"]               = "Racing / Driving"
        m["Race"]                  = "Racing / Driving"
        m["Race Track"]            = "Racing / Driving"
        m["Race 1st Person"]       = "Racing / Driving"
        m["Race (chase view)"]     = "Racing / Driving"
        m["Motorbike"]             = "Racing / Driving"
        m["Boat"]                  = "Racing / Driving"
        m["Demolition Derby"]      = "Racing / Driving"
        m["FireTruck Guide"]       = "Racing / Driving"

        // Combat Sports
        m["Boxing"]                = "Combat Sports"
        m["Wrestling"]             = "Combat Sports"
        m["Armwrestling"]          = "Combat Sports"
        m["Sumo"]                  = "Combat Sports"
        m["Bull Fighting"]         = "Combat Sports"

        // Team Sports
        m["Sports"]                = "Team Sports"
        m["Baseball"]              = "Team Sports"
        m["Soccer"]                = "Team Sports"
        m["Football"]              = "Team Sports"
        m["Basketball"]            = "Team Sports"
        m["Hockey"]                = "Team Sports"
        m["Volleyball"]            = "Team Sports"
        m["Rugby Football"]        = "Team Sports"

        // Individual Sports
        m["Tennis"]                = "Individual Sports"
        m["Golf"]                  = "Individual Sports"
        m["Bowling"]               = "Individual Sports"
        m["Pool"]                  = "Individual Sports"
        m["Darts"]                 = "Individual Sports"
        m["Skiing"]                = "Individual Sports"
        m["Track & Field"]         = "Individual Sports"
        m["Horse Racing"]          = "Individual Sports"
        m["Fishing"]               = "Hunting and Fishing"
        m["Hunting and Fishing"]   = "Hunting and Fishing"

        // Extreme Sports
        m["Skateboarding"]         = "Extreme Sports"
        m["Hang Gliding"]          = "Extreme Sports"

        // Misc sports
        m["Sports with Animals"]   = "Team Sports"
        m["Misc."]                 = "Team Sports"

        // ── Strategy ────────────────────────────────────────
        m["Strategy"]              = "Real-Time Strategy"
        m["Real Time Strategy"]    = "Real-Time Strategy"
        m["Real-Time Strategy"]    = "Real-Time Strategy"
        m["Turn-Based Strategy"]   = "Turn-Based Strategy"
        m["Turn Based Strategy"]   = "Turn-Based Strategy"
        m["Tactics"]               = "Tactical Strategy"
        m["Tactical Strategy"]     = "Tactical Strategy"
        m["Tower Defense"]         = "Tower Defense"
        m["Wargame"]               = "Turn-Based Strategy"

        // ── Simulation ──────────────────────────────────────
        m["Simulation"]            = "Flight / Vehicle Sim"
        m["Flight Simulator"]      = "Flight / Vehicle Sim"
        m["Vehicle Simulation"]    = "Flight / Vehicle Sim"
        m["Flight"]                = "Flight / Vehicle Sim"
        m["Life Simulation"]       = "Life / Pet Sim"
        m["Construction and Management Simulation"] = "Management / Tycoon"
        m["Management"]            = "Management / Tycoon"
        m["Management / Tycoon"]   = "Management / Tycoon"

        // ── Puzzle ──────────────────────────────────────────
        m["Puzzle"]                = "Tile-Matching / Block"
        m["Drop"]                  = "Tile-Matching / Block"
        m["Toss"]                  = "Tile-Matching / Block"
        m["Match"]                 = "Tile-Matching / Block"
        m["Outline"]               = "Tile-Matching / Block"
        m["Breakout"]              = "Tile-Matching / Block"
        m["Ball & Paddle"]         = "Tile-Matching / Block"
        m["Blocks"]                = "Tile-Matching / Block"

        m["Board Game"]            = "Card & Board"
        m["Board"]                 = "Card & Board"
        m["Card"]                  = "Card & Board"
        m["Cards"]                 = "Card & Board"
        m["Tabletop"]              = "Card & Board"
        m["Mahjong"]               = "Card & Board"
        m["Hanafuda"]              = "Card & Board"
        m["Othello - Reversi"]     = "Card & Board"
        m["Cards & Tiles"]         = "Card & Board"

        m["Maze"]                  = "Logic Puzzle"
        m["Sliding"]               = "Logic Puzzle"
        m["Reconstruction"]        = "Logic Puzzle"
        m["Misc."]                 = "Logic Puzzle"

        m["Quiz"]                  = "Trivia / Quiz"
        m["Questions in English"]  = "Trivia / Quiz"
        m["Questions in Japanese"] = "Trivia / Quiz"

        // ── Casual ──────────────────────────────────────────
        m["Action"]                = "Arcade / Single Screen"
        m["Arcade"]                = "Arcade / Single Screen"
        m["Field"]                 = "Arcade / Single Screen"
        m["Gallery"]               = "Arcade / Single Screen"
        m["Collect"]               = "Arcade / Single Screen"
        m["Collect & Put"]         = "Arcade / Single Screen"
        m["Digging"]               = "Arcade / Single Screen"
        m["Defeat Enemies"]        = "Arcade / Single Screen"
        m["Fighter"]               = "Arcade / Single Screen"
        m["Surround"]              = "Arcade / Single Screen"
        m["Escape"]                = "Arcade / Single Screen"
        m["Cross"]                 = "Arcade / Single Screen"
        m["Ladders"]               = "Arcade / Single Screen"
        m["Paint"]                 = "Arcade / Single Screen"
        m["Move and Sort"]         = "Arcade / Single Screen"
        m["Integrate"]             = "Arcade / Single Screen"
        m["Jump and Touch"]        = "Arcade / Single Screen"
        m["Change Surface"]        = "Arcade / Single Screen"

        m["Party"]                 = "Party / Minigames"
        m["Party / Minigames"]     = "Party / Minigames"
        m["Mini-Games"]            = "Party / Minigames"
        m["Multiplay"]             = "Party / Minigames"
        m["Casual"]                = "Party / Minigames"
        m["Casual Game"]           = "Party / Minigames"
        m["Casino"]                = "Party / Minigames"
        m["Gambling"]              = "Party / Minigames"

        m["Educational"]           = "Educational"
        m["Education"]             = "Educational"

        // ── Adventure ───────────────────────────────────────
        m["Adventure"]             = "Point-and-Click"
        m["Point & Click"]         = "Point-and-Click"
        m["Point-and-Click"]       = "Point-and-Click"
        m["Text Adventure"]        = "Interactive Fiction"
        m["Interactive Fiction"]   = "Interactive Fiction"

        m["Visual Novel"]          = "Visual Novel"

        // ── Others ──────────────────────────────────────────
        m["Music"]                 = "Rhythm / Music"
        m["Music / Dancing"]       = "Rhythm / Music"
        m["Music Game"]            = "Rhythm / Music"
        m["Instruments"]           = "Rhythm / Music"
        m["Dancing"]               = "Rhythm / Music"
        m["Rhythm"]                = "Rhythm / Music"

        m["Pinball"]               = "Pinball"

        m["Various"]               = "Utilities / Test ROMs"
        m["Utilities"]             = "Utilities / Test ROMs"
        m["Test"]                  = "Utilities / Test ROMs"

        // Unmapped raw genres that don't belong to a specific Tier 2 subgenre
        // are kept as-is in detailed mode (identity). This includes:
        // Compilation, Horror, MMO, Sandbox, etc.

        return m
    }()

    /// Minimal preset: maps raw genre strings to Tier 1 display names.
    static let minimalMappings: [String: String] = {
        var m: [String: String] = [:]

        // ── Action ──────────────────────────────────────────
        let action: [String] = [
            "Action", "Arcade",
            "Fighting", "Fighter", "Versus", "2.5D", "2D", "Vertical", "Field",
            "Beat'em Up", "Beat 'em Up", "Fighter Scrolling", "Shooter Scrolling", "Brawler",
            "Shooter", "Shoot'em Up", "Shoot 'em Up", "Shoot 'em Up (Shmup)",
            "Lightgun Shooter", "Light Gun", "Gun",
            "Stealth",
            "Hack and Slash",
            "Walking", "Commando", "Run and Gun",
            "First-Person Shooter", "Flying 1st Person", "Driving 1st Person",
            "Arcade / Single Screen",
            "Flying Vertical", "Flying Horizontal", "Misc. Vertical", "Misc. Horizontal",
            "Driving Vertical", "Driving Horizontal", "Driving Diagonal",
            "1st Person", "Flying 1st Person", "Driving 1st Person",
            "Flying (chase view)", "Driving (chase view)",
            "3rd Person",
            "Shooter", "Shooter Small", "Shooter Large",
            "Shooter / Flying Vertical", "Shooter / Flying Horizontal",
            "Shooter / Gallery", "Shooter / Gun", "Shooter / Field",
            "Shooter / Walking", "Shooter / Driving",
            "Shooter / 1st Person", "Shooter / 3rd Person",
            "Shooter / Flying (chase view)", "Shooter / Driving (chase view)",
            "Shooter / Misc. Vertical", "Shooter / Misc. Horizontal",
            "Shooter / Versus",
            "Fighter / Versus", "Fighter / 2.5D", "Fighter / 2D", "Fighter / Vertical",
            "Fighter / Field", "Fighter / Misc.", "Fighter / Driving Vertical",
        ]
        for g in action { m[g] = "Action" }

        // ── RPG ─────────────────────────────────────────────
        let rpg: [String] = [
            "Role-playing (RPG)", "Role-Playing", "RPG",
            "Action RPG", "Tactical RPG", "Dungeon Crawler",
            "Turn-Based RPG",
        ]
        for g in rpg { m[g] = "RPG" }

        // ── Platformer ──────────────────────────────────────
        let platformer: [String] = [
            "Platform", "Platformer", "2D Platformer",
            "Run Jump", "Run, Jump & Scrolling", "Run Jump & Scrolling",
            "Climbing", "Building",
            "Platform / Run Jump", "Platform / Run, Jump & Scrolling",
            "Platform / Shooter Scrolling", "Platform / Fighter Scrolling",
            "Platform / Shooter", "Platform / Fighter",
        ]
        for g in platformer { m[g] = "Platformer" }

        // ── Sports ──────────────────────────────────────────
        let sports: [String] = [
            "Sports", "Sports with Animals",
            "Racing", "Driving",
            "Race", "Race Track", "Race 1st Person", "Race (chase view)",
            "Motorbike", "Boat", "Demolition Derby", "FireTruck Guide",
            "Baseball", "Soccer", "Football", "Basketball", "Hockey",
            "Volleyball", "Rugby Football", "Handball",
            "Tennis", "Golf", "Bowling", "Pool", "Darts",
            "Skiing", "Skateboarding", "Track & Field", "Horse Racing",
            "Boxing", "Wrestling", "Armwrestling", "Sumo", "Bull Fighting",
            "Fishing", "Hunting and Fishing",
            "Hang Gliding",
            "Sports / Baseball", "Sports / Soccer", "Sports / Football",
            "Sports / Basketball", "Sports / Tennis", "Sports / Golf",
            "Sports / Bowling", "Sports / Wrestling", "Sports / Boxing",
            "Sports / Hockey", "Sports / Pool", "Sports / Track & Field",
            "Sports / Skiing", "Sports / Skateboarding", "Sports / Volleyball",
            "Sports / Darts", "Sports / Fishing", "Sports / Horse Racing",
            "Sports / Misc.", "Sports / Sumo", "Sports / Rugby Football",
            "Sports / Armwrestling", "Sports / Bull Fighting",
            "Driving / Race", "Driving / Race Track", "Driving / Race 1st Person",
            "Driving / Race (chase view)", "Driving / Motorbike",
            "Driving / Demolition Derby", "Driving / Misc.", "Driving / Boat",
            "Driving / FireTruck Guide",
            "Combat Sports", "Team Sports", "Individual Sports", "Extreme Sports",
            "Racing / Driving", "Hunting and Fishing",
        ]
        for g in sports { m[g] = "Sports" }

        // ── Casual ──────────────────────────────────────────
        let casual: [String] = [
            "Casual", "Casual Game",
            "Party", "Mini-Games", "Multiplay",
            "Casino", "Gambling",
            "Party / Minigames",
            "Ball & Paddle", "Breakout",
            "Jump and Touch",
            "Casino / Cards",
        ]
        for g in casual { m[g] = "Casual" }

        // ── Puzzle ──────────────────────────────────────────
        let puzzle: [String] = [
            "Puzzle", "Quiz",
            "Board Game", "Board", "Tabletop",
            "Drop", "Toss", "Match", "Outline", "Blocks", "Sliding",
            "Reconstruction", "Maze", "Digging", "Collect", "Collect & Put",
            "Defeat Enemies", "Surround", "Escape", "Cross", "Ladders",
            "Paint", "Move and Sort", "Integrate",
            "Card", "Cards", "Cards & Tiles", "Mahjong", "Hanafuda", "Othello - Reversi",
            "Puzzle / Drop", "Puzzle / Match", "Puzzle / Toss",
            "Puzzle / Maze", "Puzzle / Outline", "Puzzle / Sliding",
            "Puzzle / Reconstruction", "Puzzle / Misc.",
            "Questions in English", "Questions in Japanese",
            "Tile-Matching / Block", "Card & Board", "Logic Puzzle", "Trivia / Quiz",
            "Tabletop / Mahjong", "Tabletop / Hanafuda", "Tabletop / Othello - Reversi",
            "Tabletop / Misc.",
            "Ball & Paddle / Breakout", "Ball & Paddle / Jump and Touch",
            "Maze / Shooter Small", "Maze / Shooter Large", "Maze / Collect",
            "Maze / Collect & Put", "Maze / Surround", "Maze / Digging",
            "Maze / Driving", "Maze / Defeat Enemies", "Maze / Outline",
            "Maze / Ladders", "Maze / Escape", "Maze / Cross",
            "Maze / Paint", "Maze / Blocks", "Maze / Move and Sort",
            "Maze / Integrate", "Maze / Change Surface", "Maze / Fighter",
        ]
        for g in puzzle { m[g] = "Puzzle" }

        // ── Strategy ────────────────────────────────────────
        let strategy: [String] = [
            "Strategy",
            "Real-Time Strategy", "Real Time Strategy",
            "Turn-Based Strategy", "Turn Based Strategy",
            "Tactics", "Tactical Strategy",
            "Tower Defense", "Wargame",
        ]
        for g in strategy { m[g] = "Strategy" }

        // ── Simulation ──────────────────────────────────────
        let simulation: [String] = [
            "Simulation",
            "Flight Simulator", "Vehicle Simulation", "Flight",
            "Life Simulation",
            "Construction and Management Simulation", "Management",
            "Management / Tycoon", "Flight / Vehicle Sim",
            "Life / Pet Sim",
        ]
        for g in simulation { m[g] = "Simulation" }

        // ── Adventure ───────────────────────────────────────
        let adventure: [String] = [
            "Adventure",
            "Point & Click", "Point-and-Click",
            "Visual Novel",
            "Text Adventure", "Interactive Fiction",
            "Adventure / Point & Click", "Adventure / Point & Click / Education",
            "Adventure / Point & Click / Role-Playing",
        ]
        for g in adventure { m[g] = "Adventure" }

        // ── Others ──────────────────────────────────────────
        let others: [String] = [
            "Educational", "Education",
            "Compilation", "Various",
            "Music", "Music / Dancing", "Music Game", "Instruments", "Dancing", "Rhythm",
            "Pinball",
            "MMO", "Massively Multiplayer",
            "Sandbox",
            "Horror",
            "Utilities", "Test",
            "MultiGame / Compilation", "MultiGame / Mini-Games",
            "Utilities / Test ROMs", "Rhythm / Music",
            "Electromechanical / Misc.",
        ]
        for g in others { m[g] = "Others" }

        return m
    }()
}

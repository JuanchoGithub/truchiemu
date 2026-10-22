import Foundation
import SwiftUI

// A user-defined category for organizing games in the library
struct GameCategory: Identifiable, Codable, Hashable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var iconName: String // SF Symbol name
    var customIconPath: String? // Path to user-uploaded custom icon
    var colorHex: String // Hex color string
    
    // Array of ROM IDs that belong to this category
    var gameIDs: [UUID] = []

    // Stable game keys (see StableGameIdentity) for the same membership.
    // ROM IDs change on every database loss and re-add; these keys do not,
    // so membership survives a re-add. Empty for categories created before
    // stable identity existed; backfilled on next add/display.
    var gameKeys: [String] = []
    
    // Display order in the sidebar
    var sortOrder: Int = 0

    // MARK: - Smart category rules

    // A smart category stores a search query plus rules. Membership is
    // evaluated against the live library, so new matching games appear
    // automatically.
    var isSmart: Bool = false
    var smartQuery: String = ""
    // Internal system IDs (ROM.systemID values) hidden from this category.
    var smartDisabledSystemIDs: [String] = []
    // Internal system IDs explicitly enabled at save/edit time.
    var smartEnabledSystemIDs: [String] = []
    // When true, systems that become active later are added automatically.
    // False for single-system categories, so a new system does not silently
    // join them.
    var smartFollowsNewSystems: Bool = true
    // GameFilterOption raw values captured as part of the category.
    var smartActiveFilters: [String] = []
    // Display genre names captured as part of the category.
    var smartGenres: [String] = []
    // Explicit per-game overrides. Includes bypass the system and query rules;
    // excludes override everything.
    var smartIncludedGameKeys: [String] = []
    var smartExcludedGameKeys: [String] = []

    // Membership test that survives database loss and re-add.
    func contains(_ rom: ROM) -> Bool {
        if isSmart { return smartMember(rom) }
        return gameIDs.contains(rom.id) || gameKeys.contains(rom.stableIdentityKey)
    }

    // True when every internal ID of one display system is enabled in the
    // stored rules. Falls back to the disabled list for older categories.
    func smartSystemEnabled(internalIDs: [String]) -> Bool {
        if !smartEnabledSystemIDs.isEmpty {
            return internalIDs.allSatisfy { smartEnabledSystemIDs.contains($0) }
        }
        return !internalIDs.allSatisfy { smartDisabledSystemIDs.contains($0) }
    }

    // Full smart membership evaluation. `genreMatches` lets callers supply
    // the display-genre mapping (GenreManager lives on the main actor).
    func smartMember(_ rom: ROM, genreMatches: (ROM) -> Bool = { _ in true }) -> Bool {
        guard isSmart else { return contains(rom) }

        let key = rom.stableIdentityKey
        if smartExcludedGameKeys.contains(key) { return false }
        if smartIncludedGameKeys.contains(key) { return true }

        if let systemID = rom.systemID {
            if smartDisabledSystemIDs.contains(systemID) { return false }
            if !smartFollowsNewSystems && !smartEnabledSystemIDs.contains(systemID) {
                return false
            }
        }

        let terms = smartQuery.split(separator: " ").map(String.init)
        if !terms.isEmpty {
            let matches = terms.allSatisfy { term in
                rom.displayName.localizedCaseInsensitiveContains(term)
            }
            if !matches { return false }
        }

        for rawValue in smartActiveFilters {
            guard let option = GameFilterOption(rawValue: rawValue) else { continue }
            if !option.matches(rom) { return false }
        }

        if !smartGenres.isEmpty && !genreMatches(rom) { return false }
        return true
    }

    // MARK: - Codable (tolerant: gameKeys missing in pre-migration data)

    enum CodingKeys: String, CodingKey {
        case id, name, iconName, customIconPath, colorHex
        case gameIDs, gameKeys, sortOrder
        case isSmart, smartQuery, smartDisabledSystemIDs, smartEnabledSystemIDs
        case smartFollowsNewSystems, smartActiveFilters
        case smartGenres, smartIncludedGameKeys, smartExcludedGameKeys
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        iconName: String,
        customIconPath: String? = nil,
        colorHex: String,
        gameIDs: [UUID] = [],
        gameKeys: [String] = [],
        sortOrder: Int = 0,
        isSmart: Bool = false,
        smartQuery: String = "",
        smartDisabledSystemIDs: [String] = [],
        smartEnabledSystemIDs: [String] = [],
        smartFollowsNewSystems: Bool = true,
        smartActiveFilters: [String] = [],
        smartGenres: [String] = [],
        smartIncludedGameKeys: [String] = [],
        smartExcludedGameKeys: [String] = []
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.customIconPath = customIconPath
        self.colorHex = colorHex
        self.gameIDs = gameIDs
        self.gameKeys = gameKeys
        self.sortOrder = sortOrder
        self.isSmart = isSmart
        self.smartQuery = smartQuery
        self.smartDisabledSystemIDs = smartDisabledSystemIDs
        self.smartEnabledSystemIDs = smartEnabledSystemIDs
        self.smartFollowsNewSystems = smartFollowsNewSystems
        self.smartActiveFilters = smartActiveFilters
        self.smartGenres = smartGenres
        self.smartIncludedGameKeys = smartIncludedGameKeys
        self.smartExcludedGameKeys = smartExcludedGameKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "gamecontroller.fill"
        customIconPath = try container.decodeIfPresent(String.self, forKey: .customIconPath)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "007AFF"
        gameIDs = try container.decodeIfPresent([UUID].self, forKey: .gameIDs) ?? []
        gameKeys = try container.decodeIfPresent([String].self, forKey: .gameKeys) ?? []
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isSmart = try container.decodeIfPresent(Bool.self, forKey: .isSmart) ?? false
        smartQuery = try container.decodeIfPresent(String.self, forKey: .smartQuery) ?? ""
        smartDisabledSystemIDs = try container.decodeIfPresent([String].self, forKey: .smartDisabledSystemIDs) ?? []
        smartEnabledSystemIDs = try container.decodeIfPresent([String].self, forKey: .smartEnabledSystemIDs) ?? []
        smartFollowsNewSystems = try container.decodeIfPresent(Bool.self, forKey: .smartFollowsNewSystems) ?? true
        smartActiveFilters = try container.decodeIfPresent([String].self, forKey: .smartActiveFilters) ?? []
        smartGenres = try container.decodeIfPresent([String].self, forKey: .smartGenres) ?? []
        smartIncludedGameKeys = try container.decodeIfPresent([String].self, forKey: .smartIncludedGameKeys) ?? []
        smartExcludedGameKeys = try container.decodeIfPresent([String].self, forKey: .smartExcludedGameKeys) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconName, forKey: .iconName)
        try container.encodeIfPresent(customIconPath, forKey: .customIconPath)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(gameIDs, forKey: .gameIDs)
        try container.encode(gameKeys, forKey: .gameKeys)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isSmart, forKey: .isSmart)
        try container.encode(smartQuery, forKey: .smartQuery)
        try container.encode(smartDisabledSystemIDs, forKey: .smartDisabledSystemIDs)
        try container.encode(smartEnabledSystemIDs, forKey: .smartEnabledSystemIDs)
        try container.encode(smartFollowsNewSystems, forKey: .smartFollowsNewSystems)
        try container.encode(smartActiveFilters, forKey: .smartActiveFilters)
        try container.encode(smartGenres, forKey: .smartGenres)
        try container.encode(smartIncludedGameKeys, forKey: .smartIncludedGameKeys)
        try container.encode(smartExcludedGameKeys, forKey: .smartExcludedGameKeys)
    }
    
    // Title-cased name derived from a search query ("mario kart 64" ->
    // "Mario Kart 64"). Existing capitalisation (acronyms) is preserved.
    static func autoName(fromQuery query: String) -> String {
        query
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { word -> String in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    // Derived color
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    // Common icon presets
    static let commonIcons = [
        "gamecontroller.fill", "arcade.stick", "dpad.fill",
        "trophy.fill", "medal.fill", "star.fill",
        "heart.fill", "flame.fill", "bolt.fill",
        "figure.run", "figure.martial.arts", "figure.boxing",
        "figure.fencing", "figure.archery", "sportscourt.fill",
        "football.fill", "basketball.fill", "soccerball",
        "car.fill", "flag.checkered", "shield.lefthalf.filled",
        "scroll.fill", "building.columns.fill", "brain.fill",
        "puzzlepiece.fill", "dice.fill", "wand.and.stars",
        "moon.fill", "mountain.2.fill", "person.2.fill"
    ]
    
    // Predefined color palette
    static let colorPalette: [(name: String, hex: String)] = [
        ("Red", "FF3B30"), ("Orange", "FF9500"), ("Yellow", "FFCC00"),
        ("Green", "34C759"), ("Mint", "00C7BE"), ("Teal", "5AC8FA"),
        ("Cyan", "32ADE6"), ("Blue", "007AFF"), ("Indigo", "5856D6"),
        ("Purple", "AF52DE"), ("Pink", "FF2D55"), ("Brown", "A2845E"),
        ("Gray", "8E8E93"), ("Dark Gray", "636366")
    ]
    
    // Default categories
    static func defaults() -> [GameCategory] {
        []
    }
    
    static func == (lhs: GameCategory, rhs: GameCategory) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    var hex: String? {
        let components = Self.components(from: self)
        guard let components = components else { return nil }
        
        let r = UInt8(round(components.red * 255))
        let g = UInt8(round(components.green * 255))
        let b = UInt8(round(components.blue * 255))
        
        return String(format: "%02X%02X%02X", r, g, b)
    }
    
    private static func components(from color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let nsColor = NSColor(color)
        guard let components = nsColor.cgColor.components, components.count >= 3 else {
            return nil
        }
        return (
            red: components[0],
            green: components[1],
            blue: components[2],
            alpha: components.count >= 4 ? components[3] : 1.0
        )
    }
}
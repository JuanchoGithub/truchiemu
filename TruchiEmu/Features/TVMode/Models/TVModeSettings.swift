import Foundation

/// Settings for TV Mode. Small wrapper over AppSettings so views don't sprinkle
/// raw key strings. Pure functions over `AppSettings` — no instance state.
enum TVModeSettings {
    // MARK: - Keys
    private static let launchInTVModeKey = "tvMode_launchInTVMode"
    private static let themeKey = "tvMode_theme"
    private static let shownSmartEntriesKey = "tvMode_shownSmartEntries"
    private static let showSystemsKey = "tvMode_showSystems"

    // MARK: - Theme

    enum Theme: String, CaseIterable, Identifiable {
        case bold
        case muted
        case boxart
        var id: String { rawValue }
    }

    static var theme: Theme {
        guard let raw = AppSettings.getString(themeKey, defaultValue: nil) else { return .bold }
        return Theme(rawValue: raw) ?? .bold
    }

    static func setTheme(_ value: Theme) {
        AppSettings.set(themeKey, value: value.rawValue)
    }

    // MARK: - Launch

    static var launchInTVMode: Bool {
        AppSettings.getBool(launchInTVModeKey, defaultValue: false)
    }

    static func setLaunchInTVMode(_ value: Bool) {
        AppSettings.setBool(launchInTVModeKey, value: value)
    }

    // MARK: - Visible collections

    /// Identifiers for the smart (non-system) collections shown in row 1.
    /// Systems are partitioned under their own toggle to keep the menu obvious.
    enum SmartEntry: String, CaseIterable, Identifiable {
        case allGames
        case favorites
        case recent
        case lastAdded
        case retroAchievements
        case hidden
        case mameNonGames

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .allGames: return "square.grid.2x2"
            case .favorites: return "heart.fill"
            case .recent: return "clock.fill"
            case .lastAdded: return "plus.circle.fill"
            case .retroAchievements: return "trophy.fill"
            case .hidden: return "eye.slash.fill"
            case .mameNonGames: return "gearshape.2.fill"
            }
        }

        var filter: LibraryFilter {
            switch self {
            case .allGames: return .all
            case .favorites: return .favorites
            case .recent: return .recent
            case .lastAdded: return .lastAdded
            case .retroAchievements: return .retroAchievements
            case .hidden: return .hidden
            case .mameNonGames: return .mameNonGames
            }
        }

        var locKey: String {
            switch self {
            case .allGames: return "tvMode.settings.allGames"
            case .favorites: return "tvMode.settings.favorites"
            case .recent: return "tvMode.settings.recent"
            case .lastAdded: return "tvMode.settings.lastAdded"
            case .retroAchievements: return "tvMode.settings.retroAchievements"
            case .hidden: return "tvMode.settings.hidden"
            case .mameNonGames: return "tvMode.settings.mameNonGames"
            }
        }
    }

    /// Entries shown in row 1, in display order. Defaults are conservative and
    /// match the existing sidebar's smart collection set, excluding categories
    /// (those are not part of TV mode v1).
    static var shownSmartEntries: [SmartEntry] {
        if let raws = AppSettings.get(shownSmartEntriesKey, type: [String].self) {
            let preserved = SmartEntry.allCases.filter { raws.contains($0.rawValue) }
            return preserved
        }
        return [.allGames, .favorites, .recent, .lastAdded, .retroAchievements]
    }

    static func setShownSmartEntries(_ entries: [SmartEntry]) {
        AppSettings.set(shownSmartEntriesKey, value: entries.map(\.rawValue))
    }

    static var showSystems: Bool {
        AppSettings.getBool(showSystemsKey, defaultValue: true)
    }

    static func setShowSystems(_ value: Bool) {
        AppSettings.setBool(showSystemsKey, value: value)
    }
}

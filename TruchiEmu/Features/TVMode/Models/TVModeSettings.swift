import Foundation

/// Settings for TV Mode. Small wrapper over AppSettings so views don't sprinkle
/// raw key strings. Pure functions over `AppSettings` — no instance state.
enum TVModeSettings {
    // MARK: - Keys
    private static let launchInTVModeKey = "tvMode_launchInTVMode"
    private static let themeKey = "tvMode_theme"
    private static let shownSmartEntriesKey = "tvMode_shownSmartEntries"
    private static let showSystemsKey = "tvMode_showSystems"
    private static let screenSelectionModeKey = "tvMode_screenSelectionMode"
    private static let rememberedScreenIDKey = "tvMode_rememberedScreenID"
    private static let originScreenIDKey = "tvMode_originScreenID"

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

    // MARK: - Screen selection

    /// How TV Mode picks which display to launch on. `.alwaysMain` skips the
    /// picker entirely; `.ask` shows the picker on every TV-mode entry when
    /// more than one screen is connected; `.lastUsed` remembers the screen the
    /// user picked last and re-uses it on subsequent launches.
    enum ScreenSelectionMode: String, CaseIterable, Identifiable {
        case alwaysMain
        case ask
        case lastUsed

        var id: String { rawValue }

        var locKey: String {
            switch self {
            case .alwaysMain: return "tvMode.screenSelection.alwaysMain"
            case .ask: return "tvMode.screenSelection.ask"
            case .lastUsed: return "tvMode.screenSelection.lastUsed"
            }
        }
    }

    static var screenSelectionMode: ScreenSelectionMode {
        guard let raw = AppSettings.getString(screenSelectionModeKey, defaultValue: nil) else { return .ask }
        return ScreenSelectionMode(rawValue: raw) ?? .ask
    }

    static func setScreenSelectionMode(_ value: ScreenSelectionMode) {
        AppSettings.setString(screenSelectionModeKey, value: value.rawValue)
    }

    /// Stable identifier (CGDirectDisplayID as a string) of the screen the
    /// user last picked from the picker. Cleared by `resetRememberedScreen()`.
    static var rememberedScreenID: String? {
        AppSettings.getString(rememberedScreenIDKey, defaultValue: nil)
    }

    static func setRememberedScreenID(_ value: String?) {
        if let value {
            AppSettings.setString(rememberedScreenIDKey, value: value)
        } else {
            AppSettings.remove(rememberedScreenIDKey)
        }
    }

    static func resetRememberedScreen() {
        AppSettings.remove(rememberedScreenIDKey)
    }

    /// Display the main window was on right before the user entered TV Mode.
    /// Used by the exit path to put the window back where the user came from
    /// — falls back to "leave it on the TV-mode screen" when this id no
    /// longer matches an attached display (e.g. user unplugged the monitor).
    static var originScreenID: String? {
        AppSettings.getString(originScreenIDKey, defaultValue: nil)
    }

    static func setOriginScreenID(_ value: String?) {
        if let value {
            AppSettings.setString(originScreenIDKey, value: value)
        } else {
            AppSettings.remove(originScreenIDKey)
        }
    }
}

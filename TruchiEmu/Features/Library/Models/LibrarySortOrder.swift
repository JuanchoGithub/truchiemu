import Foundation

// MARK: - Library Sort Order

// One-value representation of the library's current sort. Replaces the
// legacy two-boolean design (`sortByLastPlayed` / `sortByLastAdded` AppSettings
// keys) so that future sort options are a one-line enum case addition.
//
// Display is owned by `LibrarySortPicker` — both the macOS Sort menu and the
// library filter-chip bar consume the same component.

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case name
    case lastPlayed
    case lastAdded
    case playtime
    case timeToBeat
    case systemName
    case systemAge

    var id: String { rawValue }

    /// Sort orders rendered in the primary section of the picker.
    static let primary: [LibrarySortOrder] = [.lastPlayed, .playtime, .timeToBeat, .systemName, .systemAge]

    /// Sort orders rendered in the "Other" section of the picker.
    static let other: [LibrarySortOrder] = [.lastAdded]

    /// Sorts that group the library into per-system sections. When one of
    /// these is active, the content views interleave section headers between
    /// systems (see LibrarySectionBuilder).
    var isSystemSort: Bool { self == .systemName || self == .systemAge }

    /// Persistence keys — single AppSettings entries replace the two legacy
    /// boolean keys (`sortByLastPlayed`, `sortByLastAdded`).
    static let orderKey = "sortOrder"
    static let ascendingKey = "sortAscending"

    var icon: String {
        switch self {
        case .name:       return "textformat"
        case .lastPlayed: return "clock"
        case .lastAdded:  return "calendar"
        case .playtime:   return "hourglass"
        case .timeToBeat: return "timer"
        case .systemName: return "cpu"
        case .systemAge:  return "clock.arrow.circlepath"
        }
    }

    /// Localization key for the human-readable label.
    var localizationKey: String {
        switch self {
        case .name:       return "app.sortByName"
        case .lastPlayed: return "app.lastPlayed"
        case .lastAdded:  return "app.lastAdded"
        case .playtime:   return "app.sortByPlaytime"
        case .timeToBeat: return "app.sortByTimeToBeat"
        case .systemName: return "app.sortBySystem"
        case .systemAge:  return "app.sortBySystemAge"
        }
    }

    /// Loads the persisted sort order and direction, migrating from the
    /// legacy two-boolean keys on first run. Old keys are left on disk
    /// (inert) for rollback safety.
    static func load() -> (order: LibrarySortOrder, ascending: Bool) {
        if let raw = AppSettings.getString(orderKey),
           let order = LibrarySortOrder(rawValue: raw) {
            let ascending = AppSettings.getBool(ascendingKey, defaultValue: false)
            return (order, ascending)
        }
        if AppSettings.getBool("sortByLastPlayed", defaultValue: false) {
            return (.lastPlayed, false)
        }
        if AppSettings.getBool("sortByLastAdded", defaultValue: false) {
            return (.lastAdded, false)
        }
        return (.name, false)
    }
}

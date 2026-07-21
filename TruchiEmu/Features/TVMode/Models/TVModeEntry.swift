import Foundation
import SwiftUI

/// A single entry selectable in row 1 of TV Mode. Wraps both smart collections
/// (`LibraryFilter` cases other than `.system`) and systems.
struct TVModeEntry: Identifiable, Hashable {
    let filter: LibraryFilter

    var id: String { filter.id }

    var displayName: String {
        switch filter {
        case .all: return LocalizationManager.shared.localized("app.allGames")
        case .favorites: return LocalizationManager.shared.localized("app.favorites")
        case .recent: return LocalizationManager.shared.localized("app.recent")
        case .lastAdded: return LocalizationManager.shared.localized("app.lastAdded")
        case .retroAchievements: return LocalizationManager.shared.localized("library.retroAchievements")
        case .hidden: return LocalizationManager.shared.localized("app.hidden")
        case .mameNonGames: return LocalizationManager.shared.localized("app.hiddenMAMEFiles")
        case .system(let sys): return sys.sidebarDisplayName
        case .category: return ""
        }
    }

    var sfSymbol: String? {
        switch filter {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .recent: return "clock.fill"
        case .lastAdded: return "plus.circle.fill"
        case .retroAchievements: return "trophy.fill"
        case .hidden: return "eye.slash.fill"
        case .mameNonGames: return "gearshape.2.fill"
        case .system: return nil
        case .category: return "folder.fill"
        }
    }

    var system: SystemInfo? {
        if case .system(let sys) = filter { return sys } else { return nil }
    }
}

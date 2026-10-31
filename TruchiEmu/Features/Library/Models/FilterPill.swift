import Foundation

// MARK: - Filter Pill

/// A pill in the library filter-chip bar. The bar mixes sort pills and
/// filter pills in one user-ordered list; this type is the identity used for
/// ordering, visibility and overflow.
enum FilterPill: Identifiable, Hashable {
    case sort(LibrarySortOrder)
    case filter(GameFilterOption)

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .sort(let order): return "sort:\(order.rawValue)"
        case .filter(let option): return "filter:\(option.rawValue)"
        }
    }

    init?(rawValue: String) {
        if rawValue.hasPrefix("sort:") {
            let raw = String(rawValue.dropFirst("sort:".count))
            guard let order = LibrarySortOrder(rawValue: raw) else { return nil }
            self = .sort(order)
        } else if rawValue.hasPrefix("filter:") {
            let raw = String(rawValue.dropFirst("filter:".count))
            guard let option = GameFilterOption(rawValue: raw) else { return nil }
            self = .filter(option)
        } else {
            return nil
        }
    }

    var icon: String {
        switch self {
        case .sort(let order): return order.icon
        case .filter(let option): return option.icon
        }
    }

    var label: String {
        switch self {
        case .sort(let order): return LocalizationManager.shared.localized(order.localizationKey)
        case .filter(let option): return option.label
        }
    }

    var sortOrder: LibrarySortOrder? {
        if case .sort(let order) = self { return order }
        return nil
    }

    var filterOption: GameFilterOption? {
        if case .filter(let option) = self { return option }
        return nil
    }

    /// Pills that can appear in the bar: the primary sort orders plus every
    /// filter option. `name` (implicit default) and `lastAdded` (always in the
    /// "Other" popover) are not bar pills.
    static let defaultOrder: [FilterPill] =
        LibrarySortOrder.primary.map(FilterPill.sort)
        + GameFilterOption.allCases.map(FilterPill.filter)
}

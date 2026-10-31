import Combine
import Foundation

// MARK: - Filter Pill Preferences

/// User-configurable ordering and visibility for the filter-chip bar pills.
/// Covers both sort pills and filter pills in one list. Mirrors
/// `GameToolbarPreferences`: @MainActor ObservableObject with comma-joined
/// raw-value persistence through `AppSettings`.
@MainActor
final class FilterPillPreferences: ObservableObject {
    static let shared = FilterPillPreferences()

    private static let orderKey = "library.filterPillOrder"
    private static let disabledKey = "library.filterPillDisabled"

    @Published private(set) var order: [FilterPill]
    @Published private(set) var disabled: Set<FilterPill>

    private init() {
        let storedOrder = (AppSettings.getString(Self.orderKey) ?? "")
            .split(separator: ",")
            .compactMap { FilterPill(rawValue: String($0)) }
        order = Self.normalizedOrder(storedOrder)

        let storedDisabled = (AppSettings.getString(Self.disabledKey) ?? "")
            .split(separator: ",")
            .compactMap { FilterPill(rawValue: String($0)) }
        disabled = Set(storedDisabled)
    }

    var enabled: [FilterPill] {
        order.filter { !disabled.contains($0) }
    }

    func isEnabled(_ pill: FilterPill) -> Bool {
        !disabled.contains(pill)
    }

    func setEnabled(_ pill: FilterPill, _ enabled: Bool) {
        if enabled {
            disabled.remove(pill)
        } else {
            disabled.insert(pill)
        }
        persistDisabled()
    }

    /// Moves the pill at `source` to `destination`. Used by the editor's
    /// in-place drag, where `destination` is the final index of the row.
    func move(from source: Int, to destination: Int) {
        guard order.indices.contains(source),
              order.indices.contains(destination),
              source != destination else { return }
        var newOrder = order
        let moved = newOrder.remove(at: source)
        newOrder.insert(moved, at: destination)
        order = newOrder
        persistOrder()
    }

    private func persistOrder() {
        let raw = order.map(\.rawValue).joined(separator: ",")
        AppSettings.setString(Self.orderKey, value: raw.isEmpty ? nil : raw)
    }

    private func persistDisabled() {
        let raw = disabled.map(\.rawValue).sorted().joined(separator: ",")
        AppSettings.setString(Self.disabledKey, value: raw.isEmpty ? nil : raw)
    }

    private static func normalizedOrder(_ stored: [FilterPill]) -> [FilterPill] {
        var result: [FilterPill] = []
        for value in stored where FilterPill.defaultOrder.contains(value) && !result.contains(value) {
            result.append(value)
        }
        for value in FilterPill.defaultOrder where !result.contains(value) {
            result.append(value)
        }
        return result
    }
}

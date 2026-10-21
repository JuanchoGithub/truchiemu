import Foundation
import Combine

@MainActor
final class GameToolbarPreferences: ObservableObject {
    static let shared = GameToolbarPreferences()

    private static let hiddenItemsKey = "gameToolbar.hiddenItems"
    private static let pinVisibleKey = "gameToolbar.pinVisible"
    private static let autoHideDelayKey = "gameToolbar.autoHideDelay"
    private static let groupOrderKey = "gameToolbar.groupOrder"
    private static let itemOrderKey = "gameToolbar.itemOrder"
    private static let defaultGroupOrder: [GameToolbarGroup] = [
        .window, .playback, .state, .time, .capture, .tools, .view
    ]
    private static let defaultItemOrder: [GameToolbarItemID] = [
        .stop, .pauseResume, .restart, .save, .load, .undoLoad, .record,
        .rewind, .slowMotion, .fastForward, .cheats, .training, .guide,
        .shader, .bezel, .fullscreen
    ]

    @Published private(set) var hiddenItems: Set<GameToolbarItemID>
    @Published private(set) var groupOrder: [GameToolbarGroup]
    @Published private(set) var itemOrder: [GameToolbarItemID]
    @Published var pinVisible: Bool {
        didSet { AppSettings.setBool(Self.pinVisibleKey, value: pinVisible) }
    }
    @Published var autoHideDelay: Double {
        didSet {
            let clamped = min(max(autoHideDelay, 1.0), 15.0)
            if clamped != autoHideDelay {
                autoHideDelay = clamped
            }
            AppSettings.setDouble(Self.autoHideDelayKey, value: clamped)
        }
    }

    var effectiveAutoHideDelay: TimeInterval {
        min(max(autoHideDelay, 1.0), 15.0)
    }

    private init() {
        let raw = AppSettings.getString(Self.hiddenItemsKey) ?? ""
        let ids = raw
            .split(separator: ",")
            .compactMap { GameToolbarItemID(rawValue: String($0)) }
        hiddenItems = Set(ids)

        let storedGroups = (AppSettings.getString(Self.groupOrderKey) ?? "")
            .split(separator: ",")
            .compactMap { GameToolbarGroup(rawValue: String($0)) }
        groupOrder = Self.normalizedOrder(storedGroups, defaults: Self.defaultGroupOrder)

        let storedItems = (AppSettings.getString(Self.itemOrderKey) ?? "")
            .split(separator: ",")
            .compactMap { GameToolbarItemID(rawValue: String($0)) }
        itemOrder = Self.normalizedOrder(storedItems, defaults: Self.defaultItemOrder)

        pinVisible = AppSettings.getBool(Self.pinVisibleKey, defaultValue: false)
        let storedDelay = AppSettings.getDouble(Self.autoHideDelayKey, defaultValue: 3.5)
        autoHideDelay = min(max(storedDelay > 0 ? storedDelay : 3.5, 1.0), 15.0)
    }

    private static func normalizedOrder<T: Hashable>(_ stored: [T], defaults: [T]) -> [T] {
        var result: [T] = []
        for value in stored where defaults.contains(value) && !result.contains(value) {
            result.append(value)
        }
        for value in defaults where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    func isEnabled(_ id: GameToolbarItemID) -> Bool {
        if id == .stop { return true }
        return !hiddenItems.contains(id)
    }

    func setEnabled(_ id: GameToolbarItemID, _ enabled: Bool) {
        guard id != .stop else { return }
        if enabled {
            hiddenItems.remove(id)
        } else {
            hiddenItems.insert(id)
        }
        let raw = hiddenItems.map(\.rawValue).sorted().joined(separator: ",")
        AppSettings.setString(Self.hiddenItemsKey, value: raw.isEmpty ? nil : raw)
    }

    func items(in group: GameToolbarGroup) -> [GameToolbarItem] {
        let rank = Dictionary(uniqueKeysWithValues: itemOrder.enumerated().map { ($0.element, $0.offset) })
        return GameToolbarModel.items
            .filter { $0.group == group }
            .sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
    }

    func moveGroup(_ group: GameToolbarGroup, to target: GameToolbarGroup) {
        guard group != target,
              let from = groupOrder.firstIndex(of: group),
              let targetIndex = groupOrder.firstIndex(of: target) else { return }
        var order = groupOrder
        let moved = order.remove(at: from)
        order.insert(moved, at: min(targetIndex, order.count))
        groupOrder = order
        persistGroupOrder()
    }

    func moveItem(_ item: GameToolbarItemID, to target: GameToolbarItemID) {
        guard item != target,
              let from = itemOrder.firstIndex(of: item),
              let targetIndex = itemOrder.firstIndex(of: target),
              let sourceItem = GameToolbarModel.items.first(where: { $0.id == item }),
              let targetItem = GameToolbarModel.items.first(where: { $0.id == target }),
              sourceItem.group == targetItem.group else { return }
        var order = itemOrder
        let moved = order.remove(at: from)
        order.insert(moved, at: min(targetIndex, order.count))
        itemOrder = order
        persistItemOrder()
    }

    private func persistGroupOrder() {
        let raw = groupOrder.map(\.rawValue).joined(separator: ",")
        AppSettings.setString(Self.groupOrderKey, value: raw.isEmpty ? nil : raw)
    }

    private func persistItemOrder() {
        let raw = itemOrder.map(\.rawValue).joined(separator: ",")
        AppSettings.setString(Self.itemOrderKey, value: raw.isEmpty ? nil : raw)
    }

    func resetToDefaults() {
        hiddenItems = []
        groupOrder = Self.defaultGroupOrder
        itemOrder = Self.defaultItemOrder
        pinVisible = false
        autoHideDelay = 3.5
        AppSettings.remove(Self.hiddenItemsKey)
        AppSettings.remove(Self.groupOrderKey)
        AppSettings.remove(Self.itemOrderKey)
        AppSettings.setBool(Self.pinVisibleKey, value: false)
        AppSettings.setDouble(Self.autoHideDelayKey, value: 3.5)
    }
}

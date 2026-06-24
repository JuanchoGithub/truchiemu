import SwiftUI
import Combine

struct GamepadContextMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let isSeparator: Bool
    let isDestructive: Bool
    let action: (() -> Void)?

    init(title: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSeparator = false
        self.isDestructive = isDestructive
        self.action = action
    }

    static var separator: GamepadContextMenuItem {
        GamepadContextMenuItem(title: "", isDestructive: false, action: nil)
    }

    init(title: String = "", isDestructive: Bool = false, action: (() -> Void)? = nil, isSeparator: Bool = true) {
        self.title = title
        self.isSeparator = isSeparator
        self.isDestructive = isDestructive
        self.action = action
    }
}

@MainActor
final class GamepadContextMenuState: ObservableObject {
    static let shared = GamepadContextMenuState()

    @Published var isVisible: Bool = false
    @Published var items: [GamepadContextMenuItem] = []
    @Published var focusIndex: Int = 0

    private init() {}

    var actionableItems: [GamepadContextMenuItem] {
        items.enumerated().compactMap { idx, item in
            item.isSeparator ? nil : (idx, item)
        }.map { $0.1 }
    }

    var actionableIndices: [Int] {
        items.indices.filter { !items[$0].isSeparator }
    }

    func show(_ items: [GamepadContextMenuItem]) {
        self.items = items
        self.focusIndex = actionableIndices.first ?? 0
        self.isVisible = true
    }

    func dismiss() {
        isVisible = false
        items = []
        focusIndex = 0
    }

    func navigateUp() {
        guard isVisible else { return }
        let indices = actionableIndices
        guard let currentPos = indices.firstIndex(of: focusIndex), currentPos > 0 else { return }
        focusIndex = indices[currentPos - 1]
    }

    func navigateDown() {
        guard isVisible else { return }
        let indices = actionableIndices
        guard let currentPos = indices.firstIndex(of: focusIndex),
              currentPos < indices.count - 1 else { return }
        focusIndex = indices[currentPos + 1]
    }

    func selectFocused() {
        guard isVisible, focusIndex < items.count else { return }
        let item = items[focusIndex]
        dismiss()
        item.action?()
    }
}

@MainActor
final class GamepadNavCoordinator: ObservableObject {
    static let shared = GamepadNavCoordinator()

    private let navManager = GamepadNavigationManager.shared

    var sidebarSelectableFilters: [LibraryFilter] = []
    var categoriesExpanded: Bool = true
    var systemsExpanded: Bool = true

    private init() {
        _ = GamepadLibraryContext.shared
    }

    func updateSidebarItems(_ filters: [LibraryFilter]) {
        sidebarSelectableFilters = filters
        navManager.sidebarItemCount = visibleSidebarFilters.count
    }

    func syncSidebarIndex(to filter: LibraryFilter) {
        if let idx = visibleSidebarFilters.firstIndex(where: { $0.id == filter.id }) {
            navManager.sidebarIndex = idx
        }
    }

    var visibleSidebarFilters: [LibraryFilter] {
        sidebarSelectableFilters.filter { filter in
            switch filter {
            case .category: return categoriesExpanded
            case .system: return systemsExpanded
            default: return true
            }
        }
    }

    private func navigateUp() {
        switch navManager.activeZone {
        case .sidebar:
            if navManager.sidebarIndex > 0 {
                navManager.sidebarIndex -= 1
                applySidebarSelection()
            } else {
                navManager.focusZone(.gameToolbar)
            }
        case .content:
            if navManager.contentIndex < navManager.columnCount && navManager.sidebarItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .sidebar
            } else {
                NotificationCenter.default.post(name: .gamepadNavigateUp, object: nil)
            }
        case .gameToolbar:
            break
        }
    }

    private func navigateDown() {
        switch navManager.activeZone {
        case .sidebar:
            if navManager.sidebarIndex < visibleSidebarFilters.count - 1 {
                navManager.sidebarIndex += 1
                applySidebarSelection()
            } else {
                NotificationCenter.default.post(name: .gamepadShowNotifications, object: nil)
            }
        case .content:
            let lastIndex = navManager.contentItemCount - 1
            let currentRow = navManager.contentIndex / navManager.columnCount
            let lastRow = lastIndex / navManager.columnCount
            if currentRow >= lastRow && navManager.sidebarItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .sidebar
            } else {
                NotificationCenter.default.post(name: .gamepadNavigateDown, object: nil)
            }
        case .gameToolbar:
            if navManager.sidebarItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .sidebar
            }
        }
    }

    private func navigateLeft() {
        switch navManager.activeZone {
        case .sidebar:
            break
        case .content:
            if navManager.contentIndex % navManager.columnCount == 0 && navManager.sidebarItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .sidebar
            } else {
                NotificationCenter.default.post(name: .gamepadNavigateLeft, object: nil)
            }
        case .gameToolbar:
            if navManager.gameToolbarIndex > 0 {
                navManager.gameToolbarIndex -= 1
            }
            NotificationCenter.default.post(name: .gamepadToolbarNavigateLeft, object: nil)
        }
    }

    private func navigateRight() {
        switch navManager.activeZone {
        case .sidebar:
            if navManager.contentItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .content
            }
        case .content:
            NotificationCenter.default.post(name: .gamepadNavigateRight, object: nil)
        case .gameToolbar:
            if navManager.gameToolbarIndex < navManager.gameToolbarItemCount - 1 {
                navManager.gameToolbarIndex += 1
            }
            NotificationCenter.default.post(name: .gamepadToolbarNavigateRight, object: nil)
        }
    }

    private func performSelect() {
        switch navManager.activeZone {
        case .sidebar:
            applySidebarSelection()
        case .content:
            NotificationCenter.default.post(name: .gamepadLaunchGame, object: nil)
        case .gameToolbar:
            NotificationCenter.default.post(name: .gamepadToolbarSelect, object: nil)
        }
    }

    private func performCancel() {
        switch navManager.activeZone {
        case .sidebar:
            if let keyWindow = NSApp.keyWindow, keyWindow != NSApp.mainWindow {
                keyWindow.close()
            }
        case .content:
            navManager.focusPrevZone()
        case .gameToolbar:
            NotificationCenter.default.post(name: .gamepadToolbarCancel, object: nil)
        }
    }

    private func performContextMenu() {
        NotificationCenter.default.post(name: .gamepadShowContextMenu, object: nil)
    }

    private func toggleViewMode() {
        NotificationCenter.default.post(name: .gamepadToggleViewMode, object: nil)
    }

    private func focusSearch() {
        NotificationCenter.default.post(name: .gamepadFocusSearch, object: nil)
    }

    private func cycleSortOrder() {
        NotificationCenter.default.post(name: .gamepadCycleSortOrder, object: nil)
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .openAppSettings, object: nil)
    }

    private func launchSelectedGame() {
        NotificationCenter.default.post(name: .gamepadLaunchGame, object: nil)
    }

    private func scrollUp() {
        guard navManager.activeZone == .content else { return }
        navManager.scrollAnchorIndex = max(0, navManager.scrollAnchorIndex - navManager.columnCount)
    }

    private func scrollDown() {
        guard navManager.activeZone == .content else { return }
        navManager.scrollAnchorIndex = min(navManager.contentItemCount - 1, navManager.scrollAnchorIndex + navManager.columnCount)
    }

    private func pageUp() {
        guard navManager.activeZone == .content else { return }
        let page = navManager.columnCount * 4
        navManager.scrollAnchorIndex = max(0, navManager.scrollAnchorIndex - page)
    }

    private func pageDown() {
        guard navManager.activeZone == .content else { return }
        let page = navManager.columnCount * 4
        navManager.scrollAnchorIndex = min(navManager.contentItemCount - 1, navManager.scrollAnchorIndex + page)
    }

    private func showGameToolbar() {
        NotificationCenter.default.post(name: .gamepadShowGameToolbar, object: nil)
    }

    private func applySidebarSelection() {
        let visible = visibleSidebarFilters
        guard navManager.sidebarIndex < visible.count else { return }
        let filter = visible[navManager.sidebarIndex]
        NotificationCenter.default.post(name: .gamepadSelectFilter, object: filter)
    }

    func handleAction(_ action: GamepadNavAction) {
        let ctx = GamepadContextMenuState.shared
        if ctx.isVisible {
            switch action {
            case .navigateUp: ctx.navigateUp()
            case .navigateDown: ctx.navigateDown()
            case .select: ctx.selectFocused()
            case .cancel: ctx.dismiss()
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: navigateUp()
        case .navigateDown: navigateDown()
        case .navigateLeft: navigateLeft()
        case .navigateRight: navigateRight()
        case .select: performSelect()
        case .cancel: performCancel()
        case .contextMenu: performContextMenu()
        case .toggleViewMode: toggleViewMode()
        case .focusSearch: focusSearch()
        case .cycleSortOrder: cycleSortOrder()
        case .openSettings: openSettings()
        case .launchGame: launchSelectedGame()
        case .scrollUp: scrollUp()
        case .scrollDown: scrollDown()
        case .pageUp: pageUp()
        case .pageDown: pageDown()
        case .showGameToolbar: showGameToolbar()
        case .closeWindow:
            if let keyWindow = NSApp.keyWindow, keyWindow != NSApp.mainWindow {
                keyWindow.close()
            }
        case .focusPrevZone: navManager.focusPrevZone()
        case .focusNextZone: navManager.focusNextZone()
        case .focusSidebarZone: navManager.focusZone(.sidebar)
        case .focusContentZone:
            if navManager.contentItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .content
                navManager.contentIndex = min(navManager.savedContentIndex, max(0, navManager.contentItemCount - 1))
            }
        case .focusToolbarZone:
            if navManager.gameToolbarItemCount > 0 {
                navManager.saveCurrentZoneIndex()
                navManager.activeZone = .gameToolbar
                navManager.gameToolbarIndex = min(navManager.savedGameToolbarIndex, max(0, navManager.gameToolbarItemCount - 1))
            } else {
                showGameToolbar()
            }
        }
    }
}

extension Notification.Name {
    static let gamepadShowContextMenu = Notification.Name("gamepadShowContextMenu")
    static let gamepadShowNotifications = Notification.Name("gamepadShowNotifications")
    static let gamepadFocusSearch = Notification.Name("gamepadFocusSearch")
    static let gamepadLaunchGame = Notification.Name("gamepadLaunchGame")
    static let gamepadScrollUp = Notification.Name("gamepadScrollUp")
    static let gamepadScrollDown = Notification.Name("gamepadScrollDown")
    static let gamepadSelectFilter = Notification.Name("gamepadSelectFilter")
    static let gamepadNavigateUp = Notification.Name("gamepadNavigateUp")
    static let gamepadNavigateDown = Notification.Name("gamepadNavigateDown")
    static let gamepadNavigateLeft = Notification.Name("gamepadNavigateLeft")
    static let gamepadNavigateRight = Notification.Name("gamepadNavigateRight")
    static let gamepadToggleViewMode = Notification.Name("gamepadToggleViewMode")
    static let gamepadCycleSortOrder = Notification.Name("gamepadCycleSortOrder")
    static let gamepadToolbarSelect = Notification.Name("gamepadToolbarSelect")
    static let gamepadShowGameToolbar = Notification.Name("gamepadShowGameToolbar")
    static let gamepadToolbarNavigateLeft = Notification.Name("gamepadToolbarNavigateLeft")
    static let gamepadToolbarNavigateRight = Notification.Name("gamepadToolbarNavigateRight")
    static let gamepadToolbarCancel = Notification.Name("gamepadToolbarCancel")
    static let gamepadSidebarExpansionChanged = Notification.Name("gamepadSidebarExpansionChanged")
    static let gamepadSidebarContextMenu = Notification.Name("gamepadSidebarContextMenu")
}

struct GamepadContextMenuOverlay: View {
    @ObservedObject private var state = GamepadContextMenuState.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        if state.isVisible {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { state.dismiss() }

                VStack(spacing: 2) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        if item.isSeparator {
                            Divider()
                                .padding(.horizontal, 8)
                        } else {
                            let isFocused = index == state.focusIndex
                            Button {
                                state.focusIndex = index
                                state.selectFocused()
                            } label: {
                                HStack {
                                    Text(item.title)
                                        .foregroundColor(item.isDestructive ? .red : AppColors.textPrimary(colorScheme))
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isFocused ? AppColors.brandAccent.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isFocused ? AppColors.brandAccent : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 8)
                .frame(minWidth: 240, maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
                        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeOut(duration: 0.15), value: state.isVisible)
        }
    }
}

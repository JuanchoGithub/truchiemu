import SwiftUI
import CoreGraphics

@MainActor
class GamepadNavContext: ObservableObject {
    var isActive: Bool = true
    var priority: Int { 0 }
    weak var ownedWindow: NSWindow?

    func handleAction(_ action: GamepadNavAction) {}
}

@MainActor
final class GamepadNavContextStack {
    static let shared = GamepadNavContextStack()

    private var contexts: [GamepadNavContext] = []

    private init() {}

    func push(_ context: GamepadNavContext) {
        if !contexts.contains(where: { $0 === context }) {
            contexts.append(context)
        }
        contexts.sort { $0.priority > $1.priority }
    }

    func remove(_ context: GamepadNavContext) {
        contexts.removeAll { $0 === context }
    }

    func topActive() -> GamepadNavContext? {
        let keyWindow = NSApp.keyWindow
        let activeContexts = contexts.filter { $0.isActive }
        if let key = keyWindow {
            if let match = activeContexts.first(where: { $0.ownedWindow === key }) {
                return match
            }
        }
        return activeContexts.first { $0.ownedWindow == nil } ?? activeContexts.first
    }
}

@MainActor
final class GamepadLibraryContext: GamepadNavContext {
    static let shared = GamepadLibraryContext()

    override var priority: Int { 0 }

    private override init() {
        super.init()
        GamepadNavContextStack.shared.push(self)
    }

    override func handleAction(_ action: GamepadNavAction) {
        GamepadNavCoordinator.shared.handleAction(action)
    }
}

@MainActor
final class GamepadSheetContext: GamepadNavContext {
    override var priority: Int { 100 }

    var itemCount: Int = 0
    @Published var focusIndex: Int = 0
    var columnCount: Int = 1
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var isDismissable: Bool = true

    init(itemCount: Int = 0, columnCount: Int = 1, onSelect: ((Int) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.itemCount = itemCount
        self.columnCount = columnCount
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        super.init()
    }

    override func handleAction(_ action: GamepadNavAction) {
        switch action {
        case .navigateUp:
            if focusIndex >= columnCount {
                focusIndex -= columnCount
            }
        case .navigateDown:
            let newIndex = focusIndex + columnCount
            if newIndex < itemCount { focusIndex = newIndex }
        case .navigateLeft:
            if focusIndex > 0 { focusIndex -= 1 }
        case .navigateRight:
            if focusIndex < itemCount - 1 { focusIndex += 1 }
        case .select:
            if itemCount > 0 { onSelect?(focusIndex) }
        case .cancel:
            if isDismissable { onDismiss?() }
        case .focusSearch:
            if isDismissable { onDismiss?() }
        case .scrollUp:
            let step = columnCount * 3
            if focusIndex >= step { focusIndex -= step } else { focusIndex = 0 }
        case .scrollDown:
            let step = columnCount * 3
            let newIndex = focusIndex + step
            if newIndex < itemCount { focusIndex = newIndex } else { focusIndex = max(0, itemCount - 1) }
        case .pageUp:
            let page = columnCount * 4
            if focusIndex >= page { focusIndex -= page } else { focusIndex = 0 }
        case .pageDown:
            let page = columnCount * 4
            let newIndex = focusIndex + page
            if newIndex < itemCount { focusIndex = newIndex } else { focusIndex = max(0, itemCount - 1) }
        default:
            break
        }
    }
}

@MainActor
final class GamepadGameToolbarContext: GamepadNavContext {
    override var priority: Int { 50 }

    var itemCount: Int = 0
    @Published var focusIndex: Int = 0
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var onNavigate: (() -> Void)?

    init(itemCount: Int = 0) {
        self.itemCount = itemCount
        super.init()
    }

    override func handleAction(_ action: GamepadNavAction) {
        switch action {
        case .navigateLeft:
            if focusIndex > 0 { focusIndex -= 1; onNavigate?() }
        case .navigateRight:
            if focusIndex < itemCount - 1 { focusIndex += 1; onNavigate?() }
        case .select:
            onSelect?(focusIndex)
        case .cancel:
            onDismiss?()
        default:
            break
        }
    }
}

@MainActor
final class GamepadGameRunningContext: GamepadNavContext {
    override var priority: Int { 10 }

    var onShowToolbar: (() -> Void)?
    var onCloseWindow: (() -> Void)?

    init(onShowToolbar: (() -> Void)? = nil, onCloseWindow: (() -> Void)? = nil) {
        self.onShowToolbar = onShowToolbar
        self.onCloseWindow = onCloseWindow
        super.init()
    }

    override func handleAction(_ action: GamepadNavAction) {
        if action == .showGameToolbar {
            onShowToolbar?()
        }
        if action == .closeWindow {
            onCloseWindow?()
            NSApp.keyWindow?.close()
        }
    }
}

@MainActor
final class GamepadTwoZoneContext: GamepadNavContext {
    override var priority: Int { 20 }

    enum Zone { case sidebar, content }

    @Published var activeZone: Zone = .sidebar
    @Published var sidebarIndex: Int = 0
    @Published var contentIndex: Int = 0
    var sidebarItemCount: Int = 0
    var contentItemCount: Int = 1
    var onSelectSidebar: ((Int) -> Void)?
    var onSelectContent: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    override func handleAction(_ action: GamepadNavAction) {
        switch action {
        case .navigateUp:
            switch activeZone {
            case .sidebar:
                if sidebarIndex > 0 { sidebarIndex -= 1; onSelectSidebar?(sidebarIndex) }
            case .content:
                moveFocus(forward: false)
            }
        case .navigateDown:
            switch activeZone {
            case .sidebar:
                if sidebarIndex < sidebarItemCount - 1 { sidebarIndex += 1; onSelectSidebar?(sidebarIndex) }
            case .content:
                moveFocus(forward: true)
            }
        case .navigateLeft:
            switch activeZone {
            case .sidebar: break
            case .content: activeZone = .sidebar
            }
        case .navigateRight:
            switch activeZone {
            case .sidebar: if contentItemCount > 0 { activeZone = .content }
            case .content: break
            }
        case .select:
            switch activeZone {
            case .sidebar: onSelectSidebar?(sidebarIndex)
            case .content: onSelectContent?(contentIndex)
            }
        case .cancel:
            if activeZone == .content {
                activeZone = .sidebar
            } else {
                onDismiss?()
            }
        case .scrollUp:
            let step = 3
            switch activeZone {
            case .sidebar:
                if sidebarIndex >= step { sidebarIndex -= step; onSelectSidebar?(sidebarIndex) }
            case .content:
                moveFocus(forward: false, step: step)
            }
        case .scrollDown:
            let step = 3
            switch activeZone {
            case .sidebar:
                sidebarIndex = min(sidebarIndex + step, max(0, sidebarItemCount - 1)); onSelectSidebar?(sidebarIndex)
            case .content:
                moveFocus(forward: true, step: step)
            }
        case .focusSidebarZone:
            activeZone = .sidebar
        case .focusContentZone:
            if contentItemCount > 0 { activeZone = .content }
        default:
            break
        }
    }

    private func moveFocus(forward: Bool, step: Int = 1) {
        guard let keyWindow = NSApp.keyWindow else { return }
        let key: UInt16 = 48 // Tab virtual key code
        for _ in 0..<step {
            keyWindow.makeKeyAndOrderFront(nil)
            let source = CGEventSource(stateID: .hidSystemState)
            if forward {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                    keyDown.post(tap: CGEventTapLocation.cghidEventTap)
                    keyUp.post(tap: CGEventTapLocation.cghidEventTap)
                }
            } else {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                    keyDown.flags = CGEventFlags.maskShift
                    keyUp.flags = CGEventFlags.maskShift
                    keyDown.post(tap: CGEventTapLocation.cghidEventTap)
                    keyUp.post(tap: CGEventTapLocation.cghidEventTap)
                }
            }
        }
    }
}

struct GamepadNavContextPushModifier: ViewModifier {
    @ObservedObject var context: GamepadNavContext

    func body(content: Content) -> some View {
        content
            .onAppear { GamepadNavContextStack.shared.push(context) }
            .onDisappear { GamepadNavContextStack.shared.remove(context) }
    }
}

struct GamepadSheetNavModifier: ViewModifier {
    @StateObject private var context: GamepadSheetContext
    @Binding var isPresented: Bool
    let itemCount: Int
    let columnCount: Int
    let onSelect: ((Int) -> Void)?

    init(isPresented: Binding<Bool>, itemCount: Int, columnCount: Int = 1, onSelect: ((Int) -> Void)? = nil) {
        _isPresented = isPresented
        self.itemCount = itemCount
        self.columnCount = columnCount
        self.onSelect = onSelect
        _context = StateObject(wrappedValue: GamepadSheetContext(
            itemCount: itemCount,
            columnCount: columnCount,
            onSelect: onSelect
        ))
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                context.itemCount = itemCount
                context.columnCount = columnCount
                context.onDismiss = { isPresented = false }
                if let onSelect { context.onSelect = onSelect }
                GamepadNavContextStack.shared.push(context)
            }
            .onDisappear {
                GamepadNavContextStack.shared.remove(context)
            }
    }
}

struct GamepadDismissableModifier: ViewModifier {
    @StateObject private var context = GamepadSheetContext(itemCount: 0)
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                context.onDismiss = onDismiss
                GamepadNavContextStack.shared.push(context)
            }
            .onDisappear {
                GamepadNavContextStack.shared.remove(context)
            }
    }
}

extension View {
    func gamepadNavContext(_ context: GamepadNavContext) -> some View {
        modifier(GamepadNavContextPushModifier(context: context))
    }

    func gamepadSheetNav(isPresented: Binding<Bool>, itemCount: Int, columnCount: Int = 1, onSelect: ((Int) -> Void)? = nil) -> some View {
        modifier(GamepadSheetNavModifier(isPresented: isPresented, itemCount: itemCount, columnCount: columnCount, onSelect: onSelect))
    }

    func gamepadDismissable(onDismiss: @escaping () -> Void) -> some View {
        modifier(GamepadDismissableModifier(onDismiss: onDismiss))
    }
}

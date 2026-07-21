import SwiftUI
import Combine
import AppKit

@MainActor
final class TVModeNavContext: GamepadNavContext {
    override var priority: Int { 60 }

    var handler: ((GamepadNavAction) -> Void)?

    override func handleAction(_ action: GamepadNavAction) {
        handler?(action)
    }
}

/// Maps keyboard arrows + Enter + Esc to GamepadNavAction so TV mode can be
/// operated from the keyboard while developing.
struct TVModeKeyMonitor: ViewModifier {
    let handler: (GamepadNavAction) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let action = map(event)
                    if let action { handler(action); return nil }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            }
    }

    private func map(_ event: NSEvent) -> GamepadNavAction? {
        switch event.keyCode {
        case 123: return .navigateLeft        // left arrow
        case 124: return .navigateRight       // right arrow
        case 125: return .navigateDown       // down arrow
        case 126: return .navigateUp         // up arrow
        case 36: return .select              // Return
        case 53: return .cancel              // Esc
        case 122: return .focusPrevZone      // F1 (L1, 5)
        case 120: return .focusNextZone      // F2 (R1, 5)
        case 99: return .pageUp              // F3 (L2, 10)
        case 98: return .pageDown            // F4 (R2, 10)
        case 48: return .openSettings         // Tab = SELECT (cycle theme)
        default: return nil
        }
    }
}

struct TVModeView: View {
    @EnvironmentObject private var library: ROMLibrary
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @StateObject private var viewModel: TVModeViewModel
    @StateObject private var navContext: TVModeNavContext
    @State private var showTVSettingsOverlay: Bool = false
    @State private var enteredFullscreen: Bool = false

    init(library: ROMLibrary, systemDatabase: SystemDatabaseWrapper) {
        _viewModel = StateObject(wrappedValue: TVModeViewModel(library: library, systemDatabase: systemDatabase))
        _navContext = StateObject(wrappedValue: TVModeNavContext())
    }

    var body: some View {
        ZStack {
            background
            contentLayer
            topBar
            bottomHint
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            navContext.handler = { [self] action in handle(action: action) }
            GamepadNavContextStack.shared.push(navContext)
            enterFullscreen()
        }
        .onDisappear {
            GamepadNavContextStack.shared.remove(navContext)
            // Fullscreen exit is handled by `ContentView` after it's observed
            // `tvModeSettings.isActive` flip false — that timing is after
            // SwiftUI has mounted `mainInterface`, so the unified toolbar
            // renders before the fullscreen→windowed transition starts.
            enteredFullscreen = false
        }
        .onChange(of: systemDatabase.systems) { _, _ in
            viewModel.handleExternalSystemsChange()
        }
        // Live re-load if the user changes TV mode settings from elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: .tvModeSettingsChanged)) { _ in
            viewModel.reloadSettings()
        }
        .modifier(TVModeKeyMonitor { action in handle(action: action) })
    }

    @ViewBuilder
    private var background: some View {
        if viewModel.theme == .bold {
            ZStack {
                AppColors.windowBackground(colorScheme, tinted: true)
                RadialGradient(colors: [AppColors.accentForScheme(colorScheme).opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 600).ignoresSafeArea()
                RadialGradient(colors: [AppColors.accentForScheme(colorScheme).opacity(0.18), .clear], center: .bottom, startRadius: 0, endRadius: 700).ignoresSafeArea()
            }
        } else {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.08)
                RadialGradient(colors: [Color.white.opacity(0.04), .clear], center: .center, startRadius: 0, endRadius: 500).ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        VStack {
            row1
            row2
        }
        .blur(radius: viewModel.page == .detail ? 18 : 0)
        .opacity(viewModel.page == .detail ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.25), value: viewModel.page)

        if viewModel.page == .detail, let rom = viewModel.downloadedDetailROM {
            TVModeGameDetailView(rom: rom, theme: viewModel.theme, focused: true)
                .environmentObject(library)
                .id(rom.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    @ViewBuilder
    private var row1: some View {
        CurvedRowLayout(
            items: viewModel.row1Entries,
            centerIndex: Binding(
                get: { viewModel.selectedEntryIndex },
                set: { viewModel.selectedEntryIndex = $0 }
            ),
            itemWidth: 200,
            itemHeight: 200,
            spacing: 22,
            maxSag: 28,
            visibleEachSide: 5
        ) { entry, isCenter in
            let count = viewModel.count(for: entry.filter)
            TVModeEntryTile(
                entry: entry,
                count: count,
                isFocused: viewModel.page == .row1 && isCenter,
                theme: viewModel.theme
            )
        }
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private var row2: some View {
        CurvedRowLayout(
            items: viewModel.games,
            centerIndex: Binding(
                get: { viewModel.selectedGameIndex },
                set: { viewModel.selectedGameIndex = $0 }
            ),
            itemWidth: 210,
            itemHeight: 280,
            spacing: 14,
            maxSag: 28,
            visibleEachSide: 4
        ) { rom, isCenter in
            TVModeGameTile(
                rom: rom,
                isFocused: viewModel.page != .row1 && isCenter,
                theme: viewModel.theme
            )
        }
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private var topBar: some View {
        VStack {
            HStack {
                Text(loc.localized("tvMode.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme) : .white)
                Spacer()
                themeToggle
                Button {
                    showTVSettingsOverlay = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            Spacer()
        }
        .sheet(isPresented: $showTVSettingsOverlay) {
            TVModeSettingsView()
                .environmentObject(loc)
        }
    }

    @ViewBuilder
    private var themeToggle: some View {
        HStack(spacing: 6) {
            ForEach(TVModeSettings.Theme.allCases) { t in
                Button {
                    TVModeSettings.setTheme(t)
                    NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                } label: {
                    Text(loc.localized("tvMode.theme.\(t.rawValue)"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(
                            Capsule().fill(viewModel.theme == t
                                ? (viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme).opacity(0.25) : Color.white.opacity(0.12))
                                : Color.clear)
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var bottomHint: some View {
        VStack {
            Spacer()
            HStack(spacing: 24) {
                hintChip(loc.localized("tvMode.page.systems"), active: viewModel.page == .row1)
                hintChip(loc.localized("tvMode.page.games"), active: viewModel.page == .row2)
                if viewModel.page == .detail {
                    hintChip(loc.localized("tvMode.page.detail"), active: true)
                }
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func hintChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(active && viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme).opacity(0.22) : Color.white.opacity(active ? 0.10 : 0.04)))
            .overlay(Capsule().strokeBorder(active && viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white.opacity(active ? 0.3 : 0.1), lineWidth: 1))
            .foregroundStyle(.primary)
    }
}

// MARK: - Action handling

extension TVModeView {
    fileprivate func handle(action: GamepadNavAction) {
        switch action {
        case .navigateLeft:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(-1)
            case .row2: viewModel.selectGameByOffset(-1)
            case .detail: viewModel.shiftDetailGame(by: -1)
            }
        case .navigateRight:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(1)
            case .row2: viewModel.selectGameByOffset(1)
            case .detail: viewModel.shiftDetailGame(by: 1)
            }
        case .navigateUp:
            switch viewModel.page {
            case .row2: viewModel.exitRow2()
            case .detail: viewModel.exitDetail()
            case .row1: break
            }
        case .navigateDown:
            switch viewModel.page {
            case .row1: viewModel.moveDownFromRow1()
            case .row2: viewModel.enterDetail()
            case .detail: break
            }
        // L1 / R1 — move 5 at a time
        case .focusPrevZone:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(-5)
            case .row2: viewModel.selectGameByOffset(-5)
            case .detail: viewModel.shiftDetailGame(by: -5)
            }
        case .focusNextZone:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(5)
            case .row2: viewModel.selectGameByOffset(5)
            case .detail: viewModel.shiftDetailGame(by: 5)
            }
        // L2 / R2 — move 10 at a time
        case .pageUp:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(-10)
            case .row2: viewModel.selectGameByOffset(-10)
            case .detail: viewModel.shiftDetailGame(by: -10)
            }
        case .pageDown:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(10)
            case .row2: viewModel.selectGameByOffset(10)
            case .detail: viewModel.shiftDetailGame(by: 10)
            }
        case .scrollUp:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(-10)
            case .row2: viewModel.selectGameByOffset(-10)
            case .detail: viewModel.shiftDetailGame(by: -10)
            }
        case .scrollDown:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(10)
            case .row2: viewModel.selectGameByOffset(10)
            case .detail: viewModel.shiftDetailGame(by: 10)
            }
        case .select:
            switch viewModel.page {
            case .row1: viewModel.moveDownFromRow1()
            case .row2: viewModel.enterDetail()
            case .detail: Task { await viewModel.launchSelected() }
            }
        case .launchGame:
            switch viewModel.page {
            case .row1: viewModel.moveDownFromRow1()
            case .row2: Task { await viewModel.launchSelected() }
            case .detail: Task { await viewModel.launchSelected() }
            }
        case .cancel:
            switch viewModel.page {
            case .row2: viewModel.exitRow2()
            case .detail: viewModel.exitDetail()
            case .row1: NotificationCenter.default.post(name: .tvModeExited, object: nil)
            }
        case .contextMenu:
            showTVSettingsOverlay = true
        case .toggleViewMode, .focusSearch:
            cycleTheme()
        case .openSettings:
            // SELECT button cycles the bold/muted theme instead of opening settings.
            cycleTheme()
        case .focusSidebarZone:
            viewModel.page = .row1
        case .focusContentZone:
            if !viewModel.games.isEmpty { viewModel.page = .row2 }
        default:
            break
        }
    }

    fileprivate func cycleTheme() {
        let current = TVModeSettings.theme
        let next: TVModeSettings.Theme = current == .bold ? .muted : .bold
        TVModeSettings.setTheme(next)
        NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
    }

    fileprivate func enterFullscreen() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) && !$0.styleMask.contains(.fullScreen) }),
              window.contentViewController != nil || window.contentView != nil else { return }
        window.toggleFullScreen(nil)
        enteredFullscreen = true
    }
}

extension Notification.Name {
    static let tvModeSettingsChanged = Notification.Name("tvModeSettingsChanged")
    static let tvModeExited = Notification.Name("tvModeExited")
    static let tvModeEntered = Notification.Name("tvModeEntered")
}

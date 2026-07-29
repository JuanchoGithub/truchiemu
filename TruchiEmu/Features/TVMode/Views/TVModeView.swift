import SwiftUI
import Combine
import AppKit

@MainActor
final class TVModeNavContext: GamepadNavContext {
    override var priority: Int { 60 }

    var handler: ((GamepadNavAction) -> Void)?

    /// Suspended while a game is running so launch actions (e.g. an Enter
    /// keypass during gameplay) aren't routed back into TV-mode navigation.
    /// `GamepadNavContextStack.topActive()` skips contexts where
    /// `isActive == false`.
    func suspendForGameplay() {
        isActive = false
    }

    func resumeFromGameplay() {
        isActive = true
    }

    override func handleAction(_ action: GamepadNavAction) {
        guard isActive else { return }
        handler?(action)
    }
}

/// Maps keyboard arrows + Enter + Esc to GamepadNavAction so TV mode can be
/// operated from the keyboard while developing.
///
/// The local monitor quietly forwards all `keyDown` events. While a game
/// window is running we tear the monitor down so TV-mode doesn't swallow
/// gamepad/keyboard input meant for the game (e.g. Enter as Start, Esc as
/// menu pause, arrows for navigation). When the game window closes, the
/// monitor resumes so TV-mode is once again keyboard-operable.
/// Maps keyboard arrows + Enter + Esc to GamepadNavAction so TV mode can be
/// operated from the keyboard while developing.
///
/// The local monitor quietly forwards all `keyDown` events. While a game
/// window is running we tear the monitor down so TV-mode doesn't swallow
/// gamepad/keyboard input meant for the game (e.g. Enter as Start, Esc as
/// menu pause, arrows for navigation). When the game window closes, the
/// monitor resumes so TV-mode is once again keyboard-operable.
///
/// Routed through `GamepadNavContextStack.shared.topActive()` so an
/// overlay with higher priority (e.g. `TVModeCoreDownloadSheetContext`)
/// intercepts the keystrokes instead of the underlying TV-mode surface.
struct TVModeKeyMonitor: ViewModifier {
    @ObservedObject private var games = RunningGamesTracker.shared
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { installIfNeeded() }
            .onDisappear { uninstall() }
            .onChange(of: games.runningGames.isEmpty) { _, noGameRunning in
                if noGameRunning { installIfNeeded() } else { uninstall() }
            }
    }

    private func installIfNeeded() {
        guard monitor == nil else { return }
        // Don't attach the monitor while a game is already running.
        guard RunningGamesTracker.shared.runningGames.isEmpty else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let action = map(event)
            if let action {
                GamepadNavContextStack.shared.topActive()?.handleAction(action)
                return nil
            }
            return event
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
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
    @EnvironmentObject private var coreManager: CoreManager
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var runningGames = RunningGamesTracker.shared

    @StateObject private var viewModel: TVModeViewModel
    @StateObject private var navContext: TVModeNavContext
    @ObservedObject private var tvModeSettings = TVModeSettingsManager.shared
    @ObservedObject private var screenCatalog = ScreenCatalog.shared
    @State private var showTVSettingsOverlay: Bool = false

    /// Refreshed on appear / screen change so the scale tracks the current
    /// display. Held in `@State` so children read a stable value via
    /// `\.tvModeScale` and re-render when it changes.
    @State private var scale: CGFloat = TVModeMetrics.scale

    init(library: ROMLibrary, systemDatabase: SystemDatabaseWrapper, initialEntryID: String? = nil) {
        _viewModel = StateObject(wrappedValue: TVModeViewModel(
            library: library,
            systemDatabase: systemDatabase,
            initialEntryID: initialEntryID
        ))
        _navContext = StateObject(wrappedValue: TVModeNavContext())
    }

    var body: some View {
        ZStack {
            contentLayer
            topBar
            bottomHint
            if let hudLabel = viewModel.sortHudLabel {
                sortHUD(label: hudLabel)
                    .transition(.opacity)
                    .zIndex(200)
            }
            if let pending = coreManager.pendingDownload {
                TVModeCoreDownloadOverlay(
                    pending: pending,
                    coreManager: coreManager,
                    library: library,
                    loc: loc,
                    colorScheme: colorScheme,
                    onDismiss: { coreManager.pendingDownload = nil }
                )
                .transition(.opacity)
                .zIndex(100)
            }
            if let picker = tvModeSettings.screenPickerRequest {
                TVModeScreenPickerView(
                    screens: picker.screens,
                    initialFocusIndex: picker.initialFocusIndex,
                    onSelect: { descriptor in
                        tvModeSettings.resolveScreenPicker(selected: descriptor)
                    },
                    onCancel: {
                        tvModeSettings.resolveScreenPicker(selected: nil)
                    }
                )
                .transition(.opacity)
                .zIndex(150)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        .environment(\.tvModeScale, scale)
        .animation(.easeInOut(duration: 0.2), value: coreManager.pendingDownload)
        .onAppear {
            scale = TVModeMetrics.scale
            navContext.handler = { [self] action in handle(action: action) }
            // Honor an already-running game so we don't double-rout `select` /
            // `launchGame` into the launch pipeline and surface a duplicate-
            // launch notification.
            if runningGames.runningGames.isEmpty {
                navContext.resumeFromGameplay()
            } else {
                navContext.suspendForGameplay()
            }
            GamepadNavContextStack.shared.push(navContext)
            // Screen selection (target resolve + picker + fullscreen) is
            // driven by `TVModeSettingsManager.enter()` so every entry path
            // — menu, gamepad combo, library grid, cold-start — uses the
            // exact same flow. Nothing to do here.
        }
        .onDisappear {
            GamepadNavContextStack.shared.remove(navContext)
            // Fullscreen exit is handled by `ContentView` after it's observed
            // `tvModeSettings.isActive` flip false — that timing is after
            // SwiftUI has mounted `mainInterface`, so the unified toolbar
            // renders before the fullscreen→windowed transition starts.
        }
        .onChange(of: systemDatabase.systems) { _, _ in
            viewModel.handleExternalSystemsChange()
        }
        // Live re-load if the user changes TV mode settings from elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: .tvModeSettingsChanged)) { _ in
            viewModel.reloadSettings()
        }
        // Suspend the TV-mode gamepad nav context while a game window is
        // active so its higher priority (60) doesn't outrank the game window's
        // `GamepadGameRunningContext`. Without this, an Enter pressed mid-
        // gameplay routes back here and re-fires the launch flow.
        .onChange(of: runningGames.runningGames.isEmpty) { _, noGameRunning in
            if noGameRunning { navContext.resumeFromGameplay() }
            else { navContext.suspendForGameplay() }
        }
        .modifier(TVModeKeyMonitor())
    }

    @ViewBuilder
    private var background: some View {
        if viewModel.theme == .boxart {
            TVModeBoxartBackdrop(
                rom: backdropROM,
                scrimColor: Color.black.opacity(0.45)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .drawingGroup()
            .allowsHitTesting(false)
        } else if viewModel.theme == .bold {
            TVModeAnimatedAccentBackground()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        } else {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.08)
                RadialGradient(colors: [Color.white.opacity(0.04), .clear], center: .center, startRadius: 0, endRadius: 500 * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    /// The ROM whose boxart should fill the backdrop. On the detail page we
    /// prefer the freshly-downloaded hero ROM (so art loads swap-in
    /// seamlessly); otherwise fall back to the currently-selected game in the
    /// list so the backdrop previews the game the user is focused on.
    private var backdropROM: ROM? {
        if viewModel.page == .detail, let rom = viewModel.downloadedDetailROM {
            return rom
        }
        return viewModel.selectedGame
    }

    @ViewBuilder
    private var contentLayer: some View {
        VStack {
            row1
            row2
        }
        .blur(radius: viewModel.page == .detail ? 18 * scale : 0)
        .opacity(viewModel.page == .detail ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.25), value: viewModel.page)

        if viewModel.page == .detail, let rom = viewModel.downloadedDetailROM {
            TVModeGameDetailView(
                rom: rom,
                theme: viewModel.theme,
                focused: true,
                mostRecentSaveSlot: viewModel.mostRecentSaveSlot
            )
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
            itemWidth: 200 * scale,
            itemHeight: 200 * scale,
            spacing: 22 * scale,
            maxSag: 28 * scale,
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
        .padding(.vertical, 30 * scale)
    }

    @ViewBuilder
    private var row2: some View {
        CurvedRowLayout(
            items: viewModel.games,
            centerIndex: Binding(
                get: { viewModel.selectedGameIndex },
                set: { viewModel.selectedGameIndex = $0 }
            ),
            itemWidth: 210 * scale,
            itemHeight: 280 * scale,
            spacing: 14 * scale,
            maxSag: 28 * scale,
            visibleEachSide: 4
        ) { rom, isCenter in
            TVModeGameTile(
                rom: rom,
                isFocused: viewModel.page != .row1 && isCenter,
                theme: viewModel.theme
            )
        }
        .padding(.vertical, 30 * scale)
    }

    @ViewBuilder
    private var topBar: some View {
        VStack {
            HStack {
                Text(loc.localized("tvMode.title"))
                    .font(.system(size: 22 * scale, weight: .bold))
                    .foregroundStyle(viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme) : .white)
                Spacer()
                themeToggle
                Button {
                    showTVSettingsOverlay = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18 * scale))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12 * scale)
            }
            .padding(.horizontal, 40 * scale)
            .padding(.top, 24 * scale)
            Spacer()
        }
        .sheet(isPresented: $showTVSettingsOverlay, onDismiss: restoreKeyWindowAfterSettings) {
            TVModeSettingsView()
                .environmentObject(loc)
        }
    }

    @ViewBuilder
    private var themeToggle: some View {
        HStack(spacing: 6 * scale) {
            ForEach(TVModeSettings.Theme.allCases) { t in
                Button {
                    TVModeSettings.setTheme(t)
                    NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                } label: {
                    Text(loc.localized("tvMode.theme.\(t.rawValue)"))
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .padding(.horizontal, 14 * scale).padding(.vertical, 6 * scale)
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
            HStack(spacing: 24 * scale) {
                hintChip(loc.localized("tvMode.page.systems"), active: viewModel.page == .row1)
                hintChip(loc.localized("tvMode.page.games"), active: viewModel.page == .row2)
                if viewModel.page == .detail {
                    hintChip(loc.localized("tvMode.page.detail"), active: true)
                }
            }
            .padding(.bottom, 20 * scale)
        }
    }

    /// Brief sort-mode pill that surfaces on L3 / L3+R3 to confirm the new
    /// mode. Sits at top-centre of the screen; auto-hides per
    /// `TVModeViewModel.flashSortHud()`.
    private func sortHUD(label: String) -> some View {
        VStack {
            HStack(spacing: 8 * scale) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 16 * scale, weight: .semibold))
                Text(verbatim: loc.localized("app.sortBy"))
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: label)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 18 * scale).padding(.vertical, 10 * scale)
            .background(
                Capsule().fill(AppColors.windowBackground(colorScheme, tinted: false).opacity(0.92))
            )
            .overlay(
                Capsule().strokeBorder(AppColors.brandAccent.opacity(0.5), lineWidth: 1 * scale)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .padding(.top, 28 * scale)
            Spacer()
        }
    }

    @ViewBuilder
    private func hintChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 12 * scale, weight: .semibold))
            .padding(.horizontal, 12 * scale).padding(.vertical, 5 * scale)
            .background(Capsule().fill(active && viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme).opacity(0.22) : Color.white.opacity(active ? 0.10 : 0.04)))
            .overlay(Capsule().strokeBorder(active && viewModel.theme == .bold ? AppColors.accentForScheme(colorScheme) : Color.white.opacity(active ? 0.3 : 0.1), lineWidth: 1 * scale))
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
            case .detail:
                // A on the detail page acts as "Continue": when the selected
                // ROM has a save state the most recent slot is restored, so the
                // user can resume previous play without leaving TV-mode
                // (mirrors the desktop `GameDetailView` Continue button). When
                // no save exists this falls through to a fresh launch.
                let slot = viewModel.mostRecentSaveSlot
                Task { await viewModel.launchSelected(slotToLoad: slot?.id, progressiveVersion: slot?.progressiveVersion) }
            }
        case .launchGame:
            switch viewModel.page {
            case .row1: viewModel.moveDownFromRow1()
            // Start (.launchGame) jumps straight into the game from any list
            // page; the detail-page "play fresh" path lives on Y (see the
            // `.contextMenu` branch below) since that's where the user expects
            // the secondary launch affordance to live.
            case .row2, .detail: Task { await viewModel.launchSelected() }
            }
        case .cancel:
            switch viewModel.page {
            case .row2: viewModel.exitRow2()
            case .detail: viewModel.exitDetail()
            case .row1: NotificationCenter.default.post(name: .tvModeExited, object: nil)
            }
        case .contextMenu:
            // Y is bound to `.contextMenu`. On the game-detail page A already
            // behaves as "Continue" (loads the most recent save), so Y takes
            // the natural cousin role and launches the game fresh — matches
            // the secondary "Play from start" chip rendered in
            // `TVModeGameDetailView`. `disableAutoLoad: true` forces the
            // runner to skip the auto-load step even when the user has
            // `saveState_autoLoadOnStart` enabled, so Y always starts a fresh
            // session regardless of the global preference. Any other page
            // (row1, row2, settings overlays, etc.): Y opens the TV-mode
            // settings sheet as before.
            if viewModel.page == .detail {
                Task { await viewModel.launchSelected(disableAutoLoad: true) }
            } else {
                showTVSettingsOverlay = true
            }
        case .toggleViewMode, .focusSearch:
            // X and SELECT both cycle the theme. L3 (was also routed here)
            // is repurposed to rotate the game-row sort mode — see
            // `.cycleSortOrder` / `.resetFilters` cases below.
            cycleTheme()
        case .cycleSortOrder:
            viewModel.cycleSortMode()
        case .resetFilters:
            viewModel.resetSortMode()
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
        let allThemes = TVModeSettings.Theme.allCases
        let current = TVModeSettings.theme
        let nextIndex = (allThemes.firstIndex(of: current).map { $0 + 1 } ?? 0) % allThemes.count
        TVModeSettings.setTheme(allThemes[nextIndex])
        NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
    }

    /// Re-asserts key window status on the TV-mode window after the in-app
    /// settings sheet dismisses. When a SwiftUI sheet presents on top of a
    /// fullscreen window, the dismissal handshake occasionally leaves
    /// `NSApp.keyWindow` `nil` — once that happens `GamepadNavigationManager.poll`
    /// bails at its `keyWindow != nil` guard, so every subsequently-pressed
    /// button silently does nothing until the user clicks the window with the
    /// mouse. Forcing a `makeKeyAndOrderFront` on the fullscreen TV-mode window
    /// re-keys it so polling resumes immediately. The dispatch is deferred via
    /// `DispatchQueue.main.async` so we run AFTER SwiftUI has fully torn down
    /// the sheet; calling `makeKeyAndOrderFront` synchronously inside the
    /// `.onDismiss` callback can land on a window hierarchy that's still in
    /// the middle of pulling down the sheet, which silently no-ops on the
    /// fullscreen app window.
    fileprivate func restoreKeyWindowAfterSettings() {
        // Cross at least one CATransaction boundary (mirrors the pattern used
        // elsewhere for fullscreen toggles) so the re-key runs AFTER SwiftUI
        // has fully torn the sheet down. A single `makeKeyAndOrderFront`
        // occasionally no-ops on a fullscreen window whose key status is
        // transiently undefined mid-dismissal; schedule a second attempt a
        // beat later to catch the rare case where the first one lands too
        // early.
        let reKey: () -> Void = {
            guard let window = NSApp.windows.first(where: { $0.styleMask.contains(.fullScreen) }) else { return }
            window.makeKeyAndOrderFront(nil)
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                reKey()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { reKey() }
            }
        }
    }
}

extension Notification.Name {
    static let tvModeSettingsChanged = Notification.Name("tvModeSettingsChanged")
    static let tvModeExited = Notification.Name("tvModeExited")
    static let tvModeEntered = Notification.Name("tvModeEntered")
}

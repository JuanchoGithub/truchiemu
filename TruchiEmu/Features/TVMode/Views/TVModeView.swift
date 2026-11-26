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

    /// Gates the detail view's insertion (the enter-detail stagger). The rows'
    /// blur/dim runs first (0.10 s); `detailVisible` flips true only after that
    /// finishes, so the large hero boxart fades in over already-dimmed rows
    /// instead of over still-bright, unblurred UI. Stays `true` while shifting
    /// between games on the detail page, so those crossfades keep running over
    /// the already-blurred rows.
    @State private var detailVisible: Bool = false
    @State private var detailRevealTask: Task<Void, Never>?

    /// Refreshed on appear / screen change so the scale tracks the current
    /// display. Held in `@State` so children read a stable value via
    /// `\.tvModeScale` and re-render when it changes.
    @State private var scale: CGFloat = TVModeMetrics.scale

    init(library: ROMLibrary, systemDatabase: SystemDatabaseWrapper, categoryManager: CategoryManager, initialEntryID: String? = nil) {
        _viewModel = StateObject(wrappedValue: TVModeViewModel(
            library: library,
            systemDatabase: systemDatabase,
            categoryManager: categoryManager,
            initialEntryID: initialEntryID
        ))
        _navContext = StateObject(wrappedValue: TVModeNavContext())
    }

    var body: some View {
        let palette = TVModePalette(theme: viewModel.theme, colorScheme: colorScheme)
        ZStack {
            background
                .ignoresSafeArea()
            scrims(palette)

            VStack(spacing: 0) {
                ZStack {
                    browseLayer(palette)
                    if viewModel.page == .detail, detailVisible, let rom = viewModel.downloadedDetailROM {
                        detailScrim(palette)
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

                TVModeHintBar(
                    hints: hints(),
                    sortLabel: sortLabel,
                    theme: viewModel.theme
                )
            }
            .padding(.horizontal, 40 * scale)
            .padding(.top, 22 * scale)
            .padding(.bottom, 12 * scale)
            .sheet(isPresented: $showTVSettingsOverlay, onDismiss: restoreKeyWindowAfterSettings) {
                TVModeSettingsView()
                    .environmentObject(loc)
            }

            if let hudLabel = viewModel.sortHudLabel {
                sortHUD(label: hudLabel, palette: palette)
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
        .environment(\.tvModeScale, scale)
        // Stop every TV-mode animation while a game runs. `MTKView` draws the
        // game on the main thread, so a busy TV-mode animation freezes game
        // video while the audio thread keeps playing.
        .environment(\.tvModeAnimationActive, runningGames.runningGames.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: coreManager.pendingDownload)
        .onAppear {
            refreshScale()
            // Decode all system icons once, up front: fast flights mount new
            // tiles every step, and any main-thread disk read or decode there
            // shows up as hitches. Idempotent after the first call.
            TVModeEntryTile.warmIcons(for: viewModel.row1Entries, scale: scale)
            // Cold-start resume: the main window exists now, so run the screen
            // selection (move to remembered display + fullscreen) that init
            // deferred because no window was up yet.
            tvModeSettings.resolveColdStartScreenSelectionIfNeeded()
            // Re-assert the scale a beat after appear: the cold-start
            // fullscreen transition / display settle can land after the
            // immediate read, and a stale launch-time `NSScreen.main` read
            // freezes TV-sized icons on the wrong screen. Refreshing once the
            // transition has landed keeps the icons at the size the current
            // display needs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                refreshScale()
                TVModeEntryTile.warmIcons(for: viewModel.row1Entries, scale: scale)
            }
            navContext.handler = { [self] action in handle(action: action) }
            // Honor an already-running game so we don't double-route `select` /
            // `launchGame` into the launch pipeline and surface a duplicate-
            // launch notification.
            if runningGames.runningGames.isEmpty {
                navContext.resumeFromGameplay()
            } else {
                navContext.suspendForGameplay()
            }
            GamepadNavContextStack.shared.push(navContext)
            // Screen selection (target resolve + picker + fullscreen) is
            // driven by `TVModeSettingsManager.enter()` for live entry paths
            // (menu, gamepad combo, library grid). Cold-start resume defers it
            // to here via `resolveColdStartScreenSelectionIfNeeded()` above —
            // the window only exists once this view appears.
        }
        .onDisappear {
            GamepadNavContextStack.shared.remove(navContext)
            detailRevealTask?.cancel()
            detailRevealTask = nil
            // Fullscreen exit is handled by `ContentView` after it's observed
            // `tvModeSettings.isActive` flip false — that timing is after
            // SwiftUI has mounted `mainInterface`, so the unified toolbar
            // renders before the fullscreen→windowed transition starts.
        }
        .onChange(of: systemDatabase.systems) { _, _ in
            viewModel.handleExternalSystemsChange()
        }
        .onChange(of: viewModel.row1Entries) { _, entries in
            TVModeEntryTile.warmIcons(for: entries, scale: scale)
        }
        // Live re-load if the user changes TV mode settings from elsewhere.
        .onReceive(NotificationCenter.default.publisher(for: .tvModeSettingsChanged)) { _ in
            viewModel.reloadSettings()
        }
        // Recompute the scale whenever the display setup changes (external
        // monitor plugged in / unplugged, resolution change) so the icons
        // track the screen the TV-mode window actually fills instead of the
        // value captured at launch.
        .onChange(of: screenCatalog.screens) { _, _ in
            refreshScale()
        }
        .onChange(of: screenCatalog.mainScreenID) { _, _ in
            refreshScale()
        }
        // The TV-mode window moves between screens (screen selection, fullscreen
        // transition, display re-arrangement) without necessarily posting a
        // display-parameters change — recompute the scale off the window's own
        // screen in those cases so the icons always match where the window is.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
            refreshScale()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            refreshScale()
        }
        // Suspend the TV-mode gamepad nav context while a game window is
        // active so its higher priority (60) doesn't outrank the game window's
        // `GamepadGameRunningContext`. Without this, an Enter pressed mid-
        // gameplay routes back here and re-fires the launch flow.
        .onChange(of: runningGames.runningGames.isEmpty) { _, noGameRunning in
            if noGameRunning { navContext.resumeFromGameplay() }
            else { navContext.suspendForGameplay() }
        }
        // Enter-detail stagger: hold the detail view back until the browse
        // surface has finished its fast blur/dim, then reveal it. On exit, drop
        // the gate immediately so the detail view fades out while the rows
        // unblur.
        .onChange(of: viewModel.page) { _, newPage in
            detailRevealTask?.cancel()
            detailRevealTask = nil
            guard newPage == .detail else {
                detailVisible = false
                return
            }
            detailVisible = false
            detailRevealTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.20)) {
                    detailVisible = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.20), value: viewModel.downloadedDetailROM?.id)
        .modifier(TVModeKeyMonitor())
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if viewModel.theme == .boxart {
            TVModeBoxartBackdrop(
                rom: backdropROM,
                scrimColor: Color.black.opacity(0.45)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        } else if viewModel.theme == .bold {
            TVModeAnimatedAccentBackground()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.065, green: 0.070, blue: 0.085),
                        Color(red: 0.030, green: 0.032, blue: 0.040)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [AppColors.accentForScheme(colorScheme).opacity(0.14), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 760 * scale
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    /// Top/bottom scrims and a soft vignette. They keep the header, hero text
    /// and hint bar legible over a bright boxart backdrop, and give the screen
    /// the cinematic letterbox feel the flat two-row layout lacked.
    private func scrims(_ palette: TVModePalette) -> some View {
        ZStack {
            LinearGradient(
                colors: [palette.scrimTop, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240 * scale)
            .frame(maxHeight: .infinity, alignment: .top)

            LinearGradient(
                colors: [.clear, palette.scrimBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 380 * scale)
            .frame(maxHeight: .infinity, alignment: .bottom)

            if palette.isDarkCanvas {
                RadialGradient(
                    colors: [.clear, .black.opacity(0.32)],
                    center: .center,
                    startRadius: 260 * scale,
                    endRadius: 980 * scale
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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

    /// Recomputed from the screen the TV-mode window actually sits on. More
    /// reliable than `TVModeMetrics.scale` (which reads `NSScreen.main`) during
    /// cold start and fullscreen transitions, when `NSScreen.main` can still
    /// report the screen the app launched on rather than where the window ended
    /// up. Falls back to `NSScreen.main` when no window is resolvable.
    private func refreshScale() {
        let window = NSApp.windows.first { $0.styleMask.contains(.fullScreen) }
            ?? NSApp.mainWindow
        if let screen = window?.screen {
            scale = TVModeMetrics.scale(for: screen)
        } else {
            scale = TVModeMetrics.scale
        }
    }

    // MARK: - Browse surface

    private func browseLayer(_ palette: TVModePalette) -> some View {
        VStack(spacing: 0) {
            header(palette)

            if viewModel.row1Entries.isEmpty {
                emptyLibrary(palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The systems rail only spans the hero stage. It used to share
                // the full column height with the poster row, so its lower
                // icons rendered on top of the posters.
                HStack(alignment: .top, spacing: 26 * scale) {
                    TVModeSystemRail(
                        entries: viewModel.row1Entries,
                        selectedIndex: viewModel.selectedEntryIndex,
                        move: viewModel.entryMove,
                        theme: viewModel.theme,
                        active: viewModel.page == .row1,
                        countFor: { viewModel.count(for: $0.filter) }
                    )

                    VStack(spacing: 0) {
                        titleBlock(palette)
                        TVModeHeroPanel(
                            rom: viewModel.selectedGame,
                            page: viewModel.page,
                            theme: viewModel.theme,
                            emptyMessage: loc.localized("tvMode.empty.noGames")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(viewModel.page == .row1 ? 0.80 : 1)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.page)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Full-width poster row: it centres on the screen and bleeds
                // under the rail column, which is empty at this height.
                gamesRail
            }
        }
        .blur(radius: viewModel.page == .detail ? 18 * scale : 0)
        .opacity(viewModel.page == .detail ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.10), value: viewModel.page)
    }

    private func header(_ palette: TVModePalette) -> some View {
        HStack(spacing: 12 * scale) {
            HStack(spacing: 8 * scale) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 6 * scale, height: 6 * scale)
                Text(verbatim: loc.localized("tvMode.title").uppercased())
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .tracking(2.4 * scale)
                    .foregroundStyle(palette.textSecondary)
            }

            zoneChip(palette)

            Spacer()

            themeToggle(palette)
            settingsButton(palette)
        }
        .padding(.bottom, 16 * scale)
    }

    private func themeToggle(_ palette: TVModePalette) -> some View {
        HStack(spacing: 2 * scale) {
            ForEach(TVModeSettings.Theme.allCases) { t in
                Button {
                    TVModeSettings.setTheme(t)
                    NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                } label: {
                    Text(verbatim: loc.localized("tvMode.theme.\(t.rawValue)"))
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .padding(.horizontal, 12 * scale)
                        .padding(.vertical, 6 * scale)
                        .background(
                            Capsule().fill(
                                viewModel.theme == t
                                    ? (t == .bold ? palette.accent.opacity(0.22) : palette.panelFillStrong)
                                    : Color.clear
                            )
                        )
                        .foregroundStyle(viewModel.theme == t ? palette.textPrimary : palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3 * scale)
        .background(Capsule().fill(palette.panelFill))
        .overlay(Capsule().strokeBorder(palette.panelStroke, lineWidth: 1 * scale))
    }

    private func settingsButton(_ palette: TVModePalette) -> some View {
        Button {
            showTVSettingsOverlay = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 30 * scale, height: 30 * scale)
                .background(Circle().fill(palette.panelFill))
                .overlay(Circle().strokeBorder(palette.panelStroke, lineWidth: 1 * scale))
        }
        .buttonStyle(.plain)
    }

    private func titleBlock(_ palette: TVModePalette) -> some View {
        let entry = viewModel.selectedEntry
        let isSystem = entry?.system != nil
        return VStack(alignment: .leading, spacing: 3 * scale) {
            Text(verbatim: loc.localized(isSystem ? "tvMode.eyebrow.system" : "tvMode.eyebrow.collection"))
                .font(.system(size: 10 * scale, weight: .bold))
                .tracking(2 * scale)
                .foregroundStyle(palette.accent)

            // The count shares the title's baseline. As a separate top-right
            // block it read as a detached header label, far from the title it
            // counts.
            HStack(alignment: .firstTextBaseline, spacing: 24 * scale) {
                Text(verbatim: entry?.displayName ?? loc.localized("tvMode.page.games"))
                    .font(.system(size: 42 * scale, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Spacer(minLength: 20 * scale)

                Text(verbatim: gameCountLabel(viewModel.games.count))
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.bottom, 8 * scale)
    }

    private func zoneChip(_ palette: TVModePalette) -> some View {
        let key: String
        switch viewModel.page {
        case .row1: key = "tvMode.page.systems"
        case .row2: key = "tvMode.page.games"
        case .detail: key = "tvMode.page.detail"
        }
        return Text(verbatim: loc.localized(key).uppercased())
            .font(.system(size: 9.5 * scale, weight: .bold))
            .tracking(1.4 * scale)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 4 * scale)
            .background(Capsule().fill(palette.accent.opacity(0.14)))
            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.35), lineWidth: 1 * scale))
    }

    private func gameCountLabel(_ count: Int) -> String {
        if count == 1 { return loc.localized("tvMode.meta.gamesOne") }
        return loc.localized("tvMode.meta.gamesMany")
            .replacingOccurrences(of: "{count}", with: "\(count)")
    }

    private var gamesRail: some View {
        CurvedRowLayout(
            items: viewModel.games,
            centerIndex: Binding(
                get: { viewModel.selectedGameIndex },
                set: { viewModel.selectedGameIndex = $0 }
            ),
            move: viewModel.gameMove,
            itemWidth: 160 * scale,
            itemHeight: 224 * scale,
            spacing: 12 * scale,
            maxSag: 10 * scale,
            visibleEachSide: 5
        ) { rom, focus in
            TVModeGameTile(
                rom: rom,
                // Only the games rail shows focus while it owns input. On the
                // systems rail and on the detail page the poster row sits
                // behind other content, so its 20 Hz holo is paused.
                focus: viewModel.page == .row2 ? focus : 0,
                theme: viewModel.theme
            )
        }
        // Fades the games row in for the final system of a fast flight
        // (see `pulseGamesFade`), and dims it while the systems rail owns
        // input. Both are one opacity so the two states never fight.
        .opacity((viewModel.gamesDimmed ? 0 : 1) * (viewModel.page == .row1 ? 0.62 : 1))
        .animation(.easeOut(duration: 0.25), value: viewModel.gamesDimmed)
        .animation(.easeInOut(duration: 0.2), value: viewModel.page)
        // Soft edge fade: the row bleeds past both window edges, and cut
        // posters looked accidental. Matches the systems rail's edge fade.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.045),
                    .init(color: .black, location: 0.955),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func emptyLibrary(_ palette: TVModePalette) -> some View {
        VStack(spacing: 14 * scale) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 42 * scale, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text(verbatim: loc.localized("tvMode.empty.libraryTitle"))
                .font(.system(size: 24 * scale, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(verbatim: loc.localized("tvMode.empty.libraryMessage"))
                .font(.system(size: 14 * scale))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420 * scale)
        }
    }

    private func detailScrim(_ palette: TVModePalette) -> some View {
        Group {
            if palette.isDarkCanvas {
                Color.black.opacity(0.38)
            } else {
                AppColors.windowBackground(colorScheme).opacity(0.55)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Hints

    private func hints() -> [TVModeHint] {
        switch viewModel.page {
        case .row1:
            return [
                TVModeHint(glyph: "A", label: loc.localized("tvMode.hint.open")),
                TVModeHint(glyph: "↕", label: loc.localized("tvMode.hint.systems")),
                TVModeHint(glyph: "→", label: loc.localized("tvMode.hint.games")),
                TVModeHint(glyph: "Y", label: loc.localized("app.settings")),
                TVModeHint(glyph: "X", label: loc.localized("settings.theme"))
            ]
        case .row2:
            return [
                TVModeHint(glyph: "A", label: loc.localized("header.play")),
                TVModeHint(glyph: "↓", label: loc.localized("tvMode.hint.details")),
                TVModeHint(glyph: "B", label: loc.localized("tvMode.hint.back")),
                TVModeHint(glyph: "Y", label: loc.localized("app.settings")),
                TVModeHint(glyph: "X", label: loc.localized("settings.theme"))
            ]
        case .detail:
            let hasSave = viewModel.mostRecentSaveSlot?.exists == true
            var items: [TVModeHint] = [
                TVModeHint(glyph: "A", label: loc.localized(hasSave ? "header.continue" : "header.play")),
                TVModeHint(glyph: "B", label: loc.localized("tvMode.hint.back")),
                TVModeHint(glyph: "←→", label: loc.localized("tvMode.hint.browse"), wide: true)
            ]
            if hasSave {
                items.append(TVModeHint(glyph: "Y", label: loc.localized("tvMode.hint.playFromStart")))
            }
            items.append(TVModeHint(glyph: "X", label: loc.localized("settings.theme")))
            return items
        }
    }

    private var sortLabel: String? {
        guard viewModel.page != .detail else { return nil }
        return loc.localized(viewModel.sortMode.localizationKey)
    }

    /// Brief sort-mode pill that surfaces on L3 / L3+R3 to confirm the new
    /// mode. Sits at top-centre of the screen; auto-hides per
    /// `TVModeViewModel.flashSortHud()`.
    private func sortHUD(label: String, palette: TVModePalette) -> some View {
        VStack {
            HStack(spacing: 8 * scale) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(verbatim: loc.localized("app.sortBy"))
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                Text(verbatim: label)
                    .font(.system(size: 14 * scale, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, 18 * scale)
            .padding(.vertical, 10 * scale)
            .background(Capsule().fill(palette.panelFillStrong))
            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.5), lineWidth: 1 * scale))
            .shadow(color: palette.shadow, radius: 12 * scale, y: 4 * scale)
            .padding(.top, 28 * scale)
            Spacer()
        }
    }
}

// MARK: - Action handling

extension TVModeView {
    fileprivate func handle(action: GamepadNavAction) {
        switch action {
        // The systems rail is vertical, so up/down walk the rail and
        // left/right move between the rail and the games rail. This mirrors
        // the on-screen geometry: the old horizontal system carousel used
        // left/right for systems, which no longer matches the layout.
        case .navigateUp:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(-1)
            case .row2: viewModel.exitRow2()
            case .detail: viewModel.exitDetail()
            }
        case .navigateDown:
            switch viewModel.page {
            case .row1: viewModel.selectEntryByOffset(1)
            case .row2: viewModel.enterDetail()
            case .detail: break
            }
        case .navigateLeft:
            switch viewModel.page {
            case .row1: break
            case .row2: viewModel.selectGameByOffset(-1)
            case .detail: viewModel.shiftDetailGame(by: -1)
            }
        case .navigateRight:
            switch viewModel.page {
            case .row1: viewModel.moveDownFromRow1()
            case .row2: viewModel.selectGameByOffset(1)
            case .detail: viewModel.shiftDetailGame(by: 1)
            }
        // L1 / R1 — move 5 at a time along the active axis
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
        // L2 / R2 — move 10 at a time along the active axis
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
            // A on the games rail launches immediately (Continue when a save
            // exists). The detail page is one press away on Down, so the
            // primary button no longer costs a detour through it.
            case .row2: Task { await viewModel.launchFromRail() }
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

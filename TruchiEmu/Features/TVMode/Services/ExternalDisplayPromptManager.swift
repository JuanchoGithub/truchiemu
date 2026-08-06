import Foundation
import Combine
import AppKit

/// Drives the external-display flow that starts when a non-built-in display
/// (TV/monitor) is plugged in:
///
///   1. **Warm-up (10s)** — a cold-plugged display is "online" to macOS long
///      before it can render content, and there is no public API that reports
///      when it is actually ready. A fixed warm-up window runs first, surfaced
///      as a small bottom pill ("Detected screen <name>…"). This step is
///      deliberately hands-off: no card, no pause, no input interception — the
///      player can keep playing and even pause or save before the intrusive
///      step.
///   2. **Prompt (5s)** — "Open app in External Device <name>?" card, which
///      covers part of the screen, so the game is paused as soon as it appears.
///      The countdown auto-accepts (the console-friendly default is YES);
///      B/ESC declines, A/RETURN accepts.
///   3. On accept, TV Mode enters on the newly-connected display; the paused
///      game is moved onto it (a fullscreen game window round-trips through
///      windowed so the move can `setFrame`).
///   4. **Resume gate** — the game stays paused behind a "Press A to resume"
///      card; a second A/RETURN (or another 5s) resumes it.
///
/// Input is handled two ways: a local key monitor for RETURN/ESC, and a
/// high-priority `GamepadNavContext` for A/B. The nav context sets
/// `bypassesGameplaySuppression` so `GamepadNavigationManager` keeps routing
/// A/B to it even while a game is running. Both are only installed for the
/// prompt/resume-gate steps — never during warm-up, so the player keeps full
/// control of the game there.
@MainActor
final class ExternalDisplayPromptManager: ObservableObject {
    static let shared = ExternalDisplayPromptManager()

    enum PromptPhase: Equatable {
        case idle
        /// Detected a new display; waiting out the warm-up window before asking.
        case warmingUp(ScreenDescriptor)
        /// Asking "Open app in <display>?" — A/RETURN or countdown accepts.
        case asking(ScreenDescriptor)
        /// A game was moved to the TV and paused; waiting for A/RETURN to
        /// resume (countdown auto-resumes too).
        case resumeGate(ScreenDescriptor)
    }

    @Published private(set) var phase: PromptPhase = .idle
    @Published private(set) var countdown: Int = ExternalDisplayPromptManager.countdownDuration

    static let countdownDuration = 5
    static let warmUpDuration = 10

    private let navContext = ExternalDisplayPromptNavContext()
    private var previousScreenIDs: Set<String> = []
    private var countdownTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    /// Game windows captured when the warm-up began — the ones that get the
    /// overlay, are paused from the first timer, then moved on accept.
    private var gameControllers: [StandaloneGameWindowController] = []
    /// Pending fullscreen-exit move state (see `moveGameWindow`).
    private var pendingFullscreenExitWindow: NSWindow?
    private var pendingFullscreenExitAction: (() -> Void)?

    private init() {
        previousScreenIDs = Set(ScreenCatalog.shared.screens.map(\.id))
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
        navContext.onAccept = { [weak self] in self?.accept() }
        navContext.onDecline = { [weak self] in self?.decline() }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Detection

    private func handleScreenChange() {
        let catalog = ScreenCatalog.shared
        catalog.refresh()
        let current = catalog.screens
        let currentIDs = current.map(\.id)

        // Cancel any active countdown if its display was just unplugged — the
        // flow must not keep counting toward (or auto-accept onto) a dead
        // screen. Screen ids are stable across resolution/arrangement changes,
        // so only a real disconnect matches.
        switch phase {
        case .warmingUp(let screen), .asking(let screen), .resumeGate(let screen):
            if !current.contains(screen) {
                cancelFlow()
            }
        case .idle:
            break
        }

        let addedExternal = current.first { !previousScreenIDs.contains($0.id) && !$0.isBuiltIn }
        previousScreenIDs = Set(currentIDs)

        // Never prompt while TV Mode is already on that display, when the user
        // launches straight into TV Mode, or while a prompt is already up.
        guard phase == .idle,
              let external = addedExternal,
              !TVModeSettingsManager.shared.isActive,
              !TVModeSettings.launchInTVMode else { return }

        beginWarmUp(for: external)
    }

    // MARK: - Warm-up

    /// Starts the flow with a non-intrusive warm-up window. A cold-plugged
    /// display is reported as connected before it can render, and there is no
    /// reliable public API for "ready", so we wait out `warmUpDuration` first.
    /// The warm-up is deliberately hands-off: only a small bottom pill shows
    /// (via `ExternalDisplayPromptView`) — no pause, no input interception — so
    /// the player can keep playing, and optionally pause or save, before the
    /// intrusive prompt takes over.
    private func beginWarmUp(for screen: ScreenDescriptor) {
        // Snapshot the running games now so the pill can sit over them and so
        // we know which games to pause/move once the prompt starts.
        gameControllers = GameLauncher.shared.allActiveControllers()
            .filter { $0.window != nil && ($0.runner?.isRunning ?? false) }

        phase = .warmingUp(screen)
        countdown = ExternalDisplayPromptManager.warmUpDuration

        for controller in gameControllers {
            controller.showExternalPromptOverlay()
        }
        startCountdown(seconds: ExternalDisplayPromptManager.warmUpDuration) { [weak self] in
            self?.beginPrompt(for: screen)
        }
    }

    private func beginPrompt(for screen: ScreenDescriptor) {
        // The display may have been unplugged during warm-up — abort and
        // resume the game rather than trying to move onto a dead screen.
        guard ScreenCatalog.shared.screens.contains(screen) else {
            cancelFlow()
            return
        }

        // Drop games that closed during the warm-up window (hiding their
        // overlays) so we only pause/move the ones still running.
        gameControllers = gameControllers.filter { controller in
            guard controller.window != nil, controller.runner?.isRunning == true else {
                controller.hideExternalPromptOverlay()
                return false
            }
            return true
        }

        // The prompt card covers part of the screen — pause now so the game
        // doesn't keep advancing (the warm-up pill deliberately let it play).
        setGamesPaused(true)

        for controller in gameControllers {
            controller.showExternalPromptOverlay()
        }
        GamepadNavContextStack.shared.push(navContext)
        installKeyMonitor()
        // Bring the app forward so the prompt is visible and gamepad polling is
        // live (`poll()` gates on `NSApp.isActive`).
        NSApp.activate(ignoringOtherApps: true)

        phase = .asking(screen)
        countdown = ExternalDisplayPromptManager.countdownDuration
        startCountdown(seconds: ExternalDisplayPromptManager.countdownDuration) { [weak self] in
            self?.accept()
        }
    }

    // MARK: - Prompt

    /// Auto-accept is the default: every countdown reaching zero accepts.
    /// A/RETURN also accepts.
    func accept() {
        switch phase {
        case .asking(let screen):
            phase = .idle
            countdownTask?.cancel()
            GamepadNavContextStack.shared.remove(navContext)
            enterTVMode(on: screen)
        case .resumeGate:
            resumeGame()
        case .idle, .warmingUp:
            break
        }
    }

    func decline() {
        switch phase {
        case .asking:
            cancelFlow()
        case .resumeGate, .idle, .warmingUp:
            break
        }
    }

    /// Ends the flow without entering TV Mode: resume any paused games and
    /// tear down the UI.
    private func cancelFlow() {
        phase = .idle
        countdownTask?.cancel()
        setGamesPaused(false)
        teardownPromptUI()
    }

    // MARK: - Accept flow

    private func enterTVMode(on screen: ScreenDescriptor) {
        // Games are already paused since the warm-up began; re-pausing is
        // idempotent and keeps the invariant if this ever runs without it.
        setGamesPaused(true)

        TVModeSettingsManager.shared.enter(on: screen)

        // Move the paused game(s) onto the external display. A fullscreen game
        // window is a Space, so it must exit fullscreen before it can be moved,
        // then re-enter once the exit transition lands.
        for controller in gameControllers {
            guard let window = controller.window else { continue }
            moveGameWindow(window, to: screen)
        }

        if !gameControllers.isEmpty {
            beginResumeGate(screen: screen)
        } else {
            teardownPromptUI()
        }
    }

    private func moveGameWindow(_ window: NSWindow, to screen: ScreenDescriptor) {
        let wasFullscreen = window.styleMask.contains(.fullScreen)

        let performMove: () -> Void = {
            let target = screen.visibleFrame
            // Keep the window's current size, clamped so it fits the target
            // display, centered on it.
            let size = CGSize(
                width: min(window.frame.width, target.width),
                height: min(window.frame.height, target.height)
            )
            let frame = NSRect(
                x: target.midX - size.width / 2,
                y: target.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            TVModeSettingsManager.shared.moveWindow(window, onto: screen, finalFrame: frame)
            if wasFullscreen {
                window.toggleFullScreen(nil)
            }
            // Bring the game above the TV-mode fullscreen window so the user
            // sees the paused game (and its resume gate) on the TV.
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        if wasFullscreen {
            // Exit fullscreen, run the move once the exit transition lands
            // (`handleFullscreenExit`), then re-enter fullscreen on the new
            // display — the window is already windowed at that point so the
            // re-entry targets the moved screen.
            pendingFullscreenExitWindow = window
            pendingFullscreenExitAction = performMove
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFullscreenExit(_:)),
                name: NSWindow.didExitFullScreenNotification,
                object: window
            )
            window.toggleFullScreen(nil)
        } else {
            performMove()
        }
    }

    @objc private func handleFullscreenExit(_ notification: Notification) {
        guard let window = pendingFullscreenExitWindow,
              notification.object as? NSWindow === window else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: window)
        pendingFullscreenExitWindow = nil
        let action = pendingFullscreenExitAction
        pendingFullscreenExitAction = nil
        action?()
    }

    private func beginResumeGate(screen: ScreenDescriptor) {
        phase = .resumeGate(screen)
        countdown = ExternalDisplayPromptManager.countdownDuration
        GamepadNavContextStack.shared.push(navContext)
        installKeyMonitor()
        startCountdown(seconds: ExternalDisplayPromptManager.countdownDuration) { [weak self] in
            self?.accept()
        }
    }

    func resumeGame() {
        guard case .resumeGate = phase else { return }
        phase = .idle
        countdownTask?.cancel()
        setGamesPaused(false)
        teardownPromptUI()
    }

    // MARK: - Teardown

    private func teardownPromptUI() {
        removeKeyMonitor()
        GamepadNavContextStack.shared.remove(navContext)
        for controller in gameControllers {
            controller.hideExternalPromptOverlay()
        }
        gameControllers = []
    }

    /// Pauses/unpauses every captured game window via the pause triple
    /// (runner + metal view + XPC bridge, mirroring `HardcoreViolationAlert`).
    private func setGamesPaused(_ paused: Bool) {
        for controller in gameControllers {
            controller.runner?.isPaused = paused
            controller.metalView?.isPaused = paused
            XPCBridgeAdapter.shared.setPaused(paused)
        }
    }

    // MARK: - Countdown

    /// Runs a per-second countdown from `seconds` down to zero; `completion`
    /// fires when it hits zero. The countdown is phase-agnostic — each phase's
    /// `completion` drives the next transition (warm-up → prompt, prompt →
    /// accept, resume-gate → accept).
    private func startCountdown(seconds: Int, completion: @escaping () -> Void) {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.countdown -= 1
                if self.countdown <= 0 {
                    completion()
                    return
                }
            }
        }
    }

    // MARK: - Keyboard

    /// Local key monitor mapping RETURN → accept and ESC → decline while a
    /// phase is active. Modal by design: the prompt is the focused surface, so
    /// these keys drive it (gamepad A/B remain available for the same actions).
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 36: self.accept(); return nil    // Return
            case 53: self.decline(); return nil   // Escape
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

/// High-priority nav context that routes A/RETURN (`.select`) and B/ESC
/// (`.cancel`) to the prompt manager while a phase is active. Owned `window` is
/// nil (global) and priority is above every other context so it wins
/// `topActive()`. `bypassesGameplaySuppression` keeps A/B flowing to it even
/// while a game is running.
@MainActor
private final class ExternalDisplayPromptNavContext: GamepadNavContext {
    override var priority: Int { 200 }
    override var bypassesGameplaySuppression: Bool { true }

    var onAccept: (() -> Void)?
    var onDecline: (() -> Void)?

    override func handleAction(_ action: GamepadNavAction) {
        switch action {
        case .select: onAccept?()
        case .cancel: onDecline?()
        default: break
        }
    }
}

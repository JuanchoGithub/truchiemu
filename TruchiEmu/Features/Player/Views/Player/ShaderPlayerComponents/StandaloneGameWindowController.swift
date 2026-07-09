import Cocoa
import SwiftUI
import MetalKit
import Combine


// MARK: - Safe NSHostingView

// Custom hosting view that short-circuits layout when the XPC service has crashed.
// Prevents use-after-free in SwiftUI's ItemSheetPresentationModifier.destroy during
// the vulnerable window between crash detection and window cleanup.
class SafeHostingView<Content: View>: NSHostingView<Content> {
@objc var isPassThroughOverlay = false
@objc var passesThroughEmptyAreas = false

override func layout() {
    guard !XPCConnectionManager.isShuttingDown else { return }
    super.layout()
}

override func hitTest(_ point: NSPoint) -> NSView? {
    if isPassThroughOverlay {
        return nil
    }
    let result = super.hitTest(point)
    if passesThroughEmptyAreas && result === self {
        return nil
    }
    return result
}

override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return !isPassThroughOverlay
}
}


// MARK: - Standalone Game Window Controller
class StandaloneGameWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    var runner: EmulatorRunner?
    var metalView: FocusableMTKView?
    private var coordinator: MetalCoordinator?
    private var pendingROM: ROM?
    private var pendingCoreID: String?
    
    // Reference to the ROM library for updating playtime (weak to avoid retain cycles)
    weak var library: ROMLibrary?
    // Track the ROM reference for this window instance (for playtime tracking)
    private var trackedROM: ROM?
    // Accumulated playtime in seconds (only counts when game is running and not paused)
    var accumulatedPlaytime: TimeInterval = 0
    // Timer that increments playtime every second while the game is active and not paused
    var playtimeTimer: Timer?
    
    // The currently running game's ROM. Published so the toolbar can observe it.
    @MainActor @Published public var currentGameROM: ROM?
    
    // Whether the cheats overlay is currently shown.
    @MainActor @Published public var showCheatsView: Bool = false
    
    // The sheet window for the cheat manager (if currently presented).
    private var cheatManagerSheetWindow: NSWindow?
    // Whether cheats are enabled for this game launch.
    @MainActor @Published var cheatsEnabled: Bool = false
    // Track the ROM path for this window instance (for cleanup on close)
    private var trackedROMPath: String?
    
    // Bezel support
    @MainActor @Published var bezelImage: NSImage?
    var bezelBackgroundLayer: BezelBackgroundLayer?
    var bezelViewModel: BezelViewModel?
    
    // Toolbar auto-hide state
    @MainActor @Published var isToolbarVisible: Bool = true
    @MainActor @Published var isGamepadToolbarMode: Bool = false
    @MainActor @Published var gamepadToolbarFocusedIndex: Int?
    @MainActor var gameToolbarNavContext: GamepadGameToolbarContext?
    @MainActor var gameRunningNavContext: GamepadGameRunningContext?
    @MainActor @Published var isFullscreen: Bool = false
    @MainActor @Published var autoFullscreenEnabled: Bool = false
    private var isWaitingForFullscreenAnimation = false
    private var fullscreenOverlayView: NSView?
    private var stateLoadOverlayView: NSView?
    private var pendingSlotToLoad: Int?
    private var pendingProgressiveVersion: Int?
    private var pendingROMForState: ROM?
    @MainActor @Published var saveStatesDisabled: Bool = false
@MainActor @Published var isLoading: Bool = false
@MainActor @Published var launchError: GameLaunchError?
var loadingOverlayView: NSHostingView<AnyView>?
var hardcoreAlertOverlayView: NSHostingView<AnyView>?
var errorOverlayView: NSHostingView<AnyView>?
private var firstFrameTimer: Timer?
    var pendingSystemID: String?
    var pendingROMForBezel: ROM?
    var onWindowWillClose: (() -> Void)?
    var toolbarView: NSHostingView<AnyView>?
    var hideToolbarTimer: Timer? = nil
    var skipAutoSaveOnClose: Bool = false
    private var gameLoadedObserver: NSObjectProtocol?
    private var screenshotObserver: NSObjectProtocol?
    private var clipSavedObserver: NSObjectProtocol?
    private var isClosingWindow: Bool = false
    private var didLoadSaveState: Bool = false
var moveListOverlayView: NSHostingView<AnyView>?
var achievementToastOverlayView: NSHostingView<AnyView>?
    var escapeToastOverlayView: SafeHostingView<AnyView>?
    var cheatToastOverlayView: SafeHostingView<AnyView>?
    var screenshotFlashOverlayView: NSView?
    var screenshotPillOverlayView: SafeHostingView<AnyView>?
    var recordingBadgeOverlayView: SafeHostingView<AnyView>?
    var osdOverlayView: SafeHostingView<AnyView>?
    var timeBarOverlayView: SafeHostingView<AnyView>?
    var trainingModeOverlayView: NSHostingView<AnyView>?
var p2JoinStatusOverlayView: NSHostingView<AnyView>?
private var p2JoinStatusCancellable: AnyCancellable?
    private var trainingConfigCancellable: AnyCancellable?
    private var timeMachineCancellable: AnyCancellable?
var guideSidebarView: NSHostingView<AnyView>?
    @MainActor lazy var trainingModeViewModel = TrainingModeOverlayViewModel()

    var toolbarBottomInset: CGFloat {
        guard let toolbar = toolbarView else { return 0 }
        return toolbar.frame.maxY
    }

@MainActor lazy var moveListViewModel: MoveListOverlayViewModel = {
guard let runner = self.runner else {
fatalError("runner must be set before accessing moveListViewModel")
}
return MoveListOverlayViewModel(runner: runner)
}()

@MainActor lazy var gameGuideViewModel = GameGuideViewModel()

    // Dismiss any active sheets and remove the SwiftUI toolbar from the view hierarchy.
    // Must be called before releasing the controller to prevent SwiftUI view graph teardown
    // from accessing deallocated @ObservedObject references.
    @MainActor
    func detachSwiftUI() {
        StreamRecordingService.shared.stop()
        if let sheetWindow = cheatManagerSheetWindow, let window = window {
            window.endSheet(sheetWindow)
            cheatManagerSheetWindow = nil
        }
        toolbarView?.removeFromSuperview()
        toolbarView = nil
        moveListOverlayView?.removeFromSuperview()
        moveListOverlayView = nil
        stateLoadOverlayView?.removeFromSuperview()
        stateLoadOverlayView = nil
        achievementToastOverlayView?.removeFromSuperview()
        achievementToastOverlayView = nil
        escapeToastOverlayView?.removeFromSuperview()
        escapeToastOverlayView = nil
        cheatToastOverlayView?.removeFromSuperview()
        cheatToastOverlayView = nil
        screenshotFlashOverlayView?.removeFromSuperview()
        screenshotFlashOverlayView = nil
        screenshotPillOverlayView?.removeFromSuperview()
        screenshotPillOverlayView = nil
        trainingModeOverlayView?.removeFromSuperview()
        trainingModeOverlayView = nil
        p2JoinStatusOverlayView?.removeFromSuperview()
        p2JoinStatusOverlayView = nil
        p2JoinStatusCancellable = nil
        trainingConfigCancellable = nil
        guideSidebarView?.removeFromSuperview()
guideSidebarView = nil
        loadingOverlayView?.removeFromSuperview()
        loadingOverlayView = nil
        hardcoreAlertOverlayView?.removeFromSuperview()
        hardcoreAlertOverlayView = nil
        errorOverlayView?.removeFromSuperview()
        errorOverlayView = nil
        timeBarOverlayView?.removeFromSuperview()
        timeBarOverlayView = nil
    }

    @MainActor
    func showErrorOverlay(_ error: GameLaunchError) {
        guard launchError == nil else { return }
        launchError = error
        isLoading = false
        firstFrameTimer?.invalidate()
        firstFrameTimer = nil

        if errorOverlayView == nil, let containerView = window?.contentView {
            let hostingView = NSHostingView(rootView: AnyView(GameLaunchErrorOverlay(
                windowController: self
            ).environment(SystemDatabaseWrapper.shared)))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.wantsLayer = true
            containerView.addSubview(hostingView, positioned: .above, relativeTo: nil)

            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])

            errorOverlayView = hostingView
        }
    }

    @MainActor
    func dismissErrorAndClose() {
        if launchError == .coreServiceCrashed {
            XPCConnectionManager.isShuttingDown = true
        }
        skipAutoSaveOnClose = true
        window?.close()
    }
    
    init(runner: EmulatorRunner) {
        self.runner = runner
        
        // Load auto-fullscreen setting
        autoFullscreenEnabled = AppSettings.getBool("autoFullscreenEnabled", defaultValue: false)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask:[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        
        window.center()
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        
super.init(window: window)
        window.delegate = self

        runner.onSaveStateSaved = { [weak self] slot in
            guard let self else { return }
            self.persistFightOverlayStateForSlot(slot)
        }
        runner.onSaveStateLoaded = { [weak self] slot in
            guard let self else { return }
            self.restoreFightOverlayStateForSlot(slot)
        }
        runner.onGameReset = { [weak self] in
            guard let self else { return }
            clearFightOverlayGameState()
            moveListViewModel.deactivate()
            removeMoveListOverlay()
            TrainingModeManager.shared.isMenuVisible = false
            trainingModeOverlayView?.removeFromSuperview()
            trainingModeOverlayView = nil
            TrainingModeManager.shared.setEnabled(false)
        }

        setupMetalView()
        setupInputCaptureHotkey()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupMetalView() {
        guard let runner = self.runner else { return }
        
        LoggerService.info(category: "Metal", "Setting up MetalView...")
        let mtkView = FocusableMTKView()
        mtkView.windowController = self
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)  // Transparent clear color
        mtkView.isPaused = true  // Start paused until game is launched
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoResizeDrawable = true
        // Make the Metal view's layer transparent so bezel shows through
        mtkView.wantsLayer = true
        mtkView.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.layer?.isOpaque = false  // Important: layer must be non-opaque for transparency
        if let metalLayer = mtkView.layer as? CAMetalLayer {
            metalLayer.framebufferOnly = false  // Required for blit reading drawable texture during recording
        }
        
        let coord = MetalCoordinator(runner: runner)
        mtkView.delegate = coord
        self.coordinator = coord
        self.metalView = mtkView
        runner.setMetalCoordinator(coord)

        // Set runner reference on view
        mtkView.runner = runner
        runner.metalView = mtkView
        
        // Create container view with overlay and mouse tracking
        let containerView = GameContainerView(frame: mtkView.bounds)
        containerView.windowController = self
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        // Black background on container shows through where Metal view doesn't cover
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        
        // Metal view will be sized dynamically based on bezel playable area
        // Use autoresizing so it tracks containerView size (overridden when bezel loads)
        mtkView.frame = containerView.bounds
        mtkView.autoresizingMask = [.width, .height]
        containerView.addSubview(mtkView)
        
        // Force update tracking areas
        containerView.updateTrackingAreas()
        
        // Add achievement toast overlay first (behind toolbar)
        let toastOverlay = SafeHostingView(rootView: AnyView(
            AchievementToastOverlay()
                .environment(SystemDatabaseWrapper.shared)
        ))
        toastOverlay.translatesAutoresizingMaskIntoConstraints = false
        toastOverlay.wantsLayer = true
        toastOverlay.layer?.backgroundColor = .clear
        toastOverlay.isPassThroughOverlay = true
        containerView.addSubview(toastOverlay)
        self.achievementToastOverlayView = toastOverlay

        NSLayoutConstraint.activate([
            toastOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toastOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toastOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            toastOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Add SwiftUI overlay toolbar (on top of toast overlay so clicks are not intercepted)
        let hostingView = SafeHostingView(rootView: AnyView(GameOverlayToolbar(
            runner: runner,
            windowController: self
        ).environment(SystemDatabaseWrapper.shared)))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        containerView.addSubview(hostingView)
        self.toolbarView = hostingView
        
        // Position toolbar at bottom center
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])

        // Separate full-size overlay for escape toast (passes through clicks to game below)
        let escapeToastView = SafeHostingView(rootView: AnyView(EscapeToastOverlay()))
        escapeToastView.translatesAutoresizingMaskIntoConstraints = false
        escapeToastView.wantsLayer = true
        escapeToastView.isPassThroughOverlay = true
        escapeToastView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(escapeToastView, positioned: .below, relativeTo: hostingView)
        self.escapeToastOverlayView = escapeToastView

        NSLayoutConstraint.activate([
            escapeToastView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            escapeToastView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            escapeToastView.topAnchor.constraint(equalTo: containerView.topAnchor),
            escapeToastView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Separate full-size overlay for cheat toggle toasts (passes through clicks to game below)
        let cheatToastView = SafeHostingView(rootView: AnyView(CheatToastOverlay()))
        cheatToastView.translatesAutoresizingMaskIntoConstraints = false
        cheatToastView.wantsLayer = true
        cheatToastView.isPassThroughOverlay = true
        cheatToastView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(cheatToastView, positioned: .below, relativeTo: hostingView)
        self.cheatToastOverlayView = cheatToastView

        NSLayoutConstraint.activate([
            cheatToastView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cheatToastView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cheatToastView.topAnchor.constraint(equalTo: containerView.topAnchor),
            cheatToastView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Screenshot flash backdrop — lightweight NSView (SwiftUI hosting here caused layout issues)
        let flashView = NSView()
        flashView.translatesAutoresizingMaskIntoConstraints = false
        flashView.wantsLayer = true
        flashView.isHidden = true
        flashView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        containerView.addSubview(flashView, positioned: .above, relativeTo: nil)
        self.screenshotFlashOverlayView = flashView

        NSLayoutConstraint.activate([
            flashView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            flashView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            flashView.topAnchor.constraint(equalTo: containerView.topAnchor),
            flashView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Screenshot pill overlay (in-game notification)
        let pillView = SafeHostingView(rootView: AnyView(ScreenshotPillOverlay()))
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.wantsLayer = true
        pillView.isPassThroughOverlay = true
        pillView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(pillView, positioned: .below, relativeTo: hostingView)
        self.screenshotPillOverlayView = pillView

        NSLayoutConstraint.activate([
            pillView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pillView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            pillView.topAnchor.constraint(equalTo: containerView.topAnchor),
            pillView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Recording badge overlay (REC indicator with timer)
        let badgeView = SafeHostingView(rootView: AnyView(RecordingBadgeOverlay()))
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.wantsLayer = true
        badgeView.isPassThroughOverlay = true
        badgeView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(badgeView, positioned: .below, relativeTo: hostingView)
        self.recordingBadgeOverlayView = badgeView

        NSLayoutConstraint.activate([
            badgeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            badgeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            badgeView.topAnchor.constraint(equalTo: containerView.topAnchor),
            badgeView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // OSD message overlay (centered top, shows runner.osdMessage)
        let osdView = SafeHostingView(rootView: AnyView(GameOSDOverlay(runner: runner)))
        osdView.translatesAutoresizingMaskIntoConstraints = false
        osdView.wantsLayer = true
        osdView.isPassThroughOverlay = true
        osdView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(osdView, positioned: .above, relativeTo: nil)
        self.osdOverlayView = osdView

        NSLayoutConstraint.activate([
            osdView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            osdView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            osdView.topAnchor.constraint(equalTo: containerView.topAnchor),
            osdView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Time machine / rewind bar overlay (bottom, shows scrubber + speed indicator)
        let timeBarView = SafeHostingView(rootView: AnyView(GameTimeBarOverlay(runner: runner)))
        timeBarView.translatesAutoresizingMaskIntoConstraints = false
        timeBarView.wantsLayer = true
        // Allow the slider/buttons in this overlay to receive clicks while
        // empty regions pass through to the game view below.
        timeBarView.isPassThroughOverlay = false
        timeBarView.passesThroughEmptyAreas = true
        timeBarView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(timeBarView, positioned: .above, relativeTo: osdView)
        self.timeBarOverlayView = timeBarView

        NSLayoutConstraint.activate([
            timeBarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            timeBarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            timeBarView.topAnchor.constraint(equalTo: containerView.topAnchor),
            timeBarView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Add SwiftUI loading overlay (covers entire window during game launch, on top of everything)
    let loadingView = SafeHostingView(rootView: AnyView(GameLoadingOverlay(
        windowController: self
    ).environment(SystemDatabaseWrapper.shared)))
    loadingView.translatesAutoresizingMaskIntoConstraints = false
    loadingView.wantsLayer = true
    containerView.addSubview(loadingView, positioned: .above, relativeTo: nil)
    self.loadingOverlayView = loadingView

    NSLayoutConstraint.activate([
        loadingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        loadingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        loadingView.topAnchor.constraint(equalTo: containerView.topAnchor),
        loadingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
    ])

    window?.contentView = containerView
        window?.acceptsMouseMovedEvents = true
        
        // Update fullscreen state on window changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen),
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        
        // Observe window resize to dynamically scale bezel
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onWindowResized()
        }
        
        // Observe window did move to handle screen changes
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onWindowMoved()
        }
        
        // Initially hide toolbar after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.hideToolbar()
        }

        // Observe input capture state changes to hide/show toolbar and sidebar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInputCaptureStateChanged),
            name: .inputCaptureStateChanged,
            object: nil
        )

        // Observe R3 guide toggle from controller
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleGuideSidebar),
            name: .toggleGuideSidebar,
            object: nil
        )

        // Gamepad toolbar navigation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGamepadShowToolbar),
            name: .gamepadShowGameToolbar,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGamepadToolbarSelect),
            name: .gamepadToolbarSelect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGamepadToolbarLeft),
            name: .gamepadToolbarNavigateLeft,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGamepadToolbarRight),
            name: .gamepadToolbarNavigateRight,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGamepadToolbarCancel),
            name: .gamepadToolbarCancel,
            object: nil
        )

        // Pause emulation when hardcore confirmation is shown, show overlay, resume on dismiss
        NotificationCenter.default.addObserver(
            forName: .hardcoreConfirmationRequired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showHardcoreViolationAlert()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .hardcoreConfirmationDismissed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hideHardcoreViolationAlert()
            }
        }

  // Start cursor auto-hide after initial setup delay
  DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
    let isFullscreen = self?.window?.styleMask.contains(.fullScreen) ?? false
    CursorAutoHideManager.shared.startMonitoring(isFullscreen: isFullscreen)
  }

  LoggerService.info(category: "Metal", "MetalView setup complete, isPaused=true")
}
    
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard isWaitingForFullscreenAnimation else { return }
        isWaitingForFullscreenAnimation = false

        // Remove the state-load overlay that was added in onFirstFrameReady (if any),
        // since we'll repurpose the fullscreen overlay as the new state-load overlay.
        // Without this, the original overlay stays in the view hierarchy forever,
        // covering the game and toolbar with a permanent black screen.
        let existingStateOverlay = stateLoadOverlayView
        stateLoadOverlayView = nil

        // If a state will be loaded, repurpose the fullscreen overlay as the state-load overlay
        // so the game stays hidden until the state is restored
        let slotToLoad = pendingSlotToLoad
        let willLoadState: Bool
        if slotToLoad != nil {
            willLoadState = true
        } else {
            let shouldAutoLoad = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: true) && !HardcoreModeManager.shared.isHardcoreActive
            if shouldAutoLoad && !isDolphinCore() {
                willLoadState = true
            } else {
                willLoadState = false
            }
        }

        if willLoadState {
            existingStateOverlay?.removeFromSuperview()
            stateLoadOverlayView = fullscreenOverlayView
            fullscreenOverlayView = nil
            runner?.isPaused = true
            XPCBridgeAdapter.shared.setPaused(true)
        } else {
            existingStateOverlay?.removeFromSuperview()
            fullscreenOverlayView?.removeFromSuperview()
            fullscreenOverlayView = nil
        }

        // Load bezel after fullscreen animation completes (prevents warped bezel during transition)
        Task { @MainActor in
            if let systemID = self.pendingSystemID, let romForBezel = self.pendingROMForBezel {
                await self.loadBezelForGame(systemID: systemID, rom: romForBezel)
            }
            // Fullscreen animation complete — proceed with save state loading
            if let rom = self.pendingROMForState {
                self.loadSaveStatesAfterLaunch(slotToLoad: self.pendingSlotToLoad, rom: rom)
            } else if willLoadState {
                // State was expected but pendingROMForState is nil — reveal anyway
                self.revealAfterStateLoad()
            }
        }
    }

    @objc private func windowDidChangeScreen() {
        DispatchQueue.main.async { [weak self] in
            let isFullscreen = self?.window?.styleMask.contains(.fullScreen) ?? false
            self?.isFullscreen = isFullscreen

            // Update cursor auto-hide fullscreen state
            CursorAutoHideManager.shared.updateFullscreenState(isFullscreen: isFullscreen)

            // Rescale bezel for new screen
            self?.onWindowMoved()
        }
    }

    @objc private func handleInputCaptureStateChanged(_ notification: Notification) {
        let isCapturing = notification.userInfo?["isCapturing"] as? Bool ?? false
        if isCapturing {
            hideToolbarImmediateForCapture()
            if gameGuideViewModel.isSidebarVisible {
                gameGuideViewModel.deactivate()
                guideSidebarView?.removeFromSuperview()
                guideSidebarView = nil
            }
    } else {
        showToolbarAfterCapture()
    }
    }

    @objc private func handleToggleGuideSidebar() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.gameGuideViewModel.hasGuideData else { return }
            self.toggleGuideSidebar()
        }
    }

    @objc private func handleGamepadShowToolbar() {
        DispatchQueue.main.async { [weak self] in
            self?.showGamepadToolbar()
        }
    }

    @objc private func handleGamepadToolbarSelect() {
        DispatchQueue.main.async { [weak self] in
            self?.gamepadToolbarActivateFocusedButton()
        }
    }

    @objc private func handleGamepadToolbarLeft() {
        DispatchQueue.main.async { [weak self] in
            self?.gamepadToolbarNavigateLeft()
        }
    }

    @objc private func handleGamepadToolbarRight() {
        DispatchQueue.main.async { [weak self] in
            self?.gamepadToolbarNavigateRight()
        }
    }

    @objc private func handleGamepadToolbarCancel() {
        DispatchQueue.main.async { [weak self] in
            self?.exitGamepadToolbarMode()
        }
    }
    
    // Toggle macOS native fullscreen mode
    @MainActor
    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
        isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
    }
    
    // Toggle auto-fullscreen setting
    @MainActor
    func toggleAutoFullscreen() {
        autoFullscreenEnabled.toggle()
        AppSettings.setBool("autoFullscreenEnabled", value: autoFullscreenEnabled)
        // Also enter fullscreen when enabling
        if autoFullscreenEnabled && !isFullscreen {
            toggleFullscreen()
        }
    }
    
    @MainActor
    private func showMAMEDependenciesAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Missing ROM Files"
        
        // Try to get game name from pendingROM
        var gameName = "this MAME game"
        if let rom = pendingROM {
            gameName = "\"\(rom.displayName)\""
        }
        
        alert.informativeText = "\(gameName) requires additional ROM files that were not found (parent ROM, samples, etc.).\n\nCheck the Game Info tab to see which files are required and missing."
        
        alert.addButton(withTitle: "OK")
        
        alert.runModal()
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
    }
    
    // MARK: - Normal Launch
    
    func launch(rom: ROM, coreID: String, slotToLoad: Int? = nil, progressiveVersion: Int? = nil, shaderUniformOverrides: [String: Float] = [:]) {
        // Store shader uniforms for later use in _doLaunch
        self.pendingShaderUniforms = shaderUniformOverrides
        LoggerService.info(category: "GameLauncher", "launch() received \(shaderUniformOverrides.count) shader uniforms, key shellColorIndex=\(shaderUniformOverrides["shellColorIndex"] ?? -1)")
        
        // Check if this same ROM is already running in another window
        if RunningGamesTracker.shared.isRunning(romPath: rom.runningKey) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            window?.close()
            return
        }
        
    // Register this ROM as running
        RunningGamesTracker.shared.registerRunning(romPath: rom.runningKey, displayName: rom.displayName)
        trackedROMPath = rom.runningKey
    trackedROM = rom
    accumulatedPlaytime = 0
    startPlaytimeTracking()

    // Show loading state and display window immediately
    isLoading = true
    currentGameROM = rom
    pendingSystemID = rom.systemID ?? "default"
    pendingROMForBezel = rom
        window?.title = "TruchiEmu - " + rom.displayName
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        moveListViewModel.loadForGame(rom)
gameGuideViewModel.loadForGame(rom)

        let trainingManager = TrainingModeManager.shared
        let systemID = rom.systemID ?? "default"
        let trainingGameData = moveListViewModel.moveListService.currentGameData
        let trainingLayout = trainingGameData.map { ArcadeButtonMapper.shared.arcadeLayout(for: $0) } ?? .capcom6
        trainingManager.activate(for: trainingGameData, systemID: systemID, coreID: coreID, layout: trainingLayout)
        if let runner = self.runner {
            trainingManager.inputManager.attachToRunner(runner)
            trainingManager.syncFrameDriver()
            trainingManager.inputManager.onP1InputUpdate = { [weak self] buttons, frameIndex in
                guard let self else { return }
                let entry = TrainingModeOverlayViewModel.InputHistoryEntry(
                    directions: buttons.filter { $0.isDirectional },
                    buttons: buttons.filter { !$0.isDirectional },
                    frameIndex: frameIndex
                )
                self.trainingModeViewModel.p1InputHistory.append(entry)
                if self.trainingModeViewModel.p1InputHistory.count > TrainingModeOverlayViewModel.maxHistoryEntries {
                    self.trainingModeViewModel.p1InputHistory.removeFirst()
                }
            }

            // While Time Machine scrub mode is active, hide the game toolbar so
            // it doesn't overlap the timeline. When scrub mode exits, the
            // toolbar auto-shows on the next mouse move via onMouseActivity.
            timeMachineCancellable = runner.$isRewinding
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isRewinding in
                    guard let self else { return }
                    if isRewinding {
                        self.hideToolbarImmediateForCapture()
                    }
                }
        }

        // Observe P2 join state to show/hide status overlay on game window
        p2JoinStatusCancellable = TrainingModeManager.shared.$p2JoinPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }
                if phase > 0 {
                    installP2JoinStatusOverlay()
                } else {
                    removeP2JoinStatusOverlay()
                }
            }

        trainingConfigCancellable = TrainingModeManager.shared.$config
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.isClosingWindow else { return }
                Task { @MainActor in
                    self.persistFightOverlayState()
                }
            }

        // Store progressive version for later use in loadSaveStatesAfterLaunch
        pendingProgressiveVersion = progressiveVersion

        // Proceed with launch (bezel is loaded after first frame is ready)
        GameLauncher.shared.launchPhase = .loadingCore
        _doLaunch(rom: rom, coreID: coreID, slotToLoad: slotToLoad)
    }
    
    // Store pending shader uniforms
    private var pendingShaderUniforms: [String: Float] = [:]
    
private func _doLaunch(rom: ROM, coreID: String, slotToLoad: Int? = nil) {

        // Store ROM reference before launching (used by toolbar + cheat manager)
        runner?.rom = rom
    runner?.romPath = rom.path.path
        
        // Unpause the metal view and start emulation
        metalView?.isPaused = false
        
        // Use pending shader uniforms from launch parameters
        let shaderUniforms = pendingShaderUniforms
        
        // Enable Game Mode before launching the game (must be set before game process starts)
        GameModeManager.shared.start()

        // Launch the game with current shader uniforms
        runner?.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniforms)
        // Observe game-loaded notification to update launch phase
        gameLoadedObserver = NotificationCenter.default.addObserver(forName: .gameLoaded, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isLoading {
                    GameLauncher.shared.launchPhase = .startingGame
                }
                GamepadNavigationManager.shared.setGameRunning(true)
                let ctx = GamepadGameRunningContext(onShowToolbar: { [weak self] in
                    self?.showGamepadToolbar()
                })
                ctx.ownedWindow = self.window
                self.gameRunningNavContext = ctx
                GamepadNavContextStack.shared.push(ctx)
            }
        }

                // Observe screenshot captures to flash + show toast
        screenshotObserver = NotificationCenter.default.addObserver(forName: .screenshotTaken, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let url = note.userInfo?["url"] as? URL else { return }
            let nativeURL = note.userInfo?["nativeURL"] as? URL
            self.flashScreen()
            self.postScreenshotPill(displayURL: url, nativeURL: nativeURL)
            self.postScreenshotHistory(displayURL: url, nativeURL: nativeURL)
        }

        // Observe clip saved to show toast
        clipSavedObserver = NotificationCenter.default.addObserver(forName: .clipSaved, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            self?.postClipSavedPill(url: url)
        }

        // Core is initializing async — we're now waiting for the first frame
        // Dispatch async so SwiftUI gets a render opportunity to show "Loading core..." first
        if isLoading {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isLoading else { return }
                GameLauncher.shared.launchPhase = .waitingForFrame
            }
        }

        // Disable save states for Dolphin cores due to known serialization crash
        saveStatesDisabled = isDolphinCore()
        if saveStatesDisabled {
            LoggerService.info(category: "SaveState", "Save states disabled for Dolphin core (known crash issue)")
        }

        // Start input capture for DOS/ScummVM games immediately upon launch
        if let window = window, let systemID = rom.systemID?.lowercased(), (systemID == "dos" || systemID == "scummvm") {
            InputCaptureManager.shared.startCapture(window: window)
        }
        
        // Check if runner is running
        if !(runner?.isRunning ?? false) {
            LoggerService.error(category: "Runner", "Runner is not running after launch")
            DispatchQueue.main.async { [weak self] in
                self?.showErrorOverlay(.runnerStopped)
            }
            return
        }
        
        // Load cheats for the ROM (apply is deferred until after first frame)
        if cheatsEnabled && !HardcoreModeManager.shared.areCheatsBlocked {
            CheatManagerService.shared.loadCheatsForROM(rom)
        }
        
        // Make sure the metal view is the first responder
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.metalView)
        }
        
        // Wait for the first frame before showing the window (prevents bezel flash)
        waitForFirstFrameAndShowWindow(slotToLoad: slotToLoad, rom: rom)
    }
    
    // Wait for the first frame to be rendered before dismissing the loading overlay.
    private func waitForFirstFrameAndShowWindow(slotToLoad: Int?, rom: ROM) {
        var attempts = 0
        let maxAttempts = 100 // 10 seconds at 100ms intervals

        firstFrameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            attempts += 1
            let state = MainActor.assumeIsolated { (self.runner?.isReadyForDisplay ?? false, self.runner?.lastError != nil, self.runner?.isRunning ?? false) }
            let isReady = state.0
            let hasError = state.1
            let isRunning = state.2
            let timedOut = attempts >= maxAttempts

            if isReady || hasError || !isRunning || timedOut {
                timer.invalidate()
                self.firstFrameTimer = nil

            if !isReady {
                let errorToDisplay: GameError? = MainActor.assumeIsolated { self.runner?.lastError }

                if hasError {
                    LoggerService.error(category: "Runner", "Core failed during launch, closing window immediately")
                } else if !isRunning {
                    LoggerService.error(category: "Runner", "Runner stopped unexpectedly, closing window")
                } else {
                    LoggerService.info(category: "Runner", "Timeout waiting for first frame, closing window")
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if XPCConnectionManager.isShuttingDown {
                        self.showErrorOverlay(.coreServiceCrashed)
                    } else if let error = errorToDisplay {
                        self.showErrorOverlay(.launchFailed(reason: error.localizedDescription))
                    } else if timedOut {
                        self.showErrorOverlay(.timeout)
                    } else {
                        self.showErrorOverlay(.launchFailed(reason: ""))
                    }
                }
                } else {
                    self.onFirstFrameReady(slotToLoad: slotToLoad, rom: rom)
                }
            }
        }
    }

    // First frame is ready — dismiss loading overlay and prepare the window.
    private func onFirstFrameReady(slotToLoad: Int?, rom: ROM) {
        isLoading = false
        GameLauncher.shared.launchPhase = .idle

        // Apply cheats now that the core has initialized its memory map
        // (PicoDrive crashes if retro_cheat_set is called before the first retro_run)
        if cheatsEnabled && !HardcoreModeManager.shared.areCheatsBlocked {
            let enabledCheats = CheatManagerService.shared.enabledCheats(for: rom)
            if !enabledCheats.isEmpty {
                let cheatData = enabledCheats.map { cheat in [
                    "index": cheat.index,
                    "code": cheat.code,
                    "enabled": cheat.enabled
                ] as [String: Any] }
                XPCBridgeAdapter.shared.applyCheats(cheatData)
                CheatManagerService.shared.areCheatsApplied = true
                if SystemPreferences.shared.showCheatNotifications {
                    LoggerService.info(category: "Cheats", "Auto-applied \(enabledCheats.count) cheat(s) for \(rom.displayName)")
                }
            }
        }

        // Determine if a state will be loaded (specific slot or auto-load enabled with saves)
        let willLoadState: Bool
        if slotToLoad != nil {
            willLoadState = true
        } else {
            let shouldAutoLoad = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: true) && !HardcoreModeManager.shared.isHardcoreActive
            if shouldAutoLoad && !isDolphinCore() {
                let systemID = rom.systemID ?? "default"
                let gameName = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
                let allSlots = runner?.saveManager.allSlotInfo(gameName: gameName, systemID: systemID) ?? []
                willLoadState = allSlots.contains { $0.exists }
            } else {
                willLoadState = false
            }
        }

        if willLoadState {
            // Add a black overlay to hide the game until the state is loaded
            if let containerView = window?.contentView {
                let overlay = NSView(frame: containerView.bounds)
                overlay.wantsLayer = true
                overlay.layer?.backgroundColor = NSColor.black.cgColor
                overlay.autoresizingMask = [.width, .height]
                containerView.addSubview(overlay, positioned: .above, relativeTo: nil)
                stateLoadOverlayView = overlay
            }
            // Pause the runner so the game doesn't advance before state load
            runner?.isPaused = true
            XPCBridgeAdapter.shared.setPaused(true)
        }

        // Remove loading overlay after fade-out animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.loadingOverlayView?.removeFromSuperview()
            self?.loadingOverlayView = nil
        }

        showWindowAndLoadSlot(slotToLoad: slotToLoad, rom: rom)
    }

    // Show the window and handle save state loading.
    private func showWindowAndLoadSlot(slotToLoad: Int?, rom: ROM) {
        if autoFullscreenEnabled {
            // Create a black overlay starting fully transparent so we can fade
            // to black before the fullscreen animation, masking the warping effect.
            if let containerView = window?.contentView {
                let overlay = NSView(frame: containerView.bounds)
                overlay.wantsLayer = true
                overlay.alphaValue = 0
                overlay.layer?.backgroundColor = NSColor.black.cgColor
                overlay.autoresizingMask = [.width, .height]
                containerView.addSubview(overlay, positioned: .above, relativeTo: nil)
                fullscreenOverlayView = overlay
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.fullscreenOverlayView?.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                guard let self = self else { return }
                self.pendingSlotToLoad = slotToLoad
                self.pendingROMForState = rom
                self.isWaitingForFullscreenAnimation = true
                Task { @MainActor in
                    self.toggleFullscreen()
                }
            }
            return
        }

        // Load bezel now (non-fullscreen path — bezel loads after first frame)
        Task { @MainActor in
            if let systemID = self.pendingSystemID, let romForBezel = self.pendingROMForBezel {
                await self.loadBezelForGame(systemID: systemID, rom: romForBezel)
            }
            self.loadSaveStatesAfterLaunch(slotToLoad: slotToLoad, rom: rom)
        }
    }

    // Load save states after the window is ready (either immediately or after fullscreen animation).
    private func loadSaveStatesAfterLaunch(slotToLoad: Int?, rom: ROM) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, let runner = self.runner else { return }
            let systemID = rom.systemID ?? "default"
            let gameName = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
            self.didLoadSaveState = false

            var loadedSlot: Int?

            if let slotToLoad = slotToLoad, !HardcoreModeManager.shared.areSaveStatesBlocked {
                // Load a specific slot
                let progVersion = self.pendingProgressiveVersion
                self.pendingProgressiveVersion = nil

                if let progVersion = progVersion {
                    let stateURL = runner.saveManager.progressiveStatePath(gameName: gameName, systemID: systemID, slot: slotToLoad, version: progVersion)
                    if FileManager.default.fileExists(atPath: stateURL.path) {
                        LoggerService.info(category: "SaveState", "Found progressive save #\(progVersion) at: \(stateURL.path)")
                        let success = runner.loadState(from: stateURL)
                        if success {
                            self.didLoadSaveState = true
                            loadedSlot = slotToLoad
                            LoggerService.info(category: "SaveState", "Successfully loaded save state from slot \(slotToLoad) v\(progVersion)")
                        } else {
                            #if LOG_DEBUG
                            LoggerService.debug(category: "SaveState", "Failed to load save state from slot \(slotToLoad) v\(progVersion)")
                            #endif
                        }
                    } else {
                        #if LOG_DEBUG
                        LoggerService.debug(category: "SaveState", "No save state found at: \(stateURL.path)")
                        #endif
                    }
                } else {
                    let versions = runner.saveManager.progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slotToLoad)
                    if !versions.isEmpty {
                        var newestVersion = versions[0]
                        var newestDate: Date? = nil
                        for v in versions {
                            let info = runner.saveManager.progressiveSlotInfo(gameName: gameName, systemID: systemID, slot: slotToLoad, version: v)
                            if info.exists, let date = info.modificationDate, date > (newestDate ?? .distantPast) {
                                newestDate = date
                                newestVersion = v
                            }
                        }
                        let stateURL = runner.saveManager.progressiveStatePath(gameName: gameName, systemID: systemID, slot: slotToLoad, version: newestVersion)
                        let success = runner.loadState(from: stateURL)
                        if success {
                            self.didLoadSaveState = true
                            loadedSlot = slotToLoad
                            runner.osdMessage = "Loaded Slot \(slotToLoad) #\(newestVersion)"
                            LoggerService.info(category: "SaveState", "Successfully loaded save state from slot \(slotToLoad) v\(newestVersion)")
                        } else {
                            #if LOG_DEBUG
                            LoggerService.debug(category: "SaveState", "Failed to load save state from slot \(slotToLoad)")
                            #endif
                        }
                    }
                }
            } else {
                // Auto-load: find the most recent save across all slots
                let shouldAutoLoad = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: true) && !HardcoreModeManager.shared.isHardcoreActive
                if shouldAutoLoad {
                    if self.isDolphinCore() {
                        LoggerService.info(category: "SaveState", "Auto-load disabled for Dolphin core (known crash issue)")
                    } else {
                        var mostRecentURL: URL?
                        var mostRecentSlot: Int?
                        var mostRecentDate: Date = .distantPast

                        let allSlots = runner.saveManager.allSlotInfo(gameName: gameName, systemID: systemID)
                        for slotInfo in allSlots {
                            let versions = runner.saveManager.progressiveSlotVersions(gameName: gameName, systemID: systemID, slot: slotInfo.id)
                            for v in versions {
                                let info = runner.saveManager.progressiveSlotInfo(gameName: gameName, systemID: systemID, slot: slotInfo.id, version: v)
                                if info.exists, let date = info.modificationDate, date > mostRecentDate {
                                    mostRecentDate = date
                                    mostRecentSlot = slotInfo.id
                                    mostRecentURL = runner.saveManager.progressiveStatePath(gameName: gameName, systemID: systemID, slot: slotInfo.id, version: v)
                                }
                            }
                            // Fallback: check base file if no progressive versions
                            if slotInfo.exists, let date = slotInfo.modificationDate, date > mostRecentDate {
                                mostRecentDate = date
                                mostRecentSlot = slotInfo.id
                                mostRecentURL = runner.saveManager.statePath(gameName: gameName, systemID: systemID, slot: slotInfo.id)
                            }
                        }

                        if let url = mostRecentURL {
                            LoggerService.info(category: "SaveState", "Found most recent save at: \(url.path)")
                            let success = runner.loadState(from: url)
                            if success {
                                self.didLoadSaveState = true
                                loadedSlot = mostRecentSlot
                                runner.osdMessage = "Auto-loaded most recent save"
                                LoggerService.info(category: "SaveState", "Successfully loaded most recent save")
                            } else if self.isDOSCore() {
                                runner.osdMessage = LocalizationManager.shared.localized("slot.dosAutoLoadFailed")
                                LoggerService.info(category: "SaveState", "DOS auto-load failed: DOSBox Pure start menu is enabled")
                                Task { [weak self] in
                                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                                    await MainActor.run { self?.runner?.osdMessage = nil }
                                }
                            }
                        } else {
                            #if LOG_DEBUG
                            LoggerService.debug(category: "SaveState", "No save states found for auto-load")
                            #endif
                        }
                    }
                }
            }

            // Reveal the game: remove black overlay and resume emulation
            self.revealAfterStateLoad(loadedSlot: loadedSlot)
        }
    }

    private func revealAfterStateLoad(loadedSlot: Int? = nil) {
        // Restore fight overlay state before resuming (only after a save state was loaded)
        if didLoadSaveState {
            if let slot = loadedSlot {
                restoreFightOverlayStateForSlot(slot)
            } else {
                restoreFightOverlayState()
            }
        }

        // Resume emulation
        runner?.isPaused = false
        XPCBridgeAdapter.shared.setPaused(false)
        metalView?.isPaused = false
        metalView?.needsDisplay = true

        // Fade out the state-load overlay and remove it from the view hierarchy.
        // Must use a local reference — stateLoadOverlayView must not be cleared
        // before the completion handler fires, otherwise removeFromSuperview
        // never executes and the overlay blocks toolbar interactions permanently.
        if let overlay = stateLoadOverlayView {
            stateLoadOverlayView = nil
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                overlay.animator().alphaValue = 0
            } completionHandler: {
                overlay.removeFromSuperview()
            }
        }
    }

    // MARK: - Hardcore Mode Confirmation Overlay

    @MainActor
    private func showHardcoreViolationAlert() {
        guard let containerView = window?.contentView else { return }
        runner?.isPaused = true
        metalView?.isPaused = true
        XPCBridgeAdapter.shared.setPaused(true)

        let alertView = SafeHostingView(rootView: AnyView(HardcoreViolationAlert().environment(SystemDatabaseWrapper.shared)))
        alertView.autoresizingMask = [.width, .height]
        alertView.frame = containerView.bounds
        alertView.wantsLayer = true
        containerView.addSubview(alertView, positioned: .above, relativeTo: nil)

        hardcoreAlertOverlayView = alertView
    }

    @MainActor
    private func hideHardcoreViolationAlert() {
        hardcoreAlertOverlayView?.removeFromSuperview()
        hardcoreAlertOverlayView = nil
        runner?.isPaused = false
        metalView?.isPaused = false
        XPCBridgeAdapter.shared.setPaused(false)
    }

    // MARK: - Cheats
    
    // Present the cheat manager as a sheet on this game window.
    // Pauses the game while the cheat manager is shown.
    @MainActor
    func showCheatManager() {
        guard currentGameROM != nil, window != nil else { return }

        _ = HardcoreModeManager.shared.attemptUseCheats { [weak self] in
            self?.presentCheatManagerSheet()
        }
    }

    @MainActor
    func presentCheatManagerSheet() {
        guard let rom = currentGameROM, let window = window else { return }

        // Don't show if already showing
        guard cheatManagerSheetWindow == nil else { return }
        
        // Pause the game while sheet is shown
        runner?.togglePause()
        
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask:[.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "Cheats - \(rom.displayName)"
        sheetWindow.isReleasedWhenClosed = true
        sheetWindow.contentView = SafeHostingView(rootView:
            CheatManagerViewWrapper(rom: rom, windowController: self)
                .environment(SystemDatabaseWrapper.shared)
        )
        
        cheatManagerSheetWindow = sheetWindow
        
        window.beginSheet(sheetWindow) { [weak self] _ in
            Task { @MainActor in
                self?.cheatManagerSheetWindow = nil
                // Resume the game if it was paused for the sheet
            self?.runner?.isPaused = false
            XPCBridgeAdapter.shared.setPaused(false)
            }
        }
    }
    
    // Dismiss the cheat manager sheet.
    @MainActor
    func dismissCheatManager() {
        guard let sheetWindow = cheatManagerSheetWindow, let window = window else { return }
        window.endSheet(sheetWindow)
        cheatManagerSheetWindow = nil
        runner?.isPaused = false
        XPCBridgeAdapter.shared.setPaused(false)
    }

    @MainActor
    func toggleMoveListOverlay() {
        if moveListViewModel.isOverlayVisible || moveListViewModel.needsCharacterSelection {
            trainingModeViewModel.enabledCharacterName = nil
            MoveListService.shared.clearSelectedCharacter()
            removeMoveListOverlay()
            if runner?.isPaused == true {
                runner?.isPaused = false
                XPCBridgeAdapter.shared.setPaused(false)
            }
            showToolbar()
            persistFightOverlayState()
            return
        }

        runner?.isPaused = true
        XPCBridgeAdapter.shared.setPaused(true)

        moveListViewModel.activate()
        installMoveListOverlay()
        persistFightOverlayState()
    }

    @MainActor
    func confirmPendingCharacter() {
        moveListViewModel.confirmPendingCharacter()
        if let charName = moveListViewModel.enabledCharacterName {
            trainingModeViewModel.enabledCharacterName = charName
        }
        if moveListViewModel.isOverlayVisible {
            if runner?.isPaused == true {
                runner?.isPaused = false
                XPCBridgeAdapter.shared.setPaused(false)
            }
            persistFightOverlayState()
        }
    }

    @MainActor
    func confirmAndShowOverlay(character: FightDataCharacter) {
        moveListViewModel.confirmAndShowOverlay(character: character)
        trainingModeViewModel.enabledCharacterName = character.name
        if moveListViewModel.isOverlayVisible {
            if runner?.isPaused == true {
                runner?.isPaused = false
                XPCBridgeAdapter.shared.setPaused(false)
            }
            persistFightOverlayState()
        }
    }

    private func installMoveListOverlay() {
        guard moveListOverlayView == nil, let containerView = window?.contentView else { return }

        let hostingView = SafeHostingView(rootView: AnyView(
            MoveListOverlay(viewModel: moveListViewModel, windowController: self)
                .environment(SystemDatabaseWrapper.shared)
        ))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.passesThroughEmptyAreas = true
        // Insert above training overlay so move list panel is never behind it
        if let trainingView = trainingModeOverlayView {
            containerView.addSubview(hostingView, positioned: .above, relativeTo: trainingView)
        } else if let toolbar = toolbarView {
            containerView.addSubview(hostingView, positioned: .below, relativeTo: toolbar)
        } else {
            containerView.addSubview(hostingView, positioned: .above, relativeTo: nil)
        }
        self.moveListOverlayView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private func removeMoveListOverlay() {
        moveListViewModel.deactivate()
        moveListOverlayView?.removeFromSuperview()
        moveListOverlayView = nil
    }

    @MainActor
    func deselectCurrentCharacter() {
        trainingModeViewModel.enabledCharacterName = nil
        MoveListService.shared.clearSelectedCharacter()
        removeMoveListOverlay()
        persistFightOverlayState()
    }

    @MainActor
    func toggleTrainingModeOverlay() {
        let manager = TrainingModeManager.shared
        if manager.isMenuVisible {
            manager.toggleMenu()
            trainingModeOverlayView?.removeFromSuperview()
            trainingModeOverlayView = nil
            persistFightOverlayState()
            return
        }

        manager.toggleMenu()
        if manager.isMenuVisible {
            installTrainingModeOverlay()
        }
        persistFightOverlayState()
    }

    private func installTrainingModeOverlay() {
        guard trainingModeOverlayView == nil, let containerView = window?.contentView else { return }

        trainingModeViewModel.onCloseOverlay = { [weak self] in
            guard let self else { return }
            self.trainingModeOverlayView?.removeFromSuperview()
            self.trainingModeOverlayView = nil
            self.persistFightOverlayState()
        }

        trainingModeViewModel.onSelectCharacterAndShowMoves = { [weak self] in
            guard let self else { return }
            if self.moveListOverlayView != nil {
                self.removeMoveListOverlay()
            }
            if let character = MoveListService.shared.selectedCharacter {
                self.moveListViewModel.confirmCharacter(character)
                self.installMoveListOverlay()
            }
            self.persistFightOverlayState()
        }

        trainingModeViewModel.onDeselectCharacter = { [weak self] in
            guard let self else { return }
            self.removeMoveListOverlay()
            self.persistFightOverlayState()
        }

        trainingModeViewModel.onMoveListSettingsChanged = { [weak self] in
            guard let self else { return }
            self.moveListViewModel.refreshButtonKeyLabels()
        }

        trainingModeViewModel.onResetOverlayPosition = { [weak self] in
            guard self != nil else { return }
            AppSettings.setDouble("moveListPanelOffsetX", value: 0)
            AppSettings.setDouble("moveListPanelOffsetY", value: 0)
            NotificationCenter.default.post(name: .resetMoveListOverlayPosition, object: nil)
        }

        let toolbarH = toolbarView?.frame.height ?? 0
        trainingModeViewModel.toolbarBottomMargin = toolbarH + 20

        let hostingView = SafeHostingView(rootView: AnyView(
            TrainingModeOverlay(viewModel: trainingModeViewModel)
                .environment(SystemDatabaseWrapper.shared)
        ))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        if let toolbar = toolbarView {
            containerView.addSubview(hostingView, positioned: .below, relativeTo: toolbar)
        } else {
            containerView.addSubview(hostingView, positioned: .above, relativeTo: nil)
        }
self.trainingModeOverlayView = hostingView

NSLayoutConstraint.activate([
hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
])
}

    @MainActor
    func toggleGuideSidebar() {
        if gameGuideViewModel.isSidebarVisible {
            gameGuideViewModel.deactivate()
            guideSidebarView?.removeFromSuperview()
            guideSidebarView = nil
            // Re-start capture for DOS/ScummVM games when sidebar closes
            if let window = window, !InputCaptureManager.shared.isCapturing {
                if let mtkView = metalView, mtkView.shouldCaptureInputForCurrentGame() {
                    InputCaptureManager.shared.startCapture(window: window)
                }
            }
            return
        }
        if InputCaptureManager.shared.isCapturing {
            InputCaptureManager.shared.stopCapture(reason: "Guide sidebar opened")
        }
        gameGuideViewModel.activate()
        installGuideSidebar()
    }

    private func installGuideSidebar() {
        guard guideSidebarView == nil, let containerView = window?.contentView else { return }

        let hostingView = SafeHostingView(rootView: AnyView(
            GameGuideSidebar(viewModel: gameGuideViewModel, windowController: self)
        ))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

if let toolbar = toolbarView {
containerView.addSubview(hostingView, positioned: .below, relativeTo: toolbar)
} else {
containerView.addSubview(hostingView, positioned: .above, relativeTo: nil)
}
self.guideSidebarView = hostingView

NSLayoutConstraint.activate([
hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
hostingView.widthAnchor.constraint(equalToConstant: 320)
])
}

    @MainActor
    private func installP2JoinStatusOverlay() {
        guard p2JoinStatusOverlayView == nil, let containerView = window?.contentView else { return }

        let manager = TrainingModeManager.shared
        let hostingView = SafeHostingView(rootView: AnyView(
            P2JoinStatusOverlay(
                frameDriver: manager.frameDriver,
                isArcadeSystem: manager.isArcadeSystem
            )
        ))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        if let toolbar = toolbarView {
            containerView.addSubview(hostingView, positioned: .below, relativeTo: toolbar)
        } else {
            containerView.addSubview(hostingView, positioned: .above, relativeTo: nil)
        }
        self.p2JoinStatusOverlayView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    @MainActor
    private func removeP2JoinStatusOverlay() {
        p2JoinStatusOverlayView?.removeFromSuperview()
        p2JoinStatusOverlayView = nil
    }

    func windowWillClose(_ notification: Notification) {
        XPCBridgeAdapter.shared.setPaused(true)

        isClosingWindow = true
        
        // Clear per-game fight overlay keys so they don't leak into next launch.
        // Per-slot keys are intentionally kept (they're tied to specific save states).
        clearFightOverlayGameState()
        
        isWaitingForFullscreenAnimation = false
        fullscreenOverlayView?.removeFromSuperview()
        fullscreenOverlayView = nil
        stateLoadOverlayView?.removeFromSuperview()
        stateLoadOverlayView = nil
        loadingOverlayView?.removeFromSuperview()
        loadingOverlayView = nil
        hardcoreAlertOverlayView?.removeFromSuperview()
        hardcoreAlertOverlayView = nil
        errorOverlayView?.removeFromSuperview()
        errorOverlayView = nil
        p2JoinStatusOverlayView?.removeFromSuperview()
        p2JoinStatusOverlayView = nil
        p2JoinStatusCancellable = nil
        isLoading = false
        launchError = nil

        firstFrameTimer?.invalidate()
        firstFrameTimer = nil

        InputCaptureManager.shared.cleanup()

        TrainingModeManager.shared.setEnabled(false)
        TrainingModeManager.shared.inputManager.detachFromRunner()

        stopPlaytimeTracking()

        CursorAutoHideManager.shared.stopMonitoring()
        CursorAutoHideManager.shared.showCursor()

        let shouldAutoSave = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false) && !skipAutoSaveOnClose && !HardcoreModeManager.shared.areSaveStatesBlocked

        if shouldAutoSave {
            if isDolphinCore() {
                LoggerService.info(category: "SaveState", "Auto-save disabled for Dolphin core (known crash issue)")
            } else if let runner = runner {
                LoggerService.info(category: "SaveState", "Auto-saving on window close...")
                _ = runner.saveState(slot: -1)
            }
        }
        GameModeManager.shared.stop()
        runner?.stop()
        GamepadNavigationManager.shared.setGameRunning(false)
        if let ctx = gameRunningNavContext {
            GamepadNavContextStack.shared.remove(ctx)
            gameRunningNavContext = nil
        }
        if let ctx = gameToolbarNavContext {
            GamepadNavContextStack.shared.remove(ctx)
            gameToolbarNavContext = nil
        }

        if RetroAchievementsService.shared.isEnabled {
            RetroAchievementsService.shared.refreshGameCacheAfterGameStop()
        }

        if let rom = trackedROM, accumulatedPlaytime > 0 {
            library?.recordPlaySession(rom, duration: accumulatedPlaytime)
        }

        if let romPath = trackedROMPath {
            RunningGamesTracker.shared.unregisterRunning(romPath: romPath)
        }

	if let rom = trackedROM {
		GameLauncher.shared.removeController(for: rom.id)
	}

	onWindowWillClose?()

        detachSwiftUI()

        hideToolbarTimer?.invalidate()
        hideToolbarTimer = nil

        coordinator?.cleanup()
        coordinator = nil
        metalView?.delegate = nil
        metalView = nil
        runner = nil
        bezelImage = nil
        bezelBackgroundLayer = nil
        bezelViewModel = nil
        trackedROM = nil
        trackedROMPath = nil
        currentGameROM = nil
        pendingSystemID = nil
        pendingROMForBezel = nil

        NotificationCenter.default.removeObserver(self)

        if let monitor = inputCaptureHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            inputCaptureHotkeyMonitor = nil
        }

        if let observer = gameLoadedObserver {
            NotificationCenter.default.removeObserver(observer)
            gameLoadedObserver = nil
        }
        if let observer = screenshotObserver {
            NotificationCenter.default.removeObserver(observer)
            screenshotObserver = nil
        }
    }

    // MARK: - Helper Functions

    private func fightOverlayGameKey() -> String? {
        guard currentGameROM != nil, let gameData = moveListViewModel.moveListService.currentGameData else { return nil }
        return "fightOverlay_\(gameData.name)"
    }

    private func fightOverlaySlotKey(slot: Int) -> String? {
        guard let key = fightOverlayGameKey() else { return nil }
        return "\(key)_slot\(slot)"
    }

    private func clearFightOverlayGameState() {
        guard let key = fightOverlayGameKey() else { return }
        AppSettings.remove("\(key)_moveListVisible")
        AppSettings.remove("\(key)_trainingMenuVisible")
        AppSettings.remove("\(key)_trainingEnabled")
        AppSettings.remove("\(key)_character")
    }

    @MainActor
    func persistFightOverlayState() {
        guard let key = fightOverlayGameKey() else { return }
        let moveListVisible = moveListViewModel.isOverlayVisible
        let trainingMenuVisible = trainingModeOverlayView != nil
        let trainingEnabled = TrainingModeManager.shared.config.isEnabled
        let characterName = moveListViewModel.moveListService.selectedCharacter?.name
        AppSettings.setBool("\(key)_moveListVisible", value: moveListVisible)
        AppSettings.setBool("\(key)_trainingMenuVisible", value: trainingMenuVisible)
        AppSettings.setBool("\(key)_trainingEnabled", value: trainingEnabled)
        if let name = characterName {
            AppSettings.set("\(key)_character", value: name)
        } else {
            AppSettings.remove("\(key)_character")
        }
    }

    @MainActor
    func persistFightOverlayStateForSlot(_ slot: Int) {
        guard let key = fightOverlaySlotKey(slot: slot) else { return }
        let moveListVisible = moveListViewModel.isOverlayVisible
        let trainingMenuVisible = trainingModeOverlayView != nil
        let trainingEnabled = TrainingModeManager.shared.config.isEnabled
        let characterName = moveListViewModel.moveListService.selectedCharacter?.name
        AppSettings.setBool("\(key)_moveListVisible", value: moveListVisible)
        AppSettings.setBool("\(key)_trainingMenuVisible", value: trainingMenuVisible)
        AppSettings.setBool("\(key)_trainingEnabled", value: trainingEnabled)
        if let name = characterName {
            AppSettings.set("\(key)_character", value: name)
        }
    }

    @MainActor
    private func restoreFightOverlayState() {
        guard let key = fightOverlayGameKey(),
              trainingModeViewModel.hasGameData else { return }

        _ = AppSettings.getBool("\(key)_moveListVisible", defaultValue: false)
        _ = AppSettings.getBool("\(key)_trainingMenuVisible", defaultValue: false)
        let trainingWasEnabled = AppSettings.getBool("\(key)_trainingEnabled", defaultValue: false)
        _ = AppSettings.get("\(key)_character", type: String.self)

        let manager = TrainingModeManager.shared

        if trainingWasEnabled && !manager.config.isEnabled {
            manager.frameDriver.markP2AsJoined()
            manager.setEnabled(true)
        }

        // No auto-restore of overlays on launch
        persistFightOverlayState()
    }

    @MainActor
    private func restoreFightOverlayStateForSlot(_ slot: Int) {
        guard let key = fightOverlaySlotKey(slot: slot),
              trainingModeViewModel.hasGameData else { return }

        let moveListWasVisible = AppSettings.getBool("\(key)_moveListVisible", defaultValue: false)
        let trainingMenuWasVisible = AppSettings.getBool("\(key)_trainingMenuVisible", defaultValue: false)
        let trainingWasEnabled = AppSettings.getBool("\(key)_trainingEnabled", defaultValue: false)
        let savedCharacterName: String? = AppSettings.get("\(key)_character", type: String.self)

        let manager = TrainingModeManager.shared

        let wasAnyOverlayActive = moveListWasVisible || trainingMenuWasVisible || trainingWasEnabled
        guard wasAnyOverlayActive else { return }

        if trainingWasEnabled && !manager.config.isEnabled {
            manager.frameDriver.markP2AsJoined()
            manager.setEnabled(true)
        }

        // No auto-restore of TrainingModeOverlay window on slot load
        if let savedName = savedCharacterName,
           let character = moveListViewModel.characters.first(where: { $0.name == savedName }),
           character.name != moveListViewModel.moveListService.selectedCharacter?.name {
            moveListViewModel.confirmCharacter(character)
            if !moveListViewModel.isOverlayVisible {
                installMoveListOverlay()
            }
        } else if moveListWasVisible && !moveListViewModel.isOverlayVisible {
            if let character = moveListViewModel.moveListService.selectedCharacter {
                moveListViewModel.confirmCharacter(character)
                installMoveListOverlay()
            } else {
                moveListViewModel.activate()
                installMoveListOverlay()
            }
        } else if !moveListWasVisible && moveListViewModel.isOverlayVisible {
            moveListViewModel.deactivate()
            removeMoveListOverlay()
        }

        persistFightOverlayState()
    }

    private func isDolphinCore() -> Bool {
        let coreID = AppSettings.get("lastLoadedCoreID", type: String.self) ?? ""
        return coreID.lowercased().contains("dolphin")
    }

    private func isDOSCore() -> Bool {
        return runner is DOSRunner
    }

    // MARK: - Input Capture

    func windowDidResignKey(_ notification: Notification) {
        // We no longer call handleWindowResignedKey here because transient focus loss 
        // (e.g. during resolution changes) was causing unintended capture stops.
        // Input capture is now managed by App resignation and click-outside detection.
    }

    private var inputCaptureHotkeyMonitor: Any?

    private func flashScreen() {
        guard let flashView = screenshotFlashOverlayView else { return }
        flashView.isHidden = false
        flashView.alphaValue = 1.0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flashView.animator().alphaValue = 0.0
        } completionHandler: {
            flashView.isHidden = true
            flashView.alphaValue = 1.0
        }
    }

    private func postScreenshotPill(displayURL: URL, nativeURL: URL?) {
        let openLabel = LocalizationManager.shared.localized("screenshot.open")
        let deleteLabel = LocalizationManager.shared.localized("screenshot.delete")

        let notification = PillNotification(
            icon: "camera.fill",
            title: LocalizationManager.shared.localized("screenshot.saved"),
            subtitle: displayURL.lastPathComponent,
            autoDismissDelay: 6,
            action: PillAction(label: openLabel) {
                NSWorkspace.shared.open(displayURL)
                ScreenshotPillPresenter.shared.dismiss()
            },
            secondaryAction: PillAction(label: deleteLabel) {
                if ScreenshotService.delete(at: displayURL) {
                    LoggerService.info(category: "Screenshot", "Deleted screenshot: \(displayURL.path)")
                }
                if let native = nativeURL {
                    if ScreenshotService.delete(at: native) {
                        LoggerService.info(category: "Screenshot", "Deleted native: \(native.path)")
                    }
                }
                ScreenshotPillPresenter.shared.dismiss()
            }
        )
        ScreenshotPillPresenter.shared.present(notification)
    }

    private func postScreenshotHistory(displayURL: URL, nativeURL: URL?) {
        var subtitle = displayURL.lastPathComponent
        if nativeURL != nil {
            let format = LocalizationManager.shared.localized("screenshot.withNativeFormat")
            subtitle = String(format: format, displayURL.lastPathComponent)
        }
        let payload = OpenURLActionPayload(url: displayURL.path)
        NotificationHistoryManager.shared.post(
            icon: "camera.fill",
            title: LocalizationManager.shared.localized("screenshot.saved"),
            subtitle: subtitle,
            autoDismissDelay: 8,
            actionLabel: LocalizationManager.shared.localized("screenshot.open"),
            actionType: "open-screenshot",
            actionPayload: payload
        )
    }

    private func postClipSavedPill(url: URL) {
        let openLabel = LocalizationManager.shared.localized("screenshot.open")
        let notification = PillNotification(
            icon: "video.badge.checkmark",
            title: LocalizationManager.shared.localized("media.clipSaved"),
            subtitle: url.lastPathComponent,
            autoDismissDelay: 6,
            action: PillAction(label: openLabel) {
                NSWorkspace.shared.open(url)
                ScreenshotPillPresenter.shared.dismiss()
            }
        )
        ScreenshotPillPresenter.shared.present(notification)
    }

    static func registerScreenshotHistoryHandler() {
        NotificationHistoryManager.shared.registerActionHandler(type: "open-screenshot") { entry in
            guard let payload: OpenURLActionPayload = entry.decodePayload(OpenURLActionPayload.self),
                  let url = URL(string: payload.url) else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }

    private func setupInputCaptureHotkey() {
        inputCaptureHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let self, self.launchError != nil {
                let keyCode = event.keyCode
                if keyCode == 36 || keyCode == 49 || keyCode == 53 {
                    self.dismissErrorAndClose()
                    return nil
                }
            }
        let hotkeys = HotkeyConfigManager.shared
        let systemID = self?.runner?.systemID
        if hotkeys.matches(.toggleInputCapture, systemID: systemID, event: event) {
            if let window = self?.window {
                InputCaptureManager.shared.handleToggleHotkey(window: window)
            }
            return nil
        }
        if hotkeys.matches(.toggleGuideSidebar, systemID: systemID, event: event) {
            if let self, self.gameGuideViewModel.hasGuideData {
                self.toggleGuideSidebar()
                return nil
            }
        }
        return event
        }
    }
}


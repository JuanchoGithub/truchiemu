import Cocoa
import SwiftUI
import MetalKit
import Combine


// MARK: - Safe NSHostingView

// Custom hosting view that short-circuits layout when the XPC service has crashed.
// Prevents use-after-free in SwiftUI's ItemSheetPresentationModifier.destroy during
// the vulnerable window between crash detection and window cleanup.
class SafeHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        guard !XPCConnectionManager.isShuttingDown else { return }
        super.layout()
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
    @MainActor @Published var isFullscreen: Bool = false
    @MainActor @Published var autoFullscreenEnabled: Bool = false
    private var isWaitingForFullscreenAnimation = false
    private var fullscreenOverlayView: NSView?
    private var pendingSlotToLoad: Int?
    private var pendingROMForState: ROM?
    @MainActor @Published var saveStatesDisabled: Bool = false
    @MainActor @Published var isLoading: Bool = false
    var loadingOverlayView: NSHostingView<AnyView>?
    var pendingSystemID: String?
    var pendingROMForBezel: ROM?
    var onWindowWillClose: (() -> Void)?
    var toolbarView: NSHostingView<AnyView>?
    var hideToolbarTimer: Timer?
    var skipAutoSaveOnClose: Bool = false

    // Dismiss any active sheets and remove the SwiftUI toolbar from the view hierarchy.
    // Must be called before releasing the controller to prevent SwiftUI view graph teardown
    // from accessing deallocated @ObservedObject references.
    @MainActor
    func detachSwiftUI() {
        if let sheetWindow = cheatManagerSheetWindow, let window = window {
            window.endSheet(sheetWindow)
            cheatManagerSheetWindow = nil
        }
        toolbarView?.removeFromSuperview()
        toolbarView = nil
        loadingOverlayView?.removeFromSuperview()
        loadingOverlayView = nil
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
        
        let coord = MetalCoordinator(runner: runner)
        mtkView.delegate = coord
        self.coordinator = coord
        self.metalView = mtkView
        
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
        
        // Add SwiftUI overlay toolbar
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

    // Add SwiftUI loading overlay (covers entire window during game launch)
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
        fullscreenOverlayView?.removeFromSuperview()
        fullscreenOverlayView = nil

        // Load bezel after fullscreen animation completes (prevents warped bezel during transition)
        Task { @MainActor in
            if let systemID = self.pendingSystemID, let romForBezel = self.pendingROMForBezel {
                await self.loadBezelForGame(systemID: systemID, rom: romForBezel)
            }
            // Fullscreen animation complete — proceed with save state loading
            if let slotToLoad = self.pendingSlotToLoad, let rom = self.pendingROMForState {
                self.loadSaveStatesAfterLaunch(slotToLoad: slotToLoad, rom: rom)
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
    
    func launch(rom: ROM, coreID: String, slotToLoad: Int? = nil, shaderUniformOverrides: [String: Float] = [:]) {
        // Store shader uniforms for later use in _doLaunch
        self.pendingShaderUniforms = shaderUniformOverrides
        LoggerService.info(category: "GameLauncher", "launch() received \(shaderUniformOverrides.count) shader uniforms, key shellColorIndex=\(shaderUniformOverrides["shellColorIndex"] ?? -1)")
        
        // Check if this same ROM is already running in another window
        if RunningGamesTracker.shared.isRunning(romPath: rom.path.path) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            window?.close()
            return
        }
        
    // Register this ROM as running
    RunningGamesTracker.shared.registerRunning(romPath: rom.path.path, displayName: rom.displayName)
    trackedROMPath = rom.path.path
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

    // Proceed with launch (bezel is loaded after first frame is ready)
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
        
        // Launch the game with current shader uniforms
        runner?.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniforms)

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
            // Show error message and close window
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Error"
                alert.informativeText = "Game could not be loaded, check the logs."
                alert.runModal()
                self.window?.close()
            }
            return
        }
        
        // Load and optionally apply cheats after core is up
        autoLoadAndApplyCheats(for: rom)
        
        // Make sure the metal view is the first responder
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.metalView)
        }
        
        // Wait for the first frame before showing the window (prevents bezel flash)
        waitForFirstFrameAndShowWindow(slotToLoad: slotToLoad, rom: rom)
    }
    
    // Wait for the first frame to be rendered before dismissing the loading overlay.
    private func waitForFirstFrameAndShowWindow(slotToLoad: Int?, rom: ROM) {
        // Poll for isReadyForDisplay with a timeout (5 seconds max)
        var attempts = 0
        let maxAttempts = 100 // 10 seconds at 100ms intervals
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            
            attempts += 1
            // Already on main thread (Timer.scheduledTimer runs on main runloop)
            let state = MainActor.assumeIsolated { (self.runner?.isReadyForDisplay ?? false, self.runner?.lastError != nil, self.runner?.isRunning ?? false) }
            let isReady = state.0
            let hasError = state.1
            let isRunning = state.2
            let timedOut = attempts >= maxAttempts
            
            // Check for MAME missing dependencies (set during load via log callback)
            // NOTE: Removed - conflicts with pre-launch check. We handle this in GameLauncher now.
            // let mameMissingDeps = LibretroBridgeSwift.getMameMissingDependencies()
            
            if isReady || hasError || !isRunning || timedOut {
                timer.invalidate()
                
                // Removed: Runtime MAME dependency check conflicts with pre-launch check
                // if mameMissingDeps {
                //     LoggerService.warning(category: "Runner", "MAME reported missing dependencies, showing alert and closing")
                //     self.showMAMEDependenciesAlert()
                //     self.window?.close()
                //     return
                // }
                
                if !isReady {
                    
                    let errorToDisplay: GameError? = MainActor.assumeIsolated { self.runner?.lastError }

                    if hasError {
                        LoggerService.error(category: "Runner", "Core failed during launch, closing window immediately")
                    } else if !isRunning {
                        LoggerService.error(category: "Runner", "Runner stopped unexpectedly, closing window")
                    } else {
                        LoggerService.info(category: "Runner", "Timeout waiting for first frame, closing window")
                    }
                    
                    // Dont show window, terminate the emulation instead
                    self.window?.close()
                    MainActor.assumeIsolated {
                        self.runner?.stop()
                        self.runner = nil
                    }
                    
                    // Show error alert to the user
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.alertStyle = .critical
                        
                        if let error = errorToDisplay {
                            alert.messageText = "Launch Error"
                            alert.informativeText = error.localizedDescription
                        } else if timedOut {
                            alert.messageText = "Launch Timeout"
                            alert.informativeText = "The game took too long to start. The emulator may have crashed or failed to respond."
                        } else {
                            alert.messageText = "Launch Failed"
                            alert.informativeText = "The game session ended unexpectedly during launch."
                        }
                        
                        alert.runModal()
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
            // Cover game content with a black overlay during the fullscreen animation
            // to prevent visual artifacts from frames rendering mid-transition.
            if let containerView = window?.contentView {
                let overlay = NSView(frame: containerView.bounds)
                overlay.wantsLayer = true
                overlay.layer?.backgroundColor = NSColor.black.cgColor
                overlay.autoresizingMask = [.width, .height]
                containerView.addSubview(overlay, positioned: .above, relativeTo: nil)
                fullscreenOverlayView = overlay
            }
            pendingSlotToLoad = slotToLoad
            pendingROMForState = rom
            isWaitingForFullscreenAnimation = true
            toggleFullscreen()
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
        if let slotToLoad = slotToLoad {
            // Wait for emulation to stabilize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, let runner = self.runner else { return }
                let systemID = rom.systemID ?? "default"
                let stateURL = runner.saveManager.statePath(gameName: rom.displayName, systemID: systemID, slot: slotToLoad)
                if FileManager.default.fileExists(atPath: stateURL.path) {
                    LoggerService.info(category: "SaveState", "Found save state at: \(stateURL.path)")
                    let success = runner.loadState(slot: slotToLoad)
                    if success {
                        runner.osdMessage = "Loaded Slot \(slotToLoad)"
                        LoggerService.info(category: "SaveState", "Successfully loaded save state from slot \(slotToLoad)")
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { runner.osdMessage = nil }
                        }
                    } else {
                        LoggerService.debug(category: "SaveState", "Failed to load save state from slot \(slotToLoad)")
                    }
                } else {
                    LoggerService.debug(category: "SaveState", "No save state found at: \(stateURL.path)")
                }
            }
        } else {
            // Auto-load from slot -1 after launch completes (if enabled)
            let shouldAutoLoad = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: true)
            if shouldAutoLoad {
                // Skip auto-load for Dolphin cores due to known serialization crash
                if isDolphinCore() {
                    LoggerService.info(category: "SaveState", "Auto-load disabled for Dolphin core (known crash issue)")
                } else {
                    // Wait for emulation to stabilize
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self, let runner = self.runner else { return }
                        let systemID = rom.systemID ?? "default"
                        let stateURL = runner.saveManager.statePath(gameName: rom.displayName, systemID: systemID, slot: -1)
                        if FileManager.default.fileExists(atPath: stateURL.path) {
                            LoggerService.info(category: "SaveState", "Found save state at: \(stateURL.path)")
                            let success = runner.loadState(slot: -1)
                            if success {
                                runner.osdMessage = "Auto-loaded last session"
                                LoggerService.info(category: "SaveState", "Successfully loaded auto-save state")
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    await MainActor.run { runner.osdMessage = nil }
                                }
                            } else {
                                LoggerService.debug(category: "SaveState", "Failed to load auto-save state")
                            }
                        } else {
                            LoggerService.debug(category: "SaveState", "No save state found at: \(stateURL.path)")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cheats
    
    // Load cheats for the ROM and optionally apply enabled cheats to the running core.
    // Called after the emulator core has started.
    private func autoLoadAndApplyCheats(for rom: ROM) {
        // Always load cheats so they appear in the manager
        if cheatsEnabled {
            CheatManagerService.shared.loadCheatsForROM(rom)
        } else {
            return
        }
        
        let enabledCheats = CheatManagerService.shared.enabledCheats(for: rom)
        guard !enabledCheats.isEmpty else { return }
        
        let cheatData = enabledCheats.map { cheat in[
                "index": cheat.index,
                "code": cheat.code,
                "enabled": cheat.enabled
            ] as[String: Any]
        }
        XPCBridgeAdapter.shared.applyCheats(cheatData)
        CheatManagerService.shared.areCheatsApplied = true
        
        if SystemPreferences.shared.showCheatNotifications {
            LoggerService.info(category: "Cheats", "Auto-applied \(enabledCheats.count) cheat(s) for \(rom.displayName)")
        }
    }
    
    // Present the cheat manager as a sheet on this game window.
    // Pauses the game while the cheat manager is shown.
    @MainActor
    func showCheatManager() {
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
    
    func windowWillClose(_ notification: Notification) {
        isWaitingForFullscreenAnimation = false
        fullscreenOverlayView?.removeFromSuperview()
        fullscreenOverlayView = nil
        loadingOverlayView?.removeFromSuperview()
        loadingOverlayView = nil
        isLoading = false

        InputCaptureManager.shared.cleanup()

        stopPlaytimeTracking()

        CursorAutoHideManager.shared.stopMonitoring()
        CursorAutoHideManager.shared.showCursor()

        let shouldAutoSave = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false) && !skipAutoSaveOnClose

        if shouldAutoSave {
            if isDolphinCore() {
                LoggerService.info(category: "SaveState", "Auto-save disabled for Dolphin core (known crash issue)")
            } else if let runner = runner {
                LoggerService.info(category: "SaveState", "Auto-saving on window close...")
                _ = runner.saveState(slot: -1)
            }
        }
        runner?.stop()

        if let rom = trackedROM, accumulatedPlaytime > 0 {
            library?.recordPlaySession(rom, duration: accumulatedPlaytime)
        }

        if let romPath = trackedROMPath {
            RunningGamesTracker.shared.unregisterRunning(romPath: romPath)
        }

        if let rom = trackedROM {
            GameLauncher.shared.removeController(for: rom.id)
        }

        if !RunningGamesTracker.shared.isGameRunning {
            XPCBridgeAdapter.shared.stop()
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
    }

    // MARK: - Helper Functions

    private func isDolphinCore() -> Bool {
        let coreID = AppSettings.get("lastLoadedCoreID", type: String.self) ?? ""
        return coreID.lowercased().contains("dolphin")
    }

    // MARK: - Input Capture

    func windowDidResignKey(_ notification: Notification) {
        // We no longer call handleWindowResignedKey here because transient focus loss 
        // (e.g. during resolution changes) was causing unintended capture stops.
        // Input capture is now managed by App resignation and click-outside detection.
    }

    private var inputCaptureHotkeyMonitor: Any?

    private func setupInputCaptureHotkey() {
        inputCaptureHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 109 {
                if let window = self?.window {
                    InputCaptureManager.shared.handleToggleHotkey(window: window)
                }
                return nil
            }
            return event
        }
    }
}


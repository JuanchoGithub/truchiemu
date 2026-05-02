import Cocoa
import SwiftUI
import MetalKit
import Combine

// MARK: - Container view with tracking area for toolbar auto-hide
class GameContainerView: NSView {
    weak var windowController: StandaloneGameWindowController?
    private var lastMouseLocation: NSPoint?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        for trackingArea in self.trackingAreas {
            removeTrackingArea(trackingArea)
        }
        // Add new tracking area covering the entire view
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override func mouseMoved(with event: NSEvent) {
        // In fullscreen, the cursor position is pinned to the top of the screen,
        // and mouseMoved events keep firing even though the cursor hasn't moved.
        // Only notify the controller if the mouse actually changed position.
        let location = event.locationInWindow
        if lastMouseLocation != location {
            lastMouseLocation = location
            windowController?.onMouseActivity()
        }
    }
}

// MARK: - Standalone Game Window Controller
class StandaloneGameWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    private var runner: EmulatorRunner?
    private var metalView: FocusableMTKView?
    private var coordinator: MetalCoordinator?
    private var pendingROM: ROM?
    private var pendingCoreID: String?
    
    // Reference to the ROM library for updating playtime (weak to avoid retain cycles)
    weak var library: ROMLibrary?
    // Track the ROM reference for this window instance (for playtime tracking)
    private var trackedROM: ROM?
    // Accumulated playtime in seconds (only counts when game is running and not paused)
    private var accumulatedPlaytime: TimeInterval = 0
    // Timer that increments playtime every second while the game is active and not paused
    private var playtimeTimer: Timer?
    
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
    private var bezelBackgroundLayer: BezelBackgroundLayer?
    private var bezelViewModel: BezelViewModel?
    
    // Toolbar auto-hide state
    @MainActor @Published var isToolbarVisible: Bool = true
    @MainActor @Published var isFullscreen: Bool = false
    private var toolbarView: NSHostingView<AnyView>?
    private var hideToolbarTimer: Timer?
    
    init(runner: EmulatorRunner) {
        self.runner = runner
        
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
        let hostingView = NSHostingView(rootView: AnyView(GameOverlayToolbar(
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
    
    // Called when the window is resized. Dynamically scales bezel to fit new window size.
    private func onWindowResized() {
        guard let containerView = window?.contentView as? GameContainerView,
              let bezelLayer = bezelBackgroundLayer else { return }
        
        // Update bezel layer frame to match container
        bezelLayer.frame = containerView.bounds
        
        // If we have a bezel image, update the screen-scaled version
        if let bezelImage = bezelImage {
            let screenBounds = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            bezelLayer.setBezelImageForScreen(bezelImage, screenSize: screenBounds.size)
        }
        
        // Update Metal view frame to match bezel playable area
        updateMetalViewFrameForBezel()
        
        // Re-assert focus on the metal view after frame changes to prevent loss of keyboard input
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.metalView)
        }
    }
    
    // Updates the Metal view frame to match the playable area of the bezel.
    // This ensures the bezel is visible around the edges of the game content.
    private func updateMetalViewFrameForBezel() {
        guard let containerView = window?.contentView as? GameContainerView else {
            return
        }
        
        // Check if bezel layer exists and has a playable area
        if let bezelLayer = bezelBackgroundLayer, let playableArea = bezelLayer.playableAreaRect {
            // Resize Metal view to match the playable area
            metalView?.frame = playableArea
            LoggerService.debug(category: "Bezel", "Metal view resized to playable area: \(playableArea.width)x\(playableArea.height)")
        } else {
            // No bezel or no playable area - Metal view fills the entire container
            metalView?.frame = containerView.bounds
        }
    }
    
    // Called when the window moves to a different screen or returns from fullscreen.
    private func onWindowMoved() {
        // Update max window size for current screen
        constrainWindowToScreenBounds()
        
        // Re-scale bezel for new screen
        onWindowResized()
    }
    
    // Toggle macOS native fullscreen mode
    @MainActor
    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
        isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
    }
    
    @MainActor
    func onMouseActivity() {
        showToolbar()
    }
    
    @MainActor
    private func showToolbar() {
        if !isToolbarVisible {
            isToolbarVisible = true
            toolbarView?.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 1
            }
        }
        // Restart timer on real mouse activity (filtered by GameContainerView)
        scheduleHideToolbar()
    }
    
    func scheduleHideToolbar() {
        hideToolbarTimer?.invalidate()
        hideToolbarTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hideToolbar()
            }
        }
    }
    
    // MARK: - Playtime Tracking
    
    // Start tracking playtime with a timer that accumulates seconds only when the game is running and not paused
    private func startPlaytimeTracking() {
        playtimeTimer?.invalidate()
        playtimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let runner = self.runner else {
                timer.invalidate()
                return
            }
            // Only accumulate time when the game is running and not paused.
            // Timer.scheduledTimer fires on the main thread, so isPaused can be read directly
            // without DispatchQueue.main.sync (which would deadlock here).
            if runner.isRunning {
                Task { @MainActor in
                    if !runner.isPaused {
                        self.accumulatedPlaytime += 1.0
                    }
                }
            }
        }
    }
    
    // Stop playtime tracking
    private func stopPlaytimeTracking() {
        playtimeTimer?.invalidate()
        playtimeTimer = nil
    }
    
    @MainActor
    private func hideToolbar() {
        if isToolbarVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarView?.animator().alphaValue = 0
            } completionHandler: {[weak self] in
                Task { @MainActor [weak self] in
                    self?.isToolbarVisible = false
                }
            }
        }
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
        RunningGamesTracker.shared.registerRunning(romPath: rom.path.path)
        trackedROMPath = rom.path.path
        trackedROM = rom
        accumulatedPlaytime = 0
        startPlaytimeTracking()
        
        // Load bezel before launching (synchronously wait for bezel to be ready)
        let systemID = rom.systemID ?? "default"
        Task { @MainActor in
            await loadBezelForGame(systemID: systemID, rom: rom)
            // Bezel is now loaded, proceed with launch
            _doLaunch(rom: rom, coreID: coreID, slotToLoad: slotToLoad)
        }
    }
    
    // Store pending shader uniforms
    private var pendingShaderUniforms: [String: Float] = [:]
    
    private func _doLaunch(rom: ROM, coreID: String, slotToLoad: Int? = nil) {
        // Store ROM reference before launching (used by toolbar + cheat manager)
        runner?.rom = rom
        runner?.romPath = rom.path.path
        currentGameROM = rom
        
        // Update window title
        window?.title = "TruchiEmu - " + rom.displayName
        
        // Unpause the metal view and start emulation
        metalView?.isPaused = false
        
        // Use pending shader uniforms from launch parameters
        let shaderUniforms = pendingShaderUniforms
        
        // Launch the game with current shader uniforms
        runner?.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniforms)

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
    
    // Wait for the first frame to be rendered before showing the window.
    // This prevents the user from seeing a flash of the bezel without game content.
    private func waitForFirstFrameAndShowWindow(slotToLoad: Int?, rom: ROM) {
        // Poll for isReadyForDisplay with a timeout (5 seconds max)
        var attempts = 0
        let maxAttempts = 50 // 5 seconds at 100ms intervals
        
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
            
            if isReady || hasError || !isRunning || timedOut {
                timer.invalidate()
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
                    self.showWindowAndLoadSlot(slotToLoad: slotToLoad, rom: rom)
                }
            }
        }
    }
    
    // Show the window and handle save state loading.
    private func showWindowAndLoadSlot(slotToLoad: Int?, rom: ROM) {
        // Show and bring window to front
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Load from the specified slot after launch completes
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
    
    // Load bezel for a game and set up the background layer.
    // Constrains window size to screen bounds if bezel is larger than screen.
    @MainActor
    private func loadBezelForGame(systemID: String, rom: ROM) async {
        // Initialize bezel view model if needed
        if bezelViewModel == nil {
            bezelViewModel = BezelViewModel()
        }
        
        // Load bezel
        await bezelViewModel?.loadBezel(systemID: systemID, rom: rom)
        
        // Apply bezel image if loaded
        if let bezelImage = bezelViewModel?.bezelImage {
            self.bezelImage = bezelImage
            
            // Get screen bounds to constrain bezel size
            let screenBounds = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            
            LoggerService.debug(category: "Bezel", "Loading bezel for game. Screen bounds: \(Int(screenBounds.width))x\(Int(screenBounds.height)), Bezel size: \(Int(bezelImage.size.width))x\(Int(bezelImage.size.height))")
            
            // Create bezel background layer if needed
            if let containerView = window?.contentView as? GameContainerView {
                if bezelBackgroundLayer == nil {
                    let layer = BezelBackgroundLayer(frame: containerView.bounds)
                    layer.autoresizingMask = [.width, .height]
                    containerView.addSubview(layer, positioned: .below, relativeTo: metalView)
                    bezelBackgroundLayer = layer
                }
                
                // Use scaled bezel image to prevent oversized window
                bezelBackgroundLayer?.setBezelImageForScreen(bezelImage, screenSize: screenBounds.size)
                
                // Constrain window to screen bounds if bezel would make it larger
                constrainWindowToScreenBounds()
                
                // Resize Metal view to match bezel playable area
                updateMetalViewFrameForBezel()
                
                LoggerService.info(category: "Bezel", "Bezel applied for \(rom.displayName)")
            }
        } else {
            LoggerService.debug(category: "Bezel", "No bezel image loaded for \(rom.displayName)")
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
        LibretroBridge.applyCheats(cheatData)
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
        sheetWindow.contentView = NSHostingView(rootView:
            CheatManagerViewWrapper(rom: rom, windowController: self)
                .environment(SystemDatabaseWrapper.shared)
        )
        
        cheatManagerSheetWindow = sheetWindow
        
        window.beginSheet(sheetWindow) { [weak self] _ in
            Task { @MainActor in
                self?.cheatManagerSheetWindow = nil
                // Resume the game if it was paused for the sheet
                self?.runner?.isPaused = false
                LibretroBridge.setPaused(false)
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
        LibretroBridge.setPaused(false)
    }
    
    // Constrain the window size to fit within screen bounds.
    // This prevents bezels from making the window larger than the screen.
    @MainActor
    private func constrainWindowToScreenBounds() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let currentFrame = window.frame
        
        // If window is larger than screen, constrain it
        if currentFrame.width > screenFrame.width || currentFrame.height > screenFrame.height {
            LoggerService.debug(category: "Bezel", "Constraining window to screen bounds. Current: \(Int(currentFrame.width))x\(Int(currentFrame.height)), Screen: \(Int(screenFrame.width))x\(Int(screenFrame.height))")
            
            var newFrame = currentFrame
            newFrame.size.width = min(currentFrame.width, screenFrame.width)
            newFrame.size.height = min(currentFrame.height, screenFrame.height)
            
            // Recenter window
            newFrame.origin.x = screenFrame.origin.x + (screenFrame.width - newFrame.width) / 2
            newFrame.origin.y = screenFrame.origin.y + (screenFrame.height - newFrame.height) / 2
            
            window.setFrame(newFrame, display: true, animate: true)
        }
        
        // Set window size constraints to prevent future resizing beyond screen bounds
        window.minSize = NSSize(width: 640, height: 480)
        window.maxSize = NSSize(width: screenFrame.width, height: screenFrame.height)
    }
    
  func windowWillClose(_ notification: Notification) {
    // Clean up input capture if active
    InputCaptureManager.shared.cleanup()

    // Stop playtime tracking immediately so no more time accumulates
    stopPlaytimeTracking()
    
    // Stop cursor auto-hide and restore cursor visibility
    CursorAutoHideManager.shared.stopMonitoring()
    CursorAutoHideManager.shared.showCursor()

    // 1. Check the setting (Default to false for safety)
    let shouldAutoSave = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
        
        if shouldAutoSave {
            if let runner = runner {
                LoggerService.info(category: "SaveState", "Auto-saving on window close...")
                // We call this BEFORE runner.stop() to ensure the core is still active
                _ = runner.saveState(slot: -1)
            }
        }
        runner?.stop()
        
        // Record play session with the accumulated playtime
        if let rom = trackedROM, accumulatedPlaytime > 0 {
            library?.recordPlaySession(rom, duration: accumulatedPlaytime)
        }
        
        // Unregister this ROM from the running games tracker
        if let romPath = trackedROMPath {
            RunningGamesTracker.shared.unregisterRunning(romPath: romPath)
        }
        
        // Clean up from GameLauncher's active controllers
        if let rom = trackedROM {
            GameLauncher.shared.removeController(for: rom.id)
        }
    }

    // MARK: - Input Capture

    func windowDidResignKey(_ notification: Notification) {
        // We no longer call handleWindowResignedKey here because transient focus loss 
        // (e.g. during resolution changes) was causing unintended capture stops.
        // Input capture is now managed by App resignation and click-outside detection.
    }

    // Setup hotkey monitor for Cmd+F10
    private func setupInputCaptureHotkey() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Cmd+F10 (keyCode 109 = F10)
            if event.modifierFlags.contains(.command) && event.keyCode == 109 {
                if let window = self?.window {
                    InputCaptureManager.shared.handleToggleHotkey(window: window)
                }
                return nil // Consume the event
            }
            return event
        }
    }

  @MainActor
  class MetalCoordinator: NSObject, MTKViewDelegate {
    let runner: EmulatorRunner
    private var commandQueue: MTLCommandQueue?
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var innerDrawCount = 0
    // 4-frame temporal buffer for GBC shader (T-1, T-2, T-3, T-4, plus current frame passed directly)
    private var temporalTextures: [MTLTexture?] = [nil, nil, nil, nil]
    private var temporalIndex: Int = 0 // Cycles 0-3, points to "current"
    private var frameCounter: UInt32 = 0
    
    // Viewport debouncing to prevent warping during resize
    private var stableViewportSize: CGSize = .zero
    private var resizeTimer: Timer?
    private let resizeSettleInterval: TimeInterval = 0.15 // 150ms

    init(runner: EmulatorRunner) {
      self.runner = runner
    }
    
 // MARK: - Viewport Debouncing   
 private var lastStableAspect: CGFloat = 0.0
 private var aspectStableTimer: Timer?
 private var lastUsedDrawableSize: CGSize = .zero
   
 private func shouldUpdateAspect(for view: MTKView) -> Bool {
   // Return true if aspect should update, false if should keep stable
   let currentSize = view.drawableSize
   
   // If significantly different from last used, update
   if abs(currentSize.width - lastUsedDrawableSize.width) > 50 || 
      abs(currentSize.height - lastUsedDrawableSize.height) > 50 {
     lastUsedDrawableSize = currentSize
     return true
   }
   
return false
  }

    private func ensureTemporalTextures(width: Int, height: Int, device: MTLDevice, sourceFormat: MTLPixelFormat) {
            // Check if all textures are valid and match
            var allValid = true
            for tex in temporalTextures {
                if tex == nil || tex!.width != width || tex!.height != height || tex!.pixelFormat != sourceFormat {
                    allValid = false
                    break
                }
            }
            if allValid { return }

            // Create all 4 temporal textures
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: sourceFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private

            temporalTextures = [nil, nil, nil, nil]
            for i in 0..<4 {
                if let newTex = device.makeTexture(descriptor: descriptor) {
                    temporalTextures[i] = newTex
                }
            }
            temporalIndex = 0
            LoggerService.debug(category: "Shaders", "Created 4-frame temporal buffer: \(width)x\(height) format:\(sourceFormat)")
        }

        private func getTemporalTexture(at index: Int) -> MTLTexture? {
            return temporalTextures[index]
        }

        private func advanceTemporalIndex() {
            temporalIndex = (temporalIndex + 1) % 4
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Apply CATransform3D layer rotation so rotated games display upright
            let rotation = runner.currentFrameRotation
            let angle: Double
            switch rotation {
            case 1: angle = .pi / 2.0      // 90° CW
            case 2: angle = .pi             // 180°
            case 3: angle = -.pi / 2.0     // 270° CW (= -90°)
            default: angle = 0.0
            }
            view.layer?.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        }

        private func getFragmentFunctionName() -> String {
            return ShaderManager.shared.getCurrentFragmentFunctionName()
        }

        private func getPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
            let fragmentName = getFragmentFunctionName()
            
            if let cached = pipelineCache[fragmentName] {
                return cached
            }
            
            // Create new pipeline
            guard let library = loadShaderLibrary(device: device) else {
                LoggerService.debug(category: "Shaders", "ERROR: Could not create shader library.")
                return nil
            }
            
            guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
                  let fragmentFunction = library.makeFunction(name: fragmentName) else {
                LoggerService.debug(category: "Shaders", "ERROR: Could not find shader function '\(fragmentName)'")
                LoggerService.debug(category: "Shaders", "Available functions: \(library.functionNames.joined(separator: ", "))")
                return nil
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.vertexFunction = vertexFunction
            desc.fragmentFunction = fragmentFunction

            do {
                let pipeline = try device.makeRenderPipelineState(descriptor: desc)
                pipelineCache[fragmentName] = pipeline
                LoggerService.debug(category: "Shaders", "Created pipeline for '\(fragmentName)'")
                return pipeline
            } catch {
                LoggerService.debug(category: "Shaders", "ERROR: Failed to create pipeline '\(fragmentName)': \(error)")
                return nil
            }
        }

        func draw(in view: MTKView) {
            // Reset mouse deltas at start of each frame
            LibretroBridgeSwift.resetMouseDeltas()

            guard let device = view.device,
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            // Transparent background (alpha 0) so bezel shows through
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].storeAction = .store
            
            if commandQueue == nil {
                LoggerService.debug(category: "Metal", "Initializing Command Queue...")
                commandQueue = device.makeCommandQueue()
            }
            
            guard let cmdQueue = commandQueue,
                  let cmdBuffer = cmdQueue.makeCommandBuffer() else { 
                LoggerService.debug(category: "Metal", "Failed to create command buffer")
                return 
            }
            
            let pipeline = getPipelineState(device: device)
            if let pipeline = pipeline {
                if let frameTex = runner.currentFrameTexture {
                    if let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
      // ASPECT RATIO — multi-tier fallback:
      // 1. Core-provided aspect ratio from retro_system_av_info (preferred for N64, PS1, etc.)
      // 2. Pixel dimensions from frame texture (frameW/frameH)
      // 3. System's known display aspect ratio (final fallback for consoles with fixed display output)
      // Use current drawable size for viewport (to maintain proper centering and scaling)
      let viewWidth = view.drawableSize.width
      let viewHeight = view.drawableSize.height
      let isRotated = (runner.currentFrameRotation == 1 || runner.currentFrameRotation == 3)
      let frameW = CGFloat(frameTex.width)
      let frameH = CGFloat(frameTex.height)
      var targetAspect: CGFloat
      
      // Track drawable size for aspect stability
      _ = shouldUpdateAspect(for: view)
                        
                        // Try core-provided aspect ratio first (preferred for N64, PS1, etc.)
                        let coreAspect = LibretroBridgeSwift.aspectRatio()
                        if coreAspect > 0.0 {
                            // Core provided a valid aspect ratio — use it directly
                            targetAspect = isRotated ? (1.0 / CGFloat(coreAspect)) : CGFloat(coreAspect)
                        } else {
                            // Fall back to computing from pixel dimensions
                            targetAspect = isRotated ? (frameH / frameW) : (frameW / frameH)
                        }
                        
                        // Final fallback: for known console systems, use the system's canonical display aspect ratio
                        // to prevent incorrect rendering when the core reports wrong or missing aspect info.
                        // This catches cases where PS1 cores report non-4:3 internal resolutions (e.g. 368x240).
                        if let systemID = runner.rom?.systemID,
                           let systemInfo = SystemDatabase.system(forID: systemID) {
                            _ = systemInfo.displayAspectRatio

                            //If the aspect ratio is wider than the Macbook screen, force it to 16:10
                            // FIXME: this should be an option in settings
                            if targetAspect > 1.7 {
                                targetAspect = 1.6
                                LoggerService.extreme(category: "Metal", "[Aspect Ratio] Core/pixel ratio \(String(format: "%.3f", targetAspect)) is wider than the macbook screen. Forcing aspect ratio to 16:10")
                            }
                        }
                        var drawWidth = viewWidth
                        var drawHeight = viewWidth / targetAspect
                        
                        if drawHeight > viewHeight {
                            drawHeight = viewHeight
                            drawWidth = viewHeight * targetAspect
                        }
                        
                        let x = (viewWidth - drawWidth) / 2.0
                        let y = (viewHeight - drawHeight) / 2.0
                        
                        let viewport = MTLViewport(originX: Double(x), originY: Double(y), 
                                                   width: Double(drawWidth), height: Double(drawHeight), 
                                                   znear: 0.0, zfar: 1.0)
                        enc.setViewport(viewport)
                        
      let fw = Float(frameTex.width)
      let fh = Float(frameTex.height)
      let vpW = Float(view.drawableSize.width)
      let vpH = Float(view.drawableSize.height)
      let time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
        let fragmentName = getFragmentFunctionName()
                         
                          // Helper: get a uniform value from the thread-safe snapshot
                          func getUniform(_ name: String, fallback: Float) -> Float {
                              let snapshot = ShaderManager.shared.getUniformSnapshot()
                              return snapshot[name] ?? fallback
                          }

                        enc.setRenderPipelineState(pipeline)
                        enc.setFragmentTexture(frameTex, index: 0)

                        switch fragmentName {
                        case "fragmentCRT", "fragmentPassthrough":
                            // Use preset defaults for all uniforms - no ROMSettings fallback
                            // Genesis bleeding is quite noticeable.
                            let scanInt = getUniform("scanlineIntensity", fallback: 0.6) 
                            let barrelAmt = getUniform("barrelAmount", fallback: 0.05)
                            let colorB = getUniform("colorBoost", fallback: 1.1)
                            LoggerService.extreme(category: "Shaders", "scanInt=\(scanInt) barrelAmt=\(barrelAmt) colorBoost=\(colorB)")
                            var u = CRTUniforms(
                                 scanlineIntensity: scanInt,
                                 barrelAmount: barrelAmt,
                                 colorBoost: colorB,
                                 time: time,
                                 bleedAmount: getUniform("bleedAmount", fallback: 0.0),
                                 texSizeX: Float(frameTex.width),
                                 texSizeY: Float(frameTex.height),
                                 vignetteStrength: getUniform("vignetteStrength", fallback: 0.45),
                                 flickerStrength: getUniform("flickerStrength", fallback: 0.005),
                                 bloomStrength: getUniform("bloomStrength", fallback: 1.3),
                                 chromaAmount: getUniform("chromaAmount", fallback: 0.0012),
                                 softnessAmount: getUniform("softnessAmount", fallback: 0.0008),
                                 bezelRounding: getUniform("bezelRounding", fallback: 0.04),
                                 bezelGlow: getUniform("bezelGlow", fallback: 0.35),
                                 tintR: getUniform("tintR", fallback: 0.96),
                                 tintG: getUniform("tintG", fallback: 1.04),
                                 tintB: getUniform("tintB", fallback: 0.95),
                                 useDistort: getUniform("useDistort", fallback: 1.0),
                                 useScan: getUniform("useScan", fallback: 1.0),
                                 useBleed: getUniform("useBleed", fallback: 1.0),
                                 useSoft: getUniform("useSoft", fallback: 1.0),
                                 useChroma: getUniform("useChroma", fallback: 1.0),
                                 useWhite: getUniform("useWhite", fallback: 1.0),
                                 useVig: getUniform("useVig", fallback: 1.0),
                                 useFlick: getUniform("useFlick", fallback: 1.0),
                                 useBezel: getUniform("useBezel", fallback: 1.0),
                                 useBloom: getUniform("useBloom", fallback: 0.0),
                                 padding: 0.0
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                        case "fragmentDotMatrixLCD":
                            // Use preset defaults for all uniforms
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = DotMatrixLCDUniforms(
                                dotOpacity: getUniform("dotOpacity", fallback: 0.85),
                                metallicIntensity: getUniform("metallicIntensity", fallback: 0.5),
                                specularShininess: getUniform("specularShininess", fallback: 8.0),
                                colorBoost: colorB,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<DotMatrixLCDUniforms>.stride, index: 0)
                        case "fragmentLottesCRT":
                            let colorB = getUniform("colorBoost", fallback: 1.1)
                            var u = LottesUniforms(
                                scanlineStrength: getUniform("scanlineStrength", fallback: 0.5),
                                maskStrength: getUniform("maskStrength", fallback: 0.3),
                                bloomAmount: getUniform("bloomAmount", fallback: 0.15),
                                curvatureAmount: getUniform("curvatureAmount", fallback: 0.02),
                                colorBoost: colorB,
                                _pad: 0,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<LottesUniforms>.stride, index: 0)
                        case "fragmentSharpBilinear":
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = SharpBilinearUniforms(
                                sharpness: getUniform("sharpness", fallback: 0.8),
                                colorBoost: colorB,
                                scanlineOpacity: getUniform("scanlineOpacity", fallback: 0.0),
                                _pad: 0,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<SharpBilinearUniforms>.stride, index: 0)
                        case "fragment8bGameBoy":
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = EightBitGameBoyUniforms(
                                gridStrength: getUniform("gridStrength", fallback: 0.4),
                                pixelSeparation: getUniform("pixelSeparation", fallback: 0.05),
                                brightnessBoost: getUniform("brightnessBoost", fallback: 1.2),
                                colorBoost: colorB,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0),
                                showShell: getUniform("showShell", fallback: 1.0),
                                showStrip: getUniform("showStrip", fallback: 1.0),
                                showLens: getUniform("showLens", fallback: 1.0),
                                showText: getUniform("showText", fallback: 1.0),
                                showLED: getUniform("showLED", fallback: 1.0),
                                lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0),
                                lightStrength: getUniform("lightStrength", fallback: 1.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<EightBitGameBoyUniforms>.stride, index: 0)
                        case "fragment8BitGBC":
                            // Game Boy Color with 4-frame temporal feedback
                            ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                            let colorB = getUniform("colorBoost", fallback: 1.44)
                            let fw = Float(frameTex.width)
                            let fh = Float(frameTex.height)
                            let gw = getUniform("ghostWeights", fallback: 0.45)
   // Compute flags from enable toggles
   var flags: UInt32 = 0
   let ghostEnabled = getUniform("enableGhost", fallback: 1.0) > 0.5
   let gridEnabled = getUniform("enableGrid", fallback: 1.0) > 0.5
   let aberrationEnabled = getUniform("enableAberration", fallback: 1.0) > 0.5
   let bleedEnabled = getUniform("enableBleed", fallback: 1.0) > 0.5
   let newtonRingsEnabled = getUniform("enableNewtonRings", fallback: 1.0) > 0.5
   let jitterEnabled = getUniform("enableJitter", fallback: 1.0) > 0.5
   let reflectionEnabled = getUniform("enableReflection", fallback: 1.0) > 0.5
   let grainEnabled = getUniform("enableGrain", fallback: 1.0) > 0.5
   let vignetteEnabled = getUniform("enableVignette", fallback: 1.0) > 0.5
   let topographyEnabled = getUniform("enableTopography", fallback: 1.0) > 0.5
   let colorMatrixEnabled = getUniform("enableColorMatrix", fallback: 1.0) > 0.5
   if ghostEnabled { flags |= 1 << 0 } // FLAG_GHOSTING
   if gridEnabled { flags |= 1 << 1 } // FLAG_GRID
   if aberrationEnabled { flags |= 1 << 2 } // FLAG_ABERRATION
   if bleedEnabled { flags |= 1 << 3 } // FLAG_BLEED
   if newtonRingsEnabled { flags |= 1 << 4 } // FLAG_NEWTON_RINGS
   if jitterEnabled { flags |= 1 << 5 } // FLAG_JITTER
   if reflectionEnabled { flags |= 1 << 6 } // FLAG_REFLECTION
   if grainEnabled { flags |= 1 << 7 } // FLAG_GRAIN
   if vignetteEnabled { flags |= 1 << 8 } // FLAG_VIGNETTE
   if topographyEnabled { flags |= 1 << 9 } // FLAG_TOPOGRAPHY
   if colorMatrixEnabled { flags |= 1 << 10 } // FLAG_COLOR_MATRIX
   LoggerService.info(category: "Shaders", "GBC flags: ghost=\(ghostEnabled) grid=\(gridEnabled) aberration=\(aberrationEnabled) bleed=\(bleedEnabled) newtonRings=\(newtonRingsEnabled) jitter=\(jitterEnabled) reflection=\(reflectionEnabled) grain=\(grainEnabled) vignette=\(vignetteEnabled) topography=\(topographyEnabled) colorMatrix=\(colorMatrixEnabled) -> flags=\(flags)")
                            var u = GBCUniforms(
                                dotOpacity: getUniform("dotOpacity", fallback: 0.85),
                                specularShininess: getUniform("specularShininess", fallback: 8.0),
                                colorBoost: colorB,
                                physicalDepth: getUniform("physicalDepth", fallback: 0.22),
                                ghostingWeight: gw,
                                frameIndex: frameCounter,
                                flags: flags,
                                brightnessBoost: getUniform("brightnessBoost", fallback: 1.0),
                                showShell: getUniform("showShell", fallback: 1.0),
                                lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0),
                                lightStrength: getUniform("lightStrength", fallback: 1.0),
                                shellColorIndex: {
                                let val = getUniform("shellColorIndex", fallback: 0.0)
                                LoggerService.info(category: "Shaders", "GBC shellColorIndex=\(val)")
                                return val
                            }(),
                                gridThicknessDark: getUniform("gridThicknessDark", fallback: 0.2),
                                gridThicknessLight: getUniform("gridThicknessLight", fallback: 0.1),
                                sourceSize: SIMD4<Float>(fw, fh, 0, 0),
                                outputSize: SIMD4<Float>(vpW, vpH, 0, 0)
)
                            enc.setFragmentBytes(&u, length: MemoryLayout<GBCUniforms>.stride, index: 0)
                            // Set all 5 textures: frame0=current, frame1=T-1, frame2=T-2, frame3=T-3, frame4=T-4
                            enc.setFragmentTexture(frameTex, index: 0)
                            for i in 1...4 {
                                if let tex = getTemporalTexture(at: (temporalIndex - i + 4) % 4) {
                                    enc.setFragmentTexture(tex, index: i)
                                }
                            }
                            frameCounter += 1
                        case "fragmentLiteCRT":
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = LiteCRTUniforms(
                                scanlineIntensity: getUniform("scanlineIntensity", fallback: 0.3),
                                phosphorStrength: getUniform("phosphorStrength", fallback: 0.2),
                                brightness: getUniform("brightness", fallback: 1.1),
                                colorBoost: colorB
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<LiteCRTUniforms>.stride, index: 0)
                        case "fragmentScaleSmooth":
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = ScaleSmoothUniforms(
                                smoothness: getUniform("smoothness", fallback: 1.0),
                                colorBoost: colorB,
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<ScaleSmoothUniforms>.stride, index: 0)
                        case "fragmentGBAShader":
                            ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = GBAUniforms(
                                dotOpacity: getUniform("dotOpacity", fallback: 0.8),
                                specularShininess: getUniform("specularShininess", fallback: 1.0),
                                colorBoost: colorB,
                                ghostingWeight: getUniform("ghostingWeight", fallback: 0.25),
                                physicalDepth: getUniform("physicalDepth", fallback: 0.2),
                                frameIndex: UInt32(frameCounter % 60),
                                sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                                outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0),
                                lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0)
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<GBAUniforms>.stride, index: 0)
                            enc.setFragmentTexture(frameTex, index: 0)
                            for i in 1...2 {
                                if let tex = getTemporalTexture(at: (temporalIndex - i + 4) % 4) {
                                    enc.setFragmentTexture(tex, index: i)
                                }
                            }
                            frameCounter += 1
                        case "fragmentCRTMultipass":
                            ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = CRTMultipassUniforms(
                                scanlineIntensity: getUniform("scanlineIntensity", fallback: 0.45),
                                barrelAmount: getUniform("barrelAmount", fallback: 0.15),
                                colorBoost: colorB,
                                time: time,
                                ghostingWeight: getUniform("ghostingWeight", fallback: 0.3),
                                bleedAmount: getUniform("bleedAmount", fallback: 0.0),
                                texSizeX: fw,
                                texSizeY: fh,
                                vignetteStrength: getUniform("vignetteStrength", fallback: 0.6),
                                flickerStrength: getUniform("flickerStrength", fallback: 0.05),
                                bloomStrength: getUniform("bloomStrength", fallback: 0.25),
                                chromaAmount: getUniform("chromaAmount", fallback: 0.4),
                                softnessAmount: getUniform("softnessAmount", fallback: 0.2),
                                bezelRounding: getUniform("bezelRounding", fallback: 0.1),
                                bezelGlow: getUniform("bezelGlow", fallback: 0.5),
                                tintR: getUniform("tintR", fallback: 1.0),
                                tintG: getUniform("tintG", fallback: 1.0),
                                tintB: getUniform("tintB", fallback: 1.0),
                                useDistort: getUniform("useDistort", fallback: 1.0),
                                useScan: getUniform("useScan", fallback: 1.0),
                                useBleed: getUniform("useBleed", fallback: 1.0),
                                useSoft: getUniform("useSoft", fallback: 1.0),
                                useChroma: getUniform("useChroma", fallback: 1.0),
                                useWhite: getUniform("useWhite", fallback: 1.0),
                                useVig: getUniform("useVig", fallback: 1.0),
                                useFlick: getUniform("useFlick", fallback: 1.0),
                                useBezel: getUniform("useBezel", fallback: 1.0),
                                useBloom: getUniform("useBloom", fallback: 1.0),
                                padding: 0.0
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTMultipassUniforms>.stride, index: 0)
                            enc.setFragmentTexture(frameTex, index: 0)
                            for i in 1...4 {
                                if let tex = getTemporalTexture(at: (temporalIndex - i + 4) % 4) {
                                    enc.setFragmentTexture(tex, index: i)
                                }
                            }
                            frameCounter += 1
                        default:
                            // Fallback to basic passthrough/CRT style
                            let colorB = getUniform("colorBoost", fallback: 1.0)
                            var u = CRTUniforms(
                                scanlineIntensity: 0.0,
                                barrelAmount: 0.0,
                                colorBoost: colorB,
                                time: time,
                                bleedAmount: getUniform("bleedAmount", fallback: 0.0),
                                texSizeX: Float(frameTex.width),
                                texSizeY: Float(frameTex.height),
                                vignetteStrength: 0.0,
                                flickerStrength: 0.0,
                                bloomStrength: 0.0,
                                chromaAmount: 0.0,
                                softnessAmount: 0.0,
                                bezelRounding: 0.0,
                                bezelGlow: 0.0,
                                tintR: 1.0,
                                tintG: 1.0,
                                tintB: 1.0,
                                useDistort: 0.0,
                                useScan: 0.0,
                                useBleed: 0.0,
                                useSoft: 0.0,
                                useChroma: 0.0,
                                useWhite: 0.0,
                                useVig: 0.0,
                                useFlick: 0.0,
                                useBezel: 0.0,
                                useBloom: 0.0,
                                padding: 0.0
                            )
                            enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                        }

                        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        enc.endEncoding()
                        
                        // For shaders with temporal feedback: maintain rolling history
                        // Must happen AFTER render encoder ends
                        // Advance first, then write to that slot (becomes T-1 for next frame)
                        if fragmentName == "fragment8BitGBC" || fragmentName == "fragmentGBAShader" || fragmentName == "fragmentCRTMultipass" {
                            advanceTemporalIndex()
                            let blit = cmdBuffer.makeBlitCommandEncoder()
                            if let tex = temporalTextures[temporalIndex] {
                                blit?.copy(from: frameTex, to: tex)
                            }
                            blit?.endEncoding()
                        }
                        
                        innerDrawCount += 1
                        
                        if innerDrawCount <= 3 {
                            LoggerService.extreme(category: "Metal", "Drawing frame \(innerDrawCount) with texture \(frameTex.width)x\(frameTex.height)")
                        }
                    }
                } else {
                    // No frame texture yet - just present black screen
                    if innerDrawCount < 10 {
                        LoggerService.extreme(category: "Metal", "No frame texture yet, drawing black")
                    }
                }
            } else {
                if innerDrawCount < 5 {
                    LoggerService.debug(category: "Metal", "Failed to get pipeline state for fragment shader")
                }
            }

            cmdBuffer.present(drawable)
            cmdBuffer.commit()
        }
        
        // Load the shader library containing all shaders
        private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
            // Try to load pre-compiled metallib from bundle
            if let url = Bundle.main.url(forResource: "default", withExtension: "metallib") {
                LoggerService.info(category: "Shaders", "Found metallib at: \(url)")
                do {
                    let library = try device.makeLibrary(URL: url)
                    return library
                } catch {
                    LoggerService.error(category: "Shaders", "Failed to load metallib: \(error)")
                }
            }
            
            // Fallback: compile all_shaders.metal from bundle resources
            if let bundlePath = Bundle.main.resourcePath {
                let shadersPath = (bundlePath as NSString).appendingPathComponent("all_shaders.metal")
                if let source = try? String(contentsOfFile: shadersPath, encoding: .utf8) {
                    do {
                        let library = try device.makeLibrary(source: source, options: nil)
                        LoggerService.info(category: "Shaders", "Compiled all_shaders.metal with functions: \(library.functionNames.joined(separator: ", "))")
                        return library
                    } catch {
                        LoggerService.debug(category: "Shaders", "Failed to compile all_shaders.metal: \(error)")
                    }
                }
                
                // Try individual shader files as last resort
                let shaderFiles = ["CRTFilter", "CRTTest", "LCDGrid", "VibrantLCD", "DotMatrixLCD", "EdgeSmooth", "Composite", "Passthrough", "8bGameBoyColor"]
                for file in shaderFiles {
                    let filePath = (bundlePath as NSString).appendingPathComponent("\(file).metal")
                    if let source = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        do {
                            let library = try device.makeLibrary(source: source, options: nil)
                            LoggerService.info(category: "Shaders", "Compiled \(file).metal with functions: \(library.functionNames.joined(separator: ", "))")
                            return library
                        } catch {
                            LoggerService.debug(category: "Shaders", "Failed to compile \(file).metal: \(error)")
                        }
                    }
                }
            }
            
            return nil
        }
    }
}

import Foundation
import IOSurface
import Metal

final class XPCBridgeAdapter {
    static let shared = XPCBridgeAdapter()

    private let shmManager = SharedMemoryManager.shared
    private let videoManager = IOSurfaceVideoManager()
    private var sessionID: String = ""
    private var useXPC: Bool = true {
        didSet { g_xpcModeActive = ObjCBool(useXPC) }
    }
    private var useSharedMemory: Bool = false
    private var hasLoggedPoll = false

    private init() {
        g_xpcModeActive = ObjCBool(useXPC)
    }

    var isActive: Bool { useXPC }

    private var gameLoadedHandler: ((String) -> Void)?

    func registerGameLoadedCallback(handler: @escaping (String) -> Void) {
        guard useXPC else {
            LibretroBridgeSwift.registerGameLoadedCallback(handler: handler)
            return
        }
        gameLoadedHandler = handler
    }

    func createResizedSurface(width: Int, height: Int) -> IOSurface? {
        videoManager.createSurface(width: width, height: height, format: 1)
    }

    func enableXPCMode() {
        useXPC = true
        XPCConnectionManager.shared.connect()
    }

    func disableXPCMode() {
        useXPC = false
        shmManager.cleanup()
        videoManager.cleanup()
        XPCConnectionManager.shared.disconnect()
    }

    // MARK: - Launch & Lifecycle

    func launch(dylibPath: String, romPath: String, coreID: String, systemID: String?, romFilename: String?,
                 shaderDir: String?, videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void,
                 wiiControllerType: Int = 0,
                 onFailure: ((String) -> Void)? = nil) {
        guard useXPC else {
            LoggerService.warning(category: "XPCBridgeAdapter", "launch() — XPC DISABLED, launching in-process (useXPC=false)")
            LibretroBridgeSwift.launch(
                dylibPath: dylibPath, romPath: romPath, coreID: coreID,
                systemID: systemID, romFilename: romFilename, shaderDir: shaderDir,
                wiiControllerType: wiiControllerType,
                videoCallback: videoCallback, onFailure: onFailure
            )
            return
        }

        if !XPCConnectionManager.shared.isConnected {
            XPCConnectionManager.shared.connect()
        }

        sessionID = String(Int(Date().timeIntervalSince1970) % 999999)
        let shmCreated = shmManager.createSharedMemory(sessionID: sessionID)
        useSharedMemory = shmCreated

        let saveDir = SaveDirectoryBridge.libretroSaveDirectoryPath()
        let sysDir = SaveDirectoryBridge.libretroSystemDirectoryPath()
        let lang = SystemPreferences.shared.systemLanguage.libretroRawValue
        let logLevel = Int(LoggerService.shared.currentLevel.coreLogLevelValue)

        guard let proxy = XPCConnectionManager.shared.remoteProxy else {
            onFailure?("XPC service not connected")
            return
        }

        if useSharedMemory {
            proxy.setSharedMemoryName(shmManager.sharedName) {}
        }

        let defaultSurface = videoManager.createSurface(width: 1024, height: 1024, format: 1)
        if let surface = defaultSurface {
            proxy.setIOSurfaceForVideo(surface) {}
        }

        let delegate = CoreClientDelegate.shared
        delegate.onGameLoaded = { [weak self] romPath in
            self?.gameLoadedHandler?(romPath)
        }
        delegate.onCoreFailed = { message in
            onFailure?(message)
        }
        delegate.onGeometryChanged = { [weak self] width, height, _ in
            guard let surface = self?.videoManager.createSurface(width: width, height: height, format: 1) else { return }
            XPCConnectionManager.shared.remoteProxy?.setIOSurfaceForVideo(surface) {}
        }
        delegate.onRcheevosAchievementTriggered = { [weak self] id in
            self?.onRcheevosAchievementTriggered?(id)
        }
        delegate.onRcheevosAchievementProgress = { [weak self] id, value in
            self?.onRcheevosAchievementProgress?(id, value)
        }
        delegate.onRcheevosChallengeStarted = { [weak self] id in
            self?.onRcheevosChallengeStarted?(id)
        }
        delegate.onRcheevosChallengeCancelled = { [weak self] id in
            self?.onRcheevosChallengeCancelled?(id)
        }
        delegate.onRcheevosRichPresence = { [weak self] message in
            self?.onRcheevosRichPresence?(message)
        }

        proxy.launch(
        dylibPath: dylibPath, romPath: romPath, coreID: coreID,
        systemID: systemID, romFilename: romFilename, shaderDir: shaderDir,
        saveDirectory: saveDir, systemDirectory: sysDir,
        language: lang, logLevel: logLevel, wiiControllerType: wiiControllerType
        ) { success, errorMessage in
            if !success {
                onFailure?(errorMessage ?? "Unknown error")
            }
        }

        if let pending = pendingRcheevosTriggers {
            sendRcheevosTriggers(pending, richPresenceScript: pendingRichPresenceScript, proxy: proxy)
            pendingRcheevosTriggers = nil
            pendingRichPresenceScript = nil
        }

        if useSharedMemory {
            startFramePolling(videoCallback: videoCallback)
        }
    }

    private var framePollingTimer: DispatchSourceTimer?

    private func startFramePolling(videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void) {
        let queue = DispatchQueue(label: "truchiemu.framepoll", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.pollSharedMemoryForFrame(videoCallback: videoCallback)
        }
        timer.resume()
        framePollingTimer = timer
    }

    private func pollSharedMemoryForFrame(videoCallback: @escaping (UnsafeRawPointer?, Int, Int, Int, Int) -> Void) {
        guard let shm = shmManager.sharedMemory else { return }
        guard xpc_shm_load_frameReady(shm) == 1 else { return }
        xpc_shm_store_frameReady(shm, 0)

        let width = Int(shm.pointee.videoWidth)
        let height = Int(shm.pointee.videoHeight)
        let format = Int(shm.pointee.videoFormat)
        let pitch = Int(shm.pointee.videoPitch)

        if !hasLoggedPoll {
            hasLoggedPoll = true
            LoggerService.info(category: "XPC", "poll: \(width)x\(height) pitch=\(pitch) format=\(format)")
        }

        if let surface = videoManager.getCurrentSurface() {
            surface.lock(options: [], seed: nil)
            let baseAddress = surface.baseAddress
            let surfacePitch = surface.bytesPerRow
            videoCallback(baseAddress.assumingMemoryBound(to: UInt8.self), width, height, surfacePitch, format)
            surface.unlock(options: [], seed: nil)
        }
    }

    func stop() {
        guard useXPC else {
            LibretroBridgeSwift.stop()
            return
        }
        framePollingTimer?.cancel()
        framePollingTimer = nil
        XPCConnectionManager.shared.remoteProxy?.stop {}
        XPCConnectionManager.shared.disconnect()
        shmManager.cleanup()
        videoManager.cleanup()

        let delegate = CoreClientDelegate.shared
        delegate.onVideoFrame = nil
        delegate.onAudioAvailable = nil
        delegate.onGameLoaded = nil
        delegate.onCoreFailed = nil
        delegate.onGeometryChanged = nil
        delegate.onRotationChanged = nil
        delegate.onCoreOptionsV1 = nil
        delegate.onCoreOptionsV2 = nil
        delegate.onRcheevosAchievementTriggered = nil
        delegate.onRcheevosAchievementProgress = nil
        delegate.onRcheevosChallengeStarted = nil
        delegate.onRcheevosChallengeCancelled = nil
        gameLoadedHandler = nil
        hasLoggedPoll = false
    }

    func waitForCompletion() {
        guard !useXPC else { return }
        LibretroBridgeSwift.waitForCompletion()
    }

    // MARK: - Input (hot path — uses shared memory when available)

    func setKeyState(retroID: Int, player: Int = 0, pressed: Bool) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            xpc_shm_set_input_state(shm, Int32(player), Int32(retroID), pressed ? 1 : 0)
            return
        }
        guard useXPC else { LibretroBridgeSwift.setKeyState(retroID: retroID, player: player, pressed: pressed); return }
        XPCConnectionManager.shared.remoteProxy?.setKeyState(Int32(retroID), player: Int32(player), pressed: pressed) {}
    }

    func setAnalogState(_ index: Int, id: Int, value: Int32, player: Int = 0) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            xpc_shm_set_analog_state(shm, Int32(player), Int32(index), Int32(id), Int16(value))
            return
        }
        guard useXPC else { LibretroBridgeSwift.setAnalogState(index, id: id, value: value); return }
        XPCConnectionManager.shared.remoteProxy?.setAnalogState(player: Int32(player), stick: Int32(index), axis: Int32(id), value: value) {}
    }

    func setAnalogButtonState(retroID: Int, value: Int32, player: Int = 0) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            xpc_shm_set_analog_button(shm, Int32(player), Int32(retroID), Int16(clamping: value))
            return
        }
        guard useXPC else { LibretroBridgeSwift.setAnalogButtonState(retroID: retroID, player: player, value: value); return }
        XPCConnectionManager.shared.remoteProxy?.setAnalogButtonState(Int32(retroID), player: Int32(player), value: value) {}
    }

    func setTurboState(turboIdx: Int, active: Bool, targetButton: Int, player: Int = 0) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            xpc_shm_set_turbo_active(shm, Int32(player), Int32(turboIdx), active)
            xpc_shm_set_turbo_fireButton(shm, Int32(player), Int32(turboIdx), Int32(targetButton))
            return
        }
        guard useXPC else { LibretroBridgeSwift.setTurboState(turboIdx: turboIdx, active: active, targetButton: targetButton); return }
        XPCConnectionManager.shared.remoteProxy?.setTurboState([Int32(turboIdx), active ? 1 : 0, Int32(targetButton)]) {}
    }

    // MARK: - Keyboard / Mouse / Pointer (shared memory when available)

    func dispatchKeyboardEvent(keycode: UInt32, character: UInt32, modifiers: UInt32, down: Bool) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            xpc_shm_set_keyboard_state(shm, Int32(keycode), down)
        }
        guard useXPC else { LibretroBridgeSwift.dispatchKeyboardEvent(keycode: keycode, character: character, modifiers: modifiers, down: down); return }
        XPCConnectionManager.shared.remoteProxy?.dispatchKeyboardEvent(keycode: keycode, character: character, modifiers: modifiers, down: down) {}
    }

    func setMouseDeltaX(_ dx: Int16, y dy: Int16) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.mouse.delta_x = dx
            shm.pointee.mouse.delta_y = dy
            return
        }
        guard useXPC else { LibretroBridgeSwift.setMouseDeltaX(dx, y: dy); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "setMouseDeltaX without shared memory — XPC proxy path not implemented for mouse input")
    }

    func addMouseDelta(_ dx: Int16, y dy: Int16) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            let newX = Int32(shm.pointee.mouse.delta_x) + Int32(dx)
            let newY = Int32(shm.pointee.mouse.delta_y) + Int32(dy)
            shm.pointee.mouse.delta_x = Int16(max(-32767, min(32767, newX)))
            shm.pointee.mouse.delta_y = Int16(max(-32767, min(32767, newY)))
            return
        }
        guard useXPC else { LibretroBridgeSwift.addMouseDelta(dx, y: dy); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "addMouseDelta without shared memory — XPC proxy path not implemented for mouse input")
    }

    func setMouseButton(_ button: Int, pressed: Bool) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            if button == 0 {
                if pressed { shm.pointee.mouse.buttons |= 1 } else { shm.pointee.mouse.buttons &= ~1 }
            } else if button == 1 {
                if pressed { shm.pointee.mouse.buttons |= 2 } else { shm.pointee.mouse.buttons &= ~2 }
            } else if button == 2 {
                if pressed { shm.pointee.mouse.buttons |= 4 } else { shm.pointee.mouse.buttons &= ~4 }
            }
            return
        }
        guard useXPC else { LibretroBridgeSwift.setMouseButton(button, pressed: pressed); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "setMouseButton without shared memory — XPC proxy path not implemented for mouse input")
    }

    func addMouseWheelDelta(_ delta: Int16) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.mouse.wheel_delta += delta
            return
        }
        guard useXPC else { LibretroBridgeSwift.addMouseWheelDelta(delta); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "addMouseWheelDelta without shared memory — XPC proxy path not implemented for mouse input")
    }

    func resetMouseDeltas() {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.mouse.delta_x = 0
            shm.pointee.mouse.delta_y = 0
            shm.pointee.mouse.wheel_delta = 0
            return
        }
        guard useXPC else { LibretroBridgeSwift.resetMouseDeltas(); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "resetMouseDeltas without shared memory — XPC proxy path not implemented for mouse input")
    }

    func setAbsoluteMousePosition(_ x: Int16, y: Int16, override: Bool) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.mouse.absolute_position_override = override
            shm.pointee.mouse.absolute_x = x
            shm.pointee.mouse.absolute_y = y
            return
        }
        guard useXPC else { LibretroBridgeSwift.setAbsoluteMousePosition(x, y: y, override: override); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "setAbsoluteMousePosition without shared memory — XPC proxy path not implemented")
    }

    func setPointerPosition(_ x: Int16, y: Int16, pressed: Bool) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.pointer.pointer_x = x
            shm.pointee.pointer.pointer_y = y
            shm.pointee.pointer.pointer_pressed = pressed
            return
        }
        guard useXPC else { LibretroBridgeSwift.setPointerPosition(x, y: y, pressed: pressed); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "setPointerPosition without shared memory — XPC proxy path not implemented for pointer input")
    }

    func setAnalogMouseConfig(player: Int, enabled: Bool, sensitivity: Float, deadzone: Float, stickIndex: Int) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            xpc_shm_set_analog_mouse_config(shm, Int32(player), enabled, sensitivity, deadzone, Int32(stickIndex))
            return
        }
        guard useXPC else {
            LibretroBridgeSwift.setAnalogAsMouseEnabled(enabled, forPlayer: player)
            LibretroBridgeSwift.setAnalogAsMouseSensitivity(sensitivity, forPlayer: player)
            LibretroBridgeSwift.setAnalogAsMouseDeadzone(deadzone, forPlayer: player)
            LibretroBridgeSwift.setAnalogAsMouseStick(stickIndex, forPlayer: player)
            return
        }
        LoggerService.warning(category: "XPCBridgeAdapter", "setAnalogMouseConfig without shared memory — unsupported")
    }

    func setAnalogMouseDeltaX(_ dx: Int16, y dy: Int16) {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.mouse.analog_mouse_delta_x = dx
            shm.pointee.mouse.analog_mouse_delta_y = dy
            return
        }
        guard useXPC else { LibretroBridgeSwift.setAnalogMouseDeltaX(dx, y: dy); return }
        LoggerService.warning(category: "XPCBridgeAdapter", "setAnalogMouseDelta without shared memory — unsupported")
    }

    // MARK: - State / Settings (XPC async)

    func setPaused(_ paused: Bool) {
        guard useXPC else {
            LibretroBridgeSwift.setPaused(paused)
            return
        }
        if useSharedMemory, let shm = shmManager.sharedMemory {
            shm.pointee.isPaused = paused
        }
        XPCConnectionManager.shared.remoteProxy?.setPaused(paused) {}
    }

    func setSpeedMultiplier(_ multiplier: Float) {
        guard useXPC else {
            LibretroBridgeSwift.setSpeedMultiplier(multiplier)
            return
        }
        ensureXPCConnection()
        let sem = DispatchSemaphore(value: 0)
        var ackReceived = false
        XPCConnectionManager.shared.remoteProxy?.setSpeedMultiplier(multiplier) {
            ackReceived = true
            sem.signal()
        }
        if sem.wait(timeout: .now() + .milliseconds(500)) == .timedOut {
            LoggerService.warning(category: "TimeMachine", "setSpeedMultiplier XPC reply timed out")
        } else if !ackReceived {
            LoggerService.warning(category: "TimeMachine", "setSpeedMultiplier XPC reply: proxy returned nil")
        } else {
            LoggerService.debug(category: "TimeMachine", "setSpeedMultiplier reply ok")
        }
    }

    func resetGame() {
        guard useXPC else {
            LibretroBridgeSwift.resetGame()
            return
        }
        XPCConnectionManager.shared.remoteProxy?.resetGame {}
    }

    func setRewindEnabled(_ enabled: Bool, captureInterval: UInt32) {
        guard useXPC else {
            LibretroBridgeSwift.setRewindEnabled(enabled, captureInterval: captureInterval)
            return
        }
        ensureXPCConnection()
        XPCConnectionManager.shared.remoteProxy?.setRewindEnabled(enabled, captureInterval: captureInterval) {}
    }

    func setStateCaptureCallback(_ callback: ((Data, UInt64) -> Void)?) {
        if !useXPC {
            if let callback {
                LibretroBridgeSwift.setStateCaptureCallback(callback)
            }
            return
        }

        capturedStatePollTimer?.invalidate()
        capturedStatePollTimer = nil
        capturedStateLastFrame = 0

        if let callback {
            capturedStateCallback = callback
            ensureXPCConnection()
            // Poll the XPC service at ~20Hz for newly captured states. This is
            // less frequent than the per-frame capture interval (typically 3
            // frames), so the XPC traffic stays bounded. The XPC service
            // overwrites its latest slot each frame; we coalesce here.
            let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.pollCapturedState()
            }
            RunLoop.main.add(timer, forMode: .common)
            capturedStatePollTimer = timer
        } else {
            capturedStateCallback = nil
            XPCConnectionManager.shared.remoteProxy?.setRewindEnabled(false, captureInterval: 3) {}
        }
    }

    private var capturedStatePollTimer: Timer?
    private var capturedStateCallback: ((Data, UInt64) -> Void)?
    private var capturedStateLastFrame: UInt64 = 0

    private func pollCapturedState() {
        guard let callback = capturedStateCallback else { return }
        XPCConnectionManager.shared.remoteProxy?.consumeCapturedState { [weak self] state, frameIndex in
            guard let self else { return }
            guard let state, frameIndex > self.capturedStateLastFrame else { return }
            self.capturedStateLastFrame = frameIndex
            callback(state, frameIndex)
        }
    }

    func flushAudio() {
        guard useXPC else {
            LibretroBridgeSwift.flushAudio()
            return
        }
        ensureXPCConnection()
        XPCConnectionManager.shared.remoteProxy?.flushAudio() {}
    }

    func runSingleFrame() {
        guard useXPC else {
            LibretroBridgeSwift.runSingleFrame()
            return
        }
        ensureXPCConnection()
        XPCConnectionManager.shared.remoteProxy?.runSingleFrame() {}
    }

    func setFrameCount(_ frameCount: UInt64) {
        guard useXPC else {
            LibretroBridgeSwift.setFrameCount(frameCount)
            return
        }
        ensureXPCConnection()
        XPCConnectionManager.shared.remoteProxy?.setFrameCount(frameCount) {}
    }

    private func ensureXPCConnection() {
        if !XPCConnectionManager.shared.isConnected {
            XPCConnectionManager.shared.connect()
        }
    }

    func isPaused() -> Bool {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            return shm.pointee.isPaused
        }
        guard useXPC else { return LibretroBridgeSwift.isPaused() }
        var result = false
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.isPaused { paused in
            result = paused
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .milliseconds(500))
        return result
    }

    func currentRotation() -> Int {
        if useSharedMemory, let shm = shmManager.sharedMemory {
            return Int(shm.pointee.currentRotation)
        }
        guard useXPC else { return LibretroBridgeSwift.currentRotation() }
        var result = 0
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getCurrentRotation { rot in
            result = Int(rot)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .milliseconds(500))
        return result
    }

    func aspectRatio() -> Float {
        guard useXPC else { return LibretroBridgeSwift.aspectRatio() }
        var result: Float = 0
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getAspectRatio { ar in
            result = ar
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func audioSampleRate() -> Double {
        guard useXPC else { return LibretroBridgeSwift.audioSampleRate() }
        var result: Double = 44100.0
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getAudioSampleRate { rate in
            result = rate
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    // MARK: - Save States (XPC async with semaphore for sync needs)

    func serializeSize() -> Int {
        guard useXPC else { return LibretroBridgeSwift.serializeSize() }
        var result: Int = 0
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.serializeSize { size in
            result = size
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func serializeState() -> Data? {
        guard useXPC else { return LibretroBridgeSwift.serializeState() }
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.serializeState { data in
            result = data
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func unserializeState(_ data: Data) -> Bool {
        guard useXPC else { return LibretroBridgeSwift.unserializeState(data) }
        var result: Bool = false
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.unserializeState(data) { success in
            result = success
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    // MARK: - SRAM

    func getSaveRAMData() -> Data? {
        guard useXPC else { return LibretroBridgeSwift.getSaveRAMData() }
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getSaveRAMData { data in
            result = data
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func loadSaveRAMData(_ data: Data) -> Bool {
        guard useXPC else { return LibretroBridgeSwift.loadSaveRAMData(data) }
        var result: Bool = false
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.loadSaveRAMData(data) { success in
            result = success
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func saveDirectoryPath() -> String {
        return SaveDirectoryBridge.libretroSaveDirectoryPath()
    }

    // MARK: - Core Options

    func getOptionValue(forKey key: String) -> String? {
        guard useXPC else { return LibretroBridgeSwift.getOptionValue(forKey: key) }
        var result: String?
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getOptionValue(forKey: key) { value in
            result = value
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func setOptionValue(_ value: String, forKey key: String) {
        guard useXPC else {
            LibretroBridgeSwift.setOptionValue(value, forKey: key)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setOptionValue(value, forKey: key) {}
    }

    func setControllerPortDevice(_ port: Int, device: Int) {
        guard useXPC else {
            LibretroBridgeSwift.setControllerPortDevice(UInt32(port), device: UInt32(device))
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setControllerPortDevice(port: port, device: device) {}
    }

    func setVariablesUpdated() {
        guard useXPC else {
            LibretroBridgeSwift.setVariablesUpdated()
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setVariablesUpdated() {}
    }

    func setGenesisDeviceType(_ deviceType: UInt32) {
        guard useXPC else {
            LibretroBridgeSwift.setGenesisDeviceType(deviceType)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setGenesisDeviceType(Int(deviceType)) {}
    }

    func setWiiControllerType(_ deviceType: UInt32) {
        guard useXPC else {
            LibretroBridgeSwift.setWiiControllerType(deviceType)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setWiiControllerType(Int(deviceType)) {}
    }

    func setOptions(_ options: [String: String]) {
        guard useXPC else {
            for (key, value) in options {
                LibretroBridgeSwift.setOptionValue(value, forKey: key)
            }
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setOptions(options) {}
    }

    func getOptionsDictionary() -> [String: Any]? {
        guard useXPC else { return LibretroBridgeSwift.getOptionsDictionary() }
        var result: [String: Any]?
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getOptionsDictionary { dict in
            result = dict
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func getCategoriesDictionary() -> [String: Any]? {
        guard useXPC else { return LibretroBridgeSwift.getCategoriesDictionary() }
        var result: [String: Any]?
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getCategoriesDictionary { dict in
            result = dict
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func getInputDescriptorsDictionary() -> [String: Any]? {
        guard useXPC else { return LibretroBridge.getInputDescriptorsDictionary() }
        var result: [String: Any]?
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.getInputDescriptorsDictionary { dict in
            result = dict
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    func loadCoreForOptions(dylibPath: String, coreID: String, romPath: String?) {
        guard useXPC else {
            LibretroBridgeSwift.loadCoreForOptions(dylibPath, coreID: coreID, romPath: romPath)
            return
        }
        if !XPCConnectionManager.shared.isConnected {
            XPCConnectionManager.shared.connect()
        }
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.loadCoreForOptions(dylibPath: dylibPath, coreID: coreID, romPath: romPath) {
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(5))
    }

    func isCoreLoadedForOptions() -> Bool {
        guard useXPC else { return LibretroBridgeSwift.isCoreLoadedForOptions() }
        var result = false
        let sem = DispatchSemaphore(value: 0)
        XPCConnectionManager.shared.synchronousProxy?.isCoreLoadedForOptions { loaded in
            result = loaded
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(2))
        return result
    }

    // MARK: - Cheats

    func applyCheats(_ cheats: [[String: Any]]) {
        guard useXPC else {
            LibretroBridgeSwift.applyCheats(cheats)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.applyCheats(cheats) {}
    }

    func applyDirectMemoryCheats(_ cheats: [[String: Any]]) {
        guard useXPC else {
            LibretroBridgeSwift.applyDirectMemoryCheats(cheats)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.applyDirectMemoryCheats(cheats) {}
    }

    // MARK: - Language / Log Level

    func setLanguage(_ language: Int) {
        guard useXPC else {
            LibretroBridgeSwift.setLanguage(language)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setLanguage(language) {}
    }

    func setLogLevel(_ level: Int) {
        guard useXPC else {
            LibretroBridgeSwift.setLogLevel(level)
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setLogLevel(level) {}
    }

    func setAppLogLevel(_ rawValue: String) {
        guard useXPC else {
            if let level = LogLevel(rawValue: rawValue) {
                LoggerService.shared.setLevel(level)
            }
            return
        }
        XPCConnectionManager.shared.remoteProxy?.setAppLogLevel(rawValue) {}
    }

    // MARK: - RetroAchievements (rcheevos)

    /// Public event callbacks. In XPC mode the XPC service's rcheevos runtime
    /// fires these via `CoreClientDelegate`; in non-XPC mode the local runtime
    /// fires them directly. The runner wires these to RetroAchievementsService.
    var onRcheevosAchievementTriggered: ((Int) -> Void)?
    var onRcheevosAchievementProgress: ((Int, Int) -> Void)?
    var onRcheevosChallengeStarted: ((Int) -> Void)?
    var onRcheevosChallengeCancelled: ((Int) -> Void)?
    var onRcheevosRichPresence: ((String) -> Void)?

/// Local rcheevos runtime for non-XPC mode (headless / option discovery).
private var localRcheevosRuntime: RcheevosRuntime?
private var pendingRcheevosTriggers: [RcheevosAchievementTrigger]?
private var pendingRichPresenceScript: String?

func loadRcheevosAchievements(_ triggers: [RcheevosAchievementTrigger], richPresenceScript: String? = nil) {
    guard useXPC else {
        let runtime = RcheevosRuntime()
        wireLocalRcheevosCallbacks(runtime)
        runtime.loadGame(triggers: triggers)
        if let script = richPresenceScript {
            runtime.activateRichPresence(script: script)
        }
        localRcheevosRuntime = runtime
        return
    }
    guard let proxy = XPCConnectionManager.shared.remoteProxy else {
        pendingRcheevosTriggers = triggers
        pendingRichPresenceScript = richPresenceScript
        LoggerService.info(category: "XPCBridgeAdapter", "Stashing \(triggers.count) rcheevos triggers (proxy not ready)")
        return
    }
    sendRcheevosTriggers(triggers, richPresenceScript: richPresenceScript, proxy: proxy)
}

private func sendRcheevosTriggers(_ triggers: [RcheevosAchievementTrigger], richPresenceScript: String?, proxy: CoreHostProtocol) {
    let dicts: [[String: Any]] = triggers.map { entry in
        [
            "id": Int(entry.id),
            "title": entry.title,
            "trigger": entry.trigger,
            "isUnlocked": entry.isUnlocked,
        ]
    }
    LoggerService.info(category: "XPCBridgeAdapter", "Sending \(dicts.count) rcheevos triggers to XPC service")
    proxy.loadRcheevosAchievements(dicts, richPresenceScript: richPresenceScript) { reply in
            if let reply = reply, let ok = reply["ok"] as? Bool, !ok {
                let err = (reply["error"] as? String) ?? "unknown"
                LoggerService.error(category: "XPCBridgeAdapter", "loadRcheevosAchievements failed: \(err)")
            } else {
                LoggerService.info(category: "XPCBridgeAdapter", "loadRcheevosAchievements reply: ok")
            }
        }
    }

    func resetRcheevosTriggers() {
        guard useXPC else {
            localRcheevosRuntime?.resetTriggers()
            return
        }
        XPCConnectionManager.shared.remoteProxy?.resetRcheevosTriggers {}
    }

    func deactivateRcheevosAchievement(id: Int) {
        guard useXPC else {
            localRcheevosRuntime?.deactivateAchievement(id: UInt32(id))
            return
        }
        XPCConnectionManager.shared.remoteProxy?.deactivateRcheevosAchievement(id: id) {}
    }

    func deactivateRcheevos() {
        guard useXPC else {
            localRcheevosRuntime?.deactivateAllAchievements()
            localRcheevosRuntime = nil
            return
        }
        XPCConnectionManager.shared.remoteProxy?.deactivateRcheevos {}
    }

    private func wireLocalRcheevosCallbacks(_ runtime: RcheevosRuntime) {
        runtime.onAchievementTriggered = { [weak self] id in
            self?.onRcheevosAchievementTriggered?(id)
        }
        runtime.onAchievementProgress = { [weak self] id, value in
            self?.onRcheevosAchievementProgress?(id, value)
        }
        runtime.onChallengeStarted = { [weak self] id in
            self?.onRcheevosChallengeStarted?(id)
        }
        runtime.onChallengeCancelled = { [weak self] id in
            self?.onRcheevosChallengeCancelled?(id)
        }
        runtime.onRichPresence = { [weak self] message in
            self?.onRcheevosRichPresence?(message)
        }
    }
}


import Foundation
import IOSurface

final class CoreHostService: NSObject, NSXPCListenerDelegate {
	private var activeConnection: NSXPCConnection?
	private var activeImpl: CoreHostImplementation?
	private var isTerminating = false

    override init() {
        super.init()
        let listener = NSXPCListener.service()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.remoteObjectInterface = NSXPCInterface(with: CoreClientProtocol.self)
        let exportedInterface = NSXPCInterface(with: CoreHostProtocol.self)
        exportedInterface.setClasses(NSSet(object: IOSurface.self) as Set, for: #selector(CoreHostProtocol.setIOSurfaceForVideo(_:reply:)), argumentIndex: 0, ofReply: false)
        newConnection.exportedInterface = exportedInterface
        let impl = CoreHostImplementation()
        impl.clientProxy = newConnection.remoteObjectProxyWithErrorHandler({ _ in
            LoggerService.error(category: "XPC-Service", "Client proxy error")
        }) as? CoreClientProtocol
        newConnection.exportedObject = impl
        activeConnection = newConnection
        activeImpl = impl

	newConnection.interruptionHandler = { [weak self] in
			LoggerService.warning(category: "XPC-Service", "Connection interrupted — cleaning up and exiting")
			self?.terminate()
		}

		newConnection.invalidationHandler = { [weak self] in
			LoggerService.info(category: "XPC-Service", "Connection invalidated — cleaning up and exiting")
			self?.terminate()
		}

        newConnection.resume()
        return true
    }

    private func terminate() {
        guard !isTerminating else { return }
        isTerminating = true
        activeImpl?.cleanupForExit()
        activeImpl = nil
        activeConnection?.invalidate()
        activeConnection = nil
        LoggerService.info(category: "XPC-Service", "Exiting process after connection teardown")
        exit(0)
    }
}

class CoreHostImplementation: NSObject, CoreHostProtocol {
	private var sharedMemory: UnsafeMutablePointer<XPCSharedMemory>?
	private var videoSurface: IOSurface?
    var clientProxy: CoreClientProtocol?
	private var isRunning = false
	private var hasStopped = false

    // rcheevos lives here in the XPC service so its peek callback can read
    // libretro memory through the same `g_instance` that the core uses.
    private var rcheevosRuntime: RcheevosRuntime?
    private var rcheevosSystemID: String?
    private var rcheevosRuntimePtr: UnsafeMutableRawPointer?
    private var pendingRcheevosTriggers: [RcheevosAchievementTrigger]?
    private var pendingRichPresenceScript: String?

    private let capturedStateLock = NSLock()
    private var pendingCapturedStates: [(Data, UInt64)] = []
    // Small cap: the client polls at 20Hz and consumes one state per poll, and
    // the emulation produces ~20 states/sec (every 3 frames at 60fps), so this
    // buffer only holds a brief surplus during polling jitter. Capping by
    // count is fine here because each captured state can be several MB (e.g.
    // PPSSPP with FMV state), and a large cap bursts the XPC service's memory
    // whenever serialization outpaces the poll rate. The poller drains in
    // FIFO order, so a small cap retains ordering without losing snapshots
    // in steady state — and bounds memory instead of letting the queue grow
    // toward the full rewind window.
    private let maxPendingStates = 4

    private static func logMemoryFootprint(label: String) {
        var info = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return }
        let mb = Double(info.resident_size) / 1024.0 / 1024.0

        var vmInfo = task_vm_info()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
        let vmKerr = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        let footprintMB: Double
        if vmKerr == KERN_SUCCESS {
            footprintMB = Double(vmInfo.phys_footprint) / 1024.0 / 1024.0
        } else {
            footprintMB = -1
        }

        LoggerService.info(category: "XPC-Memory", "\(label): resident=\(String(format: "%.1f", mb))MB footprint=\(String(format: "%.1f", footprintMB))MB")
    }

    // Mirrors Play!'s CAppConfig::GetBasePath() (NSDocumentDirectory /
    // "Play Data Files") and pre-creates the vfs/mc0 and vfs/mc1 memory-card
    // directories the HLE BIOS looks for. Runs in the XPC host so
    // NSDocumentDirectory resolves the same way the core sees it.
    private static func ensurePlayMemoryCardDirectories() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            LoggerService.warning(category: "PS2-MemCard", "Could not resolve Documents directory for Play! memory cards")
            return
        }
        let vfs = documents
            .appendingPathComponent("Play Data Files", isDirectory: true)
            .appendingPathComponent("vfs", isDirectory: true)
        for card in ["mc0", "mc1"] {
            let cardDir = vfs.appendingPathComponent(card, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: cardDir, withIntermediateDirectories: true)
                LoggerService.info(category: "PS2-MemCard", "Ensured Play! memory card directory: \(cardDir.path)")
                // Documents is iCloud-synced by default. Existing card contents
                // may be dataless placeholders that read as empty/corrupt — pull
                // them down before the core opens the card.
                ICloudMaterializer.ensureDirectoryMaterialized(at: cardDir)
            } catch {
                LoggerService.error(category: "PS2-MemCard", "Failed to create \(cardDir.path): \(error.localizedDescription)")
            }
        }
    }

    override init() {
        super.init()
    }

	func cleanupForExit() {
		guard !hasStopped else {
			if let shm = sharedMemory {
				munmap(shm, MemoryLayout<XPCSharedMemory>.size)
				sharedMemory = nil
			}
			videoSurface = nil
			return
		}
		LibretroBridge.stop()
		LibretroBridge.waitForCompletion()
		LibretroBridge.cleanupInstance()
		Self.logMemoryFootprint(label: "post-cleanup")
		if let shm = sharedMemory {
			munmap(shm, MemoryLayout<XPCSharedMemory>.size)
			sharedMemory = nil
		}
		videoSurface = nil
	}

    func launch(dylibPath: String,
                 romPath: String,
                 coreID: String,
                 systemID: String?,
                 romFilename: String?,
                 shaderDir: String?,
                 saveDirectory: String,
                 systemDirectory: String,
                 language: Int,
                 logLevel: Int,
                 wiiControllerType: Int,
                 reply: @escaping (Bool, String?) -> Void) {

        SaveDirectoryBridge.setSavePath(saveDirectory)
        SaveDirectoryBridge.setSystemPath(systemDirectory)

        // Any of these paths may be iCloud-synced (Desktop & Documents sync, or
        // a user-chosen library folder). A dataless placeholder reads as
        // empty/corrupt to the core, so download the bytes before launch. The
        // ROM is materialized as a single file; system dir (BIOS, etc.) is
        // walked because the core reads specific files from it on demand.
        ICloudMaterializer.ensureMaterialized(at: URL(fileURLWithPath: romPath), timeout: 120)
        ICloudMaterializer.ensureDirectoryMaterialized(at: URL(fileURLWithPath: systemDirectory))

        // Play! (PS2) ignores GET_SAVE_DIRECTORY/GET_SYSTEM_DIRECTORY and stores
        // its virtual memory cards under NSDocumentDirectory/Play Data Files/vfs/
        // {mc0,mc1}. It only EnsurePathExists() during CPS2VM construction, so a
        // launch that aborts early (e.g. the old serialize crash) leaves the base
        // folder without the mc0/mc1 subdirs and the HLE BIOS reports "no memory
        // cards". Pre-create them here so a card is always present. These are
        // directory-backed cards — an empty directory is a valid blank card.
        if coreID.lowercased().contains("play_libretro") {
            Self.ensurePlayMemoryCardDirectories()
        }

		LibretroBridge.setLanguage(Int32(language))
		LibretroBridge.setLogLevel(Int32(logLevel))
        LibretroBridge.setPaused(false)
        isRunning = true
        Self.logMemoryFootprint(label: "pre-launch")

        let weakProxy = clientProxy
        LibretroBridge.registerGameLoadedCallback { romPath in
            let pathStr = String(cString: romPath)
            weakProxy?.gameLoaded(romPath: pathStr)
        }

        // Spin up the rcheevos runtime here so its peek callback reads through
        // the XPC service's `g_instance`. Triggers are loaded by the main app
        // via `loadRcheevosAchievements` once it has them.
        rcheevosSystemID = systemID
        let runtime = RcheevosRuntime(systemID: systemID)
        let weakProxy2 = clientProxy
        runtime.onAchievementTriggered = { id in
            weakProxy2?.rcheevosAchievementTriggered(id: id)
        }
        runtime.onAchievementProgress = { id, value in
            weakProxy2?.rcheevosAchievementProgress(id: id, value: value)
        }
        runtime.onChallengeStarted = { id in
            weakProxy2?.rcheevosChallengeStarted(id: id)
        }
        runtime.onChallengeCancelled = { id in
            weakProxy2?.rcheevosChallengeCancelled(id: id)
        }
        runtime.onRichPresence = { message in
            weakProxy2?.rcheevosRichPresenceUpdate(message: message)
        }
        rcheevosRuntime = runtime
        rcheevosRuntimePtr = Unmanaged.passUnretained(runtime).toOpaque()

        if let pending = pendingRcheevosTriggers {
            runtime.loadGame(triggers: pending)
            LoggerService.info(category: "XPC-Service", "Applied \(pending.count) stashed rcheevos triggers")
            if let script = pendingRichPresenceScript {
                runtime.activateRichPresence(script: script)
                LoggerService.info(category: "XPC-Service", "Applied stashed rich presence script")
            }
            pendingRcheevosTriggers = nil
            pendingRichPresenceScript = nil
        }

        var failureMsg: String?
        let videoCallback: (UnsafeRawPointer?, Int32, Int32, Int32, Int32) -> Void = { [weak self] data, w, h, pitch, format in
            self?.handleVideoFrame(data: data, width: Int(w), height: Int(h), pitch: Int(pitch), format: Int(format))
        }

		LibretroBridge.launch(withDylibPath: dylibPath,
							  romPath: romPath,
							  shaderDir: shaderDir,
							  videoCallback: videoCallback,
							  coreID: coreID,
							  systemID: systemID,
							  romFilename: romFilename,
							  wiiControllerType: Int32(wiiControllerType)) { msg in
			failureMsg = msg
		}
		Self.logMemoryFootprint(label: "post-launch")

        reply(failureMsg == nil, failureMsg)
    }

    private var hasLoggedVideoFrame = false
    private var hasLoggedRcheevosFrame = false

    private func handleVideoFrame(data: UnsafeRawPointer?, width: Int, height: Int, pitch: Int, format: Int) {
        if let shm = sharedMemory {
            shm.pointee.videoWidth = Int32(width)
            shm.pointee.videoHeight = Int32(height)
            shm.pointee.videoPitch = Int32(pitch)
            shm.pointee.videoFormat = Int32(format)
            if !hasLoggedVideoFrame {
                hasLoggedVideoFrame = true
                LoggerService.info(category: "XPC-Service", "handleVideoFrame: \(width)x\(height) pitch=\(pitch) format=\(format)")
            }
        } else {
            LoggerService.warning(category: "XPC-Service", "handleVideoFrame: sharedMemory is nil!")
        }

        guard let surface = videoSurface, width > 0, height > 0 else {
            if let shm = sharedMemory { xpc_shm_store_frameReady(shm, 1) }
            return
        }

        if width > surface.width || height > surface.height {
            if let shm = sharedMemory { xpc_shm_store_frameReady(shm, 1) }
            clientProxy?.geometryChanged(width: width, height: height, aspectRatio: LibretroBridge.aspectRatio())
            return
        }

        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        guard let data = data else { return }
        let dst = surface.baseAddress
        let dstPitch = surface.bytesPerRow

        if dstPitch == pitch {
            memcpy(dst, data, height * pitch)
        } else {
            for row in 0..<height {
                let src = data.advanced(by: row * pitch)
                let dstRow = dst.advanced(by: row * dstPitch)
                memcpy(dstRow, src, min(pitch, dstPitch))
            }
        }
        if let shm = sharedMemory { xpc_shm_store_frameReady(shm, 1) }

        // Tick rcheevos once per delivered frame, after the IOSurface is updated.
        // processFrame fires the event callback synchronously, which forwards to
        // the main app via the XPC client proxy.
        if let rt = rcheevosRuntime {
            if !hasLoggedRcheevosFrame {
                hasLoggedRcheevosFrame = true
                LoggerService.info(category: "XPC-Service", "rcheevos runtime present, calling processFrame")
            }
            rt.processFrame()
        } else if !hasLoggedRcheevosFrame {
            hasLoggedRcheevosFrame = true
            LoggerService.info(category: "XPC-Service", "rcheevos runtime is NIL in handleVideoFrame")
        }
    }

	func stop(reply: @escaping () -> Void) {
		isRunning = false
		hasStopped = true
		rcheevosRuntime?.deactivateAllAchievements()
		rcheevosRuntime = nil
		rcheevosRuntimePtr = nil
		LibretroBridge.stop()
		LibretroBridge.waitForCompletion()
		LibretroBridge.cleanupInstance()
		Self.logMemoryFootprint(label: "post-stop-cleanup")
		reply()
	}

    func setPaused(_ paused: Bool, reply: @escaping () -> Void) {
        LibretroBridge.setPaused(paused)
        if let shm = sharedMemory {
            shm.pointee.isPaused = paused
        }
        reply()
    }

    func setSpeedMultiplier(_ multiplier: Float, reply: @escaping () -> Void) {
        LoggerService.info(category: "TimeMachine", "XPC: setSpeedMultiplier(\(multiplier))")
        LibretroBridge.setSpeedMultiplier(multiplier)
        reply()
    }

    func resetGame(reply: @escaping () -> Void) {
        LibretroBridge.resetGame()
        reply()
    }

    func isPaused(reply: @escaping (Bool) -> Void) {
        reply(LibretroBridge.isPaused())
    }

    func setLanguage(_ language: Int, reply: @escaping () -> Void) {
        LibretroBridge.setLanguage(Int32(language))
        reply()
    }

    func setLogLevel(_ level: Int, reply: @escaping () -> Void) {
        LibretroBridge.setLogLevel(Int32(level))
        reply()
    }

    func setAppLogLevel(_ rawValue: String, reply: @escaping () -> Void) {
        if let level = LogLevel(rawValue: rawValue) {
            LoggerService.shared.setLevel(level)
        }
        reply()
    }

    func serializeSize(reply: @escaping (Int) -> Void) {
        reply(Int(LibretroBridge.serializeSize()))
    }

    func serializeState(reply: @escaping (Data?) -> Void) {
        reply(LibretroBridge.serializeState())
    }

    func unserializeState(_ data: Data, reply: @escaping (Bool) -> Void) {
        reply(LibretroBridge.unserializeState(data))
    }

    func setRewindEnabled(_ enabled: Bool, captureInterval: UInt32, reply: @escaping () -> Void) {
        LoggerService.info(category: "TimeMachine", "XPC: setRewindEnabled enabled=\(enabled) interval=\(captureInterval)")
        LibretroBridge.setRewindEnabled(enabled, captureInterval: captureInterval)
        if enabled {
            LibretroBridge.setStateCaptureCallback { [weak self] state, frameIndex in
                guard let self else { return }
                self.capturedStateLock.lock()
                self.pendingCapturedStates.append((state, frameIndex))
                while self.pendingCapturedStates.count > self.maxPendingStates {
                    self.pendingCapturedStates.removeFirst()
                }
                self.capturedStateLock.unlock()
            }
        } else {
            LibretroBridge.setStateCaptureCallback(nil)
            capturedStateLock.lock()
            pendingCapturedStates.removeAll(keepingCapacity: true)
            capturedStateLock.unlock()
        }
        reply()
    }

    func consumeCapturedState(reply: @escaping (Data?, UInt64) -> Void) {
        capturedStateLock.lock()
        defer { capturedStateLock.unlock() }
        if let oldest = pendingCapturedStates.first {
            pendingCapturedStates.removeFirst()
            reply(oldest.0, oldest.1)
        } else {
            reply(nil, 0)
        }
    }

    func flushAudio(reply: @escaping () -> Void) {
        LibretroBridge.flushAudio()
        reply()
    }

    func runSingleFrame(reply: @escaping () -> Void) {
        LibretroBridge.runSingleFrame()
        reply()
    }

    func setFrameCount(_ frameCount: UInt64, reply: @escaping () -> Void) {
        LibretroBridge.setFrameCount(frameCount)
        reply()
    }

    func getSaveRAMData(reply: @escaping (Data?) -> Void) {
        reply(LibretroBridge.getSaveRAMData())
    }

    func loadSaveRAMData(_ data: Data, reply: @escaping (Bool) -> Void) {
        reply(LibretroBridge.loadSaveRAMData(data))
    }

    func applyCheats(_ cheats: [[String: Any]], reply: @escaping () -> Void) {
        LibretroBridge.applyCheats(cheats)
        reply()
    }

    func applyDirectMemoryCheats(_ cheats: [[String: Any]], reply: @escaping () -> Void) {
        LibretroBridge.applyDirectMemoryCheats(cheats)
        reply()
    }

    func setOptionValue(_ value: String, forKey key: String, reply: @escaping () -> Void) {
        LibretroBridge.setOptionValue(value, forKey: key)
        reply()
    }

    func setOptions(_ options: [String: String], reply: @escaping () -> Void) {
        for (key, value) in options {
            LibretroBridge.setOptionValue(value, forKey: key)
        }
        reply()
    }

    func getOptionValue(forKey key: String, reply: @escaping (String?) -> Void) {
        reply(LibretroBridge.getOptionValue(forKey: key))
    }

    func resetOptionToDefault(forKey key: String, reply: @escaping () -> Void) {
        LibretroBridge.resetOptionToDefault(forKey: key)
        reply()
    }

    func resetAllOptionsToDefaults(reply: @escaping () -> Void) {
        LibretroBridge.resetAllOptionsToDefaults()
        reply()
    }

    func getOptionsDictionary(reply: @escaping ([String: Any]?) -> Void) {
        reply(LibretroBridge.getOptionsDictionary())
    }

    func getCategoriesDictionary(reply: @escaping ([String: Any]?) -> Void) {
        reply(LibretroBridge.getCategoriesDictionary())
    }

    func getInputDescriptorsDictionary(reply: @escaping ([String: Any]?) -> Void) {
        reply(LibretroBridge.getInputDescriptorsDictionary())
    }

    func getAspectRatio(reply: @escaping (Float) -> Void) {
        reply(LibretroBridge.aspectRatio())
    }

    func getCurrentRotation(reply: @escaping (Int) -> Void) {
        reply(Int(LibretroBridge.currentRotation()))
    }

    func getAudioSampleRate(reply: @escaping (Double) -> Void) {
        reply(LibretroBridge.audioSampleRate())
    }

    func setControllerPortDevice(port: Int, device: Int, reply: @escaping () -> Void) {
        LibretroBridge.setControllerPortDevice(UInt32(port), device: UInt32(device))
        reply()
    }

    func setVariablesUpdated(reply: @escaping () -> Void) {
        LibretroBridge.setVariablesUpdated()
        reply()
    }

    func setGenesisDeviceType(_ deviceType: Int, reply: @escaping () -> Void) {
        LibretroBridge.setGenesisDeviceType(UInt32(deviceType))
        reply()
    }

    func setWiiControllerType(_ deviceType: Int, reply: @escaping () -> Void) {
        LoggerService.info(category: "CoreHostService", "setWiiControllerType received deviceType=\(deviceType)")
        LibretroBridge.setWiiControllerType(UInt32(deviceType))
        reply()
    }

    func loadCoreForOptions(dylibPath: String, coreID: String, romPath: String?, reply: @escaping () -> Void) {
        LibretroBridge.loadCore(forOptions: dylibPath, coreID: coreID, romPath: romPath)
        reply()
    }

    func isCoreLoadedForOptions(reply: @escaping (Bool) -> Void) {
        reply(LibretroBridge.isCoreLoadedForOptions())
    }

    func setKeyStates(_ states: [Int: Bool], reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            for (id, pressed) in states {
                xpc_shm_set_input_state(shm, 0, Int32(id), pressed ? 1 : 0)
            }
        } else {
            for (id, pressed) in states {
                LibretroBridge.setKeyState(Int32(id), pressed: pressed)
            }
        }
        reply()
    }

    func setKeyState(_ id: Int32, pressed: Bool, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            xpc_shm_set_input_state(shm, 0, id, pressed ? 1 : 0)
        } else {
            LibretroBridge.setKeyState(id, pressed: pressed)
        }
        reply()
    }

    func setKeyState(_ id: Int32, player: Int32, pressed: Bool, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            xpc_shm_set_input_state(shm, player, id, pressed ? 1 : 0)
        } else {
            LibretroBridge.setKeyState(id, player: player, pressed: pressed)
        }
        reply()
    }

    func setAnalogStates(_ states: [[Int]], reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            for state in states {
                guard state.count == 3 else { continue }
                xpc_shm_set_analog_state(shm, 0, Int32(state[0]), Int32(state[1]), Int16(state[2]))
            }
        } else {
            for state in states {
                guard state.count == 3 else { continue }
                LibretroBridge.setAnalogState(Int32(state[0]), id: Int32(state[1]), value: Int32(state[2]))
            }
        }
        reply()
    }

    func setAnalogState(_ state: [Int32], reply: @escaping () -> Void) {
        if let shm = sharedMemory, state.count == 3 {
            xpc_shm_set_analog_state(shm, 0, state[0], state[1], Int16(state[2]))
        } else if state.count == 3 {
            LibretroBridge.setAnalogState(state[0], id: state[1], value: state[2])
        }
        reply()
    }

    func setAnalogState(player: Int32, stick: Int32, axis: Int32, value: Int32, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            xpc_shm_set_analog_state(shm, player, stick, axis, Int16(value))
        } else {
            LibretroBridge.setAnalogStateForPlayer(player, stick: stick, axis: axis, value: value)
        }
        reply()
    }

    func setAnalogButtonStates(_ states: [Int: Int32], reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            for (id, val) in states {
                xpc_shm_set_analog_button(shm, 0, Int32(id), Int16(clamping: val))
            }
        } else {
            for (id, val) in states {
                LibretroBridge.setAnalogButtonState(Int32(id), value: Int32(val))
            }
        }
        reply()
    }

    func setAnalogButtonState(_ id: Int32, value: Int32, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            xpc_shm_set_analog_button(shm, 0, id, Int16(clamping: value))
        } else {
            LibretroBridge.setAnalogButtonState(id, value: value)
        }
        reply()
    }

    func setAnalogButtonState(_ id: Int32, player: Int32, value: Int32, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            xpc_shm_set_analog_button(shm, player, id, Int16(clamping: value))
        } else {
            LibretroBridge.setAnalogButtonState(id, player: player, value: value)
        }
        reply()
    }

    func setTurboStates(_ states: [[Int]], reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            for state in states {
                guard state.count == 3 else { continue }
                xpc_shm_set_turbo_active(shm, 0, Int32(state[0]), state[1] != 0)
                xpc_shm_set_turbo_fireButton(shm, 0, Int32(state[0]), Int32(state[2]))
            }
        } else {
            for state in states {
                guard state.count == 3 else { continue }
                LibretroBridge.setTurboState(Int32(state[0]), active: state[1] != 0, targetButton: Int32(state[2]))
            }
        }
        reply()
    }

    func setTurboState(_ state: [Int32], reply: @escaping () -> Void) {
        if let shm = sharedMemory, state.count == 3 {
            xpc_shm_set_turbo_active(shm, 0, state[0], state[1] != 0)
            xpc_shm_set_turbo_fireButton(shm, 0, state[0], state[2])
        } else if state.count == 3 {
            LibretroBridge.setTurboState(state[0], active: state[1] != 0, targetButton: state[2])
        }
        reply()
    }

    func setKeyboardStates(_ states: [Int: Bool], reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            for (id, pressed) in states {
                xpc_shm_set_keyboard_state(shm, Int32(id), pressed)
            }
        }
        reply()
    }

    func setMouseState(deltaX: Int16, deltaY: Int16, wheelDelta: Int16, buttons: UInt32, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            shm.pointee.mouse.delta_x = deltaX
            shm.pointee.mouse.delta_y = deltaY
            shm.pointee.mouse.wheel_delta = wheelDelta
            shm.pointee.mouse.buttons = buttons
        }
        reply()
    }

    func setPointerPosition(x: Int16, y: Int16, pressed: Bool, reply: @escaping () -> Void) {
        if let shm = sharedMemory {
            shm.pointee.pointer.pointer_x = x
            shm.pointee.pointer.pointer_y = y
            shm.pointee.pointer.pointer_pressed = pressed
        }
        reply()
    }

    func dispatchKeyboardEvent(keycode: UInt32, character: UInt32, modifiers: UInt32, down: Bool, reply: @escaping () -> Void) {
        LibretroBridge.dispatchKeyboardEvent(keycode, character: character, modifiers: modifiers, down: down)
        reply()
    }

    func setSharedMemoryName(_ name: String, reply: @escaping () -> Void) {
        let fd = xpc_shm_open(name, O_RDWR, 0o600)
        guard fd >= 0 else {
            LoggerService.error(category: "XPC-Service", "shm_open failed for \(name)")
            reply()
            return
        }

        let size = MemoryLayout<XPCSharedMemory>.size
        let ptr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        close(fd)

        guard let rawPtr = ptr, Int(bitPattern: rawPtr) != Int(bitPattern: MAP_FAILED) else {
            LoggerService.error(category: "XPC-Service", "mmap failed for shared memory")
            reply()
            return
        }

        sharedMemory = rawPtr.assumingMemoryBound(to: XPCSharedMemory.self)
        xpc_shm_set_global(sharedMemory)
        LoggerService.info(category: "XPC-Service", "Mapped shared memory: \(name)")
        reply()
    }

    func setIOSurfaceForVideo(_ surface: IOSurface?, reply: @escaping () -> Void) {
        videoSurface = surface
        LoggerService.info(category: "XPC-Service", "Received IOSurface: \(surface != nil ? "yes" : "nil")")
        reply()
    }

    // MARK: - RetroAchievements (rcheevos)

    func loadRcheevosAchievements(_ triggers: [[String: Any]], richPresenceScript: String?, reply: @escaping ([String: Any]?) -> Void) {
        let entries: [RcheevosAchievementTrigger] = triggers.compactMap { dict in
            guard let id = (dict["id"] as? NSNumber)?.uint32Value,
                  let trigger = dict["trigger"] as? String else { return nil }
            let title = (dict["title"] as? String) ?? ""
            let rawUnlocked = dict["isUnlocked"]
            let isUnlocked: Bool
            if let b = rawUnlocked as? Bool {
                isUnlocked = b
            } else if let n = rawUnlocked as? NSNumber {
                isUnlocked = n.boolValue
            } else if let n = rawUnlocked as? Int {
                isUnlocked = n != 0
            } else {
                isUnlocked = false
                LoggerService.error(category: "XPC-Service", "rcheevos isUnlocked unexpected type: \(type(of: rawUnlocked)) val=\(rawUnlocked ?? "nil")")
            }
            return RcheevosAchievementTrigger(id: id, title: title, trigger: trigger, isUnlocked: isUnlocked)
        }

        let unlockedCount = entries.filter(\.isUnlocked).count
        LoggerService.info(category: "XPC-Service", "Parsed \(entries.count) rcheevos triggers, \(unlockedCount) unlocked")

        if let runtime = rcheevosRuntime {
            runtime.loadGame(triggers: entries)
            if let script = richPresenceScript {
                runtime.activateRichPresence(script: script)
            }
            reply(["ok": true, "count": entries.count])
        } else {
            pendingRcheevosTriggers = entries
            pendingRichPresenceScript = richPresenceScript
            LoggerService.info(category: "XPC-Service", "Stashed \(entries.count) rcheevos triggers (runtime not ready)")
            reply(["ok": true, "count": entries.count, "stashed": true])
        }
    }

    func resetRcheevosTriggers(reply: @escaping () -> Void) {
        rcheevosRuntime?.resetTriggers()
        reply()
    }

    func deactivateRcheevosAchievement(id: Int, reply: @escaping () -> Void) {
        rcheevosRuntime?.deactivateAchievement(id: UInt32(id))
        reply()
    }

    func deactivateRcheevos(reply: @escaping () -> Void) {
        rcheevosRuntime?.deactivateAllAchievements()
        rcheevosRuntime = nil
        rcheevosRuntimePtr = nil
        reply()
    }

    func ping(reply: @escaping () -> Void) {
        reply()
    }
}

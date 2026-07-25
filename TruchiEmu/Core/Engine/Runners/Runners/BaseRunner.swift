import MetalKit
import Foundation
import SwiftUI
import GameController
import AppKit
import Combine

// Import the GameError definition
// Since it's in the same module, we don't necessarily need an import if it's part of the same target,
// but we might need to ensure it's accessible.

// MARK: - MTLTexture to NSImage conversion

// Convert MTLTexture to NSImage using Metal texture bytes directly
func NSImageFromMTLTexture(_ texture: MTLTexture) -> NSImage? {
    let width = texture.width
    let height = texture.height
    
    guard width > 0 && height > 0 else { return nil }
    
    var bytesPerPixel: Int
    let region = MTLRegionMake2D(0, 0, width, height)
    
    // Handle different pixel formats
    switch texture.pixelFormat {
    case .bgra8Unorm, .rgba8Unorm, .rgba8Unorm_srgb:
        // 32-bit formats (XRGB8888, RGBA)
        bytesPerPixel = 4
    case .b5g6r5Unorm, .a1bgr5Unorm, .bgr5A1Unorm:
        // 16-bit formats (RGB565, 1555, 5551)
        bytesPerPixel = 2
    case .r8Unorm:
        // 8-bit grayscale fallback
        bytesPerPixel = 1
    default:
        LoggerService.error(category: "SaveState", "Unsupported pixel format: \(texture.pixelFormat.rawValue)")
        return nil
    }
    
    let bytesPerRow = width * bytesPerPixel
    let byteCount = width * height * bytesPerPixel
    
    var byteArray = [UInt8](repeating: 0, count: byteCount)
    
    byteArray.withUnsafeMutableBytes { pointer in
        texture.getBytes(
            pointer.baseAddress!,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )
    }
    
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    
    var cgImage: CGImage?
    
    switch texture.pixelFormat {
    case .bgra8Unorm:
        // BGRA8888 — Metal stores B@0 G@1 R@2 A@3
        // premultipliedFirst + byteOrder32Little:
        //   Native (big-endian) ARGB → swapped → [B, G, R, A] in memory
        //   byte 3 = A, byte 2 = R, byte 1 = G, byte 0 = B
        //   Force A=0xFF since libretro XRGB8888 has X(alpha)=0,
        //   preventing premultiplied alpha from zeroing color channels.
        var forcedAlpha = byteArray
        for i in 0..<(width * height) {
            forcedAlpha[i * 4 + 3] = 0xFF
        }
        let provider = CGDataProvider(data: Data(forcedAlpha) as CFData)
        if let provider = provider {
            cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
        
    case .rgba8Unorm, .rgba8Unorm_srgb:
        // RGBA8888 — Metal stores R@0 G@1 B@2 A@3
        // byteOrder32Big + last: byte 0 = R, byte 1 = G, byte 2 = B, byte 3 = A
        // Force A=0xFF since libretro cores typically set the alpha byte to 0.
        var forcedAlpha = byteArray
        for i in 0..<(width * height) {
            forcedAlpha[i * 4 + 3] = 0xFF
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            .union(.byteOrder32Big)
        let provider = CGDataProvider(data: Data(forcedAlpha) as CFData)
        if let provider = provider {
            cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
        
    case .b5g6r5Unorm:
        // RGB565 - expand to RGBA8888
        let expanded = expandRGB565toRGBA(from: byteArray, width: width, height: height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            .union(.byteOrder32Big)
        let provider = CGDataProvider(data: Data(expanded) as CFData)
        if let provider = provider {
            cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
        
case .a1bgr5Unorm, .bgr5A1Unorm:
        // ARGB1555 / BGR5A1 - expand to RGBA8888
        let expanded = expandARGB1555toRGBA(from: byteArray, width: width, height: height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            .union(.byteOrder32Big)
        let provider = CGDataProvider(data: Data(expanded) as CFData)
        if let provider = provider {
            cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
        
    case .r8Unorm:
        // 8-bit grayscale - replicate into RGBA channels with full alpha
        let expanded = expandR8toRGBA(from: byteArray, width: width, height: height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            .union(.byteOrder32Big)
        let provider = CGDataProvider(data: Data(expanded) as CFData)
        if let provider = provider {
            cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
        
    default:
        return nil
    }
    
    guard let image = cgImage else { return nil }
    
    return NSImage(cgImage: image, size: NSSize(width: width, height: height))
}

// Expand RGB565 data to RGBA8888
private func expandRGB565toRGBA(from data: [UInt8], width: Int, height: Int) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: width * height * 4)
    let srcCount = data.count / 2  // number of 16-bit pixels
    
    for i in 0..<srcCount {
        let offset = i * 2
        // Handle endianness - read as little-endian 16-bit
        let pixel = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        
        // Extract RGB565 components
        let r = Int((pixel >> 11) & 0x1F)
        let g = Int((pixel >> 5) & 0x3F)
        let b = Int(pixel & 0x1F)
        
        // Expand to 8-bit
        let expandedR = UInt8((r << 3) | (r >> 2))  // 5 -> 8 bits
        let expandedG = UInt8((g << 2) | (g >> 4))  // 6 -> 8 bits
        let expandedB = UInt8((b << 3) | (b >> 2))  // 5 -> 8 bits
        
        // Write as RGBA (byteOrder32Big + premultipliedLast = R@0 G@1 B@2 A@3)
        let dstOffset = i * 4
        result[dstOffset] = expandedR       // R
        result[dstOffset + 1] = expandedG   // G
        result[dstOffset + 2] = expandedB   // B
        result[dstOffset + 3] = 0xFF        // A
    }
    
    return result
}

// Expand ARGB1555 data to RGBA8888
private func expandARGB1555toRGBA(from data: [UInt8], width: Int, height: Int) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: width * height * 4)
    let srcCount = data.count / 2  // number of 16-bit pixels
    
    for i in 0..<srcCount {
        let offset = i * 2
        // Handle endianness - read as little-endian 16-bit
        let pixel = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        
        // Extract ARGB1555 components (A1R5G5B5 format)
        let a = Int((pixel >> 15) & 0x1)
        let r = Int((pixel >> 10) & 0x1F)
        let g = Int((pixel >> 5) & 0x1F)
        let b = Int(pixel & 0x1F)
        
        // Expand to 8-bit
        let expandedR = UInt8((r << 3) | (r >> 2))
        let expandedG = UInt8((g << 3) | (g >> 2))
        let expandedB = UInt8((b << 3) | (b >> 2))
        let expandedA = a == 0 ? UInt8(0x00) : UInt8(0xFF)
        
        // Write as RGBA (byteOrder32Big + premultipliedLast = R@0 G@1 B@2 A@3)
        let dstOffset = i * 4
        result[dstOffset] = expandedR       // R
        result[dstOffset + 1] = expandedG   // G
        result[dstOffset + 2] = expandedB   // B
        result[dstOffset + 3] = expandedA   // A
    }
    
    return result
}

// Expand 8-bit grayscale data to RGBA8888
private func expandR8toRGBA(from data: [UInt8], width: Int, height: Int) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: width * height * 4)

    for i in 0..<(width * height) {
        let gray = data[i]
        let dstOffset = i * 4
        result[dstOffset] = gray       // R
        result[dstOffset + 1] = gray   // G
        result[dstOffset + 2] = gray   // B
        result[dstOffset + 3] = 0xFF   // A
    }

    return result
}

class EmulatorRunner: ObservableObject, @unchecked Sendable {
    @MainActor weak var metalView: MTKView?
    @MainActor @Published var currentFrameTexture: MTLTexture? = nil
    @MainActor @Published var currentFrameRotation: Int = 0  // 0, 1, 2, 3 = 0, 90, 180, 270 CW
    
    // Whether the first frame has been received and the view is ready for display.
    // Used to prevent showing the window before game content is ready (avoids bezel flash).
    @MainActor @Published var isReadyForDisplay: Bool = false
    
    // Reference to the game window for input capture
    @MainActor weak var window: NSWindow?
    nonisolated(unsafe) var gameWindow: NSWindow?
    
    // MARK: - Save State
    @MainActor @Published var currentSlot: Int = 0
    @MainActor @Published var osdMessage: String?
    var undoBuffer: Data?
    var onSaveStateLoaded: ((Int) -> Void)?
    var onSaveStateSaved: ((Int) -> Void)?
    var onGameReset: (() -> Void)?
    
    var systemID: String = "default"
    var activeCoreID: String = ""

    var analogMouseTimer: Timer?
    var analogMouseButtonLeft: String = "a"
    var analogMouseButtonDownRight: String = "b"
    var analogMouseButtonDownMiddle: String = "x"
    var analogMouseAccumulatedDX: Float = 0
    var analogMouseAccumulatedDY: Float = 0
    var sidebarCursorX: CGFloat?
    var sidebarCursorY: CGFloat?

    // Whether the current core supports save states
    var supportsSaveStates: Bool {
        // Play! (PS2) reports a non-zero serialize size but crashes inside
        // retro_serialize (CSIF::SaveState) when the memory-card subsystem is
        // in an inconsistent state. Treat it as unsupported until the core can
        // serialize reliably.
        if activeCoreID.lowercased().contains("play_libretro") {
            return false
        }
        return XPCBridgeAdapter.shared.serializeSize() > 0
    }
    
    internal var device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var emulationQueue = DispatchQueue(label: "truchiemu.emulation", qos: .userInteractive)
    internal var isRunning = false
    private var hasLoggedFrame = false
    private var runnerFrameCount = 0
    private var textureCache: MTLTexture? = nil
    private var rfTextureCache: MTLTexture? = nil
    private let rfDecoder = RfDecoderBridge()
    private let textureLock = NSLock()
    @MainActor @Published var rom: ROM?
    @MainActor @Published var lastError: GameError?
    var romPath: String = ""
    private var analogButtonStates: [RetroButton: Float] = [:]
    @MainActor @Published private(set) var currentInputState: [Int: Bool] = [:]
    
    // Expose saveManager for UI access
    var saveManager: SaveStateManager { _saveManager }
    private let _saveManager = SaveStateManager()
    // Keyboard mapping snapshots per player, captured at launch — safe to read from any thread.
    var cachedKeyboardMappings: [Int: KeyboardMapping] = [1: KeyboardMapping(buttons: [:])]
    // Controller share button binding identifier captured at launch.
    // Single physical button; tapped briefly → ShareBehavior.singlePress,
    // held longer → ShareBehavior.longPress. Dispatched via
    // ControllerLongPressDetector (BaseRunner.handleSharePress).
    var cachedShareButtonBinding: String? = nil
    // Time machine controller binding identifiers captured at launch.
    var cachedRewindBinding: String? = nil
    var cachedSlowMotionBinding: String? = nil
    var cachedFastForwardBinding: String? = nil
    // Quick save / quick load controller binding identifiers captured at
    // launch (per-system cache; only populated when the per-system override
    // or global default assigns a controller button).
    var cachedSaveStateBinding: String? = nil
    var cachedLoadStateBinding: String? = nil
    var cachedPauseBinding: String? = nil
    var cachedToggleGuideSidebarBinding: String? = nil
    private var hookedController: GCController? = nil
    private var hookedControllers: [Int: GCController] = [:]
    
    // Turbo button state tracking
    private var activeTurboButtons: Set<RetroButton> = []

    // Time machine / rewind buffer
    var timeMachineBuffer: TimeMachineBuffer = TimeMachineBuffer()

    // rcheevos achievement detection — the actual RcheevosRuntime lives in
    // the XPC service (so its peek callback can read libretro memory). This
    // runner just feeds triggers in and listens for events back.
    var rcheevosAchievements: [Achievement]?
    var rcheevosRichPresenceScript: String?
    private let rcheevosLock = NSLock()
    private var _needsRcheevosReset = false
    
    static func forSystem(_ systemID: String?) -> EmulatorRunner {
        let runner: EmulatorRunner
        switch systemID {
        case "nes":      runner = NESRunner()
        case "snes":     runner = SNESRunner()
        case "n64":      runner = N64Runner()
        case "dos":      runner = DOSRunner()
case "scummvm": runner = ScummVMRunner()
        case "saturn": runner = SaturnRunner()
        default: runner = EmulatorRunner()
        }
        runner.systemID = systemID ?? "default"
        return runner
    }



    @MainActor
    open func launch(rom: ROM, coreID: String, shaderUniformOverrides: [String: Float] = [:]) {
        if findCoreLib(coreID: coreID) == nil {
            LoggerService.error(category: "Runner", "Core dylib not found: \(coreID)")
            lastError = .coreNotFound(coreID: coreID)
            isRunning = false
            self.stop()
            return
        }
        
        self.rom = rom
        self.activeCoreID = coreID

        if ArchiveExtractor.isArchive(url: rom.path)
            && !ArchiveExtractor.isArchiveAwareCore(coreID)
            && !ArchiveExtractor.isArchiveAwareSystem(rom.systemID) {
            do {
                let extractedFiles = try ArchiveExtractor.shared.extract(url: rom.path, systemID: rom.systemID)
                let selectedFile: URL
                if let innerPath = rom.innerROMPath {
                    let innerName = URL(fileURLWithPath: innerPath).lastPathComponent
                    if let match = extractedFiles.first(where: { $0.lastPathComponent == innerName }) {
                        selectedFile = match
                        LoggerService.info(category: "Runner", "Using extracted ROM (innerROMPath): \(match.lastPathComponent)")
                    } else {
                        selectedFile = extractedFiles[0]
                        LoggerService.info(category: "Runner", "Inner ROM '\(innerName)' not found in extraction, using first: \(extractedFiles[0].lastPathComponent)")
                    }
                } else if let best = pickBestROM(from: extractedFiles, systemID: rom.systemID) {
                    selectedFile = best
                    LoggerService.info(category: "Runner", "Using extracted ROM: \(best.lastPathComponent)")
                } else {
                    selectedFile = extractedFiles[0]
                    LoggerService.info(category: "Runner", "Using first extracted file: \(extractedFiles[0].lastPathComponent)")
                }
                self.romPath = selectedFile.path
            } catch {
                LoggerService.error(category: "Runner", "Archive extraction failed: \(error.localizedDescription)")
                lastError = .launchFailed(reason: error.localizedDescription)
                isRunning = false
                self.stop()
                return
            }
        } else {
            self.romPath = rom.path.path
        }
        let sysID = rom.systemID ?? "default"
        let cs = ControllerService.shared
        let kbPlayer = cs.connectedControllers.first(where: { $0.isKeyboard })
        let assignedPlayers = kbPlayer?.assignedPlayers ?? [1]
        var mappings: [Int: KeyboardMapping] = [:]
        for player in assignedPlayers {
            var mapping = cs.keyboardMapping(for: sysID, player: player)
            if mapping.buttons.isEmpty {
                mapping = KeyboardMapping.defaults(for: sysID)
            }
            mappings[player] = mapping
        }
        self.cachedKeyboardMappings = mappings
        
        setupGamepadInput()
        SDLInputManager.shared.registerRunner(self)

        isRunning = true
        
        let selectedLang = SystemPreferences.shared.systemLanguage.libretroRawValue
        let selectedLogLevel = LoggerService.shared.currentLevel.coreLogLevelValue
        
        // Track last loaded core so Options view knows which file to persist to
        AppSettings.set("lastLoadedCoreID", value: coreID)

        let shaderDir = Bundle.main.resourceURL?.appendingPathComponent("slang-shaders").path

        let capturedMemoryBudgetMB = AppSettings.getInt("timeMachine_memoryMB", defaultValue: 256)
        let capturedMasterEnabled = AppSettings.getBool("timeMachine_enabled", defaultValue: true)
        let capturedRewindEnabled = capturedMasterEnabled && AppSettings.getBool("timeMachine_rewindEnabled", defaultValue: true)

        // Register callback to load SRAM when game is loaded. We also
        // finish setting up the time machine buffer from here — running it
        // post-launch guarantees the XPC service is fully up and accepting
        // state-capture requests. Trying earlier races against launch
        // handshake and gets silently dropped.
        XPCBridgeAdapter.shared.registerGameLoadedCallback { [weak self] romPath in
            self?.loadSRAMOnGameLoad(romPath: romPath)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .gameLoaded, object: nil)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard capturedRewindEnabled else {
                    // Time Machine (or rewind) is disabled — don't allocate or capture.
                    LoggerService.info(category: "TimeMachine", "Rewind disabled in settings — buffer not allocated")
                    return
                }
                // Dolphin's retro_serialize runs the full State::DoState on its own
                // internal CPU thread, which has no GL context current. The GL state
                // serializer (OGL::OGLStagingTexture::Create) calls glGenBuffers there
                // and crashes. Save states are already disabled for dolphin
                // (see isDolphinCore()); skip rewind for the same reason.
                if coreID.lowercased().contains("dolphin") {
                    LoggerService.warning(category: "TimeMachine", "Rewind not supported for Dolphin cores — buffer not allocated")
                    return
                }
                // Play! (PS2) crashes inside retro_serialize (CSIF::SaveState ->
                // SaveCallReplies) when the SIF/memory-card subsystem is in an
                // inconsistent state — e.g. no memory cards available. The fault
                // is a native C++ crash that ObjC @catch cannot recover from.
                // Skip rewind capture for this core (see supportsSaveStates).
                if coreID.lowercased().contains("play_libretro") {
                    LoggerService.warning(category: "TimeMachine", "Rewind not supported for Play! (PS2) core — buffer not allocated")
                    return
                }
                let memoryBudget = capturedMemoryBudgetMB * 1024 * 1024
                self.timeMachineBuffer = TimeMachineBuffer(maxMemoryBytes: memoryBudget)
                let coreStateSize = XPCBridgeAdapter.shared.serializeSize()
                if coreStateSize > 0 {
                    self.timeMachineBuffer.configure(stateSize: coreStateSize)
                    XPCBridgeAdapter.shared.setRewindEnabled(true, captureInterval: UInt32(self.timeMachineBuffer.captureInterval))
                    XPCBridgeAdapter.shared.setStateCaptureCallback { [weak self] state, frameIndex in
                        self?.timeMachineBuffer.push(frameIndex: frameIndex, data: state)
                    }
                } else {
                    LoggerService.warning(category: "TimeMachine", "serializeSize returned 0 after game loaded — rewind disabled")
                }
            }
        }

        let savedDir = XPCBridgeAdapter.shared.saveDirectoryPath()
        LoggerService.info(category: "Runner", "Using save directory: \(savedDir)")

        let rom = self.rom
        let dylibPath = self.findCoreLib(coreID: coreID) ?? coreID
        let cachedAchievements = self.rcheevosAchievements ?? []
        let resolvedRomPath = self.romPath
        let genesisControllerType = AppSettings.getGenesisControllerType()
        let wiiControllerType = AppSettings.getWiiControllerType()
        let hasRealController = !ControllerService.shared.connectedControllers.contains { !$0.isKeyboard }

        emulationQueue.async { [cachedAchievements, genesisControllerType] in
            XPCBridgeAdapter.shared.setLanguage(selectedLang)
            XPCBridgeAdapter.shared.setLogLevel(Int(selectedLogLevel))

            // Ensure save directories are created and configured
            SaveDirectoryBridge.ensureDirectoriesExist()

            guard let rom = rom else { return }

            let romPath = resolvedRomPath
            let systemID = rom.systemID

            let lowerCoreID = coreID.lowercased()
            let lowerSystemID = systemID?.lowercased() ?? ""
            let isGenesisCore = lowerCoreID.contains("genesis_plus_gx") || lowerCoreID.contains("picodrive")
            let isGenesisSystem = lowerSystemID == "genesis" || lowerSystemID == "megadrive" || lowerSystemID == "32x"
            if isGenesisCore && isGenesisSystem {
                let deviceType: UInt32 = genesisControllerType == .sixButton ? 514 : 513
                XPCBridgeAdapter.shared.setGenesisDeviceType(deviceType)
                if lowerCoreID.contains("picodrive") {
                    let options = CoreOverrideService.shared.picodriveGenesisOptions(sixButton: genesisControllerType == .sixButton)
                    for (key, value) in options {
                        XPCBridgeAdapter.shared.setOptionValue(value, forKey: key)
                    }
                    if !options.isEmpty {
                        XPCBridgeAdapter.shared.setVariablesUpdated()
                    }
                }
            } else {
                XPCBridgeAdapter.shared.setGenesisDeviceType(0)
            }

            // Wii (Dolphin): tell the core which controller subtype is attached.
            // Auto mode picks Wiimote + Classic Controller when a real controller
            // (GC or SDL) is connected, otherwise a plain Wiimote. The override
            // forces a specific subtype regardless of controller presence.
            // The value is passed as a launch parameter (deterministic) rather
            // than a separate fire-and-forget XPC message (which raced the
            // launch dispatch and was observed reaching the core as 0).
            let isDolphinCore = lowerCoreID.contains("dolphin")
            var wiiDeviceForLaunch: Int = 0
            if isDolphinCore {
                let device: UInt32
                if let forced = wiiControllerType.deviceValue {
                    device = forced
                } else {
                    device = hasRealController ? 1025 : 1
                }
                wiiDeviceForLaunch = Int(device)
                LoggerService.info(category: "BaseRunner", "WiiDeviceResolve wiiControllerType=\(wiiControllerType.rawValue) hasRealController=\(hasRealController) resolvedDevice=\(device)")
            } else {
                XPCBridgeAdapter.shared.setWiiControllerType(0)
            }
            // Set up rcheevos achievement detection. The runtime lives in the
            // XPC service; we just feed triggers in and listen for events.
            if !cachedAchievements.isEmpty {
                let triggers = cachedAchievements.map { achievement in
                    RcheevosAchievementTrigger(
                        id: UInt32(achievement.id),
                        title: achievement.title,
                        trigger: achievement.trigger ?? "",
                        isUnlocked: achievement.isUnlocked
                    )
                }
                XPCBridgeAdapter.shared.loadRcheevosAchievements(triggers, richPresenceScript: self.rcheevosRichPresenceScript)
                LoggerService.info(category: "Runner", "rcheevos loaded \(cachedAchievements.count) triggers for systemID=\(systemID ?? "default")")
            }

            XPCBridgeAdapter.shared.launch(
                dylibPath: dylibPath,
                romPath: romPath,
                coreID: coreID,
                systemID: systemID,
                romFilename: rom.filenameWithoutExtension,
                shaderDir: shaderDir,
            videoCallback: { [weak self] data, width, height, pitch, format in
                self?.updateFrame(data: data, width: width, height: height, pitch: pitch, format: format)
                self?.rcheevosLock.lock()
                let needsReset = self?._needsRcheevosReset ?? false
                if needsReset { self?._needsRcheevosReset = false }
                self?.rcheevosLock.unlock()
                if needsReset { XPCBridgeAdapter.shared.resetRcheevosTriggers() }
                },
                wiiControllerType: wiiDeviceForLaunch,
                onFailure: { [weak self] message in
                    Task { @MainActor in
                        LoggerService.error(category: "Runner", "Core launch failed: \(message)")
                        self?.lastError = .launchFailed(reason: message)
                        self?.isRunning = false
                    }
                }
            )
        }

        // Subscribe to rcheevos events from the XPC service for unlock handling.
        XPCBridgeAdapter.shared.onRcheevosAchievementTriggered = { achievementId in
            XPCBridgeAdapter.shared.deactivateRcheevosAchievement(id: achievementId)
            Task { @MainActor in
                let hardcore = AppSettings.getBool("hardcore_mode_enabled", defaultValue: false)
                await RetroAchievementsService.shared.unlockAchievement(id: achievementId, hardcore: hardcore)
            }
        }
    XPCBridgeAdapter.shared.onRcheevosRichPresence = { message in
        Task { @MainActor in
            guard let game = RetroAchievementsService.shared.currentGame else { return }
            let pingGameID = game.parentGameID ?? game.id
            await RetroAchievementsService.shared.updateRichPresence(gameID: pingGameID, message: message)
        }
    }

    // Notify RA server that a session has started
    if let game = RetroAchievementsService.shared.currentGame {
        let sessionGameID = game.parentGameID ?? game.id
        Task { @MainActor in
            await RetroAchievementsService.shared.startSession(gameID: sessionGameID)
        }
    }
    }

    // MARK: - Pause State
    @MainActor @Published var isPaused: Bool = false
    
    @MainActor
    func stop() {
        LoggerService.info(category: "Runner", "Stopping emulation thread")
        isRunning = false

        saveSRAMIfAvailable()

        timeMachineBuffer.clear()
        XPCBridgeAdapter.shared.setRewindEnabled(false, captureInterval: 3)
        XPCBridgeAdapter.shared.setStateCaptureCallback(nil)

        XPCBridgeAdapter.shared.deactivateRcheevos()
        XPCBridgeAdapter.shared.onRcheevosAchievementTriggered = nil
        XPCBridgeAdapter.shared.onRcheevosAchievementProgress = nil
        XPCBridgeAdapter.shared.onRcheevosChallengeStarted = nil
        XPCBridgeAdapter.shared.onRcheevosChallengeCancelled = nil
        XPCBridgeAdapter.shared.onRcheevosRichPresence = nil

        XPCBridgeAdapter.shared.stop()
        XPCBridgeAdapter.shared.waitForCompletion()

        hookedController?.extendedGamepad?.valueChangedHandler = nil
        hookedController = nil
        for (_, controller) in hookedControllers {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        hookedControllers.removeAll()
        textureCache = nil
        rfTextureCache = nil
        rfDecoder.reset()
        undoBuffer = nil
        SDLInputManager.shared.unregisterRunner()
    }

// MARK: - SRAM Save/Load

    private func loadSRAMOnGameLoad(romPath: String) {
        let romURL = URL(fileURLWithPath: romPath)
        let saveDir = XPCBridgeAdapter.shared.saveDirectoryPath()
        let baseName = romURL.deletingPathExtension().lastPathComponent

        let extensions = ["srm", "sav", "save"]
        for ext in extensions {
            let sramURL = URL(fileURLWithPath: saveDir).appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: sramURL.path) {
                do {
                    let sramData = try Data(contentsOf: sramURL)
                    if XPCBridgeAdapter.shared.loadSaveRAMData(sramData) {
                        LoggerService.info(category: "Runner", "Loaded SRAM (\(sramData.count) bytes) from: \(sramURL.path)")
                    }
                } catch {
                    LoggerService.error(category: "Runner", "Failed to load SRAM: \(error.localizedDescription)")
                }
                return
            }
        }

        #if LOG_DEBUG
        LoggerService.debug(category: "Runner", "No SRAM file found for: \(baseName)")
        #endif
    }

    @MainActor
    private func sramFilePath(for rom: ROM) -> URL {
        let saveDir = URL(fileURLWithPath: XPCBridgeAdapter.shared.saveDirectoryPath())
        let baseName = rom.path.deletingPathExtension().lastPathComponent
        return saveDir.appendingPathComponent("\(baseName).srm")
    }

    @MainActor
    private func saveSRAMIfAvailable() {
        guard let gameRom = rom else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Runner", "No ROM loaded, skipping SRAM save")
            #endif
            return
        }

        guard let sramData = XPCBridgeAdapter.shared.getSaveRAMData(), !sramData.isEmpty else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Runner", "No SAVE_RAM to save for \(gameRom.displayName)")
            #endif
            return
        }

        let sramPath = sramFilePath(for: gameRom)
        let saveDir = sramPath.deletingLastPathComponent()
        LoggerService.info(category: "Runner", "SRAM save directory: \(saveDir.path)")

        do {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

            try sramData.write(to: sramPath)
            LoggerService.info(category: "Runner", "Saved SRAM (\(sramData.count) bytes) to: \(sramPath.path)")
        } catch {
            LoggerService.error(category: "Runner", "Failed to save SRAM: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadSRAMIfAvailable(for rom: ROM) {
        let sramPath = sramFilePath(for: rom)

        guard FileManager.default.fileExists(atPath: sramPath.path) else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Runner", "No SRAM file found at: \(sramPath.path)")
            #endif
            return
        }

        do {
            let sramData = try Data(contentsOf: sramPath)
            guard XPCBridgeAdapter.shared.loadSaveRAMData(sramData) else {
                LoggerService.error(category: "Runner", "Failed to load SRAM into core")
                return
            }
            LoggerService.info(category: "Runner", "Loaded SRAM (\(sramData.count) bytes) from: \(sramPath.path)")
        } catch {
            LoggerService.error(category: "Runner", "Failed to load SRAM: \(error.localizedDescription)")
        }
    }
    
    // Toggle pause state
    @MainActor
    func togglePause() {
        isPaused.toggle()
        XPCBridgeAdapter.shared.setPaused(isPaused)
        osdMessage = isPaused ? LocalizationManager.shared.localized("osd.paused") : LocalizationManager.shared.localized("osd.resumed")
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self.osdMessage = nil }
        }
    }
    
    @MainActor
    func reloadGame() {
        isPaused = false
        XPCBridgeAdapter.shared.setPaused(false)
        XPCBridgeAdapter.shared.resetGame()
        rcheevosLock.lock()
        _needsRcheevosReset = true
        rcheevosLock.unlock()
        onGameReset?()
    }

    @MainActor
    private func slotLabel(_ slot: Int) -> String {
        slot == -1
            ? LocalizationManager.shared.localized("osd.auto")
            : LocalizationManager.shared.localized("osd.slot", "\(slot)")
    }

    // MARK: - Time Machine & Speed Control

    @MainActor @Published var speedMultiplier: Float = 1.0
    @MainActor @Published var isRewinding: Bool = false

    /// Live playhead frame index while in Time Machine scrub mode. The
    /// timeline overlay reads this; left/right arrows on the keyboard or
    /// the in-game left/right bindings move it.
    @MainActor @Published var timeMachineScrubFrameIndex: UInt64 = 0

    // Mirror of `isRewinding` for the GCController valueChangedHandler, which
    // fires on a non-MainActor queue. The main-actor `@Published` is poorly
    // suited for cross-thread reads; this `nonisolated(unsafe)` Bool is set
    // in lockstep with `isRewinding` on the main actor and read atomically
    // from the gamepad thread. This matches how `ShaderParameterStore` and
    // MAME lookup tables expose data to non-MainActor code.
    nonisolated(unsafe) var isRewindingStorage: Bool = false

    // Settings availability helpers. Read at action time so mid-game
    // settings changes take effect for the next key/gamepad press.
    @MainActor
    static func timeMachineMasterEnabled() -> Bool {
        AppSettings.getBool("timeMachine_enabled", defaultValue: true)
    }
    @MainActor
    static func rewindFeatureEnabled() -> Bool {
        timeMachineMasterEnabled() && AppSettings.getBool("timeMachine_rewindEnabled", defaultValue: true)
    }
    @MainActor
    static func fastForwardFeatureEnabled() -> Bool {
        timeMachineMasterEnabled() && AppSettings.getBool("timeMachine_fastForwardEnabled", defaultValue: true)
    }
    @MainActor
    static func slowMotionFeatureEnabled() -> Bool {
        timeMachineMasterEnabled() && AppSettings.getBool("timeMachine_slowMotionEnabled", defaultValue: true)
    }

    /// Blink an OSD hint then clear it after a short delay.
    @MainActor
    private func showDisabledOSD(_ message: String) {
        osdMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { if self.osdMessage == message { self.osdMessage = nil } }
        }
    }

    @MainActor
    private func applyState(_ data: Data, resumeAfter: Bool) -> Bool {
        let success = XPCBridgeAdapter.shared.unserializeState(data)
        if success {
            XPCBridgeAdapter.shared.flushAudio()
            // Run one retro_run so the restored state actually renders to
            // the framebuffer. Otherwise the user steps the scrubber and sees
            // nothing visibly change until emulation resumes.
            XPCBridgeAdapter.shared.runSingleFrame()
            rcheevosLock.lock()
            _needsRcheevosReset = true
            rcheevosLock.unlock()
            XPCBridgeAdapter.shared.setPaused(!resumeAfter)
            speedMultiplier = 1.0
            XPCBridgeAdapter.shared.setSpeedMultiplier(1.0)
        }
        return success
    }

    /// Enter (or exit) Time Machine scrub mode. While active, emulation is
    /// paused and left/right inputs step the playhead across saved snapshots.
    /// Pressing the rewind key again resumes emulation from the current
    /// playhead position.
    @MainActor
    func toggleTimeMachineMode() {
        guard Self.rewindFeatureEnabled() else {
            showDisabledOSD(LocalizationManager.shared.localized("settings.timeMachine.rewindDisabledHint"))
            return
        }
        if isRewinding {
            exitTimeMachineMode()
        } else {
            enterTimeMachineMode()
        }
    }

    @MainActor
    private func enterTimeMachineMode() {
        guard let newest = timeMachineBuffer.newestFrameIndex,
              timeMachineBuffer.entryCount > 1 else {
            osdMessage = LocalizationManager.shared.localized("osd.noRewindData")
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
            return
        }
        isRewinding = true
        isRewindingStorage = true
        speedMultiplier = 1.0
        XPCBridgeAdapter.shared.setSpeedMultiplier(1.0)
        XPCBridgeAdapter.shared.setPaused(true)
        timeMachineScrubFrameIndex = newest
        osdMessage = LocalizationManager.shared.localized("osd.rewind")
        LoggerService.info(category: "TimeMachine", "Entered scrub mode at frame \(newest)")
    }

    @MainActor
    func exitTimeMachineMode() {
        guard isRewinding else { return }
        let exitScrubFrame = timeMachineScrubFrameIndex
        let preTruncateOldest = timeMachineBuffer.oldestFrameIndex ?? 0
        let preTruncateNewest = timeMachineBuffer.newestFrameIndex ?? 0
        let preTruncateCount = timeMachineBuffer.entryCount
        isRewinding = false
        isRewindingStorage = false
        speedMultiplier = 1.0
        XPCBridgeAdapter.shared.setSpeedMultiplier(1.0)
        // Drop entries past the playhead so the timeline's total duration
        // reflects only the remaining history after rewinding. Without this
        // the overlay keeps reporting the pre-rewind total (e.g., 20s even
        // though we scrubbed back to 10s and resumed from there).
        timeMachineBuffer.truncate(after: exitScrubFrame)
        // Reset the engine's internal capture-indexing clock so the next
        // captures are indexed at exitScrubFrame+1, +2, … instead of the
        // pre-rewind frame number. This also lowers the XPC poller's
        // watermark (see XPCBridgeAdapter.setFrameCount) so post-rewind
        // captures aren't rejected as stale.
        //
        // Sent BEFORE setPaused(false): both go FIFO over the same
        // NSXPCConnection, so the engine clock is guaranteed to be rolled
        // back before the run loop wakes and bumps _frameCount++. Reversing
        // the order would let a few frames run at the stale (high) frame
        // number before the rewind arrived, leaking out-of-range captures
        // into the queue that drainCapturedState would then reject.
        XPCBridgeAdapter.shared.setFrameCount(exitScrubFrame)
        XPCBridgeAdapter.shared.setPaused(false)
        let postTruncateOldest = timeMachineBuffer.oldestFrameIndex ?? 0
        let postTruncateNewest = timeMachineBuffer.newestFrameIndex ?? 0
        let postTruncateCount = timeMachineBuffer.entryCount
        osdMessage = nil
        LoggerService.info(category: "TimeMachine", "Exited scrub mode — scrubFrame=\(exitScrubFrame) preTruncate [oldest=\(preTruncateOldest) newest=\(preTruncateNewest) count=\(preTruncateCount)] postTruncate [oldest=\(postTruncateOldest) newest=\(postTruncateNewest) count=\(postTruncateCount)]")
    }

    /// Step the playhead one snapshot toward the past (direction < 0) or
    /// toward the present (direction > 0). Used by keyboard arrows, the
    /// user's in-game left/right bindings, and the gamepad dpad while in
    /// Time Machine scrub mode.
    @MainActor
    func stepTimeMachine(direction: Int) {
        guard isRewinding else { return }
        let scrub = timeMachineScrubFrameIndex
        let target: UInt64
        if direction < 0 {
            // Find a snapshot *strictly* before the playhead. nearestEntry
            // (before:) returns entries with frameIndex <= arg, so when the
            // playhead sits on an existing snapshot the query would match that
            // same entry — producing frameIndex == scrub and "no step". Step
            // back to the entry before scrub by querying scrub-1 in that case.
            guard scrub > 0 else { return }
            let nearest = timeMachineBuffer.nearestEntry(before: scrub)
            guard let nearest else {
                #if LOG_DEBUG
                LoggerService.debug(category: "TimeMachine", "step back: no snapshots (scrub=\(scrub))")
                #endif
                return
            }
            if nearest.frameIndex < scrub {
                target = nearest.frameIndex
            } else {
                // nearest.frameIndex == scrub → query one frame earlier.
                guard let prev = timeMachineBuffer.nearestEntry(before: scrub - 1) else {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "TimeMachine", "step back: no earlier snapshot (scrub=\(scrub))")
                    #endif
                    return
                }
                target = prev.frameIndex
            }
        } else if direction > 0 {
            // Find a snapshot *strictly* after the playhead. nearestEntry
            // (after:) returns entries with frameIndex >= arg.
            guard let nearest = timeMachineBuffer.nearestEntry(after: scrub) else {
                #if LOG_DEBUG
                LoggerService.debug(category: "TimeMachine", "step forward: no snapshots (scrub=\(scrub))")
                #endif
                return
            }
            if nearest.frameIndex > scrub {
                target = nearest.frameIndex
            } else {
                // nearest.frameIndex == scrub → query scrub+1.
                guard let next = timeMachineBuffer.nearestEntry(after: scrub + 1) else {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "TimeMachine", "step forward: no later snapshot (scrub=\(scrub))")
                    #endif
                    return
                }
                target = next.frameIndex
            }
        } else {
            return
        }
        guard let entry = timeMachineBuffer.entry(at: target) else {
            LoggerService.warning(category: "TimeMachine", "stepTimeMachine: target \(target) has no entry")
            return
        }
        let success = applyState(entry.data, resumeAfter: false)
        if success {
            timeMachineScrubFrameIndex = target
        } else {
            LoggerService.warning(category: "TimeMachine", "step direction \(direction) failed at frame \(target)")
        }
    }

    @MainActor
    func toggleFastForward() {
        guard Self.fastForwardFeatureEnabled() else {
            showDisabledOSD(LocalizationManager.shared.localized("settings.timeMachine.fastForwardDisabledHint"))
            return
        }
        if isRewinding { exitTimeMachineMode(); return }
        let speeds: [Float] = [2.0, 4.0, 8.0]
        let idx = speeds.firstIndex { $0 == speedMultiplier } ?? -1
        let next = (idx + 1) % (speeds.count + 1)
        speedMultiplier = next < speeds.count ? speeds[next] : 1.0
        let label = speedMultiplier > 1.0 ? "\(Int(speedMultiplier))x" : "Normal Speed"
        osdMessage = label
        LoggerService.info(category: "TimeMachine", "toggleFastForward → \(speedMultiplier)")
        XPCBridgeAdapter.shared.setSpeedMultiplier(speedMultiplier)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { if self.speedMultiplier == 1.0 { self.osdMessage = nil } }
        }
    }

    @MainActor
    func toggleSlowMotion() {
        guard Self.slowMotionFeatureEnabled() else {
            showDisabledOSD(LocalizationManager.shared.localized("settings.timeMachine.slowMotionDisabledHint"))
            return
        }
        if isRewinding { exitTimeMachineMode(); return }
        let speeds: [Float] = [0.5, 0.25]
        let idx = speeds.firstIndex { $0 == speedMultiplier } ?? -1
        let next = (idx + 1) % (speeds.count + 1)
        speedMultiplier = next < speeds.count ? speeds[next] : 1.0
        let label = speedMultiplier < 1.0 ? "\(Int(1.0 / speedMultiplier))x Slow" : "Normal Speed"
        osdMessage = label
        LoggerService.info(category: "TimeMachine", "toggleSlowMotion → \(speedMultiplier)")
        XPCBridgeAdapter.shared.setSpeedMultiplier(speedMultiplier)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { if self.speedMultiplier == 1.0 { self.osdMessage = nil } }
        }
    }

    /// Seek to a specific frame (used by the slider in GameTimeBarOverlay).
    /// Returns emulation to 1x and does NOT leave scrub mode.
    @MainActor
    func rewindToFrame(_ frameIndex: UInt64) -> Bool {
        guard Self.rewindFeatureEnabled() else { return false }
        guard let entry = timeMachineBuffer.entry(at: frameIndex) ?? timeMachineBuffer.nearestEntry(before: frameIndex) else {
            return false
        }
        let success = XPCBridgeAdapter.shared.unserializeState(entry.data)
        if success {
            XPCBridgeAdapter.shared.flushAudio()
            // Render the unserialized state to the framebuffer so the user
            // sees the snapshot at the seeked position instead of the last
            // emulated frame.
            XPCBridgeAdapter.shared.runSingleFrame()
            rcheevosLock.lock()
            _needsRcheevosReset = true
            rcheevosLock.unlock()
            speedMultiplier = 1.0
            XPCBridgeAdapter.shared.setSpeedMultiplier(1.0)
            if isRewinding {
                timeMachineScrubFrameIndex = entry.frameIndex
                // Stay paused while scrubbing.
                XPCBridgeAdapter.shared.setPaused(true)
            } else {
                XPCBridgeAdapter.shared.setPaused(false)
            }
        }
        return success
    }

    // Legacy single-shot toggle (settings/HUD). Now equivalent to a one-shot
    // jump back without entering scrub mode.
    @MainActor
    func toggleRewind() {
        guard Self.rewindFeatureEnabled() else {
            showDisabledOSD(LocalizationManager.shared.localized("settings.timeMachine.rewindDisabledHint"))
            return
        }
        if isRewinding { exitTimeMachineMode(); return }
        speedMultiplier = 1.0
        XPCBridgeAdapter.shared.setSpeedMultiplier(1.0)
        guard let newest = timeMachineBuffer.newestFrameIndex,
              let nearest = timeMachineBuffer.nearestEntry(before: newest - 1),
              nearest.frameIndex < newest else {
            osdMessage = LocalizationManager.shared.localized("osd.noRewindData")
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
            return
        }
        let success = applyState(nearest.data, resumeAfter: true)
        if success {
            osdMessage = LocalizationManager.shared.localized("osd.rewound")
        } else {
            osdMessage = LocalizationManager.shared.localized("osd.rewindFailed")
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self.osdMessage = nil }
        }
    }

    // MARK: - Slot-based Save State
    
    // Compression preference
    var compressSaveStates: Bool {
        AppSettings.getBool("saveState_compress", defaultValue: false)
    }
    
    private var progressiveSlotCount: Int {
        max(1, min(5, AppSettings.getInt("progressiveSaves_slotCount", defaultValue: 3)))
    }

    private func resolveSaveURL(slot: Int, gameName: String, systemID: String) -> (URL, Int?) {
        let slotCount = progressiveSlotCount
        let version = saveManager.rotateProgressiveVersions(gameName: gameName, systemID: systemID, slot: slot, slotCount: slotCount)
        return (saveManager.progressiveStatePath(gameName: gameName, systemID: systemID, slot: slot, version: version), version)
    }

    // Save the current emulator state to the specified slot
    @MainActor
    func saveState(slot: Int, progressiveVersion: Int? = nil) -> Bool {
        guard supportsSaveStates else {
            let error = GameError.saveStateError(reason: "Core doesn't support save states")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        guard let stateData = XPCBridgeAdapter.shared.serializeState() else {
            let error = GameError.saveStateError(reason: "Serialization failed")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        guard let gameRom = rom else {
            let error = GameError.saveStateError(reason: "No game loaded")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        let systemID = gameRom.systemID ?? "default"
        let gameKey = "\(gameRom.displayName)__\(gameRom.id.uuidString.prefix(8))"
        let (stateURL, version) = resolveSaveURL(slot: slot, gameName: gameKey, systemID: systemID)
        let actualVersion = progressiveVersion ?? version
        
        do {
            // Apply compression if enabled
            let finalData: Data
            if compressSaveStates, let compressed = SaveStateManager.compressStateData(stateData) {
                finalData = compressed
                let ratio = Double(finalData.count) / Double(stateData.count) * 100
                #if LOG_DEBUG
                LoggerService.debug(category: "SaveState", "Compressed: \(Int64(stateData.count).formattedByteSize) -> \(Int64(finalData.count).formattedByteSize) (\(Int(ratio))%)")
                #endif
            } else {
                finalData = stateData
            }
            
            try finalData.write(to: stateURL, options: [.atomic])
            
            // Capture and save thumbnail if we have a current frame
            if let frameTex = currentFrameTexture {
                #if LOG_DEBUG
                LoggerService.debug(category: "SaveState", "Capturing thumbnail for slot \(slot)")
                #endif
                #if LOG_DEBUG
                LoggerService.debug(category: "SaveState", "Texture format: \(frameTex.pixelFormat.rawValue), size: \(frameTex.width)x\(frameTex.height)")
                #endif
                let nsImage = NSImageFromMTLTexture(frameTex)
                if let nsImage = nsImage {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "SaveState", "Captured thumbnail: \(nsImage.size.width)x\(nsImage.size.height)")
                    #endif
                    if let v = actualVersion {
                        saveManager.saveThumbnail(nsImage, gameName: gameKey, systemID: systemID, slot: slot)
                        // Also save thumbnail for progressive version
                        saveManager.saveProgressiveThumbnail(image: nsImage, gameName: gameKey, systemID: systemID, slot: slot, version: v)
                    } else {
                        saveManager.saveThumbnail(nsImage, gameName: gameKey, systemID: systemID, slot: slot)
                    }
                } else {
                    LoggerService.error(category: "SaveState", "ERROR: NSImageFromMTLTexture returned nil")
                }
            } else {
                #if LOG_DEBUG
                LoggerService.debug(category: "SaveState", "WARNING: currentFrameTexture is nil, cannot capture thumbnail")
                #endif
            }
            
            if !AppSettings.getBool("hasCelebratedFirstSave", defaultValue: false) {
                AppSettings.setBool("hasCelebratedFirstSave", value: true)
                osdMessage = LocalizationManager.shared.localized("osd.firstSaveTitle")
                CelebrationManager.shared.celebrate(
                    icon: "party.popper.fill",
                    title: LocalizationManager.shared.localized("celebration.firstSaveTitle"),
                    subtitle: LocalizationManager.shared.localized("celebration.firstSaveSubtitle"),
                    style: .grand
                )
            } else if let v = actualVersion {
                osdMessage = LocalizationManager.shared.localized("osd.savedVersion", slotLabel(slot), v)
            } else {
                osdMessage = LocalizationManager.shared.localized(slot == -1 ? "osd.savedAuto" : "osd.savedSlot", slotLabel(slot))
            }
            
            onSaveStateSaved?(slot)
            AppHaptics.success()
            
            // Clear OSD after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
            
            return true
        } catch {
            let err = GameError.saveStateError(reason: error.localizedDescription)
            osdMessage = err.localizedDescription
            self.lastError = err
            return false
        }
    }
    
    // Load an emulator state from a specific URL
    @MainActor
    func loadState(from url: URL) -> Bool {
        guard supportsSaveStates else {
            let error = GameError.loadStateError(reason: "Core doesn't support save states")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }

        undoBuffer = XPCBridgeAdapter.shared.serializeState()

        // A state file on an iCloud-synced directory can be a dataless
        // placeholder that reads as empty; pull it down before loading.
        ICloudMaterializer.ensureMaterialized(at: url)

        guard let fileData = try? Data(contentsOf: url) else {
            let error = GameError.loadStateError(reason: "State file not found")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }

        var actualData: Data
        if let decompressed = SaveStateManager.decompressStateData(fileData) {
            actualData = decompressed
        } else {
            let error = GameError.loadStateError(reason: "State incompatible or corrupted")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }

        let success = XPCBridgeAdapter.shared.unserializeState(actualData)
        if success {
            osdMessage = LocalizationManager.shared.localized("osd.loadedSaveState")
            AppHaptics.success()
            rcheevosLock.lock()
            _needsRcheevosReset = true
            rcheevosLock.unlock()

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
        } else {
            let error = GameError.loadStateError(reason: "State incompatible or corrupted")
            osdMessage = error.localizedDescription
            self.lastError = error
        }

        return success
    }

    // Load an emulator state from the specified slot
    @MainActor
    func loadState(slot: Int) -> Bool {
        guard supportsSaveStates else {
            let error = GameError.loadStateError(reason: "Core doesn't support save states")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        guard let gameRom = rom else {
            let error = GameError.loadStateError(reason: "No game loaded")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        let systemID = gameRom.systemID ?? "default"
        let gameKey = "\(gameRom.displayName)__\(gameRom.id.uuidString.prefix(8))"
        let stateURL: URL

        let versions = saveManager.progressiveSlotVersions(gameName: gameKey, systemID: systemID, slot: slot)
        if !versions.isEmpty {
            var newestVersion = versions[0]
            var newestDate: Date? = nil
            for v in versions {
                let info = saveManager.progressiveSlotInfo(gameName: gameKey, systemID: systemID, slot: slot, version: v)
                if info.exists {
                    if let date = info.modificationDate, date > (newestDate ?? .distantPast) {
                        newestDate = date
                        newestVersion = v
                    }
                }
            }
            stateURL = saveManager.progressiveStatePath(gameName: gameKey, systemID: systemID, slot: slot, version: newestVersion)
        } else {
            stateURL = saveManager.statePath(gameName: gameKey, systemID: systemID, slot: slot)
        }
        
        // Save current state as undo buffer before loading
        undoBuffer = XPCBridgeAdapter.shared.serializeState()
        
        guard let fileData = try? Data(contentsOf: stateURL) else {
            let error = GameError.loadStateError(reason: "State file not found")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        // Decompress if needed (handles both compressed and raw data)
        let actualData: Data
        if let decompressed = SaveStateManager.decompressStateData(fileData) {
            actualData = decompressed
        } else {
            let error = GameError.loadStateError(reason: "State incompatible or corrupted")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        let success = XPCBridgeAdapter.shared.unserializeState(actualData)
        if success {
                osdMessage = LocalizationManager.shared.localized("osd.loadedSaveState")
            rcheevosLock.lock()
            _needsRcheevosReset = true
            rcheevosLock.unlock()
            onSaveStateLoaded?(slot)
            
            // Clear OSD after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
        } else {
            let error = GameError.loadStateError(reason: "State incompatible or corrupted")
            osdMessage = error.localizedDescription
            self.lastError = error
        }
        
        return success
    }
    
    // Undo the last load operation (restore from undo buffer)
    @MainActor
    func undoLoadState() -> Bool {
        guard let undoData = undoBuffer else {
            osdMessage = LocalizationManager.shared.localized("osd.nothingToUndo")
            return false
        }
        
        // Decompress undo buffer if needed
        let actualData: Data
        if let decompressed = SaveStateManager.decompressStateData(undoData) {
            actualData = decompressed
        } else {
            osdMessage = LocalizationManager.shared.localized("osd.undoFailed")
            return false
        }
        
        let success = XPCBridgeAdapter.shared.unserializeState(actualData)
        if success {
            undoBuffer = nil
            osdMessage = LocalizationManager.shared.localized("osd.undoSuccess")
            
            // Clear OSD after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
        } else {
            osdMessage = LocalizationManager.shared.localized("osd.undoFailed")
        }
        
        return success
    }
    
    // Cycle to the next save slot (0-9)
    @MainActor
    func nextSlot() {
        if currentSlot >= 9 {
            currentSlot = 0
        } else {
            currentSlot += 1
        }
        osdMessage = LocalizationManager.shared.localized("osd.currentSlot", slotLabel(currentSlot))
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run { self.osdMessage = nil }
        }
    }
    
    // Cycle to the previous save slot (0-9)
    @MainActor
    func previousSlot() {
        if currentSlot <= 0 {
            currentSlot = 9
        } else {
            currentSlot -= 1
        }
        osdMessage = LocalizationManager.shared.localized("osd.currentSlot", slotLabel(currentSlot))
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run { self.osdMessage = nil }
        }
    }
    
    // Legacy method for backward compat—calls current slot
    func saveState() {
        Task { @MainActor in
            _ = saveState(slot: currentSlot)
        }
    }

weak var metalCoordinator: MetalCoordinator?

    func setMetalCoordinator(_ coord: MetalCoordinator) {
        metalCoordinator = coord
    }

    @MainActor
    func performScreenshot() {
        let romName = rom?.filenameWithoutExtension ?? "screenshot"
        let sysID = rom?.systemID ?? systemID
        let includeNative = AppSettings.getBool("screenshot_include_native", defaultValue: false)

        let displayURL = ScreenshotService.url(for: romName, systemID: sysID, suffix: nil)
        let nativeURL: URL? = includeNative ? ScreenshotService.url(for: romName, systemID: sysID, suffix: "_native") : nil

        // Haptic feedback
        let haptic = NSHapticFeedbackManager.defaultPerformer
        haptic.perform(.generic, performanceTime: .default)

        if let coord = metalCoordinator {
            coord.requestScreenshotCapture(displayURL: displayURL, nativeURL: nativeURL) { urls in
                guard !urls.isEmpty else { return }
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .screenshotTaken,
                        object: nil,
                        userInfo: [
                            "url": urls[0],
                            "nativeURL": urls.count > 1 ? urls[1] : URL?.none as Any,
                        ]
                    )
                }
            }
        } else {
            guard let frame = currentFrameTexture else {
                LoggerService.warning(category: "Screenshot", "No frame available to capture")
                return
            }
            if includeNative {
                _ = ScreenshotService.capture(from: frame, romName: romName, systemID: sysID, suffix: "_native")
            }
            if let result = ScreenshotService.capture(from: frame, romName: romName, systemID: sysID, suffix: nil) {
                NotificationCenter.default.post(
                    name: .screenshotTaken,
                    object: nil,
                    userInfo: ["url": result.url]
                )
            }
        }
    }

    // MARK: - Share Button Handling

    /// Cap streaming/recording output so VideoToolbox can encode in real time.
    /// Returns the input unchanged when already within bounds; otherwise rescales
    /// preserving aspect ratio to fit within (maxW, maxH). Raw core feeds (NES/SNES
    /// etc. at 256×224) are passed through untouched — only drawable-sized caps trigger.
    @MainActor public var captureSize: CGSize {
        if StreamRecordingService.shared.recordWithShaders, let view = metalView {
            // Match the recorder's drawing: the recorder crops the centered
            // game sub-rect out of the baked-in-shader drawable (see
            // MetalCoordinator.computeCenteredGameSubRect) so the encoded
            // frame has no black pillarbox/letterbox bars. Use the same
            // sub-rect dimensions here so AVAssetWriter / RollingVideoBuffer
            // chunk sizes match what the recorder actually emits.
            //
            // No artificial resolution clamp: the pool-allocated pixel buffer
            // and the renderer's `cropRect` must agree on dimensions, and
            // modern Apple Silicon records 4K H.264/HEVC in real time via
            // VideoToolbox without affecting the Metal render pipeline.
            if let frameTex = currentFrameTexture, frameTex.width > 0, frameTex.height > 0 {
                // MTKView.drawableSize is in pixels; build a scratch
                // descriptor-less lookup by computing the sub-rect via the
                // shared helper, which only needs the texture dims.
                let drawableTex = view.currentDrawable?.texture
                if let dt = drawableTex {
                    let region = MetalCoordinator.computeCenteredGameSubRect(
                        drawable: dt,
                        frameTex: frameTex,
                        isRotated: currentFrameRotation == 1 || currentFrameRotation == 3,
                        coreAspect: Double(XPCBridgeAdapter.shared.aspectRatio()),
                        systemID: systemID
                    )
                    return CGSize(width: max(1, CGFloat(region.size.width)),
                                  height: max(1, CGFloat(region.size.height)))
                }
            }
            let ds = view.drawableSize
            return CGSize(width: max(1, ds.width), height: max(1, ds.height))
        }
        // Raw core frame without shader processing — emit at the native
        // pixel grid (no DAR letterbox/anamorphic-stretch padding). Players
        // play the file at native pixel ratio; users wanting pixel-perfect
        // aspect display should keep `recordWithShaders` (the default),
        // which renders the shader-applied drawable through a centered
        // crop. (Previous behavior CPU-resized via vImage to DAR-pad the
        // raw frame; removed for performance — see MetalCoordinator's
        // recording pipeline rewrite.)
        if let tex = currentFrameTexture, tex.width > 0, tex.height > 0 {
            return CGSize(width: CGFloat(tex.width), height: CGFloat(tex.height))
        }
        return CGSize(width: 640, height: 480)
    }

    @MainActor
    func handleSharePress(isLongPress: Bool) {
        LoggerService.info(category: "Runner", "handleSharePress isLongPress=\(isLongPress)")
        let config = ShareButtonConfig.load()
        let behavior = isLongPress ? config.longPress : config.singlePress
        LoggerService.info(category: "Runner", "handleSharePress behavior=\(behavior) isEnabled=\(RollingVideoBufferService.shared.isEnabled)")

        switch behavior {
        case .none:
            break

        case .screenshot:
            performScreenshot()

        case .startVideoRecording:
            if StreamRecordingService.shared.isRecording {
                StreamRecordingService.shared.stop()
            } else {
                let size = captureSize
                let url = Self.recordingOutputURL(systemID: systemID, rom: rom)
                StreamRecordingService.shared.startRecording(outputURL: url, width: Int(size.width), height: Int(size.height))
            }

        case .streamTwitch:
            if StreamRecordingService.shared.isRecording {
                StreamRecordingService.shared.stop()
            } else {
                StreamRecordingService.shared.startStreaming(mode: .twitch)
            }

        case .streamYoutube:
            if StreamRecordingService.shared.isRecording {
                StreamRecordingService.shared.stop()
            } else {
                StreamRecordingService.shared.startStreaming(mode: .youtube)
            }

        case .streamCustom:
            if StreamRecordingService.shared.isRecording {
                StreamRecordingService.shared.stop()
            } else {
                StreamRecordingService.shared.startStreaming(mode: .custom)
            }

        case .saveLastXSeconds:
            guard RollingVideoBufferService.shared.isEnabled else {
                osdMessage = LocalizationManager.shared.localized("settings.media.rolling.disabledHint")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.osdMessage = nil
                }
                return
            }
            osdMessage = LocalizationManager.shared.localized("osd.savingClip")
            RollingVideoBufferService.shared.saveBufferToFile { [weak self] url in
                if let url = url {
                        self?.osdMessage = LocalizationManager.shared.localized("osd.clipSaved")
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self?.osdMessage = nil
                    }
                    NotificationCenter.default.post(
                        name: .clipSaved,
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
            }
        }
    }

    @MainActor static func recordingOutputURL(systemID: String, rom: ROM?) -> URL {
        let directory: URL
        if let saved = StreamRecordingService.localOutputPath, !saved.isEmpty {
            directory = URL(fileURLWithPath: saved)
        } else {
            directory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ??
                FileManager.default.temporaryDirectory
        }
        let gameName = sanitizeFilenameComponent(rom?.displayName ?? rom?.filenameWithoutExtension ?? "unknown")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let date = formatter.string(from: Date())
        let ext = StreamRecordingService.shared.customVideoCodec.isLossless ? "mov" : "mp4"
        let filename = "TruchiEmu_\(systemID)_\(gameName)_\(date).\(ext)"
        return directory.appendingPathComponent(filename)
    }

    private static func sanitizeFilenameComponent(_ str: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: ".-_"))
        return str.components(separatedBy: allowed.inverted).joined()
    }

    func setKeyState(retroID: Int, pressed: Bool) {
        MainActor.assumeIsolated {
            currentInputState[retroID] = pressed
        }
        XPCBridgeAdapter.shared.setKeyState(retroID: retroID, pressed: pressed)
    }

    func setKeyState(retroID: Int, player: Int, pressed: Bool) {
        if player == 0 {
            MainActor.assumeIsolated {
                currentInputState[retroID] = pressed
            }
        }
        XPCBridgeAdapter.shared.setKeyState(retroID: retroID, player: player, pressed: pressed)
    }

    private func pickBestROM(from files: [URL], systemID: String?) -> URL? {
        let knownExts: Set<String>
        if let sysID = systemID,
           let system = SystemDatabase.system(forID: sysID) {
            knownExts = Set(system.extensions.map { $0.lowercased() })
        } else {
            knownExts = []
        }

        if !knownExts.isEmpty {
            if let match = files.first(where: { knownExts.contains($0.pathExtension.lowercased()) }) {
                return match
            }
        }

        let preferredExts: Set<String> = ["nes", "smc", "sfc", "n64", "z64", "gba", "gbc", "gb", "gg", "sms", "md", "smd", "gen", "sfc", "fig", "pce", "ngp", "ws", "vb", "at7800", "a78", "lnx", "jag", "cue", "chd", "iso"]
        if let match = files.first(where: { preferredExts.contains($0.pathExtension.lowercased()) }) {
            return match
        }

        let skipExts: Set<String> = ["txt", "nfo", "readme", "xml", "cfg", "ini", "sav", "srm", "bsv", "json", "bps", "ips", "ups", "xdelta"]
        if let match = files.first(where: { !skipExts.contains($0.pathExtension.lowercased()) && $0.lastPathComponent != ".metadata.json" }) {
            return match
        }

        return files.first
    }

    func findCoreLib(coreID: String) -> String? {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!.appendingPathComponent("TruchiEmu/Cores/\(coreID)")
    guard let versionDirs = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter({ $0.hasDirectoryPath }),
          let latest = versionDirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else { return nil }
    let dylibName = "\(coreID).dylib"
    let path = latest.appendingPathComponent(dylibName).path
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }

    internal func updateFrame(data: UnsafeRawPointer?, width: Int, height: Int, pitch: Int, format: Int) {
        guard let data = data, width > 0, height > 0 else { return }
        
        textureLock.lock()
        defer { textureLock.unlock() }

        guard let device = self.device else { return }

        if !hasLoggedFrame {
            LoggerService.info(category: "Runner", "updateFrame: \(width)x\(height) pitch=\(pitch) format=\(format)")
        }

        let mtlFormat = mapPixelFormat(format)
        let declaredBPP = pixelBytesForFormat(mtlFormat)
        let declaredMinPitch = width * declaredBPP

        let actualBPP = pitch / max(1, width)
        let useBPP: Int
        let useFormat: MTLPixelFormat
        if pitch < declaredMinPitch && actualBPP > 0 {
            useBPP = actualBPP
            useFormat = useBPP >= 4 ? .bgra8Unorm : (useBPP == 2 ? .b5g6r5Unorm : .r8Unorm)
            LoggerService.info(category: "Runner", "FALLBACK: actualBPP=\(actualBPP) useFormat=\(useFormat.rawValue)")
        } else {
            useBPP = declaredBPP
            useFormat = mtlFormat
        }

        // "Digital -> RF -> decoder" path: feed the raw core frame through the
        // famidec RF decoder and display its decoded 640x480 output instead.
        if ShaderManager.shared.getCurrentFragmentFunctionName() == "fragmentRfDisplay" {
            processRfFrame(data: data, width: width, height: height, pitch: pitch,
                           bpp: useBPP, format: format)
            return
        }

        var tex: MTLTexture
        if let existing = textureCache,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == useFormat {
            tex = existing
            let expectedRowBytes = existing.width * pixelBytesForFormat(existing.pixelFormat)
            if pitch == expectedRowBytes {
                tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: data,
                            bytesPerRow: pitch)
            } else {
                var rowBuffer = [UInt8](repeating: 0, count: width * useBPP)
                for row in 0..<height {
                    let src = data.advanced(by: row * pitch)
                    let dst = rowBuffer.withUnsafeMutableBufferPointer { $0.baseAddress! }
                    dst.initialize(from: src.assumingMemoryBound(to: UInt8.self), count: width * useBPP)
                    tex.replace(region: MTLRegionMake2D(0, row, width, 1),
                                mipmapLevel: 0,
                                withBytes: rowBuffer,
                                bytesPerRow: width * useBPP)
                }
            }
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: useFormat,
                                                                 width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            guard let newTex = device.makeTexture(descriptor: desc) else { return }
            tex = newTex
            textureCache = tex

            let expectedRowBytes = width * pixelBytesForFormat(useFormat)
            if pitch == expectedRowBytes {
                tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: data,
                            bytesPerRow: pitch)
            } else {
                LoggerService.warning(category: "Runner", "First frame pitch=\(pitch) != expected=\(expectedRowBytes) useBPP=\(useBPP) useFormat=\(useFormat.rawValue), using copy path")
                var rowBuffer = [UInt8](repeating: 0, count: width * useBPP)
                for row in 0..<height {
                    let src = data.advanced(by: row * pitch)
                    let dst = rowBuffer.withUnsafeMutableBufferPointer { $0.baseAddress! }
                    dst.initialize(from: src.assumingMemoryBound(to: UInt8.self), count: width * useBPP)
                    tex.replace(region: MTLRegionMake2D(0, row, width, 1),
                                mipmapLevel: 0,
                                withBytes: rowBuffer,
                                bytesPerRow: width * useBPP)
                }
            }
        }

        #if DEBUG
        if systemID == "n64" {
            _ = data.bindMemory(to: UInt32.self, capacity: 1)
        }
        #endif

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrameTexture = tex
            self.metalView?.needsDisplay = true
            
            if !self.hasLoggedFrame {
                LoggerService.info(category: "Runner", "First frame received (\(width)x\(height))")
                self.hasLoggedFrame = true
                self.isReadyForDisplay = true
                // Read rotation from core on first frame
                let rotation = XPCBridgeAdapter.shared.currentRotation()
                if self.currentFrameRotation != Int(rotation) {
                    self.currentFrameRotation = Int(rotation)
                    LoggerService.info(category: "Runner", "Frame rotation: \(rotation) (\(rotation * 90) deg CW)")
                }
            }

            self.runnerFrameCount += 1
        }
    }

    // Runs the raw core frame through the famidec RF decoder and publishes the
    // decoded 640x480 texture as currentFrameTexture. Mirrors the bookkeeping
    // of updateFrame() so first-frame / rotation handling stays consistent.
    private func processRfFrame(data: UnsafeRawPointer, width: Int, height: Int,
                                pitch: Int, bpp: Int, format: Int) {
        let snap = ShaderManager.shared.getUniformSnapshot()
        let getF: (String, Float) -> Float = { snap[$0] ?? $1 }
        rfDecoder.setSignalStrength(getF("signalStrength", 1.0),
                                    snow: getF("snowAmount", 0.0),
                                    tuningHz: getF("tuningHz", 0.0),
                                    ghosting: getF("ghosting", 0.0),
                                    saturation: getF("saturation", 1.0),
                                    hueDeg: getF("hue", 0.0),
                                    colorMode: Int32(getF("colorMode", 1.0)),
                                    instability: getF("instability", 0.5))

        rfDecoder.processFrame(data, width: Int32(width), height: Int32(height),
                               pitch: Int32(pitch), bpp: Int32(bpp), format: Int32(format))

        guard let device = self.device,
              let decoded = rfDecoder.decodedRGBA() else { return }
        let dw = Int(rfDecoder.decodedWidth())
        let dh = Int(rfDecoder.decodedHeight())

        var tex = rfTextureCache
        if tex == nil || tex?.width != dw || tex?.height != dh {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                width: dw, height: dh, mipmapped: false)
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            guard let newTex = device.makeTexture(descriptor: desc) else { return }
            tex = newTex
            rfTextureCache = tex
        }
        tex?.replace(region: MTLRegionMake2D(0, 0, dw, dh),
                     mipmapLevel: 0,                      withBytes: UnsafeRawPointer(decoded),
                     bytesPerRow: dw * 4)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrameTexture = tex
            self.metalView?.needsDisplay = true

            if !self.hasLoggedFrame {
                LoggerService.info(category: "Runner", "RF decoder first frame (\(dw)x\(dh))")
                self.hasLoggedFrame = true
                self.isReadyForDisplay = true
            }
            self.runnerFrameCount += 1
        }
    }

    internal func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
        switch format {
        case 0: return .a1bgr5Unorm // 0RGB1555
        case 1: return .bgra8Unorm  // XRGB8888
        case 2: return .b5g6r5Unorm // RGB565
        default: return .bgra8Unorm
        }
    }

    private func pixelBytesForFormat(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .bgra8Unorm, .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm_srgb:
            return 4
        case .b5g6r5Unorm, .a1bgr5Unorm, .bgr5A1Unorm:
            return 2
        case .r8Unorm, .r8Unorm_srgb:
            return 1
        default:
            return 4
        }
    }

    func mapKey(_ keyCode: UInt16) -> (retroID: Int, player: Int)? {
        for (player, mapping) in cachedKeyboardMappings {
            for (button, code) in mapping.buttons where code == keyCode {
                let rid = Int(button.retroID(for: self.systemID, coreID: self.activeCoreID))
                guard rid >= 0 else { return nil }
                return (retroID: rid, player: player - 1)
            }
        }
        return nil
    }

    @MainActor
    open func setupGamepadInput() {
        let cs = ControllerService.shared

        LoggerService.info(category: "Runner", "setupGamepadInput: connectedControllers=\(cs.connectedControllers.map { $0.name })")

        // Cache gamepad hotkey bindings at launch (per-system resolved).
        // All caches fall back to the global binding when no per-system
        // override exists for that action.
        let hotkeys = HotkeyConfigManager.shared
        func cachedGC(_ action: HotkeyAction, systemID: String?) -> String? {
            let b = hotkeys.controllerBinding(for: action, systemID: systemID, source: .gameController)
            return b.isUnset ? nil : b.identifier
        }
        // sysID gets resolved later (line ~1794) from rom?.systemID ?? "default"; pass it
        // through here once, so the cache is built before gamepad input is wired.
        let resolvedSysID = rom?.systemID
        cachedShareButtonBinding     = cachedGC(.shareButton,       systemID: resolvedSysID)
        cachedRewindBinding           = cachedGC(.rewind,           systemID: resolvedSysID)
        cachedSlowMotionBinding       = cachedGC(.slowMotion,       systemID: resolvedSysID)
        cachedFastForwardBinding      = cachedGC(.fastForward,      systemID: resolvedSysID)
        cachedSaveStateBinding        = cachedGC(.saveState,        systemID: resolvedSysID)
        cachedLoadStateBinding        = cachedGC(.loadState,        systemID: resolvedSysID)
        cachedPauseBinding            = cachedGC(.pause,            systemID: resolvedSysID)
        cachedToggleGuideSidebarBinding = cachedGC(.toggleGuideSidebar, systemID: resolvedSysID)

        // Pre-warm rolling buffer so it's continuously recording before share press
        if RollingVideoBufferService.shared.isEnabled {
            LoggerService.info(category: "Runner", "Rolling buffer pre-warmed and recording")
        }

        // Wire long-press detector callbacks
        let detector = ControllerLongPressDetector.shared
        detector.onSinglePress = { [weak self] in
            LoggerService.info(category: "Runner", "onSinglePress fired")
            self?.handleSharePress(isLongPress: false)
        }
        detector.onLongPress = { [weak self] in
            LoggerService.info(category: "Runner", "onLongPress fired")
            self?.handleSharePress(isLongPress: true)
        }

        if cs.activePlayerIndex == 0 && !cs.connectedControllers.isEmpty {
            cs.activePlayerIndex = 1
        }

        let sysID = rom?.systemID ?? "default"

        for player in cs.connectedControllers {
            guard let controller = player.gcController,
                  let extendedGamepad = controller.extendedGamepad else { continue }

            let mapping: ControllerGamepadMapping
            if let identity = player.identityKey {
                mapping = cs.mapping(forIdentity: identity, systemID: sysID)
            } else {
                mapping = cs.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID)
            }
            let ports = player.assignedPlayers.map { $0 - 1 }

            for port in ports {
                LoggerService.info(category: "Runner", "Hooking gamepad: \(controller.vendorName ?? "Unknown") for port \(port) system: \(sysID)")
                self.hookedControllers[port] = controller
                if port == 0 { self.hookedController = controller }
            }

            extendedGamepad.valueChangedHandler = { [weak self] _, element in
                guard let self = self else { return }
                // Ignore controller input while the gamepad toolbar overlay is
                // open so presses aren't double-handled by the game.
                if GamepadNavigationManager.shared.isGamepadToolbarActive { return }

                // Share button: a single physical button that, depending on
                // press duration, dispatches the user's configured Single-press
                // or Long-press ShareBehavior (screenshot / record / etc).
                // SharingTabView owns the behavior pickers; this is just the
                // physical-press dispatch.
                if let button = element as? GCControllerButtonInput,
                   let name = element.localizedName,
                   name == self.cachedShareButtonBinding {
                    LoggerService.info(category: "Runner", "GC element: '\(name)' share button pressed=\(button.isPressed)")
                    if button.isPressed {
                        ControllerLongPressDetector.shared.handlePressDown(elementName: name)
                    } else {
                        ControllerLongPressDetector.shared.handlePressUp(elementName: name)
                    }
                    return
                }

                if let button = element as? GCControllerButtonInput,
                   let name = element.localizedName {
                    // Time machine controller bindings
                    if name == self.cachedRewindBinding {
                        if button.isPressed {
                            HardcoreModeManager.shared.attemptRewind {
                                Task { @MainActor in self.toggleTimeMachineMode() }
                            }
                        }
                        // Toggle semantics — no action on release.
                        return
                    }
                    if name == self.cachedSlowMotionBinding && button.isPressed {
                        HardcoreModeManager.shared.attemptSlowMotion {
                            Task { @MainActor in self.toggleSlowMotion() }
                        }
                        return
                    }
                    if name == self.cachedFastForwardBinding && button.isPressed {
                        HardcoreModeManager.shared.attemptFastForward {
                            Task { @MainActor in self.toggleFastForward() }
                        }
                        return
                    }

                    // Quick save / quick load controller hotkeys.
                    if button.isPressed {
                        if name == self.cachedSaveStateBinding {
                            HardcoreModeManager.shared.attemptSaveState {
                                Task { @MainActor in _ = self.saveState(slot: self.currentSlot) }
                            }
                            return
                        }
                        if name == self.cachedLoadStateBinding {
                            HardcoreModeManager.shared.attemptLoadState {
                                Task { @MainActor in _ = self.loadState(slot: self.currentSlot) }
                            }
                            return
                        }
                        if name == self.cachedPauseBinding {
                            if button.isPressed {
                                Task { @MainActor in self.togglePause() }
                            }
                            // Toggle semantics — no action on release.
                            return
                        }
                        if name == self.cachedToggleGuideSidebarBinding {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .toggleGuideSidebar, object: nil)
                            }
                            return
                        }
                    }
                }

                // Time Machine scrub mode: intercept directional inputs to
                // step the playhead. The dpad element arrives as a
                // GCControllerDirectionPad (read dpad.left/right sub-buttons
                // directly); analog stick events arrive as their own
                // GCControllerAxisInput/GCControllerButtonInput and route
                // through timeMachineScrubDirection via the user's
                // .lStickLeft/.lStickRight mappings. Inputs are NOT forwarded
                // to the core while scrubbing.
                if self.isRewindingStorage {
                    let dir: Int
                    if let dpad = element as? GCControllerDirectionPad {
                        let lPressed = dpad.left.isPressed
                        let rPressed = dpad.right.isPressed
                        #if LOG_DEBUG
                        LoggerService.debug(category: "TimeMachine", "Gamepad dpad element: left pressed=\(lPressed) right pressed=\(rPressed)")
                        #endif
                        if lPressed { dir = -1 }
                        else if rPressed { dir = 1 }
                        else { dir = 0 }
                    } else {
                        #if LOG_DEBUG
                        let nameForLog = element.localizedName ?? "<nil>"
                        let kindForLog = String(describing: type(of: element))
                        let computedDir = self.timeMachineScrubDirection(for: element, mapping: mapping, extendedGamepad: extendedGamepad)
                        LoggerService.debug(category: "TimeMachine", "Gamepad non-dpad element: name='\(nameForLog)' kind=\(kindForLog) computedDir=\(computedDir)")
                        dir = computedDir
                        #else
                        dir = self.timeMachineScrubDirection(for: element, mapping: mapping, extendedGamepad: extendedGamepad)
                        #endif
                    }
                    if dir != 0 {
                        let capturedDir = dir
                        LoggerService.info(category: "TimeMachine", "Stepping gamepad → dir=\(capturedDir)")
                        Task { @MainActor in self.stepTimeMachine(direction: capturedDir) }
                        return
                    }
                }

                for port in ports {
                    if let dpad = element as? GCControllerDirectionPad {
                        self.updateGamepadButton(dpad.up, in: mapping, extendedGamepad: extendedGamepad, player: port)
                        self.updateGamepadButton(dpad.down, in: mapping, extendedGamepad: extendedGamepad, player: port)
                        self.updateGamepadButton(dpad.left, in: mapping, extendedGamepad: extendedGamepad, player: port)
                        self.updateGamepadButton(dpad.right, in: mapping, extendedGamepad: extendedGamepad, player: port)
                        self.updateGamepadButton(dpad, in: mapping, extendedGamepad: extendedGamepad, player: port)
                    } else {
                        self.updateGamepadButton(element, in: mapping, extendedGamepad: extendedGamepad, player: port)
                    }
                }
            }
        }
    }

    func elementMatches(_ element: GCControllerElement, name: String) -> Bool {
        if element.localizedName == name { return true }
        if let sf = element.sfSymbolsName, sf == name { return true }
        if let unmapped = element.unmappedLocalizedName, unmapped == name { return true }
        return false
    }

    func elementMatches(_ element: GCControllerElement, mapping: GCButtonMapping, extendedGamepad: GCExtendedGamepad?) -> Bool {
        if let identifier = mapping.identifier, identifier != .vendorSpecific {
            if identifier.matches(element: element, extendedGamepad: extendedGamepad) { return true }
        }
        if let name = mapping.gcElementName, !name.isEmpty {
            return elementMatches(element, name: name)
        }
        return false
    }

    /// While in Time Machine scrub mode, return -1 (left) / +1 (right) / 0
    /// (no match) for the dpad/stick element the user pressed, according to
    /// whatever they've bound to RetroButton.left / .right / .lStickLeft /
    /// .lStickRight for the current core. Non-isolated — matches how
    /// updateGamepadButton is invoked from the GCController valueChangedHandler
    /// (which fires on a non-main queue).
    func timeMachineScrubDirection(for element: GCControllerElement, mapping: ControllerGamepadMapping, extendedGamepad: GCExtendedGamepad?) -> Int {
        for (btn, btnMapping) in mapping.buttons {
            guard btn == .left || btn == .right || btn == .lStickLeft || btn == .lStickRight ||
                  btn == .rStickLeft || btn == .rStickRight else { continue }
            if !elementMatches(element, mapping: btnMapping, extendedGamepad: extendedGamepad) { continue }
            switch btn {
            case .left, .lStickLeft, .rStickLeft: return -1
            case .right, .lStickRight, .rStickRight: return 1
            default: return 0
            }
        }
        return 0
    }

    func updateGamepadButton(_ element: GCControllerElement, in mapping: ControllerGamepadMapping, extendedGamepad: GCExtendedGamepad? = nil, player: Int = 0) {
        for (btn, btnMapping) in mapping.buttons {
            guard elementMatches(element, mapping: btnMapping, extendedGamepad: extendedGamepad) else { continue }
            
            if let info = btn.analogInfo {
                var value: Float = 0.0
                
                if let btnElement = element as? GCControllerButtonInput {
                    value = btnElement.value
                } else if let axisElement = element as? GCControllerAxisInput {
                    value = abs(axisElement.value)
                } else if let stick = element as? GCControllerDirectionPad {
                    let axisVal = (info.id == 0) ? stick.xAxis.value : stick.yAxis.value
                    value = abs(axisVal)
                }
                
                analogButtonStates[btn] = value
                
                var aggregatedAxisValue: Float = 0.0
                for (mappedBtn, _) in mapping.buttons {
                    if let otherInfo = mappedBtn.analogInfo, 
                    otherInfo.index == info.index, 
                    otherInfo.id == info.id {
                        let btnState = analogButtonStates[mappedBtn] ?? 0.0
                        aggregatedAxisValue += (btnState * otherInfo.sign)
                    }
                }
                
            let deadzone = info.index == 0 ? mapping.leftStickDeadzone : mapping.rightStickDeadzone
            aggregatedAxisValue = AnalogDeadZone(radial: deadzone, anti: 0.0).apply(aggregatedAxisValue)
        aggregatedAxisValue = max(-1.0, min(1.0, aggregatedAxisValue))
        let retroValue = Int32(aggregatedAxisValue * 32767.0)
        XPCBridgeAdapter.shared.setAnalogState(Int(info.index), id: Int(info.id), value: retroValue, player: player)
        }

        // 1b. Handle Mouse Buttons — route to mouse button state instead of joypad
        else if btn == .mouseLeft || btn == .mouseRight || btn == .mouseMiddle {
            let buttonIndex = btn == .mouseLeft ? 0 : (btn == .mouseRight ? 1 : 2)
            if let btnElement = element as? GCControllerButtonInput {
                XPCBridgeAdapter.shared.setMouseButton(buttonIndex, pressed: btnElement.isPressed)
            } else if let axisElement = element as? GCControllerAxisInput {
                XPCBridgeAdapter.shared.setMouseButton(buttonIndex, pressed: abs(axisElement.value) > 0.5)
            }
        }

        // 2. Handle Digital Joypad Buttons (ID 0 to 15)
        else if btn.retroID(for: self.systemID, coreID: self.activeCoreID) >= 0 {
            let retroID = Int(btn.retroID(for: self.systemID, coreID: self.activeCoreID))
                
                if let btnElement = element as? GCControllerButtonInput {
                    // Send analog value for L2/R2 triggers (used by Flycast for Dreamcast analog triggers)
                    if retroID == 12 || retroID == 13 {
                let analogValue = Int32(btnElement.value * 32767.0)
                XPCBridgeAdapter.shared.setAnalogButtonState(retroID: retroID, value: analogValue, player: player)
                    }
                    // This covers face buttons, triggers (Z-button), and D-pad directions
                    self.setKeyState(retroID: retroID, player: player, pressed: btnElement.isPressed)
                } 
                else if let axisElement = element as? GCControllerAxisInput {
                    // Send analog value for L2/R2 triggers mapped to axes
                    if retroID == 12 || retroID == 13 {
                let analogValue = Int32(abs(axisElement.value) * 32767.0)
                XPCBridgeAdapter.shared.setAnalogButtonState(retroID: retroID, value: analogValue, player: player)
                    }
                    // If a digital button is mapped to an axis (like a trigger mapped to 'A')
                    self.setKeyState(retroID: retroID, player: player, pressed: abs(axisElement.value) > 0.5)
                }
                // NOTE: Removed the 'GCControllerDirectionPad' check here.
                // Mapping names like "D-pad Up" refer to button sub-elements in GameController.
            }
            
            // 3. Handle System Buttons (Pause, Reset, etc. with retroID: -1)
            else {
                if let btnElement = element as? GCControllerButtonInput, btnElement.isPressed {
                    // Handle non-gameplay actions here (e.g., open menu, toggle fast forward)
                    self.handleSystemAction(for: btn)
                }
            }
        }
    }

    // Helper to handle buttons that aren't mapped to the libretro virtual controller
    private func handleSystemAction(for btn: RetroButton) {
        switch btn {
        case .pause:
            break
        case .reset:
            break
        default:
            break
        }
    }

    func setupAnalogMouseTimer(primaryStick: GCControllerDirectionPad, secondaryStick: GCControllerDirectionPad,
                                sensitivity: Float, deadZone: Float) {
        analogMouseTimer?.invalidate()
        analogMouseAccumulatedDX = 0
        analogMouseAccumulatedDY = 0

        analogMouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }

        if GameGuideViewModel.isGuideSidebarOpen {
            let pX = primaryStick.xAxis.value
            let pY = primaryStick.yAxis.value
            let sX = secondaryStick.xAxis.value
            let sY = secondaryStick.yAxis.value
            var moveX: CGFloat = 0
            var moveY: CGFloat = 0
            if fabsf(pX) >= deadZone { moveX += CGFloat(pX * sensitivity * 12.0) }
            if fabsf(pY) >= deadZone { moveY += CGFloat(pY * sensitivity * 12.0) }
            if fabsf(sX) >= deadZone { moveX += CGFloat(sX * sensitivity * 6.0) }
            if fabsf(sY) >= deadZone { moveY += CGFloat(sY * sensitivity * 6.0) }

            if moveX != 0 || moveY != 0 {
                if self.sidebarCursorX == nil {
                    let loc = NSEvent.mouseLocation
                    self.sidebarCursorX = loc.x
                    self.sidebarCursorY = loc.y
                }
                self.sidebarCursorX! += moveX
                self.sidebarCursorY! += moveY
                let screen = NSScreen.main?.frame ?? .zero
                self.sidebarCursorX = max(screen.minX, min(screen.maxX, self.sidebarCursorX!))
                self.sidebarCursorY = max(screen.minY, min(screen.maxY, self.sidebarCursorY!))
                let cgPoint = CGPoint(x: self.sidebarCursorX!, y: screen.height - self.sidebarCursorY!)
                CGDisplayMoveCursorToPoint(CGMainDisplayID(), cgPoint)
            }
            return
        }

            self.sidebarCursorX = nil
            self.sidebarCursorY = nil

            var xVal = primaryStick.xAxis.value
            var yVal = primaryStick.yAxis.value
            if fabsf(xVal) < deadZone { xVal = 0 }
            if fabsf(yVal) < deadZone { yVal = 0 }

            var fdx = Float(xVal) * sensitivity * 8.0
            var fdy = Float(-yVal) * sensitivity * 8.0

            let x2 = secondaryStick.xAxis.value
            let y2 = secondaryStick.yAxis.value
            if fabsf(x2) >= deadZone { fdx += Float(x2) * sensitivity * 8.0 * 0.2 }
            if fabsf(y2) >= deadZone { fdy += Float(-y2) * sensitivity * 8.0 * 0.2 }

            self.analogMouseAccumulatedDX += fdx
            self.analogMouseAccumulatedDY += fdy

            let dx = Int16(clamping: Int(self.analogMouseAccumulatedDX.rounded()))
            let dy = Int16(clamping: Int(self.analogMouseAccumulatedDY.rounded()))
            self.analogMouseAccumulatedDX -= Float(dx)
            self.analogMouseAccumulatedDY -= Float(dy)

            XPCBridgeAdapter.shared.setAnalogMouseDeltaX(dx, y: dy)
        }
    }

    func handleAnalogMouseButton(_ raw: String, pressed: Bool) {
        if raw == analogMouseButtonLeft || raw == "y" {
            if GameGuideViewModel.isGuideSidebarOpen {
                postMacMouseClick(button: .left, down: pressed)
            } else if raw == analogMouseButtonLeft {
                XPCBridgeAdapter.shared.setMouseButton(0, pressed: pressed)
            }
        } else if raw == analogMouseButtonDownRight {
            if GameGuideViewModel.isGuideSidebarOpen {
                postMacMouseClick(button: .right, down: pressed)
            } else {
                XPCBridgeAdapter.shared.setMouseButton(1, pressed: pressed)
            }
        } else if raw == analogMouseButtonDownMiddle {
            if GameGuideViewModel.isGuideSidebarOpen {
                postMacMouseClick(button: .center, down: pressed)
            } else {
                XPCBridgeAdapter.shared.setMouseButton(2, pressed: pressed)
            }
        }
    }

    func handleGuideToggleButton(retroBtn: RetroButton, pressed: Bool, systemID: String) {
        let stickString = AppSettings.getString("analogMouse_stick_\(systemID)", defaultValue: "left") ?? "left"
        let isToggle = (stickString == "right" && retroBtn == .l3) || (stickString == "left" && retroBtn == .r3)
        if isToggle && pressed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleGuideSidebar, object: nil)
            }
        }
    }

    func postMacMouseClick(button: CGMouseButton, down: Bool) {
        let appKitPoint: NSPoint
        if let x = sidebarCursorX, let y = sidebarCursorY {
            appKitPoint = NSPoint(x: x, y: y)
        } else {
            appKitPoint = NSEvent.mouseLocation
        }

        let nsEventType: NSEvent.EventType
        switch button {
        case .left:   nsEventType = down ? .leftMouseDown : .leftMouseUp
        case .right:  nsEventType = down ? .rightMouseDown : .rightMouseUp
        case .center: nsEventType = down ? .otherMouseDown : .otherMouseUp
        default:      nsEventType = down ? .leftMouseDown : .leftMouseUp
        }

        LoggerService.info(category: "Runner", "postMacMouseClick: appKit=\(appKitPoint) AX=\(AXIsProcessTrusted()) gameWindow=\(String(describing: gameWindow))")

        // Try via NSApp (routes to key window, in-process)
        let window = gameWindow ?? NSApp.keyWindow
        let windowPoint = window?.convertPoint(fromScreen: appKitPoint) ?? .zero
        if let mouseEvent = NSEvent.mouseEvent(
            with: nsEventType,
            location: windowPoint,
            modifierFlags: [],
            timestamp: CACurrentMediaTime(),
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: down ? 1.0 : 0.0
        ) {
            DispatchQueue.main.async {
                if let w = window {
                    w.sendEvent(mouseEvent)
                    LoggerService.info(category: "Runner", "postMacMouseClick: window.sendEvent button=\(button.rawValue) down=\(down)")
                } else {
                    LoggerService.info(category: "Runner", "postMacMouseClick: no window, cannot click")
                }
            }
        }
    }
}

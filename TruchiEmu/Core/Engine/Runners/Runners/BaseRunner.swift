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
        XPCBridgeAdapter.shared.serializeSize() > 0
    }
    
    internal var device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var emulationQueue = DispatchQueue(label: "truchiemu.emulation", qos: .userInteractive)
    internal var isRunning = false
    private var hasLoggedFrame = false
    private var runnerFrameCount = 0
    private var textureCache: MTLTexture? = nil
    private let textureLock = NSLock()
    @MainActor @Published var rom: ROM?
    @MainActor @Published var lastError: GameError?
    var romPath: String = ""
    private var analogButtonStates: [RetroButton: Float] = [:]
    @MainActor @Published private(set) var currentInputState: [Int: Bool] = [:]
    
    // Expose saveManager for UI access
    var saveManager: SaveStateManager { _saveManager }
    private let _saveManager = SaveStateManager()
    // Keyboard mapping snapshot captured at launch — safe to read from any thread.
    var cachedKeyboardMapping: KeyboardMapping = KeyboardMapping(buttons: [:])
    private var hookedController: GCController? = nil
    private var hookedControllers: [Int: GCController] = [:]
    
    // Turbo button state tracking
    private var activeTurboButtons: Set<RetroButton> = []

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
                isRunning = false
                self.stop()
                return
            }
        } else {
            self.romPath = rom.path.path
        }
        let sysID = rom.systemID ?? "default"
        var mapping = ControllerService.shared.keyboardMapping(for: sysID)
        if mapping.buttons.isEmpty {
            mapping = KeyboardMapping.defaults(for: sysID)
        }
        self.cachedKeyboardMapping = mapping
        
        setupGamepadInput()
        
        isRunning = true
        
        let selectedLang = SystemPreferences.shared.systemLanguage.libretroRawValue
        let selectedLogLevel = LoggerService.shared.currentLevel.coreLogLevelValue
        
        // Track last loaded core so Options view knows which file to persist to
        AppSettings.set("lastLoadedCoreID", value: coreID)

        // Get the bundled slang shader directory path
        let shaderDir = Bundle.main.resourceURL?.appendingPathComponent("slang").path

        // Register callback to load SRAM when game is loaded
        XPCBridgeAdapter.shared.registerGameLoadedCallback { [weak self] romPath in
            self?.loadSRAMOnGameLoad(romPath: romPath)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .gameLoaded, object: nil)
            }
        }

        let savedDir = XPCBridgeAdapter.shared.saveDirectoryPath()
        LoggerService.info(category: "Runner", "Using save directory: \(savedDir)")

        let rom = self.rom
        let dylibPath = self.findCoreLib(coreID: coreID) ?? coreID
        let cachedAchievements = self.rcheevosAchievements ?? []
        let resolvedRomPath = self.romPath
        let genesisControllerType = AppSettings.getGenesisControllerType()

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
        undoBuffer = nil
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
        osdMessage = isPaused ? "Paused" : "Resumed"
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self.osdMessage = nil }
        }
    }
    
    // Reload the current ROM
    @MainActor
    func reloadGame() {
        guard let gameRom = rom else { return }
        guard gameRom.systemID != nil else { return }
        
        // Store current core info
        let coreID = AppSettings.get("lastLoadedCoreID", type: String.self) ?? ""
        
        // Reset pause state
        isPaused = false
        XPCBridgeAdapter.shared.setPaused(false)
        
        // Stop current game
        stop()
        
        // Small delay to ensure cleanup
        Thread.sleep(forTimeInterval: 0.1)
        
        // Re-setup controller input after reload
        setupGamepadInput()
        
        // Relaunch
        isRunning = true
        let shaderDir = Bundle.main.resourceURL?.appendingPathComponent("slang").path
        emulationQueue.async {
            XPCBridgeAdapter.shared.launch(
                dylibPath: self.findCoreLib(coreID: coreID) ?? coreID,
                romPath: gameRom.path.path,
                coreID: coreID,
                systemID: gameRom.systemID,
                romFilename: gameRom.path.lastPathComponent,
                shaderDir: shaderDir,
                videoCallback: { [weak self] data, width, height, pitch, format in
                    self?.updateFrame(data: data, width: width, height: height, pitch: pitch, format: format)
                }
            )
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
            
            if let v = actualVersion {
                osdMessage = "Saved \(slot == -1 ? "Auto" : "Slot \(slot)") #\(v)"
            } else {
                osdMessage = "Saved \(slot == -1 ? "Auto" : "Slot \(slot)")"
            }
            
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
            osdMessage = "Loaded save state"
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
            osdMessage = "Loaded \(slot == -1 ? "Auto" : "Slot \(slot)")"
            rcheevosLock.lock()
            _needsRcheevosReset = true
            rcheevosLock.unlock()
            
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
            osdMessage = "Nothing to undo"
            return false
        }
        
        // Decompress undo buffer if needed
        let actualData: Data
        if let decompressed = SaveStateManager.decompressStateData(undoData) {
            actualData = decompressed
        } else {
            osdMessage = "Error: Could not restore previous state"
            return false
        }
        
        let success = XPCBridgeAdapter.shared.unserializeState(actualData)
        if success {
            undoBuffer = nil
            osdMessage = "Undo successful"
            
            // Clear OSD after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
        } else {
            osdMessage = "Error: Could not restore previous state"
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
        osdMessage = "Slot: \(currentSlot)"
        
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
        osdMessage = "Slot: \(currentSlot)"
        
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
        for (button, code) in cachedKeyboardMapping.buttons {
            if code == keyCode {
                let rid = Int(button.retroID(for: self.systemID, coreID: self.activeCoreID))
                guard rid >= 0 else { return nil }
                return (retroID: rid, player: button.playerIndex)
            }
        }
        return nil
    }

    @MainActor
    open func setupGamepadInput() {
        let cs = ControllerService.shared

        LoggerService.info(category: "Runner", "setupGamepadInput: connectedControllers=\(cs.connectedControllers.map { $0.name })")

        if cs.activePlayerIndex == 0 && !cs.connectedControllers.isEmpty {
            cs.activePlayerIndex = 1
        }

        let sysID = rom?.systemID ?? "default"

        for player in cs.connectedControllers {
            guard let controller = player.gcController,
                  let extendedGamepad = controller.extendedGamepad else { continue }

            let mapping = cs.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID)
            let ports = player.assignedPlayers.map { $0 - 1 }

            for port in ports {
                LoggerService.info(category: "Runner", "Hooking gamepad: \(controller.vendorName ?? "Unknown") for port \(port) system: \(sysID)")
                self.hookedControllers[port] = controller
                if port == 0 { self.hookedController = controller }
            }

            extendedGamepad.valueChangedHandler = { [weak self] _, element in
                guard let self = self else { return }
                for port in ports {
                    if let dpad = element as? GCControllerDirectionPad {
                        self.updateGamepadButton(dpad.up, in: mapping, player: port)
                        self.updateGamepadButton(dpad.down, in: mapping, player: port)
                        self.updateGamepadButton(dpad.left, in: mapping, player: port)
                        self.updateGamepadButton(dpad.right, in: mapping, player: port)
                        self.updateGamepadButton(dpad, in: mapping, player: port)
                    } else {
                        self.updateGamepadButton(element, in: mapping, player: port)
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

    func updateGamepadButton(_ element: GCControllerElement, in mapping: ControllerGamepadMapping, player: Int = 0) {
        for (btn, btnMapping) in mapping.buttons {
            guard elementMatches(element, name: btnMapping.gcElementName) else { continue }
            
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
            // Trigger your emulator pause logic
            break
        case .reset:
            // Trigger your emulator reset logic
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

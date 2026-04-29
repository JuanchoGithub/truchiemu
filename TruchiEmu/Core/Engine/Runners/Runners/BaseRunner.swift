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
        LoggerService.error(category: "Renderer", "Unsupported pixel format: \(texture.pixelFormat.rawValue)")
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
        // Standard BGRA8888 format
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        byteArray.withUnsafeMutableBytes { ptr in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return }
            cgImage = context.makeImage()
        }
        
    case .b5g6r5Unorm:
        // RGB565 - need to expand to 32-bit
        let expanded = expandRGB565toBGRA(from: byteArray, width: width, height: height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little)
        expanded.withUnsafeBytes { ptr in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return }
            cgImage = context.makeImage()
        }
        
    case .a1bgr5Unorm, .bgr5A1Unorm:
        // ARGB1555 / BGR5A1 - expand to 32-bit
        let expanded = expandARGB1555toBGRA(from: byteArray, width: width, height: height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        expanded.withUnsafeBytes { ptr in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return }
            cgImage = context.makeImage()
        }
        
    default:
        return nil
    }
    
    guard let image = cgImage else { return nil }
    
    return NSImage(cgImage: image, size: NSSize(width: width, height: height))
}

// Expand RGB565 data to BGRA8888
private func expandRGB565toBGRA(from data: [UInt8], width: Int, height: Int) -> [UInt8] {
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
        
        // Write as BGRA (skip alpha)
        let dstOffset = i * 4
        result[dstOffset] = expandedB       // B
        result[dstOffset + 1] = expandedG   // G
        result[dstOffset + 2] = expandedR   // R
        result[dstOffset + 3] = 0xFF        // A (unused)
    }
    
    return result
}

// Expand ARGB1555 data to BGRA8888
private func expandARGB1555toBGRA(from data: [UInt8], width: Int, height: Int) -> [UInt8] {
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
        
        // Write as BGRA
        let dstOffset = i * 4
        result[dstOffset] = expandedB       // B
        result[dstOffset + 1] = expandedG   // G
        result[dstOffset + 2] = expandedR   // R
        result[dstOffset + 3] = expandedA   // A
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
    
    // MARK: - Save State
    @MainActor @Published var currentSlot: Int = 0
    @MainActor @Published var osdMessage: String?
    var undoBuffer: Data?
    
    var systemID: String = "default"

    // Whether the current core supports save states
    var supportsSaveStates: Bool {
        LibretroBridgeSwift.serializeSize() > 0
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
    
    // Expose saveManager for UI access
    var saveManager: SaveStateManager { _saveManager }
    private let _saveManager = SaveStateManager()
    // Keyboard mapping snapshot captured at launch — safe to read from any thread.
    var cachedKeyboardMapping: KeyboardMapping = KeyboardMapping(buttons: [:])
    private var hookedController: GCController? = nil
    
    // Turbo button state tracking
    private var activeTurboButtons: Set<RetroButton> = []
    
    static func forSystem(_ systemID: String?) -> EmulatorRunner {
        let runner: EmulatorRunner
        switch systemID {
        case "nes":      runner = NESRunner()
        case "snes":     runner = SNESRunner()
        case "n64":      runner = N64Runner()
        case "dos":      runner = DOSRunner()
        case "scummvm":  runner = ScummVMRunner()
        default:         runner = EmulatorRunner()
        }
        runner.systemID = systemID ?? "default"
        return runner
    }



    @MainActor
    func launch(rom: ROM, coreID: String) {
        if findCoreLib(coreID: coreID) == nil {
            LoggerService.error(category: "Runner", "Core dylib not found: \(coreID)")
            isRunning = false
            self.stop()
            return
        }
        
        self.rom = rom
        self.romPath = rom.path.path
        let sysID = rom.systemID ?? "default"
        var mapping = ControllerService.shared.keyboardMapping(for: sysID)
        if mapping.buttons.isEmpty {
            mapping = KeyboardMapping.defaults(for: sysID)
        }
        self.cachedKeyboardMapping = mapping
        
        setupGamepadInput()
        
        isRunning = true
        
        let selectedLang = SystemPreferences.shared.systemLanguage.rawValue
        let selectedLogLevel = Int32(SystemPreferences.shared.coreLogLevel.rawValue)
        
        // Track last loaded core so Options view knows which file to persist to
        AppSettings.set("lastLoadedCoreID", value: coreID)

        // Get the bundled slang shader directory path
        let shaderDir = Bundle.main.resourceURL?.appendingPathComponent("slang").path

        // Register callback to load SRAM when game is loaded
        LibretroBridgeSwift.registerGameLoadedCallback { [weak self] romPath in
            self?.loadSRAMOnGameLoad(romPath: romPath)
        }

        let savedDir = LibretroBridgeSwift.saveDirectoryPath()
        LoggerService.info(category: "Runner", "Using save directory: \(savedDir)")
        
  emulationQueue.async {
    LibretroBridgeSwift.setLanguage(selectedLang)
    LibretroBridgeSwift.setLogLevel(Int(selectedLogLevel))
    
    // Ensure save directories are created and configured
    SaveDirectoryBridge.ensureDirectoriesExist()

    let dylibPath = self.findCoreLib(coreID: coreID) ?? coreID

    // We don't have a direct way to catch a SIGSEGV here,
    // but we can catch potential Swift errors if the bridge was designed to throw.
    // For now, we ensure we handle the launch result.
    LibretroBridgeSwift.launch(
                dylibPath: dylibPath, 
                romPath: self.rom!.path.path,
                coreID: coreID,
                systemID: self.rom!.systemID,
                shaderDir: shaderDir,
                videoCallback: { [weak self] data, width, height, pitch, format in
                    self?.updateFrame(data: data, width: width, height: height, pitch: pitch, format: format)
                },
                onFailure: { [weak self] message in
                    Task { @MainActor in
                        LoggerService.error(category: "Runner", "Core launch failed: \(message)")
                        self?.lastError = .launchFailed(reason: message)
                        self?.isRunning = false
                    }
                }
            )
            
            // If we reach here, the launch call has returned. 
            // We should verify if it actually succeeded.
            // This is a bit speculative without more info from the bridge, 
            // but it's a good place to check.
        }
    }

    // MARK: - Pause State
    @MainActor @Published var isPaused: Bool = false
    
    @MainActor
    func stop() {
        LoggerService.info(category: "Runner", "Stopping emulation thread")
        isRunning = false

        // Save SRAM before stopping the core
        saveSRAMIfAvailable()

        LibretroBridgeSwift.stop()

        // Wait for the core to fully terminate (retro_unload_game + retro_deinit)
        // This ensures the core is completely killed before proceeding
        LibretroBridgeSwift.waitForCompletion()

        hookedController?.extendedGamepad?.valueChangedHandler = nil
        hookedController = nil
    }

// MARK: - SRAM Save/Load

    private func loadSRAMOnGameLoad(romPath: String) {
        let romURL = URL(fileURLWithPath: romPath)
        let saveDir = LibretroBridgeSwift.saveDirectoryPath()
        let baseName = romURL.deletingPathExtension().lastPathComponent

        let extensions = ["srm", "sav", "save"]
        for ext in extensions {
            let sramURL = URL(fileURLWithPath: saveDir).appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: sramURL.path) {
                do {
                    let sramData = try Data(contentsOf: sramURL)
                    if LibretroBridgeSwift.loadSaveRAMData(sramData) {
                        LoggerService.info(category: "Runner", "Loaded SRAM (\(sramData.count) bytes) from: \(sramURL.path)")
                    }
                } catch {
                    LoggerService.error(category: "Runner", "Failed to load SRAM: \(error.localizedDescription)")
                }
                return
            }
        }

        LoggerService.debug(category: "Runner", "No SRAM file found for: \(baseName)")
    }

    @MainActor
    private func sramFilePath(for rom: ROM) -> URL {
        let saveDir = URL(fileURLWithPath: LibretroBridgeSwift.saveDirectoryPath())
        let baseName = rom.path.deletingPathExtension().lastPathComponent
        return saveDir.appendingPathComponent("\(baseName).srm")
    }

    @MainActor
    private func saveSRAMIfAvailable() {
        guard let gameRom = rom else {
            LoggerService.debug(category: "Runner", "No ROM loaded, skipping SRAM save")
            return
        }

        guard let sramData = LibretroBridgeSwift.getSaveRAMData(), !sramData.isEmpty else {
            LoggerService.debug(category: "Runner", "No SAVE_RAM to save for \(gameRom.displayName)")
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
            LoggerService.debug(category: "Runner", "No SRAM file found at: \(sramPath.path)")
            return
        }

        do {
            let sramData = try Data(contentsOf: sramPath)
            guard LibretroBridgeSwift.loadSaveRAMData(sramData) else {
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
        LibretroBridgeSwift.setPaused(isPaused)
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
        LibretroBridgeSwift.setPaused(false)
        
        // Stop current game
        stop()
        
        // Small delay to ensure cleanup
        Thread.sleep(forTimeInterval: 0.1)
        
        // Relaunch
        isRunning = true
        let shaderDir = Bundle.main.resourceURL?.appendingPathComponent("slang").path
        emulationQueue.async {
            LibretroBridgeSwift.launch(
                dylibPath: self.findCoreLib(coreID: coreID) ?? coreID, 
                romPath: gameRom.path.path,
                coreID: coreID,
                systemID: gameRom.systemID,
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
    
    // Save the current emulator state to the specified slot
    @MainActor
    func saveState(slot: Int) -> Bool {
        guard supportsSaveStates else {
            let error = GameError.saveStateError(reason: "Core doesn't support save states")
            osdMessage = error.localizedDescription
            self.lastError = error
            return false
        }
        
        guard let stateData = LibretroBridgeSwift.serializeState() else {
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
        let stateURL = saveManager.statePath(gameName: gameRom.displayName, systemID: systemID, slot: slot)
        
        do {
            // Apply compression if enabled
            let finalData: Data
            if compressSaveStates, let compressed = SaveStateManager.compressStateData(stateData) {
                finalData = compressed
                let ratio = Double(finalData.count) / Double(stateData.count) * 100
                LoggerService.debug(category: "SaveState", "Compressed: \(Int64(stateData.count).formattedByteSize) -> \(Int64(finalData.count).formattedByteSize) (\(Int(ratio))%)")
            } else {
                finalData = stateData
            }
            
            try finalData.write(to: stateURL, options: [.atomic])
            
            // Capture and save thumbnail if we have a current frame
            if let frameTex = currentFrameTexture {
                LoggerService.debug(category: "SaveState", "Capturing thumbnail for slot \(slot)")
                let nsImage = NSImageFromMTLTexture(frameTex)
                if let nsImage = nsImage {
                    LoggerService.debug(category: "SaveState", "Captured thumbnail: \(nsImage.size.width)x\(nsImage.size.height)")
                    saveManager.saveThumbnail(nsImage, gameName: gameRom.displayName, systemID: systemID, slot: slot)
                } else {
                    LoggerService.error(category: "SaveState", "ERROR: NSImageFromMTLTexture returned nil")
                }
            } else {
                LoggerService.debug(category: "SaveState", "WARNING: currentFrameTexture is nil, cannot capture thumbnail")
            }
            
            osdMessage = "Saved \(slot == -1 ? "Auto" : "Slot \(slot)")"
            
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
        let stateURL = saveManager.statePath(gameName: gameRom.displayName, systemID: systemID, slot: slot)
        
        // Save current state as undo buffer before loading
        undoBuffer = LibretroBridgeSwift.serializeState()
        
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
        
        let success = LibretroBridgeSwift.unserializeState(actualData)
        if success {
            osdMessage = "Loaded \(slot == -1 ? "Auto" : "Slot \(slot)")"
            
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
        
        let success = LibretroBridgeSwift.unserializeState(actualData)
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
        LibretroBridgeSwift.setKeyState(retroID: retroID, pressed: pressed)
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

        let mtlFormat = mapPixelFormat(format)

        let tex: MTLTexture
        if let existing = textureCache, existing.width == width, existing.height == height, existing.pixelFormat == mtlFormat {
            tex = existing
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mtlFormat,
                                                                 width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            guard let newTex = device.makeTexture(descriptor: desc) else { return }
            tex = newTex
            textureCache = tex
        }
        
        tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: data,
                    bytesPerRow: pitch)

        #if DEBUG
        if systemID == "n64" {
            let firstPixelPtr = data.bindMemory(to: UInt32.self, capacity: 1)
            if firstPixelPtr.pointee == 0 {
                LoggerService.warning(category: "Runner", "N64 frame pixel[0] is 0x00000000 - possible readback failure")
            }
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
                let rotation = LibretroBridgeSwift.currentRotation()
                if self.currentFrameRotation != Int(rotation) {
                    self.currentFrameRotation = Int(rotation)
                    LoggerService.info(category: "Runner", "Frame rotation: \(rotation) (\(rotation * 90) deg CW)")
                }
            }

            self.runnerFrameCount += 1
        }
    }

    internal func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
        // Defaults to common format
        switch format {
        case 0: return .a1bgr5Unorm // 0RGB1555
        case 1: return .bgra8Unorm  // XRGB8888
        case 2: return .b5g6r5Unorm // RGB565
        default: return .bgra8Unorm
        }
    }

    func mapKey(_ keyCode: UInt16) -> Int? {
        for (button, code) in cachedKeyboardMapping.buttons {
            if code == keyCode {
                return Int(button.retroID(for: self.systemID))
            }
        }
        return nil
    }

    @MainActor
    func setupGamepadInput() {
        // Ensure ControllerService is initialized
        let cs = ControllerService.shared
        
        // Debug: Log controller state
        LoggerService.info(category: "Runner", "setupGamepadInput: activePlayerIndex=\(cs.activePlayerIndex), connectedControllers=\(cs.connectedControllers.map { $0.name })")
        
        // Auto-select first controller if none selected
        if cs.activePlayerIndex == 0 && !cs.connectedControllers.isEmpty {
            cs.activePlayerIndex = 1
        }
        
        let activeIdx = cs.activePlayerIndex
        LoggerService.info(category: "Runner", "setupGamepadInput: after auto-select, activeIdx=\(activeIdx)")
        
        if activeIdx == 0 { return } // Keyboard
        
        guard let player = cs.connectedControllers.first(where: { $0.playerIndex == activeIdx }),
              let controller = player.gcController else { return }
        
        let sysID = rom?.systemID ?? "default"
        let mapping = cs.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID) as ControllerGamepadMapping
        
        guard let extendedGamepad = controller.extendedGamepad else {
            LoggerService.info(category: "Runner", "ERROR: No extendedGamepad on controller!")
            return
        }
        
        LoggerService.info(category: "Runner", "Hooking gamepad: \(controller.vendorName ?? "Unknown") for system: \(sysID)")
        self.hookedController = controller
        
extendedGamepad.valueChangedHandler = { [weak self] _, element in
            guard let self = self else { return }
            
            // Debug: log every input event
            let elemName = element.localizedName ?? "unknown"
            let isPressed = (element as? GCControllerButtonInput)?.isPressed ?? false
            
            // If it's a DPad or Stick, we want to handle its 4 directions
            if let dpad = element as? GCControllerDirectionPad {
                self.updateGamepadButton(dpad.up, in: mapping)
                self.updateGamepadButton(dpad.down, in: mapping)
                self.updateGamepadButton(dpad.left, in: mapping)
                self.updateGamepadButton(dpad.right, in: mapping)
                // Also update the pad itself for analog stick support
                self.updateGamepadButton(dpad, in: mapping)
            } else {
                self.updateGamepadButton(element, in: mapping)
            }
        }
    }

    private func updateGamepadButton(_ element: GCControllerElement, in mapping: ControllerGamepadMapping) {
        let name = element.localizedName ?? ""

        for (btn, btnMapping) in mapping.buttons {
            // Only process the mapping that matches the physical element that changed
            guard btnMapping.gcElementName == name else { continue }
            
            // 1. Handle Analog Sticks / Axes (e.g., N64 Analog Stick)
            if let info = btn.analogInfo {
                var value: Float = 0.0
                
                if let btnElement = element as? GCControllerButtonInput {
                    value = btnElement.value
                } else if let axisElement = element as? GCControllerAxisInput {
                    value = abs(axisElement.value)
                } else if let stick = element as? GCControllerDirectionPad {
                    // Rare case: If the mapping points to the whole stick
                    let axisVal = (info.id == 0) ? stick.xAxis.value : stick.yAxis.value
                    value = abs(axisVal)
                }
                
                analogButtonStates[btn] = value
                
                // Aggregate directions for this specific axis (e.g., combine Up + Down into one Y axis)
                var aggregatedAxisValue: Float = 0.0
                for (mappedBtn, _) in mapping.buttons {
                    if let otherInfo = mappedBtn.analogInfo, 
                    otherInfo.index == info.index, 
                    otherInfo.id == info.id {
                        let btnState = analogButtonStates[mappedBtn] ?? 0.0
                        aggregatedAxisValue += (btnState * otherInfo.sign)
                    }
                }
                
                aggregatedAxisValue = max(-1.0, min(1.0, aggregatedAxisValue))
                let retroValue = Int32(aggregatedAxisValue * 32767.0)
                LibretroBridgeSwift.setAnalogState(Int(info.index), id: Int(info.id), value: retroValue)
            } 
            
            // 2. Handle Digital Joypad Buttons (ID 0 to 15)
            else if btn.retroID(for: self.systemID) >= 0 {
                let retroID = Int(btn.retroID(for: self.systemID))
                
                if let btnElement = element as? GCControllerButtonInput {
                    // This covers face buttons, triggers (Z-button), and D-pad directions
                    self.setKeyState(retroID: retroID, pressed: btnElement.isPressed)
                } 
                else if let axisElement = element as? GCControllerAxisInput {
                    // If a digital button is mapped to an axis (like a trigger mapped to 'A')
                    self.setKeyState(retroID: retroID, pressed: abs(axisElement.value) > 0.5)
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
}

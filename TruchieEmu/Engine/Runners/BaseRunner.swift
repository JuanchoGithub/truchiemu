import MetalKit
import Foundation
import SwiftUI
import GameController
import AppKit

// MARK: - MTLTexture to NSImage conversion

/// Convert MTLTexture to NSImage using Metal texture bytes directly
func NSImageFromMTLTexture(_ texture: MTLTexture) -> NSImage? {
    let width = texture.width
    let height = texture.height
    
    guard texture.pixelFormat == .bgra8Unorm else { return nil }
    
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let byteCount = width * height * bytesPerPixel
    
    var byteArray = [UInt8](repeating: 0, count: byteCount)
    
    let region = MTLRegionMake2D(0, 0, width, height)
    byteArray.withUnsafeMutableBytes { pointer in
        texture.getBytes(
            pointer.baseAddress!,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )
    }
    
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        .union(.byteOrder32Little)
    
    var cgImage: CGImage?
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
    guard let image = cgImage else { return nil }
    
    return NSImage(cgImage: image, size: NSSize(width: width, height: height))
}

class EmulatorRunner: ObservableObject, @unchecked Sendable {
    @MainActor weak var metalView: MTKView?
    @MainActor @Published var currentFrameTexture: MTLTexture? = nil
    
    // MARK: - Save State
    @MainActor @Published var currentSlot: Int = 0
    @MainActor @Published var osdMessage: String?
    var undoBuffer: Data?
    
    /// Whether the current core supports save states
    var supportsSaveStates: Bool {
        LibretroBridge.serializeSize() > 0
    }
    
    internal var device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var emulationQueue = DispatchQueue(label: "truchiemu.emulation", qos: .userInteractive)
    internal var isRunning = false
    private var hasLoggedFrame = false
    private var runnerFrameCount = 0
    private var textureCache: MTLTexture? = nil
    private let textureLock = NSLock()
    @MainActor @Published var rom: ROM?
    var romPath: String = ""
    
    /// Expose saveManager for UI access
    var saveManager: SaveStateManager { _saveManager }
    private let _saveManager = SaveStateManager()
    /// Keyboard mapping snapshot captured at launch — safe to read from any thread.
    var cachedKeyboardMapping: KeyboardMapping = KeyboardMapping(buttons: [:])
    private var hookedController: GCController? = nil
    
    static func forSystem(_ systemID: String?) -> EmulatorRunner {
        switch systemID {
        case "nes":      return NESRunner()
        case "snes":     return SNESRunner()
        case "n64":      return N64Runner()
        case "dos":      return DOSRunner()
        case "scummvm":  return ScummVMRunner()
        default:         return EmulatorRunner()
        }
    }

    @MainActor
    func launch(rom: ROM, coreID: String) {
        guard let core = findCoreLib(coreID: coreID) else {
            print("[Runner] Core dylib not found: \(coreID)")
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
        let loggingEnabled = UserDefaults.standard.bool(forKey: "logging_enabled")
        let loggingLevel = UserDefaults.standard.integer(forKey: "logging_level")
        
        // Map logging level to core log level
        let selectedLogLevel: Int32
        if !loggingEnabled {
            selectedLogLevel = Int32(CoreLogLevel.none.rawValue)
        } else {
            switch loggingLevel {
            case 0: selectedLogLevel = Int32(CoreLogLevel.none.rawValue)
            case 1: selectedLogLevel = Int32(CoreLogLevel.info.rawValue)
            case 2: selectedLogLevel = Int32(CoreLogLevel.warn.rawValue)  // Most verbose available
            default: selectedLogLevel = Int32(CoreLogLevel.info.rawValue)
            }
        }
        
        if loggingEnabled {
            let levelName = loggingLevel == 0 ? "None" : loggingLevel == 1 ? "Info" : "Debug/Verbose"
            print("[Runner] Logging enabled at level: \(levelName)")
        }
        
        // Track last loaded core so Options view knows which file to persist to
        UserDefaults.standard.set(coreID, forKey: "lastLoadedCoreID")
        
        emulationQueue.async {
            LibretroBridge.setLanguage(Int32(selectedLang))
            LibretroBridge.setLogLevel(Int32(selectedLogLevel))
            LibretroBridge.launch(withDylibPath: core, romPath: rom.path.path,
                                  videoCallback: { [weak self] data, width, height, pitch, format in
                self?.updateFrame(data: data, width: Int(width), height: Int(height), pitch: Int(pitch), format: Int(format))
            }, coreID: coreID)
        }
    }

    // MARK: - Pause State
    @MainActor @Published var isPaused: Bool = false
    
    func stop() {
        print("[Runner] Stopping emulation thread...")
        isRunning = false
        LibretroBridge.stop()
        
        hookedController?.extendedGamepad?.valueChangedHandler = nil
        hookedController = nil
    }
    
    /// Toggle pause state
    @MainActor
    func togglePause() {
        isPaused.toggle()
        LibretroBridge.setPaused(isPaused)
        osdMessage = isPaused ? "Paused" : "Resumed"
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self.osdMessage = nil }
        }
    }
    
    /// Reload the current ROM
    @MainActor
    func reloadGame() {
        guard let gameRom = rom else { return }
        guard let sysID = gameRom.systemID else { return }
        
        // Store current core info
        let coreID = UserDefaults.standard.string(forKey: "lastLoadedCoreID") ?? ""
        
        // Reset pause state
        isPaused = false
        LibretroBridge.setPaused(false)
        
        // Stop current game
        stop()
        
        // Small delay to ensure cleanup
        Thread.sleep(forTimeInterval: 0.1)
        
        // Relaunch
        isRunning = true
        emulationQueue.async {
            LibretroBridge.launch(withDylibPath: self.findCoreLib(coreID: coreID) ?? coreID, 
                                  romPath: gameRom.path.path,
                                  videoCallback: { [weak self] data, width, height, pitch, format in
                self?.updateFrame(data: data, width: Int(width), height: Int(height), pitch: Int(pitch), format: Int(format))
            }, coreID: coreID)
        }
    }

    // MARK: - Slot-based Save State
    
    /// Compression preference
    var compressSaveStates: Bool {
        UserDefaults.standard.bool(forKey: "compress_save_states")
    }
    
    /// Save the current emulator state to the specified slot
    @MainActor
    func saveState(slot: Int) -> Bool {
        guard supportsSaveStates else {
            osdMessage = "Error: Core doesn't support save states"
            return false
        }
        
        guard let stateData = LibretroBridge.serializeState() else {
            osdMessage = "Error: Serialization failed"
            return false
        }
        
        guard let gameRom = rom else {
            osdMessage = "Error: No game loaded"
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
                print("[SaveState] Compressed: \(Int64(stateData.count).formattedByteSize) -> \(Int64(finalData.count).formattedByteSize) (\(Int(ratio))%)")
            } else {
                finalData = stateData
            }
            
            try finalData.write(to: stateURL, options: [.atomic])
            
            // Capture and save thumbnail if we have a current frame
            if let frameTex = currentFrameTexture {
                let nsImage = NSImageFromMTLTexture(frameTex)
                if let nsImage = nsImage {
                    saveManager.saveThumbnail(nsImage, gameName: gameRom.displayName, systemID: systemID, slot: slot)
                }
            }
            
            osdMessage = "Saved \(slot == -1 ? "Auto" : "Slot \(slot)")"
            
            // Clear OSD after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
            
            return true
        } catch {
            osdMessage = "Error: Could not write save state"
            return false
        }
    }
    
    /// Load an emulator state from the specified slot
    @MainActor
    func loadState(slot: Int) -> Bool {
        guard supportsSaveStates else {
            osdMessage = "Error: Core doesn't support save states"
            return false
        }
        
        guard let gameRom = rom else {
            osdMessage = "Error: No game loaded"
            return false
        }
        
        let systemID = gameRom.systemID ?? "default"
        let stateURL = saveManager.statePath(gameName: gameRom.displayName, systemID: systemID, slot: slot)
        
        // Save current state as undo buffer before loading
        undoBuffer = LibretroBridge.serializeState()
        
        guard let fileData = try? Data(contentsOf: stateURL) else {
            osdMessage = "Error: State file not found"
            return false
        }
        
        // Decompress if needed (handles both compressed and raw data)
        let actualData: Data
        if let decompressed = SaveStateManager.decompressStateData(fileData) {
            actualData = decompressed
        } else {
            osdMessage = "Error: State incompatible or corrupted"
            return false
        }
        
        let success = LibretroBridge.unserializeState(actualData)
        if success {
            osdMessage = "Loaded \(slot == -1 ? "Auto" : "Slot \(slot)")"
            
            // Clear OSD after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.osdMessage = nil }
            }
        } else {
            osdMessage = "Error: State incompatible or corrupted"
        }
        
        return success
    }
    
    /// Undo the last load operation (restore from undo buffer)
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
        
        let success = LibretroBridge.unserializeState(actualData)
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
    
    /// Cycle to the next save slot (0-9)
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
    
    /// Cycle to the previous save slot (0-9)
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
        LibretroBridge.setKeyState(Int32(retroID), pressed: pressed)
    }

    func findCoreLib(coreID: String) -> String? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("TruchieEmu/Cores/\(coreID)")
        guard let versionDirs = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil),
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrameTexture = tex
            self.metalView?.needsDisplay = true
            
            if !self.hasLoggedFrame {
                print("[Runner] UI ACTIVATED with first frame (\(width)x\(height))")
                self.hasLoggedFrame = true
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
                return Int(button.retroID)
            }
        }
        return nil
    }

    @MainActor
    func setupGamepadInput() {
        let activeIdx = ControllerService.shared.activePlayerIndex
        if activeIdx == 0 { return } // Keyboard
        
        guard let player = ControllerService.shared.connectedControllers.first(where: { $0.playerIndex == activeIdx }),
              let controller = player.gcController else { return }
        
        let sysID = rom?.systemID ?? "default"
        let mapping = ControllerService.shared.mapping(for: controller.vendorName ?? "Unknown", systemID: sysID)
        
        print("[Runner] Hooking gamepad: \(controller.vendorName ?? "Unknown") for system: \(sysID)")
        self.hookedController = controller
        
        controller.extendedGamepad?.valueChangedHandler = { [weak self] _, element in
            guard let self = self else { return }
            
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

    private func updateGamepadButton(_ element: GCControllerElement, in mapping: ControllerMapping) {
        let name = element.localizedName ?? ""
        for (btn, btnMapping) in mapping.buttons {
            if btnMapping.gcElementName == name {
                if let info = btn.analogInfo {
                    // Handle Analog/Pseudo-Analog
                    var val: Int32 = 0
                    if let stick = element as? GCControllerDirectionPad {
                        let axisVal = (info.id == 0) ? stick.xAxis.value : stick.yAxis.value
                        val = Int32(axisVal * info.sign * 32767)
                    } else if let btnElement = element as? GCControllerButtonInput {
                        val = btnElement.isPressed ? Int32(info.sign * 32767) : 0
                    } else if let axisElement = element as? GCControllerAxisInput {
                        val = Int32(axisElement.value * info.sign * 32767)
                    }
                    LibretroBridge.setAnalogState(info.index, id: info.id, value: val)
                } else {
                    // Handle Digital
                    let retroID = btn.retroID
                    if let btnElement = element as? GCControllerButtonInput {
                        self.setKeyState(retroID: Int(retroID), pressed: btnElement.isPressed)
                    } else if let axisElement = element as? GCControllerAxisInput {
                        self.setKeyState(retroID: Int(retroID), pressed: abs(axisElement.value) > 0.5)
                    }
                }
            }
        }
    }
}

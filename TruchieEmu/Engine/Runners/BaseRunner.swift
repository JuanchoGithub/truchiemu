import MetalKit
import Foundation
import SwiftUI
import GameController

class EmulatorRunner: ObservableObject, @unchecked Sendable {
    @MainActor weak var metalView: MTKView?
    @MainActor @Published var currentFrameTexture: MTLTexture? = nil
    
    internal var device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var emulationQueue = DispatchQueue(label: "truchiemu.emulation", qos: .userInteractive)
    internal var isRunning = false
    private var hasLoggedFrame = false
    private var runnerFrameCount = 0
    private var textureCache: MTLTexture? = nil
    private let textureLock = NSLock()
    var rom: ROM?
    var romPath: String = ""
    /// Keyboard mapping snapshot captured at launch — safe to read from any thread.
    var cachedKeyboardMapping: KeyboardMapping = KeyboardMapping(buttons: [:])
    private var hookedController: GCController? = nil
    
    static func forSystem(_ systemID: String?) -> EmulatorRunner {
        switch systemID {
        case "nes":  return NESRunner()
        case "snes": return SNESRunner()
        case "n64":  return N64Runner()
        default:     return EmulatorRunner()
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
        let selectedLogLevel = loggingEnabled ? SystemPreferences.shared.coreLogLevel.rawValue : CoreLogLevel.none.rawValue
        
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

    func stop() {
        print("[Runner] Stopping emulation thread...")
        isRunning = false
        LibretroBridge.stop()
        
        hookedController?.extendedGamepad?.valueChangedHandler = nil
        hookedController = nil
    }

    func saveState() {
        LibretroBridge.saveState()
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

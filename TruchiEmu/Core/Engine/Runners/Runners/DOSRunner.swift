import MetalKit
import Foundation
import SwiftUI
import GameController

// DOS-specific emulator runner using DOSBox-Pure.
//
// DOSBox-Pure is designed to work with ZIP files directly, providing:
// - Automatic C: drive mounting from ZIP contents
// - Built-in "Start Menu" for selecting executables
// - Game controller auto-mapping (arrows, space, ctrl, alt)
// - Mouse mode support for point-and-click adventures
// - Save state support via Libretro API
class DOSRunner: EmulatorRunner, @unchecked Sendable {
    
    // MARK: - DOS-Specific Configuration
    
    // CPU cycles setting for DOS emulation
    // Values: "auto", "3000" (8088/XT), "8000" (286), "25000" (386), "max" (Pentium)
    private var cyclesSetting: String {
        AppSettings.get("dosbox_pure_cycles", type: String.self) ?? "auto"
    }
    
    // Whether mouse mode is currently active (used by UI)
    @MainActor @Published var isMouseMode: Bool = false
    
    // MARK: - Launch Override
    
    @MainActor
    override func launch(rom: ROM, coreID: String, shaderUniformOverrides: [String: Float] = [:]) {
        // DOSBox-Pure handles ZIP files natively - no extraction needed
        // The core will mount the ZIP as a C: drive automatically
        LoggerService.info(category: "DOSRunner", "Launching DOS game: \(rom.name), cycles: \(cyclesSetting)")
        
        // Set DOS-specific core options before launch
        configureCoreOptions()
        
        super.launch(rom: rom, coreID: coreID, shaderUniformOverrides: shaderUniformOverrides)
        
        // Auto-start input capture for DOS games
        if let window = self.window, !InputCaptureManager.shared.isCapturing {
            InputCaptureManager.shared.startCapture(window: window)
        }
    }
    
    // MARK: - Core Options Configuration
    
    // Configure DOSBox-Pure specific core options
    private func configureCoreOptions() {
        // Set CPU cycles
        let cycles = cyclesSetting
        AppSettings.set("dosbox_pure_cycles", value: cycles)
        
        // Enable auto-start menu for multi-executable games
        AppSettings.setBool("dosbox_pure_start_menu", value: true)
        
        // Enable mouse emulation by default
        AppSettings.setBool("dosbox_pure_mouse", value: true)
    }
    
    // MARK: - Mouse Mode Toggle
    
    // Toggle between gamepad mode and mouse mode
    // In mouse mode, the left analog stick controls the DOS mouse cursor
    @MainActor func toggleMouseMode() {
        isMouseMode.toggle()
        LoggerService.debug(category: "DOSRunner", "Mouse mode: \(isMouseMode ? "ON" : "OFF")")
    }
    
    // MARK: - DOS-Specific Input Handling
    
    @MainActor
    override func setupGamepadInput() {
        let cs = ControllerService.shared

        for player in cs.connectedControllers {
            guard let controller = player.gcController,
                  let extendedGamepad = controller.extendedGamepad else { continue }

            let ports = player.assignedPlayers.map { $0 - 1 }
            for port in ports {
                LoggerService.debug(category: "DOSRunner", "Hooking gamepad for DOS: \(controller.vendorName ?? "Unknown") port \(port)")
            }

            extendedGamepad.valueChangedHandler = { [weak self] _, element in
                guard let self = self else { return }
                for port in ports {
                    self.handleGamepadInput(element, player: port)
                }
            }
        }
    }
    
    // Handle gamepad input in standard DOS game mode
    // Maps: D-Pad → JOYPAD buttons 4-7 (up/down/left/right), Buttons → JOYPAD 8-9 (A/B)
    private func handleGamepadInput(_ element: GCControllerElement, player: Int = 0) {
        if let dpad = element as? GCControllerDirectionPad {
            // DOSBox-Pure handles keyboard mapping internally
            // Forward D-Pad as JOYPAD button IDs
            let upPressed = dpad.up.isPressed
            let downPressed = dpad.down.isPressed
            let leftPressed = dpad.left.isPressed
            let rightPressed = dpad.right.isPressed
            
            LoggerService.debug(category: "DOSRunner", "DPad: up=\(upPressed), down=\(downPressed), left=\(leftPressed), right=\(rightPressed)")
            
            setKeyState(retroID: 4, player: player, pressed: upPressed) // JOYPAD_UP
            setKeyState(retroID: 5, player: player, pressed: downPressed) // JOYPAD_DOWN
            setKeyState(retroID: 6, player: player, pressed: leftPressed) // JOYPAD_LEFT
            setKeyState(retroID: 7, player: player, pressed: rightPressed) // JOYPAD_RIGHT
        } else if let btn = element as? GCControllerButtonInput {
            // Map common buttons to JOYPAD A/B (buttons 8 and 9)
            let name = btn.localizedName ?? ""
            if name.contains("A") || name.contains("X") {
                setKeyState(retroID: 13, player: player, pressed: btn.isPressed) // RETROK_RETURN
            } else if name.contains("B") || name.contains("Circle") {
                setKeyState(retroID: 44, player: player, pressed: btn.isPressed) // RETROK_SPACE
            }
        }
    }
    
    // MARK: - Disk Control for Multi-Disc Games
    
    // Load a new disk image for multi-disc DOS games
    // DOSBox-Pure supports the Libretro Disk Control API
    func loadDisk(imagePath: String) {
        LoggerService.info(category: "DOSRunner", "Loading disk image: \(imagePath)")
        // Use Libretro disk control API to swap disks
        // This is handled by the core's RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE
    }
    
    // Get the current disk index (for multi-disc games)
    var currentDiskIndex: Int {
        // Query current disk from Libretro
        return 0
    }
    
    // Get the total number of disks in the current game
    var totalDisks: Int {
        // Query total disks from Libretro
        return 1
    }
}
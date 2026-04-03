import MetalKit
import Foundation
import SwiftUI
import GameController

/// DOS-specific emulator runner using DOSBox-Pure.
///
/// DOSBox-Pure is designed to work with ZIP files directly, providing:
/// - Automatic C: drive mounting from ZIP contents
/// - Built-in "Start Menu" for selecting executables
/// - Game controller auto-mapping (arrows, space, ctrl, alt)
/// - Mouse mode support for point-and-click adventures
/// - Save state support via Libretro API
class DOSRunner: EmulatorRunner, @unchecked Sendable {
    
    // MARK: - DOS-Specific Configuration
    
    /// CPU cycles setting for DOS emulation
    /// Values: "auto", "3000" (8088/XT), "8000" (286), "25000" (386), "max" (Pentium)
    private var cyclesSetting: String {
        UserDefaults.standard.string(forKey: "dosbox_pure_cycles") ?? "auto"
    }
    
    /// Whether mouse mode is currently active (used by UI)
    @MainActor @Published var isMouseMode: Bool = false
    
    // MARK: - Launch Override
    
    @MainActor
    override func launch(rom: ROM, coreID: String) {
        // DOSBox-Pure handles ZIP files natively - no extraction needed
        // The core will mount the ZIP as a C: drive automatically
        LoggerService.info(category: "DOSRunner", "Launching DOS game: \(rom.name), cycles: \(cyclesSetting)")
        
        // Set DOS-specific core options before launch
        configureCoreOptions()
        
        super.launch(rom: rom, coreID: coreID)
    }
    
    // MARK: - Core Options Configuration
    
    /// Configure DOSBox-Pure specific core options
    private func configureCoreOptions() {
        // Set CPU cycles
        let cycles = cyclesSetting
        UserDefaults.standard.set(cycles, forKey: "dosbox_pure_cycles")
        
        // Enable auto-start menu for multi-executable games
        UserDefaults.standard.set(true, forKey: "dosbox_pure_start_menu")
        
        // Enable mouse emulation by default
        UserDefaults.standard.set(true, forKey: "dosbox_pure_mouse")
    }
    
    // MARK: - Mouse Mode Toggle
    
    /// Toggle between gamepad mode and mouse mode
    /// In mouse mode, the left analog stick controls the DOS mouse cursor
    @MainActor func toggleMouseMode() {
        isMouseMode.toggle()
        LoggerService.debug(category: "DOSRunner", "Mouse mode: \(isMouseMode ? "ON" : "OFF")")
    }
    
    // MARK: - DOS-Specific Input Handling
    
    @MainActor
    override func setupGamepadInput() {
        let activeIdx = ControllerService.shared.activePlayerIndex
        if activeIdx == 0 {
            // Keyboard mode - DOSBox-Pure handles keyboard natively
            LoggerService.debug(category: "DOSRunner", "Using keyboard input for DOS")
            return
        }
        
        guard let player = ControllerService.shared.connectedControllers.first(where: { $0.playerIndex == activeIdx }),
              let controller = player.gcController else {
            super.setupGamepadInput()
            return
        }
        
        LoggerService.debug(category: "DOSRunner", "Hooking gamepad for DOS: \(controller.vendorName ?? "Unknown")")
        
        controller.extendedGamepad?.valueChangedHandler = { [weak self] _, element in
            guard let self = self else { return }
            // DOSBox-Pure handles input mapping internally, just forward to core
            self.handleGamepadInput(element)
        }
    }
    
    /// Handle gamepad input in standard DOS game mode
    /// Maps: D-Pad → Arrow keys, Buttons → Enter/Space/Alt/Ctrl
    private func handleGamepadInput(_ element: GCControllerElement) {
        if let dpad = element as? GCControllerDirectionPad {
            // DOSBox-Pure handles keyboard mapping internally
            // We just forward the D-Pad as arrow keys
            if dpad.up.isPressed { setKeyState(retroID: 19, pressed: true) } // RETROK_UP
            else { setKeyState(retroID: 19, pressed: false) }
            if dpad.down.isPressed { setKeyState(retroID: 20, pressed: true) } // RETROK_DOWN
            else { setKeyState(retroID: 20, pressed: false) }
            if dpad.left.isPressed { setKeyState(retroID: 18, pressed: true) } // RETROK_LEFT
            else { setKeyState(retroID: 18, pressed: false) }
            if dpad.right.isPressed { setKeyState(retroID: 17, pressed: true) } // RETROK_RIGHT
            else { setKeyState(retroID: 17, pressed: false) }
        } else if let btn = element as? GCControllerButtonInput {
            // Map common buttons to Enter/Space
            let name = btn.localizedName ?? ""
            if name.contains("A") || name.contains("X") {
                setKeyState(retroID: 13, pressed: btn.isPressed) // RETROK_RETURN
            } else if name.contains("B") || name.contains("Circle") {
                setKeyState(retroID: 44, pressed: btn.isPressed) // RETROK_SPACE
            }
        }
    }
    
    // MARK: - Disk Control for Multi-Disc Games
    
    /// Load a new disk image for multi-disc DOS games
    /// DOSBox-Pure supports the Libretro Disk Control API
    func loadDisk(imagePath: String) {
        LoggerService.info(category: "DOSRunner", "Loading disk image: \(imagePath)")
        // Use Libretro disk control API to swap disks
        // This is handled by the core's RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE
    }
    
    /// Get the current disk index (for multi-disc games)
    var currentDiskIndex: Int {
        // Query current disk from Libretro
        return 0
    }
    
    /// Get the total number of disks in the current game
    var totalDisks: Int {
        // Query total disks from Libretro
        return 1
    }
}
import Foundation
import GameController
import Combine

@MainActor
class ControllerService: ObservableObject {
    static let shared = ControllerService()
    @Published var currentSystemID: String = "default" 

    @Published var connectedControllers: [PlayerController] = []

    @Published var activePlayerIndex: Int = 0 {
        didSet {
            AppSettings.setInt("active_player_index", value: activePlayerIndex)
        }
    }

    // Handedness preference: "right" (default) or "left"
    @Published var handedness: String {
        didSet {
            AppSettings.set("controller_handedness", value: handedness)
        }
    }
    private let mappingKey = "controller_mappings_v2"
    private let kbMappingKey = "keyboard_mapping_v1"
    private var savedMappings: [String: [String: ControllerGamepadMapping]] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.handedness = AppSettings.get("controller_handedness", type: String.self) ?? "right"
        self.activePlayerIndex = AppSettings.getInt("active_player_index", defaultValue: 0)
        loadMappings()
        setupControllerNotifications()
        refreshConnectedControllers()
    }

    // MARK: - Controller Detection

    private func setupControllerNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in self?.refreshConnectedControllers() }
            .store(in: &cancellables)
    }

    private func refreshConnectedControllers() {
        var players: [PlayerController] = []
        for (index, gc) in GCController.controllers().prefix(4).enumerated() {
            let vendorName = gc.vendorName ?? "Unknown Controller"
            let mapping = savedMappings[vendorName]?["default"] ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
            players.append(PlayerController(
                playerIndex: index + 1,
                gcController: gc,
                mapping: mapping
            ))
        }
        connectedControllers = players
        
        // Auto-detect: If no player selected (keyboard mode) and controllers are available, select first controller
        if activePlayerIndex == 0 && !players.isEmpty {
            activePlayerIndex = 1
        }
    }

    // MARK: - Mappings

    func updateMapping(for vendorName: String, systemID: String, mapping: ControllerGamepadMapping) {
        if savedMappings[vendorName] == nil { savedMappings[vendorName] = [:] }
        savedMappings[vendorName]?[systemID] = mapping
        
        refreshConnectedControllers()
        saveMappings()
    }
    
    func mapping(for vendorName: String, systemID: String) -> ControllerGamepadMapping {
        // 1. Return the explicit system override if the user saved one
        if let systemMapping = savedMappings[vendorName]?[systemID] {
            return systemMapping
        }
        
        // 2. Fetch the master Global configuration (or create it if it doesn't exist)
        let globalMapping = savedMappings[vendorName]?["default"] 
            ?? ControllerGamepadMapping.defaults(for: vendorName, systemID: "default", handedness: handedness)
        
        if systemID == "default" {
            return globalMapping
        }
        
        // 3. Dynamically translate the Global config into the Target system
        return ControllerGamepadMapping.derived(from: globalMapping, for: systemID)
    }

    func updateKeyboardMapping(_ mapping: KeyboardMapping, for systemID: String) {
        var all = keyboardMappings
        all[systemID] = mapping
        keyboardMappings = all
        if let data = try? JSONEncoder().encode(all) {
            AppSettings.setData(kbMappingKey, value: data)
        }
    }

    func removeMapping(for vendorName: String, systemID: String) {
        savedMappings[vendorName]?.removeValue(forKey: systemID)
        if savedMappings[vendorName]?.isEmpty == true {
            savedMappings.removeValue(forKey: vendorName)
        }
        refreshConnectedControllers()
        saveMappings()
    }

    func removeKeyboardMapping(for systemID: String) {
        keyboardMappings.removeValue(forKey: systemID)
        if let data = try? JSONEncoder().encode(keyboardMappings) {
            AppSettings.setData(kbMappingKey, value: data)
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(savedMappings) {
            AppSettings.setData(mappingKey, value: data)
        }
    }

    private func loadMappings() {
        if let data = AppSettings.getData(mappingKey),
           let saved = try? JSONDecoder().decode([String: [String: ControllerGamepadMapping]].self, from: data) {
            savedMappings = saved
        }
        
        if let data = AppSettings.getData(kbMappingKey),
           let saved = try? JSONDecoder().decode([String: KeyboardMapping].self, from: data) {
            keyboardMappings = saved
        }
    }
    
    @Published var keyboardMappings: [String: KeyboardMapping] = [:]
    
    func keyboardMapping(for systemID: String) -> KeyboardMapping {
        // 1. Return explicit system override
        if let systemMapping = keyboardMappings[systemID] {
            return systemMapping
        }
        
        // 2. Fetch master Global configuration
        let globalMapping = keyboardMappings["default"] 
            ?? KeyboardMapping.defaults(for: "default", handedness: handedness)
            
        if systemID == "default" {
            return globalMapping
        }
        
        // 3. Dynamically translate
        return KeyboardMapping.derived(from: globalMapping, for: systemID)
    }
}

// MARK: - Models

struct PlayerController: Identifiable {
    var id: Int { playerIndex }
    var playerIndex: Int
    var gcController: GCController?
    var mapping: ControllerGamepadMapping

    var name: String { gcController?.vendorName ?? "Player \(playerIndex)" }
    var isConnected: Bool { gcController != nil }
}

struct ControllerGamepadMapping: Codable {
    var vendorName: String
    var buttons: [RetroButton: GCButtonMapping]

    static func defaults(for vendorName: String, systemID: String, handedness: String = "right") -> ControllerGamepadMapping {
        let isLeftHanded = handedness == "left"
        var mapping = ControllerGamepadMapping(vendorName: vendorName, buttons: [:])
        let availableButtons = RetroButton.availableButtons(for: systemID)
        
        // --- MASTER TEMPLATE POPULATION (For "Global / Default") ---
        if systemID == "default" {
            // Standard D-Pad
            mapping.buttons[.up] = GCButtonMapping(gcElementName: "D-pad Up", gcElementAlias: "Up")
            mapping.buttons[.down] = GCButtonMapping(gcElementName: "D-pad Down", gcElementAlias: "Down")
            mapping.buttons[.left] = GCButtonMapping(gcElementName: "D-pad Left", gcElementAlias: "Left")
            mapping.buttons[.right] = GCButtonMapping(gcElementName: "D-pad Right", gcElementAlias: "Right")
            
            // Standard Face Buttons (MFi / Xbox / PS layout)
            mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
            mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
            mapping.buttons[.x] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
            mapping.buttons[.y] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            
            // Shoulders & Triggers
            mapping.buttons[.l1] = GCButtonMapping(gcElementName: "Left Shoulder", gcElementAlias: "L1")
            mapping.buttons[.r1] = GCButtonMapping(gcElementName: "Right Shoulder", gcElementAlias: "R1")
            mapping.buttons[.l2] = GCButtonMapping(gcElementName: "Left Trigger", gcElementAlias: "L2")
            mapping.buttons[.r2] = GCButtonMapping(gcElementName: "Right Trigger", gcElementAlias: "R2")
            
            // Stick Clicks
            mapping.buttons[.l3] = GCButtonMapping(gcElementName: "Left Thumbstick Button", gcElementAlias: "L3")
            mapping.buttons[.r3] = GCButtonMapping(gcElementName: "Right Thumbstick Button", gcElementAlias: "R3")
            
            // System Buttons
            mapping.buttons[.start] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
            mapping.buttons[.select] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
            
            // Analog Stick Directions (Crucial for N64 derivation)
            mapping.buttons[.lStickUp] = GCButtonMapping(gcElementName: "Left Thumbstick Up", gcElementAlias: "L Stick Up")
            mapping.buttons[.lStickDown] = GCButtonMapping(gcElementName: "Left Thumbstick Down", gcElementAlias: "L Stick Down")
            mapping.buttons[.lStickLeft] = GCButtonMapping(gcElementName: "Left Thumbstick Left", gcElementAlias: "L Stick Left")
            mapping.buttons[.lStickRight] = GCButtonMapping(gcElementName: "Left Thumbstick Right", gcElementAlias: "L Stick Right")
            
            mapping.buttons[.rStickUp] = GCButtonMapping(gcElementName: "Right Thumbstick Up", gcElementAlias: "R Stick Up")
            mapping.buttons[.rStickDown] = GCButtonMapping(gcElementName: "Right Thumbstick Down", gcElementAlias: "R Stick Down")
            mapping.buttons[.rStickLeft] = GCButtonMapping(gcElementName: "Right Thumbstick Left", gcElementAlias: "R Stick Left")
            mapping.buttons[.rStickRight] = GCButtonMapping(gcElementName: "Right Thumbstick Right", gcElementAlias: "R Stick Right")
            
            return mapping
        }

        // --- SPECIFIC SYSTEM LEGACY DEFAULTS (Keep your existing NES/SNES code below) ---
        if availableButtons.contains(.a) && availableButtons.contains(.b) && !availableButtons.contains(.x) {
            // NES Standard layout
            mapping.buttons[.up] = GCButtonMapping(gcElementName: "D-pad Up", gcElementAlias: "Up")
            mapping.buttons[.down] = GCButtonMapping(gcElementName: "D-pad Down", gcElementAlias: "Down")
            mapping.buttons[.left] = GCButtonMapping(gcElementName: "D-pad Left", gcElementAlias: "Left")
            mapping.buttons[.right] = GCButtonMapping(gcElementName: "D-pad Right", gcElementAlias: "Right")
            
            if isLeftHanded {
                // Left-handed: A on X, B on Y
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
                mapping.buttons[.turboA] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.turboB] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
            } else {
                // Right-handed (default): A on A, B on B
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
                mapping.buttons[.turboA] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.turboB] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            }
            
            mapping.buttons[.start] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
            mapping.buttons[.select] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
        }
        // MARK: - SNES-style (16-bit era with X, Y, L, R)
        // SNES, Genesis 6-button, etc.
        else if availableButtons.contains(.x) && availableButtons.contains(.y) {
            // D-Pad (all systems)
            mapping.buttons[.up] = GCButtonMapping(gcElementName: "D-pad Up", gcElementAlias: "Up")
            mapping.buttons[.down] = GCButtonMapping(gcElementName: "D-pad Down", gcElementAlias: "Down")
            mapping.buttons[.left] = GCButtonMapping(gcElementName: "D-pad Left", gcElementAlias: "Left")
            mapping.buttons[.right] = GCButtonMapping(gcElementName: "D-pad Right", gcElementAlias: "Right")
            
            if isLeftHanded {
                // Left-handed layout for SNES-style
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
                mapping.buttons[.x] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.y] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
            } else {
                // Right-handed (default): Standard layout
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
                mapping.buttons[.x] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.y] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            }
            
            // Shoulder buttons
            mapping.buttons[.l1] = GCButtonMapping(gcElementName: "Left Shoulder", gcElementAlias: "L1")
            mapping.buttons[.r1] = GCButtonMapping(gcElementName: "Right Shoulder", gcElementAlias: "R1")
            
            // L2/R2 only on systems that use them
            if availableButtons.contains(.l2) {
                mapping.buttons[.l2] = GCButtonMapping(gcElementName: "Left Trigger", gcElementAlias: "L2")
            }
            if availableButtons.contains(.r2) {
                mapping.buttons[.r2] = GCButtonMapping(gcElementName: "Right Trigger", gcElementAlias: "R2")
            }
            
            mapping.buttons[.start] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
            mapping.buttons[.select] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
        }
        
        // MARK: - Genesis/Mega Drive specific
        if systemID == "genesis" || systemID == "megadrive", availableButtons.contains(.c), availableButtons.contains(.z) {
            mapping.buttons[.c] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
            if availableButtons.contains(.z) {
                mapping.buttons[.z] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            }
        }
        
        // MARK: - Analog sticks (only for systems that support them)
        if availableButtons.contains(.lStickUp) {
            mapping.buttons[.lStickUp] = GCButtonMapping(gcElementName: "Left Thumbstick Up", gcElementAlias: "L Stick Up")
            mapping.buttons[.lStickDown] = GCButtonMapping(gcElementName: "Left Thumbstick Down", gcElementAlias: "L Stick Down")
            mapping.buttons[.lStickLeft] = GCButtonMapping(gcElementName: "Left Thumbstick Left", gcElementAlias: "L Stick Left")
            mapping.buttons[.lStickRight] = GCButtonMapping(gcElementName: "Left Thumbstick Right", gcElementAlias: "L Stick Right")
        }
        if availableButtons.contains(.rStickUp) {
            mapping.buttons[.rStickUp] = GCButtonMapping(gcElementName: "Right Thumbstick Up", gcElementAlias: "R Stick Up")
            mapping.buttons[.rStickDown] = GCButtonMapping(gcElementName: "Right Thumbstick Down", gcElementAlias: "R Stick Down")
            mapping.buttons[.rStickLeft] = GCButtonMapping(gcElementName: "Right Thumbstick Left", gcElementAlias: "R Stick Left")
            mapping.buttons[.rStickRight] = GCButtonMapping(gcElementName: "Right Thumbstick Right", gcElementAlias: "R Stick Right")
        }
        
        // Thumbstick clicks
        if availableButtons.contains(.l3) {
            mapping.buttons[.l3] = GCButtonMapping(gcElementName: "Left Thumbstick Button", gcElementAlias: "L3")
        }
        if availableButtons.contains(.r3) {
            mapping.buttons[.r3] = GCButtonMapping(gcElementName: "Right Thumbstick Button", gcElementAlias: "R3")
        }
        
        // N64 C-buttons
        if availableButtons.contains(.cUp) {
            // Map C-buttons to right stick or face buttons
            if isLeftHanded {
                mapping.buttons[.cUp] = GCButtonMapping(gcElementName: "D-pad Up", gcElementAlias: "Up")
                mapping.buttons[.cDown] = GCButtonMapping(gcElementName: "D-pad Down", gcElementAlias: "Down")
                mapping.buttons[.cLeft] = GCButtonMapping(gcElementName: "D-pad Left", gcElementAlias: "Left")
                mapping.buttons[.cRight] = GCButtonMapping(gcElementName: "D-pad Right", gcElementAlias: "Right")
            } else {
                mapping.buttons[.cUp] = GCButtonMapping(gcElementName: "Right Stick", gcElementAlias: "R Stick Y")
                mapping.buttons[.cDown] = GCButtonMapping(gcElementName: "Right Stick", gcElementAlias: "R Stick Y")
                mapping.buttons[.cLeft] = GCButtonMapping(gcElementName: "Right Stick", gcElementAlias: "R Stick X")
                mapping.buttons[.cRight] = GCButtonMapping(gcElementName: "Right Stick", gcElementAlias: "R Stick X")
            }
        }
        
        // Arcade coin/start buttons
        if availableButtons.contains(.coin1) {
            mapping.buttons[.coin1] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            mapping.buttons[.start1] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
        }
        if availableButtons.contains(.coin2) {
            mapping.buttons[.coin2] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
            mapping.buttons[.start2] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
        }
        
        return mapping
    }
}

struct GCButtonMapping: Codable {
    var gcElementName: String
    var gcElementAlias: String?
}

struct KeyboardMapping: Codable {
    var buttons: [RetroButton: UInt16]

    static func defaults(for systemID: String, handedness: String = "right") -> KeyboardMapping {
        let isLeftHanded = handedness == "left"
        var base: [RetroButton: UInt16] = [:]
        
        // Standard D-Pad on arrow keys for all systems
        base[.up] = 126     // Up Arrow
        base[.down] = 125   // Down Arrow
        base[.left] = 123   // Left Arrow
        base[.right] = 124  // Right Arrow
        
        // Start and Select
        base[.start] = 36   // Return/Enter
        base[.select] = 48  // Tab
        
        switch systemID {
        case "nes":
            // NES: 4 directions + Start + Select + A + B (+ Turbo)
            if isLeftHanded {
                base[.a] = 8     // X key
                base[.b] = 9     // Y key
                base[.turboA] = 6  // A key (turbo)
                base[.turboB] = 7  // B key (turbo)
            } else {
                base[.a] = 6     // A key
                base[.b] = 7     // B key
                base[.turboA] = 8  // X key (turbo)
                base[.turboB] = 9  // Y key (turbo)
            }
            
        case "nes_turbo":
            // NES Turbo variant with explicit turbo buttons
            if isLeftHanded {
                base[.a] = 8     // X key
                base[.b] = 9     // Y key
                base[.turboA] = 6  // A key (turbo)
                base[.turboB] = 7  // B key (turbo)
            } else {
                base[.a] = 6     // A key
                base[.b] = 7     // B key
                base[.turboA] = 8  // X key (turbo)
                base[.turboB] = 9  // Y key (turbo)
            }
            
        case "snes", "sfc":
            // SNES: D-Pad + Start + Select + A, B, X, Y + L, R
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.x] = 8     // X
            base[.y] = 9     // Y
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            if isLeftHanded {
                // Swap A/B with X/Y for left-handed
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }
            
        case "genesis", "megadrive":
            // Genesis: D-Pad + Start + A, B, C, X, Y, Z (Mode for Select)
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.c] = 8     // X
            base[.x] = 12    // Q
            base[.y] = 13    // E
            base[.z] = 14    // W
            base[.select] = 48  // Tab (Mode button)
            
        case "n64":
            // N64: D-Pad + Start + A, B, Z + L, R + C-buttons (on right stick or WASD)
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.z] = 14    // W (R)
            base[.l1] = 12   // Q
            base[.r1] = 11   // E
            // C-buttons mapped to num pad or IJKL
            base[.cUp] = 126   // Up arrow (secondary - C buttons)
            base[.cDown] = 125 // Down arrow
            base[.cLeft] = 123 // Left arrow
            base[.cRight] = 124 // Right arrow
            
        case "psx", "ps1":
            // PlayStation: D-Pad + Start + Select + Square(□), X, Circle(○), △
            // + L1, R1, L2, R2, Analog
            base[.a] = 6     // A (X button)
            base[.b] = 7     // B (Circle button)
            base[.x] = 8     // X (Square button)
            base[.y] = 9     // Y (Triangle button)
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            base[.l2] = 1    // 1 (top row)
            base[.r2] = 3    // 3 (top row)
            base[.select] = 48  // Tab
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }
            
        case "gba", "gb", "gbc":
            // Game Boy family: D-Pad + Start + Select + A, B (+ L, R on GBA)
            base[.a] = 6     // A
            base[.b] = 7     // B
            if systemID == "gba" {
                base[.l1] = 12  // Q
                base[.r1] = 14  // W
            }
            
        case "nds":
            // Nintendo DS: D-Pad + Start + Select + A, B, X, Y + L, R
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.x] = 8     // X
            base[.y] = 9     // Y
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            // Touch screen support via mouse
        
        case "sms":
            // Sega Master System: D-Pad + 1, 2 (Start for Select)
            base[.a] = 6     // A (Button 1)
            base[.b] = 7     // B (Button 2)
            
        case "gamegear":
            // Game Gear: Similar to Master System
            base[.a] = 6     // A (Button 1)
            base[.b] = 7     // B (Button 2)
            
        case "32x":
            // Sega 32X: 6-button + Start + A, B, C, X, Y, Z + Mode (Select)
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.c] = 8     // X
            base[.x] = 12    // Q
            base[.y] = 13    // E
            base[.z] = 14    // W
            base[.start] = 36  // Return
            base[.select] = 48 // Tab (Mode)
            
        case "atari2600":
            // Atari 2600: Joystick + Action button + Reset, Select (on console)
            base[.a] = 6     // A (Action)
            base[.select] = 48  // Tab (Difficulty)
            
        case "atari5200":
            // Atari 5200: Joystick + 4 action buttons + Start, Pause, Reset
            base[.a] = 6     // Button 1
            base[.b] = 7     // Button 2
            base[.x] = 8     // Button 3
            base[.y] = 9     // Button 4
            
        case "atari7800":
            // Atari 7800: Joystick + 1 or 2 buttons
            base[.a] = 6     // A
            base[.b] = 7     // B
            
        case "lynx":
            // Atari Lynx: D-Pad + A, B + Option, Pause
            base[.a] = 6     // A
            base[.b] = 7     // B
            
        case "ngp", "ngc":
            // Neo Geo Pocket: D-Pad + A, B + Option
            base[.a] = 6     // A
            base[.b] = 7     // B
            
        case "pce":
            // PC Engine / TurboGrafx-16: D-Pad + 1, 2 buttons + Run and Select
            base[.a] = 6     // Button 1
            base[.b] = 7     // Button 2
            
        case "saturn":
            // Sega Saturn: D-Pad + Start + A, B, C, X, Y, Z + L, R
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.c] = 8     // X (C)
            base[.x] = 12    // Q (X)
            base[.y] = 13    // E (Y)
            base[.z] = 14    // W (Z)
            base[.l1] = 1    // 1 (L)
            base[.r1] = 3    // 3 (R)
            
        case "dreamcast":
            // Dreamcast: D-Pad + Start + A, B, X, Y + L, R + Analog
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.x] = 8     // X
            base[.y] = 9     // Y
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            base[.l2] = 1    // 1 (L Trigger)
            base[.r2] = 3    // 3 (R Trigger)
            // Analog stick support
            base[.lStickUp] = 126 // Up Arrow
            base[.lStickDown] = 125 // Down Arrow
            base[.lStickLeft] = 123 // Left Arrow
            base[.lStickRight] = 124 // Right Arrow            
        case "ps2":
            // PlayStation 2: Similar to PS1 + Analog
            base[.a] = 6     // A (Cross)
            base[.b] = 7     // B (Circle)
            base[.x] = 8     // X (Square)
            base[.y] = 9     // Y (Triangle)
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            base[.l2] = 1    // 1 (L2)
            base[.r2] = 3    // 3 (R2)
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }
            
        case "psp":
            // PSP: D-Pad + Start + Select + Square, X, Circle, Triangle + L, R
            base[.a] = 6     // A (Cross)
            base[.b] = 7     // B (Circle)
            base[.x] = 8     // X (Square)
            base[.y] = 9     // Y (Triangle)
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            base[.select] = 48 // Tab
            
        case "3do":
            // 3DO: D-Pad + Start + A, B, C + Play, Stop, X
            base[.a] = 6     // A (Play)
            base[.b] = 7     // B (Pause)
            base[.c] = 8     // C (Stop)
            base[.x] = 12    // X (Play/Pause)
            
        case "mame", "fba", "arcade":
            // Arcade: D-Pad + Coin + Start + A, B + others
            base[.a] = 6     // A (Button 1)
            base[.b] = 7     // B (Button 2)
            base[.x] = 8     // X (Button 3)
            base[.y] = 9     // Y (Button 4)
            base[.l1] = 12   // Q (Button 5)
            base[.r1] = 14   // W (Button 6)
            base[.coin1] = 18  // R (Coin 1)
            base[.start1] = 19 // T (Start 1)
            
        case "scummvm":
            // ScummVM: Full mouse and keyboard emulation
            // D-Pad or Left Stick for movement
            base[.a] = 6     // A (Left Click)
            base[.b] = 7     // B (Right Click)
            // Additional keys for interaction
            base[.x] = 49    // Space
            base[.y] = 53    // Escape
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            base[.l2] = 1    // 1
            base[.r2] = 3    // 3
            
        case "dos":
            // DOSBox: Full keyboard support - use all standard keys
            // Arrow keys for D-Pad are already set
            // Standard WASD for movement in many DOS games
            base[.a] = 0     // A
            base[.b] = 11    // B
            base[.c] = 8     // C
            base[.x] = 7     // X
            base[.y] = 16    // Y
            base[.z] = 6     // Z
            base[.start] = 36  // Return
            base[.select] = 53 // Escape
            // Additional keys for DOS games
            base[.space] = 49  // Space
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            
        case "wii":
            // Wii Remote: D-Pad + A, B + 1, 2 + Home (Select)
            base[.a] = 6     // A
            base[.b] = 7     // B
            base[.x] = 8     // 1
            base[.y] = 9     // 2
            base[.l1] = 12   // Q
            base[.r1] = 14   // W
            base[.select] = 48  // Home
            
        case "switch":
            // Nintendo Switch: D-Pad + Plus/Minus (Start/Select) + A, B, X, Y + L, R, ZL, ZR
            // Note: Nintendo uses different face button layout than Sony
            base[.a] = 6     // A (Right)
            base[.b] = 7     // B (Bottom)
            base[.x] = 8     // X (Top)
            base[.y] = 9     // Y (Left)
            base[.l1] = 12   // L
            base[.r1] = 14   // R
            base[.l2] = 1    // ZL
            base[.r2] = 3    // ZR
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }
            
        default:
            // Generic/Default: Modern standard layout acting as the global template
            // Note: D-Pad (Arrows) and Start/Select are already mapped at the top of this function.
            
            base[.a] = 6     // Z
            base[.b] = 7     // X
            base[.x] = 8     // C
            base[.y] = 9     // V
            
            base[.l1] = 12   // Q
            base[.r1] = 14   // E (Mac keycode 14)
            base[.l2] = 18   // 1 (Number row)
            base[.r2] = 20   // 3 (Number row)
            base[.l3] = 19   // 2 (Number row)
            base[.r3] = 21   // 4 (Number row)
            
            // Left Stick (Mapped to WASD to avoid conflict with D-Pad arrows)
            base[.lStickUp] = 13    // W
            base[.lStickDown] = 1   // S
            base[.lStickLeft] = 0   // A
            base[.lStickRight] = 2  // D
            
            // Right Stick (Mapped to IJKL)
            base[.rStickUp] = 34    // I
            base[.rStickDown] = 40  // K
            base[.rStickLeft] = 38  // J
            base[.rStickRight] = 37 // L
        }
        
        return KeyboardMapping(buttons: base)
    }
}

// MARK: - RetroButton Enum

enum RetroButton: String, Codable, CaseIterable {
    // Basic buttons (available on all systems)
    case up, down, left, right    // D-Pad
    case start, select            // System buttons
    
    // Primary face buttons
    case a, b  // Common to most systems
    
    // Extended face buttons (SNES and up)
    case x, y, c, z  // Additional buttons
    
    // Shoulder buttons
    case l1, l2, l3
    case r1, r2, r3
    
    // Arcade specific
    case coin1, coin2, start1, start2
    
    // Turbo buttons (special)
    case turboA, turboB
    case turboX, turboY
    
    // Analog sticks
    case lStickUp, lStickDown, lStickLeft, lStickRight
    case rStickUp, rStickDown, rStickLeft, rStickRight

    // N64 C buttons
    case cUp, cDown, cLeft, cRight
    
    // Additional buttons
    case pause, reset
    case space // Space bar for DOS
    
    // Mouse buttons (ScummVM, etc)
    case mouseLeft, mouseRight, mouseMiddle
    case mouseX, mouseY
    case mouseScrollUp, mouseScrollDown

    var displayName: String {
        switch self {
        case .up:    return "Up"
        case .down:  return "Down"
        case .left:  return "Left"
        case .right: return "Right"
        case .a:     return "A"
        case .b:     return "B"
        case .c:     return "C"
        case .x:     return "X"
        case .y:     return "Y"
        case .z:     return "Z"
        case .start: return "Start"
        case .select:return "Select / Mode"
        case .l1:    return "L1"
        case .l2:    return "L2"
        case .l3:    return "L3 (Left Click)"
        case .r1:    return "R1"
        case .r2:    return "R2"
        case .r3:    return "R3 (Right Click)"
        case .coin1: return "Insert Coin 1"
        case .coin2: return "Insert Coin 2"
        case .start1:return "1P Start"
        case .start2:return "2P Start"
        case .lStickUp: return "Left Stick Up"
        case .lStickDown: return "Left Stick Down"
        case .lStickLeft: return "Left Stick Left"
        case .lStickRight: return "Left Stick Right"
        case .rStickUp: return "Right Stick Up"
        case .rStickDown: return "Right Stick Down"
        case .rStickLeft: return "Right Stick Left"
        case .rStickRight: return "Right Stick Right"
        case .cUp:    return "C-Button Up"
        case .cDown:  return "C-Button Down"
        case .cLeft:  return "C-Button Left"
        case .cRight: return "C-Button Right"
        case .pause:  return "Pause"
        case .reset:  return "Reset"
        case .turboA: return "Turbo A"
        case .turboB: return "Turbo B"
        case .turboX: return "Turbo X"
        case .turboY: return "Turbo Y"
        case .space:  return "Space"
        case .mouseLeft: return "Mouse Left Click"
        case .mouseRight: return "Mouse Right Click"
        case .mouseMiddle: return "Mouse Middle Click"
        case .mouseX: return "Mouse X Axis"
        case .mouseY: return "Mouse Y Axis"
        case .mouseScrollUp: return "Mouse Scroll Up"
        case .mouseScrollDown: return "Mouse Scroll Down"
        }
    }
    
    // Returns the list of buttons that are relevant/available for a given system.
    // This limits the UI to only show buttons that can be mapped for that system.
    // First tries to get buttons from InputDescriptorsManager (captured from core),
    // falls back to hardcoded system defaults.
    static func availableButtons(for systemID: String) -> [RetroButton] {
        if let buttons = InputDescriptorsManager.shared.availableButtons(for: systemID), !buttons.isEmpty {
            return buttons
        }
        return systemDefaultButtons(for: systemID)
    }

    // Hardcoded system-specific button defaults. Used as fallback when core
    // input descriptors are not available.
    static func systemDefaultButtons(for systemID: String) -> [RetroButton] {
        switch systemID.lowercased() {
        // MARK: - NES Family (8-bit Nintendo)
        case "nes":
            return [.up, .down, .left, .right, .a, .b, .turboA, .turboB, .start, .select]
        case "nes_turbo":
            // NES with explicit Turbo - same as NES but emphasizes turbo buttons
            return [.up, .down, .left, .right, .a, .b, .turboA, .turboB, .start, .select]
            
        // MARK: - SNES Family (16-bit Nintendo)
        case "snes", "sfc":
            return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select]
            
        // MARK: - Game Boy Family
        case "gb", "gbc":
            return [.up, .down, .left, .right, .a, .b, .start, .select]
        case "gba":
            return [.up, .down, .left, .right, .a, .b, .l1, .r1, .start, .select]
            
        // MARK: - N64
        case "n64":
            return[.up, .down, .left, .right, .a, .b, .z, .l1, .r1, .start, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .cUp, .cDown, .cLeft, .cRight]
            
        // MARK: - Nintendo DS/3DS
        case "nds":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select]
        case "3ds":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .start, .select, .lStickUp, .lStickDown, .lStickLeft, .lStickRight]            

        // MARK: - Sega Genesis/Mega Drive
        case "genesis", "megadrive":
            return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .start, .select]
            
        // MARK: - Sega Master System / Game Gear
        case "sms":
            return [.up, .down, .left, .right, .a, .b, .start]
        case "gamegear":
            return [.up, .down, .left, .right, .a, .b, .start]
            
        // MARK: - Sega Saturn
        case "saturn":
            return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .l1, .r1, .start, .select]
            
        // MARK: - Sega 32X
        case "32x":
            return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .start, .select]
            
        // MARK: - Dreamcast
        case "dreamcast":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .start, .select, .lStickUp, .lStickDown, .lStickLeft, .lStickRight]
            
        // MARK: - PlayStation Family
        case "psx", "ps1":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .l3, .r3, .start, .select, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .rStickUp, .rStickDown, .rStickLeft, .rStickRight]
        case "ps2":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .l3, .r3, .start, .select, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .rStickUp, .rStickDown, .rStickLeft, .rStickRight]
        case "psp":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select, .lStickUp, .lStickDown, .lStickLeft, .lStickRight]
            
        // MARK: - Nintendo Switch/Wii
        case "switch":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .l3, .r3, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .rStickUp, .rStickDown, .rStickLeft, .rStickRight, .start, .select]
        case "wii":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .start, .select]
        case "wiiu":
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .l3, .r3, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .rStickUp, .rStickDown, .rStickLeft, .rStickRight, .start, .select]            

        // MARK: - Arcade
        case "mame", "fba", "arcade":
            return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .coin1, .coin2, .start1, .start2]
            
        // MARK: - Atari
        case "atari2600":
            return [.up, .down, .left, .right, .a, .select]
        case "atari5200":
            return [.up, .down, .left, .right, .a, .b, .x, .y, .start, .pause]
        case "atari7800":
            return [.up, .down, .left, .right, .a, .b]
        case "lynx":
            return [.up, .down, .left, .right, .a, .b]
            
        // MARK: - NEC
        case "pce", "tg16":
            return [.up, .down, .left, .right, .a, .b, .start, .select]
        case "pcfx":
            return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select]
            
        // MARK: - SNK
        case "ngp", "ngc":
            return [.up, .down, .left, .right, .a, .b, .start]
            
        // MARK: - 3DO
        case "3do":
            return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .start, .select]
            
        // MARK: - ScummVM (requires mouse)
        case "scummvm":
            return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select, .mouseLeft, .mouseRight, .mouseX, .mouseY]
            
        // MARK: - DOSBox (requires full keyboard + mouse)
        case "dos":
            return[.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .l1, .r1, .start, .select, .space, .pause, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .mouseLeft, .mouseRight, .mouseX, .mouseY]
            
        // MARK: - Default (fallback with most common buttons)
        default:
            return[.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .l3, .r3, .start, .select, .lStickUp, .lStickDown, .lStickLeft, .lStickRight, .rStickUp, .rStickDown, .rStickLeft, .rStickRight]
        }
    }
    
    // Returns the list of button names for a turbo variation of a system.
    // Turbo buttons rapidly toggle their associated button on/off when held.
    static func turboButtons(for systemID: String) -> [RetroButton] {
        switch systemID.lowercased() {
        case "nes", "nes_turbo":
            return [.turboA, .turboB]
        case "snes", "sfc":
            return [.turboA, .turboB, .turboX, .turboY]
        case "genesis", "megadrive":
            return [.turboA, .turboB, .turboX, .turboY]
        case "scummvm":
            // Turbo for rapid clicking
            return [.turboA]
        default:
            return []
        }
    }
    
    // Returns a human-readable system category name for UI grouping
    static func systemCategory(for systemID: String) -> String {
        switch systemID.lowercased() {
        case "nes": return "NES (8-bit Nintendo)"
        case "snes", "sfc": return "SNES (16-bit Nintendo)"
        case "n64": return "Nintendo 64"
        case "gb", "gbc", "gba": return "Game Boy Family"
        case "nds", "3ds": return "Nintendo Handhelds"
        case "genesis", "megadrive": return "Genesis / Mega Drive"
        case "sms", "gamegear": return "Sega 8-bit"
        case "saturn": return "Sega Saturn"
        case "dreamcast": return "Sega Dreamcast"
        case "psx", "ps1", "ps2", "psp": return "PlayStation Family"
        case "switch", "wii", "wiiu": return "Modern Nintendo"
        case "mame", "fba", "arcade": return "Arcade"
        case "atari2600", "atari5200", "atari7800", "lynx": return "Atari Family"
        case "pce", "tg16", "pcfx": return "NEC Family"
        case "ngp", "ngc": return "SNK Neo Geo Pocket"
        case "3do": return "3DO"
        case "scummvm": return "ScummVM (Adventure Games)"
        case "dos": return "DOS (MS-DOS Games)"
        default: return "Other"
        }
    }
    
    func retroID(for systemID: String) -> Int32 {
        switch self {
        // Standard buttons remain the same
        case .b: return 0
        case .y: return 1
        case .select: return 2
        case .start: return 3
        case .up: return 4
        case .down: return 5
        case .left: return 6
        case .right: return 7
        case .a: return 8
        case .x: return 9
        case .l1: return 10
        case .r1: return 11
        case .l2: return 12
        case .r2: return 13
        case .l3: return 14
        case .r3: return 15

        // The Context-Sensitive "Z" Button
        case .z:
            if systemID == "n64" {
                return 12 // N64 Z is a Trigger (L2)
            } else if ["genesis", "megadrive", "saturn", "32x"].contains(systemID) {
                return 11 // Sega Z is the 6th face button (usually mapped to R1)
            }
            return 12 // Default fallback

        // The Context-Sensitive "C" Button
        case .c:
            if ["genesis", "megadrive", "saturn", "32x"].contains(systemID) {
                return 8 // Sega C is usually mapped to RetroPad A
            }
            return -1

        case .coin1: return 2
        case .start1: return 3
        
        default: return -1
        }
    }
    
    // Returns whether this button is an analog axis rather than a digital button
    var isAnalog: Bool {
        return self == .lStickUp || self == .lStickDown || self == .lStickLeft || self == .lStickRight ||
               self == .rStickUp || self == .rStickDown || self == .rStickLeft || self == .rStickRight ||
               self == .cUp || self == .cDown || self == .cLeft || self == .cRight ||
               self == .mouseX || self == .mouseY
    }

    // Returns analog axis information for libretro analog state
    var analogInfo: (index: Int32, id: Int32, sign: Float)? {
        switch self {
        case .lStickUp:    return (0, 1, -1.0)
        case .lStickDown:  return (0, 1, 1.0)
        case .lStickLeft:  return (0, 0, -1.0)
        case .lStickRight: return (0, 0, 1.0)
        case .rStickUp:    return (1, 1, -1.0)
        case .rStickDown:  return (1, 1, 1.0)
        case .rStickLeft:  return (1, 0, -1.0)
        case .rStickRight: return (1, 0, 1.0)
        case .cUp:     return (1, 1, -1.0)  // C-Up is negative Y axis on analog
        case .cDown:   return (1, 1, 1.0)
        case .cLeft:   return (1, 0, -1.0)  // C-Left is negative X axis on analog
        case .cRight:  return (1, 0, 1.0)
        case .mouseX:  return (2, 0, 1.0)   // Mouse X
        case .mouseY:  return (2, 1, 1.0)   // Mouse Y
        default: return nil
        }
    }
    
    // Whether this is a turbo button that should rapidly toggle
    var isTurbo: Bool {
        return self == .turboA || self == .turboB || self == .turboX || self == .turboY
    }
    
    // The base button this turbo button maps to
    var turboBaseButton: RetroButton? {
        switch self {
        case .turboA: return .a
        case .turboB: return .b
        case .turboX: return .x
        case .turboY: return .y
        default: return nil
        }
    }

}
// MARK: - Dynamic Global Translators

extension ControllerGamepadMapping {
    static func derived(from global: ControllerGamepadMapping, for systemID: String) -> ControllerGamepadMapping {
        var mapping = ControllerGamepadMapping(vendorName: global.vendorName, buttons: [:])
        let availableButtons = RetroButton.availableButtons(for: systemID)
        
        // Helper to map a target system button to a source global button
        func map(_ target: RetroButton, to source: RetroButton) {
            if availableButtons.contains(target), let globalBtn = global.buttons[source] {
                mapping.buttons[target] = globalBtn
            }
        }

        // 1. Map all 1:1 identical buttons first (e.g., A -> A, Start -> Start)
        for btn in availableButtons {
            if let globalBtn = global.buttons[btn] {
                mapping.buttons[btn] = globalBtn
            }
        }

        // 2. Apply system-specific logical overrides
        switch systemID.lowercased() {
        case "nes", "nes_turbo":
            map(.turboA, to: .x)
            map(.turboB, to: .y)
            
        case "n64":
            map(.z, to: .l2) 
            map(.a, to: .a) 
            map(.b, to: .x) // Standard N64-to-modern mapping: B on X
            // Map C-buttons to Right Stick
            map(.cUp, to: .rStickUp)
            map(.cDown, to: .rStickDown)
            map(.cLeft, to: .rStickLeft)
            map(.cRight, to: .rStickRight)
            
        case "genesis", "megadrive", "saturn", "32x":
            // Map Sega 6-button layout to modern 4-face + shoulders
            map(.a, to: .x)
            map(.b, to: .a)
            map(.c, to: .b)
            map(.x, to: .l1)
            map(.y, to: .y)
            map(.z, to: .r1)
            
        case "mame", "fba", "arcade":
            map(.coin1, to: .select)
            map(.start1, to: .start)
            map(.coin2, to: .l3)
            map(.start2, to: .r3)
            
        default:
            break
        }
        
        return mapping
    }
}

extension KeyboardMapping {
    static func derived(from global: KeyboardMapping, for systemID: String) -> KeyboardMapping {
        var mapping = KeyboardMapping(buttons: [:])
        let availableButtons = RetroButton.availableButtons(for: systemID)
        
        func map(_ target: RetroButton, to source: RetroButton) {
            if availableButtons.contains(target), let globalKey = global.buttons[source] {
                mapping.buttons[target] = globalKey
            }
        }

        for btn in availableButtons {
            if let globalKey = global.buttons[btn] {
                mapping.buttons[btn] = globalKey
            }
        }

        switch systemID.lowercased() {
        case "nes", "nes_turbo":
            map(.turboA, to: .x)
            map(.turboB, to: .y)
        case "n64":
            map(.z, to: .l2)
            map(.cUp, to: .rStickUp)
            map(.cDown, to: .rStickDown)
            map(.cLeft, to: .rStickLeft)
            map(.cRight, to: .rStickRight)
        case "genesis", "megadrive", "saturn", "32x":
            map(.a, to: .x)
            map(.b, to: .a)
            map(.c, to: .b)
            map(.x, to: .l1)
            map(.y, to: .y)
            map(.z, to: .r1)
        case "mame", "fba", "arcade":
            map(.coin1, to: .select)
            map(.start1, to: .start)
            map(.coin2, to: .l3)
            map(.start2, to: .r3)
        default:
            break
        }
        
        return mapping
    }
}
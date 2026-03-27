import Foundation
import GameController
import Combine

@MainActor
class ControllerService: ObservableObject {
    static let shared = ControllerService()
    
    @Published var connectedControllers: [PlayerController] = []

    @Published var activePlayerIndex: Int = 0 {
        didSet {
            defaults.set(activePlayerIndex, forKey: "active_player_index")
        }
    }

    private let defaults = UserDefaults.standard
    private let mappingKey = "controller_mappings_v2" 
    private let kbMappingKey = "keyboard_mapping_v1"
    private var savedMappings: [String: [String: ControllerMapping]] = [:] 

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.activePlayerIndex = defaults.integer(forKey: "active_player_index")
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
            let mapping = savedMappings[vendorName]?["default"] ?? ControllerMapping.defaults(for: vendorName, systemID: "default")
            players.append(PlayerController(
                playerIndex: index + 1,
                gcController: gc,
                mapping: mapping
            ))
        }
        connectedControllers = players
    }

    // MARK: - Mappings

    func updateMapping(for vendorName: String, systemID: String, mapping: ControllerMapping) {
        if savedMappings[vendorName] == nil { savedMappings[vendorName] = [:] }
        savedMappings[vendorName]?[systemID] = mapping
        
        refreshConnectedControllers()
        saveMappings()
    }
    
    func mapping(for vendorName: String, systemID: String) -> ControllerMapping {
        if let systemMapping = savedMappings[vendorName]?[systemID] {
            return systemMapping
        }
        if let global = savedMappings[vendorName]?["default"] {
            return global
        }
        return ControllerMapping.defaults(for: vendorName, systemID: systemID)
    }

    func updateKeyboardMapping(_ mapping: KeyboardMapping, for systemID: String) {
        var all = keyboardMappings
        all[systemID] = mapping
        keyboardMappings = all
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: kbMappingKey)
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(savedMappings) {
            defaults.set(data, forKey: mappingKey)
        }
    }

    private func loadMappings() {
        if let data = defaults.data(forKey: mappingKey),
           let saved = try? JSONDecoder().decode([String: [String: ControllerMapping]].self, from: data) {
            savedMappings = saved
        }
        
        if let data = defaults.data(forKey: kbMappingKey),
           let saved = try? JSONDecoder().decode([String: KeyboardMapping].self, from: data) {
            keyboardMappings = saved
        }
    }
    
    @Published var keyboardMappings: [String: KeyboardMapping] = [:]
    
    func keyboardMapping(for systemID: String) -> KeyboardMapping {
        keyboardMappings[systemID] ?? KeyboardMapping.defaults(for: systemID)
    }
}

// MARK: - Models

struct PlayerController: Identifiable {
    var id: Int { playerIndex }
    var playerIndex: Int
    var gcController: GCController?
    var mapping: ControllerMapping

    var name: String { gcController?.vendorName ?? "Player \(playerIndex)" }
    var isConnected: Bool { gcController != nil }
}

struct ControllerMapping: Codable {
    var vendorName: String
    var buttons: [RetroButton: GCButtonMapping]

    static func defaults(for vendorName: String, systemID: String) -> ControllerMapping {
        var mapping = ControllerMapping(vendorName: vendorName, buttons: [:])
        
        mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
        mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
        mapping.buttons[.x] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
        mapping.buttons[.y] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
        
        mapping.buttons[.up] = GCButtonMapping(gcElementName: "D-pad Up", gcElementAlias: "Up")
        mapping.buttons[.down] = GCButtonMapping(gcElementName: "D-pad Down", gcElementAlias: "Down")
        mapping.buttons[.left] = GCButtonMapping(gcElementName: "D-pad Left", gcElementAlias: "Left")
        mapping.buttons[.right] = GCButtonMapping(gcElementName: "D-pad Right", gcElementAlias: "Right")
        
        mapping.buttons[.l1] = GCButtonMapping(gcElementName: "Left Shoulder", gcElementAlias: "L1")
        mapping.buttons[.r1] = GCButtonMapping(gcElementName: "Right Shoulder", gcElementAlias: "R1")
        mapping.buttons[.l2] = GCButtonMapping(gcElementName: "Left Trigger", gcElementAlias: "L2")
        mapping.buttons[.r2] = GCButtonMapping(gcElementName: "Right Trigger", gcElementAlias: "R2")
        
        mapping.buttons[.start] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
        mapping.buttons[.select] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
        
        // Analog sticks
        mapping.buttons[.lStickX] = GCButtonMapping(gcElementName: "Left Stick", gcElementAlias: "L Stick X")
        mapping.buttons[.lStickY] = GCButtonMapping(gcElementName: "Left Stick", gcElementAlias: "L Stick Y")
        mapping.buttons[.rStickX] = GCButtonMapping(gcElementName: "Right Stick", gcElementAlias: "R Stick X")
        mapping.buttons[.rStickY] = GCButtonMapping(gcElementName: "Right Stick", gcElementAlias: "R Stick Y")
        
        return mapping
    }
}

struct GCButtonMapping: Codable {
    var gcElementName: String   
    var gcElementAlias: String? 
}

struct KeyboardMapping: Codable {
    var buttons: [RetroButton: UInt16]  

    static func defaults(for systemID: String) -> KeyboardMapping {
        var base: [RetroButton: UInt16] = [
            .up:     126,  
            .down:   125,  
            .left:   123,  
            .right:  124,  
            .a:      6,    
            .b:      7,    
            .start:  36,   
            .select: 48,   
        ]
        
        switch systemID {
        case "snes":
            base[.x] = 8 
            base[.y] = 9 
            base[.l1] = 12 
            base[.r1] = 14 
        case "genesis":
            base[.c] = 8 
            base[.x] = 12 
            base[.y] = 13 
            base[.z] = 14 
        case "mame", "fba", "arcade":
            base[.coin1] = 18 
            base[.start1] = 19 
        default:
            base[.x] = 8
            base[.y] = 9
        }
        
        return KeyboardMapping(buttons: base)
    }
}

enum RetroButton: String, Codable, CaseIterable {
    case up, down, left, right
    case a, b, c, x, y, z
    case start, select
    case l1, l2, l3
    case r1, r2, r3
    case coin1, coin2, start1, start2
    case lStickX, lStickY, rStickX, rStickY // Individual axes
    case cUp, cDown, cLeft, cRight // N64 C-buttons
    case pause, reset

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
        case .lStickX:return "Left Stick X (Horizontal)"
        case .lStickY:return "Left Stick Y (Vertical)"
        case .rStickX:return "Right Stick X (Horizontal)"
        case .rStickY:return "Right Stick Y (Vertical)"
        case .cUp:    return "C-Button Up"
        case .cDown:  return "C-Button Down"
        case .cLeft:  return "C-Button Left"
        case .cRight: return "C-Button Right"
        case .pause: return "Pause"
        case .reset: return "Reset"
        }
    }
    
    static func relevantButtons(for systemID: String) -> [RetroButton] {
        switch systemID.lowercased() {
        case "nes":      return [.up, .down, .left, .right, .a, .b, .start, .select]
        case "snes":     return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .start, .select]
        case "ps1", "psx": return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .l3, .r3, .lStickX, .lStickY, .rStickX, .rStickY, .start, .select]
        case "n64":      return [.up, .down, .left, .right, .a, .b, .l1, .r1, .z, .start, .lStickX, .lStickY, .cUp, .cDown, .cLeft, .cRight]
        case "genesis":  return [.up, .down, .left, .right, .a, .b, .c, .x, .y, .z, .start, .select]
        case "mame", "fba", "arcade": return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .coin1, .start1]
        case "default":  return [.up, .down, .left, .right, .a, .b, .x, .y, .l1, .r1, .l2, .r2, .lStickX, .lStickY, .rStickX, .rStickY, .start, .select]
        default:         return RetroButton.allCases
        }
    }
    
    var retroID: Int32 {
        switch self {
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
        case .coin1: return 2 
        case .start1: return 3
        case .lStickX, .lStickY, .rStickX, .rStickY, .cUp, .cDown, .cLeft, .cRight, .c, .z, .coin2, .start2, .pause, .reset: return 0
        }
    }
    
    var isAnalog: Bool {
        return self == .lStickX || self == .lStickY || self == .rStickX || self == .rStickY ||
               self == .cUp || self == .cDown || self == .cLeft || self == .cRight
    }

    var analogInfo: (index: Int32, id: Int32, sign: Float)? {
        switch self {
        case .lStickX: return (0, 0, 1.0)
        case .lStickY: return (0, 1, 1.0)
        case .rStickX: return (1, 0, 1.0)
        case .rStickY: return (1, 1, 1.0)
        case .cUp:     return (1, 1, -1.0)
        case .cDown:   return (1, 1, 1.0)
        case .cLeft:   return (1, 0, -1.0)
        case .cRight:  return (1, 0, 1.0)
        default: return nil
        }
    }
}

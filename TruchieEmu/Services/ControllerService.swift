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
    private let mappingKey = "controller_mappings_v1"
    private let kbMappingKey = "keyboard_mapping_v1"
    private var savedMappings: [String: ControllerMapping] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.activePlayerIndex = UserDefaults.standard.integer(forKey: "active_player_index")
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
            let mapping = savedMappings[vendorName] ?? ControllerMapping.defaults(for: vendorName)
            players.append(PlayerController(
                playerIndex: index + 1,
                gcController: gc,
                mapping: mapping
            ))
        }
        connectedControllers = players
    }

    // MARK: - Mappings

    func updateMapping(for vendorName: String, mapping: ControllerMapping) {
        savedMappings[vendorName] = mapping
        if let idx = connectedControllers.firstIndex(where: { $0.gcController?.vendorName == vendorName }) {
            connectedControllers[idx].mapping = mapping
        }
        saveMappings()
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
           let saved = try? JSONDecoder().decode([String: ControllerMapping].self, from: data) {
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

    var name: String { gcController?.vendorName ?? "Keyboard (Player \(playerIndex))" }
    var isConnected: Bool { gcController != nil }
}

struct ControllerMapping: Codable {
    var vendorName: String
    var buttons: [RetroButton: GCButtonMapping]

    static func defaults(for vendorName: String) -> ControllerMapping {
        ControllerMapping(vendorName: vendorName, buttons: [:])
    }
}

struct GCButtonMapping: Codable {
    var gcElementName: String   // e.g. "buttonA", "leftThumbstickButton"
    var gcElementAlias: String? // Display label
}

struct KeyboardMapping: Codable {
    var buttons: [RetroButton: UInt16]  // RetroButton -> macOS keyCode

    static func defaults(for systemID: String) -> KeyboardMapping {
        var base: [RetroButton: UInt16] = [
            .up:     126,  // arrow up
            .down:   125,  // arrow down
            .left:   123,  // arrow left
            .right:  124,  // arrow right
            .a:      6,    // z
            .b:      7,    // x
            .start:  36,   // return
            .select: 48,   // tab
        ]
        
        switch systemID {
        case "snes":
            base[.x] = 8 // c
            base[.y] = 9 // v
            base[.l1] = 12 // q
            base[.r1] = 14 // r
        case "genesis":
            base[.c] = 8 // c
            base[.x] = 12 // q
            base[.y] = 13 // w
            base[.z] = 14 // e
        case "mame", "fba", "arcade":
            base[.coin1] = 18 // 1
            base[.start1] = 19 // 2
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
        case .l3:    return "L3"
        case .r1:    return "R1"
        case .r2:    return "R2"
        case .r3:    return "R3"
        case .coin1: return "Insert Coin 1"
        case .coin2: return "Insert Coin 2"
        case .start1:return "1P Start"
        case .start2:return "2P Start"
        case .pause: return "Pause"
        case .reset: return "Reset"
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
        // Arcade specific often map to these or are handled by core-specific mappings
        case .coin1: return 2 // Usually Select
        case .start1: return 3 // Usually Start
        default: return 0
        }
    }
}

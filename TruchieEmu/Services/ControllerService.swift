import Foundation
import GameController
import Combine

@MainActor
class ControllerService: ObservableObject {
    @Published var connectedControllers: [PlayerController] = []
    @Published var keyboardMapping: KeyboardMapping = KeyboardMapping.defaults

    private let defaults = UserDefaults.standard
    private let mappingKey = "controller_mappings_v1"
    private let kbMappingKey = "keyboard_mapping_v1"
    private var savedMappings: [String: ControllerMapping] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
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

    func updateKeyboardMapping(_ mapping: KeyboardMapping) {
        keyboardMapping = mapping
        if let data = try? JSONEncoder().encode(mapping) {
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
           let saved = try? JSONDecoder().decode(KeyboardMapping.self, from: data) {
            keyboardMapping = saved
        }
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

    static var defaults: KeyboardMapping {
        KeyboardMapping(buttons: [
            .up:     126,  // arrow up
            .down:   125,  // arrow down
            .left:   123,  // arrow left
            .right:  124,  // arrow right
            .a:      6,    // z
            .b:      7,    // x
            .x:      8,    // c
            .y:      9,    // v
            .start:  36,   // return
            .select: 53,   // esc
            .l1:     12,   // q
            .r1:     14,   // r
        ])
    }
}

enum RetroButton: String, Codable, CaseIterable {
    case up, down, left, right
    case a, b, x, y
    case start, select
    case l1, l2, l3
    case r1, r2, r3

    var displayName: String {
        switch self {
        case .up:    return "D-Pad Up"
        case .down:  return "D-Pad Down"
        case .left:  return "D-Pad Left"
        case .right: return "D-Pad Right"
        case .a:     return "A"
        case .b:     return "B"
        case .x:     return "X"
        case .y:     return "Y"
        case .start: return "Start"
        case .select:return "Select"
        case .l1:    return "L1"
        case .l2:    return "L2"
        case .l3:    return "L3 (Click)"
        case .r1:    return "R1"
        case .r2:    return "R2"
        case .r3:    return "R3 (Click)"
        }
    }
}

import Foundation
import GameController

enum GamepadNavButton: String, Codable, CaseIterable, Identifiable {
    case buttonA
    case buttonB
    case buttonX
    case buttonY
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case l1
    case r1
    case l2
    case r2
    case l3
    case r3
    case start
    case select
    case leftStickUp
    case leftStickDown
    case leftStickLeft
    case leftStickRight
    case rightStickUp
    case rightStickDown
    case rightStickLeft
    case rightStickRight
    case l3PlusR3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .buttonA: return "A"
        case .buttonB: return "B"
        case .buttonX: return "X"
        case .buttonY: return "Y"
        case .dpadUp: return "D-pad ↑"
        case .dpadDown: return "D-pad ↓"
        case .dpadLeft: return "D-pad ←"
        case .dpadRight: return "D-pad →"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .start: return "Start"
        case .select: return "Select"
        case .leftStickUp: return "L-Stick ↑"
        case .leftStickDown: return "L-Stick ↓"
        case .leftStickLeft: return "L-Stick ←"
        case .leftStickRight: return "L-Stick →"
        case .rightStickUp: return "R-Stick ↑"
        case .rightStickDown: return "R-Stick ↓"
        case .rightStickLeft: return "R-Stick ←"
        case .rightStickRight: return "R-Stick →"
        case .l3PlusR3: return "L3+R3"
        }
    }

    var isAnalog: Bool {
        switch self {
        case .l2, .r2, .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight:
            return true
        default:
            return false
        }
    }

    static let availableForMapping: [GamepadNavButton] = [
        .buttonA, .buttonB, .buttonX, .buttonY,
        .l1, .r1, .l2, .r2, .l3, .r3, .l3PlusR3,
        .start, .select
    ]
}

enum GamepadNavAction: String, Codable, CaseIterable, Identifiable {
    case navigateUp
    case navigateDown
    case navigateLeft
    case navigateRight
    case focusPrevZone
    case focusNextZone
    case focusSidebarZone
    case focusContentZone
    case focusToolbarZone
    case pageUp
    case pageDown
    case scrollUp
    case scrollDown
    case select
    case cancel
    case contextMenu
    case toggleViewMode
    case focusSearch
    case cycleSortOrder
    case openSettings
    case launchGame
    case showGameToolbar
    case closeWindow

    var id: String { rawValue }

    var localizationKey: String {
        "gamepadNav.action." + rawValue
    }

    var isGameWindowAction: Bool {
        switch self {
        case .showGameToolbar, .closeWindow: return true
        default: return false
        }
    }

    var isNavigationAction: Bool {
        switch self {
        case .navigateUp, .navigateDown, .navigateLeft, .navigateRight: return true
        default: return false
        }
    }

    var isScrollAction: Bool {
        switch self {
        case .scrollUp, .scrollDown, .pageUp, .pageDown: return true
        default: return false
        }
    }
}

struct GamepadNavBinding: Codable, Equatable, Hashable {
    var button: GamepadNavButton?
    var threshold: Float

    static let unbound = GamepadNavBinding(button: nil, threshold: 0.5)

    var isUnset: Bool { button == nil }

    init(button: GamepadNavButton?, threshold: Float = 0.5) {
        self.button = button
        self.threshold = threshold
    }

    var displayString: String {
        guard let button else { return "—" }
        return button.displayName
    }
}

struct GamepadNavConfig: Codable, Equatable {
    var binding: GamepadNavBinding

    static let unbound = GamepadNavConfig(binding: .unbound)
}

@MainActor
final class GamepadNavConfigManager: ObservableObject {
    static let shared = GamepadNavConfigManager()

    @Published private(set) var config: [GamepadNavAction: GamepadNavConfig]
    @Published var isEnabled: Bool {
        didSet {
            AppSettings.setBool(Self.enabledKey, value: isEnabled)
            if !isEnabled {
                GamepadNavigationManager.shared.stopPolling()
            }
        }
    }

    private static let storageKey = "gamepadNavConfig"
    private static let enabledKey = "gamepadNavigationEnabled"

    private init() {
        self.isEnabled = AppSettings.getBool(Self.enabledKey, defaultValue: true)
        if let data = AppSettings.getData(Self.storageKey),
           let decoded = try? JSONDecoder().decode([GamepadNavAction: GamepadNavConfig].self, from: data) {
            self.config = decoded
            for action in GamepadNavAction.allCases {
                if config[action] == nil {
                    config[action] = Self.defaults[action]!
                }
            }
        } else {
            self.config = Self.defaults
        }
    }

    static let defaults: [GamepadNavAction: GamepadNavConfig] = [
        .navigateUp:       GamepadNavConfig(binding: GamepadNavBinding(button: .dpadUp)),
        .navigateDown:     GamepadNavConfig(binding: GamepadNavBinding(button: .dpadDown)),
        .navigateLeft:     GamepadNavConfig(binding: GamepadNavBinding(button: .dpadLeft)),
        .navigateRight:    GamepadNavConfig(binding: GamepadNavBinding(button: .dpadRight)),
        .focusPrevZone:    GamepadNavConfig(binding: GamepadNavBinding(button: .l1)),
        .focusNextZone:    GamepadNavConfig(binding: GamepadNavBinding(button: .r1)),
        .focusSidebarZone: GamepadNavConfig(binding: GamepadNavBinding(button: .dpadLeft)),
        .focusContentZone: GamepadNavConfig(binding: GamepadNavBinding(button: .dpadRight)),
        .focusToolbarZone: GamepadNavConfig(binding: GamepadNavBinding(button: .dpadUp)),
        .pageUp:           GamepadNavConfig(binding: GamepadNavBinding(button: .l2)),
        .pageDown:          GamepadNavConfig(binding: GamepadNavBinding(button: .r2)),
        .scrollUp:          GamepadNavConfig(binding: GamepadNavBinding(button: .rightStickUp)),
        .scrollDown:        GamepadNavConfig(binding: GamepadNavBinding(button: .rightStickDown)),
        .select:           GamepadNavConfig(binding: GamepadNavBinding(button: .buttonA)),
        .cancel:           GamepadNavConfig(binding: GamepadNavBinding(button: .buttonB)),
        .contextMenu:      GamepadNavConfig(binding: GamepadNavBinding(button: .buttonY)),
        .toggleViewMode:   GamepadNavConfig(binding: GamepadNavBinding(button: .buttonX)),
        .focusSearch:      GamepadNavConfig(binding: GamepadNavBinding(button: .l3)),
        .cycleSortOrder:   GamepadNavConfig(binding: GamepadNavBinding(button: .r3)),
        .openSettings:      GamepadNavConfig(binding: GamepadNavBinding(button: .select)),
        .launchGame:        GamepadNavConfig(binding: GamepadNavBinding(button: .start)),
        .showGameToolbar:   GamepadNavConfig(binding: GamepadNavBinding(button: .l3PlusR3)),
        .closeWindow:      GamepadNavConfig(binding: .unbound),
    ]

    func update(_ action: GamepadNavAction, binding: GamepadNavBinding) {
        config[action]?.binding = binding
        save()
    }

    func resetToDefaults() {
        config = Self.defaults
        save()
    }

    func button(for action: GamepadNavAction) -> GamepadNavButton? {
        config[action]?.binding.button
    }

    func findConflicts(for binding: GamepadNavBinding, excluding action: GamepadNavAction) -> [(GamepadNavAction, GamepadNavBinding)] {
        guard let button = binding.button, !binding.isUnset else { return [] }
        var conflicts: [(GamepadNavAction, GamepadNavBinding)] = []
        for (act, cfg) in config {
            guard act != action else { continue }
            if cfg.binding.button == button {
                conflicts.append((act, cfg.binding))
            }
        }
        return conflicts
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            AppSettings.setData(Self.storageKey, value: data)
        }
    }
}

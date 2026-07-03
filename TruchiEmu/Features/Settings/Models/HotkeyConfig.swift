import Foundation
import Carbon.HIToolbox

struct HotkeyBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifierFlags: UInt

    var isCommand: Bool { modifierFlags & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 }
    var isShift: Bool { modifierFlags & UInt(NSEvent.ModifierFlags.shift.rawValue) != 0 }
    var isOption: Bool { modifierFlags & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 }
    var isControl: Bool { modifierFlags & UInt(NSEvent.ModifierFlags.control.rawValue) != 0 }

    static func command(_ keyCode: UInt16) -> HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifierFlags: UInt(NSEvent.ModifierFlags.command.rawValue))
    }

    static func plain(_ keyCode: UInt16) -> HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifierFlags: 0)
    }

    static let none = HotkeyBinding(keyCode: UInt16.max, modifierFlags: 0)

    var isUnset: Bool { keyCode == UInt16.max }

    func matches(_ event: NSEvent) -> Bool {
        guard !isUnset else { return false }
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode && UInt(eventFlags.rawValue) == modifierFlags
    }

    var displayString: String {
        if isUnset { return "—" }
        var parts: [String] = []
        if isControl { parts.append("⌃") }
        if isOption { parts.append("⌥") }
        if isShift { parts.append("⇧") }
        if isCommand { parts.append("⌘") }
        parts.append(HotkeyBinding.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0:"A", 11:"B", 8:"C", 2:"D", 14:"E", 3:"F", 5:"G", 4:"H", 34:"I", 38:"J",
            40:"K", 37:"L", 46:"M", 45:"N", 31:"O", 35:"P", 12:"Q", 15:"R", 1:"S", 17:"T",
            32:"U", 9:"V", 13:"W", 7:"X", 16:"Y", 6:"Z",
            18:"1", 19:"2", 20:"3", 21:"4", 22:"5", 23:"6", 24:"7", 25:"8", 26:"9", 27:"0",
            36:"↩", 48:"⇥", 49:"Space", 53:"⎋",
            51:"⌫", 117:"Del", 123:"←", 124:"→", 125:"↓", 126:"↑",
            33:"F1", 122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6",
            98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case saveState
    case loadState
    case undoLoadState
    case slotNext
    case slotPrev
    case slot0
    case slot1
    case slot2
    case slot3
    case slot4
    case slot5
    case slot6
    case slot7
    case slot8
    case slot9
    case toggleInputCapture
    case trainingReset
    case trainingToggleRecording
    case trainingStartPlayback
    case toggleTrainingMode
    case screenshot

    var id: String { rawValue }

    var localizationKey: String {
        "hotkeys.action." + rawValue
    }

    var isTrainingAction: Bool {
        switch self {
        case .trainingReset, .trainingToggleRecording, .trainingStartPlayback, .toggleTrainingMode:
            return true
        default:
            return false
        }
    }

    var isSlotAction: Bool {
        switch self {
        case .slot0, .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9:
            return true
        default:
            return false
        }
    }

    var searchSectionID: String {
        if isSlotAction { return "slots" }
        if isTrainingAction { return "training" }
        if self == .screenshot { return "screenshots" }
        return "general"
    }
}

enum ControllerHotkeySource: String, Codable {
    case gameController
    case sdl
}

struct ControllerHotkeyBinding: Codable, Equatable, Hashable {
    var source: ControllerHotkeySource
    var identifier: String
    var displayLabel: String

    static let unset = ControllerHotkeyBinding(source: .gameController, identifier: "", displayLabel: "")

    var isUnset: Bool { identifier.isEmpty }

    static func gc(_ identifier: String, label: String? = nil) -> ControllerHotkeyBinding {
        ControllerHotkeyBinding(
            source: .gameController,
            identifier: identifier,
            displayLabel: label ?? identifier
        )
    }

    static func sdl(_ index: Int, label: String? = nil) -> ControllerHotkeyBinding {
        ControllerHotkeyBinding(
            source: .sdl,
            identifier: String(index),
            displayLabel: label ?? "Button \(index)"
        )
    }
}

struct HotkeyConfig: Codable, Equatable {
    var primary: HotkeyBinding
    var secondary: HotkeyBinding
    var controller: ControllerHotkeyBinding?

    static let unbound = HotkeyConfig(
        primary: .none,
        secondary: .none,
        controller: nil
    )

    private enum CodingKeys: String, CodingKey {
        case primary, secondary, controller
    }

    init(primary: HotkeyBinding, secondary: HotkeyBinding, controller: ControllerHotkeyBinding? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.controller = controller
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primary = try c.decode(HotkeyBinding.self, forKey: .primary)
        secondary = try c.decode(HotkeyBinding.self, forKey: .secondary)
        controller = try c.decodeIfPresent(ControllerHotkeyBinding.self, forKey: .controller)
    }
}

@MainActor
final class HotkeyConfigManager: ObservableObject {
    static let shared = HotkeyConfigManager()

    @Published private(set) var config: [HotkeyAction: HotkeyConfig]

    private static let storageKey = "hotkeyConfig"

    private init() {
        if let data = AppSettings.getData(Self.storageKey),
           let decoded = try? JSONDecoder().decode([HotkeyAction: HotkeyConfig].self, from: data) {
            self.config = decoded
            let defaults = Self.defaults
            for action in HotkeyAction.allCases {
                if config[action] == nil {
                    config[action] = defaults[action]!
                }
            }
        } else {
            self.config = Self.defaults
        }
    }

    static let defaults: [HotkeyAction: HotkeyConfig] = [
        .saveState:               HotkeyConfig(primary: .command(1),   secondary: .plain(96)),    // ⌘S, F5
        .loadState:               HotkeyConfig(primary: .command(37),  secondary: .plain(98)),    // ⌘L, F7
        .undoLoadState:           HotkeyConfig(primary: .command(6),   secondary: .none),         // ⌘Z
        .slotNext:                HotkeyConfig(primary: .plain(97),    secondary: .none),         // F6
        .slotPrev:                HotkeyConfig(primary: .plain(95),    secondary: .none),         // F4
        .slot0:                   HotkeyConfig(primary: .command(27),  secondary: .none),         // ⌘0
        .slot1:                   HotkeyConfig(primary: .command(18),  secondary: .none),         // ⌘1
        .slot2:                   HotkeyConfig(primary: .command(19),  secondary: .none),         // ⌘2
        .slot3:                   HotkeyConfig(primary: .command(20),  secondary: .none),         // ⌘3
        .slot4:                   HotkeyConfig(primary: .command(21),  secondary: .none),         // ⌘4
        .slot5:                   HotkeyConfig(primary: .command(22),  secondary: .none),         // ⌘5
        .slot6:                   HotkeyConfig(primary: .command(23),  secondary: .none),         // ⌘6
        .slot7:                   HotkeyConfig(primary: .command(24),  secondary: .none),         // ⌘7
        .slot8:                   HotkeyConfig(primary: .command(25),  secondary: .none),         // ⌘8
        .slot9:                   HotkeyConfig(primary: .command(26),  secondary: .none),         // ⌘9
        .toggleInputCapture:      HotkeyConfig(primary: .command(46),  secondary: .none),         // ⌘M
        .trainingReset:           HotkeyConfig(primary: .command(17),  secondary: .plain(100)),   // ⌘T, F8
        .trainingToggleRecording: HotkeyConfig(primary: .plain(101),   secondary: .none),         // F9
        .trainingStartPlayback:   HotkeyConfig(primary: .plain(109),   secondary: .none),         // F10
        .toggleTrainingMode:      HotkeyConfig(primary: HotkeyBinding(keyCode: 17, modifierFlags: UInt(NSEvent.ModifierFlags.command.rawValue) | UInt(NSEvent.ModifierFlags.shift.rawValue)), secondary: .none), // ⇧⌘T
        .screenshot:              HotkeyConfig(
                                       primary: HotkeyBinding(keyCode: 1, modifierFlags: UInt(NSEvent.ModifierFlags.command.rawValue) | UInt(NSEvent.ModifierFlags.shift.rawValue)),
                                       secondary: .none,
                                       controller: nil,
                                   ),
    ]

    func controllerBinding(for action: HotkeyAction, source: ControllerHotkeySource) -> ControllerHotkeyBinding {
        if let bound = config[action]?.controller, !bound.isUnset {
            return bound
        }
        return Self.defaultControllerBinding(for: action, source: source)
    }

    func matchesController(_ action: HotkeyAction, gcElementName: String) -> Bool {
        guard let bound = config[action]?.controller, !bound.isUnset, bound.source == .gameController else {
            return gcElementName == Self.defaultControllerBinding(for: action, source: .gameController).identifier
        }
        return bound.identifier == gcElementName
    }

    func matchesController(_ action: HotkeyAction, sdlButtonIndex: Int) -> Bool {
        guard let bound = config[action]?.controller, !bound.isUnset, bound.source == .sdl else {
            let fallback = Self.defaultControllerBinding(for: action, source: .sdl)
            guard !fallback.isUnset else { return false }
            return Int(fallback.identifier) == sdlButtonIndex
        }
        return Int(bound.identifier) == sdlButtonIndex
    }

    func update(_ action: HotkeyAction, primary: HotkeyBinding) {
        config[action]?.primary = primary
        save()
    }

    func update(_ action: HotkeyAction, secondary: HotkeyBinding) {
        config[action]?.secondary = secondary
        save()
    }

    func updateControllerBinding(_ action: HotkeyAction, binding: ControllerHotkeyBinding?) {
        config[action]?.controller = binding
        save()
    }

    func resetHotkeyControllerBinding(_ action: HotkeyAction) {
        config[action]?.controller = Self.defaults[action]?.controller
        save()
    }

    static func defaultControllerBinding(for action: HotkeyAction, source: ControllerHotkeySource) -> ControllerHotkeyBinding {
        switch (action, source) {
        case (.screenshot, .gameController):
            return .gc("Share Button", label: "Share Button")
        case (.screenshot, .sdl):
            return .sdl(13)
        default:
            return .unset
        }
    }

    var availableControllerSources: [ControllerHotkeySource] {
        var sources: [ControllerHotkeySource] = []
        if ControllerService.shared.connectedControllers.contains(where: { $0.gcController != nil }) {
            sources.append(.gameController)
        }
        if ControllerService.shared.connectedControllers.contains(where: { $0.isSDL }) {
            sources.append(.sdl)
        }
        if sources.isEmpty {
            sources = [.gameController, .sdl]
        }
        return sources
    }

    func resetToDefaults() {
        config = Self.defaults
        save()
    }

    func matches(_ action: HotkeyAction, event: NSEvent) -> Bool {
        guard let cfg = config[action] else { return false }
        return cfg.primary.matches(event) || cfg.secondary.matches(event)
    }

    func findConflicts(for binding: HotkeyBinding, excluding action: HotkeyAction) -> [(HotkeyAction, HotkeyBinding)] {
        guard !binding.isUnset else { return [] }
        var conflicts: [(HotkeyAction, HotkeyBinding)] = []
        for (act, cfg) in config {
            guard act != action else { continue }
            if cfg.primary == binding { conflicts.append((act, cfg.primary)) }
            if cfg.secondary == binding { conflicts.append((act, cfg.secondary)) }
        }
        return conflicts
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            AppSettings.setData(Self.storageKey, value: data)
        }
    }
}

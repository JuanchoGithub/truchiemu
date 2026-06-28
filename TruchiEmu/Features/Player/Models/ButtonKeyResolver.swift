import Foundation
import GameController

@MainActor
enum ButtonKeyResolver {

    static func keyLabel(
        for fightDataKey: String,
        systemID: String,
        layout: ArcadeLayout,
        systemControlMappings: [String: [String: String]]?
    ) -> String? {
        let retroBtn = ArcadeButtonMapper.shared.retroButton(
            for: fightDataKey,
            layout: layout,
            systemID: systemID,
            systemControlMappings: systemControlMappings
        )
        guard let retroBtn else { return nil }

        let hasGamepad = ControllerService.shared.connectedControllers.contains { !$0.isKeyboard && $0.gcController != nil }

        if hasGamepad, let gamepadLabel = resolveGamepadLabel(retroBtn: retroBtn, systemID: systemID) {
            return gamepadLabel
        }

        let displayButton = resolveDisplayButton(retroBtn, systemID: systemID)
        return resolveKeyboardLabel(retroBtn: displayButton, systemID: systemID)
    }

    static func allKeyLabels(
        fightDataKeys: [String],
        systemID: String,
        layout: ArcadeLayout,
        systemControlMappings: [String: [String: String]]?
    ) -> [String: String] {
        var labels: [String: String] = [:]
        for key in fightDataKeys {
            if let label = keyLabel(for: key, systemID: systemID, layout: layout, systemControlMappings: systemControlMappings) {
                labels[key] = label
            }
        }
        return labels
    }

    static func consoleButtonLabel(
        for fightDataKey: String,
        systemID: String,
        layout: ArcadeLayout,
        systemControlMappings: [String: [String: String]]?
    ) -> String? {
        let retroBtn = ArcadeButtonMapper.shared.retroButton(
            for: fightDataKey,
            layout: layout,
            systemID: systemID,
            systemControlMappings: systemControlMappings
        )
        return retroBtn?.rawValue.uppercased()
    }

    static func allConsoleButtonLabels(
        fightDataKeys: [String],
        systemID: String,
        layout: ArcadeLayout,
        systemControlMappings: [String: [String: String]]?
    ) -> [String: String] {
        var labels: [String: String] = [:]
        for key in fightDataKeys {
            if let label = consoleButtonLabel(for: key, systemID: systemID, layout: layout, systemControlMappings: systemControlMappings) {
                labels[key] = label
            }
        }
        return labels
    }

    private static let disabledToEnabledButton: [RetroButton: RetroButton] = [
        .x: .a,
        .y: .b,
        .z: .c,
    ]

    static func resolveDisplayButton(_ retroBtn: RetroButton, systemID: String) -> RetroButton {
        let disabled = RetroButton.disabledButtons(for: systemID)
        guard disabled.contains(retroBtn), let fallback = disabledToEnabledButton[retroBtn] else {
            return retroBtn
        }
        return fallback
    }

    private static func resolveKeyboardLabel(retroBtn: RetroButton, systemID: String) -> String? {
        let mapping = ControllerService.shared.keyboardMapping(for: systemID)
        guard let keyCode = mapping.buttons[retroBtn] else { return nil }
        return keyName(for: keyCode)
    }

    private static func resolveGamepadLabel(retroBtn: RetroButton, systemID: String) -> String? {
        let cs = ControllerService.shared
        guard let player = cs.connectedControllers.first(where: { !$0.isKeyboard && $0.gcController != nil }) else {
            return nil
        }
        let mapping = cs.mapping(for: player.mapping.vendorName, systemID: systemID)
        guard let btnMapping = mapping.buttons[retroBtn] else { return nil }
        if let alias = btnMapping.gcElementAlias, !alias.isEmpty { return alias }
        return simplifyGamepadName(btnMapping.gcElementName)
    }

    private static func simplifyGamepadName(_ name: String) -> String {
        let simplified = name
            .replacingOccurrences(of: "Button ", with: "")
            .replacingOccurrences(of: " Bumper", with: "")
            .replacingOccurrences(of: " Trigger", with: "T")
            .replacingOccurrences(of: "Left ", with: "L")
            .replacingOccurrences(of: "Right ", with: "R")
        if simplified.count <= 4 { return simplified }
        return String(simplified.prefix(4))
    }

    private static let keyCodeNames: [UInt16: String] = [
        0:"A", 11:"B", 8:"C", 2:"D", 14:"E", 3:"F", 5:"G", 4:"H", 34:"I", 38:"J",
        40:"K", 37:"L", 46:"M", 45:"N", 31:"O", 35:"P", 12:"Q", 15:"R", 1:"S", 17:"T",
        32:"U", 9:"V", 13:"W", 7:"X", 16:"Y", 6:"Z",
        18:"1", 19:"2", 20:"3", 21:"4", 22:"5", 23:"6", 24:"7", 25:"8", 26:"9", 27:"0",
        36:"Ret", 48:"Tab", 49:"Spc", 53:"Esc",
        51:"Del", 117:"Fwd", 123:"←", 124:"→", 125:"↓", 126:"↑"
    ]

    static func keyName(for keyCode: UInt16) -> String {
        keyCodeNames[keyCode] ?? "K\(keyCode)"
    }
}

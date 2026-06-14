import Foundation

struct ControllerGamepadMapping: Codable {
    var vendorName: String
    var buttons: [RetroButton: GCButtonMapping]
    var leftStickDeadzone: Float
    var rightStickDeadzone: Float

    private enum CodingKeys: String, CodingKey {
        case vendorName, buttons, leftStickDeadzone, rightStickDeadzone
    }

    init(vendorName: String, buttons: [RetroButton: GCButtonMapping], leftStickDeadzone: Float = 0.15, rightStickDeadzone: Float = 0.15) {
        self.vendorName = vendorName
        self.buttons = buttons
        self.leftStickDeadzone = leftStickDeadzone
        self.rightStickDeadzone = rightStickDeadzone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorName = try container.decode(String.self, forKey: .vendorName)
        buttons = try container.decode([RetroButton: GCButtonMapping].self, forKey: .buttons)
        leftStickDeadzone = try container.decodeIfPresent(Float.self, forKey: .leftStickDeadzone) ?? 0.15
        rightStickDeadzone = try container.decodeIfPresent(Float.self, forKey: .rightStickDeadzone) ?? 0.15
    }

    static func defaults(for vendorName: String, systemID: String, handedness: String = "right") -> ControllerGamepadMapping {
        let isLeftHanded = handedness == "left"
        var mapping = ControllerGamepadMapping(vendorName: vendorName, buttons: [:])
        let availableButtons = RetroButton.availableButtons(for: systemID)

        mapping.buttons[.up] = GCButtonMapping(gcElementName: "D-pad (Up)", gcElementAlias: "D-pad (Up)")
        mapping.buttons[.down] = GCButtonMapping(gcElementName: "D-pad (Down)", gcElementAlias: "D-pad (Down)")
        mapping.buttons[.left] = GCButtonMapping(gcElementName: "D-pad (Left)", gcElementAlias: "D-pad (Left)")
        mapping.buttons[.right] = GCButtonMapping(gcElementName: "D-pad (Right)", gcElementAlias: "D-pad (Right)")

        if availableButtons.contains(.a) && availableButtons.contains(.b) && !availableButtons.contains(.x) {
            if isLeftHanded {
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
                mapping.buttons[.turboA] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.turboB] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
            } else {
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
                mapping.buttons[.turboA] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.turboB] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            }

            mapping.buttons[.start] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
            mapping.buttons[.select] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
        }
        else if availableButtons.contains(.x) && availableButtons.contains(.y) {
            if isLeftHanded {
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "X Button", gcElementAlias: "X Button")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Y Button", gcElementAlias: "Y Button")
                mapping.buttons[.x] = GCButtonMapping(gcElementName: "A Button", gcElementAlias: "A Button")
                mapping.buttons[.y] = GCButtonMapping(gcElementName: "B Button", gcElementAlias: "B Button")
            } else {
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "A Button", gcElementAlias: "A Button")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "B Button", gcElementAlias: "B Button")
                mapping.buttons[.x] = GCButtonMapping(gcElementName: "X Button", gcElementAlias: "X Button")
                mapping.buttons[.y] = GCButtonMapping(gcElementName: "Y Button", gcElementAlias: "Y Button")
            }

            mapping.buttons[.l1] = GCButtonMapping(gcElementName: "Left Bumper", gcElementAlias: "Left Bumper")
            mapping.buttons[.r1] = GCButtonMapping(gcElementName: "Right Bumper", gcElementAlias: "Right Bumper")

            if availableButtons.contains(.l2) {
                mapping.buttons[.l2] = GCButtonMapping(gcElementName: "Left Trigger", gcElementAlias: "Left Trigger")
            }
            if availableButtons.contains(.r2) {
                mapping.buttons[.r2] = GCButtonMapping(gcElementName: "Right Trigger", gcElementAlias: "Right Trigger")
            }

            mapping.buttons[.start] = GCButtonMapping(gcElementName: "Menu Button", gcElementAlias: "Menu Button")
            mapping.buttons[.select] = GCButtonMapping(gcElementName: "View Button", gcElementAlias: "View Button")
        }

        if availableButtons.contains(.lStickUp) {
            mapping.buttons[.lStickUp] = GCButtonMapping(gcElementName: "Left Stick (Up)", gcElementAlias: "Left Stick (Up)")
            mapping.buttons[.lStickDown] = GCButtonMapping(gcElementName: "Left Stick (Down)", gcElementAlias: "Left Stick (Down)")
            mapping.buttons[.lStickLeft] = GCButtonMapping(gcElementName: "Left Stick (Left)", gcElementAlias: "Left Stick (Left)")
            mapping.buttons[.lStickRight] = GCButtonMapping(gcElementName: "Left Stick (Right)", gcElementAlias: "Left Stick (Right)")
        }
        if availableButtons.contains(.rStickUp) {
            mapping.buttons[.rStickUp] = GCButtonMapping(gcElementName: "Right Stick (Up)", gcElementAlias: "Right Stick (Up)")
            mapping.buttons[.rStickDown] = GCButtonMapping(gcElementName: "Right Stick (Down)", gcElementAlias: "Right Stick (Down)")
            mapping.buttons[.rStickLeft] = GCButtonMapping(gcElementName: "Right Stick (Left)", gcElementAlias: "Right Stick (Left)")
            mapping.buttons[.rStickRight] = GCButtonMapping(gcElementName: "Right Stick (Right)", gcElementAlias: "Right Stick (Right)")
        }

        if availableButtons.contains(.l3) {
            mapping.buttons[.l3] = GCButtonMapping(gcElementName: "Left Stick Click", gcElementAlias: "Left Stick Click")
        }
        if availableButtons.contains(.r3) {
            mapping.buttons[.r3] = GCButtonMapping(gcElementName: "Right Stick Click", gcElementAlias: "Right Stick Click")
        }

        if availableButtons.contains(.cUp) {
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

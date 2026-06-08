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

        mapping.buttons[.up] = GCButtonMapping(gcElementName: "D-pad Up", gcElementAlias: "Up")
        mapping.buttons[.down] = GCButtonMapping(gcElementName: "D-pad Down", gcElementAlias: "Down")
        mapping.buttons[.left] = GCButtonMapping(gcElementName: "D-pad Left", gcElementAlias: "Left")
        mapping.buttons[.right] = GCButtonMapping(gcElementName: "D-pad Right", gcElementAlias: "Right")

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
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
                mapping.buttons[.x] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.y] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
            } else {
                mapping.buttons[.a] = GCButtonMapping(gcElementName: "Button A", gcElementAlias: "A")
                mapping.buttons[.b] = GCButtonMapping(gcElementName: "Button B", gcElementAlias: "B")
                mapping.buttons[.x] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
                mapping.buttons[.y] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
            }

            mapping.buttons[.l1] = GCButtonMapping(gcElementName: "Left Shoulder", gcElementAlias: "L1")
            mapping.buttons[.r1] = GCButtonMapping(gcElementName: "Right Shoulder", gcElementAlias: "R1")

            if availableButtons.contains(.l2) {
                mapping.buttons[.l2] = GCButtonMapping(gcElementName: "Left Trigger", gcElementAlias: "L2")
            }
            if availableButtons.contains(.r2) {
                mapping.buttons[.r2] = GCButtonMapping(gcElementName: "Right Trigger", gcElementAlias: "R2")
            }

            mapping.buttons[.start] = GCButtonMapping(gcElementName: "Button Menu", gcElementAlias: "Menu")
            mapping.buttons[.select] = GCButtonMapping(gcElementName: "Button Options", gcElementAlias: "Options")
        }

        if ["genesis", "megadrive"].contains(systemID) {
            mapping.buttons[.c] = GCButtonMapping(gcElementName: "Button X", gcElementAlias: "X")
            mapping.buttons[.z] = GCButtonMapping(gcElementName: "Button Y", gcElementAlias: "Y")
        }

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

        if availableButtons.contains(.l3) {
            mapping.buttons[.l3] = GCButtonMapping(gcElementName: "Left Thumbstick Button", gcElementAlias: "L3")
        }
        if availableButtons.contains(.r3) {
            mapping.buttons[.r3] = GCButtonMapping(gcElementName: "Right Thumbstick Button", gcElementAlias: "R3")
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

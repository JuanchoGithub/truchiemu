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

        mapping.buttons[.up] = GCButtonMapping(identifier: .dpadUp, gcElementAlias: "D-pad (Up)")
        mapping.buttons[.down] = GCButtonMapping(identifier: .dpadDown, gcElementAlias: "D-pad (Down)")
        mapping.buttons[.left] = GCButtonMapping(identifier: .dpadLeft, gcElementAlias: "D-pad (Left)")
        mapping.buttons[.right] = GCButtonMapping(identifier: .dpadRight, gcElementAlias: "D-pad (Right)")

        if availableButtons.contains(.a) && availableButtons.contains(.b) && !availableButtons.contains(.x) {
            if isLeftHanded {
                mapping.buttons[.a] = GCButtonMapping(identifier: .faceWest, gcElementAlias: "X")
                mapping.buttons[.b] = GCButtonMapping(identifier: .faceNorth, gcElementAlias: "Y")
                mapping.buttons[.turboA] = GCButtonMapping(identifier: .faceSouth, gcElementAlias: "A")
                mapping.buttons[.turboB] = GCButtonMapping(identifier: .faceEast, gcElementAlias: "B")
            } else {
                mapping.buttons[.a] = GCButtonMapping(identifier: .faceSouth, gcElementAlias: "A")
                mapping.buttons[.b] = GCButtonMapping(identifier: .faceEast, gcElementAlias: "B")
                mapping.buttons[.turboA] = GCButtonMapping(identifier: .faceWest, gcElementAlias: "X")
                mapping.buttons[.turboB] = GCButtonMapping(identifier: .faceNorth, gcElementAlias: "Y")
            }

            mapping.buttons[.start] = GCButtonMapping(identifier: .buttonMenu, gcElementAlias: "Menu")
            mapping.buttons[.select] = GCButtonMapping(identifier: .buttonOptions, gcElementAlias: "Options")
        }
        else if availableButtons.contains(.x) && availableButtons.contains(.y) {
            if isLeftHanded {
                mapping.buttons[.a] = GCButtonMapping(identifier: .faceWest, gcElementAlias: "X Button")
                mapping.buttons[.b] = GCButtonMapping(identifier: .faceNorth, gcElementAlias: "Y Button")
                mapping.buttons[.x] = GCButtonMapping(identifier: .faceSouth, gcElementAlias: "A Button")
                mapping.buttons[.y] = GCButtonMapping(identifier: .faceEast, gcElementAlias: "B Button")
            } else {
                mapping.buttons[.a] = GCButtonMapping(identifier: .faceSouth, gcElementAlias: "A Button")
                mapping.buttons[.b] = GCButtonMapping(identifier: .faceEast, gcElementAlias: "B Button")
                mapping.buttons[.x] = GCButtonMapping(identifier: .faceWest, gcElementAlias: "X Button")
                mapping.buttons[.y] = GCButtonMapping(identifier: .faceNorth, gcElementAlias: "Y Button")
            }

            mapping.buttons[.l1] = GCButtonMapping(identifier: .leftShoulder, gcElementAlias: "Left Bumper")
            mapping.buttons[.r1] = GCButtonMapping(identifier: .rightShoulder, gcElementAlias: "Right Bumper")

            if availableButtons.contains(.l2) {
                mapping.buttons[.l2] = GCButtonMapping(identifier: .leftTrigger, gcElementAlias: "Left Trigger")
            }
            if availableButtons.contains(.r2) {
                mapping.buttons[.r2] = GCButtonMapping(identifier: .rightTrigger, gcElementAlias: "Right Trigger")
            }

            mapping.buttons[.start] = GCButtonMapping(identifier: .buttonMenu, gcElementAlias: "Menu Button")
            mapping.buttons[.select] = GCButtonMapping(identifier: .buttonOptions, gcElementAlias: "View Button")
        }

        if availableButtons.contains(.lStickUp) {
            mapping.buttons[.lStickUp] = GCButtonMapping(identifier: .leftThumbstickUp, gcElementAlias: "Left Stick (Up)")
            mapping.buttons[.lStickDown] = GCButtonMapping(identifier: .leftThumbstickDown, gcElementAlias: "Left Stick (Down)")
            mapping.buttons[.lStickLeft] = GCButtonMapping(identifier: .leftThumbstickLeft, gcElementAlias: "Left Stick (Left)")
            mapping.buttons[.lStickRight] = GCButtonMapping(identifier: .leftThumbstickRight, gcElementAlias: "Left Stick (Right)")
        }
        if availableButtons.contains(.rStickUp) {
            mapping.buttons[.rStickUp] = GCButtonMapping(identifier: .rightThumbstickUp, gcElementAlias: "Right Stick (Up)")
            mapping.buttons[.rStickDown] = GCButtonMapping(identifier: .rightThumbstickDown, gcElementAlias: "Right Stick (Down)")
            mapping.buttons[.rStickLeft] = GCButtonMapping(identifier: .rightThumbstickLeft, gcElementAlias: "Right Stick (Left)")
            mapping.buttons[.rStickRight] = GCButtonMapping(identifier: .rightThumbstickRight, gcElementAlias: "Right Stick (Right)")
        }

        if availableButtons.contains(.l3) {
            mapping.buttons[.l3] = GCButtonMapping(identifier: .leftThumbstickButton, gcElementAlias: "Left Stick Click")
        }
        if availableButtons.contains(.r3) {
            mapping.buttons[.r3] = GCButtonMapping(identifier: .rightThumbstickButton, gcElementAlias: "Right Stick Click")
        }

        if availableButtons.contains(.cUp) {
            if isLeftHanded {
                mapping.buttons[.cUp] = GCButtonMapping(identifier: .dpadUp, gcElementAlias: "Up")
                mapping.buttons[.cDown] = GCButtonMapping(identifier: .dpadDown, gcElementAlias: "Down")
                mapping.buttons[.cLeft] = GCButtonMapping(identifier: .dpadLeft, gcElementAlias: "Left")
                mapping.buttons[.cRight] = GCButtonMapping(identifier: .dpadRight, gcElementAlias: "Right")
            } else {
                mapping.buttons[.cUp] = GCButtonMapping(identifier: .rightThumbstickUp, gcElementAlias: "R Stick Y")
                mapping.buttons[.cDown] = GCButtonMapping(identifier: .rightThumbstickDown, gcElementAlias: "R Stick Y")
                mapping.buttons[.cLeft] = GCButtonMapping(identifier: .rightThumbstickLeft, gcElementAlias: "R Stick X")
                mapping.buttons[.cRight] = GCButtonMapping(identifier: .rightThumbstickRight, gcElementAlias: "R Stick X")
            }
        }

        if availableButtons.contains(.coin1) {
            mapping.buttons[.coin1] = GCButtonMapping(identifier: .faceNorth, gcElementAlias: "Y")
            mapping.buttons[.start1] = GCButtonMapping(identifier: .buttonMenu, gcElementAlias: "Menu")
        }
        if availableButtons.contains(.coin2) {
            mapping.buttons[.coin2] = GCButtonMapping(identifier: .faceWest, gcElementAlias: "X")
            mapping.buttons[.start2] = GCButtonMapping(identifier: .buttonOptions, gcElementAlias: "Options")
        }

        return mapping
    }
}

struct GCButtonMapping: Codable {
    var identifier: GCButtonIdentifier?
    var gcElementName: String?
    var gcElementAlias: String?

    init(identifier: GCButtonIdentifier?, gcElementName: String? = nil, gcElementAlias: String? = nil) {
        self.identifier = identifier
        self.gcElementName = gcElementName
        self.gcElementAlias = gcElementAlias ?? gcElementName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let raw = try? c.decode(RawLegacyGCButtonMapping.self) {
            self.identifier = GCButtonIdentifier(rawValue: raw.identifier ?? "")
            self.gcElementName = raw.gcElementName
            self.gcElementAlias = raw.gcElementAlias
        } else {
            self.identifier = nil
            self.gcElementName = nil
            self.gcElementAlias = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        let raw = RawLegacyGCButtonMapping(
            identifier: identifier?.rawValue,
            gcElementName: gcElementName,
            gcElementAlias: gcElementAlias
        )
        try c.encode(raw)
    }

    private struct RawLegacyGCButtonMapping: Codable {
        var identifier: String?
        var gcElementName: String?
        var gcElementAlias: String?
    }

    static func legacy(gcElementName: String, gcElementAlias: String?) -> GCButtonMapping {
        return GCButtonMapping(identifier: legacyIdentifier(for: gcElementName),
                               gcElementName: gcElementName,
                               gcElementAlias: gcElementAlias ?? gcElementName)
    }

    private static func legacyIdentifier(for name: String) -> GCButtonIdentifier? {
        let mapping: [String: GCButtonIdentifier] = [
            "D-pad (Up)": .dpadUp, "D-pad Up": .dpadUp, "Directional Pad Up": .dpadUp,
            "D-pad (Down)": .dpadDown, "D-pad Down": .dpadDown, "Directional Pad Down": .dpadDown,
            "D-pad (Left)": .dpadLeft, "D-pad Left": .dpadLeft, "Directional Pad Left": .dpadLeft,
            "D-pad (Right)": .dpadRight, "D-pad Right": .dpadRight, "Directional Pad Right": .dpadRight,
            "Button A": .faceSouth, "A Button": .faceSouth, "Cross": .faceSouth, "Button 1": .faceSouth,
            "Button B": .faceEast, "B Button": .faceEast, "Circle": .faceEast, "Button 2": .faceEast,
            "Button X": .faceWest, "X Button": .faceWest, "Square": .faceWest, "Button 3": .faceWest,
            "Button Y": .faceNorth, "Y Button": .faceNorth, "Triangle": .faceNorth, "Button 4": .faceNorth,
            "Left Bumper": .leftShoulder, "L1": .leftShoulder,
            "Right Bumper": .rightShoulder, "R1": .rightShoulder,
            "Left Trigger": .leftTrigger, "L2": .leftTrigger, "LT": .leftTrigger,
            "Right Trigger": .rightTrigger, "R2": .rightTrigger, "RT": .rightTrigger,
            "Left Stick Click": .leftThumbstickButton, "L3": .leftThumbstickButton,
            "Right Stick Click": .rightThumbstickButton, "R3": .rightThumbstickButton,
            "Menu Button": .buttonMenu, "Button Menu": .buttonMenu, "Menu": .buttonMenu, "Start": .buttonMenu,
            "View Button": .buttonOptions, "Button Options": .buttonOptions, "Options": .buttonOptions, "Select": .buttonOptions,
            "Share Button": .buttonShare, "Share": .buttonShare,
            "Left Stick (Up)": .leftThumbstickUp, "Left Stick Up": .leftThumbstickUp,
            "Left Stick (Down)": .leftThumbstickDown, "Left Stick Down": .leftThumbstickDown,
            "Left Stick (Left)": .leftThumbstickLeft, "Left Stick Left": .leftThumbstickLeft,
            "Left Stick (Right)": .leftThumbstickRight, "Left Stick Right": .leftThumbstickRight,
            "Right Stick (Up)": .rightThumbstickUp, "Right Stick Up": .rightThumbstickUp,
            "Right Stick (Down)": .rightThumbstickDown, "Right Stick Down": .rightThumbstickDown,
            "Right Stick (Left)": .rightThumbstickLeft, "Right Stick Left": .rightThumbstickLeft,
            "Right Stick (Right)": .rightThumbstickRight, "Right Stick Right": .rightThumbstickRight,
        ]
        return mapping[name]
    }
}

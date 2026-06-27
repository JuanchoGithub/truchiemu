import Foundation

struct SDLButtonMapping: Codable {
    var sdlButtonIndex: Int
    var sdlButtonAlias: String?

    private enum CodingKeys: String, CodingKey {
        case sdlButtonIndex, sdlButtonAlias
    }

    init(sdlButtonIndex: Int, sdlButtonAlias: String? = nil) {
        self.sdlButtonIndex = sdlButtonIndex
        self.sdlButtonAlias = sdlButtonAlias
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sdlButtonIndex = try container.decode(Int.self, forKey: .sdlButtonIndex)
        sdlButtonAlias = try container.decodeIfPresent(String.self, forKey: .sdlButtonAlias)
    }
}

struct SDLControllerMapping: Codable {
    var vendorName: String
    var buttons: [RetroButton: SDLButtonMapping]
    var leftStickDeadzone: Float
    var rightStickDeadzone: Float

    private enum CodingKeys: String, CodingKey {
        case vendorName, buttons, leftStickDeadzone, rightStickDeadzone
    }

    init(vendorName: String, buttons: [RetroButton: SDLButtonMapping], leftStickDeadzone: Float = 0.15, rightStickDeadzone: Float = 0.15) {
        self.vendorName = vendorName
        self.buttons = buttons
        self.leftStickDeadzone = leftStickDeadzone
        self.rightStickDeadzone = rightStickDeadzone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorName = try container.decode(String.self, forKey: .vendorName)
        buttons = try container.decode([RetroButton: SDLButtonMapping].self, forKey: .buttons)
        leftStickDeadzone = try container.decodeIfPresent(Float.self, forKey: .leftStickDeadzone) ?? 0.15
        rightStickDeadzone = try container.decodeIfPresent(Float.self, forKey: .rightStickDeadzone) ?? 0.15
    }

    static func defaults(for systemID: String) -> SDLControllerMapping {
        var mapping = SDLControllerMapping(vendorName: "Standard HID Gamepad", buttons: [:])

        mapping.buttons[.up] = SDLButtonMapping(sdlButtonIndex: 11, sdlButtonAlias: "D-Pad Up")
        mapping.buttons[.down] = SDLButtonMapping(sdlButtonIndex: 12, sdlButtonAlias: "D-Pad Down")
        mapping.buttons[.left] = SDLButtonMapping(sdlButtonIndex: 13, sdlButtonAlias: "D-Pad Left")
        mapping.buttons[.right] = SDLButtonMapping(sdlButtonIndex: 14, sdlButtonAlias: "D-Pad Right")

        mapping.buttons[.a] = SDLButtonMapping(sdlButtonIndex: 0, sdlButtonAlias: "A (Bottom)")
        mapping.buttons[.b] = SDLButtonMapping(sdlButtonIndex: 1, sdlButtonAlias: "B (Right)")
        mapping.buttons[.x] = SDLButtonMapping(sdlButtonIndex: 2, sdlButtonAlias: "X (Left)")
        mapping.buttons[.y] = SDLButtonMapping(sdlButtonIndex: 3, sdlButtonAlias: "Y (Top)")

        mapping.buttons[.l1] = SDLButtonMapping(sdlButtonIndex: 4, sdlButtonAlias: "Left Bumper")
        mapping.buttons[.r1] = SDLButtonMapping(sdlButtonIndex: 5, sdlButtonAlias: "Right Bumper")
        mapping.buttons[.l2] = SDLButtonMapping(sdlButtonIndex: 6, sdlButtonAlias: "Left Trigger")
        mapping.buttons[.r2] = SDLButtonMapping(sdlButtonIndex: 7, sdlButtonAlias: "Right Trigger")

        mapping.buttons[.select] = SDLButtonMapping(sdlButtonIndex: 8, sdlButtonAlias: "Select")
        mapping.buttons[.start] = SDLButtonMapping(sdlButtonIndex: 9, sdlButtonAlias: "Start")

        mapping.buttons[.l3] = SDLButtonMapping(sdlButtonIndex: 10, sdlButtonAlias: "Left Stick Click")
        mapping.buttons[.r3] = SDLButtonMapping(sdlButtonIndex: 11, sdlButtonAlias: "Right Stick Click")

        let availableButtons = RetroButton.availableButtons(for: systemID)

        if availableButtons.contains(.lStickUp) {
            mapping.buttons[.lStickUp] = SDLButtonMapping(sdlButtonIndex: 0, sdlButtonAlias: "Left Stick (Up)")
            mapping.buttons[.lStickDown] = SDLButtonMapping(sdlButtonIndex: 1, sdlButtonAlias: "Left Stick (Down)")
            mapping.buttons[.lStickLeft] = SDLButtonMapping(sdlButtonIndex: 2, sdlButtonAlias: "Left Stick (Left)")
            mapping.buttons[.lStickRight] = SDLButtonMapping(sdlButtonIndex: 3, sdlButtonAlias: "Left Stick (Right)")
        }
        if availableButtons.contains(.rStickUp) {
            mapping.buttons[.rStickUp] = SDLButtonMapping(sdlButtonIndex: 0, sdlButtonAlias: "Right Stick (Up)")
            mapping.buttons[.rStickDown] = SDLButtonMapping(sdlButtonIndex: 1, sdlButtonAlias: "Right Stick (Down)")
            mapping.buttons[.rStickLeft] = SDLButtonMapping(sdlButtonIndex: 2, sdlButtonAlias: "Right Stick (Left)")
            mapping.buttons[.rStickRight] = SDLButtonMapping(sdlButtonIndex: 3, sdlButtonAlias: "Right Stick (Right)")
        }

        if availableButtons.contains(.cUp) {
            mapping.buttons[.cUp] = SDLButtonMapping(sdlButtonIndex: 2, sdlButtonAlias: "C Stick (Up)")
            mapping.buttons[.cDown] = SDLButtonMapping(sdlButtonIndex: 2, sdlButtonAlias: "C Stick (Down)")
            mapping.buttons[.cLeft] = SDLButtonMapping(sdlButtonIndex: 3, sdlButtonAlias: "C Stick (Left)")
            mapping.buttons[.cRight] = SDLButtonMapping(sdlButtonIndex: 3, sdlButtonAlias: "C Stick (Right)")
        }

        if availableButtons.contains(.turboA) {
            mapping.buttons[.turboA] = SDLButtonMapping(sdlButtonIndex: 0, sdlButtonAlias: "Turbo A")
            mapping.buttons[.turboB] = SDLButtonMapping(sdlButtonIndex: 1, sdlButtonAlias: "Turbo B")
        }
        if availableButtons.contains(.turboX) {
            mapping.buttons[.turboX] = SDLButtonMapping(sdlButtonIndex: 2, sdlButtonAlias: "Turbo X")
            mapping.buttons[.turboY] = SDLButtonMapping(sdlButtonIndex: 3, sdlButtonAlias: "Turbo Y")
        }

        if availableButtons.contains(.coin1) {
            mapping.buttons[.coin1] = SDLButtonMapping(sdlButtonIndex: 8, sdlButtonAlias: "Coin 1")
            mapping.buttons[.start1] = SDLButtonMapping(sdlButtonIndex: 9, sdlButtonAlias: "Start 1")
        }
        if availableButtons.contains(.coin2) {
            mapping.buttons[.coin2] = SDLButtonMapping(sdlButtonIndex: 8, sdlButtonAlias: "Coin 2")
            mapping.buttons[.start2] = SDLButtonMapping(sdlButtonIndex: 9, sdlButtonAlias: "Start 2")
        }

        return mapping
    }
}

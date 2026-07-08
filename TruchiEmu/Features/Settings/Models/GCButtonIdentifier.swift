import Foundation
import GameController

enum GCButtonIdentifier: String, Codable, Hashable {
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case faceSouth, faceEast, faceWest, faceNorth
    case leftShoulder, rightShoulder
    case leftTrigger, rightTrigger
    case leftThumbstickButton, rightThumbstickButton
    case buttonMenu, buttonOptions, buttonHome, buttonShare
    case leftThumbstickUp, leftThumbstickDown, leftThumbstickLeft, leftThumbstickRight
    case rightThumbstickUp, rightThumbstickDown, rightThumbstickLeft, rightThumbstickRight
    case vendorSpecific

    static func vendor(label: String) -> GCButtonIdentifier {
        return .vendorSpecific
    }
}

extension GCButtonIdentifier {
    func matches(element: GCControllerElement, extendedGamepad: GCExtendedGamepad?) -> Bool {
        switch self {
        case .dpadUp:
            if let dpad = extendedGamepad?.dpad, element === dpad.up { return true }
            return matchesByName(element, candidates: Self.dpadUpAliases)
        case .dpadDown:
            if let dpad = extendedGamepad?.dpad, element === dpad.down { return true }
            return matchesByName(element, candidates: Self.dpadDownAliases)
        case .dpadLeft:
            if let dpad = extendedGamepad?.dpad, element === dpad.left { return true }
            return matchesByName(element, candidates: Self.dpadLeftAliases)
        case .dpadRight:
            if let dpad = extendedGamepad?.dpad, element === dpad.right { return true }
            return matchesByName(element, candidates: Self.dpadRightAliases)
        case .faceSouth:
            if let btn = extendedGamepad?.buttonA, element === btn { return true }
            return matchesByName(element, candidates: Self.faceSouthAliases)
        case .faceEast:
            if let btn = extendedGamepad?.buttonB, element === btn { return true }
            return matchesByName(element, candidates: Self.faceEastAliases)
        case .faceWest:
            if let btn = extendedGamepad?.buttonX, element === btn { return true }
            return matchesByName(element, candidates: Self.faceWestAliases)
        case .faceNorth:
            if let btn = extendedGamepad?.buttonY, element === btn { return true }
            return matchesByName(element, candidates: Self.faceNorthAliases)
        case .leftShoulder:
            if let btn = extendedGamepad?.leftShoulder, element === btn { return true }
            return matchesByName(element, candidates: Self.leftShoulderAliases)
        case .rightShoulder:
            if let btn = extendedGamepad?.rightShoulder, element === btn { return true }
            return matchesByName(element, candidates: Self.rightShoulderAliases)
        case .leftTrigger:
            if let btn = extendedGamepad?.leftTrigger, element === btn { return true }
            return matchesByName(element, candidates: Self.leftTriggerAliases)
        case .rightTrigger:
            if let btn = extendedGamepad?.rightTrigger, element === btn { return true }
            return matchesByName(element, candidates: Self.rightTriggerAliases)
        case .leftThumbstickButton:
            if let btn = extendedGamepad?.leftThumbstickButton, element === btn { return true }
            return matchesByName(element, candidates: Self.leftThumbstickButtonAliases)
        case .rightThumbstickButton:
            if let btn = extendedGamepad?.rightThumbstickButton, element === btn { return true }
            return matchesByName(element, candidates: Self.rightThumbstickButtonAliases)
        case .buttonMenu:
            if let btn = extendedGamepad?.buttonMenu, element === btn { return true }
            return matchesByName(element, candidates: Self.buttonMenuAliases)
        case .buttonOptions:
            if let btn = extendedGamepad?.buttonOptions, element === btn { return true }
            return matchesByName(element, candidates: Self.buttonOptionsAliases)
        case .buttonHome:
            if let btn = extendedGamepad?.buttonHome, element === btn { return true }
            return matchesByName(element, candidates: Self.buttonHomeAliases)
        case .buttonShare:
            if let share = (extendedGamepad as? GCXboxGamepad)?.buttonShare, element === share { return true }
            return matchesByName(element, candidates: Self.buttonShareAliases)
        case .leftThumbstickUp:
            if let stick = extendedGamepad?.leftThumbstick, element === stick.up { return true }
            return matchesByName(element, candidates: Self.leftStickUpAliases)
        case .leftThumbstickDown:
            if let stick = extendedGamepad?.leftThumbstick, element === stick.down { return true }
            return matchesByName(element, candidates: Self.leftStickDownAliases)
        case .leftThumbstickLeft:
            if let stick = extendedGamepad?.leftThumbstick, element === stick.left { return true }
            return matchesByName(element, candidates: Self.leftStickLeftAliases)
        case .leftThumbstickRight:
            if let stick = extendedGamepad?.leftThumbstick, element === stick.right { return true }
            return matchesByName(element, candidates: Self.leftStickRightAliases)
        case .rightThumbstickUp:
            if let stick = extendedGamepad?.rightThumbstick, element === stick.up { return true }
            return matchesByName(element, candidates: Self.rightStickUpAliases)
        case .rightThumbstickDown:
            if let stick = extendedGamepad?.rightThumbstick, element === stick.down { return true }
            return matchesByName(element, candidates: Self.rightStickDownAliases)
        case .rightThumbstickLeft:
            if let stick = extendedGamepad?.rightThumbstick, element === stick.left { return true }
            return matchesByName(element, candidates: Self.rightStickLeftAliases)
        case .rightThumbstickRight:
            if let stick = extendedGamepad?.rightThumbstick, element === stick.right { return true }
            return matchesByName(element, candidates: Self.rightStickRightAliases)
        case .vendorSpecific:
            return false
        }
    }

    private func matchesByName(_ element: GCControllerElement, candidates: Set<String>) -> Bool {
        if candidates.contains(element.localizedName ?? "") { return true }
        if let unmapped = element.unmappedLocalizedName, candidates.contains(unmapped) { return true }
        if let sf = element.sfSymbolsName, candidates.contains(sf) { return true }
        for alias in element.aliases where candidates.contains(alias) { return true }
        return false
    }

    static func identify(element: GCControllerElement, extendedGamepad: GCExtendedGamepad?) -> (GCButtonIdentifier, String) {
        if let gp = extendedGamepad {
            if let dpad = element as? GCControllerDirectionPad {
                if element === dpad { return (.dpadUp, "D-pad") }
            }
            if element === gp.dpad.up { return (.dpadUp, "D-pad (Up)") }
            if element === gp.dpad.down { return (.dpadDown, "D-pad (Down)") }
            if element === gp.dpad.left { return (.dpadLeft, "D-pad (Left)") }
            if element === gp.dpad.right { return (.dpadRight, "D-pad (Right)") }
            if element === gp.buttonA { return (.faceSouth, "Button A") }
            if element === gp.buttonB { return (.faceEast, "Button B") }
            if element === gp.buttonX { return (.faceWest, "Button X") }
            if element === gp.buttonY { return (.faceNorth, "Button Y") }
            if element === gp.leftShoulder { return (.leftShoulder, "Left Bumper") }
            if element === gp.rightShoulder { return (.rightShoulder, "Right Bumper") }
            if element === gp.leftTrigger { return (.leftTrigger, "Left Trigger") }
            if element === gp.rightTrigger { return (.rightTrigger, "Right Trigger") }
            if let l3 = gp.leftThumbstickButton, element === l3 { return (.leftThumbstickButton, "Left Stick Click") }
            if let r3 = gp.rightThumbstickButton, element === r3 { return (.rightThumbstickButton, "Right Stick Click") }
            if element === gp.buttonMenu { return (.buttonMenu, "Menu Button") }
            if let options = gp.buttonOptions, element === options { return (.buttonOptions, "View Button") }
            if let home = gp.buttonHome, element === home { return (.buttonHome, "Home Button") }
            if let share = (gp as? GCXboxGamepad)?.buttonShare, element === share { return (.buttonShare, "Share Button") }
            if element === gp.leftThumbstick.up { return (.leftThumbstickUp, "Left Stick (Up)") }
            if element === gp.leftThumbstick.down { return (.leftThumbstickDown, "Left Stick (Down)") }
            if element === gp.leftThumbstick.left { return (.leftThumbstickLeft, "Left Stick (Left)") }
            if element === gp.leftThumbstick.right { return (.leftThumbstickRight, "Left Stick (Right)") }
            if element === gp.rightThumbstick.up { return (.rightThumbstickUp, "Right Stick (Up)") }
            if element === gp.rightThumbstick.down { return (.rightThumbstickDown, "Right Stick (Down)") }
            if element === gp.rightThumbstick.left { return (.rightThumbstickLeft, "Right Stick (Left)") }
            if element === gp.rightThumbstick.right { return (.rightThumbstickRight, "Right Stick (Right)") }
        }
        let label = element.localizedName ?? "Button"
        return (.vendorSpecific, label)
    }
}

extension GCButtonIdentifier {
    static let dpadUpAliases: Set<String> = ["D-pad (Up)", "D-pad Up", "Directional Pad Up", "Dpad Up", "Up"]
    static let dpadDownAliases: Set<String> = ["D-pad (Down)", "D-pad Down", "Directional Pad Down", "Dpad Down", "Down"]
    static let dpadLeftAliases: Set<String> = ["D-pad (Left)", "D-pad Left", "Directional Pad Left", "Dpad Left", "Left"]
    static let dpadRightAliases: Set<String> = ["D-pad (Right)", "D-pad Right", "Directional Pad Right", "Dpad Right", "Right"]
    static let faceSouthAliases: Set<String> = ["Button A", "A Button", "A", "Cross", "Button 1", "B"]
    static let faceEastAliases: Set<String> = ["Button B", "B Button", "B", "Circle", "Button 2", "A"]
    static let faceWestAliases: Set<String> = ["Button X", "X Button", "X", "Square", "Button 3", "Y"]
    static let faceNorthAliases: Set<String> = ["Button Y", "Y Button", "Y", "Triangle", "Button 4", "X"]
    static let leftShoulderAliases: Set<String> = ["Left Bumper", "L1", "Left Shoulder", "Shoulder Left"]
    static let rightShoulderAliases: Set<String> = ["Right Bumper", "R1", "Right Shoulder", "Shoulder Right"]
    static let leftTriggerAliases: Set<String> = ["Left Trigger", "L2", "Trigger Left", "LT"]
    static let rightTriggerAliases: Set<String> = ["Right Trigger", "R2", "Trigger Right", "RT"]
    static let leftThumbstickButtonAliases: Set<String> = ["Left Stick Click", "L3", "Left Thumbstick Button"]
    static let rightThumbstickButtonAliases: Set<String> = ["Right Stick Click", "R3", "Right Thumbstick Button"]
    static let buttonMenuAliases: Set<String> = ["Menu Button", "Button Menu", "Menu", "Start", "Button Start"]
    static let buttonOptionsAliases: Set<String> = ["View Button", "Button Options", "Options", "Select", "Button Select", "Back"]
    static let buttonHomeAliases: Set<String> = ["Home Button", "Button Home", "Home", "Guide", "Xbox Button", "PS Button"]
    static let buttonShareAliases: Set<String> = ["Share Button", "Button Share", "Share", "Touchpad", "Create"]
    static let leftStickUpAliases: Set<String> = ["Left Stick (Up)", "Left Stick Up", "Left Thumbstick Up"]
    static let leftStickDownAliases: Set<String> = ["Left Stick (Down)", "Left Stick Down", "Left Thumbstick Down"]
    static let leftStickLeftAliases: Set<String> = ["Left Stick (Left)", "Left Stick Left", "Left Thumbstick Left"]
    static let leftStickRightAliases: Set<String> = ["Left Stick (Right)", "Left Stick Right", "Left Thumbstick Right"]
    static let rightStickUpAliases: Set<String> = ["Right Stick (Up)", "Right Stick Up", "Right Thumbstick Up"]
    static let rightStickDownAliases: Set<String> = ["Right Stick (Down)", "Right Stick Down", "Right Thumbstick Down"]
    static let rightStickLeftAliases: Set<String> = ["Right Stick (Left)", "Right Stick Left", "Right Thumbstick Left"]
    static let rightStickRightAliases: Set<String> = ["Right Stick (Right)", "Right Stick Right", "Right Thumbstick Right"]
}

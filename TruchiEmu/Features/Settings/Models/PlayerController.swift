import Foundation
import GameController
import AppKit

extension NSImage {
    var withTintColor: NSImage {
        let image = self.copy() as! NSImage
        image.isTemplate = true
        return image
    }
}

struct PlayerController: Identifiable {
    let id: UUID
    var assignedPlayers: Set<Int>
    var gcController: GCController?
    var mapping: ControllerGamepadMapping
    var sortOrder: Int
    var productCategory: String
    var isKeyboard: Bool
    var sdlInstanceID: Int32?
    var sdlMapping: SDLControllerMapping?
    var sdlName: String?
    var identityKey: ControllerIdentityKey?

    var primaryPlayer: Int { assignedPlayers.min() ?? 1 }
    var isSDL: Bool { sdlInstanceID != nil }
    var name: String {
        if isKeyboard { return "Keyboard" }
        if isSDL { return sdlName ?? "SDL Controller" }
        return gcController?.vendorName ?? "Player \(primaryPlayer)"
    }
    var isConnected: Bool { gcController != nil || isKeyboard || isSDL }

    var typeIconName: String {
        if isKeyboard { return "Keyboard" }
        switch productCategory {
        case "DualSense": return "ControllerDualSense"
        case "DualShock4": return "ControllerDualShock4"
        case "XboxOne": return "ControllerXbox"
        case "MFi": return "ControllerMFi"
        case "ArcadeStick": return "ControllerArcadeStick"
        default: return "ControllerHID"
        }
    }

    var typeIcon: NSImage? {
        Bundle.main.image(forResource: typeIconName)?.withTintColor
    }

    init(id: UUID = UUID(), assignedPlayers: Set<Int>, gcController: GCController? = nil, mapping: ControllerGamepadMapping, sortOrder: Int = 0, productCategory: String = "", isKeyboard: Bool = false, sdlInstanceID: Int32? = nil, sdlMapping: SDLControllerMapping? = nil, sdlName: String? = nil, identityKey: ControllerIdentityKey? = nil) {
        self.id = id
        self.assignedPlayers = assignedPlayers
        self.gcController = gcController
        self.mapping = mapping
        self.sortOrder = sortOrder
        self.productCategory = productCategory
        self.isKeyboard = isKeyboard
        self.sdlInstanceID = sdlInstanceID
        self.sdlMapping = sdlMapping
        self.sdlName = sdlName
        self.identityKey = identityKey
    }
}

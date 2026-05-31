import Foundation

enum RetroButton: String, Codable, CaseIterable {
    case up, down, left, right
    case start, select

    case a, b

    case x, y, c, z

    case l1, l2, l3
    case r1, r2, r3

    case coin1, coin2, coin3, coin4, start1, start2, start3, start4

    case turboA, turboB
    case turboX, turboY

    case lStickUp, lStickDown, lStickLeft, lStickRight
    case rStickUp, rStickDown, rStickLeft, rStickRight

    case cUp, cDown, cLeft, cRight

    case pause, reset
    case space

    case mouseLeft, mouseRight, mouseMiddle
    case mouseX, mouseY
    case mouseScrollUp, mouseScrollDown

    func displayName(for systemID: String? = nil, coreID: String? = nil) -> String {
        if let coreID = coreID, let label = CoreButtonOverride.shared.label(for: self, coreID: coreID) {
            return label
        }
        if let systemID = systemID, let label = CoreButtonOverride.shared.label(for: self, systemID: systemID) {
            return label
        }
        return displayName
    }

    var displayName: String {
        switch self {
        case .up:    return LocalizationManager.shared.localized("controller.button.up")
        case .down:  return LocalizationManager.shared.localized("controller.button.down")
        case .left:  return LocalizationManager.shared.localized("controller.button.left")
        case .right: return LocalizationManager.shared.localized("controller.button.right")
        case .a:     return LocalizationManager.shared.localized("controller.button.a")
        case .b:     return LocalizationManager.shared.localized("controller.button.b")
        case .c:     return LocalizationManager.shared.localized("controller.button.c")
        case .x:     return LocalizationManager.shared.localized("controller.button.x")
        case .y:     return LocalizationManager.shared.localized("controller.button.y")
        case .z:     return LocalizationManager.shared.localized("controller.button.z")
        case .start: return LocalizationManager.shared.localized("controller.button.start")
        case .select:return LocalizationManager.shared.localized("controller.button.select")
        case .l1:    return LocalizationManager.shared.localized("controller.button.l1")
        case .l2:    return LocalizationManager.shared.localized("controller.button.l2")
        case .l3:    return LocalizationManager.shared.localized("controller.button.l3")
        case .r1:    return LocalizationManager.shared.localized("controller.button.r1")
        case .r2:    return LocalizationManager.shared.localized("controller.button.r2")
        case .r3:    return LocalizationManager.shared.localized("controller.button.r3")
        case .coin1: return LocalizationManager.shared.localized("controller.button.coin1")
        case .coin2: return LocalizationManager.shared.localized("controller.button.coin2")
        case .coin3: return LocalizationManager.shared.localized("controller.button.coin3")
        case .coin4: return LocalizationManager.shared.localized("controller.button.coin4")
        case .start1: return LocalizationManager.shared.localized("controller.button.start1")
        case .start2: return LocalizationManager.shared.localized("controller.button.start2")
        case .start3: return LocalizationManager.shared.localized("controller.button.start3")
        case .start4: return LocalizationManager.shared.localized("controller.button.start4")
        case .lStickUp: return LocalizationManager.shared.localized("controller.button.lStickUp")
        case .lStickDown: return LocalizationManager.shared.localized("controller.button.lStickDown")
        case .lStickLeft: return LocalizationManager.shared.localized("controller.button.lStickLeft")
        case .lStickRight: return LocalizationManager.shared.localized("controller.button.lStickRight")
        case .rStickUp: return LocalizationManager.shared.localized("controller.button.rStickUp")
        case .rStickDown: return LocalizationManager.shared.localized("controller.button.rStickDown")
        case .rStickLeft: return LocalizationManager.shared.localized("controller.button.rStickLeft")
        case .rStickRight: return LocalizationManager.shared.localized("controller.button.rStickRight")
        case .cUp:    return LocalizationManager.shared.localized("controller.button.cUp")
        case .cDown:  return LocalizationManager.shared.localized("controller.button.cDown")
        case .cLeft:  return LocalizationManager.shared.localized("controller.button.cLeft")
        case .cRight: return LocalizationManager.shared.localized("controller.button.cRight")
        case .pause:  return LocalizationManager.shared.localized("controller.button.pause")
        case .reset:  return LocalizationManager.shared.localized("controller.button.reset")
        case .turboA: return LocalizationManager.shared.localized("controller.button.turboA")
        case .turboB: return LocalizationManager.shared.localized("controller.button.turboB")
        case .turboX: return LocalizationManager.shared.localized("controller.button.turboX")
        case .turboY: return LocalizationManager.shared.localized("controller.button.turboY")
        case .space:  return LocalizationManager.shared.localized("controller.button.space")
        case .mouseLeft: return LocalizationManager.shared.localized("controller.button.mouseLeft")
        case .mouseRight: return LocalizationManager.shared.localized("controller.button.mouseRight")
        case .mouseMiddle: return LocalizationManager.shared.localized("controller.button.mouseMiddle")
        case .mouseX: return LocalizationManager.shared.localized("controller.button.mouseX")
        case .mouseY: return LocalizationManager.shared.localized("controller.button.mouseY")
        case .mouseScrollUp: return LocalizationManager.shared.localized("controller.button.mouseScrollUp")
        case .mouseScrollDown: return LocalizationManager.shared.localized("controller.button.mouseScrollDown")
        }
    }

    static func availableButtons(for systemID: String, coreID: String? = nil) -> [RetroButton] {
        var base = CoreButtonOverride.shared.buttons(for: systemID, coreID: coreID)
        let turbos = CoreButtonOverride.shared.turboButtons(for: systemID)
        for turbo in turbos where !base.contains(turbo) {
            base.append(turbo)
        }
        if let descriptors = InputDescriptorsManager.shared.availableButtons(for: systemID) {
            let extras = descriptors.filter { !base.contains($0) }
            base += extras
        }
        
        // Sort alphabetically by display name
        return base.sorted { 
            $0.displayName(for: systemID, coreID: coreID) < 
            $1.displayName(for: systemID, coreID: coreID) 
        }
    }

    func retroID(for systemID: String, coreID: String? = nil) -> Int32 {
        if let coreID = coreID, let override = CoreButtonOverride.shared.retroID(for: self, coreID: coreID) {
            return override
        }
        if let identity = CoreButtonOverride.identityID(for: self) {
            return identity
        }
        switch self {
        case .c:
            if ["genesis", "megadrive", "saturn", "32x"].contains(systemID.lowercased()) { return 8 }
            return -1
        case .z:
            if ["genesis", "megadrive", "saturn", "32x"].contains(systemID.lowercased()) { return 11 }
            return 12
        case .coin1: return 2
        case .start1: return 3
        case .coin2: return 4
        case .start2: return 5
        case .coin3: return 6
        case .start3: return 7
        case .coin4: return 8
        case .start4: return 9
        default: return -1
        }
    }

    var isAnalog: Bool {
        return self == .lStickUp || self == .lStickDown || self == .lStickLeft || self == .lStickRight ||
               self == .rStickUp || self == .rStickDown || self == .rStickLeft || self == .rStickRight ||
               self == .cUp || self == .cDown || self == .cLeft || self == .cRight ||
               self == .mouseX || self == .mouseY
    }

    var analogInfo: (index: Int32, id: Int32, sign: Float)? {
        switch self {
        case .lStickUp:    return (0, 1, -1.0)
        case .lStickDown:  return (0, 1, 1.0)
        case .lStickLeft:  return (0, 0, -1.0)
        case .lStickRight: return (0, 0, 1.0)
        case .rStickUp:    return (1, 1, -1.0)
        case .rStickDown:  return (1, 1, 1.0)
        case .rStickLeft:  return (1, 0, -1.0)
        case .rStickRight: return (1, 0, 1.0)
        case .cUp:     return (1, 1, -1.0)
        case .cDown:   return (1, 1, 1.0)
        case .cLeft:   return (1, 0, -1.0)
        case .cRight:  return (1, 0, 1.0)
        case .mouseX:  return (2, 0, 1.0)
        case .mouseY:  return (2, 1, 1.0)
        default: return nil
        }
    }

    var isTurbo: Bool {
        return self == .turboA || self == .turboB || self == .turboX || self == .turboY
    }

    var turboBaseButton: RetroButton? {
        switch self {
        case .turboA: return .a
        case .turboB: return .b
        case .turboX: return .x
        case .turboY: return .y
        default: return nil
        }
    }

}

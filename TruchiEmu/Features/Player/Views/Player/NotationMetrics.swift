import SwiftUI
import AppKit

enum NotationMetrics {
    static let directionSize: CGFloat = 26
    static let buttonSize: CGFloat = 29
    static let motionWidth: CGFloat = 30
    static let motionHeight: CGFloat = 26
    static let waitDotSize: CGFloat = 8
    static let badgeSize: CGFloat = 11
    static let tokenSpacing: CGFloat = 5
    static let stepSpacing: CGFloat = 8
    static let borderWidth: CGFloat = 1.5

    static let punchFill = Color(.sRGB, red: 1.0, green: 0.843, blue: 0.0, opacity: 1.0)
    static let kickFill = Color(.sRGB, red: 0.898, green: 0.224, blue: 0.208, opacity: 1.0)
    static let airFill = Color(.sRGB, red: 0.392, green: 0.710, blue: 0.965, opacity: 1.0)
    static let grappleFill = Color(.sRGB, red: 0.553, green: 0.431, blue: 0.388, opacity: 1.0)
    static let blockFill = Color(.sRGB, red: 0.220, green: 0.745, blue: 0.973, opacity: 1.0)
    static let weaponFill = Color(.sRGB, red: 0.471, green: 0.565, blue: 0.612, opacity: 1.0)

    static let punchFillDimmed = Color(.sRGB, red: 0.5, green: 0.42, blue: 0.0, opacity: 0.4)
    static let kickFillDimmed = Color(.sRGB, red: 0.45, green: 0.11, blue: 0.1, opacity: 0.4)
    static let airFillDimmed = Color(.sRGB, red: 0.196, green: 0.355, blue: 0.48, opacity: 0.4)
    static let grappleFillDimmed = Color(.sRGB, red: 0.276, green: 0.216, blue: 0.194, opacity: 0.4)
    static let blockFillDimmed = Color(.sRGB, red: 0.11, green: 0.373, blue: 0.487, opacity: 0.4)
    static let weaponFillDimmed = Color(.sRGB, red: 0.235, green: 0.282, blue: 0.306, opacity: 0.4)

    static let punchFillNS = NSColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0)
    static let kickFillNS = NSColor(red: 0.898, green: 0.224, blue: 0.208, alpha: 1.0)
    static let airFillNS = NSColor(red: 0.392, green: 0.710, blue: 0.965, alpha: 1.0)
    static let grappleFillNS = NSColor(red: 0.553, green: 0.431, blue: 0.388, alpha: 1.0)
    static let blockFillNS = NSColor(red: 0.220, green: 0.745, blue: 0.973, alpha: 1.0)
    static let weaponFillNS = NSColor(red: 0.471, green: 0.565, blue: 0.612, alpha: 1.0)

    static let punchFillDimmedNS = NSColor(red: 0.5, green: 0.42, blue: 0.0, alpha: 0.4)
    static let kickFillDimmedNS = NSColor(red: 0.45, green: 0.11, blue: 0.1, alpha: 0.4)
    static let airFillDimmedNS = NSColor(red: 0.196, green: 0.355, blue: 0.48, alpha: 0.4)
    static let grappleFillDimmedNS = NSColor(red: 0.276, green: 0.216, blue: 0.194, alpha: 0.4)
    static let blockFillDimmedNS = NSColor(red: 0.11, green: 0.373, blue: 0.487, alpha: 0.4)
    static let weaponFillDimmedNS = NSColor(red: 0.235, green: 0.282, blue: 0.306, alpha: 0.4)
}

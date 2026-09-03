import Foundation

/// Buttons on a generic Xbox-style gamepad. Used to map between the
/// physical controller surface (rendered in `ControllerTestSheet`) and the
/// underlying `GCControllerButtonInput` / SDL button indices.
///
/// Kept distinct from `RetroButton` (in-game binding target) and
/// `GamepadNavButton` (UI-navigation target) because the test pad is a
/// physical-layout concern: a face button here is "the green A button on
/// the controller" regardless of what in-game action it's currently bound to.
enum PadButton: String, CaseIterable, Hashable {
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight

    case a
    case b
    case x
    case y

    case l1
    case r1
    case l2
    case r2

    case l3
    case r3

    case start
    case select
    case share

    // Stick directions — synthesised from analog axis events by
    // `ControllerInputObserver` when the axis crosses ±0.5. Each maps to
    // a `RetroButton.lStick*` / `rStick*` so the user can remap the
    // "push stick in a direction" physical action to a libretro analog
    // binding the same way the main settings page supports.
    case lStickUp
    case lStickDown
    case lStickLeft
    case lStickRight
    case rStickUp
    case rStickDown
    case rStickLeft
    case rStickRight

    /// Short label rendered on or near the button (e.g. "A", "LB", "Start").
    var label: String {
        switch self {
        case .a, .b, .x, .y: return rawValue.uppercased()
        case .l1: return "LB"
        case .r1: return "RB"
        case .l2: return "LT"
        case .r2: return "RT"
        case .l3: return "L3"
        case .r3: return "R3"
        case .start: return "Start"
        case .select: return "Select"
        case .share: return "Share"
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
             .lStickUp, .lStickDown, .lStickLeft, .lStickRight,
             .rStickUp, .rStickDown, .rStickLeft, .rStickRight: return ""
        }
    }

}

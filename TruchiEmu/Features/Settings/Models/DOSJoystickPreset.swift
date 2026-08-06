import Foundation

/// DOSBox-Pure emulates a DOS-era joystick and exposes it to the guest game
/// only when the controller port device type is set to a joystick subclass
/// (see `retro_set_controller_port_device` in LibretroBridgeImpl). Each preset
/// below maps to one of DOSBox-Pure's advertised device subclasses.
enum DOSJoystickPreset: String, Codable, CaseIterable, Identifiable {
    case off
    case gravis
    case joystick2
    case thrustmaster
    case both

    var id: String { rawValue }

    /// Raw libretro device value for `RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_JOYPAD, n)`.
    /// DOSBox-Pure publishes its presets as `RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_JOYPAD, i - PRESET_GENERICKEYBOARD)`
    /// where the standard libretro macro is `(((subclass + 1) << RETRO_DEVICE_TYPE_SHIFT) | base)`
    /// with `RETRO_DEVICE_TYPE_SHIFT = 8` and `RETRO_DEVICE_JOYPAD = 1`.
    /// So: Gravis (subclass 3) -> 0x401 = 1025, Basic Joystick 1 (subclass 4) -> 0x501 = 1281,
    /// ThrustMaster (subclass 6) -> 0x701 = 1793, Both (subclass 7) -> 0x801 = 2049.
    /// 0 means "leave the core default" (LibretroBridgeImpl falls back to RETRO_DEVICE_JOYPAD).
    var deviceValue: UInt32 {
        switch self {
        case .off: return 0
        case .gravis: return 1025        // 0x401 — Gravis GamePad (1 D-pad, 4 buttons)
        case .joystick2: return 1281    // 0x501 — First DOS joystick (2 axes, 2 buttons)
        case .thrustmaster: return 1793 // 0x701 — ThrustMaster Flight Stick (3 axes, 4 buttons, 1 hat)
        case .both: return 2049         // 0x801 — Both DOS joysticks (4 axes, 4 buttons)
        }
    }

    var localizationKey: String { "settings.dosJoystick.preset.\(rawValue)" }
}

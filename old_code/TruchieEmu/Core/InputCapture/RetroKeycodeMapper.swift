import Carbon.HIToolbox

// MARK: - macOS Virtual Keycode → Libretro RETROK Mapper
//
// Libretro cores expect keyboard events using RETROK_* keycodes (defined in
// libretro.h's `enum retro_key`), which are based on ASCII / SDL key values.
// macOS NSEvent.keyCode returns hardware virtual keycodes (kVK_* from
// Carbon/HIToolbox/Events.h) which have completely different numeric values.
//
// Without this translation, pressing 'A' on macOS sends keycode 0x00 to
// the core, which maps to RETROK_UNKNOWN — so the core ignores it entirely.

enum RetroKeycodeMapper {

    /// Translate a macOS virtual keycode (NSEvent.keyCode) to a libretro RETROK value.
    /// Returns 0 (RETROK_UNKNOWN) for unmapped keys.
    static func retroKey(fromMacOS keyCode: UInt16) -> UInt32 {
        return macOSToRetroKey[keyCode] ?? 0
    }

    /// Encode NSEvent.ModifierFlags into libretro RETROKMOD bitmask.
    static func retroMod(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mod: UInt32 = 0
        if flags.contains(.shift)    { mod |= 0x01 }  // RETROKMOD_SHIFT
        if flags.contains(.control)  { mod |= 0x02 }  // RETROKMOD_CTRL
        if flags.contains(.option)   { mod |= 0x04 }  // RETROKMOD_ALT
        if flags.contains(.command)  { mod |= 0x08 }  // RETROKMOD_META
        if flags.contains(.capsLock) { mod |= 0x20 }  // RETROKMOD_CAPSLOCK
        return mod
    }

    // MARK: - Complete Mapping Table
    //
    // macOS kVK_* (left) → RETROK_* value (right)
    //
    // RETROK values from the standard libretro.h enum retro_key:
    //   Letters a-z     = 97-122 (ASCII lowercase)
    //   Digits 0-9      = 48-57  (ASCII)
    //   F1-F15          = 282-296
    //   Arrows          = 273-276
    //   Keypad 0-9      = 256-265
    //   Modifiers       = 300-313

    private static let macOSToRetroKey: [UInt16: UInt32] = [
        // ── Letters ──
        0x00:  97,  // kVK_ANSI_A        → RETROK_a
        0x01: 115,  // kVK_ANSI_S        → RETROK_s
        0x02: 100,  // kVK_ANSI_D        → RETROK_d
        0x03: 102,  // kVK_ANSI_F        → RETROK_f
        0x04: 104,  // kVK_ANSI_H        → RETROK_h
        0x05: 103,  // kVK_ANSI_G        → RETROK_g
        0x06: 122,  // kVK_ANSI_Z        → RETROK_z
        0x07: 120,  // kVK_ANSI_X        → RETROK_x
        0x08:  99,  // kVK_ANSI_C        → RETROK_c
        0x09: 118,  // kVK_ANSI_V        → RETROK_v
        0x0B:  98,  // kVK_ANSI_B        → RETROK_b
        0x0C: 113,  // kVK_ANSI_Q        → RETROK_q
        0x0D: 119,  // kVK_ANSI_W        → RETROK_w
        0x0E: 101,  // kVK_ANSI_E        → RETROK_e
        0x0F: 114,  // kVK_ANSI_R        → RETROK_r
        0x10: 121,  // kVK_ANSI_Y        → RETROK_y
        0x11: 116,  // kVK_ANSI_T        → RETROK_t
        0x1F: 111,  // kVK_ANSI_O        → RETROK_o
        0x20: 117,  // kVK_ANSI_U        → RETROK_u
        0x22: 105,  // kVK_ANSI_I        → RETROK_i
        0x23: 112,  // kVK_ANSI_P        → RETROK_p
        0x25: 108,  // kVK_ANSI_L        → RETROK_l
        0x26: 106,  // kVK_ANSI_J        → RETROK_j
        0x28: 107,  // kVK_ANSI_K        → RETROK_k
        0x2D: 110,  // kVK_ANSI_N        → RETROK_n
        0x2E: 109,  // kVK_ANSI_M        → RETROK_m

        // ── Digits ──
        0x1D:  48,  // kVK_ANSI_0        → RETROK_0
        0x12:  49,  // kVK_ANSI_1        → RETROK_1
        0x13:  50,  // kVK_ANSI_2        → RETROK_2
        0x14:  51,  // kVK_ANSI_3        → RETROK_3
        0x15:  52,  // kVK_ANSI_4        → RETROK_4
        0x17:  53,  // kVK_ANSI_5        → RETROK_5
        0x16:  54,  // kVK_ANSI_6        → RETROK_6
        0x1A:  55,  // kVK_ANSI_7        → RETROK_7
        0x1C:  56,  // kVK_ANSI_8        → RETROK_8
        0x19:  57,  // kVK_ANSI_9        → RETROK_9

        // ── Symbols / Punctuation ──
        0x1B:  45,  // kVK_ANSI_Minus         → RETROK_MINUS
        0x18:  61,  // kVK_ANSI_Equal         → RETROK_EQUALS
        0x21:  91,  // kVK_ANSI_LeftBracket   → RETROK_LEFTBRACKET
        0x1E:  93,  // kVK_ANSI_RightBracket  → RETROK_RIGHTBRACKET
        0x29:  59,  // kVK_ANSI_Semicolon     → RETROK_SEMICOLON
        0x27:  39,  // kVK_ANSI_Quote         → RETROK_QUOTE
        0x2A:  92,  // kVK_ANSI_Backslash     → RETROK_BACKSLASH
        0x2B:  44,  // kVK_ANSI_Comma         → RETROK_COMMA
        0x2F:  46,  // kVK_ANSI_Period        → RETROK_PERIOD
        0x2C:  47,  // kVK_ANSI_Slash         → RETROK_SLASH
        0x32:  96,  // kVK_ANSI_Grave         → RETROK_BACKQUOTE

        // ── Whitespace / Control ──
        0x24:  13,  // kVK_Return        → RETROK_RETURN
        0x30:   9,  // kVK_Tab           → RETROK_TAB
        0x31:  32,  // kVK_Space         → RETROK_SPACE
        0x33:   8,  // kVK_Delete        → RETROK_BACKSPACE
        0x35:  27,  // kVK_Escape        → RETROK_ESCAPE
        0x75: 127,  // kVK_ForwardDelete → RETROK_DELETE

        // ── Navigation ──
        0x7E: 273,  // kVK_UpArrow       → RETROK_UP
        0x7D: 274,  // kVK_DownArrow     → RETROK_DOWN
        0x7C: 275,  // kVK_RightArrow    → RETROK_RIGHT
        0x7B: 276,  // kVK_LeftArrow     → RETROK_LEFT
        0x72: 277,  // kVK_Help          → RETROK_INSERT  (Mac Help ≈ PC Insert)
        0x73: 278,  // kVK_Home          → RETROK_HOME
        0x77: 279,  // kVK_End           → RETROK_END
        0x74: 280,  // kVK_PageUp        → RETROK_PAGEUP
        0x79: 281,  // kVK_PageDown      → RETROK_PAGEDOWN

        // ── Function Keys ──
        0x7A: 282,  // kVK_F1            → RETROK_F1
        0x78: 283,  // kVK_F2            → RETROK_F2
        0x63: 284,  // kVK_F3            → RETROK_F3
        0x76: 285,  // kVK_F4            → RETROK_F4
        0x60: 286,  // kVK_F5            → RETROK_F5
        0x61: 287,  // kVK_F6            → RETROK_F6
        0x62: 288,  // kVK_F7            → RETROK_F7
        0x64: 289,  // kVK_F8            → RETROK_F8
        0x65: 290,  // kVK_F9            → RETROK_F9
        0x6D: 291,  // kVK_F10           → RETROK_F10
        0x67: 292,  // kVK_F11           → RETROK_F11
        0x6F: 293,  // kVK_F12           → RETROK_F12
        0x69: 294,  // kVK_F13           → RETROK_F13
        0x6B: 295,  // kVK_F14           → RETROK_F14
        0x71: 296,  // kVK_F15           → RETROK_F15

        // ── Numpad ──
        0x52: 256,  // kVK_ANSI_Keypad0        → RETROK_KP0
        0x53: 257,  // kVK_ANSI_Keypad1        → RETROK_KP1
        0x54: 258,  // kVK_ANSI_Keypad2        → RETROK_KP2
        0x55: 259,  // kVK_ANSI_Keypad3        → RETROK_KP3
        0x56: 260,  // kVK_ANSI_Keypad4        → RETROK_KP4
        0x57: 261,  // kVK_ANSI_Keypad5        → RETROK_KP5
        0x58: 262,  // kVK_ANSI_Keypad6        → RETROK_KP6
        0x59: 263,  // kVK_ANSI_Keypad7        → RETROK_KP7
        0x5B: 264,  // kVK_ANSI_Keypad8        → RETROK_KP8
        0x5C: 265,  // kVK_ANSI_Keypad9        → RETROK_KP9
        0x41: 266,  // kVK_ANSI_KeypadDecimal  → RETROK_KP_PERIOD
        0x4B: 267,  // kVK_ANSI_KeypadDivide   → RETROK_KP_DIVIDE
        0x43: 268,  // kVK_ANSI_KeypadMultiply → RETROK_KP_MULTIPLY
        0x4E: 269,  // kVK_ANSI_KeypadMinus    → RETROK_KP_MINUS
        0x45: 270,  // kVK_ANSI_KeypadPlus     → RETROK_KP_PLUS
        0x4C: 271,  // kVK_ANSI_KeypadEnter    → RETROK_KP_ENTER
        0x51: 272,  // kVK_ANSI_KeypadEquals   → RETROK_KP_EQUALS

        // ── Modifier Keys ──
        0x47: 300,  // kVK_ANSI_KeypadClear → RETROK_NUMLOCK (Mac Clear ≈ PC NumLock)
        0x39: 301,  // kVK_CapsLock       → RETROK_CAPSLOCK
        0x3C: 303,  // kVK_RightShift     → RETROK_RSHIFT
        0x38: 304,  // kVK_Shift          → RETROK_LSHIFT
        0x3E: 305,  // kVK_RightControl   → RETROK_RCTRL
        0x3B: 306,  // kVK_Control        → RETROK_LCTRL
        0x3D: 307,  // kVK_RightOption    → RETROK_RALT
        0x3A: 308,  // kVK_Option         → RETROK_LALT
        0x36: 309,  // kVK_RightCommand   → RETROK_RMETA
        0x37: 310,  // kVK_Command        → RETROK_LMETA

        // ── Misc ──
        0x0A:  60,  // kVK_ISO_Section    → RETROK_LESS  (international key)
    ]
}

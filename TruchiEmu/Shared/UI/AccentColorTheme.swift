import SwiftUI

enum AccentColorTheme: String, CaseIterable, Codable {
    case samus
    case chocobo
    case protoss
    case joker
    case geralt
    case megaMan
    case custom

    case mario
    case luigi
    case sonic
    case halfLife
    case kratos
    case kirby
    case zelda
    case pikachu
    case doom
    case masterChief

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        if let migrated = Self.migratedRawValue(rawValue) {
            self = migrated
        } else if let theme = AccentColorTheme(rawValue: rawValue) {
            self = theme
        } else {
            self = .megaMan
        }
    }

    private static func migratedRawValue(_ old: String) -> AccentColorTheme? {
        switch old {
        case "cyan": return .samus
        case "amber": return .chocobo
        case "rose": return .protoss
        case "violet": return .joker
        case "emerald": return .geralt
        case "ocean": return .megaMan
        case "aquatic": return .samus
        case "solar": return .chocobo
        case "crimson": return .protoss
        case "royal": return .joker
        case "forest": return .geralt
        case "deep": return .megaMan
        case "pokemon": return .pikachu
        case "ryu": return .kratos
        default: return nil
        }
    }

    var accent: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.851, green: 0.467, blue: 0.024, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 0.882, green: 0.114, blue: 0.282, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.486, green: 0.227, blue: 0.929, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.020, green: 0.588, blue: 0.412, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.024, green: 0.714, blue: 0.831, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 0.898, green: 0.145, blue: 0.129, opacity: 1.0)
        case .luigi: return Color(.sRGB, red: 0.000, green: 0.659, blue: 0.302, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.000, green: 0.376, blue: 0.941, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 1.000, green: 0.400, blue: 0.000, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 0.800, green: 0.000, blue: 0.000, opacity: 1.0)
        case .kirby: return Color(.sRGB, red: 1.000, green: 0.549, blue: 0.718, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.176, green: 0.549, blue: 0.235, opacity: 1.0)
        case .pikachu: return Color(.sRGB, red: 1.000, green: 0.800, blue: 0.000, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 0.545, green: 0.000, blue: 0.000, opacity: 1.0)
        case .masterChief: return Color(.sRGB, red: 0.250, green: 0.580, blue: 0.280, opacity: 1.0)
        }
    }

    var accentDimmed: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.024, green: 0.478, blue: 0.588, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.733, green: 0.392, blue: 0.020, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 0.757, green: 0.086, blue: 0.220, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.408, green: 0.180, blue: 0.800, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.016, green: 0.490, blue: 0.341, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.020, green: 0.600, blue: 0.698, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.024, green: 0.478, blue: 0.588, opacity: 1.0)
        case .mario: return Self.dimmedColor(from: Color(.sRGB, red: 0.898, green: 0.145, blue: 0.129, opacity: 1.0))
        case .luigi: return Self.dimmedColor(from: Color(.sRGB, red: 0.000, green: 0.659, blue: 0.302, opacity: 1.0))
        case .sonic: return Self.dimmedColor(from: Color(.sRGB, red: 0.000, green: 0.376, blue: 0.941, opacity: 1.0))
        case .halfLife: return Self.dimmedColor(from: Color(.sRGB, red: 1.000, green: 0.400, blue: 0.000, opacity: 1.0))
        case .kratos: return Self.dimmedColor(from: Color(.sRGB, red: 0.800, green: 0.000, blue: 0.000, opacity: 1.0))
        case .kirby: return Self.dimmedColor(from: Color(.sRGB, red: 1.000, green: 0.549, blue: 0.718, opacity: 1.0))
        case .zelda: return Self.dimmedColor(from: Color(.sRGB, red: 0.176, green: 0.549, blue: 0.235, opacity: 1.0))
        case .pikachu: return Self.dimmedColor(from: Color(.sRGB, red: 1.000, green: 0.800, blue: 0.000, opacity: 1.0))
        case .doom: return Self.dimmedColor(from: Color(.sRGB, red: 0.545, green: 0.000, blue: 0.000, opacity: 1.0))
        case .masterChief: return Self.dimmedColor(from: Color(.sRGB, red: 0.250, green: 0.580, blue: 0.280, opacity: 1.0))
        }
    }

    var accentDark: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.016, green: 0.333, blue: 0.408, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.576, green: 0.306, blue: 0.016, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 0.596, green: 0.059, blue: 0.157, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.318, green: 0.125, blue: 0.647, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.012, green: 0.384, blue: 0.267, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.017, green: 0.500, blue: 0.582, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.016, green: 0.333, blue: 0.408, opacity: 1.0)
        case .mario: return Self.darkColor(from: Color(.sRGB, red: 0.898, green: 0.145, blue: 0.129, opacity: 1.0))
        case .luigi: return Self.darkColor(from: Color(.sRGB, red: 0.000, green: 0.659, blue: 0.302, opacity: 1.0))
        case .sonic: return Self.darkColor(from: Color(.sRGB, red: 0.000, green: 0.376, blue: 0.941, opacity: 1.0))
        case .halfLife: return Self.darkColor(from: Color(.sRGB, red: 1.000, green: 0.400, blue: 0.000, opacity: 1.0))
        case .kratos: return Self.darkColor(from: Color(.sRGB, red: 0.800, green: 0.000, blue: 0.000, opacity: 1.0))
        case .kirby: return Self.darkColor(from: Color(.sRGB, red: 1.000, green: 0.549, blue: 0.718, opacity: 1.0))
        case .zelda: return Self.darkColor(from: Color(.sRGB, red: 0.176, green: 0.549, blue: 0.235, opacity: 1.0))
        case .pikachu: return Self.darkColor(from: Color(.sRGB, red: 1.000, green: 0.800, blue: 0.000, opacity: 1.0))
        case .doom: return Self.darkColor(from: Color(.sRGB, red: 0.545, green: 0.000, blue: 0.000, opacity: 1.0))
        case .masterChief: return Self.darkColor(from: Color(.sRGB, red: 0.250, green: 0.580, blue: 0.280, opacity: 1.0))
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.078, green: 0.722, blue: 0.651, opacity: 1.0)   // teal, analogous to cyan
        case .chocobo: return Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1.0) // amber, lighter orange
        case .protoss: return Color(.sRGB, red: 0.957, green: 0.247, blue: 0.369, opacity: 1.0) // rose, lighter red
        case .joker: return Color(.sRGB, red: 0.545, green: 0.361, blue: 0.965, opacity: 1.0)   // violet, lighter purple
        case .geralt: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)  // emerald, lighter green
        case .megaMan: return Color(.sRGB, red: 0.133, green: 0.827, blue: 0.933, opacity: 1.0) // light cyan
        case .custom: return Color(.sRGB, red: 0.078, green: 0.722, blue: 0.651, opacity: 1.0)  // teal, matches cyan base
        case .mario: return Color(.sRGB, red: 0.976, green: 0.451, blue: 0.086, opacity: 1.0)   // orange, lighter red
        case .luigi: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)   // emerald, lighter green
        case .sonic: return Color(.sRGB, red: 0.231, green: 0.510, blue: 0.965, opacity: 1.0)   // blue, lighter blue
        case .halfLife: return Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1.0) // amber, lighter orange
        case .kratos: return Color(.sRGB, red: 0.937, green: 0.267, blue: 0.267, opacity: 1.0)  // red, lighter dark-red
        case .kirby: return Color(.sRGB, red: 0.925, green: 0.282, blue: 0.600, opacity: 1.0)   // pink, lighter pink
        case .zelda: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)   // emerald, lighter green
        case .pikachu: return Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1.0) // amber, lighter yellow
        case .doom: return Color(.sRGB, red: 0.863, green: 0.149, blue: 0.149, opacity: 1.0)    // red, lighter dark-red
        case .masterChief: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0) // emerald, lighter green
        }
    }

    var accentForLightMode: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.020, green: 0.370, blue: 0.454, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 0.573, green: 0.074, blue: 0.183, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 0.584, green: 0.094, blue: 0.084, opacity: 1.0)
        case .luigi: return Color(.sRGB, red: 0.000, green: 0.460, blue: 0.211, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 0.700, green: 0.280, blue: 0.000, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.114, green: 0.357, blue: 0.153, opacity: 1.0)
        case .pikachu: return Color(.sRGB, red: 0.550, green: 0.420, blue: 0.000, opacity: 1.0)
        case .kirby: return Color(.sRGB, red: 0.700, green: 0.300, blue: 0.430, opacity: 1.0)
        case .masterChief: return Color(.sRGB, red: 0.163, green: 0.377, blue: 0.182, opacity: 1.0)
        default: return self.accent
        }
    }

    var accentDimmedForLightMode: Color {
        Self.dimmedColor(from: accentForLightMode)
    }

    var accentDarkForLightMode: Color {
        Self.darkColor(from: accentForLightMode)
    }

    var secondaryAccentForLightMode: Color {
        switch self {
        case .chocobo, .geralt: return Color(.sRGB, red: 0.596, green: 0.327, blue: 0.017, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.025, green: 0.456, blue: 0.579, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 0.250, green: 0.426, blue: 0.585, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.480, green: 0.400, blue: 0.000, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 0.550, green: 0.550, blue: 0.550, opacity: 1.0)
        case .kirby, .luigi: return Color(.sRGB, red: 0.370, green: 0.566, blue: 0.645, opacity: 1.0)
        case .zelda, .masterChief: return Color(.sRGB, red: 0.556, green: 0.421, blue: 0.081, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 0.700, green: 0.280, blue: 0.000, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.013, green: 0.382, blue: 0.268, opacity: 1.0)
        default: return self.secondaryAccent
        }
    }

    var accentForDarkMode: Color {
        switch self {
        case .joker: return Color(.sRGB, red: 0.650, green: 0.400, blue: 1.000, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.150, green: 0.650, blue: 0.850, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.300, green: 0.600, blue: 1.000, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 1.000, green: 0.350, blue: 0.500, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 1.000, green: 0.400, blue: 0.380, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.400, green: 0.720, blue: 0.440, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 1.000, green: 0.271, blue: 0.000, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 1.000, green: 0.333, blue: 0.333, opacity: 1.0)
        default: return self.accent
        }
    }

    var accentDimmedForDarkMode: Color {
        Self.dimmedColor(from: accentForDarkMode)
    }

    var accentDarkForDarkMode: Color {
        Self.darkColor(from: accentForDarkMode)
    }

    var secondaryAccentForDarkMode: Color {
        switch self {
        case .protoss: return Color(.sRGB, red: 0.650, green: 0.400, blue: 1.000, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 0.600, green: 0.650, blue: 0.350, opacity: 1.0)
        default: return self.secondaryAccent
        }
    }

    var displayName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .samus: return loc.localized("settings.theme.samus")
        case .chocobo: return loc.localized("settings.theme.chocobo")
        case .protoss: return loc.localized("settings.theme.protoss")
        case .joker: return loc.localized("settings.theme.joker")
        case .geralt: return loc.localized("settings.theme.geralt")
        case .megaMan: return loc.localized("settings.theme.megaMan")
        case .custom: return loc.localized("settings.theme.custom")
        case .mario: return loc.localized("settings.theme.mario")
        case .luigi: return loc.localized("settings.theme.luigi")
        case .sonic: return loc.localized("settings.theme.sonic")
        case .halfLife: return loc.localized("settings.theme.halfLife")
        case .kratos: return loc.localized("settings.theme.kratos")
        case .kirby: return loc.localized("settings.theme.kirby")
        case .zelda: return loc.localized("settings.theme.zelda")
        case .pikachu: return loc.localized("settings.theme.pikachu")
        case .doom: return loc.localized("settings.theme.doom")
        case .masterChief: return loc.localized("settings.theme.masterChief")
        }
    }

    var iconAssetName: String {
        switch self {
        case .custom: return "ThemeCustom"
        case .samus: return "ThemeSamus"
        case .chocobo: return "ThemeChocobo"
        case .protoss: return "ThemeProtoss"
        case .joker: return "ThemeJoker"
        case .geralt: return "ThemeGeralt"
        case .megaMan: return "ThemeMegaMan"
        case .mario: return "ThemeMario"
        case .luigi: return "ThemeLuigi"
        case .sonic: return "ThemeSonic"
        case .halfLife: return "ThemeHalfLife"
        case .kratos: return "ThemeKratos"
        case .kirby: return "ThemeKirby"
        case .zelda: return "ThemeZelda"
        case .pikachu: return "ThemePikachu"
        case .doom: return "ThemeDoom"
        case .masterChief: return "ThemeMasterChief"
        }
    }

    var isCustom: Bool {
        return self == .custom
    }

    static func dimmedColor(from accent: Color) -> Color {
        guard let nsColor = NSColor(accent).usingColorSpace(.sRGB) else { return accent }
        return Color(.sRGB, red: nsColor.redComponent * 0.84,
                     green: nsColor.greenComponent * 0.84,
                     blue: nsColor.blueComponent * 0.84,
                     opacity: 1.0)
    }

    static func darkColor(from accent: Color) -> Color {
        guard let nsColor = NSColor(accent).usingColorSpace(.sRGB) else { return accent }
        return Color(.sRGB, red: nsColor.redComponent * 0.70,
                     green: nsColor.greenComponent * 0.70,
                     blue: nsColor.blueComponent * 0.70,
                     opacity: 1.0)
    }
}

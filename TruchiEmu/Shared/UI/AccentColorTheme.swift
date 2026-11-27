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

    // Light-mode accent. Every case is darkened (hue and chroma kept) until it
    // reaches WCAG AA (4.5:1) as text on the light window background. The
    // bright `accent` above stays the brand swatch used for fills and icons.
    var accentForLightMode: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.000, green: 0.424, blue: 0.548, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.648, green: 0.281, blue: 0.000, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 0.773, green: 0.000, blue: 0.198, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.475, green: 0.210, blue: 0.914, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.000, green: 0.449, blue: 0.284, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.000, green: 0.426, blue: 0.536, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.000, green: 0.424, blue: 0.548, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 0.778, green: 0.000, blue: 0.000, opacity: 1.0)
        case .luigi: return Color(.sRGB, red: 0.000, green: 0.456, blue: 0.092, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.000, green: 0.341, blue: 0.904, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 0.749, green: 0.143, blue: 0.000, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 0.778, green: 0.000, blue: 0.000, opacity: 1.0)
        case .kirby: return Color(.sRGB, red: 0.656, green: 0.240, blue: 0.416, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.021, green: 0.455, blue: 0.140, opacity: 1.0)
        case .pikachu: return Color(.sRGB, red: 0.542, green: 0.353, blue: 0.000, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 0.545, green: 0.000, blue: 0.000, opacity: 1.0)
        case .masterChief: return Color(.sRGB, red: 0.099, green: 0.452, blue: 0.154, opacity: 1.0)
        }
    }

    var accentDimmedForLightMode: Color {
        Self.dimmedColor(from: accentForLightMode)
    }

    var accentDarkForLightMode: Color {
        Self.darkColor(from: accentForLightMode)
    }

    // Light-mode secondary accent. Same rule: hue-correct and AA-safe as text,
    // so it can back both primary buttons and tinted controls on pale surfaces.
    var secondaryAccentForLightMode: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.000, green: 0.442, blue: 0.383, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.621, green: 0.304, blue: 0.000, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 0.771, green: 0.000, blue: 0.225, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.458, green: 0.255, blue: 0.856, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.000, green: 0.451, blue: 0.254, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.000, green: 0.427, blue: 0.527, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.000, green: 0.442, blue: 0.383, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 0.708, green: 0.197, blue: 0.000, opacity: 1.0)
        case .luigi: return Color(.sRGB, red: 0.000, green: 0.451, blue: 0.254, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.080, green: 0.368, blue: 0.811, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 0.616, green: 0.299, blue: 0.000, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 0.772, green: 0.038, blue: 0.125, opacity: 1.0)
        case .kirby: return Color(.sRGB, red: 0.741, green: 0.038, blue: 0.446, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.000, green: 0.451, blue: 0.254, opacity: 1.0)
        case .pikachu: return Color(.sRGB, red: 0.621, green: 0.304, blue: 0.000, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 0.772, green: 0.000, blue: 0.044, opacity: 1.0)
        case .masterChief: return Color(.sRGB, red: 0.000, green: 0.451, blue: 0.254, opacity: 1.0)
        }
    }

    // Dark-mode accent. Lightened (hue and chroma kept) until it reaches AA on
    // the dark card surface. `accentForDarkMode` is what `brandAccent` uses in
    // dark appearance, so icons and links stay legible on every theme.
    var accentForDarkMode: Color {
        switch self {
        case .samus: return Color(.sRGB, red: 0.171, green: 0.635, blue: 0.767, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.875, green: 0.489, blue: 0.085, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 1.000, green: 0.365, blue: 0.454, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.690, green: 0.478, blue: 1.000, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.178, green: 0.662, blue: 0.482, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.024, green: 0.714, blue: 0.831, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.171, green: 0.635, blue: 0.767, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 1.000, green: 0.379, blue: 0.322, opacity: 1.0)
        case .luigi: return Color(.sRGB, red: 0.065, green: 0.676, blue: 0.318, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.259, green: 0.590, blue: 1.000, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 1.000, green: 0.400, blue: 0.000, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 1.000, green: 0.380, blue: 0.308, opacity: 1.0)
        case .kirby: return Color(.sRGB, red: 1.000, green: 0.549, blue: 0.718, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.299, green: 0.660, blue: 0.341, opacity: 1.0)
        case .pikachu: return Color(.sRGB, red: 1.000, green: 0.800, blue: 0.000, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 0.941, green: 0.430, blue: 0.365, opacity: 1.0)
        case .masterChief: return Color(.sRGB, red: 0.328, green: 0.656, blue: 0.352, opacity: 1.0)
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
        case .samus: return Color(.sRGB, red: 0.078, green: 0.722, blue: 0.651, opacity: 1.0)
        case .chocobo: return Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1.0)
        case .protoss: return Color(.sRGB, red: 1.000, green: 0.364, blue: 0.462, opacity: 1.0)
        case .joker: return Color(.sRGB, red: 0.661, green: 0.491, blue: 1.000, opacity: 1.0)
        case .geralt: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)
        case .megaMan: return Color(.sRGB, red: 0.133, green: 0.827, blue: 0.933, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.078, green: 0.722, blue: 0.651, opacity: 1.0)
        case .mario: return Color(.sRGB, red: 0.976, green: 0.451, blue: 0.086, opacity: 1.0)
        case .luigi: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)
        case .sonic: return Color(.sRGB, red: 0.303, green: 0.585, blue: 1.000, opacity: 1.0)
        case .halfLife: return Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1.0)
        case .kratos: return Color(.sRGB, red: 1.000, green: 0.375, blue: 0.359, opacity: 1.0)
        case .kirby: return Color(.sRGB, red: 0.988, green: 0.343, blue: 0.654, opacity: 1.0)
        case .zelda: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)
        case .pikachu: return Color(.sRGB, red: 0.961, green: 0.620, blue: 0.043, opacity: 1.0)
        case .doom: return Color(.sRGB, red: 1.000, green: 0.378, blue: 0.334, opacity: 1.0)
        case .masterChief: return Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506, opacity: 1.0)
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

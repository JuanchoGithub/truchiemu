import SwiftUI

enum AccentColorTheme: String, CaseIterable, Codable {
    case cyan
    case amber
    case rose
    case violet
    case emerald
    case ocean
    case custom

    var accent: Color {
        switch self {
        case .cyan: return Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698, opacity: 1.0)
        case .amber: return Color(.sRGB, red: 0.851, green: 0.467, blue: 0.024, opacity: 1.0)
        case .rose: return Color(.sRGB, red: 0.882, green: 0.114, blue: 0.282, opacity: 1.0)
        case .violet: return Color(.sRGB, red: 0.486, green: 0.227, blue: 0.929, opacity: 1.0)
        case .emerald: return Color(.sRGB, red: 0.020, green: 0.588, blue: 0.412, opacity: 1.0)
        case .ocean: return Color(.sRGB, red: 0.012, green: 0.412, blue: 0.631, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.031, green: 0.569, blue: 0.698, opacity: 1.0)
        }
    }

    var accentDimmed: Color {
        switch self {
        case .cyan: return Color(.sRGB, red: 0.024, green: 0.478, blue: 0.588, opacity: 1.0)
        case .amber: return Color(.sRGB, red: 0.733, green: 0.392, blue: 0.020, opacity: 1.0)
        case .rose: return Color(.sRGB, red: 0.757, green: 0.086, blue: 0.220, opacity: 1.0)
        case .violet: return Color(.sRGB, red: 0.408, green: 0.180, blue: 0.800, opacity: 1.0)
        case .emerald: return Color(.sRGB, red: 0.016, green: 0.490, blue: 0.341, opacity: 1.0)
        case .ocean: return Color(.sRGB, red: 0.010, green: 0.345, blue: 0.529, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.024, green: 0.478, blue: 0.588, opacity: 1.0)
        }
    }

    var accentDark: Color {
        switch self {
        case .cyan: return Color(.sRGB, red: 0.016, green: 0.333, blue: 0.408, opacity: 1.0)
        case .amber: return Color(.sRGB, red: 0.576, green: 0.306, blue: 0.016, opacity: 1.0)
        case .rose: return Color(.sRGB, red: 0.596, green: 0.059, blue: 0.157, opacity: 1.0)
        case .violet: return Color(.sRGB, red: 0.318, green: 0.125, blue: 0.647, opacity: 1.0)
        case .emerald: return Color(.sRGB, red: 0.012, green: 0.384, blue: 0.267, opacity: 1.0)
        case .ocean: return Color(.sRGB, red: 0.008, green: 0.271, blue: 0.416, opacity: 1.0)
        case .custom: return Color(.sRGB, red: 0.016, green: 0.333, blue: 0.408, opacity: 1.0)
        }
    }

    var displayName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .cyan: return loc.localized("settings.theme.cyan")
        case .amber: return loc.localized("settings.theme.amber")
        case .rose: return loc.localized("settings.theme.rose")
        case .violet: return loc.localized("settings.theme.violet")
        case .emerald: return loc.localized("settings.theme.emerald")
        case .ocean: return loc.localized("settings.theme.ocean")
        case .custom: return loc.localized("settings.theme.custom")
        }
    }

    var systemImageName: String {
        return "circle.fill"
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

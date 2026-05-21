import Foundation

enum AppearanceMode: String, CaseIterable, Codable {
    case automatic
    case light
    case dark

    var displayName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .automatic: return loc.localized("settings.appearance.automatic")
        case .light: return loc.localized("settings.appearance.light")
        case .dark: return loc.localized("settings.appearance.dark")
        }
    }

    var systemImageName: String {
        switch self {
        case .automatic: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

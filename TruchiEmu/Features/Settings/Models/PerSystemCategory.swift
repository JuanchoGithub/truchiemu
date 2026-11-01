import Foundation

/// The per-system option categories shown in the Per-System options column.
///
/// A `nil` selection means the inactive-system "Setup" placeholder.
enum PerSystemCategory: String, CaseIterable, Identifiable {
    case shader
    case controls
    case cheats
    case boxArt
    case core
    case achievements
    case bezel

    var id: String { rawValue }

    /// Localization key for the display label.
    var labelKey: String {
        switch self {
        case .shader: return "settings.shaders"
        case .controls: return "settings.controllers"
        case .cheats: return "settings.cheats"
        case .boxArt: return "settings.boxArt"
        case .core: return "settings.core"
        case .achievements: return "settings.retroAchievements"
        case .bezel: return "settings.bezels"
        }
    }

    var icon: String {
        switch self {
        case .shader: return "wand.and.rays"
        case .controls: return "gamecontroller"
        case .cheats: return "wand.and.stars"
        case .boxArt: return "photo.stack"
        case .core: return "cpu"
        case .achievements: return "shield.lefthalf.filled"
        case .bezel: return "rectangle.on.rectangle"
        }
    }
}

import SwiftUI

enum DetailSection: String, CaseIterable {
    case gameInfo = "Game Info"
    case shader = "Shader"
    case bezels = "Bezels"
    case controls = "Controls"
    case savedStates = "Saved States"
    case cheats = "Cheats"
    case core = "Core"
    case achievements = "Achievements"
    
    var localizedTitle: String {
        switch self {
        case .gameInfo: return LocalizationManager.shared.localized("gameDetail.gameInfo")
        case .shader: return LocalizationManager.shared.localized("gameDetail.shader")
        case .bezels: return LocalizationManager.shared.localized("gameDetail.bezels")
        case .controls: return LocalizationManager.shared.localized("gameDetail.controls")
        case .savedStates: return LocalizationManager.shared.localized("gameDetail.savedStates")
        case .cheats: return LocalizationManager.shared.localized("gameDetail.cheats")
        case .core: return LocalizationManager.shared.localized("gameDetail.core")
        case .achievements: return LocalizationManager.shared.localized("gameDetail.achievements")
        }
    }

    var helpText: String {
        switch self {
        case .gameInfo:
            return "View game details, metadata, and metadata identification tools"
        case .shader:
            return "Customize visual effects like CRT filters and screen smoothing"
        case .bezels:
            return "Browse and apply decorative bezel artwork around the game screen"
        case .controls:
            return "View and customize keyboard and controller button mappings"
        case .savedStates:
            return "Manage save states created during gameplay — load or delete saves"
        case .cheats:
            return "Download, enable, and manage cheat codes for this game"
        case .core:
            return "Choose which emulation engine to use for this game or system"
        case .achievements:
            return "View RetroAchievements — earn points by completing in-game challenges"
        }
    }
    
    var headerIcon: String {
        return sectionIcon
    }
    
    var sectionIcon: String {
        switch self {
        case .gameInfo: return "info.circle"
        case .shader: return "display"
        case .bezels: return "photo.on.rectangle.angled"
        case .controls: return "gamecontroller"
        case .savedStates: return "externaldrive"
        case .cheats: return "wand.and.stars"
        case .core: return "cpu"
        case .achievements: return "trophy"
        }
    }
}
import SwiftUI

// MARK: - Detail Sections

enum DetailSection: String, CaseIterable {
    case gameInfo = "Game Info"
    case shader = "Shader"
    case bezels = "Bezels"
    case controls = "Controls"
    case savedStates = "Saved States"
    case cheats = "Cheats"
    case core = "Core"
    case achievements = "Achievements"
    
    // Plain-language description of what each section does, shown as tooltip
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
    
    // SF Symbol icon for the section header (larger)
    var headerIcon: String {
        return sectionIcon
    }
    
    // SF Symbol icon used in sidebar navigation
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
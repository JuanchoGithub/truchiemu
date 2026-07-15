import SwiftUI

enum DetailSection: String, CaseIterable {
    case gameInfo = "Game Info"
    case shader = "Shader"
    case bezels = "Bezels"
    case controls = "Controls"
    case analogMouse = "Analog Mouse"
    case coreOptions = "Core Options"
    case savedStates = "Saved States"
    case cheats = "Cheats"
    case core = "Core"
    case achievements = "Achievements"
    case technical = "Technical"

    var localizedTitle: String {
        switch self {
        case .gameInfo: return LocalizationManager.shared.localized("gameDetail.gameInfo")
        case .shader: return LocalizationManager.shared.localized("gameDetail.shader")
        case .bezels: return LocalizationManager.shared.localized("gameDetail.bezels")
        case .controls: return LocalizationManager.shared.localized("gameDetail.controls")
        case .analogMouse: return LocalizationManager.shared.localized("gameDetail.analogMouse")
        case .coreOptions: return LocalizationManager.shared.localized("gameDetail.coreOptions")
        case .savedStates: return LocalizationManager.shared.localized("gameDetail.savedStates")
        case .cheats: return LocalizationManager.shared.localized("gameDetail.cheats")
        case .core: return LocalizationManager.shared.localized("gameDetail.core")
        case .achievements: return LocalizationManager.shared.localized("gameDetail.achievements")
        case .technical: return LocalizationManager.shared.localized("gameDetail.technical")
        }
    }

    var helpText: String {
        switch self {
        case .gameInfo:
            return LocalizationManager.shared.localized("gameDetail.gameInfoHelp")
        case .shader:
            return LocalizationManager.shared.localized("gameDetail.shaderHelp")
        case .bezels:
            return LocalizationManager.shared.localized("gameDetail.bezelsHelp")
        case .controls:
            return LocalizationManager.shared.localized("gameDetail.controlsHelp")
        case .analogMouse:
            return LocalizationManager.shared.localized("gameDetail.analogMouseHelp")
        case .coreOptions:
            return LocalizationManager.shared.localized("gameDetail.coreOptionsHelp")
        case .savedStates:
            return LocalizationManager.shared.localized("gameDetail.savedStatesHelp")
        case .cheats:
            return LocalizationManager.shared.localized("gameDetail.cheatsHelp")
        case .core:
            return LocalizationManager.shared.localized("gameDetail.coreHelp")
        case .achievements:
            return LocalizationManager.shared.localized("gameDetail.achievementsHelp")
        case .technical:
            return LocalizationManager.shared.localized("gameDetail.technicalHelp")
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
        case .analogMouse: return "computermouse"
        case .coreOptions: return "cpu"
        case .savedStates: return "externaldrive"
        case .cheats: return "wand.and.stars"
        case .core: return "cpu"
        case .achievements: return "trophy"
        case .technical: return "doc.text.magnifyingglass"
        }
    }
}
import Foundation

enum ShareBehavior: String, Codable, CaseIterable, Identifiable {
    case none
    case screenshot
    case startVideoRecording
    case streamTwitch
    case streamYoutube
    case streamCustom
    case saveLastXSeconds

    var id: String { rawValue }

    var localizationKey: String {
        "media.behavior." + rawValue
    }

    var requiresRollingBuffer: Bool {
        self == .saveLastXSeconds
    }

    var isStreaming: Bool {
        switch self {
        case .streamTwitch, .streamYoutube, .streamCustom: return true
        default: return false
        }
    }

    var isNone: Bool {
        self == .none
    }
}

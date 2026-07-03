import Foundation

enum RollingBufferDuration: Double, Codable, CaseIterable, Identifiable {
    case seconds30 = 30
    case seconds60 = 60
    case minutes2 = 120
    case minutes5 = 300
    case minutes10 = 600
    case minutes15 = 900
    case custom = -1

    var id: Double { rawValue }

    var localizationKey: String {
        switch self {
        case .seconds30: return "media.duration.30s"
        case .seconds60: return "media.duration.60s"
        case .minutes2:  return "media.duration.2m"
        case .minutes5:  return "media.duration.5m"
        case .minutes10: return "media.duration.10m"
        case .minutes15: return "media.duration.15m"
        case .custom:    return "media.saveLastMoments.custom"
        }
    }

    var actualDuration: Double {
        switch self {
        case .custom: return 60
        default: return rawValue
        }
    }

    static let maxCustomDuration: Double = 900
}

struct RollingBufferConfig: Codable, Equatable {
    var enabled: Bool = false
    var duration: RollingBufferDuration = .seconds60
    var recordDisplayResolution: Bool = false

    private static let storageKey = "rollingBufferConfig"

    static func load() -> RollingBufferConfig {
        if let data = AppSettings.getData(storageKey),
           let decoded = try? JSONDecoder().decode(RollingBufferConfig.self, from: data) {
            return decoded
        }
        return RollingBufferConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppSettings.setData(Self.storageKey, value: data)
        }
    }
}

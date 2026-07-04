import Foundation

struct ShareButtonConfig: Codable, Equatable {
    var singlePress: ShareBehavior = .none
    var longPress: ShareBehavior = .none

    private static let storageKey = "shareButtonConfig"

    static func load() -> ShareButtonConfig {
        if let data = AppSettings.getData(storageKey),
           let decoded = try? JSONDecoder().decode(ShareButtonConfig.self, from: data) {
            return decoded
        }
        return ShareButtonConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppSettings.setData(Self.storageKey, value: data)
        }
    }
}

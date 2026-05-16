import Foundation

struct GameMappingProfile: Codable, Identifiable {
    var id: String { gameID }
    let gameID: String
    let systemID: String
    var gamepadOverrides: [RetroButton: GCButtonMapping]?
    var keyboardOverrides: [RetroButton: UInt16]?

    static func fileName(for gameID: String) -> String {
        let safe = gameID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? gameID
        return "GameMapping_\(safe).json"
    }
}

final class GameMappingStorage {
    static let shared = GameMappingStorage()

    private let storageURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/GameMappings", isDirectory: true)
    }()

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private init() {
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    func load(for gameID: String) -> GameMappingProfile? {
        let url = storageURL.appendingPathComponent(GameMappingProfile.fileName(for: gameID))
        guard let data = try? Data(contentsOf: url),
              let profile = try? decoder.decode(GameMappingProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    func save(_ profile: GameMappingProfile) {
        let url = storageURL.appendingPathComponent(GameMappingProfile.fileName(for: profile.gameID))
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: url)
    }

    func delete(for gameID: String) {
        let url = storageURL.appendingPathComponent(GameMappingProfile.fileName(for: gameID))
        try? FileManager.default.removeItem(at: url)
    }
}

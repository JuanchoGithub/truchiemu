import Foundation

struct ROM: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: URL
    var systemID: String?
    var boxArtPath: URL?
    var isFavorite: Bool = false
    var lastPlayed: Date?
    var selectedCoreID: String?
    var useCustomCore: Bool = false
    var metadata: ROMMetadata?
    var settings: ROMSettings = ROMSettings()

    // Derived
    var displayName: String { metadata?.title ?? name }
    var fileExtension: String { path.pathExtension.lowercased() }

    // Persistent storage paths
    var boxArtLocalPath: URL {
        path.deletingLastPathComponent()
            .appendingPathComponent("boxart")
            .appendingPathComponent("\(name)_boxart.jpg")
    }
    
    var infoLocalPath: URL {
        path.deletingLastPathComponent()
            .appendingPathComponent("\(name)_info.json")
    }
}

struct ROMSettings: Codable, Hashable {
    var crtEnabled: Bool = false
    var scanlinesEnabled: Bool = true
    var scanlineIntensity: Float = 0.35
    var barrelEnabled: Bool = false
    var barrelAmount: Float = 0.12
    var phosphorEnabled: Bool = false
    var scanlineSmooth: Bool = false
    var colorBoost: Float = 1.0
    var bezelStyle: String = "none"
}

struct ROMMetadata: Codable, Hashable {
    var title: String?
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var players: Int?
    var description: String?
    var rating: Double?
}

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
    var metadata: ROMMetadata?

    // Derived
    var displayName: String { metadata?.title ?? name }
    var fileExtension: String { path.pathExtension.lowercased() }
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

import Foundation

/// One game that the user can select in the manual match sheet.
/// The list comes from the system DAT first and from LaunchBox second.
struct GameMatchCandidate: Identifiable, Hashable {
    enum Source: String {
        case dat
        case launchBox

        var localizedKey: String {
            switch self {
            case .dat: return "gameInfo.matchSourceDAT"
            case .launchBox: return "gameInfo.matchSourceLaunchBox"
            }
        }
    }

    let id: String
    let source: Source
    let name: String
    let year: String?
    let publisher: String?
    let developer: String?
    let genre: String?
    let players: Int?
    let description: String?
    let esrbRating: String?
    let cooperative: Bool?
    let thumbnailLookupSystemID: String?
    /// Box art URL of a LaunchBox game. nil for DAT entries.
    let boxArtURL: URL?
    /// Diacritic-free lowercased name, used by the search field.
    let searchKey: String

    init(
        source: Source,
        id: String,
        name: String,
        year: String? = nil,
        publisher: String? = nil,
        developer: String? = nil,
        genre: String? = nil,
        players: Int? = nil,
        description: String? = nil,
        esrbRating: String? = nil,
        cooperative: Bool? = nil,
        thumbnailLookupSystemID: String? = nil,
        boxArtURL: URL? = nil
    ) {
        self.id = "\(source.rawValue)|\(id)"
        self.source = source
        self.name = name
        self.year = year
        self.publisher = publisher
        self.developer = developer
        self.genre = genre
        self.players = players
        self.description = description
        self.esrbRating = esrbRating
        self.cooperative = cooperative
        self.thumbnailLookupSystemID = thumbnailLookupSystemID
        self.boxArtURL = boxArtURL
        self.searchKey = Self.searchKey(for: name)
    }

    static func searchKey(for name: String) -> String {
        name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    /// Second line of a result row: year, maker, and genre when known.
    var detailLine: String {
        [year, developer ?? publisher, genre]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

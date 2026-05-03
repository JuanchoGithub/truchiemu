import Foundation
import SwiftUI

@MainActor
final class GenreManager: ObservableObject {
    static let shared = GenreManager()

    private let settingsKey = "genreMappings"

    @Published private(set) var mappings: [String: String] = [:]

    private init() {
        loadMappings()
    }

    func effectiveDisplayName(for original: String?) -> String {
        guard let genre = original else { return "Unknown" }
        return mappings[genre] ?? genre
    }

    func getAllDisplayGenres(from roms: [ROM]) -> [String] {
        let names = roms.compactMap { effectiveDisplayName(for: $0.metadata?.genre) }
        return Array(Set(names)).sorted()
    }

    var allMappings: [(original: String, display: String)] {
        mappings.map { (original: $0.key, display: $0.value) }
    }

    func mergeGenres(from originals: Set<String>, to display: String) {
        for original in originals {
            mappings[original] = display
        }
        saveMappings()
    }

    func removeMapping(for original: String) {
        mappings.removeValue(forKey: original)
        saveMappings()
    }

    private func loadMappings() {
        if let loaded: [String: String] = AppSettings.get(settingsKey, type: [String: String].self) {
            mappings = loaded
        } else {
            mappings = [
                "Shoot'em Up": "Shooter",
                "Sports with Animals": "Sports",
                "Lightgun Shooter": "Shooter",
                "Casual Game": "Casual",
                "Adventure / Point & Click": "Point & Click",
                "Adventure / Point & Click / Education": "Point & Click",
                "Adventure / Point & Click / Role-Playing": "Point & Click",
                "Music / Dancing": "Music",
                "Fighter": "Fighting"
            ]
            saveMappings()
        }
    }

    private func saveMappings() {
        AppSettings.set(settingsKey, value: mappings)
    }
}
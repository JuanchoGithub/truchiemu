import Foundation
import SwiftUI

@MainActor
final class GenreManager: ObservableObject {
    static let shared = GenreManager()

    private let settingsKey = "genreMappings"
    private let hiddenGenresKey = "hiddenGenreDisplayNames"

    @Published private(set) var mappings: [String: String] = [:]
    @Published private(set) var hiddenGenres: Set<String> = []

    private init() {
        loadMappings()
        loadHiddenGenres()
    }

    func effectiveDisplayName(for original: String?) -> String {
        guard let genre = original else { return "Unknown" }
        return mappings[genre] ?? genre
    }

    func getAllDisplayGenres(from roms: [ROM]) -> [String] {
        let names = roms.compactMap { effectiveDisplayName(for: $0.metadata?.genre) }
        return Array(Set(names)).sorted()
    }

    func getVisibleDisplayGenres(from roms: [ROM]) -> [String] {
        getAllDisplayGenres(from: roms).filter { !hiddenGenres.contains($0) }
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

    func isHidden(_ displayName: String) -> Bool {
        hiddenGenres.contains(displayName)
    }

    func toggleHidden(_ displayName: String) {
        if hiddenGenres.contains(displayName) {
            hiddenGenres.remove(displayName)
        } else {
            hiddenGenres.insert(displayName)
        }
        saveHiddenGenres()
    }

    /// Group of display names that are hidden (for badge display)
    var hiddenDisplayNames: [String] {
        hiddenGenres.sorted()
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

    private func loadHiddenGenres() {
        if let loaded: [String] = AppSettings.get(hiddenGenresKey, type: [String].self) {
            hiddenGenres = Set(loaded)
        }
    }

    private func saveHiddenGenres() {
        AppSettings.set(hiddenGenresKey, value: Array(hiddenGenres))
    }
}
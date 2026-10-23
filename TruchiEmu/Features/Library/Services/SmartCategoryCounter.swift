import Foundation

// Computes sidebar counts for every smart category in one pass over the
// library. The sidebar caches the result and recomputes only when the library,
// the category rules, the genre mappings, or the search text change. This
// keeps the hot path (sidebar body evaluation) free of O(ROMs) scans.
@MainActor
enum SmartCategoryCounter {
    static func counts(
        categories: [GameCategory],
        roms: [ROM],
        searchTerms: [String]
    ) -> [String: Int] {
        let smartCategories = categories.filter { $0.isSmart }
        guard !smartCategories.isEmpty else { return [:] }

        // Resolve display genres once per ROM, never once per category.
        let needsGenres = smartCategories.contains { !$0.smartGenres.isEmpty }
        var result: [String: Int] = [:]

        for rom in roms where !rom.isHidden {
            if !searchTerms.isEmpty {
                let matches = searchTerms.allSatisfy {
                    rom.displayName.localizedCaseInsensitiveContains($0)
                }
                if !matches { continue }
            }

            let displayGenres: [String] = needsGenres
                ? GenreManager.shared.effectiveDisplayNames(for: rom.metadata?.genre)
                : []

            for category in smartCategories {
                let isMember = category.smartMember(rom) { _ in
                    displayGenres.contains { category.smartGenres.contains($0) }
                }
                if isMember {
                    result[category.id, default: 0] += 1
                }
            }
        }

        return result
    }
}

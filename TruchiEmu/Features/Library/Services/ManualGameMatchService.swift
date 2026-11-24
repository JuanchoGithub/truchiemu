import Foundation

/// Finds the games that the user can select in the manual match sheet.
///
/// The search uses two sources. The system DAT comes first because it is the
/// same list that the automatic identification uses. The LaunchBox list comes
/// second and adds games that the DAT does not hold.
@MainActor
final class ManualGameMatchService {
    static let shared = ManualGameMatchService()

    private var cachedSystemID: String?
    private var cachedCandidates: [GameMatchCandidate] = []

    private init() {}

    /// All games for a system, sorted by name. The result is cached for the
    /// last system only, because a large list is costly to build.
    func candidates(for systemID: String) async -> [GameMatchCandidate] {
        if cachedSystemID == systemID, !cachedCandidates.isEmpty {
            return cachedCandidates
        }

        var results = await datCandidates(for: systemID)
        results.append(contentsOf: await launchBoxCandidates(for: systemID))
        results.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        cachedSystemID = systemID
        cachedCandidates = results
        return results
    }

    /// Filters the candidates with every token of the query. The query and the
    /// names are diacritic-free and lowercased, so "pokemon" finds "Pokémon".
    nonisolated static func filter(
        _ candidates: [GameMatchCandidate],
        query: String,
        limit: Int = 250
    ) -> [GameMatchCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(candidates.prefix(limit)) }

        let tokens = GameMatchCandidate.searchKey(for: trimmed)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return Array(candidates.prefix(limit)) }

        var results: [GameMatchCandidate] = []
        for candidate in candidates where tokens.allSatisfy({ candidate.searchKey.contains($0) }) {
            results.append(candidate)
            if results.count >= limit { break }
        }
        return results
    }

    // MARK: - DAT

    private func datCandidates(for systemID: String) async -> [GameMatchCandidate] {
        if systemID == "mame" {
            await MAMEUnifiedService.shared.ensureLoaded()
            var seen = Set<String>()
            var results: [GameMatchCandidate] = []
            for entry in MAMEUnifiedService.shared.runnableEntries where !entry.isBIOS {
                let name = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(GameMatchCandidate.searchKey(for: name)).inserted else { continue }
                results.append(GameMatchCandidate(
                    source: .dat,
                    id: entry.shortName,
                    name: name,
                    year: entry.year,
                    publisher: entry.manufacturer,
                    developer: entry.manufacturer,
                    players: entry.players
                ))
            }
            return results
        }

        guard let system = SystemDatabase.system(forID: systemID) else { return [] }
        let database = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)

        var best: [String: GameInfo] = [:]
        for info in database.values {
            let name = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = GameMatchCandidate.searchKey(for: name)
            if let current = best[key] {
                if metadataScore(info) > metadataScore(current) { best[key] = info }
            } else {
                best[key] = info
            }
        }

        return best.values.map { info in
            GameMatchCandidate(
                source: .dat,
                id: info.name,
                name: info.name,
                year: info.year,
                publisher: info.publisher,
                developer: info.developer,
                genre: info.genre,
                players: info.players,
                thumbnailLookupSystemID: info.thumbnailLookupSystemID
            )
        }
    }

    private func metadataScore(_ info: GameInfo) -> Int {
        var score = 0
        if info.year?.isEmpty == false { score += 1 }
        if info.publisher?.isEmpty == false { score += 1 }
        if info.developer?.isEmpty == false { score += 1 }
        if info.genre?.isEmpty == false { score += 1 }
        if info.players != nil { score += 1 }
        return score
    }

    // MARK: - LaunchBox

    private func launchBoxCandidates(for systemID: String) async -> [GameMatchCandidate] {
        let service = LaunchBoxMetadataService.shared
        guard let platformName = service.platformName(forSystemID: systemID) else { return [] }

        // The platform file can hold many megabytes. Read it off the main
        // thread so the sheet stays alive while the list loads.
        let games = await Task.detached(priority: .userInitiated) {
            LaunchBoxMetadataService.loadPlatformGames(platformName: platformName)
        }.value

        var seen = Set<String>()
        var results: [GameMatchCandidate] = []
        for game in games {
            let name = game.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(GameMatchCandidate.searchKey(for: name)).inserted else { continue }
            results.append(GameMatchCandidate(
                source: .launchBox,
                id: String(game.databaseID),
                name: name,
                year: game.releaseYear,
                publisher: game.publisher,
                developer: game.developer,
                genre: game.genres,
                players: game.maxPlayers,
                description: game.overview,
                esrbRating: game.esrb,
                cooperative: game.cooperative,
                boxArtURL: service.boxArtRef(for: game).map { LaunchBoxMetadataService.cdnURL(for: $0) }
            ))
        }
        return results
    }
}

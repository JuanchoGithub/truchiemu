import Foundation

/// One game suggested for another game.
///
/// The engine returns the full `ROM` so callers can open the game info window,
/// launch the game, or draw its box art without another library lookup.
struct SimilarGameMatch: Identifiable {
    let rom: ROM
    let score: Double
    /// The strongest signal behind the match, shown to the user.
    let reason: Reason

    var id: UUID { rom.id }

    enum Reason {
        case genre
        case developer
        case series
        case publisher
        case year
    }
}

/// Offline recommendation engine.
///
/// It compares the target game with the rest of the library using metadata the
/// app already holds: genre, developer, publisher, series title, release year,
/// and player count. The system family then reorders the accepted matches, so a
/// game on the same hardware comes first. There is no network call and no
/// external service, so the results work for every system and never consume an
/// API quota.
enum SimilarGamesEngine {

    // MARK: - Weights

    private static let genreWeight = 0.42
    private static let developerWeight = 0.20
    private static let seriesWeight = 0.20
    private static let publisherWeight = 0.07
    private static let yearWeight = 0.06
    private static let playersWeight = 0.05

    /// Genre, series, or an exact studio match must clear this bar on their
    /// own. Publisher, release year, and player count only refine a match.
    private static let minimumScore = 0.15

    // MARK: - Public API

    static func recommendations(
        for target: ROM,
        in library: [ROM],
        limit: Int = 6
    ) -> [SimilarGameMatch] {
        guard limit > 0 else { return [] }

        let targetProfile = Profile(rom: target)
        guard targetProfile.hasSignal else { return [] }

        var matches: [SimilarGameMatch] = []

        for candidate in library {
            guard candidate.id != target.id,
                  !candidate.isHidden,
                  !candidate.isBios,
                  candidate.category == "game",
                  !candidate.isSwitchAddOn,
                  candidate.mameRomType == nil || candidate.mameRomType == "game",
                  candidate.displayName.caseInsensitiveCompare(target.displayName) != .orderedSame
            else { continue }

            let profile = Profile(rom: candidate)
            guard let match = score(target: targetProfile, candidate: profile, rom: candidate) else { continue }
            matches.append(match)
        }

        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            // Equal scores: keep the list local to the target's system first.
            let lhsSameSystem = lhs.rom.systemID == target.systemID
            let rhsSameSystem = rhs.rom.systemID == target.systemID
            if lhsSameSystem != rhsSameSystem { return lhsSameSystem }
            return lhs.rom.displayName.localizedStandardCompare(rhs.rom.displayName) == .orderedAscending
        }

        if matches.count > limit {
            matches.removeLast(matches.count - limit)
        }
        return matches
    }

    // MARK: - Scoring

    private static func score(
        target: Profile,
        candidate: Profile,
        rom: ROM
    ) -> SimilarGameMatch? {
        var total = 0.0
        // Genre, series, and an exact studio match form the core of a
        // recommendation. Publisher, year, and player count only refine it.
        var coreScore = 0.0
        var contributions: [(weight: Double, reason: SimilarGameMatch.Reason)] = []

        let genreScore = jaccard(target.genres, candidate.genres)
        if genreScore > 0 {
            let weight = genreScore * genreWeight
            total += weight
            coreScore += weight
            contributions.append((weight, .genre))
        }

        if let targetDeveloper = target.developer, let candidateDeveloper = candidate.developer {
            let similarity = companySimilarity(targetDeveloper, candidateDeveloper)
            if similarity > 0 {
                let weight = similarity * developerWeight
                total += weight
                coreScore += weight
                contributions.append((weight, .developer))
            }
        }

        if let targetPublisher = target.publisher, let candidatePublisher = candidate.publisher {
            let similarity = companySimilarity(targetPublisher, candidatePublisher)
            if similarity > 0 {
                let weight = similarity * publisherWeight
                total += weight
                contributions.append((weight, .publisher))
            }
        }

        let seriesSimilarity = seriesSimilarity(target.series, candidate.series)
        if seriesSimilarity > 0 {
            let weight = seriesSimilarity * seriesWeight
            total += weight
            coreScore += weight
            contributions.append((weight, .series))
        }

        if let targetYear = target.year, let candidateYear = candidate.year {
            let difference = abs(targetYear - candidateYear)
            let similarity = max(0, 1 - Double(difference) / 8)
            if similarity > 0 {
                let weight = similarity * yearWeight
                total += weight
                contributions.append((weight, .year))
            }
        }

        total += playerSimilarity(target, candidate) * playersWeight

        guard coreScore >= minimumScore else { return nil }

        // System affinity only reorders the matches above the bar. It must not
        // push a candidate over the bar on its own.
        total += systemAffinity(target: target, candidate: candidate)

        let reason = contributions.max { lhs, rhs in
            // When two signals are close, name the more specific one.
            if abs(lhs.weight - rhs.weight) < 0.02 {
                return reasonPriority(lhs.reason) < reasonPriority(rhs.reason)
            }
            return lhs.weight < rhs.weight
        }?.reason ?? .genre
        return SimilarGameMatch(rom: rom, score: total, reason: reason)
    }

    private static func reasonPriority(_ reason: SimilarGameMatch.Reason) -> Int {
        switch reason {
        case .series: return 4
        case .developer: return 3
        case .genre: return 2
        case .publisher: return 1
        case .year: return 0
        }
    }

    /// Bonus for a candidate on related hardware. Same system wins, then the
    /// same family. An arcade system ID names the emulator set (MAME, FBNeo,
    /// Neo Geo), not the board, so every arcade entry is a peer.
    private static func systemAffinity(target: Profile, candidate: Profile) -> Double {
        guard let targetSystem = target.systemID,
              let candidateSystem = candidate.systemID,
              let targetType = target.systemType,
              let candidateType = candidate.systemType,
              targetType == candidateType
        else { return 0 }

        if targetType == .arcade { return 0.05 }
        return targetSystem == candidateSystem ? 0.08 : 0.05
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }

    /// Company names arrive with legal suffixes and generic words. Exact names
    /// score full; a contained name ("Nintendo" vs "Nintendo EAD") scores lower.
    private static func companySimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        guard lhs.count >= 4, rhs.count >= 4 else { return 0 }
        let lhsWords = " \(lhs) "
        let rhsWords = " \(rhs) "
        return (lhsWords.contains(rhsWords) || rhsWords.contains(lhsWords)) ? 0.55 : 0
    }

    /// Titles are reduced to their first significant words. Sequels, ports, and
    /// spin-offs of one franchise share that prefix.
    private static func seriesSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let shared = zip(lhs, rhs).prefix { pair in pair.0 == pair.1 }.count
        let shorterCount = min(lhs.count, rhs.count)

        if shared >= shorterCount { return 1 }
        if shared >= 2 { return 0.8 }
        if shared == 1, lhs[0] == rhs[0], lhs[0].count >= 5 { return 0.6 }
        // "Zelda" and "Legend of Zelda" share one franchise word in a different position.
        let lhsWords = Set(lhs)
        let rhsWords = Set(rhs)
        if lhsWords.isSubset(of: rhsWords) || rhsWords.isSubset(of: lhsWords) { return 0.8 }
        return 0
    }

    private static func playerSimilarity(_ lhs: Profile, _ rhs: Profile) -> Double {
        var score = 0.0
        if lhs.cooperative && rhs.cooperative { score += 0.6 }
        if lhs.players >= 2 && rhs.players >= 2 { score += 0.4 }
        return score
    }

    // MARK: - Profile

    private struct Profile {
        let genres: Set<String>
        let developer: String?
        let publisher: String?
        let series: [String]
        let year: Int?
        let players: Int
        let cooperative: Bool
        let systemID: String?
        let systemType: SystemType?

        init(rom: ROM) {
            let metadata = rom.metadata
            genres = Self.genres(from: metadata?.genre)
            developer = Self.company(from: metadata?.developer)
            publisher = Self.company(from: metadata?.publisher)
            series = Self.seriesWords(from: rom.displayName)
            year = Self.year(from: metadata?.year)
            players = metadata?.players ?? 1
            cooperative = metadata?.cooperative ?? false
            systemID = rom.systemID
            systemType = rom.systemID.map(SystemType.type(forSystemID:))
        }

        var hasSignal: Bool {
            !genres.isEmpty || developer != nil || publisher != nil || !series.isEmpty
        }

        private static func genres(from raw: String?) -> Set<String> {
            guard let raw, !raw.isEmpty else { return [] }
            let separators = CharacterSet(charactersIn: ",/|;")
            var result = Set<String>()
            for part in raw.components(separatedBy: separators) {
                let key = normalized(part)
                guard !key.isEmpty else { continue }
                result.insert(genreSynonyms[key] ?? key)
            }
            return result
        }

        private static func company(from raw: String?) -> String? {
            guard let raw else { return nil }
            let words = normalized(raw).split(separator: " ").map(String.init)
            let kept = words.filter { !companyNoise.contains($0) }
            let name = kept.joined(separator: " ")
            return name.isEmpty ? nil : name
        }

        private static func year(from raw: String?) -> Int? {
            guard let raw, let value = Int(raw.prefix(4)), value > 1900 else { return nil }
            return value
        }

        private static func seriesWords(from name: String) -> [String] {
            var words = normalized(name).split(separator: " ").map(String.init)
            words = words.filter { word in
                if word.allSatisfy(\.isNumber) { return false }
                if romanNumerals.contains(word) { return false }
                if seriesNoise.contains(word) { return false }
                return true
            }
            return words.count > 2 ? Array(words.prefix(2)) : words
        }
    }

    // MARK: - Text normalization

    private static let genreSynonyms: [String: String] = [
        "platform": "platform",
        "platformer": "platform",
        "shooter": "shooter",
        "shoot em up": "shooter",
        "shmup": "shooter",
        "role playing": "rpg",
        "role playing game": "rpg",
        "role playing rpg": "rpg",
        "rpg": "rpg",
        "beat em up": "beat em up",
        "beat em up brawler": "beat em up",
        "brawler": "beat em up",
        "run and gun": "run and gun",
        "fighting": "fighting",
        "versus fighting": "fighting",
        "racing": "racing",
        "driving": "racing",
        "racing driving": "racing",
        "strategy": "strategy",
        "real time strategy": "strategy",
        "turn based strategy": "strategy",
        "puzzle": "puzzle",
        "puzzle game": "puzzle",
        "sports": "sports",
        "sports game": "sports",
        "adventure": "adventure",
        "adventure game": "adventure",
        "action": "action",
        "action game": "action",
        "action adventure": "action adventure",
    ]

    private static let companyNoise: Set<String> = [
        "inc", "incorporated", "ltd", "limited", "llc", "co", "corp", "corporation",
        "company", "gmbh", "kk", "sa", "sarl", "pty", "the", "of", "and",
        "studios", "studio", "entertainment", "interactive", "software", "games", "game",
    ]

    private static let seriesNoise: Set<String> = [
        "the", "a", "an", "of", "and", "super", "ultra", "new", "vs", "versus",
        "vol", "volume", "part", "chapter", "episode",
    ]

    private static let romanNumerals: Set<String> = [
        "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi",
        "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx",
    ]

    private static let tokenSeparators = CharacterSet.alphanumerics.inverted

    private static func normalized(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: tokenSeparators)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

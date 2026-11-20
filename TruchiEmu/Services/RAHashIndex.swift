import Foundation

// MARK: - RA Game List Entry

/// One game in a RetroAchievements console list.
///
/// The RetroAchievements API uses mixed key names. The decoder accepts the
/// names that the API sends and the names that the local files use.
struct RAGameListEntry: Decodable, Sendable {
    let id: Int
    let title: String
    let consoleID: Int
    let consoleName: String
    let hashes: [String]

    enum CodingKeys: String, CodingKey {
        case ID, Title, ConsoleID, ConsoleName, Hashes
        case id, title, consoleID, consoleName, hashes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode ID (handles string/int and case variants)
        if let value = try? container.decode(Int.self, forKey: .ID) { id = value }
        else if let value = try? container.decode(Int.self, forKey: .id) { id = value }
        else if let text = try? container.decode(String.self, forKey: .ID) { id = Int(text) ?? 0 }
        else if let text = try? container.decode(String.self, forKey: .id) { id = Int(text) ?? 0 }
        else { id = 0 }

        // Decode Title
        title = (try? container.decode(String.self, forKey: .Title))
            ?? (try? container.decode(String.self, forKey: .title))
            ?? "Unknown"

        // Decode ConsoleID
        if let value = try? container.decode(Int.self, forKey: .ConsoleID) { consoleID = value }
        else if let value = try? container.decode(Int.self, forKey: .consoleID) { consoleID = value }
        else if let text = try? container.decode(String.self, forKey: .ConsoleID) { consoleID = Int(text) ?? 0 }
        else if let text = try? container.decode(String.self, forKey: .consoleID) { consoleID = Int(text) ?? 0 }
        else { consoleID = 0 }

        // Decode ConsoleName
        consoleName = (try? container.decode(String.self, forKey: .ConsoleName))
            ?? (try? container.decode(String.self, forKey: .consoleName))
            ?? ""

        // Decode Hashes
        hashes = (try? container.decode([String].self, forKey: .Hashes))
            ?? (try? container.decode([String].self, forKey: .hashes))
            ?? []
    }
}

// MARK: - RA Hash Index

/// A read-only index of the RetroAchievements game lists.
///
/// The index holds all games in memory. One build replaces many database
/// queries. The old code loaded every game of a console for every ROM. That
/// took 121 seconds for 2,108 ROMs. The build of all 25 cached lists takes
/// about 0.2 seconds.
struct RAHashIndex: Sendable {

    /// One game of the index.
    struct Game: Sendable {
        let id: Int
        let title: String
        let consoleID: Int
        let hashes: [String]
    }

    /// Lower-case file hash to game.
    let gamesByHash: [String: Game]

    /// Console ID to the games of that console.
    let gamesByConsole: [Int: [Game]]

    /// Console ID to the normalized titles of that console. The titles are
    /// used for the name search.
    private let titlesByConsole: [Int: ConsoleTitles]

    /// True when the index holds no games.
    var isEmpty: Bool { gamesByHash.isEmpty }

    /// The number of games in the index.
    var gameCount: Int { gamesByConsole.values.reduce(0) { $0 + $1.count } }

    init(games: [Game]) {
        var byHash: [String: Game] = [:]
        var byConsole: [Int: [Game]] = [:]

        for game in games {
            byConsole[game.consoleID, default: []].append(game)
            for hash in game.hashes {
                byHash[hash.lowercased()] = game
            }
        }

        var titles: [Int: ConsoleTitles] = [:]
        for (consoleID, consoleGames) in byConsole {
            titles[consoleID] = ConsoleTitles(
                titles: consoleGames.map { (Self.normalizeTitle($0.title), $0) }
            )
        }

        self.gamesByHash = byHash
        self.gamesByConsole = byConsole
        self.titlesByConsole = titles
    }

    // MARK: - Lookups

    /// Finds the game with the given file hash.
    /// - Parameter consoleID: The console to search. Use nil to search all
    ///   consoles.
    func game(hash: String, consoleID: Int? = nil) -> Game? {
        guard let match = gamesByHash[hash.lowercased()] else { return nil }
        if let consoleID = consoleID, match.consoleID != consoleID { return nil }
        return match
    }

    /// Finds the first game of the console whose title contains the text.
    ///
    /// The search uses the same rules as the old database search. The search
    /// ignores case and accents.
    func game(titleContains text: String, consoleID: Int) -> Game? {
        let query = Self.normalizeTitle(text)
        guard !query.isEmpty else { return nil }
        guard let entry = titlesByConsole[consoleID] else { return nil }

        // The search uses one native string search over all titles of the
        // console. The old code ran one search per title. That took 0.96
        // seconds for 2,108 ROMs.
        guard !query.contains(ConsoleTitles.separator) else {
            return entry.firstGame(containing: query)
        }

        var searchStart = 0
        let length = entry.joined.length
        while searchStart < length {
            let searchRange = NSRange(location: searchStart, length: length - searchStart)
            let range = entry.joined.range(of: query, options: [], range: searchRange)
            if range.location == NSNotFound { break }

            // A match that crosses the separator between two titles is not a
            // match. The search continues after the match.
            if !entry.joined.substring(with: range).contains(ConsoleTitles.separator) {
                if let index = entry.gameIndex(atUTF16Offset: range.location) {
                    return entry.games[index]
                }
            }
            searchStart = range.location + range.length
        }
        return nil
    }

    // MARK: - Helpers

    /// Removes the file extension, the underscores and the tags from a ROM
    /// name. The result is the text that the name search uses.
    static func cleanedRomTitle(_ title: String) -> String {
        var cleaned = title

        if let lastDotIndex = cleaned.lastIndex(of: ".") {
            cleaned = String(cleaned[..<lastDotIndex])
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")

        if let regex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: .caseInsensitive) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                options: [],
                range: NSRange(location: 0, length: cleaned.utf16.count),
                withTemplate: ""
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Makes a title comparable. The result ignores case and accents.
    static func normalizeTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // MARK: - Console Titles

    /// The normalized titles of one console.
    ///
    /// The struct holds all titles in one string. One separator is between
    /// the titles. The name search uses one native string search over this
    /// string. The old code ran one search per title.
    ///
    /// The struct uses `NSString` because its search is about three times
    /// faster than the search of `String`. An `NSString` does not change
    /// after it is built. The struct is therefore safe to use from more than
    /// one thread.
    private struct ConsoleTitles: @unchecked Sendable {
        /// The separator between two titles. The character is a control
        /// character. It does not appear in a title.
        static let separator: Character = "\u{1}"

        /// All normalized titles of the console.
        let joined: NSString

        /// The UTF-16 offset of each title in `joined`.
        let starts: [Int]

        /// The game of each title.
        let games: [Game]

        /// The number of titles.
        var count: Int { games.count }

        init(titles: [(title: String, game: Game)]) {
            var units: [UInt16] = []
            var starts: [Int] = []
            starts.reserveCapacity(titles.count)

            for item in titles {
                starts.append(units.count)
                units.append(contentsOf: item.title.utf16)
                units.append(0x01)
            }

            self.joined = NSString(string: String(decoding: units, as: UTF16.self))
            self.starts = starts
            self.games = titles.map(\.game)
        }

        /// The index of the title that holds the UTF-16 offset.
        func gameIndex(atUTF16Offset offset: Int) -> Int? {
            var low = 0
            var high = starts.count - 1
            var found = -1

            while low <= high {
                let middle = (low + high) / 2
                if starts[middle] <= offset {
                    found = middle
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            return found >= 0 ? found : nil
        }

        /// The first game whose title contains the text. The function is the
        /// slow path. It is only used when the text holds the separator.
        func firstGame(containing text: String) -> Game? {
            for (index, start) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1] : joined.length
                let titleRange = NSRange(location: start, length: max(0, end - start - 1))
                if joined.substring(with: titleRange).contains(text) {
                    let game = games[index]
                    if game.id > 0 { return game }
                }
            }
            return nil
        }
    }

    // MARK: - Build

    /// Builds the index from the cached list files.
    ///
    /// The function reads the files in a background task. The files hold all
    /// data that the match phase needs: the game ID, the title, the console
    /// and the file hashes.
    ///
    /// - Parameters:
    ///   - folder: The folder that holds the cached list files.
    ///   - consoleIDs: The consoles to load. Use nil to load all consoles.
    static func build(from folder: URL, consoleIDs: Set<Int>? = nil) async -> RAHashIndex {
        await Task.detached(priority: .userInitiated) {
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension == "json" }

            var games: [Game] = []
            for file in files {
                if let consoleIDs = consoleIDs {
                    let prefix = file.lastPathComponent.components(separatedBy: "_").first ?? ""
                    guard let consoleID = Int(prefix), consoleIDs.contains(consoleID) else { continue }
                }

                guard let data = try? Data(contentsOf: file),
                      let entries = try? JSONDecoder().decode([RAGameListEntry].self, from: data)
                else { continue }

                for entry in entries {
                    games.append(Game(
                        id: entry.id,
                        title: entry.title,
                        consoleID: entry.consoleID,
                        hashes: entry.hashes
                    ))
                }
            }

            return RAHashIndex(games: games)
        }.value
    }
}

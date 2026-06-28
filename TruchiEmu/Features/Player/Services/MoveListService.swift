import Foundation

@MainActor
class MoveListService: ObservableObject {
    static let shared = MoveListService()
    @Published private(set) var currentGameData: FightDataGame?
    @Published private(set) var selectedCharacter: FightDataCharacter?
    @Published private(set) var availableCharacters: [FightDataCharacter] = []
    @Published private(set) var controlLabels: [String: String] = [:]
    @Published private(set) var controlAbbreviations: [String: String] = [:]
    @Published private(set) var categoryLabels: [String: String] = [:]
    @Published private(set) var commonNotes: [String] = []
    @Published private(set) var cheatNotes: [String] = []

    private var cachedGames: [String: FightDataGame] = [:]
    private var index: FightDataIndex?

    private static let arcadeSystemIDs: Set<String> = ["mame", "fba", "fbneo", "arcade", "mame078", "mame2010", "mame2016"]

    func loadGameData(for rom: ROM) {
        let shortName = rom.shortNameForMAME.lowercased()
        let systemID = rom.systemID ?? "default"
        let romName = rom.filenameWithoutExtension.lowercased()

        let cacheKey = shortName.isEmpty ? romName : shortName
        if let cached = cachedGames[cacheKey] {
            applyGameData(cached)
            return
        }

        if let customGame = loadCustomGameMatch(shortName: shortName, romName: romName, displayName: rom.displayName, systemID: systemID) {
            cachedGames[cacheKey] = customGame
            applyGameData(customGame)
            return
        }

        let fightIndex = loadIndex()
        let isArcade = Self.arcadeSystemIDs.contains(systemID.lowercased())

        let matchedFile: String?
        if isArcade {
            matchedFile = findArcadeMatch(shortName: shortName, romName: romName, index: fightIndex)
        } else {
            matchedFile = findConsoleMatch(displayName: rom.displayName, index: fightIndex)
        }

        guard let filename = matchedFile else {
            currentGameData = nil
            selectedCharacter = nil
            availableCharacters = []
            controlLabels = [:]
            controlAbbreviations = [:]
            categoryLabels = [:]
            commonNotes = []
            cheatNotes = []
            return
        }

        if let game = loadFightDataFile(filename) {
            cachedGames[cacheKey] = game
            applyGameData(game)
            return
        }

        currentGameData = nil
        selectedCharacter = nil
        availableCharacters = []
        controlLabels = [:]
        controlAbbreviations = [:]
        categoryLabels = [:]
        commonNotes = []
        cheatNotes = []
    }

    func selectCharacter(_ character: FightDataCharacter) {
        selectedCharacter = character
        if let game = currentGameData {
            let key = "movelist_\(game.name)_character"
            AppSettings.set(key, value: character.name)
        }
    }

    func clearSelectedCharacter() {
        if let game = currentGameData {
            let key = "movelist_\(game.name)_character"
            AppSettings.remove(key)
        }
        selectedCharacter = nil
    }

    func loadIndexEntries() -> [FightDataIndexEntry] {
        loadIndex().games
    }

    func loadGameByFile(_ filename: String) -> FightDataGame? {
        if let cached = cachedGames[filename] { return cached }
        guard let game = loadFightDataFile(filename) else { return nil }
        cachedGames[filename] = game
        return game
    }

    func resolveButtonLabel(_ controlKey: String) -> String {
        if let abbr = controlAbbreviations[controlKey] {
            return abbr
        }
        if let label = controlLabels[controlKey] {
            return label
        }
        return controlKey
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    func resolveCategoryLabel(_ categoryKey: String, gameCategories: [String: String] = [:]) -> String {
        let labels = gameCategories.isEmpty ? categoryLabels : gameCategories
        if let label = labels[categoryKey] {
            return label
        }
        let stripped = categoryKey.replacingOccurrences(of: "_", with: "")
        if let label = labels[stripped] {
            return label
        }
        return stripped
    }

    private func applyGameData(_ game: FightDataGame) {
        currentGameData = game
        controlLabels = game.controls
        controlAbbreviations = game.controlAbbr ?? [:]
        categoryLabels = game.categories
        commonNotes = game.commonNotes ?? []
        cheatNotes = game.cheatNotes ?? []
        availableCharacters = game.characters

        let savedCharName: String? = AppSettings.get("movelist_\(game.name)_character", type: String.self)
        if let savedName = savedCharName,
           let saved = game.characters.first(where: { $0.name == savedName }) {
            selectedCharacter = saved
        } else {
            selectedCharacter = nil
        }
    }

    private func loadIndex() -> FightDataIndex {
        if let existing = index {
            return existing
        }
        guard let url = Bundle.main.url(forResource: "fightdata_index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(FightDataIndex.self, from: data) else {
            let empty = FightDataIndex(schemaVersion: 1, games: [])
            index = empty
            return empty
        }
        index = loaded
        return loaded
    }

    private func findArcadeMatch(shortName: String, romName: String, index: FightDataIndex) -> String? {
        for entry in index.games {
            for romId in entry.romIds {
                let lower = romId.lowercased()
                if shortName == lower || romName == lower {
                    return entry.file
                }
            }
        }
        return nil
    }

    private func findConsoleMatch(displayName: String, index: FightDataIndex) -> String? {
        let normalized = GameNameFormatter.normalizedComparisonKey(displayName)
        for entry in index.games {
            if entry.normalizedName == normalized {
                return entry.file
            }
            if entry.aliases.contains(where: { normalizeForComparison($0) == normalized }) {
                return entry.file
            }
        }
        let variants = ROMIdentifierService.romanNumeralVariants(of: normalized)
        for variant in variants {
            for entry in index.games {
                if entry.normalizedName == variant {
                    return entry.file
                }
                if entry.aliases.contains(where: { normalizeForComparison($0) == variant }) {
                    return entry.file
                }
            }
        }
        return nil
    }

    private func normalizeForComparison(_ string: String) -> String {
        GameNameFormatter.normalizedComparisonKey(string)
    }

    private func loadFightDataFile(_ filename: String) -> FightDataGame? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FightDataGame.self, from: data)
    }

    private func loadCustomGameMatch(shortName: String, romName: String, displayName: String, systemID: String) -> FightDataGame? {
        let storageService = MoveListStorageService.shared
        let isArcade = Self.arcadeSystemIDs.contains(systemID.lowercased())

        let customGamesDir = SaveDirectoryManager.shared.systemDirectory.appendingPathComponent("FightData")
        if let files = try? FileManager.default.contentsOfDirectory(at: customGamesDir, includingPropertiesForKeys: nil) {
            for fileURL in files where fileURL.pathExtension == "json" {
                guard let data = try? Data(contentsOf: fileURL),
                      let game = try? JSONDecoder().decode(FightDataGame.self, from: data) else { continue }
                if isArcade {
                    for romId in game.romIds {
                        let lower = romId.lowercased()
                        if shortName == lower || romName == lower { return game }
                    }
                } else {
                    let normalized = GameNameFormatter.normalizedComparisonKey(displayName)
                    if GameNameFormatter.normalizedComparisonKey(game.name) == normalized { return game }
                }
            }
        }

        for entry in storageService.customGames {
            guard let data = entry.gameJSON.data(using: .utf8),
                  let game = try? JSONDecoder().decode(FightDataGame.self, from: data) else { continue }
            if isArcade {
                for romId in game.romIds {
                    let lower = romId.lowercased()
                    if shortName == lower || romName == lower { return game }
                }
            } else {
                let normalized = GameNameFormatter.normalizedComparisonKey(displayName)
                if GameNameFormatter.normalizedComparisonKey(game.name) == normalized { return game }
            }
        }

        return nil
    }
}

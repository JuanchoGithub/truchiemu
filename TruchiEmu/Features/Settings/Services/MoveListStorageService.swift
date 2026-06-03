import Foundation
import SwiftData

@MainActor
class MoveListStorageService: ObservableObject {
    static let shared = MoveListStorageService()

    @Published private(set) var moveEntries: [MoveListEntry] = []
    @Published private(set) var customGames: [CustomGameDataEntry] = []
    private var hasLoaded = false

    private var context: ModelContext {
        SwiftDataContainer.shared.mainContext
    }

    private init() {}

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadAll()
        migrateCommonCommandEntries()
    }

    private func loadAll() {
        let ctx = context
        let moveDesc = FetchDescriptor<MoveListEntry>(sortBy: [SortDescriptor(\.compositeKey)])
        moveEntries = (try? ctx.fetch(moveDesc)) ?? []

        let gameDesc = FetchDescriptor<CustomGameDataEntry>(sortBy: [SortDescriptor(\.gameName)])
        customGames = (try? ctx.fetch(gameDesc)) ?? []
    }

    private func migrateCommonCommandEntries() {
        let migrationKey = "movelist_common_migration_done"
        if AppSettings.getBool(migrationKey, defaultValue: false) { return }

        let gameNames = Set(moveEntries.map(\.gameName))
        for gameName in gameNames {
            let commonMoveIds: Set<String>
            if let entry = MoveListService.shared.loadIndexEntries().first(where: { $0.name == gameName }),
               let game = MoveListService.shared.loadGameByFile(entry.file),
               let commons = game.commonCommands {
                commonMoveIds = Set(commons.map(\.id))
            } else if let customEntry = getCustomGame(name: gameName),
                      let data = customEntry.gameJSON.data(using: .utf8),
                      let game = try? JSONDecoder().decode(FightDataGame.self, from: data),
                      let commons = game.commonCommands {
                commonMoveIds = Set(commons.map(\.id))
            } else {
                continue
            }

            let entriesToMigrate = moveEntries.filter { entry in
                entry.gameName == gameName &&
                entry.characterName != "__common__" &&
                commonMoveIds.contains(entry.moveId) &&
                entry.moveId != "__char_hidden__"
            }

            for entry in entriesToMigrate {
                let newKey = "\(gameName)::__common__::\(entry.moveId)"

                if let existing = moveEntries.first(where: { $0.compositeKey == newKey }) {
                    if entry.isFavorite { existing.isFavorite = true }
                    if entry.isHidden { existing.isHidden = true }
                    if entry.isOverride, let oj = entry.overrideJSON {
                        existing.isOverride = true
                        existing.overrideJSON = oj
                    }
                    if entry.isCustom, let cj = entry.customMoveJSON {
                        existing.isCustom = true
                        existing.customMoveJSON = cj
                    }
                    context.delete(entry)
                    moveEntries.removeAll { $0.compositeKey == entry.compositeKey }
                } else {
                    entry.characterName = "__common__"
                    entry.compositeKey = newKey
                }
            }
        }

        if !moveEntries.isEmpty || context.hasChanges {
            try? context.save()
        }
        AppSettings.setBool(migrationKey, value: true)
    }

    // MARK: - MoveListEntry CRUD

    func toggleFavorite(gameName: String, characterName: String, moveId: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        if let existing = moveEntries.first(where: { $0.compositeKey == key }) {
            let favoriteCount = moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName && $0.isFavorite }.count
            if !existing.isFavorite && favoriteCount >= 3 { return }
            existing.isFavorite.toggle()
            try? context.save()
        } else {
            let favoriteCount = moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName && $0.isFavorite }.count
            if favoriteCount >= 3 { return }
            let entry = MoveListEntry(compositeKey: key, gameName: gameName, characterName: characterName, moveId: moveId, isFavorite: true)
            context.insert(entry)
            try? context.save()
            moveEntries.append(entry)
        }
    }

    func toggleHidden(gameName: String, characterName: String, moveId: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        if let existing = moveEntries.first(where: { $0.compositeKey == key }) {
            existing.isHidden.toggle()
            try? context.save()
        } else {
            let entry = MoveListEntry(compositeKey: key, gameName: gameName, characterName: characterName, moveId: moveId, isHidden: true)
            context.insert(entry)
            try? context.save()
            moveEntries.append(entry)
        }
    }

    func saveOverride(gameName: String, characterName: String, moveId: String, overrideJSON: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        if let existing = moveEntries.first(where: { $0.compositeKey == key }) {
            existing.isOverride = true
            existing.overrideJSON = overrideJSON
            try? context.save()
        } else {
            let entry = MoveListEntry(compositeKey: key, gameName: gameName, characterName: characterName, moveId: moveId, isOverride: true, overrideJSON: overrideJSON)
            context.insert(entry)
            try? context.save()
            moveEntries.append(entry)
        }
    }

    func resetOverride(gameName: String, characterName: String, moveId: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        guard let existing = moveEntries.first(where: { $0.compositeKey == key }) else { return }
        existing.isOverride = false
        existing.overrideJSON = nil
        if !existing.isFavorite && !existing.isHidden && !existing.isCustom {
            context.delete(existing)
            moveEntries.removeAll { $0.compositeKey == key }
        }
        try? context.save()
    }

    func addCustomMove(gameName: String, characterName: String, moveId: String, customMoveJSON: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        if moveEntries.contains(where: { $0.compositeKey == key }) { return }
        let entry = MoveListEntry(compositeKey: key, gameName: gameName, characterName: characterName, moveId: moveId, isCustom: true, customMoveJSON: customMoveJSON)
        context.insert(entry)
        try? context.save()
        moveEntries.append(entry)
    }

    func deleteCustomMove(gameName: String, characterName: String, moveId: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        guard let existing = moveEntries.first(where: { $0.compositeKey == key }) else { return }
        context.delete(existing)
        moveEntries.removeAll { $0.compositeKey == key }
        try? context.save()
    }

    func deleteEntry(_ entry: MoveListEntry) {
        loadIfNeeded()
        context.delete(entry)
        moveEntries.removeAll { $0.compositeKey == entry.compositeKey }
        try? context.save()
    }

    // MARK: - Query helpers

    func getFavorites(gameName: String, characterName: String) -> [MoveListEntry] {
        loadIfNeeded()
        return moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName && $0.isFavorite }
    }

    func getHidden(gameName: String, characterName: String) -> [MoveListEntry] {
        loadIfNeeded()
        return moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName && $0.isHidden }
    }

    func getOverrides(gameName: String, characterName: String) -> [MoveListEntry] {
        loadIfNeeded()
        return moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName && $0.isOverride }
    }

    func getCustomMoves(gameName: String, characterName: String) -> [MoveListEntry] {
        loadIfNeeded()
        return moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName && $0.isCustom }
    }

    func getEntriesForGame(gameName: String, characterName: String? = nil) -> [MoveListEntry] {
        loadIfNeeded()
        return moveEntries.filter { entry in
            entry.gameName == gameName && (characterName == nil || entry.characterName == characterName)
        }
    }

    func getGamesWithCustomData() -> [String] {
        loadIfNeeded()
        let gameNames = Set(moveEntries.map(\.gameName))
        return gameNames.sorted()
    }

    func getCharactersWithCustomData(gameName: String) -> [String] {
        loadIfNeeded()
        let charNames = Set(moveEntries.filter { $0.gameName == gameName }.map(\.characterName))
        return charNames.sorted()
    }

    func isFavorite(gameName: String, characterName: String, moveId: String) -> Bool {
        loadIfNeeded()
        return moveEntries.contains { $0.compositeKey == "\(gameName)::\(characterName)::\(moveId)" && $0.isFavorite }
    }

    func isHidden(gameName: String, characterName: String, moveId: String) -> Bool {
        loadIfNeeded()
        return moveEntries.contains { $0.compositeKey == "\(gameName)::\(characterName)::\(moveId)" && $0.isHidden }
    }

    func getOverride(gameName: String, characterName: String, moveId: String) -> MoveListEntry? {
        loadIfNeeded()
        return moveEntries.first { $0.compositeKey == "\(gameName)::\(characterName)::\(moveId)" && $0.isOverride }
    }

    // MARK: - CustomGameDataEntry CRUD

    func addCustomGame(name: String, gameJSON: String, isImported: Bool = false) {
        loadIfNeeded()
        if customGames.contains(where: { $0.gameName == name }) { return }
        let entry = CustomGameDataEntry(gameName: name, gameJSON: gameJSON, isImported: isImported)
        context.insert(entry)
        try? context.save()
        customGames.append(entry)
    }

    func updateCustomGame(name: String, gameJSON: String) {
        loadIfNeeded()
        guard let existing = customGames.first(where: { $0.gameName == name }) else { return }
        existing.gameJSON = gameJSON
        existing.modifiedAt = Date()
        try? context.save()
    }

    func deleteCustomGame(name: String) {
        loadIfNeeded()
        guard let existing = customGames.first(where: { $0.gameName == name }) else { return }
        context.delete(existing)
        customGames.removeAll { $0.gameName == name }

        let relatedEntries = moveEntries.filter { $0.gameName == name }
        for entry in relatedEntries {
            context.delete(entry)
        }
        moveEntries.removeAll { $0.gameName == name }
        try? context.save()
    }

    func getCustomGame(name: String) -> CustomGameDataEntry? {
        loadIfNeeded()
        return customGames.first { $0.gameName == name }
    }

    func importGameJSON(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let name = json["name"] as? String,
        let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]),
        let jsonString = String(data: jsonData, encoding: .utf8) else { return false }

        addCustomGame(name: name, gameJSON: jsonString, isImported: true)
        return true
    }

    // MARK: - Character-level operations

    func toggleCharacterHidden(gameName: String, characterName: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::__char_hidden__"

        if let existing = moveEntries.first(where: { $0.compositeKey == key }) {
            existing.isHidden.toggle()
            try? context.save()
        } else {
            let entry = MoveListEntry(compositeKey: key, gameName: gameName, characterName: characterName, moveId: "__char_hidden__", isHidden: true)
            context.insert(entry)
            try? context.save()
            moveEntries.append(entry)
        }
    }

    func isCharacterHidden(gameName: String, characterName: String) -> Bool {
        loadIfNeeded()
        return moveEntries.contains { $0.compositeKey == "\(gameName)::\(characterName)::__char_hidden__" && $0.isHidden }
    }

    func updateCustomMove(gameName: String, characterName: String, moveId: String, customMoveJSON: String) {
        loadIfNeeded()
        let key = "\(gameName)::\(characterName)::\(moveId)"

        guard let existing = moveEntries.first(where: { $0.compositeKey == key && $0.isCustom }) else { return }
        existing.customMoveJSON = customMoveJSON
        try? context.save()
    }

    func addCharacterToBundledGame(gameName: String, characterName: String) {
        loadIfNeeded()
        addCustomGame(name: "__char_override__\(gameName)", gameJSON: "{}", isImported: false)
    }

    func deleteCharacter(gameName: String, characterName: String) {
        loadIfNeeded()
        let relatedEntries = moveEntries.filter { $0.gameName == gameName && $0.characterName == characterName }
        for entry in relatedEntries {
            context.delete(entry)
        }
        moveEntries.removeAll { $0.gameName == gameName && $0.characterName == characterName }
        try? context.save()
    }
}

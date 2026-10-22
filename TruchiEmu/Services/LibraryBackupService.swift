import Foundation

// Database-external backup of per-game data, keyed by stable identity.
// The SwiftData store can be lost (crash, corrupt file). This JSON file
// lives next to it and restores favorites, playtime, core choice, custom
// names and categories when games are re-added.
@MainActor
enum LibraryBackupService {
    struct GameBackup: Codable {
        var isFavorite: Bool = false
        var totalPlaytimeSeconds: Double = 0
        var timesPlayed: Int = 0
        var lastPlayed: Date?
        var selectedCoreID: String?
        var customName: String?
        var useCustomCore: Bool = false
        var dateAdded: Date?
    }

    struct CategoryBackup: Codable {
        var id: String
        var name: String
        var iconName: String
        var customIconPath: String?
        var colorHex: String
        var sortOrder: Int
        var gameKeys: [String]
        var isSmart: Bool = false
        var smartQuery: String = ""
        var smartDisabledSystemIDs: [String] = []
        var smartEnabledSystemIDs: [String] = []
        var smartFollowsNewSystems: Bool = true
        var smartActiveFilters: [String] = []
        var smartGenres: [String] = []
        var smartIncludedGameKeys: [String] = []
        var smartExcludedGameKeys: [String] = []

        enum CodingKeys: String, CodingKey {
            case id, name, iconName, customIconPath, colorHex, sortOrder, gameKeys
            case isSmart, smartQuery, smartDisabledSystemIDs, smartEnabledSystemIDs
            case smartFollowsNewSystems, smartActiveFilters
            case smartGenres, smartIncludedGameKeys, smartExcludedGameKeys
        }

        init(
            id: String,
            name: String,
            iconName: String,
            customIconPath: String?,
            colorHex: String,
            sortOrder: Int,
            gameKeys: [String],
            isSmart: Bool = false,
            smartQuery: String = "",
            smartDisabledSystemIDs: [String] = [],
            smartEnabledSystemIDs: [String] = [],
            smartFollowsNewSystems: Bool = true,
            smartActiveFilters: [String] = [],
            smartGenres: [String] = [],
            smartIncludedGameKeys: [String] = [],
            smartExcludedGameKeys: [String] = []
        ) {
            self.id = id
            self.name = name
            self.iconName = iconName
            self.customIconPath = customIconPath
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.gameKeys = gameKeys
            self.isSmart = isSmart
            self.smartQuery = smartQuery
            self.smartDisabledSystemIDs = smartDisabledSystemIDs
            self.smartEnabledSystemIDs = smartEnabledSystemIDs
            self.smartFollowsNewSystems = smartFollowsNewSystems
            self.smartActiveFilters = smartActiveFilters
            self.smartGenres = smartGenres
            self.smartIncludedGameKeys = smartIncludedGameKeys
            self.smartExcludedGameKeys = smartExcludedGameKeys
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "gamecontroller.fill"
            customIconPath = try container.decodeIfPresent(String.self, forKey: .customIconPath)
            colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "007AFF"
            sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
            gameKeys = try container.decodeIfPresent([String].self, forKey: .gameKeys) ?? []
            isSmart = try container.decodeIfPresent(Bool.self, forKey: .isSmart) ?? false
            smartQuery = try container.decodeIfPresent(String.self, forKey: .smartQuery) ?? ""
            smartDisabledSystemIDs = try container.decodeIfPresent([String].self, forKey: .smartDisabledSystemIDs) ?? []
            smartEnabledSystemIDs = try container.decodeIfPresent([String].self, forKey: .smartEnabledSystemIDs) ?? []
            smartFollowsNewSystems = try container.decodeIfPresent(Bool.self, forKey: .smartFollowsNewSystems) ?? true
            smartActiveFilters = try container.decodeIfPresent([String].self, forKey: .smartActiveFilters) ?? []
            smartGenres = try container.decodeIfPresent([String].self, forKey: .smartGenres) ?? []
            smartIncludedGameKeys = try container.decodeIfPresent([String].self, forKey: .smartIncludedGameKeys) ?? []
            smartExcludedGameKeys = try container.decodeIfPresent([String].self, forKey: .smartExcludedGameKeys) ?? []
        }
    }

    struct Payload: Codable {
        var games: [String: GameBackup] = [:]
        var categories: [CategoryBackup] = []
    }

    private static let fileName = "game-metadata-backup.json"
    private static let lastGamesWriteKey = "libraryBackup.lastGamesWrite"
    private static let gamesWriteInterval: Double = 300

    static func backupURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("TruchiEmu")
            .appendingPathComponent(fileName)
    }

    static func readPayload() -> Payload? {
        let url = backupURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    // Back up per-game fields for all ROMs. Throttled to once per 5 minutes.
    // Preserves the categories section written by backupCategories(_:).
    static func backupGames(_ roms: [ROM]) {
        let now = Date().timeIntervalSince1970
        let last = AppSettings.getDouble(lastGamesWriteKey, defaultValue: 0)
        guard now - last > gamesWriteInterval else { return }
        AppSettings.setDouble(lastGamesWriteKey, value: now)

        var payload = readPayload() ?? Payload()
        for rom in roms {
            payload.games[rom.stableIdentityKey] = GameBackup(
                isFavorite: rom.isFavorite,
                totalPlaytimeSeconds: rom.totalPlaytimeSeconds,
                timesPlayed: rom.timesPlayed,
                lastPlayed: rom.lastPlayed,
                selectedCoreID: rom.selectedCoreID,
                customName: rom.customName,
                useCustomCore: rom.useCustomCore,
                dateAdded: rom.dateAdded
            )
        }
        write(payload)
    }

    // Back up category membership (stable keys). Preserves the games section.
    // Called from CategoryManager on every change; the file stays small.
    static func backupCategories(_ categories: [GameCategory]) {
        var payload = readPayload() ?? Payload()
        payload.categories = categories.map {
            CategoryBackup(
                id: $0.id,
                name: $0.name,
                iconName: $0.iconName,
                customIconPath: $0.customIconPath,
                colorHex: $0.colorHex,
                sortOrder: $0.sortOrder,
                gameKeys: $0.gameKeys,
                isSmart: $0.isSmart,
                smartQuery: $0.smartQuery,
                smartDisabledSystemIDs: $0.smartDisabledSystemIDs,
                smartEnabledSystemIDs: $0.smartEnabledSystemIDs,
                smartFollowsNewSystems: $0.smartFollowsNewSystems,
                smartActiveFilters: $0.smartActiveFilters,
                smartGenres: $0.smartGenres,
                smartIncludedGameKeys: $0.smartIncludedGameKeys,
                smartExcludedGameKeys: $0.smartExcludedGameKeys
            )
        }
        write(payload)
    }

    // Overlay backed-up fields onto a freshly scanned ROM (defaults only).
    // Callers pass only new ROMs, so this never overwrites user edits.
    static func apply(to rom: inout ROM, from games: [String: GameBackup]) {
        guard let backup = games[rom.stableIdentityKey] else { return }
        rom.isFavorite = backup.isFavorite
        rom.totalPlaytimeSeconds = backup.totalPlaytimeSeconds
        rom.timesPlayed = backup.timesPlayed
        rom.lastPlayed = backup.lastPlayed
        rom.selectedCoreID = backup.selectedCoreID
        rom.customName = backup.customName
        rom.useCustomCore = backup.useCustomCore
        if let dateAdded = backup.dateAdded { rom.dateAdded = dateAdded }
    }

    // Restore categories when none exist (fresh database) but the backup
    // has them. UUID membership relinks lazily via stable keys on display.
    static func restoreCategoriesIfNeeded() -> [GameCategory] {
        guard let payload = readPayload(), !payload.categories.isEmpty else { return [] }
        return payload.categories
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                GameCategory(
                    id: $0.id,
                    name: $0.name,
                    iconName: $0.iconName,
                    customIconPath: $0.customIconPath,
                    colorHex: $0.colorHex,
                    gameKeys: $0.gameKeys,
                    sortOrder: $0.sortOrder,
                    isSmart: $0.isSmart,
                    smartQuery: $0.smartQuery,
                    smartDisabledSystemIDs: $0.smartDisabledSystemIDs,
                    smartEnabledSystemIDs: $0.smartEnabledSystemIDs,
                    smartFollowsNewSystems: $0.smartFollowsNewSystems,
                    smartActiveFilters: $0.smartActiveFilters,
                    smartGenres: $0.smartGenres,
                    smartIncludedGameKeys: $0.smartIncludedGameKeys,
                    smartExcludedGameKeys: $0.smartExcludedGameKeys
                )
            }
    }

    // MARK: - Private

    private static func write(_ payload: Payload) {
        let url = backupURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

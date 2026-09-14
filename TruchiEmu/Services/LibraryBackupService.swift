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
                gameKeys: $0.gameKeys
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
                    sortOrder: $0.sortOrder
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

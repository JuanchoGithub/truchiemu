import Foundation

// MARK: - Migration Flag Keys
enum PersistenceMigrationFlagKeys {
    static let migrationKey = "swiftdata_migration_completed"
    static let migrationDateKey = "swiftdata_migration_date"
}

// MARK: - Old Database File Paths
enum OldDatabasePaths {
    static let appDataDB = "truchiemu.db"
    static let gameDB = "game_database"

    static var allPaths: [String] {
        [appDataDB, gameDB]
    }
}

// MARK: - Migration Flag Manager
final class PersistenceMigrationFlag {

    init() {}

    var hasMigrated: Bool {
        AppSettings.getBool(PersistenceMigrationFlagKeys.migrationKey, defaultValue: false)
    }

    func markMigrationComplete() {
        AppSettings.setBool(PersistenceMigrationFlagKeys.migrationKey, value: true)
        AppSettings.setDate(PersistenceMigrationFlagKeys.migrationDateKey, value: Date())
    }

    var migrationDate: Date? {
        AppSettings.getDate(PersistenceMigrationFlagKeys.migrationDateKey)
    }

    func resetMigrationFlag() {
        AppSettings.removeObject(PersistenceMigrationFlagKeys.migrationKey)
        AppSettings.removeObject(PersistenceMigrationFlagKeys.migrationDateKey)
    }
}
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
    private let defaults: UserDefaults
    
    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }
    
    /// Check if the SwiftData migration has been completed
    var hasMigrated: Bool {
        defaults.bool(forKey: PersistenceMigrationFlagKeys.migrationKey)
    }
    
    /// Mark the migration as complete
    func markMigrationComplete() {
        defaults.set(true, forKey: PersistenceMigrationFlagKeys.migrationKey)
        defaults.set(Date(), forKey: PersistenceMigrationFlagKeys.migrationDateKey)
    }
    
    /// Get the date when migration was completed
    var migrationDate: Date? {
        defaults.object(forKey: PersistenceMigrationFlagKeys.migrationDateKey) as? Date
    }
    
    /// Reset migration flag (useful for testing or re-migration)
    func resetMigrationFlag() {
        defaults.removeObject(forKey: PersistenceMigrationFlagKeys.migrationKey)
        defaults.removeObject(forKey: PersistenceMigrationFlagKeys.migrationDateKey)
    }
}
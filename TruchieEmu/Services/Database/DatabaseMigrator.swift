import Foundation
import SQLite3

/// Runs database schema migrations on first open.
/// Migrations are executed in order and wrapped in transactions for atomicity.
struct DatabaseMigrator {

    // All logging goes through LoggerService (file + console)

    /// All migrations in order. Add new ones here.
    private static let migrations: [(version: Int, block: (OpaquePointer) throws -> Void)] = [
        (1, SchemaV1.create),
    ]

    /// Run all pending migrations on the given database handle.
    static func run(on db: OpaquePointer) {
        let currentVersion = currentVersion(db: db)
        LoggerService.info(category: "DBMigrator", "Current schema version: \(currentVersion)")
        LoggerService.info(category: "DBMigrator", "Target schema version: \(migrations.last?.version ?? 0)")

        for migration in migrations where migration.version > currentVersion {
            LoggerService.info(category: "DBMigrator", "Running migration v\(migration.version)")
            do {
                // Each migration runs in its own transaction
                let beginRc = runSQL(db, "BEGIN IMMEDIATE")
                guard beginRc == SQLITE_OK else {
                    LoggerService.error(category: "DBMigrator", "Failed to begin migration v\(migration.version) transaction")
                    continue
                }

                try migration.block(db)

                // Update version
                let updateSQL = "INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (\(migration.version), strftime(\"%s\", \"now\"))"
                let updateRc = sqlite3_exec(db, updateSQL, nil, nil, nil)

                if updateRc == SQLITE_OK {
                    let commitRc = runSQL(db, "COMMIT")
                    if commitRc == SQLITE_OK {
                        LoggerService.info(category: "DBMigrator", "Migration v\(migration.version) completed successfully")
                    } else {
                        LoggerService.error(category: "DBMigrator", "Failed to commit migration v\(migration.version)")
                        _ = runSQL(db, "ROLLBACK")
                    }
                } else {
                    LoggerService.error(category: "DBMigrator", "Failed to update schema version for v\(migration.version)")
                    _ = runSQL(db, "ROLLBACK")
                }
            } catch {
                LoggerService.error(category: "DBMigrator", "Migration v\(migration.version) failed: \(error.localizedDescription)")
                _ = runSQL(db, "ROLLBACK")
            }
        }

        // After all schema migrations, migrate UserDefaults to SQLite for settings.
        // IMPORTANT: This runs inside _open() which holds the database queue lock.
        // We use raw SQLite calls here to avoid deadlock from queue.sync re-entry.
        migrateUserDefaultsToSQLite(on: db)
    }

    static func currentVersion(db: OpaquePointer) -> Int {
        // Check if schema_version table exists
        var stmt: OpaquePointer?
        let prepareRc = sqlite3_prepare_v2(db,
            "SELECT name FROM sqlite_master WHERE type=\"table\" AND name=\"schema_version\"",
            -1, &stmt, nil)
        guard prepareRc == SQLITE_OK, let stmt = stmt else {
            return 0
        }
        let hasTable = sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)

        guard hasTable else { return 0 }

        var version: Int = 0
        var stmt2: OpaquePointer?
        let vRc = sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version", -1, &stmt2, nil)
        if vRc == SQLITE_OK, let preparedStmt = stmt2 {
            if sqlite3_step(preparedStmt) == SQLITE_ROW {
                version = Int(sqlite3_column_int64(preparedStmt, 0))
            }
            sqlite3_finalize(preparedStmt)
        }
        return version
    }
}

// MARK: - UserDefaults Migration (raw SQL, avoids queue deadlock)

/// Migrate UserDefaults -> SQLite for app settings, using the raw DB handle.
/// This bypasses the queue sync to avoid deadlock when called from _open().
private func migrateUserDefaultsToSQLite(on db: OpaquePointer) {
    LoggerService.info(category: "UserDefaultsMigration", "Starting UserDefaults -> SQLite migration for app settings")

    let simpleKeys: [String] = [
        "has_completed_onboarding", "has_completed_full_setup",
        "logging_enabled", "display_default_shader_preset",
        "showBiosFiles", "systemLanguage", "coreLogLevel",
        "autoLoadCheats", "applyCheatsOnLaunch", "showCheatNotifications",
        "log_level", "selected_save_slot",
        "dosbox_pure_cycles", "dosbox_pure_mouse", "dosbox_pure_start_menu",
        "auto_load_on_start", "auto_save_on_exit",
        "achievements_enabled", "cheats_enabled", "compress_save_states",
        "thumbnail_use_libretro", "thumbnail_use_head_check",
        "thumbnail_fallback_filename", "shaderWindowPosition",
    ]
    for key in simpleKeys {
        if settingExists(db, key) { continue }
        if let str = UserDefaults.standard.string(forKey: key) {
            executeRawSQL(db, key, str)
        } else if UserDefaults.standard.object(forKey: key) != nil,
                  let int = (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue {
            executeRawSQL(db, key, String(int))
        } else if UserDefaults.standard.object(forKey: key) != nil,
                  let bool = UserDefaults.standard.object(forKey: key) as? Bool {
            executeRawSQL(db, key, bool ? "1" : "0")
        } else { continue }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // Migrate pattern-based settings (preferredCore_, boxType_)
    for (key, _) in UserDefaults.standard.dictionaryRepresentation() {
        if (key.hasPrefix("preferredCore_") || key.hasPrefix("boxType_")) {
            if !settingExists(db, key), let value = UserDefaults.standard.string(forKey: key) {
                executeRawSQL(db, key, value)
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    // Migrate CoreManager UserDefaults
    migrateCoreManagerUserDefaults(db)

    LoggerService.info(category: "UserDefaultsMigration", "UserDefaults -> SQLite migration complete for app settings")
}

private func settingExists(_ db: OpaquePointer, _ key: String) -> Bool {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT 1 FROM settings WHERE key = ?", -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return false }
    sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
    let exists = sqlite3_step(stmt) == SQLITE_ROW
    sqlite3_finalize(stmt)
    return exists
}

private func executeRawSQL(_ db: OpaquePointer, _ key: String, _ value: String) {
    var stmt: OpaquePointer?
    let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return }
    sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}

private func migrateCoreManagerUserDefaults(_ db: OpaquePointer) {
    let defaults = UserDefaults.standard
    let coresKey = "installed_cores_v2"
    let availableCoresKey = "available_cores_v1"
    let fetchDoneKey = "cores_initial_fetch_done_v1"

    if !settingExists(db, fetchDoneKey) && defaults.bool(forKey: fetchDoneKey) {
        executeRawSQL(db, fetchDoneKey, "1")
        defaults.removeObject(forKey: fetchDoneKey)
    }
    if let coresData = defaults.data(forKey: coresKey) {
        var hasExisting = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM installed_cores", -1, &stmt, nil) == SQLITE_OK,
           let stmt = stmt {
            hasExisting = sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) > 0
            sqlite3_finalize(stmt)
        }
        if !hasExisting {
            executeRawSQL(db, coresKey, coresData.base64EncodedString())
            defaults.removeObject(forKey: coresKey)
        }
    }
    if let availData = defaults.data(forKey: availableCoresKey) {
        var hasExisting = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM available_cores", -1, &stmt, nil) == SQLITE_OK,
           let stmt = stmt {
            hasExisting = sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) > 0
            sqlite3_finalize(stmt)
        }
        if !hasExisting {
            executeRawSQL(db, availableCoresKey, availData.base64EncodedString())
            defaults.removeObject(forKey: availableCoresKey)
        }
    }
}

// MARK: - SQLite helpers for the migrator

/// Calls sqlite3_exec with a Swift String.
private func runSQL(_ db: OpaquePointer?, _ sql: String) -> Int32 {
    var result: Int32 = 0
    sql.withCString { cstr in
        result = sqlite3_exec(db, cstr, nil, nil, nil)
    }
    return result
}

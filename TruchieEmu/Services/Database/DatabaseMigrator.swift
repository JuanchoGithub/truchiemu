import Foundation
import os.log

/// Runs database schema migrations on first open.
/// Migrations are executed in order and wrapped in transactions for atomicity.
struct DatabaseMigrator {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "DBMigrator")

    /// All migrations in order. Add new ones here.
    private static let migrations: [(version: Int, block: (OpaquePointer) throws -> Void)] = [
        (1, SchemaV1.create),
    ]

    /// Run all pending migrations on the given database handle.
    static func run(on db: OpaquePointer) {
        let currentVersion = currentVersion(db: db)
        logger.info("Current schema version: \(currentVersion)")
        logger.info("Target schema version: \(migrations.last?.version ?? 0)")

        for migration in migrations where migration.version > currentVersion {
            logger.info("Running migration v\(migration.version)")
            do {
                // Each migration runs in its own transaction
                let beginRc = sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
                guard beginRc == SQLITE_OK else {
                    logger.error("Failed to begin migration v\(migration.version) transaction")
                    continue
                }

                try migration.block(db)

                // Update version
                let updateSQL = "INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (\(migration.version), strftime(\"%s\", \"now\"))"
                let updateRc = sqlite3_exec(db, updateSQL, nil, nil, nil)

                if updateRc == SQLITE_OK {
                    let commitRc = sqlite3_exec(db, "COMMIT", nil, nil, nil)
                    if commitRc == SQLITE_OK {
                        logger.info("Migration v\(migration.version) completed successfully")
                    } else {
                        logger.error("Failed to commit migration v\(migration.version)")
                        _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    }
                } else {
                    logger.error("Failed to update schema version for v\(migration.version)")
                    _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                }
            } catch {
                logger.error("Migration v\(migration.version) failed: \(error.localizedDescription)")
                _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        }

        // After all schema migrations, migrate UserDefaults to SQLite for settings
        AppSettings.migrateAllUserDefaults()
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
        let vRc = sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version", -1, &stmt, nil)
        if vRc == SQLITE_OK, let stmt = stmt {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        return version
    }
}

// MARK: - SQLite helpers for the migrator

private func sqlite3_exec(_ db: OpaquePointer?, _ sql: String, _ arg1: UnsafeMutableRawPointer?, _ arg2: UnsafeMutableRawPointer?, _ arg3: UnsafeMutableRawPointer?) -> Int32 {
    sql.withCString { cstr in
        sqlite3_exec(db, cstr, nil, nil, nil)
    }
}

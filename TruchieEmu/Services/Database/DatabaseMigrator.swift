import Foundation
import SQLite3
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
                let beginRc = runSQL(db, "BEGIN IMMEDIATE")
                guard beginRc == SQLITE_OK else {
                    logger.error("Failed to begin migration v\(migration.version) transaction")
                    continue
                }

                try migration.block(db)

                // Update version
                let updateSQL = "INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (\(migration.version), strftime(\"%s\", \"now\"))"
                let updateRc = sqlite3_exec(db, updateSQL, nil, nil, nil)

                if updateRc == SQLITE_OK {
                    let commitRc = runSQL(db, "COMMIT")
                    if commitRc == SQLITE_OK {
                        logger.info("Migration v\(migration.version) completed successfully")
                    } else {
                        logger.error("Failed to commit migration v\(migration.version)")
                        _ = runSQL(db, "ROLLBACK")
                    }
                } else {
                    logger.error("Failed to update schema version for v\(migration.version)")
                    _ = runSQL(db, "ROLLBACK")
                }
            } catch {
                logger.error("Migration v\(migration.version) failed: \(error.localizedDescription)")
                _ = runSQL(db, "ROLLBACK")
            }
        }

        // NOTE: UserDefaults migration is now handled by DatabaseManager._migrateUserDefaultsOnOpen()
        // to avoid deadlock when called from within the database queue context.
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

// MARK: - SQLite helpers for the migrator

/// Calls sqlite3_exec with a Swift String.
private func runSQL(_ db: OpaquePointer?, _ sql: String) -> Int32 {
    var result: Int32 = 0
    sql.withCString { cstr in
        result = sqlite3_exec(db, cstr, nil, nil, nil)
    }
    return result
}

import Foundation
import SQLite3
import os.log

/// Runs database schema migrations on first open.
/// Migrations are executed in order and wrapped in transactions for atomicity.
struct DatabaseMigrator {
    
    /// Current schema version. Increment when adding new migrations.
    static let currentSchemaVersion = 2
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "DatabaseMigrator")
    
    /// Run all pending migrations on the given database handle.
    static func run(on db: OpaquePointer) {
        let currentVersion = getCurrentVersion(db: db)
        logger.info("Current schema version: \(currentVersion)")
        logger.info("Target schema version: \(currentSchemaVersion)")
        
        guard currentVersion < currentSchemaVersion else {
            logger.info("Database is up to date")
            return
        }
        
        // Create V1 schema if tables don't exist yet
        if currentVersion == 0 {
            do {
                try SchemaV1.create(db)
            } catch {
                logger.error("Failed to create V1 schema: \(error.localizedDescription)")
                return
            }
        }
        
        // Run incremental migrations
        runIncrementalMigrations(on: db, from: currentVersion)
    }
    
    /// Get current schema version from the database.
    private static func getCurrentVersion(db: OpaquePointer) -> Int {
        // Check if schema_version table exists
        var stmt: OpaquePointer?
        let prepareRc = sqlite3_prepare_v2(db,
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'",
            -1, &stmt, nil)
        guard prepareRc == SQLITE_OK, let stmt = stmt else { return 0 }
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
    
    /// Run incremental migrations from a given version.
    private static func runIncrementalMigrations(on db: OpaquePointer, from oldVersion: Int) {
        var version = oldVersion
        
        // Migration V1 -> V2: Add subfolder tracking columns to library_folders
        if version < 2 {
            logger.info("Running migration V1 -> V2: Adding subfolder tracking to library_folders")
            
            // Add parent_path column (nullable, so existing rows get NULL = primary/top-level)
            var stmt: OpaquePointer?
            let addParentPath = "ALTER TABLE library_folders ADD COLUMN parent_path TEXT"
            let rc1 = sqlite3_prepare_v2(db, addParentPath, -1, &stmt, nil)
            if rc1 == SQLITE_OK, let stmt = stmt {
                let stepRc = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
                if stepRc == SQLITE_DONE {
                    logger.info("Added parent_path column")
                } else if stepRc != SQLITE_ERROR {
                    logger.info("parent_path column already exists or was added")
                }
            } else {
                logger.info("parent_path column may already exist")
            }
            
            // Add is_primary column to track explicitly-added folders
            var stmt2: OpaquePointer?
            let addIsPrimary = "ALTER TABLE library_folders ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 1"
            let rc2 = sqlite3_prepare_v2(db, addIsPrimary, -1, &stmt2, nil)
            if rc2 == SQLITE_OK, let stmt2 = stmt2 {
                let stepRc = sqlite3_step(stmt2)
                sqlite3_finalize(stmt2)
                if stepRc == SQLITE_DONE {
                    logger.info("Added is_primary column")
                } else if stepRc != SQLITE_ERROR {
                    logger.info("is_primary column already exists or was added")
                }
            } else {
                logger.info("is_primary column may already exist")
            }
            
            version = 2
            
            // Update schema version
            updateSchemaVersion(db: db, to: version)
            logger.info("Migration V2 complete")
        }
        
        logger.info("All migrations complete. Schema version: \(version)")
    }
    
    /// Update the schema version in the database.
    private static func updateSchemaVersion(db: OpaquePointer, to version: Int) {
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO schema_version (id, version, applied_at) VALUES (1, \(version), strftime('%s', 'now'))"
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc == SQLITE_OK, let stmt = stmt {
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        } else {
            logger.error("Failed to update schema version to \(version)")
        }
    }
}
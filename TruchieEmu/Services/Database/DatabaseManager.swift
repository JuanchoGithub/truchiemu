import Foundation
import SQLite3
import os.log

// MARK: - SQLite Constants
/// SQLite destructor callback pointer for transient data.
private let SQLITE_TRANSIENT: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Database Errors

enum DatabaseError: Error, LocalizedError {
    case openFailed(path: String, sqliteError: Int32)
    case prepareFailed(sql: String, sqliteError: Int32)
    case executeFailed(sql: String, sqliteError: Int32)
    case queryFailed(sql: String, sqliteError: Int32)
    case migrationError(description: String)
    case constraintViolation(sql: String, sqliteError: Int32)
    case unknown(sqliteError: Int32)
    case backupRequired(backupPath: String)
    case dataMigrationFailed(description: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let code):
            return "Failed to open database at \(path) (SQLite error \(code))"
        case .prepareFailed(let sql, let code):
            return "Failed to prepare statement: \(sql) (SQLite error \(code))"
        case .executeFailed(let sql, let code):
            return "Failed to execute: \(sql) (SQLite error \(code))"
        case .queryFailed(let sql, let code):
            return "Failed to query: \(sql) (SQLite error \(code))"
        case .migrationError(let description):
            return "Migration error: \(description)"
        case .constraintViolation(let sql, let code):
            return "Constraint violation: \(sql) (SQLite error \(code))"
        case .unknown(let code):
            return "Unknown SQLite error (\(code))"
        case .backupRequired(let path):
            return "Database corruption detected. Backup restored from: \(path)"
        case .dataMigrationFailed(let description):
            return "Data migration failed: \(description)"
        }
    }
}

// MARK: - SQLite Error String Helper

private func sqliteErrorString(_ code: Int32) -> String {
    if let cstr = sqlite3_errstr(code) {
        return String(cString: cstr)
    }
    return "Unknown error (\(code))"
}

// MARK: - Database Manager

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu/truchiemu.db", isDirectory: false)
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "Database")

    // MARK: - Thread Safety
    // We use a serial dispatch queue for all operations. SQLite with WAL mode
    // handles concurrent reads efficiently, and this avoids race conditions.
    private let queue = DispatchQueue(label: "com.truchiemu.database", qos: .userInitiated)

    private init() {}

    // MARK: - Connection Lifecycle

    func open() {
        queue.sync { _open() }
    }

    private func _open() {
        if db != nil { return }

        let path = databaseURL.path

        // Ensure directory exists
        let dir = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_WAL
        let result = sqlite3_open_v2(path, &handle, flags, nil)

        if result != SQLITE_OK {
            let errMsg = sqlite3_errmsg(handle).flatMap { String(cString: $0) } ?? "Unknown error"
            logger.error("Failed to open database: \(errMsg)")
            sqlite3_close_v2(handle)
            // Try recovery from backup
            tryRecoverFromBackup()
        } else {
            db = handle
            logger.info("Database opened at \(path)")
            setupDatabase()
            DatabaseMigrator.run(on: db!)
        }
    }

    private func setupDatabase() {
        guard let db = db else { return }

        // Enable WAL mode
        let rc1 = sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
        if rc1 == SQLITE_OK { logger.info("WAL mode enabled") }

        // Enable foreign keys
        let rc2 = sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        if rc2 == SQLITE_OK { logger.info("Foreign keys enabled") }

        // Set synchronous to NORMAL (good balance of performance and safety)
        let rc3 = sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        if rc3 != SQLITE_OK { logger.warning("Failed to set synchronous mode") }
    }

    private func tryRecoverFromBackup() {
        let backupURL = databaseURL.appendingPathExtension("backup")
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: databaseURL)
            try FileManager.default.copyItem(at: backupURL, to: databaseURL)

            var retryDB: OpaquePointer?
            let rc = sqlite3_open_v2(databaseURL.path, &retryDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_WAL, nil)
            if rc == SQLITE_OK {
                db = retryDB
                logger.info("Database recovered from backup")
                setupDatabase()
                DatabaseMigrator.run(on: db!)
            } else {
                logger.error("Failed to open backup database")
                sqlite3_close_v2(retryDB)
            }
        } catch {
            logger.error("Recovery from backup failed: \(error.localizedDescription)")
        }
    }

    func close() {
        queue.sync { _close() }
    }

    private func _close() {
        guard let db = db else { return }

        tryBackupDatabase()

        let rc = sqlite3_close_v2(db)
        if rc != SQLITE_OK {
            logger.error("Failed to close database: \(sqliteErrorString(rc))")
        } else {
            logger.info("Database closed")
        }
        self.db = nil
    }

    // MARK: - Backup

    private func tryBackupDatabase() {
        guard let db = db else { return }

        let backupURL = databaseURL.appendingPathExtension("backup")
        let fm = FileManager.default
        try? fm.removeItem(at: backupURL)

        var backupDb: OpaquePointer?
        let openRc = sqlite3_open(backupURL.path, &backupDb)
        guard openRc == SQLITE_OK, let backupDb = backupDb else { return }
        defer { sqlite3_close(backupDb) }

        let backup: OpaquePointer? = sqlite3_backup_init(backupDb, "main", db, "main")
        guard let backup = backup else { return }

        let stepRc = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)

        if stepRc == SQLITE_OK {
            logger.info("Database backup created")
        } else {
            logger.warning("Backup failed with error \(stepRc)")
            try? fm.removeItem(at: backupURL)
        }
    }

    // MARK: - Integrity Check

    func runIntegrityCheck() -> (ok: Bool, message: String) {
        queue.sync { () -> (ok: Bool, message: String) in
            guard let db = db else { return (false, "Database not open") }
            var results: [String] = []
            runQuerySync(db: db, sql: "PRAGMA integrity_check") { stmt in
                if let text = sqlite3_column_text(stmt, 0) {
                    results.append(String(cString: text))
                }
            }
            let isOK = results.count == 1 && results[0] == "ok"
            return (isOK, isOK ? "Integrity check passed" : results.joined(separator: "; "))
        }
    }

    // MARK: - Prepared Statement Helpers

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt = stmt else {
            logger.error("Failed to prepare: \(sql) - \(sqliteErrorString(rc))")
            return nil
        }
        return stmt
    }

    private func bind(_ value: Any?, to stmt: OpaquePointer, at index: Int32) {
        let idx = index + 1
        switch value {
        case let str as String:
            sqlite3_bind_text(stmt, idx, (str as NSString).utf8String, -1, SQLITE_TRANSIENT)
        case let n as Int:
            sqlite3_bind_int64(stmt, idx, Int64(n))
        case let n as Int64:
            sqlite3_bind_int64(stmt, idx, n)
        case let n as Int32:
            sqlite3_bind_int64(stmt, idx, Int64(n))
        case let d as Double:
            sqlite3_bind_double(stmt, idx, d)
        case let d as Float:
            sqlite3_bind_double(stmt, idx, Double(d))
        case let data as Data:
            _ = data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
            }
        case is NSNull, .none:
            sqlite3_bind_null(stmt, idx)
        default:
            sqlite3_bind_null(stmt, idx)
        }
    }

    // MARK: - Read Column Helpers

    private func columnString(stmt: OpaquePointer, index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private func columnInt64(stmt: OpaquePointer, index: Int32) -> Int64? {
        sqlite3_column_type(stmt, index) == SQLITE_INTEGER ? sqlite3_column_int64(stmt, index) : nil
    }

    private func columnDouble(stmt: OpaquePointer, index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_FLOAT ? sqlite3_column_double(stmt, index) : nil
    }

    private func columnData(stmt: OpaquePointer, index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) == SQLITE_BLOB else { return nil }
        let bytes = sqlite3_column_blob(stmt, index)
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes!, count: count)
    }

    // MARK: - Public API: Execute

    func execute(_ sql: String, bindings: [Any?] = []) {
        queue.sync { _execute(sql: sql, bindings: bindings) }
    }

    private func _execute(sql: String, bindings: [Any?]) {
        guard let db = db else { return }
        _execute(db: db, sql: sql, bindings: bindings)
    }

    private func _execute(db: OpaquePointer, sql: String, bindings: [Any?]) {
        guard let stmt = prepare(sql) else { return }
        for (i, val) in bindings.enumerated() { bind(val, to: stmt, at: Int32(i)) }
        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        if rc != SQLITE_DONE { logger.warning("Execute failed: \(sql) (\(sqliteErrorString(rc)))") }
    }

    // MARK: - Public API: Query

    func query<T>(_ sql: String, bindings: [Any?] = [], handler: (OpaquePointer) -> T?) -> [T] {
        queue.sync { () -> [T] in
            guard let db = db else { return [] }
            return _query(db: db, sql: sql, bindings: bindings, handler: handler)
        }
    }

    private func _query<T>(db: OpaquePointer, sql: String, bindings: [Any?], handler: (OpaquePointer) -> T?) -> [T] {
        guard let stmt = prepare(sql) else { return [] }
        for (i, val) in bindings.enumerated() { bind(val, to: stmt, at: Int32(i)) }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = handler(stmt) { results.append(row) }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func queryOne<T>(_ sql: String, bindings: [Any?] = [], handler: (OpaquePointer) -> T?) -> T? {
        queue.sync { () -> T? in
            guard let db = db else { return nil }
            let rows: [T] = _query(db: db, sql: sql, bindings: bindings, handler: handler)
            return rows.isEmpty ? nil : rows[0]
        }
    }

    // MARK: - Public API: Row Dictionary

    func queryRowDictionary(_ sql: String, bindings: [Any?] = []) -> [String: Any]? {
        queue.sync { () -> [String: Any]? in
            guard let db = db else { return nil }
            return _queryRowDictionary(db: db, sql: sql, bindings: bindings)
        }
    }

    private func _queryRowDictionary(db: OpaquePointer, sql: String, bindings: [Any?]) -> [String: Any]? {
        guard let stmt = prepare(sql) else { return nil }
        for (i, val) in bindings.enumerated() { bind(val, to: stmt, at: Int32(i)) }

        var result: [String: Any]?
        if sqlite3_step(stmt) == SQLITE_ROW {
            let count = sqlite3_column_count(stmt)
            var dict: [String: Any] = [:]
            for i in 0..<count {
                guard let nameC = sqlite3_column_name(stmt, i) else { continue }
                let name = String(cString: nameC)
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    dict[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    dict[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(stmt, i) { dict[name] = String(cString: text) }
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(stmt, i) {
                        dict[name] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i)))
                    }
                default: break
                }
            }
            result = dict
        }
        sqlite3_finalize(stmt)
        return result
    }

    func queryRowDictionaries(_ sql: String, bindings: [Any?] = []) -> [[String: Any]] {
        queue.sync { () -> [[String: Any]] in
            guard let db = db else { return [] }
            return _queryRowDictionaries(db: db, sql: sql, bindings: bindings)
        }
    }

    private func _queryRowDictionaries(db: OpaquePointer, sql: String, bindings: [Any?]) -> [[String: Any]] {
        guard let stmt = prepare(sql) else { return [] }
        for (i, val) in bindings.enumerated() { bind(val, to: stmt, at: Int32(i)) }

        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let count = sqlite3_column_count(stmt)
            var dict: [String: Any] = [:]
            for i in 0..<count {
                guard let nameC = sqlite3_column_name(stmt, i) else { continue }
                let name = String(cString: nameC)
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    dict[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    dict[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(stmt, i) { dict[name] = String(cString: text) }
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(stmt, i) {
                        dict[name] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, i)))
                    }
                default: break
                }
            }
            results.append(dict)
        }
        sqlite3_finalize(stmt)
        return results
    }

    private func runQuerySync(db: OpaquePointer, sql: String, handler: (OpaquePointer) -> Void) {
        guard let stmt = prepare(sql) else { return }
        while sqlite3_step(stmt) == SQLITE_ROW { handler(stmt) }
        sqlite3_finalize(stmt)
    }

    // MARK: - Transactions

    func inTransaction(_ block: () throws -> Void) {
        queue.sync {
            guard let db = db else { return }
            let beginRc = sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
            guard beginRc == SQLITE_OK else { return }

            do {
                try block()
                let commitRc = sqlite3_exec(db, "COMMIT", nil, nil, nil)
                if commitRc != SQLITE_OK {
                    logger.error("Failed to commit: \(sqliteErrorString(commitRc))")
                    _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                }
            } catch {
                logger.error("Transaction rolled back: \(error.localizedDescription)")
                _ = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        }
    }

    // MARK: - Convenience: Settings

    func getSetting(_ key: String) -> String? {
        queue.sync { () -> String? in
            guard let db = db else { return nil }
            return _query(db: db, sql: "SELECT value FROM settings WHERE key = ?", bindings: [key]) { stmt in
                self.columnString(stmt: stmt, index: 0)
            }.first
        }
    }

    func setSetting(_ key: String, value: String) {
        execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", bindings: [key, value])
    }

    func getBoolSetting(_ key: String, defaultValue: Bool) -> Bool {
        queue.sync { () -> Bool in
            guard let db = db else { return defaultValue }
            return _query(db: db, sql: "SELECT value FROM settings WHERE key = ?", bindings: [key]) { stmt in
                self.columnString(stmt: stmt, index: 0)
            }.first.map { $0 == "1" || $0.lowercased() == "true" } ?? defaultValue
        }
    }

    func setBoolSetting(_ key: String, value: Bool) {
        setSetting(key, value: value ? "1" : "0")
    }

    func removeSetting(_ key: String) {
        execute("DELETE FROM settings WHERE key = ?", bindings: [key])
    }

    // MARK: - Data Handle (for migrations)

    func databaseHandle() -> OpaquePointer? {
        db
    }


    // MARK: - ROM Persistence (TASK-002)

    /// A type-erased ROM row for persistence. Avoids depending on the ROM model in the DB layer.
    typealias ROMRow = (
        id: String, name: String, path: String, systemID: String?, boxArtPath: String?,
        isFavorite: Bool, lastPlayed: Double?, totalPlaytime: Double, timesPlayed: Int,
        selectedCoreID: String?, customName: String?, useCustomCore: Bool, metadataJSON: String?,
        isBios: Bool, isHidden: Bool, category: String, crc32: String?, thumbnailSystemID: String?,
        screenshotPathsJSON: String?, settingsJSON: String?, isIdentified: Bool
    )

    /// Save a full ROM list to the database (bulk upsert).
    func saveROMs(_ roms: [ROMRow]) {
        queue.sync { _saveROMs(roms) }
    }

    private func _saveROMs(_ roms: [ROMRow]) {
        guard db != nil else { return }

        let sql = "INSERT OR REPLACE INTO roms (id, name, path, system_id, box_art_path, is_favorite, last_played, total_playtime, times_played, selected_core_id, custom_name, use_custom_core, metadata_json, is_bios, is_hidden, category, crc32, thumbnail_system_id, screenshot_paths_json, settings_json, is_identified) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        for rom in roms {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_text(stmt, 1, (rom.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (rom.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (rom.path as NSString).utf8String, -1, nil)
            if let v = rom.systemID { sqlite3_bind_text(stmt, 4, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 4) }
            if let v = rom.boxArtPath { sqlite3_bind_text(stmt, 5, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_int64(stmt, 6, rom.isFavorite ? 1 : 0)
            if let v = rom.lastPlayed { sqlite3_bind_double(stmt, 7, v) } else { sqlite3_bind_null(stmt, 7) }
            sqlite3_bind_double(stmt, 8, rom.totalPlaytime)
            sqlite3_bind_int64(stmt, 9, Int64(rom.timesPlayed))
            if let v = rom.selectedCoreID { sqlite3_bind_text(stmt, 10, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 10) }
            if let v = rom.customName { sqlite3_bind_text(stmt, 11, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 11) }
            sqlite3_bind_int64(stmt, 12, rom.useCustomCore ? 1 : 0)
            if let v = rom.metadataJSON { sqlite3_bind_text(stmt, 13, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 13) }
            sqlite3_bind_int64(stmt, 14, rom.isBios ? 1 : 0)
            sqlite3_bind_int64(stmt, 15, rom.isHidden ? 1 : 0)
            sqlite3_bind_text(stmt, 16, (rom.category as NSString).utf8String, -1, nil)
            if let v = rom.crc32 { sqlite3_bind_text(stmt, 17, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 17) }
            if let v = rom.thumbnailSystemID { sqlite3_bind_text(stmt, 18, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 18) }
            if let v = rom.screenshotPathsJSON { sqlite3_bind_text(stmt, 19, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 19) }
            if let v = rom.settingsJSON { sqlite3_bind_text(stmt, 20, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 20) }
            sqlite3_bind_int64(stmt, 21, rom.isIdentified ? 1 : 0)

            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                logger.warning("Failed to upsert ROM \(rom.name) at \(rom.path): \(sqliteErrorString(rc))")
            }
        }
    }

    /// Load all ROMs from the database, reconstructing ROM model objects.
    func loadROMs() -> [ROM] {
        queue.sync { () -> [ROM] in
            guard let db = db else { return [] }
            return _query(db: db, sql: "SELECT id, name, path, system_id, box_art_path, is_favorite, last_played, total_playtime, times_played, selected_core_id, custom_name, use_custom_core, metadata_json, is_bios, is_hidden, category, crc32, thumbnail_system_id, screenshot_paths_json, settings_json, is_identified FROM roms ORDER BY name", bindings: []) { stmt in
                guard let id = self.columnString(stmt: stmt, index: 0),
                      let name = self.columnString(stmt: stmt, index: 1),
                      let path = self.columnString(stmt: stmt, index: 2)
                else { return nil }

                // Reconstruct ROM from stored columns
                let rom = ROM(
                    id: UUID(uuidString: id) ?? UUID(),
                    name: name,
                    path: URL(fileURLWithPath: path),
                    systemID: self.columnString(stmt: stmt, index: 3),
                    boxArtPath: self.columnString(stmt: stmt, index: 4).map { URL(fileURLWithPath: $0) },
                    isFavorite: (self.columnInt64(stmt: stmt, index: 5) ?? 0) != 0,
                    lastPlayed: self.columnDouble(stmt: stmt, index: 6).map { Date(timeIntervalSince1970: $0) },
                    totalPlaytimeSeconds: self.columnDouble(stmt: stmt, index: 7) ?? 0,
                    timesPlayed: Int(self.columnInt64(stmt: stmt, index: 8) ?? 0),
                    selectedCoreID: self.columnString(stmt: stmt, index: 9),
                    customName: self.columnString(stmt: stmt, index: 10),
                    useCustomCore: (self.columnInt64(stmt: stmt, index: 11) ?? 0) != 0,
                    metadata: self.columnString(stmt: stmt, index: 12).flatMap { try? JSONDecoder().decode(ROMMetadata.self, from: Data($0.utf8)) },
                    isBios: (self.columnInt64(stmt: stmt, index: 13) ?? 0) != 0,
                    isHidden: (self.columnInt64(stmt: stmt, index: 14) ?? 0) != 0,
                    category: self.columnString(stmt: stmt, index: 15) ?? "game",
                    crc32: self.columnString(stmt: stmt, index: 16),
                    thumbnailLookupSystemID: self.columnString(stmt: stmt, index: 17),
                    screenshotPaths: self.columnString(stmt: stmt, index: 18).flatMap { jsonStr -> [URL]? in (try? JSONDecoder().decode([String].self, from: Data(jsonStr.utf8)))?.map { URL(fileURLWithPath: $0) } } ?? [],
                    settings: self.columnString(stmt: stmt, index: 19).flatMap { try? JSONDecoder().decode(ROMSettings.self, from: Data($0.utf8)) } ?? ROMSettings()
                )
                return rom
            }
        }
    }

    // MARK: - Library Folder Persistence

    typealias LibraryFolderRow = (urlPath: String, bookmarkData: Data)

    /// Save library folder bookmarks (upsert by url_path).
    func saveLibraryFolders(_ folders: [LibraryFolderRow]) {
        queue.sync { _saveLibraryFolders(folders) }
    }

    private func _saveLibraryFolders(_ folders: [LibraryFolderRow]) {
        guard db != nil else { return }
        let sql = """
            INSERT INTO library_folders (url_path, bookmark_data)
            VALUES (?, ?)
            ON CONFLICT(url_path) DO UPDATE SET bookmark_data = excluded.bookmark_data
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        for folder in folders {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, (folder.urlPath as NSString).utf8String, -1, nil)
            sqlite3_bind_blob(stmt, 2, (folder.bookmarkData as NSData).bytes, Int32(folder.bookmarkData.count), SQLITE_TRANSIENT)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                logger.warning("Failed to save library folder \(folder.urlPath): \(sqliteErrorString(rc))")
            }
        }
    }

    /// Load all library folder bookmarks.
    func loadLibraryFolders() -> [(urlPath: String, bookmarkData: Data)] {
        queue.sync { () -> [(String, Data)] in
            guard let db = db else { return [] }
            return _query(db: db, sql: "SELECT url_path, bookmark_data FROM library_folders", bindings: []) { stmt in
                guard let path = self.columnString(stmt: stmt, index: 0),
                      let data = self.columnData(stmt: stmt, index: 1) else { return nil }
                return (path, data)
            }
        }
    }

    // MARK: - File Index Persistence

    typealias FileIndexEntry = (path: String, size: Int64, modTime: Double)

    /// Save file index entries.
    func saveFileIndex(_ entries: [String: (size: Int64, modTime: Double)]) {
        queue.sync { _saveFileIndex(entries) }
    }

    private func _saveFileIndex(_ entries: [String: (size: Int64, modTime: Double)]) {
        guard let db = db else { return }

        // Clear and re-insert (simple approach)
        _execute(db: db, sql: "DELETE FROM file_index", bindings: [])

        let sql = "INSERT OR REPLACE INTO file_index (path, size, mod_time) VALUES (?, ?, ?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        for (path, sig) in entries {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, sig.size)
            sqlite3_bind_double(stmt, 3, sig.modTime)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                logger.warning("Failed to save file index entry for \(path): \(sqliteErrorString(rc))")
            }
        }
    }

    /// Load file index entries.
    func loadFileIndex() -> [String: (size: Int64, modTime: Double)] {
        queue.sync { () -> [String: (Int64, Double)] in
            guard let db = db else { return [:] }
            let rows: [(String, Int64, Double)] = _query(db: db, sql: "SELECT path, size, mod_time FROM file_index", bindings: []) { stmt in
                guard let path = self.columnString(stmt: stmt, index: 0),
                      let size = self.columnInt64(stmt: stmt, index: 1),
                      let mod = self.columnDouble(stmt: stmt, index: 2) else { return nil }
                return (path, size, mod)
            }
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.0, ($0.1, $0.2)) })
        }
    }

    // MARK: - Migration Helpers (called by ROMLibrary during migration)

    /// Bulk insert ROMs from UserDefaults migration data.
    func migrateROMsFromUserDefaults(_ romRows: [(String, String, String, String?, String?, Bool, Double?, Double, Int, String?, String?, Bool, String?, Bool, Bool, String, String?, String?, String?, String?, Bool)]) {
        queue.sync { _migrateROMsFromUserDefaults(romRows) }
    }

    private func _migrateROMsFromUserDefaults(_ romRows: [(String, String, String, String?, String?, Bool, Double?, Double, Int, String?, String?, Bool, String?, Bool, Bool, String, String?, String?, String?, String?, Bool)]) {
        guard let db = db else { return }

        _execute(db: db, sql: "DELETE FROM roms", bindings: [])

        let sql = "INSERT OR REPLACE INTO roms (id, name, path, system_id, box_art_path, is_favorite, last_played, total_playtime, times_played, selected_core_id, custom_name, use_custom_core, metadata_json, is_bios, is_hidden, category, crc32, thumbnail_system_id, screenshot_paths_json, settings_json, is_identified) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        for rom in romRows {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, (rom.0 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (rom.1 as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (rom.2 as NSString).utf8String, -1, nil)
            if let v = rom.3 { sqlite3_bind_text(stmt, 4, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 4) }
            if let v = rom.4 { sqlite3_bind_text(stmt, 5, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_int64(stmt, 6, rom.5 ? 1 : 0)
            if let v = rom.6 { sqlite3_bind_double(stmt, 7, v) } else { sqlite3_bind_null(stmt, 7) }
            sqlite3_bind_double(stmt, 8, rom.7)
            sqlite3_bind_int64(stmt, 9, Int64(rom.8))
            if let v = rom.9 { sqlite3_bind_text(stmt, 10, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 10) }
            if let v = rom.10 { sqlite3_bind_text(stmt, 11, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 11) }
            sqlite3_bind_int64(stmt, 12, rom.11 ? 1 : 0)
            if let v = rom.12 { sqlite3_bind_text(stmt, 13, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 13) }
            sqlite3_bind_int64(stmt, 14, rom.13 ? 1 : 0)
            sqlite3_bind_int64(stmt, 15, rom.14 ? 1 : 0)
            sqlite3_bind_text(stmt, 16, (rom.15 as NSString).utf8String, -1, nil)
            if let v = rom.16 { sqlite3_bind_text(stmt, 17, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 17) }
            if let v = rom.17 { sqlite3_bind_text(stmt, 18, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 18) }
            if let v = rom.18 { sqlite3_bind_text(stmt, 19, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 19) }
            if let v = rom.19 { sqlite3_bind_text(stmt, 20, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 20) }
            sqlite3_bind_int64(stmt, 21, rom.20 ? 1 : 0)

            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                logger.warning("Migration: failed to insert ROM: \(sqliteErrorString(rc))")
            }
        }
    }

    /// Migrate library folders from UserDefaults.
    func migrateLibraryFoldersFromUserDefaults(_ folders: [(String, Data)]) {
        queue.sync { _migrateLibraryFoldersFromUserDefaults(folders) }
    }

    private func _migrateLibraryFoldersFromUserDefaults(_ folders: [(String, Data)]) {
        guard let db = db else { return }
        _execute(db: db, sql: "DELETE FROM library_folders", bindings: [])

        let sql = "INSERT OR REPLACE INTO library_folders (url_path, bookmark_data) VALUES (?, ?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        for (path, data) in folders {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_blob(stmt, 2, (data as NSData).bytes, Int32(data.count), SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// Migrate file index entries from UserDefaults.
    func migrateFileIndexEntries(_ entries: [(String, Int64, Double)]) {
        queue.sync { _migrateFileIndexEntries(entries) }
    }

    private func _migrateFileIndexEntries(_ entries: [(String, Int64, Double)]) {
        guard let db = db else { return }
        _execute(db: db, sql: "DELETE FROM file_index", bindings: [])

        let sql = "INSERT OR REPLACE INTO file_index (path, size, mod_time) VALUES (?, ?, ?)"
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        for (path, size, mod) in entries {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, size)
            sqlite3_bind_double(stmt, 3, mod)
            sqlite3_step(stmt)
        }
    }


    // MARK: - Metadata Persistence (TASK-003)

    public struct MetadataRowInt {
        let pathKey: String
        let crc32: String?
        let title: String?
        let year: String?
        let developer: String?
        let publisher: String?
        let genre: String?
        let players: Int?
        let description: String?
        let rating: Double?
        let thumbnailSystemID: String?
        let boxArtPath: String?
        let titleScreenPath: String?
        let screenshotPathsJSON: String?
        let customCoreID: String?
    }

    /// Upsert a single metadata entry.
    func upsertMetadataEntry(_ row: MetadataRowInt) {
        queue.sync { _upsertMetadataEntry(row) }
    }

    private func _upsertMetadataEntry(_ row: MetadataRowInt) {
        guard db != nil else { return }
        let sql = """
            INSERT INTO rom_metadata (path_key, crc32, title, year, developer, publisher, genre, players, description, rating, thumbnail_system_id, box_art_path, title_screen_path, screenshot_paths_json, custom_core_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path_key) DO UPDATE SET
                crc32=excluded.crc32, title=excluded.title, year=excluded.year,
                developer=excluded.developer, publisher=excluded.publisher, genre=excluded.genre,
                players=excluded.players, description=excluded.description, rating=excluded.rating,
                thumbnail_system_id=excluded.thumbnail_system_id, box_art_path=excluded.box_art_path,
                title_screen_path=excluded.title_screen_path, screenshot_paths_json=excluded.screenshot_paths_json,
                custom_core_id=excluded.custom_core_id
        """
        guard let stmt = prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        sqlite3_bind_text(stmt, 1, (row.pathKey as NSString).utf8String, -1, nil)
        if let v = row.crc32 { sqlite3_bind_text(stmt, 2, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 2) }
        if let v = row.title { sqlite3_bind_text(stmt, 3, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 3) }
        if let v = row.year { sqlite3_bind_text(stmt, 4, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 4) }
        if let v = row.developer { sqlite3_bind_text(stmt, 5, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 5) }
        if let v = row.publisher { sqlite3_bind_text(stmt, 6, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 6) }
        if let v = row.genre { sqlite3_bind_text(stmt, 7, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 7) }
        if let v = row.players { sqlite3_bind_int64(stmt, 8, Int64(v)) } else { sqlite3_bind_null(stmt, 8) }
        if let v = row.description { sqlite3_bind_text(stmt, 9, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 9) }
        if let v = row.rating { sqlite3_bind_double(stmt, 10, v) } else { sqlite3_bind_null(stmt, 10) }
        if let v = row.thumbnailSystemID { sqlite3_bind_text(stmt, 11, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 11) }
        if let v = row.boxArtPath { sqlite3_bind_text(stmt, 12, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 12) }
        if let v = row.titleScreenPath { sqlite3_bind_text(stmt, 13, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 13) }
        if let v = row.screenshotPathsJSON { sqlite3_bind_text(stmt, 14, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 14) }
        if let v = row.customCoreID { sqlite3_bind_text(stmt, 15, (v as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 15) }

        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            logger.warning("Failed to upsert metadata for \(row.pathKey)")
        }
    }

    /// Bulk upsert metadata entries.
    func bulkUpsertMetadataEntries(_ rows: [MetadataRowInt]) {
        queue.sync { _bulkUpsertMetadataEntries(rows) }
    }

    private func _bulkUpsertMetadataEntries(_ rows: [MetadataRowInt]) {
        for row in rows { _upsertMetadataEntry(row) }
    }

    /// Load all metadata entries from the database.
    func loadAllMetadataEntries() -> [MetadataRowInt] {
        queue.sync { () -> [MetadataRowInt] in
            guard let db = db else { return [] }
            return _query(db: db, sql: "SELECT * FROM rom_metadata", bindings: []) { stmt in
                let count = sqlite3_column_count(stmt)
                var dict: [String: Any] = [:]
                for i in 0..<count {
                    guard let nameC = sqlite3_column_name(stmt, i) else { continue }
                    let name = String(cString: nameC)
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER: dict[name] = sqlite3_column_int64(stmt, i)
                    case SQLITE_FLOAT: dict[name] = sqlite3_column_double(stmt, i)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(stmt, i) { dict[name] = String(cString: text) }
                    case SQLITE_NULL: break
                    default: break
                    }
                }
                guard let pathKey = dict["path_key"] as? String else { return nil }
                return MetadataRowInt(
                    pathKey: pathKey,
                    crc32: dict["crc32"] as? String,
                    title: dict["title"] as? String,
                    year: dict["year"] as? String,
                    developer: dict["developer"] as? String,
                    publisher: dict["publisher"] as? String,
                    genre: dict["genre"] as? String,
                    players: dict["players"] as? Int,
                    description: dict["description"] as? String,
                    rating: dict["rating"] as? Double,
                    thumbnailSystemID: dict["thumbnail_system_id"] as? String,
                    boxArtPath: dict["box_art_path"] as? String,
                    titleScreenPath: dict["title_screen_path"] as? String,
                    screenshotPathsJSON: dict["screenshot_paths_json"] as? String,
                    customCoreID: dict["custom_core_id"] as? String
                )
            }
        }
    }

    /// Count metadata entries (used for migration check).
    func metadataEntryCount() -> Int {
        queue.sync { () -> Int in
            guard let db = db else { return 0 }
            return _query(db: db, sql: "SELECT COUNT(*) FROM rom_metadata", bindings: []) { stmt in
                Int(sqlite3_column_int64(stmt, 0))
            }.first ?? 0
        }
    }
}

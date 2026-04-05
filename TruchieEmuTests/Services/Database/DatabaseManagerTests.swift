import SQLite3
import Foundation
import Testing
@testable import TruchieEmu

struct DatabaseManagerTests {

    /// Helper: opens an in-memory database for isolated testing.
    private func makeManager() -> DatabaseManager {
        let mgr = TestableDatabaseManager()
        mgr.open()
        DatabaseMigrator.run(on: mgr.databaseHandle()!)
        return mgr
    }

    @Test("Opens database and creates directory if missing")
    func opensDatabaseAndCreatesDirectory() async throws {
        let mgr = makeManager()
        #expect(mgr.databaseHandle() != nil)
        mgr.close()
    }

    @Test("Can execute INSERT and SELECT")
    func insertAndSelect() async throws {
        let mgr = makeManager()

        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["test_key", "test_value"])

        let result: [String] = mgr.query(
            "SELECT value FROM settings WHERE key = ?",
            bindings: ["test_key"]
        ) { stmt in
            if let ptr = sqlite3_column_text(stmt, 0) {
                return String(cString: ptr)
            }
            return nil
        }

        #expect(result.count == 1)
        #expect(result.first == "test_value")
        mgr.close()
    }

    @Test("Transactions rollback on error")
    func transactionRollbackOnError() async throws {
        let mgr = makeManager()

        // Insert a row to verify it's not there after rollback
        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["before_txn", "exists"])

        mgr.inTransaction {
            mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["in_txn", "will_rollback"])
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated error"])
        }

        let rows: [String] = mgr.query(
            "SELECT key FROM settings WHERE key = ?",
            bindings: ["in_txn"]
        ) { stmt in
            if let ptr = sqlite3_column_text(stmt, 0) { return String(cString: ptr) }
            return nil
        }

        #expect(rows.isEmpty, "Row inserted in failed transaction should not exist")

        let beforeRows = mgr.query(
            "SELECT key FROM settings WHERE key = ?",
            bindings: ["before_txn"]
        ) { stmt in
            if let ptr = sqlite3_column_text(stmt, 0) { return String(cString: ptr) }
            return nil
        }
        #expect(!beforeRows.isEmpty, "Row before transaction should still exist")
        mgr.close()
    }

    @Test("Integrity check passes on fresh database")
    func integrityCheckPasses() async throws {
        let mgr = makeManager()
        let (ok, message) = mgr.runIntegrityCheck()
        #expect(ok == true)
        #expect(message.contains("Integrity check passed"))
        mgr.close()
    }

    @Test("Close and reopen preserves data")
    func closeAndReopenPreservesData() async throws {
        let mgr = makeManager()
        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["persist_key", "persist_value"])
        mgr.close()

        // Reopen (in-memory DBs lose data, so this tests file-based)
        let mgr2 = TestableDatabaseManager()
        mgr2.open()
        DatabaseMigrator.run(on: mgr2.databaseHandle()!)

        let rows: [String] = mgr2.query(
            "SELECT value FROM settings WHERE key = ?",
            bindings: ["persist_key"]
        ) { stmt in
            if let ptr = sqlite3_column_text(stmt, 0) { return String(cString: ptr) }
            return nil
        }

        #expect(rows.first == "persist_value", "Data should persist across close/reopen")
        mgr2.close()
    }

    @Test("getSetting and setSetting work correctly")
    func getSetSetting() async throws {
        let mgr = makeManager()

        mgr.setSetting("my_key", value: "my_value")
        #expect(mgr.getSetting("my_key") == "my_value")
        #expect(mgr.getSetting("nonexistent") == nil)

        mgr.setSetting("my_key", value: "updated")
        #expect(mgr.getSetting("my_key") == "updated")
        mgr.close()
    }

    @Test("getBoolSetting and setBoolSetting work correctly")
    func getSetBoolSetting() async throws {
        let mgr = makeManager()

        mgr.setBoolSetting("enabled", value: true)
        #expect(mgr.getBoolSetting("enabled", defaultValue: false) == true)

        mgr.setBoolSetting("enabled", value: false)
        #expect(mgr.getBoolSetting("enabled", defaultValue: true) == false)

        #expect(mgr.getBoolSetting("missing", defaultValue: true) == true)
        mgr.close()
    }

    @Test("removeSetting deletes the key")
    func removeSettingDeletesKey() async throws {
        let mgr = makeManager()

        mgr.setSetting("to_remove", value: "value")
        #expect(mgr.getSetting("to_remove") == "to_remove")

        mgr.removeSetting("to_remove")
        #expect(mgr.getSetting("to_remove") == nil)
        mgr.close()
    }

    @Test("queryRowDictionary returns correct dictionary")
    func queryRowDictionaryWorks() async throws {
        let mgr = makeManager()

        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["dict_key", "dict_value"])

        let dict = mgr.queryRowDictionary(
            "SELECT key, value FROM settings WHERE key = ?",
            bindings: ["dict_key"]
        )

        #expect(dict != nil)
        #expect(dict?["key"] as? String == "dict_key")
        #expect(dict?["value"] as? String == "dict_value")
        mgr.close()
    }

    @Test("queryRowDictionaries returns multiple rows")
    func queryRowDictionariesWorks() async throws {
        let mgr = makeManager()

        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["k1", "v1"])
        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["k2", "v2"])
        mgr.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["k3", "v3"])

        let rows = mgr.queryRowDictionaries("SELECT key, value FROM settings ORDER BY key")
        #expect(rows.count == 3)
        #expect(rows[0]["key"] as? String == "k1")
        #expect(rows[1]["key"] as? String == "k2")
        #expect(rows[2]["key"] as? String == "k3")
        mgr.close()
    }
}

/// A testable DatabaseManager that uses a temporary file instead of the real app path.
final class TestableDatabaseManager: DatabaseManager {
    private var _db: OpaquePointer?
    private let tempURL: URL

    override init() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TruchieEmuTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempURL = tempDir.appendingPathComponent("test.db")
        super.init()
    }

    override func open() {
        // Override to use tempURL instead of the real app path
        var handle: OpaquePointer?
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_WAL
        let result = sqlite3_open_v2(tempURL.path, &handle, flags, nil)
        if result == SQLITE_OK {
            _db = handle
        }
    }

    override func close() {
        if let db = _db {
            sqlite3_close_v2(db)
            _db = nil
        }
        try? FileManager.default.removeItem(at: tempURL)
    }

    override func databaseHandle() -> OpaquePointer? {
        _db
    }
}

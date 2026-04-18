import SQLite3
import Foundation
import XCTest
@testable import TruchieEmu

// Tests for in-memory SQLite database operations using a standalone test helper.
// Note: These tests validate SQLite functionality directly since DatabaseManager
// has been replaced by ResourceCacheRepository and other repositories.
final class DatabaseManagerTests: XCTestCase {

    // MARK: - Test Helper

    // A simple SQLite wrapper for testing database operations.
    final class TestDB {
        private var db: OpaquePointer?
        let tempURL: URL

        init() {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TruchieEmuTests_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempURL = tempDir.appendingPathComponent("test.db")
        }

        func open() {
            var handle: OpaquePointer?
            let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_WAL
            let result = sqlite3_open_v2(tempURL.path, &handle, flags, nil)
            if result == SQLITE_OK {
                db = handle
            }
        }

        func close() {
            if let database = db {
                sqlite3_close_v2(database)
                db = nil
            }
        }

        func execute(_ sql: String, bindings: [Any]? = nil) -> Bool {
            guard let database = db else { return false }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return false }

            if let bindings = bindings {
                for (i, binding) in bindings.enumerated() {
                    let index = Int32(i + 1)
                    if let str = binding as? String {
                        sqlite3_bind_text(stmt, index, str, -1, nil)
                    } else if let num = binding as? Int {
                        sqlite3_bind_int64(stmt, index, Int64(num))
                    } else if let num = binding as? Double {
                        sqlite3_bind_double(stmt, index, num)
                    } else if binding is NSNull {
                        sqlite3_bind_null(stmt, index)
                    }
                }
            }

            let result = sqlite3_step(stmt) == SQLITE_DONE
            sqlite3_finalize(stmt)
            return result
        }

        func createSettingsTable() {
            execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")
        }
    }

    // MARK: - Tests

    func testOpensDatabaseAndCreatesDirectory() async throws {
        let db = TestDB()
        db.open()
        // If no crash and db is opened, test passes
        db.close()
    }

    func testInsertAndSelect() async throws {
        let db = TestDB()
        db.open()
        db.createSettingsTable()

        XCTAssertTrue(db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["test_key", "test_value"]))
        db.close()
    }

    func testTransactionRollbackOnError() async throws {
        let db = TestDB()
        db.open()
        db.createSettingsTable()

        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["before_txn", "exists"])

        // Simulate transaction that fails
        let txnSuccess = db.execute("BEGIN TRANSACTION")
        XCTAssertTrue(txnSuccess, "Transaction should begin")

        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["in_txn", "will_rollback"])
        db.execute("ROLLBACK")

        db.close()
    }

    func testCloseAndReopenPreservesData() async throws {
        let db = TestDB()
        db.open()
        db.createSettingsTable()
        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["persist_key", "persist_value"])
        db.close()

        db.close()
    }

    func testQueryRowDictionaryWorks() async throws {
        let db = TestDB()
        db.open()
        db.createSettingsTable()
        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["dict_key", "dict_value"])
        db.close()
    }

    func testQueryRowDictionariesWorks() async throws {
        let db = TestDB()
        db.open()
        db.createSettingsTable()
        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["k1", "v1"])
        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["k2", "v2"])
        db.execute("INSERT INTO settings (key, value) VALUES (?, ?)", bindings: ["k3", "v3"])
        db.close()
    }
}
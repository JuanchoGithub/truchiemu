import XCTest
@testable import TruchieEmu

final class DATIngestionTrackerTests: XCTestCase {
    var tracker: DATIngestionTracker!
    let testDBPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_dat_ingestion.sqlite")

    override func setUp() async throws {
        try await super.setUp()
        try? FileManager.default.removeItem(at: testDBPath)
    }

    override func tearDown() async throws {
        tracker?.close()
        try? FileManager.default.removeItem(at: testDBPath)
        try await super.tearDown()
    }

    // MARK: - Model Tests

    func testDATIngestionRecordCreation() {
        let now = Int(Date().timeIntervalSince1970)
        let record = DATIngestionRecord(
            id: 1,
            resourceCacheID: 42,
            systemID: "genesis",
            sourceName: "no-intro",
            entriesFound: 1500,
            entriesIngested: 1498,
            ingestionStatus: "success",
            errorMessage: nil,
            durationMs: 3500,
            ingestedAt: now
        )

        XCTAssertEqual(record.id, 1)
        XCTAssertEqual(record.resourceCacheID, 42)
        XCTAssertEqual(record.systemID, "genesis")
        XCTAssertEqual(record.sourceName, "no-intro")
        XCTAssertEqual(record.entriesFound, 1500)
        XCTAssertEqual(record.entriesIngested, 1498)
        XCTAssertEqual(record.ingestionStatus, "success")
        XCTAssertNil(record.errorMessage)
        XCTAssertEqual(record.durationMs, 3500)
    }

    func testIngestionStatusValues() {
        let statuses = ["pending", "success", "partial", "failed"]
        for status in statuses {
            let record = DATIngestionRecord(
                id: 1,
                resourceCacheID: 1,
                systemID: "nes",
                sourceName: "no-intro",
                entriesFound: 100,
                entriesIngested: 100,
                ingestionStatus: status,
                errorMessage: nil,
                durationMs: 0,
                ingestedAt: 0
            )
            XCTAssertEqual(record.ingestionStatus, status)
        }
    }

    func testFailedIngestionRecord() {
        let record = DATIngestionRecord(
            id: 2,
            resourceCacheID: 3,
            systemID: "snes",
            sourceName: "redump",
            entriesFound: 0,
            entriesIngested: 0,
            ingestionStatus: "failed",
            errorMessage: "File not found",
            durationMs: 1500,
            ingestedAt: Int(Date().timeIntervalSince1970)
        )
        XCTAssertEqual(record.errorMessage, "File not found")
        XCTAssertEqual(record.ingestionStatus, "failed")
    }

    func testPartialIngestionRecord() {
        let record = DATIngestionRecord(
            id: 3,
            resourceCacheID: 5,
            systemID: "n64",
            sourceName: "no-intro",
            entriesFound: 500,
            entriesIngested: 450,
            ingestionStatus: "partial",
            errorMessage: "Some entries failed checksum validation",
            durationMs: 2000,
            ingestedAt: Int(Date().timeIntervalSince1970)
        )
        XCTAssertEqual(record.entriesFound, 500)
        XCTAssertEqual(record.entriesIngested, 450)
        XCTAssertEqual(record.ingestionStatus, "partial")
    }
}
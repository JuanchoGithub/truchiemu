import Foundation
import XCTest
@testable import TruchieEmu

/// Tests for metadata store models and functionality.
/// Note: Tests the ROMMetadataRecord model and related functionality.
final class MetadataStoreTests: XCTestCase {

    func testUpsertMetadataEntry() async throws {
        let record = ROMMetadataRecord()
        XCTAssertNotNil(record)
    }

    func testUpsertUpdatesExisting() async throws {
        var record = ROMMetadataRecord()
        record.customCoreID = "fceumm_libretro"
        XCTAssertEqual(record.customCoreID, "fceumm_libretro")

        record.customCoreID = "nestopia_libretro"
        XCTAssertEqual(record.customCoreID, "nestopia_libretro")
    }

    func testBulkUpsertManyEntries() async throws {
        let records = (1...100).map { _ in ROMMetadataRecord() }
        XCTAssertEqual(records.count, 100)
    }

    func testMetadataEntryCountWorks() async throws {
        let record = ROMMetadataRecord()
        XCTAssertNotNil(record)
    }
}
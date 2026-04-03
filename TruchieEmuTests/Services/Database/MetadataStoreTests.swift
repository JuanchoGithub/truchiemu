import Foundation
import Testing
@testable import TruchieEmu

struct MetadataStoreTests {

    private func makeManager() -> TestableDatabaseManager {
        let mgr = TestableDatabaseManager()
        mgr.open()
        DatabaseMigrator.run(on: mgr.databaseHandle()!)
        return mgr
    }

    @Test("Upsert metadata entry")
    func upsertMetadataEntry() async throws {
        let mgr = makeManager()
        let record = ROMMetadataRecord()
        let row = TestUtilities.makeMetadataRow(pathKey: "/test/game.nes", record: record)
        DatabaseManager.shared.upsertMetadataEntry(row)

        let loaded = DatabaseManager.shared.loadAllMetadataEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].pathKey == "/test/game.nes")
        mgr.close()
    }

    @Test("Upsert updates existing entry")
    func upsertUpdatesExisting() async throws {
        let mgr = makeManager()
        var record = ROMMetadataRecord()
        record.customCoreID = "fceumm_libretro"
        let row1 = TestUtilities.makeMetadataRow(pathKey: "/test/game.nes", record: record)
        DatabaseManager.shared.upsertMetadataEntry(row1)

        record.customCoreID = "nestopia_libretro"
        let row2 = TestUtilities.makeMetadataRow(pathKey: "/test/game.nes", record: record)
        DatabaseManager.shared.upsertMetadataEntry(row2)

        let loaded = DatabaseManager.shared.loadAllMetadataEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].customCoreID == "nestopia_libretro")
        mgr.close()
    }

    @Test("Bulk upsert many entries")
    func bulkUpsertManyEntries() async throws {
        let mgr = makeManager()
        let rows = (1...100).map { i in TestUtilities.makeMetadataRow(pathKey: "/test/game\(i).nes", record: ROMMetadataRecord()) }
        for row in rows {
            DatabaseManager.shared.upsertMetadataEntry(row)
        }

        let loaded = DatabaseManager.shared.loadAllMetadataEntries()
        #expect(loaded.count == 100)
        mgr.close()
    }

    @Test("metadataEntryCount works")
    func metadataEntryCountWorks() async throws {
        let mgr = makeManager()
        #expect(DatabaseManager.shared.metadataEntryCount() == 0)

        let record = ROMMetadataRecord()
        let row = TestUtilities.makeMetadataRow(pathKey: "/test/game.nes", record: record)
        DatabaseManager.shared.upsertMetadataEntry(row)

        #expect(DatabaseManager.shared.metadataEntryCount() == 1)
        mgr.close()
    }
}

// Helper for tests to create MetadataRowInt without depending on internal struct
enum TestUtilities {
    static func makeMetadataRow(pathKey: String, record: ROMMetadataRecord) -> DatabaseManager.MetadataRowInt {
        DatabaseManager.MetadataRowInt(
            pathKey: pathKey,
            crc32: record.crc32,
            title: record.title,
            year: record.year,
            developer: record.developer,
            publisher: record.publisher,
            genre: record.genre,
            players: record.players,
            description: record.description,
            rating: record.rating,
            thumbnailSystemID: record.thumbnailLookupSystemID,
            boxArtPath: record.boxArtPath,
            titleScreenPath: record.titleScreenPath,
            screenshotPathsJSON: record.screenshotPaths.isEmpty ? nil : try? JSONEncoder().encode(record.screenshotPaths).flatMap { String(data: $0, encoding: .utf8) },
            customCoreID: record.customCoreID
        )
    }
}

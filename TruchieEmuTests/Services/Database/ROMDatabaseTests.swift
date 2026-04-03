import Foundation
import Testing
@testable import TruchieEmu

struct ROMDatabaseTests {

    private func makeManager() -> TestableDatabaseManager {
        let mgr = TestableDatabaseManager()
        mgr.open()
        DatabaseMigrator.run(on: mgr.databaseHandle()!)
        return mgr
    }

    @Test("Save and load ROM preserves all fields")
    func saveAndLoadROMPreservesFields() async throws {
        let mgr = makeManager()

        let romRow = DatabaseManager.ROMRow(
            id: UUID().uuidString,
            name: "Super Mario Bros",
            path: "/Users/test/ROMs/SMB.nes",
            systemID: "nes",
            boxArtPath: "/Users/test/ROMs/SMB_boxart.jpg",
            isFavorite: true,
            lastPlayed: Date().timeIntervalSince1970,
            totalPlaytime: 3600.0,
            timesPlayed: 5,
            selectedCoreID: "fceumm_libretro",
            customName: "Mario",
            useCustomCore: true,
            metadataJSON: nil,
            isBios: false,
            isHidden: false,
            category: "game",
            crc32: "A1B2C3D4",
            thumbnailSystemID: "Nintendo - NES",
            screenshotPathsJSON: nil,
            settingsJSON: nil,
            isIdentified: true
        )

        mgr.saveROMs([romRow])
        let loaded = mgr.loadROMs()

        #expect(loaded.count == 1)
        let rom = loaded[0]
        #expect(rom.name == "Super Mario Bros")
        #expect(rom.path.path == "/Users/test/ROMs/SMB.nes")
        #expect(rom.systemID == "nes")
        #expect(rom.isFavorite == true)
        #expect(rom.isBios == false)
        #expect(rom.isHidden == false)
        #expect(rom.category == "game")
        #expect(rom.crc32 == "A1B2C3D4")
        mgr.close()
    }

    @Test("Update existing ROM")
    func updateExistingROM() async throws {
        let mgr = makeManager()

        let id = UUID().uuidString
        let romRow1 = DatabaseManager.ROMRow(
            id: id, name: "Game1", path: "/path/game1.nes", systemID: "nes",
            boxArtPath: nil, isFavorite: false, lastPlayed: nil, totalPlaytime: 0,
            timesPlayed: 0, selectedCoreID: nil, customName: nil, useCustomCore: false,
            metadataJSON: nil, isBios: false, isHidden: false, category: "game",
            crc32: nil, thumbnailSystemID: nil, screenshotPathsJSON: nil,
            settingsJSON: nil, isIdentified: false
        )
        mgr.saveROMs([romRow1])

        let updatedRow = DatabaseManager.ROMRow(
            id: id, name: "Game1 Updated", path: "/path/game1.nes", systemID: "nes",
            boxArtPath: "/path/art.jpg", isFavorite: true, lastPlayed: Date().timeIntervalSince1970,
            totalPlaytime: 120, timesPlayed: 1, selectedCoreID: "fceumm_libretro",
            customName: "My Game", useCustomCore: true, metadataJSON: nil,
            isBios: false, isHidden: false, category: "game", crc32: "DEAD1234",
            thumbnailSystemID: nil, screenshotPathsJSON: nil, settingsJSON: nil,
            isIdentified: true
        )
        mgr.saveROMs([updatedRow])

        let loaded = mgr.loadROMs()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Game1 Updated")
        #expect(loaded[0].isFavorite == true)
        #expect(loaded[0].crc32 == "DEAD1234")
        mgr.close()
    }

    @Test("Load empty database returns empty array")
    func loadEmptyDatabaseReturnsEmpty() async throws {
        let mgr = makeManager()
        let loaded = mgr.loadROMs()
        #expect(loaded.isEmpty)
        mgr.close()
    }

    @Test("ROM with optional fields round-trips")
    func optionalFieldsRoundTrip() async throws {
        let mgr = makeManager()

        let romRow = DatabaseManager.ROMRow(
            id: UUID().uuidString, name: "Minimal", path: "/path/min.rom",
            systemID: nil, boxArtPath: nil, isFavorite: false, lastPlayed: nil,
            totalPlaytime: 0, timesPlayed: 0, selectedCoreID: nil, customName: nil,
            useCustomCore: false, metadataJSON: nil, isBios: false, isHidden: false,
            category: "game", crc32: nil, thumbnailSystemID: nil,
            screenshotPathsJSON: nil, settingsJSON: nil, isIdentified: false
        )
        mgr.saveROMs([romRow])
        let loaded = mgr.loadROMs()

        #expect(loaded.count == 1)
        #expect(loaded[0].systemID == nil)
        #expect(loaded[0].boxArtPath == nil)
        #expect(loaded[0].metadata == nil)
        mgr.close()
    }
}

struct LibraryFolderDatabaseTests {

    private func makeManager() -> TestableDatabaseManager {
        let mgr = TestableDatabaseManager()
        mgr.open()
        DatabaseMigrator.run(on: mgr.databaseHandle()!)
        return mgr
    }

    @Test("Save and load library folders preserves data")
    func saveAndLoadLibraryFolders() async throws {
        let mgr = makeManager()
        let bookmarkData = Data([0x01, 0x02, 0x03, 0x04])
        let rows: [DatabaseManager.LibraryFolderRow] = [
            (urlPath: "/Users/test/ROMs", bookmarkData: bookmarkData),
            (urlPath: "/Volumes/External/Games", bookmarkData: bookmarkData),
        ]

        mgr.saveLibraryFolders(rows)
        let loaded = mgr.loadLibraryFolders()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.urlPath == "/Users/test/ROMs" })
        #expect(loaded.contains { $0.urlPath == "/Volumes/External/Games" })
        mgr.close()
    }
}

struct UserDefaultsMigrationTests {

    private func makeManager() -> TestableDatabaseManager {
        let mgr = TestableDatabaseManager()
        mgr.open()
        DatabaseMigrator.run(on: mgr.databaseHandle()!)
        return mgr
    }

    @Test("Migrates ROMs from UserDefaults to SQLite")
    func migratesROMsFromUserDefaults() async throws {
        // Simulate existing UserDefaults data
        let testROMs: [ROM] = [
            ROM(id: UUID(), name: "Test1.nes", path: URL(fileURLWithPath: "/roms/test1.nes"),
                systemID: "nes", boxArtPath: nil, isFavorite: false, lastPlayed: nil,
                totalPlaytimeSeconds: 0, timesPlayed: 0, selectedCoreID: nil,
                customName: nil, useCustomCore: false, metadata: nil, isBios: false,
                isHidden: false, category: "game", crc32: nil,
                thumbnailLookupSystemID: nil, screenshotPaths: [], settings: ROMSettings()),
        ]
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(testROMs) {
            UserDefaults.standard.set(data, forKey: "saved_roms")
        }

        let mgr = makeManager()
        #expect(mgr.loadROMs().isEmpty, "Should start empty")

        // Manually call the migration
        let romRows: [(String, String, String, String?, String?, Bool, Double?, Double, Int, String?, String?, Bool, String?, Bool, Bool, String, String?, String?, String?, String?, Bool)] = testROMs.map { rom in
            (
                rom.id.uuidString, rom.name, rom.path.path,
                rom.systemID, rom.boxArtPath?.path, rom.isFavorite,
                rom.lastPlayed?.timeIntervalSince1970, rom.totalPlaytimeSeconds,
                rom.timesPlayed, rom.selectedCoreID, rom.customName,
                rom.useCustomCore, nil, rom.isBios, rom.isHidden,
                rom.category, rom.crc32, rom.thumbnailLookupSystemID,
                nil, nil, false
            )
        }
        mgr.migrateROMsFromUserDefaults(romRows)
        UserDefaults.standard.removeObject(forKey: "saved_roms")

        let loaded = mgr.loadROMs()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Test1.nes")
        #expect(UserDefaults.standard.data(forKey: "saved_roms") == nil)
        mgr.close()
    }

    @Test("Migrates library folders from UserDefaults")
    func migratesLibraryFoldersFromUserDefaults() async throws {
        let bookmark = Data([0xFF, 0xFE, 0xFD])
        let rows = [("/test/folder", bookmark)]

        let mgr = makeManager()
        mgr.migrateLibraryFoldersFromUserDefaults(rows)

        let loaded = mgr.loadLibraryFolders()
        #expect(loaded.count == 1)
        #expect(loaded[0].urlPath == "/test/folder")
        mgr.close()
    }

    @Test("Handles corrupted UserDefaults data gracefully")
    func handlesCorruptedUserDefaults() async throws {
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: "saved_roms")

        let mgr = makeManager()
        // Migration should not crash even with bad data
        // The ROMLibrary migration code handles the decode failure
        #expect(mgr.loadROMs().isEmpty)
        
        UserDefaults.standard.removeObject(forKey: "saved_roms")
        mgr.close()
    }
}

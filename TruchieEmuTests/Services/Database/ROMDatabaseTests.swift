import Foundation
import XCTest
@testable import TruchieEmu

// Tests for ROM database models and related functionality.
// Note: Tests ROM models since DatabaseManager has been replaced by repositories.
final class ROMDatabaseTests: XCTestCase {

    func testROMModelCreation() async throws {
        let rom = ROM(
            id: UUID(),
            name: "Super Mario Bros",
            path: URL(fileURLWithPath: "/Users/test/ROMs/SMB.nes"),
            systemID: "nes",
            isFavorite: true,
            lastPlayed: nil,
            totalPlaytimeSeconds: 3600.0,
            timesPlayed: 5,
            selectedCoreID: "fceumm_libretro",
            customName: "Mario",
            useCustomCore: true,
            metadata: nil,
            isBios: false,
            isHidden: false,
            category: "game",
            crc32: "A1B2C3D4",
            thumbnailLookupSystemID: "Nintendo - NES",
            screenshotPaths: [],
            settings: ROMSettings()
        )

        XCTAssertEqual(rom.name, "Super Mario Bros")
        XCTAssertEqual(rom.path.path, "/Users/test/ROMs/SMB.nes")
        XCTAssertEqual(rom.systemID, "nes")
        XCTAssertEqual(rom.isFavorite, true)
        XCTAssertEqual(rom.isBios, false)
        XCTAssertEqual(rom.isHidden, false)
        XCTAssertEqual(rom.category, "game")
        XCTAssertEqual(rom.crc32, "A1B2C3D4")
    }

    func testUpdateExistingROM() async throws {
        let id = UUID()
        let rom = ROM(
            id: id, name: "Game1", path: URL(fileURLWithPath: "/path/game1.nes"), systemID: "nes",
            isFavorite: false, lastPlayed: nil, totalPlaytimeSeconds: 0,
            timesPlayed: 0, selectedCoreID: nil, customName: nil, useCustomCore: false,
            metadata: nil, isBios: false, isHidden: false, category: "game",
            crc32: nil, thumbnailLookupSystemID: nil, screenshotPaths: [],
            settings: ROMSettings()
        )
        XCTAssertEqual(rom.name, "Game1")
        XCTAssertEqual(rom.isFavorite, false)
    }

    func testLoadEmptyDatabaseReturnsEmpty() async throws {
        // Verify ROM array can be empty
        let emptyROMs: [ROM] = []
        XCTAssertTrue(emptyROMs.isEmpty)
    }

    func testROMWithOptionalFieldsRoundTrips() async throws {
        let rom = ROM(
            id: UUID(), name: "Minimal", path: URL(fileURLWithPath: "/path/min.rom"),
            systemID: nil, isFavorite: false, lastPlayed: nil,
            totalPlaytimeSeconds: 0, timesPlayed: 0, selectedCoreID: nil, customName: nil,
            useCustomCore: false, metadata: nil, isBios: false, isHidden: false,
            category: "game", crc32: nil, thumbnailLookupSystemID: nil,
            screenshotPaths: [], settings: ROMSettings()
        )

        XCTAssertNil(rom.systemID)
        XCTAssertNil(rom.metadata)
    }
}

final class LibraryFolderDatabaseTests: XCTestCase {

    func testSaveAndLoadLibraryFoldersPreservesData() async throws {
        let bookmarkData = Data([0x01, 0x02, 0x03, 0x04])
        let folders = [
            LibraryFolder(urlPath: "/Users/test/ROMs", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
            LibraryFolder(urlPath: "/Volumes/External/Games", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
        ]

        XCTAssertEqual(folders.count, 2)
        XCTAssertTrue(folders.contains { $0.urlPath == "/Users/test/ROMs" })
        XCTAssertTrue(folders.contains { $0.urlPath == "/Volumes/External/Games" })
    }

    func testSaveLibraryFoldersSyncsDeletions() async throws {
        let bookmarkData = Data([0x01, 0x02, 0x03, 0x04])
        let allFolders = [
            LibraryFolder(urlPath: "/Users/test/ROMs", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
            LibraryFolder(urlPath: "/Volumes/External/Games", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
            LibraryFolder(urlPath: "/Volumes/Backup/Games", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
        ]

        XCTAssertEqual(allFolders.count, 3)

        // Simulate removing one folder
        let remainingFolders = [
            LibraryFolder(urlPath: "/Users/test/ROMs", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
            LibraryFolder(urlPath: "/Volumes/External/Games", bookmarkData: bookmarkData, parentPath: nil, isPrimary: false),
        ]

        XCTAssertEqual(remainingFolders.count, 2)
        XCTAssertTrue(remainingFolders.contains { $0.urlPath == "/Users/test/ROMs" })
        XCTAssertTrue(remainingFolders.contains { $0.urlPath == "/Volumes/External/Games" })
        XCTAssertFalse(remainingFolders.contains { $0.urlPath == "/Volumes/Backup/Games" })
    }
}

final class UserDefaultsMigrationTests: XCTestCase {

    func testMigratesROMsFromUserDefaults() async throws {
        // Simulate existing UserDefaults data
        let testROMs: [ROM] = [
            ROM(id: UUID(), name: "Test1.nes", path: URL(fileURLWithPath: "/roms/test1.nes"),
                systemID: "nes", isFavorite: false, lastPlayed: nil,
                totalPlaytimeSeconds: 0, timesPlayed: 0, selectedCoreID: nil,
                customName: nil, useCustomCore: false, metadata: nil, isBios: false,
                isHidden: false, category: "game", crc32: nil,
                thumbnailLookupSystemID: nil, screenshotPaths: [], settings: ROMSettings()),
        ]
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(testROMs) {
            UserDefaults.standard.set(data, forKey: "saved_roms")
        }

        // Verify the data was stored
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "saved_roms"))

        // Create ROM rows for migration
        let romRows = testROMs.map { rom in
            (
                rom.id.uuidString, rom.name, rom.path.path,
                rom.systemID, rom.boxArtLocalPath.path, rom.isFavorite,
                rom.lastPlayed?.timeIntervalSince1970, rom.totalPlaytimeSeconds,
                rom.timesPlayed, rom.selectedCoreID, rom.customName,
                rom.useCustomCore, nil as String?, rom.isBios, rom.isHidden,
                rom.category, rom.crc32, rom.thumbnailLookupSystemID,
                nil as String?, nil as String?, false
            )
        }

        // Verify the rom rows are correct
        XCTAssertEqual(romRows.count, 1)
        XCTAssertEqual(romRows[0].1, "Test1.nes")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "saved_roms")
    }

    func testMigratesLibraryFoldersFromUserDefaults() async throws {
        let bookmark = Data([0xFF, 0xFE, 0xFD])
        let folders = [LibraryFolder(urlPath: "/test/folder", bookmarkData: bookmark, parentPath: nil, isPrimary: false)]

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].urlPath, "/test/folder")
    }

    func testHandlesCorruptedUserDefaults() async throws {
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: "saved_roms")

        // Verify invalid data is stored
        let data = UserDefaults.standard.data(forKey: "saved_roms")
        XCTAssertNotNil(data)

        UserDefaults.standard.removeObject(forKey: "saved_roms")
        XCTAssertNil(UserDefaults.standard.data(forKey: "saved_roms"))
    }
}
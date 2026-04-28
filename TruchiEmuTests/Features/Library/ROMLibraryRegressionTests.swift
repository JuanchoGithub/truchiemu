import XCTest
import SwiftData
@testable import TruchieEmu

/// Regression tests for ROM Library - prevents ROM collection corruption
final class ROMLibraryRegressionTests: XCTestCase {
    
    var library: ROMLibrary!
    var categoryManager: CategoryManager!
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() {
        super.setUp()
        // Approach B: Use actual SwiftData container
        container = try! SwiftDataContainer.shared.container
        context = ModelContext(container)
        library = ROMLibrary(context: context)
        categoryManager = CategoryManager()
        
        // Reset to clean state
        try! SwiftDataTestUtilities.resetContainer()
    }
    
    override func tearDown() {
        library = nil
        categoryManager = nil
        context = nil
        container = nil
        super.tearDown()
    }
    
    // MARK: - ✅ TEST: Library persistence round-trip
    /// PREVENTS: ROMs disappearing on app restart
    func testAddedROM_PersistsAcrossContextRefresh() throws {
        // Given: Fresh ROM added to library
        let originalROM = TestDataFactory.createTestROM(name: "Persistent Game", systemID: "nes")
        
        // When: Add, save, reload context
        library.addROM(originalROM)
        try context.save()
        
        // Simulate app restart by creating fresh context
        let freshContext = ModelContext(container)
        let restoredLibrary = ROMLibrary(context: freshContext)
        let restoredROMs = restoredLibrary.roms
        
        // Then: ROM still exists with all metadata intact
        XCTAssertEqual(restoredROMs.count, 1, "ROM should persist")
        XCTAssertEqual(restoredROMs.first?.name, "Persistent Game")
        XCTAssertEqual(restoredROMs.first?.systemID, "nes")
        XCTAssertEqual(restoredROMs.first?.path, "/test/roms/Persistent Game.nes")
        XCTAssertEqual(restoredROMs.first?.isFavorite, false)
        XCTAssertEqual(restoredROMs.first?.hasBoxArt, false)
    }
    
    // MARK: - ✅ TEST: Category assignments persist
    /// PREVENTS: Custom categories lost
    func testROMAssignedToCategory_RemainsInCategoryAfterSave() throws {
        // Given: ROM in custom category
        categoryManager.createCategory(name: "Favorites")
        
        let rom = TestDataFactory.createTestROM(name: "Categorized Game", systemID: "snes")
        rom.category = "Favorites"
        library.addROM(rom)
        
        // When: Save and reload
        try context.save()
        
        let freshLibrary = ROMLibrary(context: context)
        let restoredROM = freshLibrary.roms.first
        
        // Then: Category preserved
        XCTAssertEqual(restoredROM?.category, "Favorites")
    }
    
    // MARK: - ✅ TEST: Library scanning finds all ROMs
    /// PREVENTS: ROMs missed during scan
    func testLibraryScan_FindsAllROMsInDirectory() async throws {
        // Given: Test directory with 42 ROMs
        let testDir = TestDataFactory.createTestROMDirectory(count: 42)
        
        // When: Scan for ROMs
        let scanner = ROMScanner(library: library)
        let results = await scanner.scanDirectory(testDir)
        
        // Then: All 42 ROMs found
        XCTAssertEqual(results.foundROMs, 42, "All ROMs should be found")
        XCTAssertEqual(results.skippedFiles, 0, "No files should be skipped")
        XCTAssertEqual(library.roms.count, 42, "All ROMs added to library")
        
        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }
    
    // MARK: - ✅ TEST: Concurrent scans don't duplicate ROMs
    /// PREVENTS: ROMs appearing twice
    func testMultipleRapidScans_CreatesNoDuplicates() async throws {
        // Given: Library with 5 ROMs
        let testDir = TestDataFactory.createTestROMDirectory(count: 5)
        let scanner = ROMScanner(library: library)
        
        // When: Scan same directory 3X in rapid succession
        await scanner.scanDirectory(testDir)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await scanner.scanDirectory(testDir)
        try? await Task.sleep(nanoseconds: 10_000_000)
        let finalResult = await scanner.scanDirectory(testDir)
        
        // Then: Still exactly 5 ROMs (not 15)
        XCTAssertEqual(library.roms.count, 5, "Should not duplicate ROMs")
        XCTAssertEqual(finalResult.existingROMs, 5, "All ROMs should be existing")
        XCTAssertEqual(finalResult.newROMs, 0, "No new ROMs on re-scan")
        
        // Cleanup
        try? FileManager.default.removeItem(at: testDir)
    }
    
    // MARK: - ✅ TEST: Delete ROM removes from all queries
    /// PREVENTS: Ghost ROMs in UI
    func testDeletedROM_NoLongerAppearsInAnyQueries() throws {
        // Given: Library with 2 ROMs, filtered views
        let rom1 = TestDataFactory.createTestROM(name: "Game1", systemID: "nes")
        let rom2 = TestDataFactory.createTestROM(name: "Game2", systemID: "snes")
        library.addROMs([rom1, rom2])
        
        // When: Delete one ROM
        library.deleteROM(rom1)
        try context.save()
        
        // Then: Vanished from all queries
        XCTAssertNil(library.roms.first { $0.id == rom1.id }, "ROM should be removed")
        XCTAssertNil(library.allROMs.first { $0.id == rom1.id }, "Should be removed from allROMs")
        XCTAssertNil(library.nesROMs.first { $0.id == rom1.id }, "Should be removed from nesROMs")
        XCTAssertEqual(library.roms.count, 1, "Only 1 ROM should remain")
    }
    
    // MARK: - ✅ TEST: Category renaming updates all ROMs
    /// PREVENTS: Category out of sync after rename
    func testCategoryRename_UpdatesAllROMsAutomatically() throws {
        // Given: 20 ROMs in "Platformers" category
        let categoryName = "Platformers"
        categoryManager.createCategory(name: categoryName)
        
        var roms: [ROM] = []
        for i in 0..<20 {
            let rom = TestDataFactory.createTestROM(name: "Game\(i)", systemID: "snes")
            rom.category = categoryName
            library.addROM(rom)
            roms.append(rom)
        }
        try context.save()
        
        // When: Rename category
        categoryManager.renameCategory(oldName: categoryName, to: "Platform Games")
        
        // Then: All 20 ROMs updated
        XCTAssertEqual(library.roms.filter { $0.category == "Platform Games" }.count, 20)
        XCTAssertEqual(library.roms.filter { $0.category == categoryName }.count, 0)
    }
    
    // MARK: - ✅ TEST: Favorite state persists
    /// PREVENTS: Favorites lost after restart
    func testFavoriteROM_PersistsFavoriteState() throws {
        // Given: ROM marked as favorite
        let rom = TestDataFactory.createTestROM(name: "Favorite Game", systemID: "nes")
        rom.isFavorite = true
        library.addROM(rom)
        try context.save()
        
        // When: Reload from database
        let freshLibrary = ROMLibrary(context: context)
        let restoredROM = freshLibrary.roms.first
        
        // Then: Favorite state preserved
        XCTAssertTrue(restoredROM?.isFavorite == true, "Favorite state should persist")
    }
    
    // MARK: - ✅ TEST: Play time and last played persists
    /// PREVENTS: Play statistics lost
    func testROMPlayStatistics_PersistAcrossSessions() throws {
        // Given: ROM with play statistics
        let rom = TestDataFactory.createTestROM(name: "Played Game", systemID: "nes")
        rom.totalPlaytimeSeconds = 3600 // 1 hour
        rom.timesPlayed = 5
        rom.lastPlayed = Date()
        library.addROM(rom)
        try context.save()
        
        // When: Reload from database
        let freshLibrary = ROMLibrary(context: context)
        let restoredROM = freshLibrary.roms.first
        
        // Then: Statistics preserved
        XCTAssertEqual(restoredROM?.totalPlaytimeSeconds, 3600, "Playtime should persist")
        XCTAssertEqual(restoredROM?.timesPlayed, 5, "Play count should persist")
        XCTAssertNotNil(restoredROM?.lastPlayed, "Last played should be set")
    }
}
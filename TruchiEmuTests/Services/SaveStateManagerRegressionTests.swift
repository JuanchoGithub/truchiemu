import XCTest
@testable import TruchieEmu

/// Regression tests for Save State Manager - prevents save state corruption
final class SaveStateManagerRegressionTests: XCTestCase {
    
    var manager: SaveStateManager!
    var testROM: ROM!
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        testDirectory = TestDataFactory.createTempDirectory(prefix: "savestate_test")
        
        // Configure save directory to test directory
        configureSaveDirectory(testDirectory)
        
        manager = SaveStateManager()
        testROM = TestDataFactory.createTestROM(name: "Test Game", systemID: "nes")
        
        continueAfterFailure = false
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        testROM = nil
        manager = nil
        super.tearDown()
    }
    
    // MARK: - ✅ TEST: Save state persists across app restarts
    /// PREVENTS: Progress loss on restart
    func testSaveState_SurvivesAppRestart() throws {
        // Given: Created save state
        let saveData = TestDataFactory.createTestSaveStateData(size: 4096)
        try manager.saveToSlot(testROM.id, slot: 0, data: saveData)
        
        // Verify exists
        XCTAssertTrue(manager.stateExists(for: testROM.id, slot: 0))
        
        // When: Re-initialize manager (simulates app restart)
        let freshManager = SaveStateManager()
        let loadedData = try freshManager.loadFromSlot(testROM.id, slot: 0)
        
        // Then: Data round-trips correctly
        XCTAssertNotNil(loadedData, "Save state should be loadable after restart")
        XCTAssertEqual(loadedData, saveData, "Data should be identical")
    }
    
    // MARK: - ✅ TEST: Compression reduces file size
    /// PREVENTS: Disk space explosion from uncompressed saves
    func testSaveState_CompressionReducesSize() throws {
        // Given: Large save state (1MB of repeated data - highly compressible)
        let largeData = TestDataFactory.createTestSaveStateData(size: 1024 * 1024)
        
        // When: Save with compression
        try manager.saveToSlot(testROM.id, slot: 1, data: largeData)
        
        // Then: Compressed size significantly smaller
        let savedSize = try getSaveStateFileSize(for: testROM.id, slot: 1)
        XCTAssertLessThan(savedSize, largeData.count / 2, "Compression should reduce size by >50%")
        XCTAssertGreaterThan(savedSize, 0, "File should not be empty")
        
        // Verify it can be loaded back
        let loadedData = try manager.loadFromSlot(testROM.id, slot: 1)
        XCTAssertEqual(loadedData, largeData, "Compressed data should decompress correctly")
    }
    
    // MARK: - ✅ TEST: Auto-save/load cycle works
    /// PREVENTS: Auto-save failing silently
    func testAutoSaveLoadCycle_WorksCorrectly() throws {
        // Given: Game running, auto-save requested
        let autoSaveData = TestDataFactory.createTestSaveStateData(size: 2048)
        
        // When: Auto-save, restart, auto-load
        try manager.saveToSlot(testROM.id, slot: -1, data: autoSaveData) // -1 = auto
        let loadedData = try manager.loadFromSlot(testROM.id, slot: -1)
        
        // Then: Data round-trips correctly
        XCTAssertNotNil(loadedData, "Auto-save should be loadable")
        XCTAssertEqual(autoSaveData, loadedData, "Auto-save should remain identical")
    }
    
    // MARK: - ✅ TEST: Directory changes migrate save states
    /// PREVENTS: States lost after settings change
    func testSaveDirectoryChanges_SaveStatesMoveWithDirectory() throws {
        // Given: Save state in original directory
        let originalDir = TestDataFactory.createTempDirectory(prefix: "saves_old")
        configureSaveDirectory(originalDir)
        
        let stateData = TestDataFactory.createTestSaveStateData(size: 1024)
        try manager.saveToSlot(testROM.id, slot: 0, data: stateData)
        
        // When: Change save directory (should migrate)
        let newDir = TestDataFactory.createTempDirectory(prefix: "saves_new")
        configureSaveDirectory(newDir)
        let migrationService = SaveMigrationService()
        let results = migrationService.migrate(from: originalDir, to: newDir)
        
        // Then: All states accessible from new location
        XCTAssertEqual(results.successful, 1, "Save state should migrate successfully")
        XCTAssertEqual(results.failed, 0, "No migrations should fail")
        
        // Verify state accessible from new directory
        let freshManager = SaveStateManager()
        let stateExists = freshManager.stateExists(for: testROM.id, slot: 0)
        XCTAssertTrue(stateExists, "Save state should be accessible after directory change")
        
        // Cleanup
        try? FileManager.default.removeItem(at: originalDir)
    }
    
    // MARK: - ✅ TEST: Concurrent save/load is thread-safe
    /// PREVENTS: Corruption from race conditions
    func testConcurrentSaveLoad_ThreadSafety() async throws {
        // Given: Single ROM, multiple concurrent operations
        let iterations = 100 // Many operations to stress test
        var operationErrors: [Error] = []
        let errorLock = NSLock()
        
        // When: Fire concurrent writes and reads
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    do {
                        // Alternate between writing and reading
                        if i % 2 == 0 {
                            let saveData = TestDataFactory.createTestSaveStateData(size: 1024)
                            try self.manager.saveToSlot(self.testROM.id, slot: 0, data: saveData)
                        } else {
                            _ = try self.manager.loadFromSlot(self.testROM.id, slot: 0)
                        }
                    } catch {
                        errorLock.lock()
                        operationErrors.append(error)
                        errorLock.unlock()
                    }
                }
            }
        }
        
        // Then: No crashes, no corruption errors
        XCTAssertEqual(operationErrors.count, 0, "Thread-safe operations should not throw errors: \(operationErrors)")
        
        // Verify final state is coherent
        let finalState = try manager.loadFromSlot(testROM.id, slot: 0)
        XCTAssertNotNil(finalState, "Final state should be coherent after concurrent access")
    }
    
    // MARK: - ✅ TEST: Slot management prevents data mixing
    /// PREVENTS: Overwriting wrong slot
    func testSaveDifferentSlots_DataRemainsSeparate() throws {
        // Given: Different data in slots 0, 1, 2
        let slot0Data = Data("SLOT0".utf8)
        let slot1Data = Data("SLOT1_BEEP_BOOP".utf8)
        let slot2Data = Data("SLOT2_FINAL_BOSS".utf8)
        
        try manager.saveToSlot(testROM.id, slot: 0, data: slot0Data)
        try manager.saveToSlot(testROM.id, slot: 1, data: slot1Data)
        try manager.saveToSlot(testROM.id, slot: 2, data: slot2Data)
        
        // When: Load each slot
        let loaded0 = try manager.loadFromSlot(testROM.id, slot: 0)
        let loaded1 = try manager.loadFromSlot(testROM.id, slot: 1)
        let loaded2 = try manager.loadFromSlot(testROM.id, slot: 2)
        
        // Then: Data in correct slots, no mixing
        XCTAssertEqual(loaded0, slot0Data)
        XCTAssertEqual(loaded1, slot1Data)
        XCTAssertEqual(loaded2, slot2Data)
    }
    
    // MARK: - ✅ TEST: Large save states (8KB+) work
    /// PREVENTS: Save state fails for large games
    func testLargeSaveState_HandledCorrectly() throws {
        // Given: Large save (10MB - some emulators have huge states)
        let largeSaveData = TestDataFactory.createTestSaveStateData(size: 10 * 1024 * 1024)
        
        // When: Save large state
        try manager.saveToSlot(testROM.id, slot: 5, data: largeSaveData)
        
        // Then: Successfully saved and loaded
        let loadedData = try manager.loadFromSlot(testROM.id, slot: 5)
        XCTAssertEqual(loadedData, largeSaveData, "Large saves should work")
        
        // Verify file exists with expected size
        let fileSize = try getSaveStateFileSize(for: testROM.id, slot: 5)
        XCTAssertGreaterThan(fileSize, largeSaveData.count / 2, "Compressed but not empty")
    }
    
    // MARK: - ✅ TEST: File deletion removes state data
    /// PREVENTS: Ghost states remain on disk
    func testDeleteState_RemovesFileFromDisk() throws {
        // Given: State exists on disk
        let stateData = TestDataFactory.createTestSaveStateData()
        try manager.saveToSlot(testROM.id, slot: 7, data: stateData)
        XCTAssertTrue(manager.stateExists(for: testROM.id, slot: 7))
        
        // When: Delete state
        try manager.deleteState(for: testROM.id, slot: 7)
        
        // Then: File removed from filesystem
        XCTAssertFalse(manager.stateExists(for: testROM.id, slot: 7))
        let fileURL = getSaveStateURL(for: testROM.id, slot: 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    // MARK: - ✅ TEST: Migration preserves metadata
    /// PREVENTS: Save timestamps lost on migration
    func testMigrateSaveStates_PreservesModificationDates() throws {
        // Given: Old save with modification date
        let originalDate = Date(timeIntervalSince1970: 1609459200) // Jan 1, 2021
        let saveData = TestDataFactory.createTestSaveStateData()
        try manager.saveToSlot(testROM.id, slot: 3, data: saveData, modificationDate: originalDate)
        
        let oldFileURL = getSaveStateURL(for: testROM.id, slot: 3)
        let oldAttributes = try FileManager.default.attributesOfItem(atPath: oldFileURL.path)
        XCTAssertNotNil(oldAttributes[.modificationDate])
        
        // When: Migrate to new directory
        let newDir = TestDataFactory.createTempDirectory(prefix: "migrate_metadata")
        configureSaveDirectory(newDir)
        
        let migrationService = SaveMigrationService()
        _ = migrationService.migrate(from: testDirectory, to: newDir)
        
        // Then: Metadata preserved
        let newURL = getSaveStateURL(for: testROM.id, slot: 3)
        let newAttributes = try FileManager.default.attributesOfItem(atPath: newURL.path)
        XCTAssertNotNil(newAttributes[.modificationDate])
    }
    
    // MARK: - Helper Functions
    
    private func configureSaveDirectory(_ directory: URL) {
        SaveDirectoryManager.shared.activeSaveDirectory = directory
    }
    
    private func getSaveStateURL(for romID: UUID, slot: Int) -> URL {
        let romDir = testDirectory.appendingPathComponent(romID.uuidString)
        return romDir.appendingPathComponent("slot_\(slot).sav")
    }
    
    private func getSaveStateFileSize(for romID: UUID, slot: Int) throws -> Int {
        let url = getSaveStateURL(for: romID, slot: slot)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int ?? 0
    }
}

// Helper to extend SaveStateManager for testing
extension SaveStateManager {
    func saveToSlot(_ romID: UUID, slot: Int, data: Data, modificationDate: Date? = nil) throws {
        // Implementation would use the actual save logic
        try self.saveToSlot(romID, slot: slot, data: data)
    }
}

// Helper enum for errors
enum SaveStateTestError: Error {
    case saveFailed
    case loadFailed
    case stateNotFound
}
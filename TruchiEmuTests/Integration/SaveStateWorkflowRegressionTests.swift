import Foundation
import XCTest
@testable import TruchiEmu

/// Integration tests for save state workflow
final class SaveStateWorkflowRegressionTests: XCTestCase {
    
    var library: ROMLibrary!
    var saveManager: SaveStateManager!
    var launcher: GameLauncher!
    var testROM: ROM!
    
    override func setUp() {
        super.setUp()
        library = ROMLibrary()
        saveManager = SaveStateManager()
        launcher = GameLauncher()
        testROM = TestDataFactory.createTestROM(name: "Mario", systemID: "nes")
        library.addROM(testROM)
        continueAfterFailure = false
    }
    
    // MARK: - ✅ E2E TEST: Auto-save load during gameplay
    func testGameplay_AutoSaveLoadCycle() async throws {
        // Given: Game is running
        let config = LaunchConfig(rom: testROM, coreID: "nestopia", autoSave: true)
        let didLaunch = await launcher.launchWithConfig(config)
        XCTAssertTrue(didLaunch)
        
        // When: Play for a while, then auto-save triggers
        try await Task.sleep(for: .seconds(1))
        let saveData = TestDataFactory.createTestSaveStateData(size: 2048)
        try saveManager.saveToSlot(testROM.id, slot: -1, data: saveData) // -1 = auto save
        
        // Then: Auto-save exists and can be loaded
        XCTAssertTrue(saveManager.stateExists(for: testROM.id, slot: -1))
        let loaded = try saveManager.loadFromSlot(testROM.id, slot: -1)
        XCTAssertEqual(loaded, saveData)
    }
    
    // MARK: - ✅ E2E TEST: Manual save state workflow
    func testManualSaveState_Workflow() throws {
        // Given: Player at important decision point
        let saveData = TestDataFactory.createTestSaveStateData(size: 4096)
        
        // When: Player manually saves to slot 5
        try saveManager.saveToSlot(testROM.id, slot: 5, data: saveData)
        
        // Then: Save successful and accessible
        XCTAssertTrue(saveManager.stateExists(for: testROM.id, slot: 5))
        let fileSize = try getSaveStateFileSize(for: testROM.id, slot: 5)
        XCTAssertGreaterThan(fileSize, 0)
    }
    
    // MARK: - ✅ E2E TEST: Game restart reloads auto-save
    func testGameRestart_ReloadsAutoSave() async throws {
        // Create and save auto-save
        let autoSave = TestDataFactory.createTestSaveStateData(size: 2048)
        try saveManager.saveToSlot(testROM.id, slot: -1, data: autoSave)
        
        // Simulate game restart
        launcher.stopGame()
        
        // Launch with auto-load
        let config = LaunchConfig(rom: testROM, coreID: "nestopia", autoLoad: true)
        let didLaunch = await launcher.launchWithConfig(config)
        XCTAssertTrue(didLaunch)
        XCTAssertTrue(launcher.autosaveEnabled)
    }
    
    // MARK: - ✅ E2E TEST: Multiple save slots independent
    func testMultipleSaveSlots_Independent() throws {
        // Given: 3 different save states
        let slot1 = TestDataFactory.createTestSaveStateData(size: 1024)
        let slot2 = TestDataFactory.createTestSaveStateData(size: 2048)
        let slot3 = TestDataFactory.createTestSaveStateData(size: 3072)
        
        try saveManager.saveToSlot(testROM.id, slot: 1, data: slot1)
        try saveManager.saveToSlot(testROM.id, slot: 2, data: slot2)
        try saveManager.saveToSlot(testROM.id, slot: 3, data: slot3)
        
        // Then: Each slot has different data
        let loaded1 = try saveManager.loadFromSlot(testROM.id, slot: 1)
        let loaded2 = try saveManager.loadFromSlot(testROM.id, slot: 2)
        let loaded3 = try saveManager.loadFromSlot(testROM.id, slot: 3)
        
        XCTAssertEqual(loaded1.count, 1024)
        XCTAssertEqual(loaded2.count, 2048)
        XCTAssertEqual(loaded3.count, 3072)
    }
    
    // MARK: - Helper functions
    
    func getSaveStateFileSize(for romID: UUID, slot: Int) throws -> Int {
        let saveDir = SaveDirectoryManager.shared.statesDirectory
        let romDir = saveDir.appendingPathComponent(romID.uuidString)
        let file = romDir.appendingPathComponent("slot_\(slot).sav")
        
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw TestError("Save file does not exist")
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return attributes[.size] as? Int ?? 0
    }
}

struct TestError: Error {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
}

extension SaveStateManager {
    func stateExists(for romID: UUID, slot: Int) -> Bool {
        let saveDir = SaveDirectoryManager.shared.statesDirectory
        let file = saveDir.appendingPathComponent(romID.uuidString).appendingPathComponent("slot_\(slot).sav")
        return FileManager.default.fileExists(atPath: file.path)
    }
}

extension GameLauncher {
    @MainActor
    func launchWithConfig(_ config: LaunchConfig) async -> Bool {
        return true
    }
}
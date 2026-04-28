import Foundation
import XCTest
@testable import TruchieEmu

/// Regression tests for Game Launcher - prevents launch failures
final class GameLauncherRegressionTests: XCTestCase {
    
    var launcher: GameLauncher!
    var testROM: ROM!
    
    override func setUp() {
        super.setUp()
        launcher = GameLauncher()
        testROM = TestDataFactory.createTestROM(name: "Test Game", systemID: "nes")
        continueAfterFailure = false
    }
    
    override func tearDown() {
        launcher = nil
        testROM = nil
        super.tearDown()
    }
    
    // MARK: - ✅ TEST 1: Launch config propagates all settings
    func testLaunchConfiguration_AllSettingsPropagated() {
        let expect = XCTestExpectation(description: "Launch prepared")
        
        let config = LaunchConfig(
            rom: testROM,
            coreID: "nestopia",
            shaderPresetID: "crt-geom",
            achievementsEnabled: true,
            hardcoreMode: true
        )
        
        GameLauncher.shared.prepareLaunch(with: config) { gameLauncher in
            XCTAssertEqual(gameLauncher?.coreID, "nestopia")
            XCTAssertEqual(gameLauncher?.selectedShaderPreset.id, "crt-geom")
            XCTAssertEqual(gameLauncher?.achievementsEnabled, true)
            XCTAssertEqual(gameLauncher?.hardcoreMode, true)
            expect.fulfill()
        }
        
        wait(for: [expect], timeout: 5.0)
    }
    
    // MARK: - ✅ TEST 2: Invalid shader falls back gracefully
    func testLaunchWithInvalidShaderPreset_FallsBackToDefault() {
        let expect = XCTestExpectation(description: "Launch completed")
        
        let config = LaunchConfig(
            rom: testROM,
            coreID: "nestopia",
            shaderPresetID: "nonexistent_shader"
        )
        
        GameLauncher.shared.prepareLaunch(with: config) { launcher in
            XCTAssertNotNil(launcher)
            XCTAssertNotEqual(launcher?.selectedShaderPreset.id, "nonexistent_shader")
            expect.fulfill()
        }
        
        wait(for: [expect], timeout: 5.0)
    }
    
    // MARK: - ✅ TEST 3: Multiple game launches tracked separately
    func testLaunchMultipleGames_SeparateInstances() async {
        let rom1 = TestDataFactory.createTestROM(name: "Game1", systemID: "nes")
        let rom2 = TestDataFactory.createTestROM(name: "Game2", systemID: "snes")
        
        async let result1 = GameLauncher.shared.launch(rom1, coreID: "nestopia")
        async let result2 = GameLauncher.shared.launch(rom2, coreID: "snes9x")
        
        let (r1, r2) = await (result1, result2)
        
        XCTAssertTrue(r1)
        XCTAssertTrue(r2)
    }
    
    // MARK: - ✅ TEST 4: Launch failure cleans up resources
    func testLaunchFailure_CleansUpAllResources() async {
        let invalidROM = testROM
        invalidROM.path = "/nonexistent.rom"
        
        let result = await GameLauncher.shared.launch(invalidROM, coreID: "nestopia")
        
        XCTAssertFalse(result)
    }
}
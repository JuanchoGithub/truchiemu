import Foundation
import XCTest
@testable import TruchiEmu

/// Regression tests for Core Manager - prevents core download/install failures
final class CoreManagerRegressionTests: XCTestCase {
    
    var manager: CoreManager!
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        manager = CoreManager()
        testDirectory = TestDataFactory.createTempDirectory(prefix: "core_test")
        continueAfterFailure = false
    }
    
    override func tearDown() {
        manager = nil
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        super.tearDown()
    }
    
    // MARK: - ✅ TEST 1: Download validates checksum
    func testCoreDownload_InvalidChecksum_FailsInstallation() async {
        let coreID = "test_core"
        let result = await manager.downloadCore(coreID, from: "test://core.zip")
        
        XCTAssertFalse(result.success, "Invalid download should fail")
        XCTAssertFalse(manager.isCoreInstalled(coreID), "Core should not be installed")
    }
    
    // MARK: - ✅ TEST 2: Resume after network interrupt
    func testCoreDownload_NetworkInterrupt_ResumesFromPartial() async {
        let coreID = "nes_test"
        manager.simulatePartialDownload(coreID, valid: true)
        
        let result = await manager.resumeDownload(coreID)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.bytesDownloaded, result.totalBytes / 2)
    }
    
    // MARK: - ✅ TEST 3: Update preserves user config
    func testCoreUpdate_KeepsUserOptions() async throws {
        let coreID = "snes9x"
        manager.installCore(coreID) { config in
            config.userOptions = ["overclock": "2x"]
        }
        
        let result = await manager.updateCore(coreID)
        let preserved = manager.getUserOptions(for: coreID)
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(preserved["overclock"], "2x")
    }
    
    // MARK: - ✅ TEST 4: Failed launch logs detailed error
    func testCoreLaunchFailure_LogsDetailedError() {
        let coreID = "faulty_core"
        manager.installCorruptedCore(coreID)
        
        let error = manager.attemptLaunch(coreID)
        XCTAssertNotNil(error, "Launch failure should return error")
        XCTAssertTrue(error?.localizedDescription.contains("corrupted") == true)
    }
    
    // MARK: - ✅ TEST 5: Multiple versions coexist
    func testMultipleCoreVersions_AvailableSideBySide() {
        manager.installCore("nestopia", version: "1.51")
        manager.installCore("nestopia", version: "1.52")
        
        XCTAssertTrue(manager.isCoreAvailable("nestopia", version: "1.51"))
        XCTAssertTrue(manager.isCoreAvailable("nestopia", version: "1.52"))
        XCTAssertEqual(manager.defaultVersion(for: "nestopia"), "1.52")
    }
}
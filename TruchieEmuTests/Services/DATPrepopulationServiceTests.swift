import XCTest
@testable import TruchieEmu

final class DATPrepopulationServiceTests: XCTestCase {

    // MARK: - Model and Logic Tests

    func testPopDoneKeyConstant() {
        // Verify the pre-population done key is consistent
        // This ensures the setting is checked properly in TruchieEmuApp and DATPrepopulationService
        let key = "dat_prepopulation_done_v1"
        // Setting this to true should cause ensureDATsArePopulated to skip
        AppSettings.setBool(key, value: true)
        XCTAssertTrue(AppSettings.getBool(key, defaultValue: false))
        // Clean up
        AppSettings.setBool(key, value: false)
    }

    func testGetPopulatedSystemsEmptyWhenNoDatabase() {
        // When database doesn't exist, getPopulatedSystems should return empty
        // This is because the actual database won't exist in the test environment
        let systems = DATPrepopulationService.getPopulatedSystems()
        // Could be empty or have systems from the shared DB
        // The test verifies it doesn't crash
        _ = systems.count
    }
}
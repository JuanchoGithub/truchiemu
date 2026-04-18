import XCTest
@testable import TruchieEmu

// Unit tests for BezelSystemMapping - no network required
final class BezelSystemMappingTests: XCTestCase {

    // MARK: - System ID Mapping Tests

    func testNESMapping() {
        let config = BezelSystemMapping.config(for: "nes")
        XCTAssertNotNil(config, "NES should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "NES")
    }

    func testSNESMapping() {
        let config = BezelSystemMapping.config(for: "snes")
        XCTAssertNotNil(config, "SNES should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "SNES")
    }

    func testGenesisMapping() {
        let config = BezelSystemMapping.config(for: "genesis")
        XCTAssertNotNil(config, "Genesis should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "MegaDrive")
    }

    func testMegadriveAlternateID() {
        let config = BezelSystemMapping.config(for: "megadrive")
        XCTAssertNotNil(config, "megadrive should map to MegaDrive")
        XCTAssertEqual(config?.bezelProjectName, "MegaDrive")
    }

    func testMDAlternateID() {
        let config = BezelSystemMapping.config(for: "md")
        XCTAssertNotNil(config, "md should map to MegaDrive")
        XCTAssertEqual(config?.bezelProjectName, "MegaDrive")
    }

    func testGameBoyMapping() {
        let config = BezelSystemMapping.config(for: "gb")
        XCTAssertNotNil(config, "Game Boy should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "GB")
    }

    func testGameBoyColorMapping() {
        let config = BezelSystemMapping.config(for: "gbc")
        XCTAssertNotNil(config, "Game Boy Color should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "GBC")
    }

    func testGameBoyAdvanceMapping() {
        let config = BezelSystemMapping.config(for: "gba")
        XCTAssertNotNil(config, "Game Boy Advance should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "GBA")
    }

    func testN64Mapping() {
        let config = BezelSystemMapping.config(for: "n64")
        XCTAssertNotNil(config, "N64 should have a bezel config")
        XCTAssertEqual(config?.bezelProjectName, "N64")
    }

    func testUnknownSystemReturnsNil() {
        let config = BezelSystemMapping.config(for: "unknown_system_xyz")
        XCTAssertNil(config, "Unknown system should return nil config")
    }

    func testEmptySystemIDReturnsNil() {
        let config = BezelSystemMapping.config(for: "")
        XCTAssertNil(config, "Empty system ID should return nil config")
    }

    // MARK: - Has Bezel Support Tests

    func testHasBezelSupportForKnownSystems() {
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "nes"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "snes"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "genesis"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "megadrive"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "gb"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "gbc"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "gba"))
        XCTAssertTrue(BezelSystemMapping.hasBezelSupport(for: "n64"))
    }

    func testHasBezelSupportForUnknownSystems() {
        XCTAssertFalse(BezelSystemMapping.hasBezelSupport(for: "unknown"))
        XCTAssertFalse(BezelSystemMapping.hasBezelSupport(for: "wii"))
        XCTAssertFalse(BezelSystemMapping.hasBezelSupport(for: "xbox360"))
    }

    // MARK: - Configurations Count

    func testConfigurationsNotEmpty() {
        XCTAssertGreaterThan(BezelSystemMapping.configurations.count, 0,
                             "Should have at least one system configuration")
    }
}
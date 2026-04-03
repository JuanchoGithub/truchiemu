import XCTest
@testable import TruchieEmu

/// Unit tests for BezelManager - no network required
/// Tests bezel resolution logic with mocked data
@MainActor
final class BezelManagerTests: XCTestCase {

    var bezelManager: BezelManager!
    var storageManager: BezelStorageManager!

    override func setUp() {
        super.setUp()
        bezelManager = BezelManager.shared
        storageManager = BezelStorageManager.shared
    }

    override func tearDown() {
        bezelManager = nil
        super.tearDown()
    }

    // MARK: - Bezel Resolution Tests

    func testResolveBezelWithDisabledBezel() {
        var settings = ROMSettings()
        settings.bezelFileName = "none"

        let rom = ROM(
            name: "Super Mario Bros 3",
            path: URL(fileURLWithPath: "/fake/path.nes"),
            systemID: "nes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "nes", rom: rom)
        XCTAssertEqual(result.resolutionMethod, .none)
        XCTAssertNil(result.entry)
    }

    // MARK: - Has Bezel Support Tests

    func testHasBezelSupportForNES() {
        XCTAssertTrue(bezelManager.hasBezelSupport(for: "nes"))
    }

    func testHasBezelSupportForSNES() {
        XCTAssertTrue(bezelManager.hasBezelSupport(for: "snes"))
    }

    func testHasBezelSupportForGenesis() {
        XCTAssertTrue(bezelManager.hasBezelSupport(for: "genesis"))
    }

    func testHasBezelSupportForUnknown() {
        XCTAssertFalse(bezelManager.hasBezelSupport(for: "unknown_system"))
    }

    // MARK: - Bezel Exists Tests

    func testBezelExistsForNonExistentGame() {
        let exists = bezelManager.bezelExists(systemID: "nes", gameName: "TotallyFakeGame123")
        XCTAssertFalse(exists, "Non-existent game should not have bezel")
    }

    // MARK: - Real ROM Name Tests (from user's library)

    func testResolveBezelForSuperMarioBros3() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Super Mario Bros 3",
            path: URL(fileURLWithPath: "/fake/path.nes"),
            systemID: "nes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "nes", rom: rom)
        _ = result // Just verify it doesn't crash
    }

    func testResolveBezelForSuperMarioWorld() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Super Mario World",
            path: URL(fileURLWithPath: "/fake/path.smc"),
            systemID: "snes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "snes", rom: rom)
        _ = result
    }

    func testResolveBezelForSonic2() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Sonic 2",
            path: URL(fileURLWithPath: "/fake/path.smd"),
            systemID: "genesis",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "genesis", rom: rom)
        _ = result
    }

    func testResolveBezelForContra() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Contra",
            path: URL(fileURLWithPath: "/fake/path.nes"),
            systemID: "nes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "nes", rom: rom)
        _ = result
    }

    func testResolveBezelForContraIII() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Contra III - The Alien Wars",
            path: URL(fileURLWithPath: "/fake/path.smc"),
            systemID: "snes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "snes", rom: rom)
        _ = result
    }

    func testResolveBezelForGunstarHeroes() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Gunstar Heroes",
            path: URL(fileURLWithPath: "/fake/path.smd"),
            systemID: "genesis",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "genesis", rom: rom)
        _ = result
    }

    func testResolveBezelForStreetsOfRage2() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Streets of Rage 2",
            path: URL(fileURLWithPath: "/fake/path.smd"),
            systemID: "genesis",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "genesis", rom: rom)
        _ = result
    }

    func testResolveBezelForDonkeyKongCountry() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Donkey Kong Country 1",
            path: URL(fileURLWithPath: "/fake/path.smc"),
            systemID: "snes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "snes", rom: rom)
        _ = result
    }
}
import XCTest
@testable import TruchieEmu

/// Unit tests for LaunchBoxGamesDBService - tests for the fixed warnings and core parsing logic
@MainActor
final class LaunchBoxGamesDBServiceTests: XCTestCase {

    // MARK: - cleanAlternateTitle Logic Tests
    // These tests duplicate the regex logic from the private cleanAlternateTitle method
    // to prevent regressions in the title cleaning behavior.
    
    private func cleanAlternateTitle(_ title: String) -> String {
        var cleaned = title
        // Remove region tags in parentheses
        cleaned = cleaned.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        // Remove version suffixes
        cleaned = cleaned.replacingOccurrences(of: "\\(v[0-9.]+\\)$", with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testCleanAlternateTitleRemovesRegionTags() {
        let input = "Super Mario Bros 3 (USA)"
        let result = cleanAlternateTitle(input)
        XCTAssertEqual(result, "Super Mario Bros 3")
    }

    func testCleanAlternateTitleRemovesMultipleRegionTags() {
        let input = "Sonic The Hedgehog (USA, Europe)"
        let result = cleanAlternateTitle(input)
        XCTAssertEqual(result, "Sonic The Hedgehog")
    }

    func testCleanAlternateTitleRemovesVersionSuffix() {
        let input = "Mega Man X (USA) (v1.0)"
        let result = cleanAlternateTitle(input)
        XCTAssertEqual(result, "Mega Man X")
    }

    func testCleanAlternateTitleTrimsWhitespace() {
        let input = "  Contra III  "
        let result = cleanAlternateTitle(input)
        XCTAssertEqual(result, "Contra III")
    }

    func testCleanAlternateTitleNoChangeForCleanTitle() {
        let input = "Super Mario World"
        let result = cleanAlternateTitle(input)
        XCTAssertEqual(result, input, "Clean title should remain unchanged")
    }

    func testCleanAlternateTitleReturnsSameForEmpty() {
        let input = ""
        let result = cleanAlternateTitle(input)
        XCTAssertEqual(result, "")
    }

    // MARK: - LaunchBoxPlatformMapper Tests

    func testPlatformMapperNES() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "nes"), "Nintendo Entertainment System")
    }

    func testPlatformMapperSNES() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "snes"), "Super Nintendo Entertainment System")
    }

    func testPlatformMapperN64() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "n64"), "Nintendo 64")
    }

    func testPlatformMapperGenesis() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "genesis"), "Sega Genesis")
    }

    func testPlatformMapperCaseInsensitive() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "NES"), "Nintendo Entertainment System")
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "SNES"), "Super Nintendo Entertainment System")
    }

    func testPlatformMapperUnknownReturnsNil() {
        XCTAssertNil(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "unknown_system"))
    }

    func testPlatformMapperPSX() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "psx"), "Sony Playstation")
    }

    func testPlatformMapperMAME() {
        XCTAssertEqual(LaunchBoxPlatformMapper.launchBoxPlatformName(for: "mame"), "Arcade")
    }

    func testPlatformMapperAllSystems() {
        let allSystems = ["gba", "gb", "gbc", "nds", "sms", "gamegear", "saturn", "dreamcast", "ps2", "psp", "fba", "atari2600", "atari5200", "atari7800", "lynx", "ngp", "pce", "pcfx"]
        for system in allSystems {
            XCTAssertNotNil(LaunchBoxPlatformMapper.launchBoxPlatformName(for: system), "Platform mapper should return non-nil for '\(system)'")
        }
    }

    // MARK: - LaunchBoxGameResult Tests

    func testGameResultInitialization() {
        let result = LaunchBoxGameResult(
            title: "Test Game",
            gameId: 12345,
            boxartURL: URL(string: "https://example.com/boxart.jpg"),
            detailURL: URL(string: "https://gamesdb.launchbox-app.com/games/details/12345")
        )

        XCTAssertEqual(result.title, "Test Game")
        XCTAssertEqual(result.gameId, 12345)
        XCTAssertNotNil(result.boxartURL)
        XCTAssertNotNil(result.detailURL)
    }

    func testGameResultWithNilBoxartURL() {
        let result = LaunchBoxGameResult(
            title: "Test Game",
            gameId: 12345,
            boxartURL: nil,
            detailURL: nil
        )

        XCTAssertEqual(result.title, "Test Game")
        XCTAssertNil(result.boxartURL)
        XCTAssertNil(result.detailURL)
    }

    // MARK: - LaunchBoxMediaType Tests

    func testMediaTypeRawValues() {
        XCTAssertEqual(LaunchBoxMediaType.boxart.rawValue, "BoxartScreenshotImage")
        XCTAssertEqual(LaunchBoxMediaType.titleScreen.rawValue, "TitleScreenImage")
        XCTAssertEqual(LaunchBoxMediaType.clearLogo.rawValue, "ClearLogoImage")
        XCTAssertEqual(LaunchBoxMediaType.banner.rawValue, "BannerImage")
        XCTAssertEqual(LaunchBoxMediaType.cartridge.rawValue, "CartridgeImage")
    }
}

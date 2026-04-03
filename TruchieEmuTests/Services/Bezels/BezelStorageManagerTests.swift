import XCTest
@testable import TruchieEmu

/// Unit tests for BezelStorageManager - no network required
@MainActor
final class BezelStorageManagerTests: XCTestCase {

    var storageManager: BezelStorageManager!

    override func setUp() {
        super.setUp()
        storageManager = BezelStorageManager.shared
    }

    override func tearDown() {
        storageManager = nil
        super.tearDown()
    }

    // MARK: - Filename Sanitization Tests

    func testSanitizeFilenameWithSpaces() {
        let input = "Super Mario World"
        let result = storageManager.sanitizeFilename(input)
        XCTAssertEqual(result, "Super Mario World", "Spaces should be preserved")
    }

    func testSanitizeFilenameWithSlashes() {
        let input = "Game/Name"
        let result = storageManager.sanitizeFilename(input)
        XCTAssertFalse(result.contains("/"), "Forward slashes should be removed")
    }

    func testSanitizeFilenameWithBackslashes() {
        let input = "Game\\Name"
        let result = storageManager.sanitizeFilename(input)
        XCTAssertFalse(result.contains("\\"), "Backslashes should be removed")
    }

    func testSanitizeFilenameWithDots() {
        let input = "Super.Mario.Bros"
        let result = storageManager.sanitizeFilename(input)
        XCTAssertEqual(result, "Super.Mario.Bros", "Dots should be preserved")
    }

    func testSanitizeFilenameWithHyphens() {
        let input = "Sonic-the-Hedgehog"
        let result = storageManager.sanitizeFilename(input)
        XCTAssertEqual(result, "Sonic-the-Hedgehog", "Hyphens should be preserved")
    }

    func testSanitizeFilenameEmpty() {
        let input = ""
        let result = storageManager.sanitizeFilename(input)
        XCTAssertEqual(result, "unknown", "Empty string should return 'unknown'")
    }

    // MARK: - Path Construction Tests

    func testBezelFilePathConstruction() {
        let url = storageManager.bezelFilePath(systemID: "snes", gameName: "Super Mario World")
        XCTAssertEqual(url.lastPathComponent, "Super Mario World.png")
        XCTAssertTrue(url.path.contains("snes"))
    }

    func testBezelFilePathWithSpecialChars() {
        let url = storageManager.bezelFilePath(systemID: "genesis", gameName: "Sonic the Hedgehog 2")
        XCTAssertEqual(url.lastPathComponent, "Sonic the Hedgehog 2.png")
        XCTAssertTrue(url.path.contains("genesis"))
    }

    // MARK: - Storage Mode Tests

    func testDefaultStorageMode() {
        // Default should be libraryRelative
        XCTAssertEqual(storageManager.storageMode, .libraryRelative)
    }

    // MARK: - Bezel Root Directory Tests

    func testBezelRootDirectoryIsNotNil() {
        XCTAssertNotNil(storageManager.bezelRootDirectory, "Bezel root directory should not be nil")
    }

    func testBezelRootDirectoryExists() {
        try? storageManager.ensureDirectoriesExist()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageManager.bezelRootDirectory.path),
                      "Bezel root directory should exist after ensureDirectoriesExist")
    }

    // MARK: - Real ROM Name Tests (from user's library)

    func testBezelPathForRealNESGame() {
        let url = storageManager.bezelFilePath(systemID: "nes", gameName: "Super Mario Bros 3")
        XCTAssertEqual(url.lastPathComponent, "Super Mario Bros 3.png")
    }

    func testBezelPathForRealSNESGame() {
        let url = storageManager.bezelFilePath(systemID: "snes", gameName: "Super Mario World")
        XCTAssertEqual(url.lastPathComponent, "Super Mario World.png")
    }

    func testBezelPathForRealGenesisGame() {
        let url = storageManager.bezelFilePath(systemID: "genesis", gameName: "Sonic 2")
        XCTAssertEqual(url.lastPathComponent, "Sonic 2.png")
    }

    func testBezelPathForRealContraGame() {
        let url = storageManager.bezelFilePath(systemID: "nes", gameName: "Contra")
        XCTAssertEqual(url.lastPathComponent, "Contra.png")
    }

    func testBezelPathForRealContraIIIGame() {
        let url = storageManager.bezelFilePath(systemID: "snes", gameName: "Contra III - The Alien Wars")
        XCTAssertEqual(url.lastPathComponent, "Contra III - The Alien Wars.png")
    }
}
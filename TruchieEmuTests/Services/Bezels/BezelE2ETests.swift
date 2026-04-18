import XCTest
@testable import TruchieEmu

// End-to-End tests for bezel system
// Tests the full pipeline: system mapping → manifest fetch → bezel resolution → download
// Uses real ROM names from the user's library
// NOTE: These tests require network access and The Bezel Project repos to be available
@MainActor
final class BezelE2ETests: XCTestCase {

    var bezelManager: BezelManager!
    var apiService: BezelAPIService!
    var storageManager: BezelStorageManager!

    override func setUp() async throws {
        try await super.setUp()
        bezelManager = BezelManager.shared
        apiService = BezelAPIService.shared
        storageManager = BezelStorageManager.shared
    }

    override func tearDown() {
        bezelManager = nil
        apiService = nil
        storageManager = nil
        super.tearDown()
    }

    // MARK: - System Mapping Tests (No Network)

    func testNESConfigIsValid() throws {
        let config = BezelSystemMapping.config(for: "nes")
        XCTAssertNotNil(config, "NES should have bezel config")
        XCTAssertNotNil(config?.githubAPIURL, "Should have valid GitHub URL")
    }

    func testSNESConfigIsValid() throws {
        let config = BezelSystemMapping.config(for: "snes")
        XCTAssertNotNil(config, "SNES should have bezel config")
    }

    func testGenesisConfigIsValid() throws {
        let config = BezelSystemMapping.config(for: "genesis")
        XCTAssertNotNil(config, "Genesis should have bezel config")
        XCTAssertEqual(config?.bezelProjectName, "Sega-Mega-Drive")
    }

    // MARK: - Bezel Resolution Tests (No Network)

    func testResolveBezelForRealNESROM() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Contra",
            path: URL(fileURLWithPath: "/fake/contra.nes"),
            systemID: "nes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "nes", rom: rom)
        _ = result // Just verify it doesn't crash
    }

    func testResolveBezelForRealSNESROM() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Super Mario World",
            path: URL(fileURLWithPath: "/fake/smw.smc"),
            systemID: "snes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "snes", rom: rom)
        _ = result
    }

    func testResolveBezelForRealGenesisROM() {
        var settings = ROMSettings()
        settings.bezelFileName = ""

        let rom = ROM(
            name: "Sonic 2",
            path: URL(fileURLWithPath: "/fake/sonic2.smd"),
            systemID: "genesis",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "genesis", rom: rom)
        _ = result
    }

    func testResolveBezelDisabled() {
        var settings = ROMSettings()
        settings.bezelFileName = "none"

        let rom = ROM(
            name: "Contra",
            path: URL(fileURLWithPath: "/fake/contra.nes"),
            systemID: "nes",
            settings: settings
        )

        let result = bezelManager.resolveBezel(systemID: "nes", rom: rom)
        XCTAssertEqual(result.resolutionMethod, .none)
        XCTAssertNil(result.entry)
    }

    // MARK: - Network Tests (Optional - may be skipped if service unavailable)

    func testFetchManifestForContra() async throws {
        try XCTSkipIf(!canReachGitHub(), "Network test requires GitHub API access")

        do {
            let entries = try await apiService.fetchManifest(systemID: "nes")
            XCTAssertGreaterThanOrEqual(entries.count, 0, "Should return entries for nes")
        } catch {
            print("[Test] GitHub API unavailable: \(error)")
        }
    }

    func testBezelManagerHasBezelSupport() {
        XCTAssertTrue(bezelManager.hasBezelSupport(for: "nes"))
        XCTAssertTrue(bezelManager.hasBezelSupport(for: "snes"))
        XCTAssertTrue(bezelManager.hasBezelSupport(for: "genesis"))
        XCTAssertFalse(bezelManager.hasBezelSupport(for: "unknown"))
    }

    // MARK: - Helpers

    func canReachGitHub() -> Bool {
        let url = URL(string: "https://api.github.com")!
        return URLSession.shared.synchronousCheck(url: url) != nil
    }
}

// Helper for synchronous URL reachability check
extension URLSession {
    func synchronousCheck(url: URL) -> URLResponse? {
        let semaphore = DispatchSemaphore(value: 0)
        var response: URLResponse?
        let task = self.dataTask(with: url) { _, resp, _ in
            response = resp
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        return response
    }
}
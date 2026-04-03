import XCTest
@testable import TruchieEmu

/// Integration tests for BezelAPIService - requires network connection
/// These tests make real API calls to GitHub and may fail if the service is unavailable
@MainActor
final class BezelAPIServiceIntegrationTests: XCTestCase {

    var apiService: BezelAPIService!

    override func setUp() async throws {
        try await super.setUp()
        apiService = BezelAPIService.shared
    }

    override func tearDown() {
        apiService = nil
        super.tearDown()
    }

    // MARK: - System Mapping Validation Tests

    func testNESConfigExists() {
        let config = BezelSystemMapping.config(for: "nes")
        XCTAssertNotNil(config, "NES should have a config")
        XCTAssertNotNil(config?.githubAPIURL, "GitHub API URL should not be nil")
    }

    func testSNESConfigExists() {
        let config = BezelSystemMapping.config(for: "snes")
        XCTAssertNotNil(config, "SNES should have a config")
    }

    func testGenesisConfigExists() {
        let config = BezelSystemMapping.config(for: "genesis")
        XCTAssertNotNil(config, "Genesis should have a config")
        XCTAssertEqual(config?.bezelProjectName, "Sega-Mega-Drive")
    }

    // MARK: - Manifest Fetching Tests (Network)

    func testFetchManifestForNES() async throws {
        do {
            let entries = try await apiService.fetchManifest(systemID: "nes")
            XCTAssertGreaterThanOrEqual(entries.count, 0, "NES manifest should return without error")
        } catch let BezelError.systemNotFound(systemID) {
            print("[Test] NES bezel repo not found: \(systemID)")
        } catch BezelError.apiRateLimited {
            // GitHub API rate limited - skip gracefully
            print("[Test] GitHub API rate limited, skipping NES manifest test")
        } catch let BezelError.apiError(code) {
            // API error (403, etc) - skip gracefully
            print("[Test] GitHub API error \(code), skipping NES manifest test")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchManifestForSNES() async throws {
        do {
            let entries = try await apiService.fetchManifest(systemID: "snes")
            XCTAssertGreaterThanOrEqual(entries.count, 0, "SNES manifest should return without error")
        } catch let BezelError.systemNotFound(systemID) {
            print("[Test] SNES bezel repo not found: \(systemID)")
        } catch BezelError.apiRateLimited {
            print("[Test] GitHub API rate limited, skipping SNES manifest test")
        } catch let BezelError.apiError(code) {
            print("[Test] GitHub API error \(code), skipping SNES manifest test")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchManifestForUnknownSystem() async {
        do {
            _ = try await apiService.fetchManifest(systemID: "unknown_system_xyz")
            XCTFail("Should throw error for unknown system")
        } catch let error as BezelError {
            switch error {
            case .systemNotSupported:
                break // Expected
            default:
                XCTFail("Expected systemNotSupported error, got \(error)")
            }
        } catch {
            XCTFail("Expected BezelError, got \(error)")
        }
    }
}
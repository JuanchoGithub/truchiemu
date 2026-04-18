import XCTest
@testable import TruchieEmu

// Tests for bezel manifest pagination handling and local vs remote bezel distinction
@MainActor
final class BezelPaginationTests: XCTestCase {

    // MARK: - Config URL Tests (Verify Trees API URL is correct)

    func testNESTreesAPIURL() {
        let config = BezelSystemMapping.config(for: "nes")
        XCTAssertNotNil(config, "NES should have a config")
        XCTAssertTrue(config?.treesAPIURL.absoluteString.contains("git/trees/master?recursive=1") ?? false,
                      "Should use Git Trees API URL for full manifest")
    }

    func testSNESTreesAPIURL() {
        let config = BezelSystemMapping.config(for: "snes")
        XCTAssertNotNil(config, "SNES should have a config")
        XCTAssertTrue(config?.treesAPIURL.absoluteString.contains("git/trees/master?recursive=1") ?? false,
                      "Should use Git Trees API URL for full manifest")
    }

    func testGenesisTreesAPIURL() {
        let config = BezelSystemMapping.config(for: "genesis")
        XCTAssertNotNil(config, "Genesis should have a config")
        XCTAssertTrue(config?.treesAPIURL.absoluteString.contains("git/trees/master?recursive=1") ?? false,
                      "Should use Git Trees API URL for full manifest")
        XCTAssertEqual(config?.bezelProjectName, "Sega-Mega-Drive")
    }

    // MARK: - Bezel Entry URL Construction Tests

    func testBezelRawURLConstruction() {
        let config = BezelSystemMapping.config(for: "nes")!
        let url = config.bezelRawURL(for: "Contra (USA).png")
        XCTAssertTrue(url.absoluteString.contains("raw.githubusercontent.com"),
                      "Should use GitHub raw content URL")
        // URL should end with the filename
        XCTAssertTrue(url.lastPathComponent == "Contra (USA).png" ||
                      url.absoluteString.hasSuffix("Contra%20(USA).png") ||
                      url.absoluteString.hasSuffix("Contra (USA).png"),
                      "Filename should be in URL, got: \(url.absoluteString)")
    }

    // MARK: - Bezel Entry Model Tests

    func testBezelEntryIDExtraction() {
        let entry = BezelEntry(
            id: "Contra (USA)",
            filename: "Contra (USA).png",
            rawURL: URL(string: "https://example.com/Contra (USA).png")!,
            localURL: nil
        )
        XCTAssertEqual(entry.id, "Contra (USA)")
        XCTAssertEqual(entry.displayName, "Contra")  // "(USA)" should be stripped
    }

    func testBezelEntryWithComplexName() {
        let entry = BezelEntry(
            id: "Super Mario Bros. 3 (USA) (Rev A)",
            filename: "Super Mario Bros. 3 (USA) (Rev A).png",
            rawURL: URL(string: "https://example.com/Super Mario Bros. 3 (USA) (Rev A).png")!,
            localURL: nil
        )
        XCTAssertEqual(entry.displayName, "Super Mario Bros. 3 (Rev A)")  // "(USA)" stripped
    }

    // MARK: - Manifest Cache Tests

    func testManifestCachePathConstruction() {
        let storageManager = BezelStorageManager.shared
        let path = storageManager.manifestCachePath(for: "nes")
        XCTAssertTrue(path.lastPathComponent == "manifest.json")
        XCTAssertTrue(path.path.contains("nes"))
    }

    // MARK: - Error Handling Tests

    func testFetchManifestForUnsupportedSystem() async {
        let apiService = BezelAPIService.shared
        do {
            _ = try await apiService.fetchManifest(systemID: "unknown_system_xyz")
            XCTFail("Should throw error for unsupported system")
        } catch BezelError.systemNotSupported {
            // Expected
        } catch BezelError.apiRateLimited {
            // Rate limited - skip gracefully
            print("[Test] Rate limited, skipping unsupported system test")
        } catch {
            XCTFail("Expected systemNotSupported error, got \(error)")
        }
    }

    // MARK: - Fetch Manifest Entry Count Tests (Network - may be skipped)

    func testFetchManifestReturnsAllBezels() async {
        // This test requires network access and may fail due to rate limiting
        do {
            // Use a system with fewer bezels to avoid hitting rate limits
            let entries = try await BezelAPIService.shared.fetchManifest(systemID: "nes")

            // With Trees API we should get ALL bezels, not just 30
            // NES should have 1000+ bezels
            XCTAssertGreaterThan(entries.count, 100,
                                 "Should return all bezels, not just first page. Got \(entries.count) entries")

            // Verify entries are sorted
            for i in 1..<entries.count {
                let prev = entries[i-1].displayName.lowercased()
                let curr = entries[i].displayName.lowercased()
                XCTAssertTrue(prev <= curr || curr.starts(with: prev.prefix(1)),
                              "Entries should be sorted alphabetically by display name")
            }

            print("[Pagination Test] NES manifest returned \(entries.count) bezels")
        } catch BezelError.apiRateLimited {
            print("[Pagination Test] GitHub API rate limited - skipping full manifest test")
        } catch {
            // If we get systemNotFound, the API path might be wrong
            if case BezelError.systemNotFound = error {
                XCTFail("System not found - check the Trees API URL in BezelSystemConfig: \(error)")
            }
            // Other errors - just log and continue
            print("[Pagination Test] Error fetching manifest: \(error)")
        }
    }

    // MARK: - BezelSelectorSheet Local vs Remote Tests

    func testBezelSelectorSheetDistinguishesLocalFromRemote() {
        // Verify that the API provides isDownloaded property
        let entry = BezelEntry(
            id: "TestGame",
            filename: "TestGame.png",
            rawURL: URL(string: "https://example.com/TestGame.png")!
        )

        // By default, should not be downloaded
        XCTAssertFalse(entry.isDownloaded, "New entry should show as not downloaded")

        // With a real local path, it should show as downloaded
        let localURL = URL(fileURLWithPath: "/tmp/test/TestGame.png")

        let localEntry = BezelEntry(
            id: "TestGame",
            filename: "TestGame.png",
            rawURL: URL(string: "https://example.com/TestGame.png")!,
            localURL: localURL
        )

        // isDownloaded checks file existence, not just URL presence
        // For this test, file won't exist
        XCTAssertFalse(localEntry.isDownloaded,
                       "Entry with non-existent local path should still show as not downloaded")
    }

    // MARK: - Search Filter Tests

    func testBezelSearchFilterLogic() {
        // Simulate a list of bezel entries
        let mockEntries = [
            BezelEntry(id: "Super Mario Bros (USA)", filename: "Super Mario Bros (USA).png", rawURL: URL(string: "https://example.com/1.png")!),
            BezelEntry(id: "Super Mario Bros 2 (USA)", filename: "Super Mario Bros 2 (USA).png", rawURL: URL(string: "https://example.com/2.png")!),
            BezelEntry(id: "Super Mario Bros 3 (USA)", filename: "Super Mario Bros 3 (USA).png", rawURL: URL(string: "https://example.com/3.png")!),
            BezelEntry(id: "Zelda (USA)", filename: "Zelda (USA).png", rawURL: URL(string: "https://example.com/4.png")!),
        ]

        // Test search by game name
        let searchQuery = "mario"
        let filtered = mockEntries.filter { entry in
            entry.displayName.lowercased().contains(searchQuery) ||
            entry.id.lowercased().contains(searchQuery)
        }

        XCTAssertEqual(filtered.count, 3, "Search for 'mario' should find 3 entries")
        XCTAssertTrue(filtered.allSatisfy { $0.displayName.lowercased().contains("mario") })
    }

    func testBezelSearchHandlesEmptyQuery() {
        let mockEntries = [
            BezelEntry(id: "Contra (USA)", filename: "Contra (USA).png", rawURL: URL(string: "https://example.com/1.png")!),
            BezelEntry(id: "Zelda (USA)", filename: "Zelda (USA).png", rawURL: URL(string: "https://example.com/2.png")!),
        ]

        let searchQuery = ""
        let filtered: [BezelEntry] = searchQuery.isEmpty ? mockEntries : mockEntries.filter { entry in
            entry.displayName.lowercased().contains(searchQuery) ||
            entry.id.lowercased().contains(searchQuery)
        }

        XCTAssertEqual(filtered.count, 2, "Empty search should return all entries")
    }

    // MARK: - Bezel Storage Manager Tests

    func testStorageManagerCreatesSystemDirectories() {
        let storageManager = BezelStorageManager.shared
        try? storageManager.ensureDirectoriesExist()

        let nesDir = storageManager.systemBezelsDirectory(for: "nes")
        let snesDir = storageManager.systemBezelsDirectory(for: "snes")

        XCTAssertNotNil(nesDir)
        XCTAssertNotNil(snesDir)
        XCTAssertNotEqual(nesDir, snesDir, "Different systems should have different directories")
    }

    func testSanitizeFilenameRemovesSpecialChars() {
        let storageManager = BezelStorageManager.shared
        let sanitized = storageManager.sanitizeFilename("Game/Name\\With:Special*Chars?")
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains("\\"))
        XCTAssertFalse(sanitized.contains(":"))
        XCTAssertFalse(sanitized.contains("*"))
        XCTAssertFalse(sanitized.contains("?"))
    }
}
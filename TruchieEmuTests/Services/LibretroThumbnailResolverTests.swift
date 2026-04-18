import XCTest
@testable import TruchieEmu

@MainActor
final class LibretroThumbnailResolverTests: XCTestCase {

    // MARK: - URL Generation Order Tests

    func testCandidateURLs_PrioritizesNamedBoxartsFuzzy_WhenBoxartPriority() {
        // Simulate CRC-resolved title with region tags
        let title = "Super Mario Bros. 3 (USA) (En)"
        let urls = LibretroThumbnailResolver.candidateURLs(
            base: URL(string: "https://thumbnails.libretro.com")!,
            systemFolder: "Nintendo - Nintendo Entertainment System",
            gameTitle: title,
            priority: .boxart
        )

        // First URL should be Named_Boxarts with stripped title
        let firstURL = urls.first
        XCTAssertNotNil(firstURL, "Should generate at least one candidate URL")
        XCTAssertTrue(
            firstURL?.path.contains("Named_Boxarts") ?? false,
            "First URL should be from Named_Boxarts folder"
        )
        // The fuzzy-stripped title "Super Mario Bros. 3" should be in the first URL
        XCTAssertTrue(
            firstURL?.absoluteString.contains("Super Mario Bros. 3") ?? false,
            "First URL should contain the fuzzy-stripped title without region tags"
        )
        // Verify Named_Titles comes before Named_Snaps
        let boxartIndex = urls.firstIndex { $0.path.contains("Named_Boxarts") }
        let titlesIndex = urls.firstIndex { $0.path.contains("Named_Titles") }
        if let boxartIndex, let titlesIndex {
            XCTAssertLessThan(boxartIndex, titlesIndex, "Named_Boxarts should be tried before Named_Titles")
        }
    }

    func testCandidateURLs_PrioritizesNamedTitles_WhenTitlePriority() {
        let title = "Donkey Kong Country (USA)"
        let urls = LibretroThumbnailResolver.candidateURLs(
            base: URL(string: "https://thumbnails.libretro.com")!,
            systemFolder: "Nintendo - Super Nintendo Entertainment System",
            gameTitle: title,
            priority: .title
        )

        let firstURL = urls.first
        XCTAssertNotNil(firstURL)
        XCTAssertTrue(
            firstURL?.path.contains("Named_Titles") ?? false,
            "First URL should be from Named_Titles when title priority is set"
        )
    }

    func testStripRomFilenameTags_RemovesTrailingParentheses() {
        let input = "Super Mario 64 (USA) (En,Ja)"
        let result = LibretroThumbnailResolver.stripRomFilenameTags(input)
        XCTAssertEqual(result, "Super Mario 64")
    }

    func testStripParenthesesForFuzzyMatch_RemovesAllParentheses() {
        let input = "Sonic the Hedgehog (USA, Europe) (En)"
        let result = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(input)
        XCTAssertEqual(result, "Sonic the Hedgehog")
    }

    func testLibretroFilesystemSafeName() {
        let input = "Game & Watch (Prototype)"
        let result = LibretroThumbnailResolver.libretroFilesystemSafeName(input)
        // & should be replaced with _
        XCTAssertEqual(result, "Game _ Watch (Prototype)")
    }

    func testOrderedThumbnailTypeFolders_BoxartFirst() {
        let folders = LibretroThumbnailResolver.orderedThumbnailTypeFolders(priority: .boxart)
        XCTAssertEqual(folders, ["Named_Boxarts", "Named_Titles", "Named_Snaps"])
    }

    func testOrderedThumbnailTypeFolders_TitleFirst() {
        let folders = LibretroThumbnailResolver.orderedThumbnailTypeFolders(priority: .title)
        XCTAssertEqual(folders, ["Named_Titles", "Named_Boxarts", "Named_Snaps"])
    }

    func testFolderMapping_SMS() {
        XCTAssertEqual(
            LibretroThumbnailResolver.libretroFolderName(forSystemID: "sms"),
            "Sega - Master System - Mark III"
        )
    }

    func testFolderMapping_NES() {
        XCTAssertEqual(
            LibretroThumbnailResolver.libretroFolderName(forSystemID: "nes"),
            "Nintendo - Nintendo Entertainment System"
        )
    }

    func testFolderMapping_Unknown() {
        XCTAssertNil(LibretroThumbnailResolver.libretroFolderName(forSystemID: "unknown"))
    }

    func testFolderMapping_32X() {
        XCTAssertEqual(
            LibretroThumbnailResolver.libretroFolderName(forSystemID: "32x"),
            "Sega - 32X"
        )
    }

    func testFolderMapping_3DO() {
        XCTAssertEqual(
            LibretroThumbnailResolver.libretroFolderName(forSystemID: "3do"),
            "The 3DO Company - 3DO"
        )
    }

    // MARK: - Live CDN Integration Tests

    // Tests that the URL generation order prefers Named_Boxarts over Named_Titles
    // using a real game that has both on the Libretro CDN.
    func testRealGame_BoxartPreferredOverTitle() async throws {
        // "Super Mario Bros. 3 (USA)" has both boxart and title on the CDN
        let title = "Super Mario Bros. 3 (USA)"
        let urls = LibretroThumbnailResolver.candidateURLs(
            base: URL(string: "https://thumbnails.libretro.com")!,
            systemFolder: "Nintendo - Nintendo Entertainment System",
            gameTitle: title,
            priority: .boxart
        )

        // Find the first URL that actually exists on the CDN
        var firstMatchURL: URL?
        for url in urls {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    firstMatchURL = url
                    break
                }
            } catch {
                continue
            }
        }

        XCTAssertNotNil(firstMatchURL, "Should find at least one matching URL")

        // If we found the title-screen entry in Named_Boxarts, skip this test
        // (since we care about boxart vs title ordering)
        guard let firstMatchURL else { return }

        XCTAssertTrue(
            firstMatchURL.absoluteString.contains("Named_Boxarts"),
            "First successful URL should be from Named_Boxarts, got: \(firstMatchURL.absoluteString)"
        )
    }

    // MARK: - Known Variants Tests

    func testCandidateURLsWithKnownVariants_IncludesVariantsBeforeSuffixGuessing() {
        let title = "Columns (USA, Europe, Brazil) (En)"
        let knownVariants = [
            "Columns (USA, Europe, Brazil) (En)",
            "Columns (USA, Europe, Brazil) (En) (Beta)",
        ]
        let urls = LibretroThumbnailResolver.candidateURLs(
            base: URL(string: "https://thumbnails.libretro.com")!,
            systemFolder: "Sega - Master System - Mark III",
            gameTitle: title,
            knownVariants: knownVariants,
            priority: .boxart
        )

        // Verify that the known variant (Beta) appears before arbitrary suffix guessing
        let betaVar = urls.first { $0.absoluteString.contains("Beta") }
        let suffixRev = urls.first { $0.absoluteString.contains("(Rev 1)") }
        
        XCTAssertNotNil(betaVar, "Should include Known Beta variant URL")
        if let betaVar, let suffixRev {
            let betaIdx = urls.firstIndex(of: betaVar)!
            let revIdx = urls.firstIndex(of: suffixRev)!
            XCTAssertLessThan(betaIdx, revIdx, "Known variant (Beta) should be tried before arbitrary suffix (Rev 1)")
        }
    }

    func testCandidateURLsWithEmptyKnownVariants_FallsBackToSuffixGuessing() {
        let title = "Sonic the Hedgehog (USA, Europe)"
        let urls = LibretroThumbnailResolver.candidateURLs(
            base: URL(string: "https://thumbnails.libretro.com")!,
            systemFolder: "Sega - Master System - Mark III",
            gameTitle: title,
            knownVariants: [],
            priority: .boxart
        )

        // Should still generate suffix variants as fallback
        let suffixURLs = urls.filter { $0.absoluteString.contains("(Beta)") || $0.absoluteString.contains("(Rev 1)") }
        XCTAssertFalse(suffixURLs.isEmpty, "Should generate arbitrary suffix variants when no known variants provided")
    }
}

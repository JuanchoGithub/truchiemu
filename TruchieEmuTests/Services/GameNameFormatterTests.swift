import XCTest
@testable import TruchieEmu

final class GameNameFormatterTests: XCTestCase {
    
    func testStripRegionTags() {
        XCTAssertEqual(GameNameFormatter.stripTags("Ecco the Dolphin (World)"), "Ecco the Dolphin")
        XCTAssertEqual(GameNameFormatter.stripTags("Super Mario Bros. (USA)"), "Super Mario Bros.")
        XCTAssertEqual(GameNameFormatter.stripTags("Sonic the Hedgehog (Europe)"), "Sonic the Hedgehog")
        XCTAssertEqual(GameNameFormatter.stripTags("Mega Man 2 (Japan)"), "Mega Man 2")
    }
    
    func testStripMultipleTags() {
        XCTAssertEqual(GameNameFormatter.stripTags("Super Mario Bros. (USA, Europe)"), "Super Mario Bros.")
        XCTAssertEqual(GameNameFormatter.stripTags("Ecco the Dolphin (USA) (Rev 1)"), "Ecco the Dolphin")
    }
    
    func testStripBracketTags() {
        XCTAssertEqual(GameNameFormatter.stripTags("Sonic the Hedgehog [!]"), "Sonic the Hedgehog")
        XCTAssertEqual(GameNameFormatter.stripTags("Game [b1]"), "Game")
        XCTAssertEqual(GameNameFormatter.stripTags("Game [f1]"), "Game")
    }
    
    func testMixedTags() {
        XCTAssertEqual(GameNameFormatter.stripTags("Game Name (USA) [!]"), "Game Name")
        XCTAssertEqual(GameNameFormatter.stripTags("Game [b1] (Europe)"), "Game")
    }
    
    func testNoTags() {
        XCTAssertEqual(GameNameFormatter.stripTags("Clean Game Name"), "Clean Game Name")
        XCTAssertEqual(GameNameFormatter.stripTags("Simple"), "Simple")
    }
    
    func testExtraWhitespace() {
        XCTAssertEqual(GameNameFormatter.stripTags("Game Name  (USA)"), "Game Name")
        XCTAssertEqual(GameNameFormatter.stripTags("Game  Name (World)"), "Game  Name") // Double space mid-string preserved
    }
    
    func testEmptyStrings() {
        XCTAssertEqual(GameNameFormatter.stripTags(""), "")
        XCTAssertEqual(GameNameFormatter.stripTags("   "), "")
    }
    
    func testHasTags() {
        XCTAssertTrue(GameNameFormatter.hasTags("Game (USA)"))
        XCTAssertTrue(GameNameFormatter.hasTags("Game [!]"))
        XCTAssertFalse(GameNameFormatter.hasTags("Clean Game Name"))
    }
    
    // MARK: - Space Removal Tests
    
    func testRemoveSpaces() {
        XCTAssertEqual(GameNameFormatter.removeSpaces("Shadow Run"), "ShadowRun")
        XCTAssertEqual(GameNameFormatter.removeSpaces("Mega Man 2"), "MegaMan2")
        XCTAssertEqual(GameNameFormatter.removeSpaces("Super Mario Bros."), "SuperMarioBros.")
        XCTAssertEqual(GameNameFormatter.removeSpaces("NoSpacesHere"), "NoSpacesHere")
        XCTAssertEqual(GameNameFormatter.removeSpaces(""), "")
        XCTAssertEqual(GameNameFormatter.removeSpaces("   "), "")
        XCTAssertEqual(GameNameFormatter.removeSpaces("Single Space"), "SingleSpace")
    }
    
    func testNormalizedComparisonKey() {
        // Should strip tags, remove spaces, and lowercase
        XCTAssertEqual(GameNameFormatter.normalizedComparisonKey("Shadow Run (USA)"), "shadowrun")
        XCTAssertEqual(GameNameFormatter.normalizedComparisonKey("ShadowRun [!]"), "shadowrun")
        XCTAssertEqual(GameNameFormatter.normalizedComparisonKey("shadow run"), "shadowrun")
        XCTAssertEqual(GameNameFormatter.normalizedComparisonKey("SHADOW RUN"), "shadowrun")
        XCTAssertEqual(GameNameFormatter.normalizedComparisonKey("Mega Man 2 (USA, Europe)"), "megaman2")
        XCTAssertEqual(GameNameFormatter.normalizedComparisonKey("Super Mario Bros."), "supermariobros.")
    }
    
    func testSpaceMatching() {
        // Verify that "ShadowRun" and "Shadow Run" normalize to the same key
        let key1 = GameNameFormatter.normalizedComparisonKey("ShadowRun")
        let key2 = GameNameFormatter.normalizedComparisonKey("Shadow Run")
        XCTAssertEqual(key1, key2, "ShadowRun and Shadow Run should match after normalization")
        
        // Verify multi-word variations
        let key3 = GameNameFormatter.normalizedComparisonKey("Mega Man X")
        let key4 = GameNameFormatter.normalizedComparisonKey("MegaManX")
        XCTAssertEqual(key3, key4, "Mega Man X and MegaManX should match after normalization")
        
        // Verify with tags
        let key5 = GameNameFormatter.normalizedComparisonKey("Final Fantasy VII (USA)")
        let key6 = GameNameFormatter.normalizedComparisonKey("FinalFantasyVII")
        XCTAssertEqual(key5, key6, "Final Fantasy VII (USA) and FinalFantasyVII should match after normalization")
    }
}

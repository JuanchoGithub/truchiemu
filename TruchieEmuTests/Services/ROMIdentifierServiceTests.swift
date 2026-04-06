import XCTest
@testable import TruchieEmu

final class ROMIdentifierServiceTests: XCTestCase {

    // MARK: - Number Variant Generation Tests

    func testRomanNumeralVariants_ArabicToRoman() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "double dragon 3")
        XCTAssertTrue(variants.contains("double dragon III"), "Should generate Roman numeral variant")
    }

    func testRomanNumeralVariants_ArabicToText() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "double dragon 3")
        XCTAssertTrue(variants.contains("double dragon three"), "Should generate text number variant")
    }

    func testRomanNumeralVariants_RomanToArabic() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "double dragon iii")
        XCTAssertTrue(variants.contains("double dragon 3"), "Should convert Roman to Arabic")
    }

    func testRomanNumeralVariants_RomanToText() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "double dragon iii")
        XCTAssertTrue(variants.contains("double dragon three"), "Should convert Roman to text")
    }

    func testRomanNumeralVariants_TextToArabic() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "double dragon three")
        XCTAssertTrue(variants.contains("double dragon 3"), "Should convert text to Arabic")
    }

    func testRomanNumeralVariants_TextToRoman() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "double dragon three")
        XCTAssertTrue(variants.contains("double dragon III"), "Should convert text to Roman")
    }

    func testRomanNumeralVariants_HandlesMultipleNumbers() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "game 1 and 2")
        XCTAssertTrue(variants.contains("game I and 2"), "Should convert first number")
        XCTAssertTrue(variants.contains("game 1 and II"), "Should convert second number")
    }

    func testRomanNumeralVariants_StripsTrailingOne() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "road rash 1")
        XCTAssertTrue(variants.contains("road rash"), "Should strip trailing 1 for first-in-series")
    }

    func testRomanNumeralVariants_StripsTrailingRomanI() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "ecco the dolphin i")
        XCTAssertTrue(variants.contains("ecco the dolphin"), "Should strip trailing 'I' for first-in-series")
    }

    func testRomanNumeralVariants_StripsTrailingTextOne() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "ecco the dolphin one")
        XCTAssertTrue(variants.contains("ecco the dolphin"), "Should strip trailing 'one' for first-in-series")
    }

    func testRomanNumeralVariants_FirstInSeriesDoesNotMatchSequel() {
        // "ecco the dolphin 1" should NOT match "ecco the dolphin ii"
        // The stripped variant "ecco the dolphin" should exist but not "ecco the dolphin ii"
        let variants = ROMIdentifierService.romanNumeralVariants(of: "ecco the dolphin 1")
        XCTAssertTrue(variants.contains("ecco the dolphin"), "Should produce stripped variant")
        XCTAssertFalse(variants.contains("ecco the dolphin ii"), "Should not produce sequel variant")
    }

    func testRomanNumeralVariants_ShortString() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "a")
        XCTAssertTrue(variants.isEmpty, "Should return empty for short strings")
    }

    func testRomanNumeralVariants_DoesNotMatchNumbersInWords() {
        let variants = ROMIdentifierService.romanNumeralVariants(of: "mario kart")
        // "i" in "mario" should not be matched as Roman numeral
        // This is handled by the word boundary regex
        XCTAssertFalse(variants.contains("mar1o kart"), "Should not match Roman numerals inside words")
    }

    // MARK: - Partial Match Protection Tests

    func testIsProblematicNumberSuffixPartialMatch_ArabicNumber() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "double dragon 3",
            candidate: "double dragon"
        )
        XCTAssertTrue(result, "Should flag 'double dragon 3' vs 'double dragon' as problematic")
    }

    func testIsProblematicNumberSuffixPartialMatch_RomanNumber() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "double dragon iii",
            candidate: "double dragon"
        )
        XCTAssertTrue(result, "Should flag 'double dragon iii' vs 'double dragon' as problematic")
    }

    func testIsProblematicNumberSuffixPartialMatch_TextNumber() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "double dragon three",
            candidate: "double dragon"
        )
        XCTAssertTrue(result, "Should flag 'double dragon three' vs 'double dragon' as problematic")
    }

    func testIsProblematicNumberSuffixPartialMatch_AllowedArticle() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "the legend of zelda",
            candidate: "legend of zelda"
        )
        XCTAssertFalse(result, "Should allow 'the' article difference")
    }

    func testIsProblematicNumberSuffixPartialMatch_ExactMatch() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "double dragon",
            candidate: "double dragon"
        )
        XCTAssertFalse(result, "Exact match should not be problematic")
    }

    func testIsProblematicNumberSuffixPartialMatch_NoContainment() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "final fantasy",
            candidate: "street fighter"
        )
        XCTAssertFalse(result, "No containment should not be problematic")
    }

    func testIsProblematicNumberSuffixPartialMatch_ReversedOrder() {
        let result = ROMIdentifierService.isProblematicNumberSuffixPartialMatch(
            query: "double dragon",
            candidate: "double dragon 3"
        )
        XCTAssertTrue(result, "Should flag regardless of which is query vs candidate")
    }

    // MARK: - Normalization Tests

    func testNormalizedComparableTitle_StripsParentheses() {
        let result = ROMIdentifierService.normalizedComparableTitle("Double Dragon (USA, Europe)")
        XCTAssertEqual(result, "double dragon")
    }

    func testNormalizedComparableTitle_CollapsesWhitespace() {
        let result = ROMIdentifierService.normalizedComparableTitle("Double   Dragon")
        XCTAssertEqual(result, "double dragon")
    }

    func testAggressivelyNormalizedTitle_StripsBrackets() {
        let result = ROMIdentifierService.aggressivelyNormalizedTitle("Double Dragon [!] (USA)")
        XCTAssertEqual(result, "double dragon")
    }

    func testAggressivelyNormalizedTitle_StripsBraces() {
        let result = ROMIdentifierService.aggressivelyNormalizedTitle("Double Dragon {hack}")
        XCTAssertEqual(result, "double dragon")
    }

    // MARK: - Article Reformatting Tests

    func testMoveArticleToEnd_MovesA() {
        let result = ROMIdentifierService.moveArticleToEnd("A Dinosaur's Tale")
        XCTAssertEqual(result, "dinosaur's tale, A", "Should move 'A' to the end")
    }

    func testMoveArticleToEnd_MovesAn() {
        let result = ROMIdentifierService.moveArticleToEnd("An American Tail")
        XCTAssertEqual(result, "american tail, An", "Should move 'An' to the end")
    }

    func testMoveArticleToEnd_MovesThe() {
        let result = ROMIdentifierService.moveArticleToEnd("The Legend of Zelda")
        XCTAssertEqual(result, "legend of zelda, The", "Should move 'The' to the end")
    }

    func testMoveArticleToEnd_NoArticle() {
        let result = ROMIdentifierService.moveArticleToEnd("Double Dragon")
        XCTAssertNil(result, "Should return nil when no leading article")
    }

    func testMoveArticleToEnd_CaseInsensitive() {
        let result = ROMIdentifierService.moveArticleToEnd("a dinosaur's tale")
        XCTAssertEqual(result, "dinosaur's tale, A", "Should handle lowercase article")
    }

    func testArticleVariants_ForwardAndBackward() {
        // "a dinosaur's tale" → "dinosaur's tale, A" (article is capitalized)
        let forward = ROMIdentifierService.articleVariants(of: "a dinosaur's tale")
        XCTAssertTrue(forward.contains("dinosaur's tale, A"), "Should generate article-moved-to-end variant (capitalized)")

        // "dinosaur's tale, a" → "a dinosaur's tale"
        let backward = ROMIdentifierService.articleVariants(of: "dinosaur's tale, a")
        XCTAssertTrue(backward.contains("a dinosaur's tale"), "Should generate article-moved-to-front variant")
    }

    func testArticleVariants_The() {
        let forward = ROMIdentifierService.articleVariants(of: "the legend of zelda")
        XCTAssertTrue(forward.contains("legend of zelda, The"), "Should move 'the' to end")

        let backward = ROMIdentifierService.articleVariants(of: "legend of zelda, the")
        XCTAssertTrue(backward.contains("the legend of zelda"), "Should move 'the' to front")
    }

    func testArticleVariants_NoArticle() {
        let variants = ROMIdentifierService.articleVariants(of: "double dragon")
        XCTAssertTrue(variants.isEmpty, "Should return empty for titles without articles")
    }

    func testArticleVariant_MatchesDatabaseEntry() {
        // Simulate: ROM file = "A Dinosaur's Tale.smd", DB entry = "Dinosaur's Tale, A (USA)"
        let romQuery = ROMIdentifierService.normalizedComparableTitle("A Dinosaur's Tale")
        let dbEntry = ROMIdentifierService.normalizedComparableTitle("Dinosaur's Tale, A (USA)")

        // Direct match should fail
        XCTAssertNotEqual(romQuery, dbEntry, "Direct normalized comparison should not match")

        // But with article variant, it should match (after lowercasing for comparison)
        let articleVariants = ROMIdentifierService.articleVariants(of: romQuery)
        let lowercasedVariants = articleVariants.map { $0.lowercased() }
        XCTAssertTrue(lowercasedVariants.contains(dbEntry), "Article variant (lowercased) should match DB entry")
    }
}
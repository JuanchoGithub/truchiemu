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
}
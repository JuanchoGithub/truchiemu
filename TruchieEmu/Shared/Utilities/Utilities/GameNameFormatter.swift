import Foundation

// Utility for formatting and cleaning game display names.
// Strips common ROM tags like region indicators, revision info, and other metadata
// that appear in parentheses or square brackets in ROM filenames and database entries.
enum GameNameFormatter {
    
    // MARK: - Public API
    
    // Strip all tags from a game name.
    // Examples:
    //   "Ecco the Dolphin (World)" → "Ecco the Dolphin"
    //   "Super Mario Bros. (USA, Europe)" → "Super Mario Bros."
    //   "Sonic the Hedgehog [!]" → "Sonic the Hedgehog"
    //   "Mega Man 2 (Rev 1)" → "Mega Man 2"
    static func stripTags(_ name: String) -> String {
        // Optimized: Single pass regex to remove both square brackets and parentheses content
        // This is much faster than multiple loops with subrange mutations.
        let pattern = "\\s*(\\[[^\\]]*\\]|\\([^\\)]*\\))"
        let stripped = name.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return cleanWhitespace(stripped)
    }
    
    // Remove content within square brackets: [!], [b1], [f1], etc.
    static func removeBrackets(_ name: String) -> String {
        return name.replacingOccurrences(of: "\\s*\\[[^\\]]*\\]", with: "", options: .regularExpression)
    }
    
    // Remove content within parentheses: (USA), (World), (Rev 1), (En,Fr,De), etc.
    static func removeParentheses(_ name: String) -> String {
        return name.replacingOccurrences(of: "\\s*\\([^\\)]*\\)", with: "", options: .regularExpression)
    }
    
    // Clean up extra whitespace left after tag removal.
    static func cleanWhitespace(_ name: String) -> String {
        // Replace multiple spaces with single space and trim
        return name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                   .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Check if a name contains any tags that would be stripped.
    static func hasTags(_ name: String) -> Bool {
        return name.range(of: "\\[", options: .regularExpression) != nil ||
               name.range(of: "\\(", options: .regularExpression) != nil
    }
    
    // Remove all spaces from a game name for matching purposes.
    // Useful for matching games like "ShadowRun" vs "Shadow Run".
    static func removeSpaces(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "")
    }
    
    // Create a normalized comparison key for matching game names across different naming conventions.
    // Strips tags, removes spaces, and lowercases for maximum matching flexibility.
    static func normalizedComparisonKey(_ name: String) -> String {
        let stripped = stripTags(name)
        let noSpaces = removeSpaces(stripped)
        return noSpaces.lowercased()
    }
}

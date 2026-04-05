import Foundation

/// Utility for formatting and cleaning game display names.
/// Strips common ROM tags like region indicators, revision info, and other metadata
/// that appear in parentheses or square brackets in ROM filenames and database entries.
enum GameNameFormatter {
    
    // MARK: - Public API
    
    /// Strip all tags from a game name.
    /// Examples:
    ///   "Ecco the Dolphin (World)" → "Ecco the Dolphin"
    ///   "Super Mario Bros. (USA, Europe)" → "Super Mario Bros."
    ///   "Sonic the Hedgehog [!]" → "Sonic the Hedgehog"
    ///   "Mega Man 2 (Rev 1)" → "Mega Man 2"
    static func stripTags(_ name: String) -> String {
        var result = name
        
        // Step 1: Remove all content within square brackets [like this]
        result = removeBrackets(result)
        
        // Step 2: Remove all content within parentheses (like this)
        result = removeParentheses(result)
        
        // Step 3: Clean up whitespace
        result = cleanWhitespace(result)
        
        return result
    }
    
    /// Remove content within square brackets: [!], [b1], [f1], etc.
    static func removeBrackets(_ name: String) -> String {
        var result = name
        while let range = result.range(of: "\\s*\\[[^\\]]*\\]", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }
    
    /// Remove content within parentheses: (USA), (World), (Rev 1), (En,Fr,De), etc.
    static func removeParentheses(_ name: String) -> String {
        var result = name
        while let range = result.range(of: "\\s*\\([^\\)]*\\)", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }
    
    /// Clean up extra whitespace left after tag removal.
    static func cleanWhitespace(_ name: String) -> String {
        var result = name
        // Replace multiple spaces with single space
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        // Replace multiple dashes/spaces combinations
        result = result.replacingOccurrences(of: "\\s+-\\s+$", with: "", options: .regularExpression)
        // Trim and clean
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Check if a name contains any tags that would be stripped.
    static func hasTags(_ name: String) -> Bool {
        return name.range(of: "\\[", options: .regularExpression) != nil ||
               name.range(of: "\\(", options: .regularExpression) != nil
    }
    
    /// Remove all spaces from a game name for matching purposes.
    /// Useful for matching games like "ShadowRun" vs "Shadow Run".
    static func removeSpaces(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "")
    }
    
    /// Create a normalized comparison key for matching game names across different naming conventions.
    /// Strips tags, removes spaces, and lowercases for maximum matching flexibility.
    static func normalizedComparisonKey(_ name: String) -> String {
        let stripped = stripTags(name)
        let noSpaces = removeSpaces(stripped)
        return noSpaces.lowercased()
    }
}

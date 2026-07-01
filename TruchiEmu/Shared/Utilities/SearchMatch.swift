import Foundation

extension String {
    static let searchSeparators: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.invert()
        return set
    }()

    var searchTokens: [String] {
        unicodeScalars
            .split(whereSeparator: { !CharacterSet.alphanumerics.contains($0) })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    func fuzzyMatch(_ query: String) -> Bool {
        let lowerString = self.lowercased()
        let lowerQuery = query.lowercased()

        if lowerQuery.isEmpty { return true }
        if lowerString == lowerQuery { return true }

        var stringIndex = lowerString.startIndex
        var queryIndex = lowerQuery.startIndex
        while stringIndex < lowerString.endIndex && queryIndex < lowerQuery.endIndex {
            if lowerString[stringIndex] == lowerQuery[queryIndex] {
                queryIndex = lowerQuery.index(after: queryIndex)
            }
            stringIndex = lowerString.index(after: stringIndex)
        }
        return queryIndex == lowerQuery.endIndex
    }

    func tokenMatch(_ query: String) -> Bool {
        let hayTokens = self.searchTokens
        let qTokens = query.searchTokens
        if qTokens.isEmpty { return true }
        return qTokens.allSatisfy { needle in
            hayTokens.contains { $0 == needle || fuzzyMatchToken(haystack: $0, needle: needle) }
        }
    }

    private func fuzzyMatchToken(haystack: String, needle: String) -> Bool {
        if haystack.isEmpty { return false }
        if haystack.count < needle.count { return false }
        var hIdx = haystack.startIndex
        for c in needle {
            guard let found = haystack[hIdx...].firstIndex(of: c) else { return false }
            hIdx = haystack.index(after: found)
        }
        return true
    }
}

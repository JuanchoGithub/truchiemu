import SwiftUI

protocol SettingsSearchable {
    var searchText: String { get }
}

extension SettingsSearchable {
    var isSearching: Bool {
        !searchText.isEmpty
    }

    func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) ||
               keywords.localizedLowercase.contains(searchText.lowercased())
    }
}

import SwiftUI

protocol SettingsSearchable {
    associatedtype SectionID: Hashable

    var searchKeywordsBySection: [SectionID: [String]] { get }
    func matchesSearch(_ sectionID: SectionID) -> Bool
}

extension SettingsSearchable {
    func matchesSearch(_ sectionID: SectionID) -> Bool {
        matchesSearch(sectionID, query: "")
    }

    func matchesSearch(_ sectionID: SectionID, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        guard let kws = searchKeywordsBySection[sectionID] else { return false }
        return kws.contains { $0.localizedLowercase.fuzzyMatch(query) }
    }
}

extension View where Self: SettingsSearchable {
    var allSearchKeywords: [String] {
        searchKeywordsBySection.values.flatMap { $0 }
    }
}

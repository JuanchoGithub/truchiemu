import Foundation

struct SettingsSectionSearchProfile {
    let sectionTitle: String
    let optionTitles: [String]
    let descriptionFragments: [String]
    let keywords: [String]

    init(
        sectionTitle: String = "",
        optionTitles: [String] = [],
        descriptionFragments: [String] = [],
        keywords: [String] = []
    ) {
        self.sectionTitle = sectionTitle
        self.optionTitles = optionTitles
        self.descriptionFragments = descriptionFragments
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }

        func check(_ s: String) -> Bool {
            SettingsIndex.matches(haystack: s, query: q)
        }

        if !sectionTitle.isEmpty, check(sectionTitle) { return true }
        if optionTitles.contains(where: check) { return true }
        if descriptionFragments.contains(where: check) { return true }
        if keywords.contains(where: check) { return true }
        return false
    }
}

protocol SettingsSearchProfile {
    associatedtype SectionID: Hashable
    var searchProfileBySection: [SectionID: SettingsSectionSearchProfile] { get }
}

extension SettingsSearchProfile {
    func matchesSearch(_ sectionID: SectionID, query: String) -> Bool {
        guard let profile = searchProfileBySection[sectionID] else { return false }
        return profile.matches(query)
    }

    func hasMatch(query: String) -> Bool {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return searchProfileBySection.values.contains { $0.matches(query) }
    }
}

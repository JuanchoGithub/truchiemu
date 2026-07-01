import SwiftUI

@MainActor
enum SettingsSearchRuntime {
    @MainActor
    static func register(
        page: SettingsView.Page,
        sectionID: String,
        keywords: String,
        sectionTitle: String = "",
        optionTitles: [String] = [],
        descriptionFragments: [String] = []
    ) {
        SettingsIndex.shared.registerIfNeeded(
            page: page,
            sectionID: sectionID,
            keywords: keywords,
            sectionTitle: sectionTitle,
            optionTitles: optionTitles,
            descriptionFragments: descriptionFragments
        )
    }

    static func pageMatches(_ page: SettingsView.Page, query: String) -> Bool {
        SettingsIndex.shared.pageMatches(page, query: query)
    }
}

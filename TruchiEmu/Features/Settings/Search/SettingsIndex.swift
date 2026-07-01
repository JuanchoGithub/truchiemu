import Foundation

struct SettingsSearchHit: Identifiable, Hashable {
    enum Kind: Hashable {
        case page(SettingsView.Page)
        case section(page: SettingsView.Page, sectionID: String)
        case option(page: SettingsView.Page, sectionID: String, label: String)
        case description(page: SettingsView.Page, sectionID: String, label: String)
    }

    let id: String
    let kind: Kind
    let title: String
    let icon: String
    let breadcrumbs: [String]
    let matchedFragment: String
}

final class SettingsIndex {
    static let shared = SettingsIndex()

    private struct PageSection {
        let id: String
        let profile: SettingsSectionSearchProfile
    }

    private var sectionsByPage: [SettingsView.Page: [PageSection]] = [:]
    private var registeredKeys: Set<String> = []

    private init() {}

    static func matches(haystack: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let lower = haystack.lowercased()
        if lower.contains(q.lowercased()) { return true }
        if lower.fuzzyMatch(q) { return true }
        return haystack.tokenMatch(q)
    }

    @MainActor
    func registerIfNeeded(
        page: SettingsView.Page,
        sectionID: String,
        keywords: String,
        sectionTitle: String = "",
        optionTitles: [String] = [],
        descriptionFragments: [String] = []
    ) -> Bool {
        let key = "\(page.rawValue)::\(sectionID)"
        guard !registeredKeys.contains(key) else {
            if !optionTitles.isEmpty || !descriptionFragments.isEmpty || !keywords.isEmpty || !sectionTitle.isEmpty {
                mergeOptions(
                    page: page,
                    sectionID: sectionID,
                    sectionTitle: sectionTitle,
                    keywords: keywords,
                    optionTitles: optionTitles,
                    descriptionFragments: descriptionFragments
                )
            }
            return false
        }
        registeredKeys.insert(key)
        var entries: [String] = keywords.isEmpty
            ? []
            : keywords.split(separator: " ").map(String.init)
        if entries.isEmpty, !sectionTitle.isEmpty {
            entries = sectionTitle.lowercased().split(separator: " ").map(String.init)
        }
        let resolvedTitle: String = {
            if !sectionTitle.isEmpty { return sectionTitle }
            let words = keywords.split(separator: " ").prefix(4).map(String.init)
            return words.joined(separator: " ")
        }()
        register(
            page,
            sectionID: sectionID,
            profile: SettingsSectionSearchProfile(
                sectionTitle: resolvedTitle,
                optionTitles: optionTitles,
                descriptionFragments: descriptionFragments,
                keywords: entries
            )
        )
        return true
    }

    private func mergeOptions(
        page: SettingsView.Page,
        sectionID: String,
        sectionTitle: String,
        keywords: String,
        optionTitles: [String],
        descriptionFragments: [String]
    ) {
        guard var existing = sectionsByPage[page],
              let idx = existing.firstIndex(where: { $0.id == sectionID }) else { return }
        var profile = existing[idx].profile
        if !sectionTitle.isEmpty, profile.sectionTitle.isEmpty { profile = SettingsSectionSearchProfile(sectionTitle: sectionTitle, optionTitles: profile.optionTitles, descriptionFragments: profile.descriptionFragments, keywords: profile.keywords) }
        let mergedOptions = profile.optionTitles + optionTitles.filter { opt in !profile.optionTitles.contains(opt) }
        let mergedDescriptions = profile.descriptionFragments + descriptionFragments.filter { d in !profile.descriptionFragments.contains(d) }
        var mergedKeywords = profile.keywords
        if !keywords.isEmpty {
            let incoming = keywords.split(separator: " ").map(String.init)
            for kw in incoming where !mergedKeywords.contains(kw) {
                mergedKeywords.append(kw)
            }
        }
        existing[idx] = PageSection(
            id: sectionID,
            profile: SettingsSectionSearchProfile(
                sectionTitle: profile.sectionTitle,
                optionTitles: mergedOptions,
                descriptionFragments: mergedDescriptions,
                keywords: mergedKeywords
            )
        )
        sectionsByPage[page] = existing
    }

    func register(_ page: SettingsView.Page, sections: [(id: String, label: String, keywords: [String])]) {
        for s in sections {
            register(
                page,
                sectionID: s.id,
                profile: SettingsSectionSearchProfile(
                    sectionTitle: s.label,
                    keywords: s.keywords
                )
            )
        }
    }

    func register(_ page: SettingsView.Page, sectionID: String, profile: SettingsSectionSearchProfile) {
        var existing = sectionsByPage[page] ?? []
        if let idx = existing.firstIndex(where: { $0.id == sectionID }) {
            existing[idx] = PageSection(id: sectionID, profile: profile)
        } else {
            existing.append(PageSection(id: sectionID, profile: profile))
        }
        sectionsByPage[page] = existing
    }

    func keywords(for page: SettingsView.Page) -> [String] {
        let pageLevel = SettingsIndex.pageLevelKeywords(for: page)
        let sectionLevel = (sectionsByPage[page] ?? []).flatMap { section in
            [section.profile.sectionTitle] + section.profile.keywords
        }
        return pageLevel + sectionLevel
    }

    private func sections(for page: SettingsView.Page) -> [PageSection] {
        sectionsByPage[page] ?? []
    }

    private func matchingSections(for page: SettingsView.Page, query: String) -> [PageSection] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Array(sectionsByPage[page] ?? []) }
        return (sectionsByPage[page] ?? []).filter { sect in
            let profile = sect.profile
            if SettingsIndex.matches(haystack: profile.sectionTitle, query: query) { return true }
            if profile.keywords.contains(where: { SettingsIndex.matches(haystack: $0, query: query) }) { return true }
            if profile.optionTitles.contains(where: { SettingsIndex.matches(haystack: $0, query: query) }) { return true }
            if profile.descriptionFragments.contains(where: { SettingsIndex.matches(haystack: $0, query: query) }) { return true }
            return false
        }
    }

    func search(_ query: String) -> [SettingsSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed
        var hits: [SettingsSearchHit] = []

        var sectionHitsByPage: [SettingsView.Page: [SettingsSearchHit]] = [:]

        for page in SettingsView.allPages {
            var pageSectionHits: [SettingsSearchHit] = []

            for sect in self.matchingSections(for: page, query: q) {
                let label = sect.profile.sectionTitle.isEmpty ? sect.id : sect.profile.sectionTitle
                let matchedFragment: String = {
                    if SettingsIndex.matches(haystack: sect.profile.sectionTitle, query: q) {
                        return sect.profile.sectionTitle
                    }
                    if let kw = sect.profile.keywords.first(where: { SettingsIndex.matches(haystack: $0, query: q) }) {
                        return kw
                    }
                    if let opt = sect.profile.optionTitles.first(where: { SettingsIndex.matches(haystack: $0, query: q) }) {
                        return opt
                    }
                    if let desc = sect.profile.descriptionFragments.first(where: { SettingsIndex.matches(haystack: $0, query: q) }) {
                        return desc
                    }
                    return label
                }()

                pageSectionHits.append(SettingsSearchHit(
                    id: "section-\(page.rawValue)-\(sect.id)",
                    kind: .section(page: page, sectionID: sect.id),
                    title: label,
                    icon: page.icon,
                    breadcrumbs: [page.label, label],
                    matchedFragment: matchedFragment
                ))

                for option in sect.profile.optionTitles {
                    if SettingsIndex.matches(haystack: option, query: q) {
                        pageSectionHits.append(SettingsSearchHit(
                            id: "option-\(page.rawValue)-\(sect.id)-\(option)",
                            kind: .option(page: page, sectionID: sect.id, label: option),
                            title: option,
                            icon: page.icon,
                            breadcrumbs: [page.label, label, option],
                            matchedFragment: option
                        ))
                    }
                }

                for desc in sect.profile.descriptionFragments {
                    if SettingsIndex.matches(haystack: desc, query: q) {
                        pageSectionHits.append(SettingsSearchHit(
                            id: "desc-\(page.rawValue)-\(sect.id)-\(desc.prefix(40))",
                            kind: .description(page: page, sectionID: sect.id, label: desc),
                            title: String(desc.prefix(80)),
                            icon: page.icon,
                            breadcrumbs: [page.label, label],
                            matchedFragment: desc
                        ))
                    }
                }
            }

            sectionHitsByPage[page] = pageSectionHits

            if !pageSectionHits.isEmpty {
                hits.append(contentsOf: pageSectionHits)
            } else {
                let pageKeywords = SettingsIndex.pageLevelKeywords(for: page)
                let sidebarMatch = SettingsIndex.matches(haystack: page.label, query: q) ||
                    pageKeywords.contains { SettingsIndex.matches(haystack: $0, query: q) }
                if sidebarMatch {
                    hits.append(SettingsSearchHit(
                        id: "page-\(page.rawValue)",
                        kind: .page(page),
                        title: page.label,
                        icon: page.icon,
                        breadcrumbs: [page.label],
                        matchedFragment: page.label
                    ))
                }
            }
        }

        return hits
    }

    func matchingSidebarPages(for query: String) -> [SettingsView.Page] {
        guard !query.isEmpty else { return SettingsView.allPages }
        return SettingsView.allPages.filter { page in
            SettingsIndex.matches(haystack: page.label, query: query) ||
            SettingsIndex.pageLevelKeywords(for: page).contains { SettingsIndex.matches(haystack: $0, query: query) }
        }
    }

    static func pageLevelKeywords(for page: SettingsView.Page) -> [String] {
        page.searchKeywords.split(separator: " ").map(String.init)
    }

    @MainActor
    func pageMatches(_ page: SettingsView.Page, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if SettingsIndex.matches(haystack: page.label, query: q) { return true }
        return SettingsIndex.pageLevelKeywords(for: page).contains {
            SettingsIndex.matches(haystack: $0, query: q)
        }
    }

    @MainActor
    func sectionMatches(page: SettingsView.Page, sectionID: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if SettingsIndex.matches(haystack: page.label, query: q) { return true }
        if SettingsIndex.pageLevelKeywords(for: page).contains(where: { SettingsIndex.matches(haystack: $0, query: q) }) {
            return true
        }
        guard let profile = (sectionsByPage[page] ?? []).first(where: { $0.id == sectionID })?.profile else { return false }
        return SettingsIndex.matches(haystack: profile.sectionTitle, query: q)
            || profile.optionTitles.contains(where: { SettingsIndex.matches(haystack: $0, query: q) })
            || profile.descriptionFragments.contains(where: { SettingsIndex.matches(haystack: $0, query: q) })
            || profile.keywords.contains(where: { SettingsIndex.matches(haystack: $0, query: q) })
    }
}

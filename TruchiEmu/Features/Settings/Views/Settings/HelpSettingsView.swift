import SwiftUI

struct HelpSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.help, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if (!isSearching || matchesSearch("faq questions frequent help how")) && sectionVisible("section-faq") {
                    Section {
                        ForEach(HelpContent.faqItems) { item in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    Text(loc.localized(item.answerKey))
                                        .font(.callout)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let linkLabelKey = item.linkLabelKey, let page = item.deepLinkPage {
                                        Button {
                                            openSettingsPage(page)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: page.icon)
                                                    .font(.system(size: 11, weight: .medium))
                                                Text(loc.localized(linkLabelKey))
                                                    .font(.callout.weight(.medium))
                                                Image(systemName: "arrow.right.circle")
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundStyle(AppColors.brandAccent)
                                            .padding(.vertical, 3)
                                            .padding(.horizontal, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: AppRadius.lg)
                                                    .fill(AppColors.accentBackground(colorScheme))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: AppRadius.lg)
                                                    .stroke(AppColors.brandAccent.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, AppSpacing.xxs)
                            } label: {
                                Text(loc.localized(item.questionKey))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                            }
                        }
                    } header: {
                        Label { Text(loc.localized("help.faq")) } icon: { Image(systemName: "questionmark.circle") }
                    }
                    .id("section-faq")
                }

                if (!isSearching || matchesSearch("resources links documentation troubleshooting github")) && sectionVisible("section-resources") {
                    Section {
                        helpLinkRow(icon: "book", titleKey: "help.link.documentation", url: HelpContent.docURL(""))
                        helpLinkRow(icon: "play.circle", titleKey: "help.link.gettingStarted", url: HelpContent.docURL("getting-started"))
                        helpLinkRow(icon: "wrench.and.screwdriver", titleKey: "help.link.troubleshooting", url: HelpContent.docURL("troubleshooting"))
                        helpLinkRow(icon: "gamecontroller", titleKey: "help.link.supportedSystems", url: HelpContent.docURL("systems"))
                        helpLinkRow(icon: "chevron.left.forwardslash.chevron.right", titleKey: "help.link.github", url: URL(string: "https://github.com/JuanchoGithub/truchiemu")!)
                        helpLinkRow(icon: "exclamationmark.bubble", titleKey: "help.link.reportIssue", url: URL(string: "https://github.com/JuanchoGithub/truchiemu/issues")!)
                    } header: {
                        Label { Text(loc.localized("help.resources")) } icon: { Image(systemName: "link") }
                    }
                    .id("section-resources")
                }

                if isSearching && !hasMatchingSections {
                    Section {
                        Text(loc.localized("help.noMatchingSettings") + " \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppSpacing.xl2)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .formStyle(.grouped)
            .onChange(of: focusedSectionID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
            }
        }
        .navigationTitle(loc.localized("help.title"))
    }

    private var hasMatchingSections: Bool {
        matchesSearch("faq questions frequent help how") ||
        matchesSearch("resources links documentation troubleshooting github")
    }

    private func helpLinkRow(icon: String, titleKey: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(width: 20)
                Text(loc.localized(titleKey))
                    .font(.callout)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
    }

    private func openSettingsPage(_ page: SettingsView.Page) {
        AppSettings.set("pending_settings_page", value: page.rawValue)
        NotificationCenter.default.post(name: .openAppSettings, object: nil)
    }
}

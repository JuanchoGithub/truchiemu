import SwiftUI

struct HelpSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @Binding var searchText: String

    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) ||
            keywords.localizedLowercase.contains(searchText.lowercased())
    }

    var body: some View {
        Form {
            if !isSearching || matchesSearch("faq questions frequent help how") {
                Section {
                    ForEach(HelpContent.faqItems) { item in
                        DisclosureGroup {
                            Text(loc.localized(item.answerKey))
                                .font(.callout)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
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
            }

            if !isSearching || matchesSearch("resources links documentation troubleshooting github") {
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
}

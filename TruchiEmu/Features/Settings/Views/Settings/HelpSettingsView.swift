import SwiftUI

struct HelpSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var expandedFAQ: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl3) {
                keyboardShortcutsSection
                faqSection
                resourcesSection
            }
            .padding(AppSpacing.xl3)
        }
    }

    private var keyboardShortcutsSection: some View {
        SettingsSectionCard(loc.localized("help.shortcuts"), icon: "keyboard") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(HelpContent.keyboardShortcuts) { shortcut in
                    HStack {
                        HStack(spacing: 4) {
                            ForEach(shortcut.modifiers, id: \.self) { mod in
                                Text(verbatim: mod)
                                    .font(.caption.monospaced().weight(.medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(verbatim: shortcut.key)
                                .font(.caption.monospaced().weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppColors.cardBackgroundSubtle(colorScheme))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(width: 140, alignment: .leading)

                        Text(loc.localized(shortcut.descriptionKey))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))

                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
            }
        }
    }

    private var faqSection: some View {
        SettingsSectionCard(loc.localized("help.faq"), icon: "questionmark.circle") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(HelpContent.faqItems) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedFAQ.contains(item.id) {
                                expandedFAQ.remove(item.id)
                            } else {
                                expandedFAQ.insert(item.id)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: expandedFAQ.contains(item.id) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .frame(width: AppSpacing.xl)
                            Text(loc.localized(item.questionKey))
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppColors.textPrimary(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expandedFAQ.contains(item.id) {
                        Text(loc.localized(item.answerKey))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, AppSpacing.xl2)
                            .padding(.bottom, AppSpacing.xs)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private var resourcesSection: some View {
        SettingsSectionCard(loc.localized("help.resources"), icon: "link") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                helpLinkRow(icon: "book", titleKey: "help.link.documentation", url: HelpContent.docURL(""))
                helpLinkRow(icon: "play.circle", titleKey: "help.link.gettingStarted", url: HelpContent.docURL("getting-started"))
                helpLinkRow(icon: "wrench.and.screwdriver", titleKey: "help.link.troubleshooting", url: HelpContent.docURL("troubleshooting"))
                helpLinkRow(icon: "gamecontroller", titleKey: "help.link.supportedSystems", url: HelpContent.docURL("systems"))
                helpLinkRow(icon: "chevron.left.forwardslash.chevron.right", titleKey: "help.link.github", url: URL(string: "https://github.com/JuanchoGithub/truchiemu")!)
                helpLinkRow(icon: "exclamationmark.bubble", titleKey: "help.link.reportIssue", url: URL(string: "https://github.com/JuanchoGithub/truchiemu/issues")!)
            }
        }
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

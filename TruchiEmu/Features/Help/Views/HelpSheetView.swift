import SwiftUI

struct HelpSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedSection: HelpWindowView.HelpSection = .quickStart

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl3) {
                    switch selectedSection {
                    case .shortcuts: shortcutsSection
                    case .faq: faqSection
                    case .quickStart: quickStartSection
                    case .links: linksSection
                    }
                }
                .padding(AppSpacing.xl3)
            }
        }
        .frame(minWidth: 560, minHeight: 440, maxHeight: 600)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .background {
            Button("") { dismiss() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(HelpWindowView.HelpSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(section.label(loc: loc))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .fill(selectedSection == section ? AppColors.accentBackground(colorScheme) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .stroke(selectedSection == section ? AppColors.brandAccent.opacity(0.3) : AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
                    .foregroundStyle(selectedSection == section ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl3)
        .padding(.vertical, AppSpacing.lg)
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("help.shortcuts")
                .font(AppTypography.headingLarge)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(HelpContent.keyboardShortcuts) { shortcut in
                    HStack {
                        HStack(spacing: 4) {
                            ForEach(shortcut.modifiers, id: \.self) { mod in
                                Text(mod)
                                    .font(.caption.monospaced().weight(.medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(shortcut.key)
                                .font(.caption.monospaced().weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppColors.cardBackgroundSubtle(colorScheme))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(width: 140, alignment: .leading)

                        Text(loc.localized(shortcut.descriptionKey))
                            .font(.body)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))

                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("help.faq")
                .font(AppTypography.headingLarge)

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ForEach(HelpContent.faqItems) { item in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(loc.localized(item.questionKey))
                            .font(.body.weight(.semibold))
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
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
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
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    )
                }
            }
        }
    }

    private func openSettingsPage(_ page: SettingsView.Page) {
        AppSettings.set("pending_settings_page", value: page.rawValue)
        NotificationCenter.default.post(name: .openAppSettings, object: nil)
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("help.quickStart")
                .font(AppTypography.headingLarge)

            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                quickStartStep(number: 1, key: "help.quickStart.addROMs")
                quickStartStep(number: 2, key: "help.quickStart.downloadCore")
                quickStartStep(number: 3, key: "help.quickStart.launchGame")
                quickStartStep(number: 4, key: "help.quickStart.customize")
            }

            Link(destination: HelpContent.docURL("getting-started")) {
                Label(loc.localized("help.viewFullGuide"), systemImage: "book")
                    .font(.callout)
            }
        }
    }

    private func quickStartStep(number: Int, key: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            Text(verbatim: "\(number)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(AppColors.brandAccent)
                .frame(width: 30)

            Text(loc.localized(key))
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("help.links")
                .font(AppTypography.headingLarge)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                helpLink(icon: "book", titleKey: "help.link.documentation", url: HelpContent.docURL(""))
                helpLink(icon: "play.circle", titleKey: "help.link.gettingStarted", url: HelpContent.docURL("getting-started"))
                helpLink(icon: "wrench.and.screwdriver", titleKey: "help.link.troubleshooting", url: HelpContent.docURL("troubleshooting"))
                helpLink(icon: "gamecontroller", titleKey: "help.link.supportedSystems", url: HelpContent.docURL("systems"))
                helpLink(icon: "chevron.left.forwardslash.chevron.right", titleKey: "help.link.github", url: URL(string: "https://github.com/JuanchoGithub/truchiemu")!)
                helpLink(icon: "exclamationmark.bubble", titleKey: "help.link.reportIssue", url: URL(string: "https://github.com/JuanchoGithub/truchiemu/issues")!)
            }
        }
    }

    private func helpLink(icon: String, titleKey: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(width: 24)
                Text(loc.localized(titleKey))
                    .font(.body)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
            )
        }
    }
}

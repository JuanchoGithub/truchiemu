import SwiftUI

struct HelpWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedSection: HelpSection = .shortcuts

    enum HelpSection: String, CaseIterable, Identifiable {
        case shortcuts, faq, quickStart, links

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .shortcuts: return "keyboard"
            case .faq: return "questionmark.circle"
            case .quickStart: return "bolt.fill"
            case .links: return "link"
            }
        }

        func label(loc: LocalizationManager) -> String {
            switch self {
            case .shortcuts: return loc.localized("help.shortcuts")
            case .faq: return loc.localized("help.faq")
            case .quickStart: return loc.localized("help.quickStart")
            case .links: return loc.localized("help.links")
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1)
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(HelpSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20)
                                .fixedSize()
                                .foregroundColor(selectedSection == section ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                            Text(section.label(loc: loc))
                                .font(AppTypography.callout)
                                .foregroundColor(selectedSection == section ? AppColors.textPrimary(colorScheme) : AppColors.textSecondary(colorScheme))
                                .fontWeight(selectedSection == section ? .medium : .regular)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedSection == section ? AppColors.accentBackground(colorScheme) : .clear)
                        )
                        .overlay(alignment: .leading) {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.brandAccentSecondary)
                                    .frame(width: 3, height: 20)
                                    .padding(.leading, 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.sidebarBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .frame(width: 200)
    }

    @ViewBuilder
    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl3) {
                switch selectedSection {
                case .shortcuts:
                    shortcutsSection
                case .faq:
                    faqSection
                case .quickStart:
                    quickStartSection
                case .links:
                    linksSection
                }
            }
            .padding(AppSpacing.xl3)
        }
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
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loc.localized(item.questionKey))
                            .font(.body.weight(.semibold))
                        Text(loc.localized(item.answerKey))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
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

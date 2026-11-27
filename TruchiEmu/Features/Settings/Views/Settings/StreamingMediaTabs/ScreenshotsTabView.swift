import SwiftUI

struct ScreenshotsTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String

    @State private var customPath: String = ""
    @State private var showFolderPicker = false

    var body: some View {
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        if !isSearching {
                            statPillsRow
                        }

                        settingsCard(
                            id: "section-screenshotHotkey",
                            title: loc.localized("settings.media.hotkey.screenshotSection"),
                            icon: "keyboard",
                            keywords: "screenshot hotkey"
                        ) {
                            screenshotHotkeySectionContent
                        }

                        settingsCard(
                            id: "section-screenshotIncludeNative",
                            title: loc.localized("screenshot.section"),
                            icon: "camera",
                            keywords: "screenshot include native"
                        ) {
                            screenshotIncludeNativeSectionContent
                        }

                        settingsCard(
                            id: "section-screenshotPath",
                            title: loc.localized("settings.media.screenshotPath"),
                            icon: "folder",
                            keywords: "screenshot output path folder"
                        ) {
                            screenshotPathSectionContent
                        }

                        if isSearching && !hasAnyResults {
                            noResultsView
                        }

                        Spacer(minLength: AppSpacing.xl5)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.streaming, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                Text(title)
                    .font(AppTypography.headingSmall)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
            }
            content()
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
        .cardHoverEffect(colorScheme: colorScheme)
        .id(id)
    }

    // MARK: - Stat Pills

    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            SettingsStatPill(item: .init(
                id: "screenshotSettings",
                number: "3",
                label: "sections",
                icon: "camera"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Section Content

    private var screenshotHotkeySectionContent: some View {
        Group {
            MediaHotkeyBindingRow(action: .screenshot, sectionKey: "settings.media.hotkey.screenshotSection")
            Text(loc.localized("settings.media.hotkey.editInHotkeys"))
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }

    private var screenshotIncludeNativeSectionContent: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("screenshot.includeNative")
                        .lineLimit(1)
                    Text("screenshot.includeNativeHelp")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { config.screenshot.includeNative },
                    set: { config.screenshot.includeNative = $0; config.screenshot.save() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(.vertical, AppSpacing.xxs)
        }
    }

    private var screenshotPathSectionContent: some View {
        Group {
            HStack(spacing: 8) {
                Text(verbatim: displayPath)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsActionButton(loc.localized("settings.streaming.browse")) {
                    showFolderPicker = true
                }
                if config.screenshot.hasCustomPath {
                    SettingsActionButton(loc.localized("settings.media.reset")) {
                        config.screenshot.outputPath = ""
                        config.screenshot.save()
                        customPath = ""
                    }
                }
            }
            .folderDialog(
                isPresented: $showFolderPicker,
                path: $customPath,
                prompt: "Choose a folder for screenshots"
            )
            .onChange(of: customPath) { _, newValue in
                config.screenshot.outputPath = newValue
                config.screenshot.save()
            }
            Text(loc.localized("settings.media.screenshotPathDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    // MARK: - Helpers

    private var displayPath: String {
        config.screenshot.outputPath.isEmpty
            ? loc.localized("settings.media.defaultPath")
            : config.screenshot.outputPath
    }

    private var hasAnyResults: Bool {
        true
    }

    private var noResultsView: some View {
        VStack {
            Text("\(loc.localized("general.noMatchingSettings")) \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
    }
}

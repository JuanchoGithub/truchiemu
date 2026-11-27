import SwiftUI

struct SharingTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String

    @State private var customDurationText: String = "60"

    var body: some View {
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        if !isSearching {
                            statPillsRow
                        }

                        settingsCard(
                            id: "section-shareButton",
                            title: loc.localized("media.shareButton"),
                            icon: "shareplay",
                            keywords: "share button single press long press behavior"
                        ) {
                            shareButtonSectionContent
                        }

                        settingsCard(
                            id: "section-saveLastMoments",
                            title: loc.localized("media.saveLastMoments"),
                            icon: "clock.arrow.circlepath",
                            keywords: "save last moments clip buffer retro game clip rolling buffer"
                        ) {
                            saveLastMomentsSectionContent
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
            .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
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
                id: "shareBehaviors",
                number: "\(ShareBehavior.allCases.count)",
                label: "behaviors",
                icon: "shareplay"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Section Content

    private var shareButtonSectionContent: some View {
        Group {
            MediaHotkeyBindingRow(action: .shareButton, sectionKey: "settings.media.hotkey.shareSection")
            Text(loc.localized("settings.media.hotkey.editInHotkeys"))
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary(colorScheme))

            Picker(loc.localized("media.shareSinglePress"), selection: Binding(
                get: { config.share.singlePress },
                set: {
                    config.share.singlePress = $0
                    config.share.save()
                }
            )) {
                ForEach(shareBehaviors) { behavior in
                    Text(loc.localized(behavior.localizationKey)).tag(behavior)
                }
            }

            Picker(loc.localized("media.shareLongPress"), selection: Binding(
                get: { config.share.longPress },
                set: {
                    config.share.longPress = $0
                    config.share.save()
                }
            )) {
                ForEach(shareBehaviors) { behavior in
                    Text(loc.localized(behavior.localizationKey)).tag(behavior)
                }
            }

            Text(String(format: loc.localized("media.shareDescription"),
                        loc.localized(config.share.singlePress.localizationKey),
                        loc.localized(config.share.longPress.localizationKey)))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    private var saveLastMomentsSectionContent: some View {
        Group {
            if config.rollingBuffer.enabled {
                Picker(loc.localized("media.saveLastMomentsDuration"), selection: Binding(
                    get: { config.rollingBuffer.duration },
                    set: { newValue in
                        config.rollingBuffer.duration = newValue
                        config.rollingBuffer.save()
                        RollingVideoBufferService.shared.duration = newValue.actualDuration
                    }
                )) {
                    ForEach(RollingBufferDuration.allCases) { dur in
                        Text(dur.localizationKey).tag(dur)
                    }
                }

                if config.rollingBuffer.duration == .custom {
                    HStack {
                        Text(loc.localized("media.saveLastMoments.customSeconds"))
                        Spacer()
                        TextField("", text: $customDurationText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .frame(width: 80)
                            .onSubmit {
                                if let val = Double(customDurationText), val > 0, val <= RollingBufferDuration.maxCustomDuration {
                                    RollingVideoBufferService.shared.duration = val
                                }
                            }
                    }
                }

                Text(String(format: loc.localized("media.saveLastMomentsEstimate"),
                            String(format: "%.0f", config.rollingBuffer.estimatedFileSizeMB()),
                            String(format: "%.0f", config.rollingBuffer.estimatedFileSizeMB() / (config.rollingBuffer.effectiveSeconds / 60.0))))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))

                Toggle(loc.localized("media.saveLastMomentsDisplayRes"), isOn: Binding(
                    get: { config.rollingBuffer.recordDisplayResolution },
                    set: { newValue in
                        config.rollingBuffer.recordDisplayResolution = newValue
                        config.rollingBuffer.save()
                        RollingVideoBufferService.shared.recordDisplayResolution = newValue
                    }
                ))
            }

            if !config.rollingBuffer.enabled {
                Text(loc.localized("settings.media.rolling.disabledHint"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
        }
    }

    // MARK: - Helpers

    private var hasAnyResults: Bool {
        matchesSearch("share button single press long press behavior")
        || matchesSearch("save last moments clip buffer retro game clip rolling buffer")
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

    private var shareBehaviors: [ShareBehavior] {
        ShareBehavior.allCases
    }
}

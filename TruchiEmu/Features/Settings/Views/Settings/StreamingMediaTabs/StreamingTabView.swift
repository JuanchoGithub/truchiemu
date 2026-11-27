import SwiftUI

struct StreamingTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String
    @Binding var scopedSectionID: String?

    @State private var twitchKey: String = ""
    @State private var youtubeKey: String = ""
    @State private var customName: String = ""
    @State private var customKey: String = ""
    @State private var customURL: String = ""
    @State private var twitchURL: String = ""
    @State private var youtubeURL: String = ""

    @State private var twitchVerifyResult: VerifyState = .idle
    @State private var youtubeVerifyResult: VerifyState = .idle
    @State private var customVerifyResult: VerifyState = .idle

    init(config: Binding<MediaConfig>,
         searchText: Binding<String>,
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._config = config
        self._searchText = searchText
        self._scopedSectionID = scopedSectionID
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "") || scope == "tabStreaming"
    }

    var body: some View {
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        settingsCard(
                            id: "section-streamingEnable",
                            title: loc.localized("settings.streaming.enable"),
                            icon: "antenna.radiowaves.left.and.right",
                            keywords: "streaming enable"
                        ) {
                            Toggle(loc.localized("settings.streaming.enable"), isOn: Binding(
                                get: { config.streaming.enabled },
                                set: { config.streaming.enabled = $0; config.streaming.save() }
                            ))
                            Text(loc.localized("settings.streaming.enableDescription"))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        if config.streaming.enabled {
                            settingsCard(
                                id: "section-streamingResolution",
                                title: loc.localized("settings.streaming.resolution"),
                                icon: "rectangle.expand.vertical",
                                keywords: "streaming resolution"
                            ) {
                                Picker(loc.localized("settings.streaming.resolution"), selection: Binding(
                                    get: { config.streaming.resolution },
                                    set: { config.streaming.resolution = $0; config.streaming.save() }
                                )) {
                                    ForEach(StreamResolution.allCases) { res in
                                        Text(loc.localized(res.localizationKey)).tag(res)
                                    }
                                }
                            }

                            settingsCard(
                                id: "section-recordWithShaders",
                                title: loc.localized("settings.streaming.recordWithShaders"),
                                icon: "tv",
                                keywords: "record with shaders"
                            ) {
                                Toggle(loc.localized("settings.streaming.recordWithShaders"), isOn: Binding(
                                    get: { config.streaming.recordWithShaders },
                                    set: { config.streaming.recordWithShaders = $0; config.streaming.save() }
                                ))
                                Text(loc.localized("settings.streaming.recordWithShadersDescription"))
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }

                            settingsCard(
                                id: "section-destinations",
                                title: loc.localized("settings.streaming.destinations"),
                                icon: "network",
                                keywords: "streaming destinations twitch youtube custom"
                            ) {
                                destinationsGroupContent
                            }
                        } else {
                            settingsCard(
                                id: "section-streamingOff",
                                title: loc.localized("settings.media.streamingOff.summary"),
                                icon: "info.circle",
                                keywords: "streaming off disabled"
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.caption)
                                        Text(loc.localized("settings.media.destinations.configured"))
                                            .font(.caption)
                                        Text(verbatim: "\(config.destinations.configuredCount)/3")
                                            .font(.caption).bold()
                                    }
                                }
                            }
                        }

                        settingsCard(
                            id: "section-streamingBadge",
                            title: loc.localized("media.streamingBadge"),
                            icon: "circlebadge",
                            keywords: "streaming badge position"
                        ) {
                            streamingBadgeSectionContent
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
        .onAppear {
            let destinations = config.destinations
            twitchKey = destinations.twitchKey
            youtubeKey = destinations.youtubeKey
            twitchURL = destinations.twitchURL
            youtubeURL = destinations.youtubeURL
            customName = destinations.customName
            customKey = destinations.customKey
            customURL = destinations.customURL
        }
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
        if sectionVisible(id) {
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
    }

    // MARK: - Section Content

    private var destinationsGroupContent: some View {
        Group {
            Section {
                TwitchSection(
                    key: $twitchKey, url: $twitchURL, verifyResult: $twitchVerifyResult,
                    onKeyChange: { config.destinations.twitchKey = twitchKey; config.destinations.save() },
                    onURLChange: {
                        config.destinations.twitchURL = twitchURL.isEmpty ? StreamRecordingService.defaultTwitchURL : twitchURL
                        config.destinations.save()
                    }
                )
            }

            Section {
                YouTubeSection(
                    key: $youtubeKey, url: $youtubeURL, verifyResult: $youtubeVerifyResult,
                    onKeyChange: { config.destinations.youtubeKey = youtubeKey; config.destinations.save() },
                    onURLChange: {
                        config.destinations.youtubeURL = youtubeURL.isEmpty ? StreamRecordingService.defaultYoutubeURL : youtubeURL
                        config.destinations.save()
                    }
                )
            }

            Section {
                CustomStreamSection(
                    name: $customName, key: $customKey, url: $customURL, verifyResult: $customVerifyResult,
                    onNameChange: {
                        config.destinations.customName = customName.isEmpty ? "Custom" : customName
                        config.destinations.save()
                    },
                    onKeyChange: { config.destinations.customKey = customKey; config.destinations.save() },
                    onURLChange: { config.destinations.customURL = customURL; config.destinations.save() }
                )
            }
        }
    }

    private var streamingBadgeSectionContent: some View {
        Group {
            Toggle(loc.localized("media.streamingBadgeEnable"), isOn: Binding(
                get: { config.streamingBadge.enabled },
                set: { config.streamingBadge.enabled = $0; config.streamingBadge.save(keyPrefix: "streaming_badge") }
            ))
            if config.streamingBadge.enabled {
                Picker(loc.localized("media.streamingBadgePosition"), selection: Binding(
                    get: { config.streamingBadge.position },
                    set: { config.streamingBadge.position = $0; config.streamingBadge.save(keyPrefix: "streaming_badge") }
                )) {
                    ForEach(BadgePosition.allCases, id: \.rawValue) { pos in
                        Text(loc.localized(pos.localizationKey)).tag(pos)
                    }
                }
            }
        }
    }
}

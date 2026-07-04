import SwiftUI

struct StreamingTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
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
        Form {
            if sectionVisible("section-streamingEnable") {
                Section {
                    Toggle(loc.localized("settings.streaming.enable"), isOn: Binding(
                        get: { config.streaming.enabled },
                        set: { config.streaming.enabled = $0; config.streaming.save() }
                    ))
                    Text(loc.localized("settings.streaming.enableDescription"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                } header: {
                    Label(loc.localized("settings.streaming.enable"), systemImage: "antenna.radiowaves.left.and.right")
                }
                .id("section-streamingEnable")
            }

            if config.streaming.enabled {
                if sectionVisible("section-recordWithShaders") {
                    recordWithShadersSection
                }
                if sectionVisible("section-destinations") {
                    destinationsGroup
                }
            } else {
                if sectionVisible("section-streamingOff") {
                    streamingOffSummary
                }
            }

            if sectionVisible("section-streamingBadge") {
                streamingBadgeSection
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
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

    private var recordWithShadersSection: some View {
        Section {
            Toggle(loc.localized("settings.streaming.recordWithShaders"), isOn: Binding(
                get: { config.streaming.recordWithShaders },
                set: { config.streaming.recordWithShaders = $0; config.streaming.save() }
            ))
            Text(loc.localized("settings.streaming.recordWithShadersDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .id("section-recordWithShaders")
    }

    private var destinationsGroup: some View {
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
            } header: {
                Label("Twitch", systemImage: "antenna.radiowaves.left.and.right")
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
            } header: {
                Label("YouTube", systemImage: "video.badge.checkmark")
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
            } header: {
                Label(loc.localized("settings.streaming.customStream"), systemImage: "network")
            }
        }
    }

    private var streamingOffSummary: some View {
        Section {
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
        } header: {
            Label(loc.localized("settings.media.streamingOff.summary"), systemImage: "info.circle")
        }
    }

    private var streamingBadgeSection: some View {
        Section {
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
        } header: {
            Label(loc.localized("media.streamingBadge"), systemImage: "circlebadge")
        }
        .id("section-streamingBadge")
    }
}

import SwiftUI

struct SharingTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String

    @State private var customDurationText: String = "60"

    var body: some View {
        Form {
            if !isSearching || matchesSearch("share button single press long press behavior") {
                shareButtonSection
            }

            if !isSearching || matchesSearch("save last moments clip buffer retro game clip rolling buffer") {
                saveLastMomentsSection
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .onAppear {
            customDurationText = String(Int(config.rollingBuffer.customSeconds))
        }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.streaming, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private var shareBehaviors: [ShareBehavior] {
        ShareBehavior.allCases
    }

    private var shareButtonSection: some View {
        Section {
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
        } header: {
            Label(loc.localized("media.shareButton"), systemImage: "shareplay")
        }
    }

    private var saveLastMomentsSection: some View {
        Section {
            Toggle(loc.localized("media.saveLastMomentsEnable"), isOn: Binding(
                get: { config.rollingBuffer.enabled },
                set: { newValue in
                    config.rollingBuffer.enabled = newValue
                    config.rollingBuffer.save()
                    RollingVideoBufferService.shared.isEnabled = newValue
                    if !newValue {
                        if config.share.singlePress == .saveLastXSeconds {
                            config.share.singlePress = .none
                        }
                        if config.share.longPress == .saveLastXSeconds {
                            config.share.longPress = .none
                        }
                        config.share.save()
                    }
                }
            ))

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
        } header: {
            Label(loc.localized("media.saveLastMoments"), systemImage: "clock.arrow.circlepath")
        } footer: {
            if !config.rollingBuffer.enabled {
                Text(loc.localized("settings.media.rolling.disabledHint"))
            }
        }
    }
}

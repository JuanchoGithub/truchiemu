import SwiftUI

struct RecordingTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String
    @Binding var scopedSectionID: String?

    @State private var outputPath: String = ""
    @State private var showFolderPicker = false
    @State private var qualityExpanded: Bool = false
    @State private var recordingEnabled: Bool = AppSettings.getBool("recording_local_enabled", defaultValue: true)

    init(config: Binding<MediaConfig>,
         searchText: Binding<String>,
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._config = config
        self._searchText = searchText
        self._scopedSectionID = scopedSectionID
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "") || scope == "tabRecording"
    }

    var body: some View {
        Group {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        if !searchText.isEmpty {
                            // No stat pills for recording tab
                        }

                        settingsCard(
                            id: "section-recordingEnable",
                            title: loc.localized("settings.media.recording.enable"),
                            icon: "record.circle",
                            keywords: "recording enable local"
                        ) {
                            Toggle(loc.localized("settings.media.recording.enable"), isOn: Binding(
                                get: { recordingEnabled },
                                set: { newValue in
                                    recordingEnabled = newValue
                                    AppSettings.setBool("recording_local_enabled", value: newValue)
                                }
                            ))
                            Text(loc.localized("settings.media.recording.enableDescription"))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        settingsCard(
                            id: "section-recordingHotkey",
                            title: loc.localized("settings.media.hotkey.recordingSection"),
                            icon: "keyboard",
                            keywords: "recording hotkey"
                        ) {
                            MediaHotkeyBindingRow(action: .recording, sectionKey: "settings.media.hotkey.recordingSection")
                            Text(loc.localized("settings.media.hotkey.editInHotkeys"))
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        if recordingEnabled {
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
                                id: "section-qualitySection",
                                title: loc.localized("settings.streaming.localQuality"),
                                icon: "slider.horizontal.3",
                                keywords: "recording quality video codec bitrate audio frame rate"
                            ) {
                                qualitySectionContent
                            }

                            settingsCard(
                                id: "section-outputPath",
                                title: loc.localized("settings.streaming.outputPath"),
                                icon: "folder",
                                keywords: "recording output path folder"
                            ) {
                                outputPathSectionContent
                            }
                        } else {
                            settingsCard(
                                id: "section-recordingOff",
                                title: loc.localized("settings.media.recordingOff.summary"),
                                icon: "info.circle",
                                keywords: "recording disabled off"
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.caption)
                                        Text(verbatim: config.quality.preset.rawValue.capitalized)
                                            .font(.caption).bold()
                                        Text(verbatim: "·").font(.caption)
                                        Text(verbatim: config.quality.summaryText)
                                            .font(.caption)
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                            .font(.caption)
                                        Text(verbatim: displayOutputPath)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }

                        settingsCard(
                            id: "section-recordingBadge",
                            title: loc.localized("media.recordingBadge"),
                            icon: "circlebadge",
                            keywords: "recording badge position"
                        ) {
                            recordingBadgeSectionContent
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
            outputPath = config.output.localPath.isEmpty ? defaultOutputDirectory() : config.output.localPath
            qualityExpanded = config.qualityCustomizationExpanded(defaultFor: config.quality.preset)
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

    private var qualitySectionContent: some View {
        Group {
            Picker(loc.localized("settings.streaming.quality"), selection: Binding(
                get: { config.quality.preset },
                set: { newPreset in
                    config.quality.applyPreset(newPreset)
                    config.quality.save()
                }
            )) {
                Text(loc.localized("settings.streaming.qualityLow")).tag(RecordingQuality.low)
                Text(loc.localized("settings.streaming.qualityMedium")).tag(RecordingQuality.medium)
                Text(loc.localized("settings.streaming.qualityHigh")).tag(RecordingQuality.high)
                Text(loc.localized("settings.streaming.qualityLossless")).tag(RecordingQuality.lossless)
            }
            Text(verbatim: config.quality.summaryText)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))

            SettingsActionButton(loc.localized("settings.media.customize")) {
                qualityExpanded.toggle()
                config.setQualityCustomizationExpanded(qualityExpanded, for: config.quality.preset)
            }
            .controlSize(.small)

            if qualityExpanded {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Picker(loc.localized("settings.streaming.videoCodec"), selection: Binding(
                        get: { config.quality.codec },
                        set: {
                            config.quality.codec = $0
                            config.quality.customized = true
                            config.quality.save()
                        }
                    )) {
                        Text(verbatim: "H.264").tag(RecordingVideoCodec.h264)
                        Text(verbatim: "HEVC").tag(RecordingVideoCodec.hevc)
                        Text(verbatim: "ProRes 422").tag(RecordingVideoCodec.proRes422)
                        Text(verbatim: "ProRes 4444").tag(RecordingVideoCodec.proRes4444)
                    }

                    if config.quality.codec.supportsCustomBitrate {
                        HStack {
                            Text(loc.localized("settings.streaming.videoBitrate"))
                            Spacer()
                            TextField("", value: Binding(
                                get: { config.quality.videoBitrate / 1_000_000 },
                                set: {
                                    config.quality.videoBitrate = $0 * 1_000_000
                                    config.quality.customized = true
                                    config.quality.save()
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .frame(width: 60)
                            Text(verbatim: "Mbps")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                        }
                    }

                    HStack {
                        Text(loc.localized("settings.streaming.audioBitrate"))
                        Spacer()
                        TextField("", value: Binding(
                            get: { config.quality.audioBitrate / 1_000 },
                            set: {
                                config.quality.audioBitrate = $0 * 1_000
                                config.quality.customized = true
                                config.quality.save()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(width: 60)
                        Text(verbatim: "kbps")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }

                    HStack {
                        Text(loc.localized("settings.streaming.frameRate"))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { config.quality.frameRate },
                            set: {
                                config.quality.frameRate = $0
                                config.quality.customized = true
                                config.quality.save()
                            }
                        )) {
                            Text(verbatim: "30 fps").tag(30)
                            Text(verbatim: "60 fps").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    Text(loc.localized("settings.streaming.customQualityDescription"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }
        }
    }

    private var outputPathSectionContent: some View {
        Group {
            HStack(spacing: 8) {
                Text(verbatim: displayOutputPath)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsActionButton(loc.localized("settings.streaming.browse")) {
                    showFolderPicker = true
                }
                .controlSize(.small)
                .folderDialog(
                    isPresented: $showFolderPicker,
                    path: $outputPath,
                    prompt: "Choose a folder for recordings"
                )
                .onChange(of: outputPath) { _, newValue in
                    config.output.localPath = newValue
                    config.output.save()
                }
            }
            Text(loc.localized("settings.streaming.outputPathDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    private var recordingBadgeSectionContent: some View {
        Group {
            Toggle(loc.localized("media.recordingBadgeEnable"), isOn: Binding(
                get: { config.recordingBadge.enabled },
                set: { config.recordingBadge.enabled = $0; config.recordingBadge.save(keyPrefix: "recording_badge") }
            ))

            if config.recordingBadge.enabled {
                Picker(loc.localized("media.recordingBadgePosition"), selection: Binding(
                    get: { config.recordingBadge.position },
                    set: { config.recordingBadge.position = $0; config.recordingBadge.save(keyPrefix: "recording_badge") }
                )) {
                    ForEach(BadgePosition.allCases, id: \.rawValue) { pos in
                        Text(loc.localized(pos.localizationKey)).tag(pos)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var displayOutputPath: String {
        outputPath.isEmpty ? defaultOutputDirectory() : outputPath
    }

    private func defaultOutputDirectory() -> String {
        (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory).path
    }
}

import SwiftUI

struct RecordingTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String
    @Binding var scopedSectionID: String?

    @State private var outputPath: String = ""
    @State private var showFolderPicker = false
    @State private var qualityExpanded: Bool = false
    @State private var recordingEnabled: Bool = AppSettings.getBool("recording_local_enabled", defaultValue: true)
    @State private var seamlessRewindCut: Bool = AppSettings.getBool("recording_seamlessRewindCut", defaultValue: false)

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
        Form {
            if sectionVisible("section-recordingEnable") {
                Section {
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
                } header: {
                    Label(loc.localized("settings.media.recording.enable"), systemImage: "record.circle")
                }
                .id("section-recordingEnable")
            }

            if sectionVisible("section-recordingHotkey") {
                Section {
                    MediaHotkeyBindingRow(action: .recording, sectionKey: "settings.media.hotkey.recordingSection")
                    Text(loc.localized("settings.media.hotkey.editInHotkeys"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                } header: {
                    Label(loc.localized("settings.media.hotkey.recordingSection"), systemImage: "keyboard")
                }
                .id("section-recordingHotkey")
            }

            if recordingEnabled {
                if sectionVisible("section-recordWithShaders") {
                    recordWithShadersSection
                        .id("section-recordWithShaders")
                }
                if sectionVisible("section-seamlessRewindCut") {
                    seamlessRewindCutSection
                        .id("section-seamlessRewindCut")
                }
                if sectionVisible("section-qualitySection") {
                    qualitySection
                        .id("section-qualitySection")
                }
                if sectionVisible("section-outputPath") {
                    outputPathSection
                        .id("section-outputPath")
                }
            } else if sectionVisible("section-recordingOff") {
                Section {
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
                } header: {
                    Label(loc.localized("settings.media.recordingOff.summary"), systemImage: "info.circle")
                }
                .id("section-recordingOff")
            }

            if sectionVisible("section-recordingBadge") {
                recordingBadgeSection
                    .id("section-recordingBadge")
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .onAppear {
            outputPath = config.output.localPath.isEmpty ? defaultOutputDirectory() : config.output.localPath
            qualityExpanded = config.qualityCustomizationExpanded(defaultFor: config.quality.preset)
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
    }

    private var seamlessRewindCutSection: some View {
        Section {
            Toggle(loc.localized("settings.streaming.seamlessRewindCut"), isOn: Binding(
                get: { seamlessRewindCut },
                set: { newValue in
                    seamlessRewindCut = newValue
                    AppSettings.setBool("recording_seamlessRewindCut", value: newValue)
                }
            ))
            Text(loc.localized("settings.streaming.seamlessRewindCutDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    private var qualitySection: some View {
        Group {
            Section {
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

                Button(loc.localized("settings.media.customize")) {
                    qualityExpanded.toggle()
                    config.setQualityCustomizationExpanded(qualityExpanded, for: config.quality.preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } header: {
                Label(loc.localized("settings.streaming.localQuality"), systemImage: "slider.horizontal.3")
            } footer: {
                Text(loc.localized("settings.streaming.localQualityDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            if qualityExpanded {
                Section {
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
                } header: {
                    Label(loc.localized("settings.streaming.customQuality"), systemImage: "gearshape")
                }
                .id("section-customQuality")
            }
        }
    }

    private var outputPathSection: some View {
        Section {
            HStack(spacing: 8) {
                Text(verbatim: displayOutputPath)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(loc.localized("settings.streaming.browse")) {
                    showFolderPicker = true
                }
                .buttonStyle(.bordered)
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
        } header: {
            Label(loc.localized("settings.streaming.outputPath"), systemImage: "folder")
        }
    }

    private var recordingBadgeSection: some View {
        Section {
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
        } header: {
            Label(loc.localized("media.recordingBadge"), systemImage: "circlebadge")
        }
    }

    private var displayOutputPath: String {
        outputPath.isEmpty ? defaultOutputDirectory() : outputPath
    }

    private func defaultOutputDirectory() -> String {
        (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory).path
    }
}

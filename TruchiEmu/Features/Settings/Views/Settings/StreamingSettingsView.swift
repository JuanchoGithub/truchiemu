import SwiftUI

struct StreamingSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var recordingService = StreamRecordingService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var twitchKey: String = ""
    @State private var youtubeKey: String = ""
    @State private var customName: String = ""
    @State private var customKey: String = ""
    @State private var customURL: String = ""
    @State private var twitchURL: String = ""
    @State private var youtubeURL: String = ""
    @State private var showFolderPicker = false
    @State private var outputPath: String = ""

    @State private var twitchVerifyResult: VerifyState = .idle
    @State private var youtubeVerifyResult: VerifyState = .idle
    @State private var customVerifyResult: VerifyState = .idle

    @Binding var searchText: String

    private enum VerifyState: Equatable {
        case idle
        case verifying
        case success(String)
        case failure(String)
    }

    let searchKeywords = "streaming recording twitch youtube stream key credentials quality"

    private var isSearching: Bool { !searchText.isEmpty }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.streaming, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    var body: some View {
        Form {
            Section {
                Toggle(loc.localized("settings.streaming.enable"), isOn: Binding(
                    get: { recordingService.streamingEnabled },
                    set: { recordingService.streamingEnabled = $0; recordingService.saveSettings() }
                ))
                Text(loc.localized("settings.streaming.enableDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            } header: {
                Label(loc.localized("settings.streaming"), systemImage: "record.circle")
            }

            if recordingService.streamingEnabled {
                if !isSearching || matchesSearch("record with shaders applied gpu recording") {
                    Section {
                        Toggle(loc.localized("settings.streaming.recordWithShaders"), isOn: Binding(
                            get: { recordingService.recordWithShaders },
                            set: { recordingService.recordWithShaders = $0; recordingService.saveSettings() }
                        ))
                        Text(loc.localized("settings.streaming.recordWithShadersDescription"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }

                if !isSearching || matchesSearch("twitch stream key url verify") {
                    twitchSection
                }

                if !isSearching || matchesSearch("youtube stream key url verify") {
                    youtubeSection
                }

                if !isSearching || matchesSearch("custom stream key url server name") {
                    customSection
                }

                if !isSearching || matchesSearch("save recording as output path file location") {
                    outputPathSection
                }

                if !isSearching || matchesSearch("quality low medium high lossless bitrate codec frame rate resolution video audio") {
                    qualitySection
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .navigationTitle(loc.localized("settings.streaming"))
        .onAppear {
            twitchKey = StreamRecordingService.twitchStreamKey ?? ""
            youtubeKey = StreamRecordingService.youtubeStreamKey ?? ""
            twitchURL = StreamRecordingService.twitchStreamURL
            youtubeURL = StreamRecordingService.youtubeStreamURL
            customName = StreamRecordingService.customStreamName
            customKey = StreamRecordingService.customStreamKey ?? ""
            customURL = StreamRecordingService.customStreamURL
            outputPath = StreamRecordingService.localOutputPath ?? defaultOutputDirectory()
        }
    }

    // MARK: - Twitch Section

    private var twitchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField(loc.localized("settings.streaming.twitchKey"), text: $twitchKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onChange(of: twitchKey) { _, newValue in
                            StreamRecordingService.twitchStreamKey = newValue.isEmpty ? nil : newValue
                        }
                }
                HStack(spacing: 8) {
                    TextField(loc.localized("settings.streaming.streamURL"), text: $twitchURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: twitchURL) { _, newValue in
                            StreamRecordingService.twitchStreamURL = newValue.isEmpty ? StreamRecordingService.defaultTwitchURL : newValue
                        }
                    verifyButton(state: $twitchVerifyResult, mode: .twitch)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.localized("settings.streaming.twitchDescription"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Link("dashboard.twitch.tv", destination: URL(string: "https://dashboard.twitch.tv/settings/stream")!)
                        .font(.caption)
                }
            }
        } header: {
            Label("Twitch", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    // MARK: - YouTube Section

    private var youtubeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField(loc.localized("settings.streaming.youtubeKey"), text: $youtubeKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onChange(of: youtubeKey) { _, newValue in
                            StreamRecordingService.youtubeStreamKey = newValue.isEmpty ? nil : newValue
                        }
                }
                HStack(spacing: 8) {
                    TextField(loc.localized("settings.streaming.streamURL"), text: $youtubeURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: youtubeURL) { _, newValue in
                            StreamRecordingService.youtubeStreamURL = newValue.isEmpty ? StreamRecordingService.defaultYoutubeURL : newValue
                        }
                    verifyButton(state: $youtubeVerifyResult, mode: .youtube)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.localized("settings.streaming.youtubeDescription"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Link("studio.youtube.com", destination: URL(string: "https://studio.youtube.com/channel/livestreaming")!)
                        .font(.caption)
                }
            }
        } header: {
            Label("YouTube", systemImage: "video.badge.checkmark")
        }
    }

    // MARK: - Custom Stream Section

    private var customSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField(loc.localized("settings.streaming.customName"), text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onChange(of: customName) { _, newValue in
                        StreamRecordingService.customStreamName = newValue.isEmpty ? "Custom" : newValue
                    }
                HStack(spacing: 8) {
                    SecureField(loc.localized("settings.streaming.customKey"), text: $customKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onChange(of: customKey) { _, newValue in
                            StreamRecordingService.customStreamKey = newValue.isEmpty ? nil : newValue
                        }
                }
                HStack(spacing: 8) {
                    TextField(loc.localized("settings.streaming.customURL"), text: $customURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: customURL) { _, newValue in
                            StreamRecordingService.customStreamURL = newValue
                        }
                    verifyButton(state: $customVerifyResult, mode: .custom)
                }
                Text(loc.localized("settings.streaming.customStreamDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
        } header: {
            Label(loc.localized("settings.streaming.customStream"), systemImage: "network")
        }
    }

    // MARK: - Output Path Section

    private var outputPathSection: some View {
        Section {
            HStack(spacing: 8) {
                Text(outputPath)
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
                    path: $outputPath
                )
                .onChange(of: outputPath) { _, newValue in
                    StreamRecordingService.localOutputPath = newValue
                }
            }
            Text(loc.localized("settings.streaming.outputPathDescription"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        } header: {
            Label(loc.localized("settings.streaming.outputPath"), systemImage: "folder")
        }
    }

    // MARK: - Quality Sections

    private var qualitySection: some View {
        Group {
            Section {
                Picker(loc.localized("settings.streaming.quality"), selection: Binding(
                    get: { recordingService.quality },
                    set: { recordingService.quality = $0; recordingService.applyPreset($0); recordingService.saveSettings() }
                )) {
                    Text(loc.localized("settings.streaming.qualityLow")).tag(RecordingQuality.low)
                    Text(loc.localized("settings.streaming.qualityMedium")).tag(RecordingQuality.medium)
                    Text(loc.localized("settings.streaming.qualityHigh")).tag(RecordingQuality.high)
                    Text(loc.localized("settings.streaming.qualityLossless")).tag(RecordingQuality.lossless)
                }
            } header: {
                Label(loc.localized("settings.streaming.localQuality"), systemImage: "slider.horizontal.3")
            } footer: {
                Text(loc.localized("settings.streaming.localQualityDescription"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            Section {
                Picker(loc.localized("settings.streaming.videoCodec"), selection: Binding(
                    get: { recordingService.customVideoCodec },
                    set: { recordingService.customVideoCodec = $0; recordingService.saveSettings() }
                )) {
                    Text("H.264").tag(RecordingVideoCodec.h264)
                    Text("HEVC").tag(RecordingVideoCodec.hevc)
                    Text("ProRes 422").tag(RecordingVideoCodec.proRes422)
                    Text("ProRes 4444").tag(RecordingVideoCodec.proRes4444)
                }

                if recordingService.customVideoCodec.supportsCustomBitrate {
                    HStack {
                        Text(loc.localized("settings.streaming.videoBitrate"))
                        Spacer()
                        TextField("", value: Binding(
                            get: { recordingService.customVideoBitrate / 1_000_000 },
                            set: { recordingService.customVideoBitrate = $0 * 1_000_000; recordingService.saveSettings() }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(width: 60)
                        Text("Mbps")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                }

                HStack {
                    Text(loc.localized("settings.streaming.audioBitrate"))
                    Spacer()
                    TextField("", value: Binding(
                        get: { recordingService.customAudioBitrate / 1_000 },
                        set: { recordingService.customAudioBitrate = $0 * 1_000; recordingService.saveSettings() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(width: 60)
                    Text("kbps")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }

                HStack {
                    Text(loc.localized("settings.streaming.frameRate"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { recordingService.customFrameRate },
                        set: { recordingService.customFrameRate = $0; recordingService.saveSettings() }
                    )) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
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
        }
    }

    // MARK: - Verify Button

    @ViewBuilder
    private func verifyButton(state: Binding<VerifyState>, mode: StreamingMode) -> some View {
        switch state.wrappedValue {
        case .idle:
            Button(action: {
                Task { await performVerify(state: state, mode: mode) }
            }) {
                Label(loc.localized("settings.streaming.verify"), systemImage: "checkmark.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(loc.localized("settings.streaming.verifyDescription"))
        case .verifying:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .success(let msg):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success(colorScheme))
                    .font(.system(size: 14))
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.success(colorScheme))
                    .lineLimit(1)
            }
            .onTapGesture {
                state.wrappedValue = .idle
            }
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColors.error(colorScheme))
                    .font(.system(size: 14))
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.error(colorScheme))
                    .lineLimit(1)
            }
            .onTapGesture {
                state.wrappedValue = .idle
            }
        }
    }

    private func performVerify(state: Binding<VerifyState>, mode: StreamingMode) async {
        state.wrappedValue = .verifying
        let result = await StreamRecordingService.verifyStreamKey(mode: mode)
        switch result {
        case .success(let msg):
            state.wrappedValue = .success(msg)
        case .failure(let error):
            state.wrappedValue = .failure(error.localizedDescription)
        }
    }

    private func defaultOutputDirectory() -> String {
        (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory).path
    }
}

fileprivate extension View {
    func folderDialog(isPresented: Binding<Bool>, path: Binding<String>) -> some View {
        background(
            FolderDialogView(isPresented: isPresented, path: path)
        )
    }
}

private struct FolderDialogView: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var path: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.message = "Choose a folder for recording output"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    path = url.path
                }
                isPresented = false
            }
        }
    }
}
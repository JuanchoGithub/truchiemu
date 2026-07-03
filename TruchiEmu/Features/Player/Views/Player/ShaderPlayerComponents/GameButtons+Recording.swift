import SwiftUI

struct RecordStreamButton: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject private var recordingService = StreamRecordingService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropdownShown = false
    @State private var isHovered = false

    private var defaultIcon: String {
        recordingService.isUserRecording ? "stop.circle.fill" : "record.circle"
    }

    private var defaultLabel: String {
        if recordingService.isUserRecording {
            return loc.localized("toolbar.stopRecording")
        }
        return loc.localized("toolbar.record")
    }

    private var hasTwitchKey: Bool {
        if let key = StreamRecordingService.twitchStreamKey, !key.isEmpty { true } else { false }
    }

    private var hasYoutubeKey: Bool {
        if let key = StreamRecordingService.youtubeStreamKey, !key.isEmpty { true } else { false }
    }

    private var hasCustomKey: Bool {
        if let key = StreamRecordingService.customStreamKey, !key.isEmpty { true } else { false }
    }

    var body: some View {
        if !recordingService.streamingEnabled {
            EmptyView()
        } else {
            VStack(spacing: 4) {
                Image(systemName: defaultIcon)
                    .font(.system(size: 16, weight: .semibold))
                Text(defaultLabel)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(recordingService.isUserRecording ? .red : .white)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                if recordingService.isUserRecording {
                    recordingService.stop()
                } else {
                    isDropdownShown = true
                }
            }
            .popover(isPresented: $isDropdownShown, arrowEdge: .top) {
                StreamPickerView(
                    isDropdownShown: $isDropdownShown,
                    runner: runner,
                    recordingService: recordingService,
                    captureSize: runner.captureSize,
                    hasTwitchKey: hasTwitchKey,
                    hasYoutubeKey: hasYoutubeKey,
                    hasCustomKey: hasCustomKey
                )
                .frame(width: 220)
            }
        }
    }
}

private struct StreamPickerView: View {
    @Binding var isDropdownShown: Bool
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject var recordingService: StreamRecordingService
    let captureSize: CGSize
    let hasTwitchKey: Bool
    let hasYoutubeKey: Bool
    let hasCustomKey: Bool
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(recordingService.isUserRecording
                 ? loc.localized("toolbar.stopRecording")
                 : loc.localized("toolbar.record"))
                .font(.headline)
                .padding()
            Divider()
            if recordingService.isUserRecording {
                Button(action: {
                    recordingService.stop()
                    isDropdownShown = false
                }) {
                    Label(loc.localized("toolbar.stopRecording"), systemImage: "stop.circle.fill")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
            Button(action: {
                startMode(.localFile)
                isDropdownShown = false
            }) {
                Label(loc.localized("settings.streaming.localFile"), systemImage: "record.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hasTwitchKey {
                Divider().opacity(0.3)
                Button(action: {
                    startMode(.twitch)
                    isDropdownShown = false
                }) {
                    Label("Twitch", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if hasYoutubeKey {
                Divider().opacity(0.3)
                Button(action: {
                    startMode(.youtube)
                    isDropdownShown = false
                }) {
                    Label("YouTube", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if hasCustomKey {
                Divider().opacity(0.3)
                Button(action: {
                    startMode(.custom)
                    isDropdownShown = false
                }) {
                    Label(StreamRecordingService.customStreamName, systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func startMode(_ mode: StreamingMode) {
        let size = runner.captureSize
        switch mode {
        case .twitch, .youtube, .custom:
            recordingService.videoSize = size
            recordingService.startStreaming(mode: mode)
        case .localFile:
            let url = recordingOutputURL()
            recordingService.startRecording(outputURL: url, width: Int(size.width), height: Int(size.height))
        }
    }

    private func recordingOutputURL() -> URL {
        let directory: URL
        if let saved = StreamRecordingService.localOutputPath, !saved.isEmpty {
            directory = URL(fileURLWithPath: saved)
        } else {
            directory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ??
                FileManager.default.temporaryDirectory
        }
        let systemID = runner.systemID
        let gameName = sanitizeFilenameComponent(runner.rom?.displayName ?? runner.rom?.filenameWithoutExtension ?? "unknown")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let date = formatter.string(from: Date())
        let ext = recordingService.customVideoCodec.isLossless ? "mov" : "mp4"
        let filename = "TruchiEmu_\(systemID)_\(gameName)_\(date).\(ext)"
        return directory.appendingPathComponent(filename)
    }

    private func sanitizeFilenameComponent(_ str: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: ".-_"))
        return str.components(separatedBy: allowed.inverted).joined()
    }
}

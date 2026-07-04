import SwiftUI

enum VerifyState: Equatable {
    case idle
    case verifying
    case success(String)
    case failure(String)
}

struct VerifyButton: View {
    @Binding var state: VerifyState
    let mode: StreamingMode
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        switch state {
        case .idle:
            Button(action: { Task { await performVerify() } }) {
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
                Text(verbatim: msg)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.success(colorScheme))
                    .lineLimit(1)
            }
            .onTapGesture { state = .idle }
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColors.error(colorScheme))
                    .font(.system(size: 14))
                Text(verbatim: msg)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.error(colorScheme))
                    .lineLimit(1)
            }
            .onTapGesture { state = .idle }
        }
    }

    private func performVerify() async {
        state = .verifying
        let result = await StreamRecordingService.verifyStreamKey(mode: mode)
        switch result {
        case .success(let msg):
            state = .success(msg)
        case .failure(let error):
            state = .failure(error.localizedDescription)
        }
    }
}

struct TwitchSection: View {
    @Binding var key: String
    @Binding var url: String
    @Binding var verifyResult: VerifyState
    let onKeyChange: () -> Void
    let onURLChange: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(loc.localized("settings.streaming.twitchKey"), text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onChange(of: key) { _, _ in onKeyChange() }
            HStack(spacing: 8) {
                TextField(loc.localized("settings.streaming.streamURL"), text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onChange(of: url) { _, _ in onURLChange() }
                VerifyButton(state: $verifyResult, mode: .twitch)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.localized("settings.streaming.twitchDescription"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("dashboard.twitch.tv", destination: URL(string: "https://dashboard.twitch.tv/settings/stream")!)
                    .font(.caption)
            }
        }
    }
}

struct YouTubeSection: View {
    @Binding var key: String
    @Binding var url: String
    @Binding var verifyResult: VerifyState
    let onKeyChange: () -> Void
    let onURLChange: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(loc.localized("settings.streaming.youtubeKey"), text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onChange(of: key) { _, _ in onKeyChange() }
            HStack(spacing: 8) {
                TextField(loc.localized("settings.streaming.streamURL"), text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onChange(of: url) { _, _ in onURLChange() }
                VerifyButton(state: $verifyResult, mode: .youtube)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.localized("settings.streaming.youtubeDescription"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("studio.youtube.com", destination: URL(string: "https://studio.youtube.com/channel/livestreaming")!)
                    .font(.caption)
            }
        }
    }
}

struct CustomStreamSection: View {
    @Binding var name: String
    @Binding var key: String
    @Binding var url: String
    @Binding var verifyResult: VerifyState
    let onNameChange: () -> Void
    let onKeyChange: () -> Void
    let onURLChange: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(loc.localized("settings.streaming.customName"), text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onChange(of: name) { _, _ in onNameChange() }
            SecureField(loc.localized("settings.streaming.customKey"), text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onChange(of: key) { _, _ in onKeyChange() }
            HStack(spacing: 8) {
                TextField(loc.localized("settings.streaming.customURL"), text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onChange(of: url) { _, _ in onURLChange() }
                VerifyButton(state: $verifyResult, mode: .custom)
            }
            Text(loc.localized("settings.streaming.customStreamDescription"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

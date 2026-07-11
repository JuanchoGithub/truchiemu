import SwiftUI

enum BadgePosition: Int, Codable, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomLeft = 2
    case bottomRight = 3
    case topCenter = 4
    case bottomCenter = 5

    var localizationKey: String {
        "media.badgePosition." + {
            switch self {
            case .topLeft: return "topLeft"
            case .topRight: return "topRight"
            case .bottomLeft: return "bottomLeft"
            case .bottomRight: return "bottomRight"
            case .topCenter: return "topCenter"
            case .bottomCenter: return "bottomCenter"
            }
        }()
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .topCenter: return .top
        case .bottomCenter: return .bottom
        }
    }
}

struct RecordingBadgeOverlay: View {
    @ObservedObject private var recordingService = StreamRecordingService.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var elapsedString: String = "00:00"
    @State private var badgeEnabled: Bool = true
    @State private var positionRaw: Int = 1
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentPrefix: String {
        recordingService.mode == .localFile ? "recording_badge" : "streaming_badge"
    }

    private var currentAlignment: Alignment {
        BadgePosition(rawValue: positionRaw)?.alignment ?? .topTrailing
    }

    var body: some View {
        Group {
            if let error = recordingService.streamError {
                errorBadge(error)
            } else if !badgeEnabled { EmptyView() }
            else if case .connecting = recordingService.streamStatus {
                connectingBadge
            } else if recordingService.isUserRecording {
                recordingBadge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: currentAlignment)
        .allowsHitTesting(false)
        .onReceive(timer) { _ in
            guard recordingService.streamStatus == .streaming || recordingService.mode == .localFile,
                  let start = recordingService.recordingStartTime else {
                elapsedString = "00:00"
                badgeEnabled = true
                return
            }
            let interval = -start.timeIntervalSinceNow
            let seconds = Int(interval)
            let mins = seconds / 60
            let secs = seconds % 60
            elapsedString = String(format: "%02d:%02d", mins, secs)
            let prefix = currentPrefix
            badgeEnabled = AppSettings.getBool("\(prefix)_enabled", defaultValue: true)
            positionRaw = AppSettings.getInt("\(prefix)_position", defaultValue: 1)
        }
    }

    @ViewBuilder
    private func errorBadge(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .padding(12)
        .transition(.opacity)
    }

    @ViewBuilder
    private var connectingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
            Text("CONNECTING")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .padding(12)
        .transition(.opacity)
    }

    @ViewBuilder
    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text(elapsedString)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .monospacedDigit()
            if recordingService.mode == .localFile {
                Text("REC")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            } else if recordingService.mode == .twitch {
                AsyncImage(url: URL(string: "https://www.twitch.tv/favicon.ico")) { phase in
                    if let image = phase.image {
                        image.resizable().frame(width: 12, height: 12)
                    }
                }
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            } else if recordingService.mode == .youtube {
                AsyncImage(url: URL(string: "https://www.youtube.com/favicon.ico")) { phase in
                    if let image = phase.image {
                        image.resizable().frame(width: 12, height: 12)
                    }
                }
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            } else if recordingService.mode == .custom {
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .padding(12)
        .transition(.opacity)
    }
}

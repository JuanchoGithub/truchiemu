import SwiftUI

struct CoreDownloadStatusBar: View {
    @ObservedObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared

    private var statusMessage: String {
        switch coreManager.downloadPhase {
        case .idle:
            return ""
        case .findingURL:
            return loc.localized("coreDownload.status.findingURL")
        case .fetchingFromURL:
            return loc.localized("coreDownload.status.fetchingFromURL")
        case .downloading:
            return loc.localized("coreDownload.status.downloading")
        case .installing:
            return loc.localized("coreDownload.status.installing")
        }
    }

    private var progress: Double {
        switch coreManager.downloadPhase {
        case .downloading(let p):
            return p
        case .findingURL, .fetchingFromURL:
            return 0
        case .installing:
            return 1.0
        default:
            return 0
        }
    }

    private var isIndeterminate: Bool {
        switch coreManager.downloadPhase {
        case .findingURL, .fetchingFromURL, .installing:
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if isIndeterminate {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(coreManager.downloadCoreName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if isIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(AppColors.brandAccentSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

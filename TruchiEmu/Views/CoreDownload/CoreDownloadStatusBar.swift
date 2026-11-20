import SwiftUI

struct CoreDownloadStatusBar: View {
	@ObservedObject var coreManager: CoreManager
	@ObservedObject private var loc = LocalizationManager.shared
	@Environment(\.colorScheme) private var colorScheme

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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AppColors.accentBackground(colorScheme))
                    )

                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isIndeterminate {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(verbatim: "\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }

                Text(coreManager.downloadCoreName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
            }

            if isIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(AppColors.brandAccent)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(AppColors.brandAccent)
                    .scaleEffect(y: 0.8, anchor: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground(colorScheme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(height: 1)
        }
    }
}

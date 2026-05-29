import SwiftUI

struct UpdateAvailableView: View {
    let release: AppRelease
    @ObservedObject private var updateService = AppUpdateService.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.brandAccent)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(loc.localized("update.availableTitle"))
                        .font(.headline)
                    Text(loc.localized("update.availableSubtitle") + " \(release.version)")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Spacer()
                Button {
                    AppUpdateService.shared.skipVersion(release.version)
                } label: {
                    Text(loc.localized("update.skipVersion"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }

        if isExpanded {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(release.name)
                        .font(.subheadline.weight(.semibold))
                    MarkdownBodyView(markdown: release.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }

            HStack(spacing: AppSpacing.md) {
                if updateService.isDownloading {
                    ProgressView(value: updateService.downloadProgress) {
                        Text(loc.localized("update.downloading"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button(loc.localized("update.downloadAndInstall")) {
                        Task { await updateService.downloadAndInstall(release: release) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(loc.localized("update.viewOnGitHub")) {
                        if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            if let date = release.publishedAt {
                Text(loc.localized("update.releasedOn") + " " + date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 1)
        )
    }
}

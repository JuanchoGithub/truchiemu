import SwiftUI

struct WhatsNewView: View {
    @ObservedObject private var updateService = AppUpdateService.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isLoading = false
    @State private var releaseBody: String?
    @State private var releaseName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(loc.localized("update.whatsNew"))
                        .font(.headline)
                    if let name = releaseName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(AppSpacing.md)

            Divider()

            if let body = releaseBody {
                ScrollView {
                    MarkdownBodyView(markdown: body)
                        .padding(AppSpacing.md)
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AppEmptyState(
                    icon: "doc.text",
                    title: loc.localized("update.noReleaseNotes"),
                    description: loc.localized("update.noReleaseNotesDescription")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .task { await loadLatestReleaseNotes() }
    }

    private func loadLatestReleaseNotes() async {
        if let latest = updateService.allReleases.first {
            releaseBody = latest.body
            releaseName = latest.name
            return
        }
        isLoading = true
        _ = await updateService.checkForUpdates()
        if let latest = updateService.allReleases.first {
            releaseBody = latest.body
            releaseName = latest.name
        }
        isLoading = false
    }
}

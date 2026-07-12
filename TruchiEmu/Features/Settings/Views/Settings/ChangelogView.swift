import SwiftUI

struct ChangelogView: View {
    @ObservedObject private var updateService = AppUpdateService.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isLoading = false
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(loc.localized("update.changelog"))
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(loc.localized("update.refresh")) {
                        Task {
                            isLoading = true
                            _ = await updateService.checkForUpdates()
                            isLoading = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(AppSpacing.md)

            Divider()

            if updateService.allReleases.isEmpty && !isLoading {
                AppEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: loc.localized("update.noReleases"),
                    description: loc.localized("update.noReleasesDescription")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        ForEach(updateService.allReleases) { release in
                            ChangelogRow(
                                release: release,
                                isExpanded: expandedIDs.contains(release.id),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedIDs.contains(release.id) {
                                            expandedIDs.remove(release.id)
                                        } else {
                                            expandedIDs.insert(release.id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(AppSpacing.md)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .task { await loadReleasesIfNeeded() }
    }

    private func loadReleasesIfNeeded() async {
        guard updateService.allReleases.isEmpty else { return }
        isLoading = true
        _ = await updateService.checkForUpdates()
        isLoading = false
    }
}

private struct ChangelogRow: View {
    let release: AppRelease
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .frame(width: 16)

                if release.isCurrent {
                    Text("v\(release.version)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    Text(loc.localized("update.currentVersion"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                } else {
                    Text("v\(release.version)")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                if let date = release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
            }
            .padding(AppSpacing.md)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    MarkdownBodyView(markdown: release.body)
                        .padding(AppSpacing.md)
                }
            }
        }
        .background(AppColors.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

struct MarkdownBodyView: View {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if markdown.isEmpty {
            EmptyView()
        } else {
            Text(renderMarkdown(markdown))
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func renderMarkdown(_ source: String) -> AttributedString {
        let processed = source
            .replacingOccurrences(of: "\r\n", with: "\n")

        if let attributed = try? AttributedString(
            markdown: processed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(processed)
    }
}

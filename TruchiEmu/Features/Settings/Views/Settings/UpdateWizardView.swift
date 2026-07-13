import SwiftUI

/// Full-screen modal wizard shown on startup when an update is available.
/// Blocks the main UI until the user chooses an action (download+restart,
/// install-without-restart, or skip). Patterned after `InstallDragView`.
struct UpdateWizardView: View {
    let release: AppRelease
    let onDismiss: () -> Void

    @ObservedObject private var updateService = AppUpdateService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var expandedReleaseIDs: Set<String> = []
    @State private var didFinishInstallNoRestart = false
    @State private var didError = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl3) {
                headerSection
                versionComparison
                releaseNotesSection
                changelogSection
                actionSection
            }
            .padding(AppSpacing.xl3)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.brandAccent)
            Text(loc.localized("update.availableTitle"))
                .font(.largeTitle.weight(.bold))
            Text(loc.localized("update.availableSubtitle") + " \(release.version)")
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
        .padding(.top, AppSpacing.xl2)
    }

    // MARK: - Version Comparison

    private var versionComparison: some View {
        HStack(spacing: AppSpacing.lg) {
            versionChip(
                label: loc.localized("update.currentLabel"),
                version: AppVersion.current,
                isCurrent: true
            )
            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
            versionChip(
                label: loc.localized("update.latestLabel"),
                version: release.version,
                isCurrent: false
            )
            Spacer()
        }
    }

    private func versionChip(label: String, version: String, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
            Text("v\(version)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isCurrent ? AppColors.textPrimary(colorScheme) : AppColors.brandAccent)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(isCurrent ? AppColors.cardBorder(colorScheme) : AppColors.brandAccent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Release Notes (latest)

    private var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(loc.localized("update.wizardReleaseNotes"))
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(release.name)
                        .font(.subheadline.weight(.semibold))
                    MarkdownBodyView(markdown: release.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
            )
            if let date = release.publishedAt {
                Text(loc.localized("update.releasedOn") + " " + date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
    }

    // MARK: - Collapsible Changelog (all versions since current)

    @ViewBuilder
    private var changelogSection: some View {
        let others = updateService.newerReleases.filter { $0.tagName != release.tagName }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(loc.localized("update.changelog"))
                    .font(.headline)
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(others) { other in
                        WizardChangelogRow(
                            release: other,
                            isExpanded: expandedReleaseIDs.contains(other.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedReleaseIDs.contains(other.id) {
                                        expandedReleaseIDs.remove(other.id)
                                    } else {
                                        expandedReleaseIDs.insert(other.id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private var actionSection: some View {
        if didFinishInstallNoRestart {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(loc.localized("update.wizardUpdateLaterMessage"))
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                Button(loc.localized("update.viewOnGitHub")) {
                    if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = errorMessage {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                Button(loc.localized("update.viewOnGitHub")) {
                    if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if updateService.isDownloading {
            VStack(spacing: AppSpacing.sm) {
                if updateService.downloadProgress >= 0 {
                    ProgressView(value: updateService.downloadProgress) {
                        Text(loc.localized("update.downloading"))
                            .font(.caption)
                    }
                } else {
                    ProgressView() {
                        Text(loc.localized("update.downloading"))
                            .font(.caption)
                    }
                }
                if updateService.totalBytesWritten > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: updateService.totalBytesWritten, countStyle: .file) + (updateService.totalBytesExpected > 0 ? " / " + ByteCountFormatter.string(fromByteCount: updateService.totalBytesExpected, countStyle: .file) : ""))
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
            }
            .frame(maxWidth: .infinity)
        } else if updateService.isInstalling {
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                Text(loc.localized("update.wizardUpdateInstalled"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: AppSpacing.lg) {
                Button {
                    Task {
                        await updateService.downloadAndInstall(release: release)
                    }
                } label: {
                    Label(loc.localized("update.wizardUpdateAndRestart"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task {
                        let installed = await updateService.downloadUpdateOnly(release: release)
                        if installed != nil {
                            didFinishInstallNoRestart = true
                        } else {
                            errorMessage = loc.localized("update.noReleasesDescription")
                        }
                    }
                } label: {
                    Text(loc.localized("update.wizardUpdateLater"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    AppUpdateService.shared.skipVersion(release.version)
                    onDismiss()
                } label: {
                    Text(loc.localized("update.skipVersion"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Changelog row for older "since-current" versions

private struct WizardChangelogRow: View {
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
                Text("v\(release.version)")
                    .font(.subheadline.weight(.medium))
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

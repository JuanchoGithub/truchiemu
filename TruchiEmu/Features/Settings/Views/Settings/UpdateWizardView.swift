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
        DeckHeroBand(
            icon: "arrow.down.circle.fill",
            eyebrow: loc.localized("update.eyebrow"),
            title: loc.localized("update.availableTitle"),
            subtitle: "\(loc.localized("update.availableSubtitle")) \(release.version)",
            stats: [
                DeckStatItem(
                    id: "current",
                    icon: "desktopcomputer",
                    value: "v\(AppVersion.current)",
                    unit: loc.localized("update.currentLabel")
                ),
                DeckStatItem(
                    id: "latest",
                    icon: "sparkles",
                    value: "v\(release.version)",
                    unit: loc.localized("update.latestLabel"),
                    tint: AppColors.success(colorScheme)
                )
            ],
            height: 108
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.cardBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                SettingsActionButton(loc.localized("update.viewOnGitHub")) {
                    if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = errorMessage {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                SettingsActionButton(loc.localized("update.viewOnGitHub")) {
                    if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                }
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

                SettingsActionButton(loc.localized("update.skipVersion")) {
                    AppUpdateService.shared.skipVersion(release.version)
                    onDismiss()
                }
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

import SwiftUI

/// Step-by-step repair prompt for failed in-app updates (issue #40).
/// Finder-only: the app never deletes files. It only selects them in Finder
/// or reinstalls from the running copy on user action.
struct RecoveryPromptView: View {
    let report: AppUpdateService.UpdateHealthReport
    let onDismiss: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isReinstalling = false
    @State private var reinstallDone = false
    @State private var reinstallError: String?

    private var showsReinstall: Bool {
        report.brokenMainCopyPath != nil || report.splitInstalledPath != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl3) {
                headerSection
                if !report.strayPaths.isEmpty {
                    straySection
                }
                if report.brokenMainCopyPath != nil {
                    brokenSection
                }
                if report.splitInstalledPath != nil {
                    splitSection
                }
                actionSection
            }
            .padding(AppSpacing.xl3)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text(loc.localized("update.recovery.title"))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.xl2)
    }

    private var straySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(loc.localized("update.recovery.strayIntro"))
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            ForEach(report.strayPaths, id: \.self) { path in
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsActionButton(loc.localized("update.recovery.showInFinder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            stepList([
                loc.localized("update.recovery.stepQuit"),
                loc.localized("update.recovery.stepTrashFinder"),
                loc.localized("update.recovery.stepDownload"),
                loc.localized("update.recovery.stepMove"),
                loc.localized("update.recovery.stepVerify"),
            ])
        }
    }

    private var brokenSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(loc.localized("update.recovery.brokenIntro"))
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            if let path = report.brokenMainCopyPath {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            reinstallBlock
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(loc.localized("update.recovery.splitIntro"))
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            if let running = report.splitRunningPath,
               let installed = report.splitInstalledPath {
                Text("\(running) (v\(report.splitRunningVersion ?? "?"))\n\(installed) (v\(report.splitInstalledVersion ?? "?"))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            reinstallBlock
        }
    }

    @ViewBuilder
    private var reinstallBlock: some View {
        if reinstallDone {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(loc.localized("update.recovery.reinstallDone"))
                    .font(.callout)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
        } else if isReinstalling {
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                Text(loc.localized("update.recovery.reinstalling"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Button {
                    Task {
                        isReinstalling = true
                        reinstallError = nil
                        do {
                            _ = try await AppUpdateService.shared.reinstallFromRunningCopy()
                            reinstallDone = true
                        } catch {
                            reinstallError = loc.localized("update.recovery.reinstallFailed") + " " + error.localizedDescription
                        }
                        isReinstalling = false
                    }
                } label: {
                    Label(loc.localized("update.recovery.reinstallFromRunning"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if let error = reinstallError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: AppSpacing.lg) {
            if !showsReinstall {
                SettingsActionButton(loc.localized("update.viewOnGitHub")) {
                    AppUpdateService.shared.openReleasesPage()
                }
            }
            SettingsActionButton(loc.localized("update.recovery.dismiss")) {
                AppUpdateService.shared.dismissRecovery(for: report)
                onDismiss()
            }
        }
    }

    private func stepList(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text("\(index + 1).")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    Text(step)
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

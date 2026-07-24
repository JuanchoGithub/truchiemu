import SwiftUI
import AppKit

// Locked-down UI presented when SwiftDataContainer.launchSchemaError != nil.
// This means the on-disk SwiftData store could not be migrated/opened on this
// launch; the container currently in use is the in-memory fallback, and the
// user's saves/BIOS/states/library-DB are left intact on disk. The mode lets
// the user check for a fixing update or proceed to the limited main UI.
struct AppUpdateModeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var updateService = AppUpdateService.shared

    @State private var isChecking = false
    @State private var checkError: String?

    private var launchErrorDescription: String {
        SwiftDataContainer.shared.launchSchemaError?.localizedDescription ?? ""
    }

    var body: some View {
        VStack(spacing: AppSpacing.xl3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(loc.localized("updateMode.title"))
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)

            Text(loc.localized("updateMode.description"))
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if !launchErrorDescription.isEmpty {
                GroupBox(label: Text(loc.localized("updateMode.errorSection"))) {
                    Text(launchErrorDescription)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(AppSpacing.xs)
                }
                .frame(maxWidth: 460)
            }

            VStack(spacing: AppSpacing.md) {
                Button {
                    Task { await checkForUpdate() }
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isChecking
                             ? loc.localized("updateMode.checking")
                             : loc.localized("updateMode.checkForUpdate"))
                    }
                    .frame(maxWidth: 220)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(isChecking)

                Button {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Time Machine.app"), configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    Label(loc.localized("updateMode.openTimeMachine"), systemImage: "clock.arrow.circlepath")
                }
                .controlSize(.large)
                .buttonStyle(.bordered)

                HStack(spacing: AppSpacing.lg) {
                    Button(loc.localized("updateMode.continueLimited")) {
                        NotificationCenter.default.post(name: .exitAppUpdateMode, object: nil)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)

                    Button(loc.localized("updateMode.quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                }
            }

            if let err = checkError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 460)
            }

            if let latest = updateService.latestRelease, latest.isNewer {
                VStack(spacing: AppSpacing.xs) {
                    Text(String(format: loc.localized("updateMode.updateAvailable"), latest.version))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    if let url = URL(string: latest.htmlURL) {
                        Button(loc.localized("updateMode.openReleasePage")) { openURL(url) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(AppColors.brandAccent)
                    }
                }
            }

            Spacer(minLength: AppSpacing.xs)

            Text(loc.localized("updateMode.userDataIntact"))
                .font(.footnote)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(AppSpacing.xl3)
        .frame(minWidth: 560, minHeight: 560)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .onAppear {
            // Force-update autocheck while in Update Mode so the user is pinged
            // the moment a fixing release goes live.
            updateService.autoCheckEnabled = true
            Task { await checkForUpdate() }
        }
    }

    private func checkForUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        checkError = nil
        _ = await updateService.checkForUpdates()
    }
}

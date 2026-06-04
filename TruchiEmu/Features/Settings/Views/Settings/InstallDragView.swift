import SwiftUI
import UniformTypeIdentifiers

struct InstallDragView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isDragOverApplications = false
    @State private var isInstalling = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: AppSpacing.xl3) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text(loc.localized("install.welcome"))
                .font(.title.weight(.bold))

            Text(loc.localized("install.instructions"))
                .font(.body)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: AppSpacing.xl4) {
                VStack(spacing: AppSpacing.sm) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("TruchiEmu")
                        .font(.caption.weight(.medium))
                }
                .help(loc.localized("install.dragHint"))

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))

                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .fill(isDragOverApplications ? AppColors.brandAccent.opacity(0.15) : AppColors.cardBackground(colorScheme))
                        .frame(width: 100, height: 100)

                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .stroke(
                            isDragOverApplications ? AppColors.brandAccent : AppColors.cardBorder(colorScheme),
                            style: StrokeStyle(lineWidth: isDragOverApplications ? 2 : 1, dash: [8, 4])
                        )
                        .frame(width: 100, height: 100)

                    VStack(spacing: AppSpacing.xs) {
                        Image(systemName: "folder.fill.badge.plus")
                            .font(.title2)
                            .foregroundStyle(isDragOverApplications ? AppColors.brandAccent : AppColors.textTertiary(colorScheme))
                        Text(loc.localized("install.applicationsFolder"))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragOverApplications) { providers in
                    handleDrop(providers: providers)
                }
            }
            .padding(.vertical, AppSpacing.xl2)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(spacing: AppSpacing.sm) {
                Button(loc.localized("install.copyToApplications")) {
                    copyToApplications()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isInstalling)

                Button(loc.localized("install.openAnyway")) {
                    markInstallSkipped()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Text(loc.localized("install.openAnywayDescription"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
        }
        .padding(AppSpacing.xl5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.pathExtension == "app" else { return }
            copyApp(from: url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent))
        }
        return true
    }

    private func copyToApplications() {
        let sourceURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        copyApp(from: sourceURL)
    }

    private func copyApp(from sourceURL: URL) {
        isInstalling = true
        errorMessage = nil
        let appName = sourceURL.lastPathComponent
        let destURL = URL(fileURLWithPath: "/Applications/\(appName)")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)

                DispatchQueue.main.async {
            AppSettings.markVersionCompleted("installDragSkipped_version")
                let installedAppURL = destURL
                    let executableName = appName.replacingOccurrences(of: ".app", with: "")
                    let executableURL = installedAppURL.appendingPathComponent("Contents/MacOS/\(executableName)")

                    let process = Process()
                    process.executableURL = executableURL
                    process.arguments = []
                    try? process.run()
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    isInstalling = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func markInstallSkipped() {
        AppSettings.markVersionCompleted("installDragSkipped_version")
        NotificationCenter.default.post(name: .installDragCompleted, object: nil)
    }

    static func shouldShow() -> Bool {
        if AppSettings.isVersionMatch("installDragSkipped_version") { return false }
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasPrefix("/Applications/") { return false }
        if bundlePath.hasPrefix("/private/") { return false }
        if bundlePath.contains("Xcode.app") { return false }
        if bundlePath.contains("DerivedData") { return false }
        return true
    }
}

extension Notification.Name {
    static let installDragCompleted = Notification.Name("installDragCompleted")
}

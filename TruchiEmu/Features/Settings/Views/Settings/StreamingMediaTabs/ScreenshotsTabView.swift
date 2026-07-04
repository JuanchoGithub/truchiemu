import SwiftUI

struct ScreenshotsTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var config: MediaConfig
    @Binding var searchText: String

    @State private var customPath: String = ""
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("screenshot.includeNative")
                            .lineLimit(1)
                        Text("screenshot.includeNativeHelp")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { config.screenshot.includeNative },
                        set: { config.screenshot.includeNative = $0; config.screenshot.save() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .padding(.vertical, AppSpacing.xxs)
            } header: {
                Label(loc.localized("screenshot.section"), systemImage: "camera")
            }

            Section {
                HStack(spacing: 8) {
                    Text(verbatim: displayPath)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(loc.localized("settings.streaming.browse")) {
                        showFolderPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if config.screenshot.hasCustomPath {
                        Button(loc.localized("settings.media.reset")) {
                            config.screenshot.outputPath = ""
                            config.screenshot.save()
                            customPath = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .folderDialog(
                    isPresented: $showFolderPicker,
                    path: $customPath,
                    prompt: "Choose a folder for screenshots"
                )
                .onChange(of: customPath) { _, newValue in
                    config.screenshot.outputPath = newValue
                    config.screenshot.save()
                }
                Text(loc.localized("settings.media.screenshotPathDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            } header: {
                Label(loc.localized("settings.media.screenshotPath"), systemImage: "folder")
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .onAppear {
            customPath = config.screenshot.outputPath
        }
    }

    private var displayPath: String {
        if !config.screenshot.outputPath.isEmpty { return config.screenshot.outputPath }
        return ScreenshotService.baseDirectory.path
    }
}

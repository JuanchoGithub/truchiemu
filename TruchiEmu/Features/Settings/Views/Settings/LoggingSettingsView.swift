import SwiftUI
import AppKit

struct LoggingSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedLevel: LogLevel = .none

    @StateObject private var viewModel = LoggingSettingsViewModel()

    @Binding var searchText: String
    @ObservedObject private var loc = LocalizationManager.shared

    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.logging, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    var body: some View {
        Form {
            if !isSearching || matchesSearch("logging log debug console output level verbosity info extreme") {
                Section {
                    Picker(loc.localized("logging.logLevel"), selection: $selectedLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.description).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    logLevelDescription
                } header: {
                    Label { Text(loc.localized("logging.logLevel")) } icon: { Image(systemName: "slider.vertical.3") }
                } footer: {
                    Text(loc.localized("logging.logLevelDescription"))
                }
            }

            if !isSearching || matchesSearch("logging file folder location path size archive") {
                Section {
                    LabeledContent(loc.localized("logging.location")) {
                        HStack(spacing: AppSpacing.sm) {
                            Text(viewModel.currentLogFilePath)
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary(colorScheme))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(loc.localized("logging.showInFinder")) {
                                viewModel.showLogInFinder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    LabeledContent(loc.localized("logging.currentFile")) {
                        Text(viewModel.currentLogFileSize)
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }

                    LabeledContent(loc.localized("logging.totalLogSize")) {
                        Text(viewModel.totalLogFileSize)
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }

                    if viewModel.hasCustomLogFolder {
                        Text(loc.localized("logging.customLocationDescription"))
                            .font(.caption)
                            .foregroundStyle(AppColors.brandAccent)
                    }

                    HStack {
                        Button(loc.localized("logging.changeLocation")) {
                            viewModel.changeLogFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if viewModel.hasCustomLogFolder {
                            Button(loc.localized("logging.reset")) {
                                viewModel.resetToDefaultFolder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Label { Text(loc.localized("logging.logFileLocation")) } icon: { Image(systemName: "folder") }
                }
            }

            if !isSearching || matchesSearch("logging maintenance clear trim delete archive rotation size") {
                Section {
                    LabeledContent(loc.localized("logging.maxFileSize")) {
                        Text(loc.localized("logging.fiveMB"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }

                    LabeledContent(loc.localized("logging.autoRotation")) {
                        Text(loc.localized("logging.enabled"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }

                    LabeledContent(loc.localized("logging.ageLimit")) {
                        Text(loc.localized("logging.sevenDays"))
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                    }

                    Divider()
                        .padding(.vertical, AppSpacing.xs)

                    HStack {
                        Button(loc.localized("logging.trimOldEntries")) {
                            viewModel.trimOldLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(loc.localized("logging.clearAllLogs")) {
                            viewModel.clearAllLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } header: {
                    Label { Text(loc.localized("logging.logMaintenance")) } icon: { Image(systemName: "trash") }
                } footer: {
                    Text(loc.localized("logging.maintenanceDescription"))
                }
            }

            if isSearching && !hasMatchingSections {
                Section {
                    Text(loc.localized("logging.noMatchingSettings") + " \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("logging.title"))
        .onAppear {
            let rawLevel = AppSettings.get("log_level", type: String.self) ?? "info"
            selectedLevel = LogLevel(rawValue: rawLevel) ?? .info
            viewModel.refreshInfo()
        }
        .onChange(of: selectedLevel) { _, newValue in
            LoggerService.shared.setLevel(newValue)
            AppSettings.set("log_level", value: newValue.rawValue)
        }
    }

    private var hasMatchingSections: Bool {
        matchesSearch("logging log debug console output level verbosity info extreme") ||
        matchesSearch("logging file folder location path size archive") ||
        matchesSearch("logging maintenance clear trim delete archive rotation size")
    }

    private var logLevelDescription: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            switch selectedLevel {
            case .none:
                Label { Text(loc.localized("logging.noLogsRecorded")) } icon: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(AppColors.error(colorScheme))
            case .info:
                Label { Text(loc.localized("logging.generalLogs")) } icon: { Image(systemName: "info.circle.fill") }
                    .foregroundStyle(AppColors.brandAccent)
            case .debug:
                Label { Text(loc.localized("logging.detailedLogs")) } icon: { Image(systemName: "ladybug.fill") }
                    .foregroundStyle(AppColors.warning(colorScheme))
            case .extreme:
                Label { Text(loc.localized("logging.maximumLogging")) } icon: { Image(systemName: "bolt.fill") }
                    .foregroundStyle(AppColors.accentTertiary)
            }
        }
        .font(.caption)
    }
}

@MainActor
final class LoggingSettingsViewModel: ObservableObject {
    @Published var currentLogFilePath: String = ""
    @Published var currentLogFileSize: String = ""
    @Published var totalLogFileSize: String = ""
    @Published var currentLogFileAge: String = ""
    @Published var hasCustomLogFolder: Bool = false

    private let loc = LocalizationManager.shared

    init() {}

    func refreshInfo() {
        currentLogFilePath = LogManager.shared.currentLogURL.path
        currentLogFileSize = LogManager.shared.currentLogFileSizeString
        totalLogFileSize = LogManager.shared.totalLogFileSizeString
        currentLogFileAge = LogManager.shared.currentLogFileAgeString
        hasCustomLogFolder = LogManager.shared.customLogFolderURL != nil
    }

    func changeLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc.localized("logging.selectLogFolder")
        panel.message = loc.localized("logging.selectLogFolderMessage")

        if panel.runModal() == .OK, let url = panel.url {
            LogManager.shared.setLogFolder(url)
            refreshInfo()
        }
    }

    func resetToDefaultFolder() {
        LogManager.shared.resetToDefaultLogFolder()
        refreshInfo()
    }

    func showLogInFinder() {
        LogManager.shared.showLogInFinder()
    }

    func clearAllLogs() {
        let alert = NSAlert()
        alert.addButton(withTitle: loc.localized("logging.clearAll"))
        alert.addButton(withTitle: loc.localized("logging.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        LoggerService.shared.clearAllLogs()
        refreshInfo()
    }

    func trimOldLogs() {
        LoggerService.shared.trimOldEntries(olderThanDays: 7)
        refreshInfo()
    }
}

import SwiftUI
import AppKit

struct LoggingSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedLevel: LogLevel = .none

    @StateObject private var viewModel = LoggingSettingsViewModel()

    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?
    @ObservedObject private var loc = LocalizationManager.shared

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        if SettingsSearchRuntime.pageMatches(.logging, query: searchText) { return true }
        return SettingsIndex.matches(haystack: keywords, query: searchText)
    }

    private func sectionVisible(_ id: String) -> Bool {
        guard let scope = scopedSectionID else { return true }
        return scope == id || scope == id.replacingOccurrences(of: "section-", with: "")
    }

    var body: some View {
        Group {
            if contentLoaded {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            if !isSearching {
                                statPillsRow
                            }

                            settingsCard(
                                id: "section-levels",
                                title: loc.localized("logging.logLevel"),
                                icon: "slider.vertical.3",
                                keywords: "logging log debug console output level verbosity info extreme"
                            ) {
                                Picker(loc.localized("logging.logLevel"), selection: $selectedLevel) {
                                    ForEach(LogLevel.allCases, id: \.self) { level in
                                        Text(level.description).tag(level)
                                    }
                                }
                                .pickerStyle(.segmented)

                                logLevelDescription
                            }

                            settingsCard(
                                id: "section-files",
                                title: loc.localized("logging.logFileLocation"),
                                icon: "folder",
                                keywords: "logging file folder location path size archive"
                            ) {
                                LabeledContent(loc.localized("logging.location")) {
                                    HStack(spacing: AppSpacing.sm) {
                                        Text(viewModel.currentLogFilePath)
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        SettingsActionButton(loc.localized("logging.showInFinder")) {
                                            viewModel.showLogInFinder()
                                        }
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
                                    SettingsActionButton(loc.localized("logging.changeLocation")) {
                                        viewModel.changeLogFolder()
                                    }

                                    if viewModel.hasCustomLogFolder {
                                        SettingsActionButton(loc.localized("logging.reset")) {
                                            viewModel.resetToDefaultFolder()
                                        }
                                    }
                                }
                            }

                            settingsCard(
                                id: "section-maintenance",
                                title: loc.localized("logging.logMaintenance"),
                                icon: "trash",
                                keywords: "logging maintenance clear trim delete archive rotation size"
                            ) {
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
                                    SettingsActionButton(loc.localized("logging.trimOldEntries")) {
                                        viewModel.trimOldLogs()
                                    }

                                    SettingsActionButton(loc.localized("logging.clearAllLogs")) {
                                        viewModel.clearAllLogs()
                                    }
                                }
                            }

                            if isSearching && !hasMatchingSections {
                                noResultsView
                            }

                            Spacer(minLength: AppSpacing.xl5)
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: focusedSectionID) { _, newID in
                            guard let id = newID else { return }
                            withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                        }
                        .onChange(of: scopedSectionID) { _, newScope in
                            guard let id = newScope else { return }
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo("section-\(id)", anchor: .top) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .navigationTitle(loc.localized("logging.title"))
        .onAppear {
            let rawLevel = AppSettings.get("log_level", type: String.self) ?? "info"
            selectedLevel = LogLevel(rawValue: rawLevel) ?? .info
            viewModel.refreshInfo()
            contentLoaded = true
        }
        .onChange(of: selectedLevel) { _, newValue in
            LoggerService.shared.setLevel(newValue)
            AppSettings.set("log_level", value: newValue.rawValue)
        }
    }

    @State private var contentLoaded = false

    // MARK: - Card Helper

    @ViewBuilder
    private func settingsCard<Content: View>(
        id: String,
        title: String,
        icon: String,
        keywords: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if sectionVisible(id) && matchesSearch(keywords) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                    Text(title)
                        .font(AppTypography.headingSmall)
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                }
                content()
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xl)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
            .cardHoverEffect(colorScheme: colorScheme)
            .id(id)
        }
    }

    // MARK: - Stat Pills

    private var statPillsRow: some View {
        HStack(spacing: AppSpacing.md) {
            SettingsStatPill(item: .init(
                id: "logLevel",
                number: selectedLevel.description,
                label: "level",
                icon: "slider.vertical.3"
            ))
        }
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Helpers

    private var hasMatchingSections: Bool {
        matchesSearch("logging log debug console output level verbosity info extreme") ||
        matchesSearch("logging file folder location path size archive") ||
        matchesSearch("logging maintenance clear trim delete archive rotation size")
    }

    private var noResultsView: some View {
        VStack {
            Text(loc.localized("logging.noMatchingSettings") + " \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.xl2)
        }
        .frame(maxWidth: .infinity)
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

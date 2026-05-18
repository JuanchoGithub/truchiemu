import SwiftUI
import AppKit

// MARK: - LoggingSettingsView

struct LoggingSettingsView: View {
    @State private var selectedLevel: LogLevel = .none
    @State private var coreLogLevel: CoreLogLevel = .warn
    
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
        return keywords.localizedLowercase.fuzzyMatch(searchText) || 
               keywords.localizedLowercase.contains(searchText.lowercased())
    }
    
    var body: some View {
        Form {
            // Log Level Section
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
                    Label(loc.localized("logging.logLevel"), systemImage: "slider.vertical.3")
                } footer: {
                    Text(loc.localized("logging.logLevelDescription"))
                }
            }
            
            // Core Logging Section
            if !isSearching || matchesSearch("logging core libretro emulation debug") {
                Section {
                    Picker(loc.localized("logging.coreLogLevel"), selection: $coreLogLevel) {
                        ForEach(CoreLogLevel.allCases, id: \.self) { level in
                            Text(level.name).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text(loc.localized("logging.coreLoggingDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(loc.localized("logging.coreLogging"), systemImage: "cpu")
                }
            }
            
            // Log File Location Section
            if !isSearching || matchesSearch("logging file folder location path size archive") {
                Section {
                    LabeledContent(loc.localized("logging.location")) {
                        Text(viewModel.currentLogFilePath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    
                    LabeledContent(loc.localized("logging.currentFile")) {
                        Text("\(viewModel.currentLogFileSize) • \(viewModel.currentLogFileAge)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent(loc.localized("logging.totalLogSize")) {
                        Text(viewModel.totalLogFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Button(action: viewModel.changeLogFolder) {
                            Label(loc.localized("logging.changeLocation"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        Button(action: viewModel.showLogInFinder) {
                            Label(loc.localized("logging.showInFinder"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if viewModel.hasCustomLogFolder {
                            Button(action: viewModel.resetToDefaultFolder) {
                                Label(loc.localized("logging.reset"), systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    if viewModel.hasCustomLogFolder {
                        Text(loc.localized("logging.customLocationDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(loc.localized("logging.logFileLocation"), systemImage: "folder.fill")
                }
            }
            
            // Log Maintenance Section
            if !isSearching || matchesSearch("logging maintenance clear trim delete archive rotation size") {
                Section {
                    HStack {
                        Button(action: viewModel.clearAllLogs) {
                            Label(loc.localized("logging.clearAllLogs"), systemImage: "trash.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                        
                        Spacer()
                        
                        Button(action: viewModel.trimOldLogs) {
                            Label(loc.localized("logging.trimOldEntries"), systemImage: "scissors")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text(loc.localized("logging.maintenanceDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    LabeledContent(loc.localized("logging.maxFileSize")) {
                        Text(loc.localized("logging.fiveMB"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent(loc.localized("logging.autoRotation")) {
                        Text(loc.localized("logging.enabled"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent(loc.localized("logging.ageLimit")) {
                        Text(loc.localized("logging.sevenDays"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(loc.localized("logging.logMaintenance"), systemImage: "trash")
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text(loc.localized("logging.noMatchingSettings") + " \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
.formStyle(.grouped)
        .navigationTitle(loc.localized("logging.title"))
        .onAppear {
            let rawLevel = AppSettings.get("log_level", type: String.self) ?? "info"
            selectedLevel = LogLevel(rawValue: rawLevel) ?? .info
            
            let rawCoreLevel = AppSettings.get("core_log_level", type: Int.self) ?? 1
            coreLogLevel = CoreLogLevel(rawValue: rawCoreLevel) ?? .warn
            
            viewModel.refreshInfo()
        }
        .onChange(of: selectedLevel) { _, newValue in
            LoggerService.shared.setLevel(newValue)
            AppSettings.set("log_level", value: newValue.rawValue)
        }
        .onChange(of: coreLogLevel) { _, newValue in
            SystemPreferences.shared.coreLogLevel = newValue
            AppSettings.set("core_log_level", value: newValue.rawValue)
        }
    }
    
    private var hasMatchingSections: Bool {
        matchesSearch("logging log debug console output level verbosity info extreme") ||
        matchesSearch("logging core libretro emulation debug") ||
        matchesSearch("logging file folder location path size archive") ||
        matchesSearch("logging maintenance clear trim delete archive rotation size")
    }
    
    private var logLevelDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch selectedLevel {
            case .none:
                Label(loc.localized("logging.noLogsRecorded"), systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .info:
                Label(loc.localized("logging.generalLogs"), systemImage: "info.circle.fill")
                    .foregroundStyle(AppColors.brandAccent)
            case .debug:
                Label(loc.localized("logging.detailedLogs"), systemImage: "ladybug.fill")
                    .foregroundStyle(.orange)
            case .extreme:
                Label(loc.localized("logging.maximumLogging"), systemImage: "bolt.fill")
                    .foregroundStyle(.purple)
            }
        }
        .font(.caption)
    }
}

// MARK: - ViewModel

@MainActor
final class LoggingSettingsViewModel: ObservableObject {
    @Published var currentLogFilePath: String = ""
    @Published var currentLogFileSize: String = ""
    @Published var totalLogFileSize: String = ""
    @Published var currentLogFileAge: String = ""
    @Published var hasCustomLogFolder: Bool = false
    
    private let loc = LocalizationManager.shared
    
    init() {
        refreshInfo()
    }
    
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

import SwiftUI
import AppKit

// MARK: - LoggingSettingsView

struct LoggingSettingsView: View {
    @State private var selectedLevel: LogLevel = .none
    @State private var coreLogLevel: CoreLogLevel = .warn
    
    @StateObject private var viewModel = LoggingSettingsViewModel()
    
    @Binding var searchText: String
    
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
                    Picker("Log Level", selection: $selectedLevel) {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.description).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    logLevelDescription
                } header: {
                    Label("Log Level", systemImage: "slider.vertical.3")
                } footer: {
                    Text("Controls the verbosity of application logs. Higher levels include all lower-level logs.")
                }
            }
            
            // Core Logging Section
            if !isSearching || matchesSearch("logging core libretro emulation debug") {
                Section {
                    Picker("Core Log Level", selection: $coreLogLevel) {
                        ForEach(CoreLogLevel.allCases, id: \.self) { level in
                            Text(level.name).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Controls the verbosity of logs from the emulation core (libretro). Set this alongside App Log Level for comprehensive troubleshooting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Core Logging", systemImage: "cpu")
                }
            }
            
            // Log File Location Section
            if !isSearching || matchesSearch("logging file folder location path size archive") {
                Section {
                    LabeledContent("Location") {
                        Text(viewModel.currentLogFilePath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    
                    LabeledContent("Current file") {
                        Text("\(viewModel.currentLogFileSize) • \(viewModel.currentLogFileAge)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Total log size") {
                        Text(viewModel.totalLogFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Button(action: viewModel.changeLogFolder) {
                            Label("Change...", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        Button(action: viewModel.showLogInFinder) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if viewModel.hasCustomLogFolder {
                            Button(action: viewModel.resetToDefaultFolder) {
                                Label("Reset", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    if viewModel.hasCustomLogFolder {
                        Text("Log files are being written to a custom location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Log File Location", systemImage: "folder.fill")
                }
            }
            
            // Log Maintenance Section
            if !isSearching || matchesSearch("logging maintenance clear trim delete archive rotation size") {
                Section {
                    HStack {
                        Button(action: viewModel.clearAllLogs) {
                            Label("Clear All Logs", systemImage: "trash.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                        
                        Spacer()
                        
                        Button(action: viewModel.trimOldLogs) {
                            Label("Trim Old Entries", systemImage: "scissors")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Clear All Logs deletes all log files including rotated archives. Trim Old Entries removes entries older than 7 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    LabeledContent("Max file size") {
                        Text("5 MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Auto-rotation") {
                        Text("Enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    LabeledContent("Age limit") {
                        Text("7 days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Log Maintenance", systemImage: "trash")
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("No matching settings found for \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
.formStyle(.grouped)
        .navigationTitle("Logging")
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
                Label("No logs will be recorded anywhere", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .info:
                Label("General logs: games running, downloads, file operations, save/load states", systemImage: "info.circle.fill")
                    .foregroundStyle(.blue)
            case .debug:
                Label("Detailed logs: all info-level logs plus core options, shader activation, UI interactions, controller events", systemImage: "ladybug.fill")
                    .foregroundStyle(.orange)
            case .extreme:
                Label("Maximum logging: all debug-level logs plus every frame render, timing data, and low-level operations", systemImage: "bolt.fill")
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
        panel.prompt = "Select Log Folder"
        panel.message = "Choose a folder where log files will be stored."
        
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
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        
        LoggerService.shared.clearAllLogs()
        refreshInfo()
    }
    
    func trimOldLogs() {
        LoggerService.shared.trimOldEntries(olderThanDays: 7)
        refreshInfo()
    }
}

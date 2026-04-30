import SwiftUI
import AppKit

// MARK: - LoggingSettingsView

struct LoggingSettingsView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Log Level Section
                if !isSearching || matchesSearch("logging log debug console output level verbosity info extreme") {
                    logLevelSection
                }
                
                // Core Logging Section
                if !isSearching || matchesSearch("logging core libretro emulation debug") {
                    coreLoggingSection
                }
                
                // Log File Location Section
                if !isSearching || matchesSearch("logging file folder location path size archive") {
                    logFileSection
                }
                
                // Log Maintenance Section
                if !isSearching || matchesSearch("logging maintenance clear trim delete archive rotation size") {
                    logMaintenanceSection
                }
                
                // No results message
                if isSearching && !hasMatchingSections {
                    VStack {
                        Text("No matching settings found for \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Logging")
        .onAppear {
            viewModel.refreshInfo()
        }
    }
    
    private var hasMatchingSections: Bool {
        matchesSearch("logging log debug console output level verbosity info extreme") ||
        matchesSearch("logging core libretro emulation debug") ||
        matchesSearch("logging file folder location path size archive") ||
        matchesSearch("logging maintenance clear trim delete archive rotation size")
    }
    
    // MARK: - Log Level Section
    
    private var logLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.vertical.3")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Log Level")
                    .font(.headline)
            }
            
            VStack(spacing: 0) {
                Picker("Log Level", selection: $viewModel.selectedLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.description).tag(level)
                    }
                }
                .onChange(of: viewModel.selectedLevel) { _, newValue in
                    LoggerService.shared.setLevel(newValue)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    logLevelDescription
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
        }
    }
    
    // MARK: - Core Logging Section
    
    private var coreLoggingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Core Logging Level")
                    .font(.headline)
            }
            
            VStack(spacing: 0) {
                Picker("Core Log Level", selection: $viewModel.coreLogLevel) {
                    ForEach(CoreLogLevel.allCases, id: \.self) { level in
                        Text(level.name).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    levelDescIcon("info.circle.fill", .blue, "Controls the verbosity of logs from the emulation core itself (libretro core)")
                    levelDescIcon("doc.badge.gearshape", .purple, "Affects core-level debug output; set this alongside App Log Level for comprehensive troubleshooting")
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
        }
    }
    
    // MARK: - Log File Location Section
    
    private var logFileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Log File Location")
                    .font(.headline)
            }
            
            VStack(spacing: 16) {
                // Header with change button
                HStack {
                    Spacer()
                    Button(action: viewModel.changeLogFolder) {
                        Label("Change...", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Current path display
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.currentLogFilePath)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("File size: \(viewModel.currentLogFileSize) | Last modified: \(viewModel.currentLogFileAge)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: viewModel.showLogInFinder) {
                        Label("Show Log in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if viewModel.hasCustomLogFolder {
                        Button(action: viewModel.resetToDefaultFolder) {
                            Label("Reset to Default", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                // Warning about custom location
                if viewModel.hasCustomLogFolder {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Custom log location")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text("Log files are being written to a custom location. Reset to default to use the standard Application Support folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
        }
    }
    
    // MARK: - Log Maintenance Section
    
    private var logMaintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Log Maintenance")
                    .font(.headline)
            }
            
            VStack(spacing: 0) {
                Button(action: viewModel.clearAllLogs) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clear All Logs")
                                .font(.body)
                            Text("Delete all log files including rotated archives")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                
                Button(action: viewModel.trimOldLogs) {
                    HStack(spacing: 12) {
                        Image(systemName: "scissors")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trim Old Entries")
                                .font(.body)
                            Text("Remove log entries older than 7 days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total log size (all files)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.totalLogFileSize)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Text("Maximum log size: 5 MB per file | Auto-rotation: enabled | Age limit: 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
        }
    }
    
    // MARK: - Helper Views
    
    private var logLevelDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.selectedLevel {
            case .none:
                levelDescIcon("xmark.circle.fill", .red, "No logs will be recorded anywhere")
            case .info:
                levelDescIcon("info.circle.fill", .blue, "General logs: games running, downloads, file operations, save/load states")
            case .debug:
                levelDescIcon("ladybug.fill", .orange, "Detailed logs: all info-level logs plus core options, shader activation, UI interactions, controller events")
            case .extreme:
                levelDescIcon("bolt.fill", .purple, "Maximum logging: all debug-level logs plus every frame render, timing data, and low-level operations")
            }
        }
    }
    
    private func levelDescIcon(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .padding(.top, 4)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
final class LoggingSettingsViewModel: ObservableObject {
    @Published var selectedLevel: LogLevel = .none
    @Published var coreLogLevel: CoreLogLevel = SystemPreferences.shared.coreLogLevel { didSet { SystemPreferences.shared.coreLogLevel = coreLogLevel } }
    @Published var currentLogFilePath: String = ""
    @Published var currentLogFileSize: String = ""
    @Published var totalLogFileSize: String = ""
    @Published var currentLogFileAge: String = ""
    @Published var hasCustomLogFolder: Bool = false
    
    private var refreshTimer: Timer?
    
    init() {
        // Default to INFO log level instead of NONE
        let rawLevel = AppSettings.get("log_level", type: String.self) ?? "info"
        selectedLevel = LogLevel(rawValue: rawLevel) ?? .info
        LoggerService.shared.setLevel(selectedLevel)
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

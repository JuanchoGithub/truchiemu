import SwiftUI
import AppKit

// MARK: - LoggingSettingsView

struct LoggingSettingsView: View {
    @StateObject private var viewModel = LoggingSettingsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Log Level Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Log Level", systemImage: "slider.vertical.3")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 0) {
                        Picker("Log Level", selection: $viewModel.selectedLevel) {
                            ForEach(LogLevel.allCases, id: \.self) { level in
                                Text(level.description).tag(level)
                            }
                        }
                        .onChange(of: viewModel.selectedLevel) { newValue in
                            LoggerService.shared.setLevel(newValue)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            logLevelDescription
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .padding(.top, 4)
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
                
                // Log File Location Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Log File Location", systemImage: "folder.fill")
                            .font(.headline)
                        Spacer()
                        
                        Button(action: viewModel.changeLogFolder) {
                            Label("Change...", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    VStack(spacing: 0) {
                        // Current path display
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.currentLogFilePath)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                Text("File size: \(viewModel.currentLogFileSize) | Last modified: \(viewModel.currentLogFileAge)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        
                        Divider()
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            Button(action: viewModel.showLogInFinder) {
                                Label("Show Log in Finder", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(action: viewModel.showLogFolderInFinder) {
                                Label("Show Folder in Finder", systemImage: "folder.badge.gearshape")
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        
                        Divider()
                        
                        // Warning about custom location
                        if viewModel.hasCustomLogFolder {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Custom log location")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                Text("Log files are being written to a custom location. Reset to default to use the standard Application Support folder.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
                
                // Log Maintenance Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Log Maintenance", systemImage: "trash")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 0) {
                        Button(action: viewModel.clearAllLogs) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                VStack(alignment: .leading) {
                                    Text("Clear All Logs")
                                        .font(.body)
                                    Text("Delete all log files including rotated archives")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        Button(action: viewModel.trimOldLogs) {
                            HStack {
                                Image(systemName: "scissors")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading) {
                                    Text("Trim Old Entries")
                                        .font(.body)
                                    Text("Remove log entries older than 7 days")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total log size (all files)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(viewModel.totalLogFileSize)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                            Text("Maximum log size: 5 MB per file | Auto-rotation: enabled | Age limit: 7 days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Logging")
        .onAppear {
            viewModel.refreshInfo()
        }
    }
    
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
                .foregroundColor(color)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
final class LoggingSettingsViewModel: ObservableObject {
    @Published var selectedLevel: LogLevel = .none
    @Published var currentLogFilePath: String = ""
    @Published var currentLogFileSize: String = ""
    @Published var totalLogFileSize: String = ""
    @Published var currentLogFileAge: String = ""
    @Published var hasCustomLogFolder: Bool = false
    
    private var refreshTimer: Timer?
    
    init() {
        selectedLevel = LoggerService.shared.currentLevel
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
    
    func showLogFolderInFinder() {
        LogManager.shared.showLogFolderInFinder()
    }
    
    func clearAllLogs() {
        let alert = NSAlert()
        alert.messageText = "Clear All Logs?"
        alert.informativeText = "This will delete all log files, including rotated archives. This action cannot be undone."
        alert.alertStyle = .warning
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
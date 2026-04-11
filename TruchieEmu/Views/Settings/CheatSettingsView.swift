import SwiftUI

// MARK: - Cheat Settings View

/// Settings view for managing cheat downloads and preferences
struct CheatSettingsView: View {
    @StateObject private var downloadService = CheatDownloadService.shared
    @StateObject private var cheatManager = CheatManagerService.shared
    @ObservedObject var prefs = SystemPreferences.shared
    
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    @State private var isExporting = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Cheat Download Section
                downloadSection
                
                // Cheat Preferences
                preferencesSection
                
                // Cheat Statistics
                statisticsSection
                
                // Actions
                actionsSection
            }
            .padding(16)
        }
        .navigationTitle("Cheats")
    }
    
    // MARK: - Download Section
    
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Cheat Database")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // Header with last updated
                HStack {
                    Text("Download Cheats from Libretro Database")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if let lastDate = downloadService.lastDownloadDate {
                        Text("Last updated: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("This will download cheat files from the libretro-database repository. Files are organized by system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                
                // Progress indicator
                if downloadService.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        // Progress bar with counts
                        HStack {
                            ProgressView(value: Double(downloadService.currentDownloadedCount), total: max(Double(downloadService.totalItemsToDownload), 1))
                                .progressViewStyle(.linear)
                            
                            Text("\(downloadService.currentDownloadedCount)/\(downloadService.totalItemsToDownload)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        
                        // Status with currently downloading count
                        HStack(spacing: 4) {
                            Text(downloadService.downloadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if downloadService.currentlyDownloadingCount > 0 {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text("\(downloadService.currentlyDownloadingCount) downloading")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        // Download log (scrollable, limited height)
                        if !downloadService.downloadLog.isEmpty {
                            DownloadLogView(logEntries: downloadService.downloadLog)
                                .frame(height: 120)
                        }
                    }
                }
                
                // Download buttons
                HStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await downloadService.downloadAllCheats()
                            switch result {
                            case .success(_, _, let message):
                                downloadResult = message
                            case .failed(let message):
                                downloadResult = message
                            case .alreadyDownloading:
                                break
                            }
                        }
                    } label: {
                        Label("Download All Cheats", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(downloadService.isDownloading)
                    
                    // System-specific download
                    Menu {
                        ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { system in
                            Button(system.name) {
                                Task {
                                    do {
                                        let count = try await downloadService.downloadCheatsForSystem(system.id)
                                        if count > 0 {
                                            downloadResult = "Downloaded \(count) cheat file(s) for \(system.name)"
                                        } else {
                                            downloadResult = "No cheat files found for \(system.name)"
                                        }
                                    } catch {
                                        downloadResult = "Download failed: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Download for System...", systemImage: "gamecontroller")
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(downloadService.isDownloading)
                }
            }
            
            // Download result message
            if let result = downloadResult {
                resultBanner(result: result)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
    
    private func resultBanner(result: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(result.contains("Downloaded") ? .green : .red)
            Text(result)
                .font(.caption)
            Spacer()
            Button("Dismiss") {
                downloadResult = nil
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(result.contains("Downloaded") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Cheat Preferences")
                    .font(.headline)
            }
            
            VStack(spacing: 0) {
                Toggle(isOn: $prefs.applyCheatsOnLaunch) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apply Cheats on Launch")
                            .font(.body)
                        Text("Automatically apply enabled cheats when starting a game")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .onChange(of: prefs.applyCheatsOnLaunch) { 
                    AppSettings.setBool("applyCheatsOnLaunch", value: prefs.applyCheatsOnLaunch)
                }
                
                Divider()
                
                Toggle(isOn: $prefs.showCheatNotifications) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cheat Notifications")
                            .font(.body)
                        Text("Show notifications when cheats are activated during gameplay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .onChange(of: prefs.showCheatNotifications) {
                    AppSettings.setBool("showCheatNotifications", value: prefs.showCheatNotifications)
                }   
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Cheat Statistics")
                    .font(.headline)
            }
            
            HStack(spacing: 12) {
                statCard(
                    icon: "arrow.down.circle",
                    value: "\(downloadService.getDownloadedCheatCount())",
                    label: "Downloaded Files",
                    accent: .blue
                )
                
                statCard(
                    icon: "gamecontroller",
                    value: formatByteSize(downloadService.getDownloadedCheatSize()),
                    label: "Storage Used",
                    accent: .purple
                )
                
                statCard(
                    icon: "wand.and.stars",
                    value: AppSettings.getData("cheats_v2") != nil ? "Yes" : "No",
                    label: "Custom Cheats",
                    accent: .orange
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
    
    private func statCard(icon: String, value: String, label: String, accent: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(accent)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Actions")
                    .font(.headline)
            }
            
            VStack(spacing: 0) {
                Button {
                    showClearConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clear Downloaded Cheats")
                                .font(.body)
                            Text("Remove all downloaded cheat files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                
                Button {
                    openCheatDirectory()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Cheats Folder")
                                .font(.body)
                            Text("View downloaded cheat files in Finder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .confirmationDialog(
            "Clear Downloaded Cheats",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                do {
                    try downloadService.clearDownloadedCheats()
                } catch {
                    LoggerService.debug(category: "Cheats", "Failed to clear cheats: \(error)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded cheat files. Your custom cheats will not be affected.")
        }
    }
    
    // MARK: - Helpers
    
    private func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func openCheatDirectory() {
        let cheatsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TruchieEmu/cheats_downloaded")
        
        NSWorkspace.shared.selectFile(cheatsDir.path, inFileViewerRootedAtPath: cheatsDir.path)
    }
}

// MARK: - Download Log View

/// Shows a scrollable log of download entries with success/error status
struct DownloadLogView: View {
    let logEntries: [CheatDownloadLogEntry]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logEntries) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
                .onChange(of: logEntries.count) { _, _ in
                    // Auto-scroll to bottom when new entries are added
                    if let lastId = logEntries.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

/// Single row in the download log
struct LogEntryRow: View {
    let entry: CheatDownloadLogEntry
    
    var body: some View {
        HStack(spacing: 4) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 10))
            
            // File name (truncated if needed)
            Text(entry.fileName)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
            
            // Status message (shortened)
            Text(statusMessage)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .id(entry.id)
    }
    
    private var statusIcon: String {
        switch entry.status {
        case .inProgress:
            return "arrow.down.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch entry.status {
        case .inProgress:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var statusMessage: String {
        switch entry.status {
        case .inProgress:
            return "Downloading..."
        case .success:
            return "OK"
        case .failed(let reason):
            // Show a shortened error message
            let shortReason = reason.count > 30 ? reason.prefix(30) + "..." : reason
            return String(shortReason)
        }
    }
}

// MARK: - Preview

#Preview {
    CheatSettingsView()
}

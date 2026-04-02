import SwiftUI

// MARK: - Cheat Settings View

/// Settings view for managing cheat downloads and preferences
struct CheatSettingsView: View {
    @StateObject private var downloadService = CheatDownloadService.shared
    @StateObject private var cheatManager = CheatManagerService.shared
    @ObservedObject var prefs = SystemPreferences.shared
    
    @State private var downloadResult: CheatDownloadResult?
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
            .padding()
        }
        .navigationTitle("Cheats")
    }
    
    // MARK: - Download Section
    
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cheat Database", systemImage: "network")
                    .font(.headline)
                Spacer()
                if let lastDate = downloadService.lastDownloadDate {
                    Text("Last updated: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download Cheats from Libretro Database")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("This will download cheat files from the libretro-database repository. Files are organized by system.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                // Progress indicator
                if downloadService.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: downloadService.downloadProgress)
                            .progressViewStyle(.linear)
                        
                        Text(downloadService.downloadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                
                // Download buttons
                HStack(spacing: 12) {
                    Button {
                        Task {
                            downloadResult = await downloadService.downloadAllCheats()
                        }
                    } label: {
                        Label("Download All Cheats", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(downloadService.isDownloading)
                    
                    // System-specific download
                    Menu {
                        ForEach(SystemDatabase.systems.sorted(by: { $0.name < $1.name })) { system in
                            Button(system.name) {
                                Task {
                                    downloadResult = await downloadService.downloadCheatsForSystem(system.id)
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
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            
            // Download result message
            if let result = downloadResult {
                resultBanner(result: result)
            }
        }
    }
    
    private func resultBanner(result: CheatDownloadResult) -> some View {
        Group {
            switch result {
            case .success(let downloaded, let failed, let message):
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(message)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        downloadResult = nil
                    }
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            case .failed(let message):
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        downloadResult = nil
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            case .alreadyDownloading:
                EmptyView()
            }
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cheat Preferences", systemImage: "gearshape")
                .font(.headline)
            
            VStack(spacing: 0) {
                Toggle(isOn: $prefs.autoLoadCheats) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-load Cheats")
                            .font(.body)
                        Text("Automatically load available cheats when launching games")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                
                Divider()
                
                Toggle(isOn: $prefs.applyCheatsOnLaunch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apply Cheats on Launch")
                            .font(.body)
                        Text("Automatically apply enabled cheats when starting a game")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                
                Divider()
                
                Toggle(isOn: $prefs.showCheatNotifications) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cheat Notifications")
                            .font(.body)
                        Text("Show notifications when cheats are activated during gameplay")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cheat Statistics", systemImage: "chart.bar")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatCard(
                    icon: "arrow.down.circle",
                    iconColor: .blue,
                    value: "\(downloadService.getDownloadedCheatCount())",
                    label: "Downloaded Files"
                )
                
                StatCard(
                    icon: "gamecontroller",
                    iconColor: .purple,
                    value: "\(formatByteSize(downloadService.getDownloadedCheatSize()))",
                    label: "Storage Used"
                )
                
                StatCard(
                    icon: "wand.and.stars",
                    iconColor: .orange,
                    value: "\(UserDefaults.standard.data(forKey: "cheats_v2") != nil ? "Yes" : "No")",
                    label: "Custom Cheats"
                )
            }
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            
            VStack(spacing: 0) {
                Button {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        VStack(alignment: .leading) {
                            Text("Clear Downloaded Cheats")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Remove all downloaded cheat files")
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
                
                Button {
                    openCheatDirectory()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Open Cheats Folder")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("View downloaded cheat files in Finder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .confirmationDialog(
            "Clear Downloaded Cheats",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                do {
                    try downloadService.clearDownloadedCheats()
                } catch {
                    print("Failed to clear cheats: \(error)")
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
        
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cheatsDir.path)
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct CheatSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CheatSettingsView()
    }
}
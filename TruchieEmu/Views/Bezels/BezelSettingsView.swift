import SwiftUI

// MARK: - Bezel Settings View

/// Settings view for managing bezel downloads, storage location, and preferences.
struct BezelSettingsView: View {
    @StateObject private var apiService = BezelAPIService.shared
    @StateObject private var storageManager = BezelStorageManager.shared
    @StateObject private var bezelManager = BezelManager.shared
    
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    @State private var showStorageLocationPicker = false
    
    let system: SystemInfo?

    init(system: SystemInfo? = nil) {
        self.system = system
        if let system = system {
            _selectedSystem = State(initialValue: system.id)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Storage Location Section
                storageLocationSection
                
                // Bezel Download Section
                downloadSection
                
                // Bezel Statistics
                statisticsSection
                
                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Bezels")
    }
    
    // MARK: - Storage Location Section
    
    private var storageLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Storage Location", systemImage: "folder")
                .font(.headline)
            
            VStack(spacing: 0) {
                // Current location display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Location")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(storageManager.bezelRootDirectory.path)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(action: { storageManager.openInFinder() }) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("Open in Finder")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                
                Divider()
                
                // Storage mode selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Mode")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(BezelStorageMode.allCases, id: \.self) { mode in
                            storageModeRow(mode: mode)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
    
    private func storageModeRow(mode: BezelStorageMode) -> some View {
        HStack {
            Image(systemName: mode.icon)
                .foregroundColor(mode == storageManager.storageMode ? .blue : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.body)
                if mode == .libraryRelative {
                    Text("Bezels stored next to your first library folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if mode == .internalManaged {
                    Text("Bezels stored in Application Support")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if mode == storageManager.storageMode {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await switchStorageMode(to: mode)
            }
        }
    }
    
    @MainActor
    private func switchStorageMode(to mode: BezelStorageMode) async {
        guard mode != storageManager.storageMode else { return }
        
        let alert = NSAlert()
        alert.messageText = "Change Storage Location"
        
        switch mode {
        case .libraryRelative:
            alert.informativeText = "Move bezels to your library folder? This will copy all existing bezels to the new location."
            alert.addButton(withTitle: "Move Bezels")
            alert.addButton(withTitle: "Cancel")
        case .customFolder:
            alert.informativeText = "Choose a new folder for bezel storage. Existing bezels will be moved there."
            alert.addButton(withTitle: "Choose Folder")
            alert.addButton(withTitle: "Cancel")
        case .internalManaged:
            alert.informativeText = "Move bezels to Application Support? Existing bezels will be moved."
            alert.addButton(withTitle: "Move Bezels")
            alert.addButton(withTitle: "Cancel")
        }
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if mode == .customFolder {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.message = "Select bezel storage folder"
                
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        if storageManager.storageMode == .libraryRelative {
                            try await storageManager.migrateBezels(to: url)
                        }
                        storageManager.storageMode = .customFolder
                        storageManager.customFolderPath = url
                        AppSettings.set(BezelUserDefaultsKeys.storageMode, value: BezelStorageMode.customFolder.rawValue)
                        AppSettings.set(BezelUserDefaultsKeys.customFolderPath, value: url.path)
                        try storageManager.ensureDirectoriesExist()
                    } catch {
                        LoggerService.debug(category: "Bezel", "Failed to migrate: \(error)")
                    }
                }
            } else {
                do {
                    let newLocation: URL
                    switch mode {
                    case .libraryRelative:
                        newLocation = storageManager.libraryRelativeBezelsDirectory
                    case .internalManaged:
                        newLocation = storageManager.internalManagedDirectory
                    default:
                        newLocation = storageManager.bezelRootDirectory
                    }
                    
                    if storageManager.bezelRootDirectory != newLocation &&
                       FileManager.default.fileExists(atPath: storageManager.bezelRootDirectory.path) {
                        try await storageManager.migrateBezels(to: newLocation)
                    }
                    
                    storageManager.storageMode = mode
                    AppSettings.set(BezelUserDefaultsKeys.storageMode, value: mode.rawValue)
                    try storageManager.ensureDirectoriesExist()
                } catch {
                    LoggerService.debug(category: "Bezel", "Failed to migrate: \(error)")
                }
            }
        }
    }
    
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bezel Database", systemImage: "network")
                    .font(.headline)
                Spacer()
                if let lastDate = apiService.progressTracker.lastDownloadDate {
                    Text("Last updated: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download Bezels from The Bezel Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("This will download bezel overlays from The Bezel Project's GitHub repository. Bezels are 1920x1080 PNG images that frame your games with authentic console artwork.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                // Progress indicator
                if apiService.progressTracker.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        // Progress bar with counts
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                ProgressView(value: apiService.progressTracker.progress)
                                    .progressViewStyle(.linear)
                                
                                Text("\(apiService.progressTracker.currentDownloadedCount)/\(apiService.progressTracker.totalItemsToDownload)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            
                            // Status with currently downloading count
                            HStack(spacing: 6) {
                                Text(apiService.progressTracker.downloadStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if apiService.progressTracker.currentlyDownloadingCount > 0 {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text("\(apiService.progressTracker.currentlyDownloadingCount) downloading")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        // Download log (scrollable)
                        if !apiService.progressTracker.downloadLog.isEmpty {
                            BezelDownloadLogView(logEntries: apiService.progressTracker.downloadLog)
                                .frame(height: 120)
                        }
                    }
                    .padding(.top, 8)
                }
                
                // Download buttons and controls
                VStack(spacing: 12) {
                    // System selector and download button
                    HStack(spacing: 8) {
                        // System picker
                        Picker("System", selection: $selectedSystem) {
                            Text("All Systems").tag("all")
                            Divider()
                            ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { system in
                                Text(system.name).tag(system.id)
                            }
                        }
                        .frame(width: 150)
                        
                        // Dynamic download button
                        Button {
                            Task {
                                if selectedSystem == "all" {
                                    let result = await apiService.downloadAllSystems()
                                    downloadResult = result.message
                                } else {
                                    let result = await apiService.downloadAllBezels(systemID: selectedSystem)
                                    downloadResult = result.message
                                }
                            }
                        } label: {
                            Label(downloadButtonLabel, systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiService.progressTracker.isRunning)
                    }
                    
                    // Stop button & clear log (only when downloading)
                    if apiService.progressTracker.isRunning {
                        HStack(spacing: 8) {
                            Button {
                                apiService.progressTracker.cancelDownload()
                            } label: {
                                Label("Stop Download", systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            
                            Button {
                                apiService.progressTracker.resetLog()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .help("Clear download log")
                        }
                    }
                    
                     // System quick download menu
                     if let system = system {
                         Button {
                             Task {
                                 let result = await apiService.downloadAllBezels(systemID: system.id)
                                 downloadResult = result.message
                             }
                         } label: {
                             Label("Download \(system.name) Bezels", systemImage: "arrow.down.circle")
                                 .frame(maxWidth: .infinity)
                         }
                         .buttonStyle(.borderedProminent)
                         .disabled(apiService.progressTracker.isRunning)
                     } else {
                         Menu {
                             ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { system in
                                 Button(system.name) {
                                     selectedSystem = system.id
                                     Task {
                                         let result = await apiService.downloadAllBezels(systemID: system.id)
                                         downloadResult = result.message
                                     }
                                 }
                             }
                         } label: {
                             Label("Quick Download...", systemImage: "gamecontroller")
                         }
                         .menuStyle(.borderlessButton)
                         .disabled(apiService.progressTracker.isRunning)
                     }
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
    
    // MARK: - Dynamic Button Label
    
    /// Generates the button label based on selected system
    private var downloadButtonLabel: String {
        if selectedSystem == "all" {
            return "Download All Bezels"
        } else if let system = SystemDatabase.systems.first(where: { $0.id == selectedSystem }) {
            return "Download \(system.name) Bezels"
        }
        return "Download Bezels"
    }
    
    private func resultBanner(result: String) -> some View {
        HStack {
            Image(systemName: result.contains("Downloaded") ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundColor(result.contains("Downloaded") ? .green : .red)
            Text(result)
                .font(.caption)
            Spacer()
            Button("Dismiss") {
                downloadResult = nil
            }
        }
        .padding(10)
        .background(result.contains("Downloaded") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bezel Statistics", systemImage: "chart.bar")
                .font(.headline)
            
            HStack(spacing: 16) {
                bezelStatCard(
                    icon: "photo.on.rectangle",
                    iconColor: .blue,
                    value: "\(storageManager.downloadedBezelCount())",
                    label: "Downloaded Bezels"
                )
                
                bezelStatCard(
                    icon: "externaldrive",
                    iconColor: .purple,
                    value: formatByteSize(storageManager.bezelStorageSize()),
                    label: "Storage Used"
                )
                
                bezelStatCard(
                    icon: "gamecontroller",
                    iconColor: .orange,
                    value: "\(BezelSystemMapping.configurations.count)",
                    label: "Supported Systems"
                )
            }
        }
    }
    
    private func bezelStatCard(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
            
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
                            Text("Clear All Bezels")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Remove all downloaded bezel files")
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
                    storageManager.openInFinder()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Open Bezels Folder")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("View bezel files in Finder")
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
            "Clear All Bezels",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                do {
                    try storageManager.clearAllBezels()
                } catch {
                    LoggerService.debug(category: "Bezel", "Failed to clear bezels: \(error)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded bezel files. You can re-download them at any time.")
        }
    }
    
    // MARK: - Helpers
    
    private func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

struct BezelSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        BezelSettingsView()
    }
}
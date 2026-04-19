import SwiftUI

// MARK: - Bezel Settings View

struct BezelSettingsView: View {
    @StateObject private var apiService = BezelAPIService.shared
    @StateObject private var storageManager = BezelStorageManager.shared
    @StateObject private var bezelManager = BezelManager.shared
    
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    
    let system: SystemInfo?

    init(system: SystemInfo? = nil) {
        self.system = system
        if let system = system {
            _selectedSystem = State(initialValue: system.id)
        }
    }
    
    var body: some View {
        Form {
            // MARK: - 1. Statistics Dashboard
            Section {
                HStack(spacing: 20) {
                    statTile(
                        value: "\(storageManager.downloadedBezelCount())",
                        label: "Bezels",
                        icon: "photo.on.rectangle",
                        color: .blue
                    )
                    Divider().frame(height: 40)
                    statTile(
                        value: formatByteSize(storageManager.bezelStorageSize()),
                        label: "Storage",
                        icon: "externaldrive.fill",
                        color: .purple
                    )
                    Divider().frame(height: 40)
                    statTile(
                        value: "\(BezelSystemMapping.configurations.count)",
                        label: "Systems",
                        icon: "gamecontroller.fill",
                        color: .orange
                    )
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } header: {
                Text("Library Overview")
            }
            
            // MARK: - 2. Storage Configuration
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Path")
                                .font(.subheadline).fontWeight(.medium)
                            Text(storageManager.bezelRootDirectory.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button { storageManager.openInFinder() } label: {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                    
                    Divider()
                    
                    Picker("Storage Mode", selection: Binding(
                        get: { storageManager.storageMode },
                        set: { newValue in Task { await switchStorageMode(to: newValue) } }
                    )) {
                        ForEach(BezelStorageMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Storage Location", systemImage: "folder.fill")
            } footer: {
                Text(storageModeDescription)
            }
            
            // MARK: - 3. Download Database
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if apiService.progressTracker.isRunning {
                        bezelDownloadProgressView
                    } else {
                        bezelDownloadControls
                    }
                }
            } header: {
                Label("The Bezel Project", systemImage: "network")
            } footer: {
                if let lastDate = apiService.progressTracker.lastDownloadDate {
                    Text("Last update sync: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            
            // MARK: - 4. Maintenance
            Section("Maintenance") {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Delete All Bezel Artwork", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Bezels")
        .overlay(alignment: .bottom) {
            if let result = downloadResult {
                resultToast(result)
            }
        }
        .confirmationDialog("Clear All Bezels", isPresented: $showClearConfirmation) {
            Button("Delete Everything", role: .destructive) {
                try? storageManager.clearAllBezels()
            }
        } message: {
            Text("This will remove all downloaded PNG overlays. Your configurations will remain intact.")
        }
    }
    
    // MARK: - Subviews
    
    private var bezelDownloadProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(apiService.progressTracker.downloadStatus)
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(apiService.progressTracker.currentDownloadedCount)/\(apiService.progressTracker.totalItemsToDownload)")
                    .font(.caption.monospacedDigit())
            }
            
            ProgressView(value: apiService.progressTracker.progress)
                .progressViewStyle(.linear)
            
            HStack {
                if apiService.progressTracker.currentlyDownloadingCount > 0 {
                    Label("\(apiService.progressTracker.currentlyDownloadingCount) threads active", systemImage: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Spacer()
                Button("Stop", role: .destructive) {
                    apiService.progressTracker.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(height: 24)
            
            if !apiService.progressTracker.downloadLog.isEmpty {
                BezelDownloadLogView(logEntries: apiService.progressTracker.downloadLog)
                    .frame(height: 120)
                    .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var bezelDownloadControls: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Target System", selection: $selectedSystem) {
                    Text("All Systems").tag("all")
                    Divider()
                    ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                        Text(sys.name).tag(sys.id)
                    }
                }
                
                Button {
                    Task {
                        let result = selectedSystem == "all" ? 
                            await apiService.downloadAllSystems() : 
                            await apiService.downloadAllBezels(systemID: selectedSystem)
                        downloadResult = result.message
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            
            if let system = system {
                Button("Quick Update: \(system.name)") {
                    Task {
                        let result = await apiService.downloadAllBezels(systemID: system.id)
                        downloadResult = result.message
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
        }
        .frame(minWidth: 85)
    }

    private func resultToast(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(radius: 10)
            .padding(.bottom, 40)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { downloadResult = nil }
                }
            }
    }
    
    // MARK: - RESTORED LOGIC
    
    private var storageModeDescription: String {
        switch storageManager.storageMode {
        case .libraryRelative: return "Bezels are stored inside your ROM library folders."
        case .internalManaged: return "Bezels are managed internally in Application Support."
        case .customFolder: return "Bezels are stored in your selected custom directory."
        }
    }

    private func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
}

// MARK: - Supporting Views

struct BezelDownloadLogView: View {
    let logEntries: [BezelDownloadLogEntry]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logEntries) { entry in
                        BezelLogEntryRow(entry: entry)
                    }
                }
                .padding(6)
                .onChange(of: logEntries.count) { _, _ in
                    if let lastId = logEntries.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
            .background(Color.black.opacity(0.1))
        }
    }
}

struct BezelLogEntryRow: View {
    let entry: BezelDownloadLogEntry
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.status == .success ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(entry.status == .success ? .green : .blue)
                .font(.system(size: 10))
            
            Text(entry.fileName)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
        }
        .id(entry.id)
    }
}
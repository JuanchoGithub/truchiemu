import SwiftUI
import AppKit

// MARK: - Bezel Settings View

struct BezelSettingsView: View {
    // MARK: - Dependencies
    @ObservedObject private var apiService = BezelAPIService.shared
    @ObservedObject private var storageManager = BezelStorageManager.shared
    
    // MARK: - State
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    
    let system: SystemInfo?
    
    // MARK: - Search
    @Binding var searchText: String
    let searchKeywords: String = "bezel frame overlay monitor"

    init(system: SystemInfo? = nil, searchText: Binding<String> = .constant("")) {
        self.system = system
        self._searchText = searchText
        if let system = system {
            _selectedSystem = State(initialValue: system.id)
        }
    }
    
    // MARK: - Filtered Sections
    private var showStorageSection: Bool {
        searchText.isEmpty || "storage path folder directory".fuzzyMatch(searchText)
    }
    
    private var showDownloadsSection: Bool {
        searchText.isEmpty || "download bezels project update".fuzzyMatch(searchText)
    }
    
    private var showStatisticsSection: Bool {
        searchText.isEmpty || "statistics files space supported".fuzzyMatch(searchText)
    }
    
    private var showDangerZoneSection: Bool {
        searchText.isEmpty || "delete remove clear bezels".fuzzyMatch(searchText)
    }
    
    private var hasAnyResults: Bool {
        showStorageSection || showDownloadsSection || showStatisticsSection || showDangerZoneSection
    }
    
    var body: some View {
        Form {
            if searchText.isEmpty {
                // Show all sections normally
                storageSection
                Divider()
                downloadsSection
                Divider()
                statisticsSection
                Divider()
                dangerZoneSection
            } else {
                // Show filtered sections
                if showStorageSection {
                    storageSection
                    Divider()
                }
                if showDownloadsSection {
                    downloadsSection
                    Divider()
                }
                if showStatisticsSection {
                    statisticsSection
                    Divider()
                }
                if showDangerZoneSection {
                    dangerZoneSection
                }
                
                if !hasAnyResults {
                    noResultsView
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
        .navigationTitle("Bezel Settings")
        .confirmationDialog("Delete Bezels?", isPresented: $showClearConfirmation) {
            Button("Delete All", role: .destructive) { 
                do {
                    try storageManager.clearAllBezels()
                } catch {
                    print("Error clearing bezels: \(error)")
                }
            }
        } message: {
            Text("This will remove all downloaded images from your disk. You can re-download them later.")
        }
    }
    
    // MARK: - Section Views
    
    private var storageSection: some View {
        Section(header: Text("Storage").font(.headline)) {
            LabeledContent("Current Path") {
                Text(storageManager.bezelRootDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .help(storageManager.bezelRootDirectory.path)
            }
            
            Picker("Storage Mode", selection: Binding(
                get: { storageManager.storageMode },
                set: { newValue in
                    Task { await handleStorageMigration(to: newValue) }
                }
            )) {
                ForEach(BezelStorageMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            
            Button("Show in Finder") {
                storageManager.openInFinder()
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
    }
    
    private var downloadsSection: some View {
        Section(header: Text("Downloads").font(.headline)) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The Bezel Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Download 1080p overlays for authentic console artwork.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let lastDate = apiService.progressTracker.lastDownloadDate {
                    Text("Updated: \(lastDate.formatted(.dateTime.month().day().year()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 12) {
                HStack {
                    Picker("System", selection: $selectedSystem) {
                        Text("All Systems").tag("all")
                        Divider()
                        ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                            Text(sys.name).tag(sys.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(apiService.progressTracker.isRunning)
                    
                    Button(action: runDownload) {
                        if apiService.progressTracker.isRunning {
                            ProgressView().controlSize(.small).padding(.horizontal, 4)
                        } else {
                            Label(downloadButtonLabel, systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiService.progressTracker.isRunning)
                }
                
                if apiService.progressTracker.isRunning {
                    downloadProgressBlock
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            if let result = downloadResult {
                resultBanner(result: result)
            }
        }
    }
    
    private var statisticsSection: some View {
        Section(header: Text("Statistics").font(.headline)) {
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                GridRow {
                    statItem(label: "Files", value: "\(storageManager.downloadedBezelCount())", icon: "photo")
                    statItem(label: "Space", value: formatByteSize(storageManager.bezelStorageSize()), icon: "internaldrive")
                    statItem(label: "Supported", value: "\(BezelSystemMapping.configurations.count)", icon: "gamecontroller")
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Delete All Bezels", systemImage: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Results")
                .font(.headline)
            Text("No settings match '\(searchText)'")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Sub-views & Helpers

private extension BezelSettingsView {
    
    var downloadProgressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: apiService.progressTracker.progress)
                .progressViewStyle(.linear)
            
            HStack {
                Text(apiService.progressTracker.downloadStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(apiService.progressTracker.currentDownloadedCount)/\(apiService.progressTracker.totalItemsToDownload)")
                    .font(.caption2.monospacedDigit())
                
                Button("Stop") {
                    apiService.progressTracker.cancelDownload()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    func statItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    var downloadButtonLabel: String {
        if selectedSystem == "all" { return "Download All" }
        return "Download \(selectedSystem.capitalized)"
    }
    
    func resultBanner(result: String) -> some View {
        HStack {
            Text(result)
                .font(.caption)
            Spacer()
            Button(action: { downloadResult = nil }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(6)
    }

    func runDownload() {
        Task {
            if selectedSystem == "all" {
                let result = await apiService.downloadAllSystems()
                downloadResult = result.message
            } else {
                let result = await apiService.downloadAllBezels(systemID: selectedSystem)
                downloadResult = result.message
            }
        }
    }
    
    @MainActor
    func handleStorageMigration(to mode: BezelStorageMode) async {
        guard mode != storageManager.storageMode else { return }
        
        let alert = NSAlert()
        alert.messageText = "Change Storage Location"
        alert.informativeText = "Would you like to move your existing bezels to the new location?"
        alert.addButton(withTitle: "Move Existing")
        alert.addButton(withTitle: "Change Only")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertThirdButtonReturn { return }

        // Logic for NSOpenPanel if custom folder...
        if mode == .customFolder {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let url = panel.url {
                storageManager.customFolderPath = url
            } else {
                return
            }
        }

        if response == .alertFirstButtonReturn {
            // Perform migration logic here via storageManager
        }
        
        storageManager.storageMode = mode
    }
    
    func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

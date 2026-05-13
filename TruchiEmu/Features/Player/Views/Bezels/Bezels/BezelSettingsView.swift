import SwiftUI
import AppKit

struct BezelSettingsView: View {
    @ObservedObject private var apiService = BezelAPIService.shared
    @ObservedObject private var storageManager = BezelStorageManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    
    let system: SystemInfo?
    
    @Binding var searchText: String
    let searchKeywords: String = "bezel frame overlay monitor"

    init(system: SystemInfo? = nil, searchText: Binding<String> = .constant("")) {
        self.system = system
        self._searchText = searchText
        if let system = system {
            _selectedSystem = State(initialValue: system.id)
        }
    }
    
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
                storageSection
                downloadsSection
                statisticsSection
                dangerZoneSection
            } else {
                if showStorageSection {
                    storageSection
                }
                if showDownloadsSection {
                    downloadsSection
                }
                if showStatisticsSection {
                    statisticsSection
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
        .navigationTitle(loc.localized("bezel.settings"))
        .confirmationDialog(loc.localized("bezel.deleteBezelsTitle"), isPresented: $showClearConfirmation) {
            Button(loc.localized("bezel.deleteAll"), role: .destructive) { 
                do {
                    try storageManager.clearAllBezels()
                } catch {
                    print("Error clearing bezels: \(error)")
                }
            }
        } message: {
            Text(loc.localized("bezel.deleteAllWarning"))
        }
    }
    
    private var storageSection: some View {
        Section {
            LabeledContent(loc.localized("bezel.currentPath")) {
                Text(storageManager.bezelRootDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(storageManager.bezelRootDirectory.path)
            }
            
            Picker(loc.localized("bezel.storageMode"), selection: Binding(
                get: { storageManager.storageMode },
                set: { newValue in
                    Task { await handleStorageMigration(to: newValue) }
                }
            )) {
                ForEach(BezelStorageMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            Button(action: { storageManager.openInFinder() }) {
                Label(loc.localized("bezel.showInFinder"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            Label(loc.localized("bezel.storage"), systemImage: "folder.fill")
        }
    }
    
    private var downloadsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.localized("bezel.theBezelProject"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(loc.localized("bezel.download1080Info"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let lastDate = apiService.progressTracker.lastDownloadDate {
                Text("\(loc.localized("bezel.updated")) \(lastDate.formatted(.dateTime.month().day().year()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Picker(loc.localized("bezel.view"), selection: $selectedSystem) {
                    Text(loc.localized("bezel.allSystems")).tag("all")
                    Divider()
                    ForEach(systemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                        Text(sys.name).tag(sys.id)
                    }
                }
                .labelsHidden()
                .disabled(apiService.progressTracker.isRunning)
                
                Spacer()
                
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
            
            if let result = downloadResult {
                resultBanner(result: result)
            }
        } header: {
            Label(loc.localized("bezel.downloads"), systemImage: "arrow.down.circle.fill")
        }
    }
    
    private var statisticsSection: some View {
        Section {
            HStack(spacing: 20) {
                statTile(
                    value: "\(storageManager.downloadedBezelCount())",
                    label: loc.localized("bezel.files"),
                    icon: "photo.fill",
                    color: .blue
                )
                Divider().frame(height: 40)
                statTile(
                    value: formatByteSize(storageManager.bezelStorageSize()),
                    label: loc.localized("bezel.storageLabel"),
                    icon: "internaldrive.fill",
                    color: .purple
                )
                Divider().frame(height: 40)
                statTile(
                    value: "\(BezelSystemMapping.configurations.count)",
                    label: loc.localized("bezel.supported"),
                    icon: "gamecontroller.fill",
                    color: .orange
                )
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        } header: {
            Label(loc.localized("bezel.statistics"), systemImage: "chart.bar.fill")
        }
    }
    
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(loc.localized("bezel.deleteAllBezels"), systemImage: "trash.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
        } header: {
            Label(loc.localized("bezel.dangerZone"), systemImage: "exclamationmark.triangle.fill")
        }
    }
    
    private var noResultsView: some View {
        ContentUnavailableView {
            Label(loc.localized("bezel.noResults"), systemImage: "magnifyingglass")
        } description: {
            Text("\(loc.localized("bezel.noSettingsMatch")) '\(searchText)'")
        }
        .padding(.vertical, 40)
    }
    
    var downloadProgressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: apiService.progressTracker.progress)
                .progressViewStyle(.linear)
            
            HStack {
                Text(apiService.progressTracker.downloadStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(apiService.progressTracker.currentDownloadedCount)/\(apiService.progressTracker.totalItemsToDownload)")
                    .font(.caption2.monospacedDigit())
                
                Button(loc.localized("bezel.stop")) {
                    apiService.progressTracker.cancelDownload()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    func statItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var downloadButtonLabel: String {
        if selectedSystem == "all" { return loc.localized("bezel.downloadAll") }
        return "\(loc.localized("bezel.downloadAll")) \(selectedSystem.capitalized)"
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
        alert.messageText = loc.localized("bezel.changeStorageLocation")
        alert.informativeText = loc.localized("bezel.moveExistingPrompt")
        alert.addButton(withTitle: loc.localized("bezel.moveExisting"))
        alert.addButton(withTitle: loc.localized("bezel.changeOnly"))
        alert.addButton(withTitle: loc.localized("bezel.cancel"))
        
        let response = alert.runModal()
        if response == .alertThirdButtonReturn { return }

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
        }
        
        storageManager.storageMode = mode
    }
    
    func formatByteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
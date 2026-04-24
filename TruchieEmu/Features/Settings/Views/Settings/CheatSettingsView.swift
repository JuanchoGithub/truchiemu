import SwiftUI

// MARK: - Cheat Settings View

struct CheatSettingsView: View {
    @StateObject private var downloadService = CheatDownloadService.shared
    @StateObject private var cheatManager = CheatManagerService.shared
    @ObservedObject var prefs = SystemPreferences.shared
    
    @State private var downloadResult: String?
    @State private var showClearConfirmation = false
    @State private var selectedSystem: String = "all"
    @State private var isExporting = false
    
    @Binding var searchText: String
    
    let system: SystemInfo?
    
    let searchKeywords = "cheats codes cheat code action replay"
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) ||
               keywords.localizedLowercase.contains(searchText.lowercased())
    }
    
    private var hasAnyResults: Bool {
        matchesSearch("Cheat Library Summary files storage custom") ||
        matchesSearch("Online Database download network") ||
        matchesSearch("Apply Cheats on Launch Behavior notifications") ||
        matchesSearch("Actions Show in Finder Clear Downloaded Cheats")
    }
    
    init(system: SystemInfo? = nil, searchText: Binding<String> = .constant("")) {
        self.system = system
        self._searchText = searchText
    }
    
    var body: some View {
        Form {
            // MARK: - Statistics Dashboard
            if !isSearching || matchesSearch("Cheat Library Summary files storage custom") {
                Section {
                    HStack(spacing: 20) {
                        statTile(
                            value: "\(downloadService.getDownloadedCheatCount())",
                            label: "Files",
                            icon: "doc.on.doc.fill",
                            color: .blue
                        )
                        Divider().frame(height: 40)
                        statTile(
                            value: formatByteSize(downloadService.getDownloadedCheatSize()),
                            label: "Storage",
                            icon: "internaldrive.fill",
                            color: .purple
                        )
                        Divider().frame(height: 40)
                        statTile(
                            value: AppSettings.getData("cheats_v2") != nil ? "Active" : "None",
                            label: "Custom",
                            icon: "wand.and.stars",
                            color: .orange
                        )
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("Cheat Library Summary")
                }
            }

            // MARK: - Download Section
            if !isSearching || matchesSearch("Online Database download network") {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if let lastDate = downloadService.lastDownloadDate {
                            LabeledContent("Last Updated") {
                                Text(lastDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if downloadService.isDownloading {
                            downloadProgressView
                        } else {
                            downloadActionButtons
                        }
                    }
                } header: {
                    Label("Online Database", systemImage: "network")
                } footer: {
                    Text("Downloads cheat files from the Libretro-Database repository. Files are automatically organized by system core.")
                }
            }

            // MARK: - Preferences Section
            if !isSearching || matchesSearch("Apply Cheats on Launch Behavior notifications") {
                Section("Behavior") {
                    Toggle(isOn: $prefs.applyCheatsOnLaunch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apply Cheats on Launch")
                            Text("Automatically apply enabled cheats when starting a game")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: prefs.applyCheatsOnLaunch) { 
                        AppSettings.setBool("applyCheatsOnLaunch", value: prefs.applyCheatsOnLaunch)
                    }
                    
                    Toggle(isOn: $prefs.showCheatNotifications) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cheat Notifications")
                            Text("Show OSD notifications when cheats are activated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: prefs.showCheatNotifications) {
                        AppSettings.setBool("showCheatNotifications", value: prefs.showCheatNotifications)
                    }   
                }
            }

            // MARK: - Maintenance Section
            if !isSearching || matchesSearch("Actions Show in Finder Clear Downloaded Cheats") {
                Section("Actions") {
                    Button(action: openCheatDirectory) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear Downloaded Cheats", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            
            // MARK: - No Results
            if isSearching && !hasAnyResults {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No results")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Try a different search term")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 40)
                        Spacer()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cheats")
        .confirmationDialog(
            "Clear Downloaded Cheats",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                do {
                    try downloadService.clearDownloadedCheats()
                } catch {
                    LoggerService.debug(category: "Cheats", "Failed to clear: \(error)")
                }
            }
        } message: {
            Text("This will remove all downloaded cheat files. Your custom cheats will not be affected.")
        }
        .overlay(alignment: .bottom) {
            if let result = downloadResult {
                resultToast(result)
            }
        }
    }

// MARK: - Improved Download Progress (No Layout Shifts)
    
    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Fixed Header Area
            HStack {
                Text(downloadService.downloadStatus)
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(downloadService.currentDownloadedCount)/\(downloadService.totalItemsToDownload)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            
            ProgressView(value: Double(downloadService.currentDownloadedCount), total: max(Double(downloadService.totalItemsToDownload), 1))
                .progressViewStyle(.linear)
            
            // 2. Persistent Status Bar (Prevents the "jump")
            HStack {
                if downloadService.currentlyDownloadingCount > 0 {
                    Label("\(downloadService.currentlyDownloadingCount) active threads", systemImage: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else {
                    // This invisible label keeps the height consistent
                    Label("Idle", systemImage: "circle")
                        .font(.caption2)
                        .opacity(0) 
                }
            }
            .frame(height: 16) // Reserve the vertical space
            
            // 3. Log Area
            if !downloadService.downloadLog.isEmpty {
                DownloadLogView(logEntries: downloadService.downloadLog)
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    private var downloadActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    let result = await downloadService.downloadAllCheats()
                    handleResult(result)
                }
            } label: {
                Label("Download All", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)

            if let system = system {
                Button("Update \(system.name)") {
                    downloadForSystem(system.id, name: system.name)
                }
            } else {
                Menu("Update Specific...") {
                    ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                        Button(sys.name) {
                            downloadForSystem(sys.id, name: sys.name)
                        }
                    }
                }
            }
        }
    }

    private func statTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(value).font(.headline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
        }
        .frame(minWidth: 90)
    }

    private func resultToast(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(radius: 10)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { downloadResult = nil }
                }
            }
    }

    // MARK: - Logic Helpers

    private func downloadForSystem(_ id: String, name: String) {
        Task {
            do {
                let count = try await downloadService.downloadCheatsForSystem(id)
                downloadResult = count > 0 ? "Downloaded \(count) files for \(name)" : "No files found for \(name)"
            } catch {
                downloadResult = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleResult(_ result: CheatDownloadResult) {
        switch result {
        case .success(_, _, let message): downloadResult = message
        case .failed(let message): downloadResult = message
        case .alreadyDownloading: break
        }
    }

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

// MARK: - Download Log Components

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
                .padding(4)
                .onChange(of: logEntries.count) { _, _ in
                    if let lastId = logEntries.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: CheatDownloadLogEntry
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 10, weight: .bold))
            
            Text(entry.fileName)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
            
            Spacer()
            
            Text(statusMessage)
                .font(.system(size: 9))
                .foregroundStyle(statusColor)
        }
        .id(entry.id)
    }
    
    private var statusIcon: String {
        switch entry.status {
        case .inProgress: return "arrow.down.circle"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch entry.status {
        case .inProgress: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }
    
    private var statusMessage: String {
        switch entry.status {
        case .inProgress: return "Downloading..."
        case .success: return "OK"
        case .failed(let reason): return reason.prefix(20) + "..."
        }
    }
}

#Preview {
    CheatSettingsView()
}

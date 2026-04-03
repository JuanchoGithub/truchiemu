import SwiftUI

// MARK: - Bezel Selector Sheet

/// Sheet for selecting a bezel for a specific game.
/// Split into "Local Bezels" (cached/downloaded) and "Search Online" (API).
/// Shows a preview panel on the right when a bezel is selected.
struct BezelSelectorSheet: View {
    let rom: ROM
    let systemID: String
    let onBezelSelected: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ROMLibrary
    
    @StateObject private var bezelManager = BezelManager.shared
    @StateObject private var apiService = BezelAPIService.shared
    @StateObject private var storageManager = BezelStorageManager.shared
    
    @State private var searchQuery = ""
    @State private var localBezels: [BezelStorageManager.LocalBezelInfo] = []
    @State private var remoteBezels: [BezelEntry] = []
    @State private var isLoadingLocal = false
    @State private var isLoadingRemote = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadingBezelID: String? = nil
    @State private var selectedLocalEntry: BezelStorageManager.LocalBezelInfo?
    @State private var selectedRemoteEntry: BezelEntry?
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var activeTab: BezelTab = .local
    
    enum BezelTab: String, Identifiable, CaseIterable, Hashable {
        case local = "Local Bezels"
        case online = "Search Online"
        
        var id: String { rawValue }
    }
    
    /// Filtered local bezels based on search (fuzzy word-level matching)
    var filteredLocalBezels: [BezelStorageManager.LocalBezelInfo] {
        guard !searchQuery.isEmpty else { return localBezels }
        return localBezels.filter { entry in
            let displayName = entry.id.replacingOccurrences(of: "_", with: " ")
            return matchesFuzzy(searchQuery, against: displayName) ||
                   matchesFuzzy(searchQuery, against: entry.id)
        }
    }
    
    /// Filtered remote bezels based on search (fuzzy word-level matching)
    var filteredRemoteBezels: [BezelEntry] {
        guard !searchQuery.isEmpty else { return remoteBezels }
        return remoteBezels.filter { entry in
            matchesFuzzy(searchQuery, against: entry.displayName) ||
            matchesFuzzy(searchQuery, against: entry.id)
        }
    }
    
    /// Fuzzy match: all words in the query must appear somewhere in the text.
    /// E.g., "mario 3" matches "Super Mario Bros. 3" because both "mario" and "3" are found.
    private func matchesFuzzy(_ query: String, against text: String) -> Bool {
        let words = query.lowercased().split(separator: " ").map { String($0) }
        let lowerText = text.lowercased()
        return words.allSatisfy { lowerText.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            HSplitView {
                // Left: List of bezels
                VStack(spacing: 0) {
                    // Tab picker
                    Picker("Bezels", selection: $activeTab) {
                        Text("Local Bezels (\(localBezels.count))")
                            .tag(BezelTab.local)
                        Text("Search Online (\(remoteBezels.count))")
                            .tag(BezelTab.online)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search bezels...", text: $searchQuery)
                            .textFieldStyle(.plain)
                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    
                    // Content
                    switch activeTab {
                    case .local:
                        if isLoadingLocal {
                            localLoadingView
                        } else if filteredLocalBezels.isEmpty {
                            localEmptyView
                        } else {
                            localBezelListView
                        }
                    case .online:
                        if isLoadingRemote {
                            remoteLoadingView
                        } else if let error = errorMessage {
                            errorView(message: error)
                        } else if filteredRemoteBezels.isEmpty {
                            remoteEmptyView
                        } else {
                            remoteBezelListView
                        }
                    }
                }
                .frame(minWidth: 250, idealWidth: 300)
                
                // Right: Preview panel
                if let selected = selectedEntry {
                    bezelPreviewPanel(selected)
                } else {
                    Text("Select a bezel to preview")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Select Bezel for \(rom.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showFilePicker = true }) {
                            Label("Import Custom Bezel...", systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            clearBezel()
                            dismiss()
                        } label: {
                            Label("Clear Bezel", systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            disableBezel()
                            dismiss()
                        } label: {
                            Label("Disable Bezels", systemImage: "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                if selectedEntry != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { applySelectedBezel(); dismiss() }) {
                            Label("Apply", systemImage: "checkmark")
                        }
                        .disabled(isDownloading)
                    }
                }
            }
            .task {
                await loadLocalBezels()
                await loadRemoteBezels()
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.png],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importCustomBezel(from: url)
                    }
                case .failure(let error):
                    LoggerService.debug(category: "Bezel", "File import failed: \(error)")
                }
            }
        }
        .frame(width: 800, height: 550)
    }
    
    // MARK: - Selection helpers
    
    /// Unified selected entry (either local or remote).
    private var selectedEntry: BezelPreviewEntry? {
        if activeTab == .local, let local = selectedLocalEntry {
            return .local(local)
        } else if let remote = selectedRemoteEntry {
            return .remote(remote)
        }
        return nil
    }
    
    enum BezelPreviewEntry: Identifiable {
        case local(BezelStorageManager.LocalBezelInfo)
        case remote(BezelEntry)
        
        var id: String {
            switch self {
            case .local(let local): return local.id
            case .remote(let remote): return remote.id
            }
        }
        
        var displayName: String {
            switch self {
            case .local(let local):
                return local.id.replacingOccurrences(of: "_", with: " ")
            case .remote(let remote):
                return remote.displayName
            }
        }
    }
    
    // MARK: - Loading Views
    
    private var localLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView("Scanning local bezels...")
            Text("Looking for bezels in storage...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var remoteLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView("Loading bezels...")
            Text("Fetching from The Bezel Project...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty Views
    
    private var localEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No local bezels found")
                .font(.headline)
            Text("Browse the Search Online tab or import a custom bezel")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var remoteEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No bezels available")
                .font(.headline)
            Text("Try downloading bezels from Settings → Bezels")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Unable to load bezels")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadRemoteBezels() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - List Views
    
    private var localBezelListView: some View {
        List(selection: $selectedLocalEntry) {
            ForEach(filteredLocalBezels) { entry in
                LocalBezelListRow(entry: entry, isSelected: selectedLocalEntry?.id == entry.id)
                    .tag(entry)
                    .onTapGesture {
                        selectedLocalEntry = entry
                        selectedRemoteEntry = nil
                    }
                    .onDoubleClick {
                        selectedLocalEntry = entry
                        selectedRemoteEntry = nil
                        saveBezelFileName(entry.id)
                        dismiss()
                    }
            }
        }
        .listStyle(.inset)
    }
    
    private var remoteBezelListView: some View {
        List(selection: $selectedRemoteEntry) {
            ForEach(filteredRemoteBezels, id: \.id) { entry in
                RemoteBezelListRow(entry: entry, isSelected: selectedRemoteEntry?.id == entry.id)
                    .tag(entry)
                    .onTapGesture {
                        selectedRemoteEntry = entry
                        selectedLocalEntry = nil
                        // Auto-download bezel when tapped in online tab
                        if !entry.isDownloaded {
                            downloadRemoteBezel(entry)
                        }
                    }
                    .onDoubleClick {
                        selectedRemoteEntry = entry
                        selectedLocalEntry = nil
                        applyRemoteBezel(entry)
                        dismiss()
                    }
            }
        }
        .listStyle(.inset)
    }
    
    // MARK: - Preview Panel
    
    @ViewBuilder
    private func bezelPreviewPanel(_ entry: BezelPreviewEntry) -> some View {
        VStack(spacing: 16) {
            // Preview image
            ZStack {
                switch entry {
                case .local(let local):
                    if let image = NSImage(contentsOf: local.fileURL) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 350, maxHeight: 250)
                    }
                case .remote(let remote):
                    if remote.isDownloaded, let localURL = remote.localURL,
                       let image = NSImage(contentsOf: localURL) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 350, maxHeight: 250)
                    } else if downloadingBezelID == remote.id {
                        // Show download progress
                        VStack(spacing: 12) {
                            ProgressView(value: downloadProgress)
                                .progressViewStyle(.linear)
                                .tint(.blue)
                                .frame(width: 200)
                            Text("Downloading... \(Int(downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: 350, maxHeight: 250)
                    } else {
                        // Placeholder for remote bezels
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(maxWidth: 350, maxHeight: 250)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    Text("Preview not downloaded")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                    }
                }
            }
            .cornerRadius(8)
            
            // Info
            VStack(spacing: 8) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // Status badge
                switch entry {
                case .local:
                    Label("Local file", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                case .remote(let remote):
                    if remote.isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Label("Not downloaded", systemImage: "arrow.down.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 8) {
                switch entry {
                case .local:
                    Button(action: { saveBezelFileName(entry.id); dismiss() }) {
                        Label("Apply", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                case .remote(let remote):
                    if remote.isDownloaded {
                        Button(action: { applyRemoteBezel(remote); dismiss() }) {
                            Label("Apply", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(action: { downloadAndApply(remote) }) {
                            if isDownloading {
                                ProgressView()
                            } else {
                                Label("Download & Apply", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isDownloading)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 250, idealWidth: 300)
    }
    
    // MARK: - Actions
    
    @MainActor
    private func loadLocalBezels() async {
        isLoadingLocal = true
        localBezels = storageManager.listLocalBezels(for: systemID)
        isLoadingLocal = false
    }
    
    @MainActor
    private func loadRemoteBezels() async {
        isLoadingRemote = true
        errorMessage = nil
        
        do {
            let entries = try await bezelManager.getBezels(systemID: systemID)
            // Update local URLs and download status
            remoteBezels = entries.map { entry in
                let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: entry.id)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    return BezelEntry(
                        id: entry.id,
                        filename: entry.filename,
                        rawURL: entry.rawURL,
                        localURL: localURL
                    )
                }
                return entry
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoadingRemote = false
    }
    
    /// Download a remote bezel with progress indicator and refresh the preview image
    @MainActor
    private func downloadRemoteBezel(_ entry: BezelEntry) {
        downloadingBezelID = entry.id
        downloadProgress = 0
        
        Task {
            do {
                // Simulate progress (since URLSession.download doesn't provide progress for small files)
                let progressTask = Task {
                    while !Task.isCancelled && downloadProgress < 0.9 {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        await MainActor.run {
                            downloadProgress = min(downloadProgress + 0.1, 0.9)
                        }
                    }
                }
                
                let localURL = try await apiService.downloadBezel(systemID: systemID, entry: entry)
                progressTask.cancel()
                
                await MainActor.run {
                    downloadProgress = 1.0
                    
                    // Update the entry's local status
                    let updatedEntry = BezelEntry(
                        id: entry.id,
                        filename: entry.filename,
                        rawURL: entry.rawURL,
                        localURL: localURL
                    )
                    if let index = remoteBezels.firstIndex(where: { $0.id == entry.id }) {
                        remoteBezels[index] = updatedEntry
                        // If this is the selected entry, update it too
                        if selectedRemoteEntry?.id == entry.id {
                            selectedRemoteEntry = updatedEntry
                        }
                    }
                    
                    // Also refresh local bezels since this one is now local
                    Task { await loadLocalBezels() }
                    
                    // Clear downloading state after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.downloadingBezelID = nil
                        self.downloadProgress = 0
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to download: \(error.localizedDescription)"
                    downloadingBezelID = nil
                    downloadProgress = 0
                }
            }
        }
    }
    
    private func applyRemoteBezel(_ entry: BezelEntry) {
        saveBezelFileName(entry.id)
    }
    
    private func downloadAndApply(_ entry: BezelEntry) {
        isDownloading = true
        Task {
            do {
                _ = try await apiService.downloadBezel(systemID: systemID, entry: entry)
                // Update the entry's local status
                let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: entry.id)
                let updatedEntry = BezelEntry(
                    id: entry.id,
                    filename: entry.filename,
                    rawURL: entry.rawURL,
                    localURL: localURL
                )
                if let index = remoteBezels.firstIndex(where: { $0.id == entry.id }) {
                    remoteBezels[index] = updatedEntry
                    selectedRemoteEntry = updatedEntry
                }
                // Also refresh local bezels since this one is now local
                await loadLocalBezels()
                saveBezelFileName(entry.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isDownloading = false
        }
    }
    
    private func saveBezelFileName(_ filename: String) {
        var updated = rom
        updated.settings.bezelFileName = filename
        library.updateROM(updated)
        onBezelSelected?(filename)
    }
    
    private func clearBezel() {
        var updated = rom
        updated.settings.bezelFileName = ""
        library.updateROM(updated)
        onBezelSelected?("")
    }
    
    private func disableBezel() {
        var updated = rom
        updated.settings.bezelFileName = "none"
        library.updateROM(updated)
        onBezelSelected?("none")
    }
    
    private func importCustomBezel(from url: URL) {
        do {
            let destURL = try bezelManager.importCustomBezel(
                from: url,
                systemID: systemID,
                gameName: rom.displayName
            )
            var updated = rom
            updated.settings.bezelFileName = destURL.deletingPathExtension().lastPathComponent
            library.updateROM(updated)
            onBezelSelected?(destURL.deletingPathExtension().lastPathComponent)
            // Refresh local bezels
            Task { await loadLocalBezels() }
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
    }
    
    private func applySelectedBezel() {
        switch selectedEntry {
        case .local(let local):
            saveBezelFileName(local.id)
        case .remote(let remote):
            applyRemoteBezel(remote)
        case .none:
            break
        }
    }
}

// MARK: - Local Bezel List Row

struct LocalBezelListRow: View {
    let entry: BezelStorageManager.LocalBezelInfo
    let isSelected: Bool
    
    private var displayName: String {
        entry.id.replacingOccurrences(of: "_", with: " ")
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(entry.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View+onDoubleClick

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        self.simultaneousGesture(
            TapGesture(count: 2).onEnded { _ in action() }
        )
    }
}
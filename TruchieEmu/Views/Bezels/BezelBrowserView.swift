import SwiftUI

// MARK: - Bezel Browser View

/// A dedicated view for browsing and managing bezels per system.
/// Features:
/// - Local tab: Image grid of downloaded bezels
/// - Remote tab: List with preview panel, click to download and cache
/// Cached bezels are kept separate from "available" until user chooses to apply them.
struct BezelBrowserView: View {
    let systemID: String
    let systemName: String
    
    @StateObject private var apiService = BezelAPIService.shared
    @StateObject private var bezelManager = BezelManager.shared
    @StateObject private var storageManager = BezelStorageManager.shared
    
    // State
    @State private var allBezels: [BezelEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedEntry: BezelEntry?
    @State private var isDownloading = false
    @State private var searchQuery = ""
    @State private var activeTab: BezelBrowserTab = .local
    @State private var cachedBezels: [String: BezelEntry] = [:]
    
    // For remote preview downloads
    @State private var previewDownloadTask: Task<Void, Never>?
    @State private var previewImage: NSImage?
    @State private var isPreviewLoading = false
    
    enum BezelBrowserTab: String, CaseIterable, Identifiable {
        case local = "Local"
        case remote = "Remote"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .local: return "folder.fill"
            case .remote: return "cloud.fill"
            }
        }
        
        var label: String {
            switch self {
            case .local: return "Downloaded"
            case .remote: return "Available"
            }
        }
    }
    
    // Filtered bezels based on tab
    var localBezels: [BezelEntry] {
        allBezels.filter { $0.isDownloaded }
    }
    
    var remoteBezels: [BezelEntry] {
        allBezels.filter { !$0.isDownloaded }
    }
    
    var filteredLocalBezels: [BezelEntry] {
        guard !searchQuery.isEmpty else { return localBezels }
        let lowerQuery = searchQuery.lowercased()
        return localBezels.filter { entry in
            entry.displayName.lowercased().contains(lowerQuery) ||
            entry.id.lowercased().contains(lowerQuery)
        }
    }
    
    var filteredRemoteBezels: [BezelEntry] {
        guard !searchQuery.isEmpty else { return remoteBezels }
        let lowerQuery = searchQuery.lowercased()
        return remoteBezels.filter { entry in
            entry.displayName.lowercased().contains(lowerQuery) ||
            entry.id.lowercased().contains(lowerQuery)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with system name
            HStack {
                Text(systemName)
                    .font(.headline)
                Spacer()
                
                // Tab toggle
                Picker("View", selection: $activeTab) {
                    ForEach(BezelBrowserTab.allCases) { tab in
                        Label(tab.label, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                // Refresh button
                Button {
                    Task { await loadBezels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
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
                
                Spacer()
                
                // Stats
                Text("\(localBezels.count) downloaded, \(remoteBezels.count) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            // Loading/Empty/Error states
            if isLoading {
                ProgressView("Loading bezels...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(message: error)
            } else if (activeTab == .local && filteredLocalBezels.isEmpty) ||
                      (activeTab == .remote && filteredRemoteBezels.isEmpty) {
                emptyView
            } else {
                // Split view with content and preview
                HSplitView {
                    // List/Grid view
                    contentView
                    
                    // Preview panel
                    previewPanel
                }
            }
        }
        .task {
            await loadBezels()
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        Group {
            switch activeTab {
            case .local:
                localBezelGrid
            case .remote:
                remoteBezelList
            }
        }
        .frame(minWidth: 300, idealWidth: 400)
    }
    
    // MARK: - Local Bezel Grid (Shows thumbnails)
    
    private var localBezelGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 10)],
                spacing: 10
            ) {
                ForEach(filteredLocalBezels) { entry in
                    BezelThumbnailView(
                        entry: entry,
                        isSelected: selectedEntry?.id == entry.id
                    )
                    .onTapGesture {
                        selectedEntry = entry
                        previewImage = nil
                    }
                    .contextMenu {
                        Button {
                            applyBezel(entry)
                        } label: {
                            Label("Apply to Game", systemImage: "checkmark.circle")
                        }
                        Button {
                            try? bezelManager.removeBezel(systemID: systemID, gameName: entry.id)
                            Task { await loadBezels() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }.foregroundColor(.red)
                        Button {
                            openBezelInFinder(entry)
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Remote Bezel List (With preview)
    
    private var remoteBezelList: some View {
        List(filteredRemoteBezels, selection: $selectedEntry) { entry in
            RemoteBezelListRow(entry: entry, isSelected: selectedEntry?.id == entry.id)
                .tag(entry)
                .onTapGesture {
                    selectedEntry = entry
                    previewImage = nil
                    loadPreviewImage(for: entry)
                }
                .onDoubleClick {
                    selectedEntry = entry
                    downloadAndCache(entry)
                }
        }
        .listStyle(.inset)
    }
    
    // MARK: - Preview Panel
    
    @ViewBuilder
    private var previewPanel: some View {
        VStack(spacing: 16) {
            if let entry = selectedEntry {
                // Preview image
                ZStack {
                    if entry.isDownloaded, let localURL = entry.localURL {
                        // Load full bezel image for downloaded bezels
                        if let image = NSImage(contentsOf: localURL) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    } else if let previewImage = previewImage {
                        // Cached preview for remote bezels
                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if isPreviewLoading {
                        ProgressView("Loading preview...")
                    } else {
                        // Placeholder for remote bezels
                        placeholderPreview
                    }
                }
                .frame(maxWidth: 400, maxHeight: 300)
                .cornerRadius(8)
                .clipped()
                
                // Bezel info
                VStack(spacing: 8) {
                    Text(entry.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(entry.filename)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Status badge
                    HStack {
                        if entry.isDownloaded {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else if isCached(entry.id) {
                            Label("Cached (preview)", systemImage: "eye.circle.fill")
                                .foregroundColor(.blue)
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
                    if entry.isDownloaded {
                        // Already downloaded - offer to apply
                        Button {
                            applyBezel(entry)
                        } label: {
                            Label("Apply to Current Game", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        // Download and cache
                        Button {
                            downloadAndCache(entry)
                        } label: {
                            if isDownloading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label(isCached(entry.id) ? "Apply to Current Game" : "Download & Preview", 
                                      systemImage: isCached(entry.id) ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isDownloading)
                        
                        // If cached, show option to make available
                        if isCached(entry.id) {
                            Button {
                                moveToAvailable(entry)
                            } label: {
                                Label("Add to Available Bezels", systemImage: "folder.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                Text("Select a bezel to preview")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 350)
    }
    
    @ViewBuilder
    private var placeholderPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Click bezel to load preview")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Empty & Error Views
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: activeTab == .local ? "folder" : "cloud")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(activeTab == .local ? "No bezels downloaded yet" : "No bezels available")
                .font(.headline)
            Text(activeTab == .local ? "Download bezels from the Remote tab" : "Check your internet connection")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Unable to load bezels")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadBezels() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    @MainActor
    private func loadBezels() async {
        isLoading = true
        errorMessage = nil
        
        do {
            allBezels = try await bezelManager.getBezels(systemID: systemID)
            // Update local URLs and download status
            allBezels = allBezels.map { entry in
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
        
        isLoading = false
    }
    
    /// Check if a bezel is cached (preview downloaded)
    private func isCached(_ bezelID: String) -> Bool {
        cachedBezels[bezelID] != nil
    }
    
    /// Download bezel for preview caching
    @MainActor
    private func downloadAndCache(_ entry: BezelEntry) {
        isDownloading = true
        
        Task {
            do {
                let url = try await apiService.downloadBezel(systemID: systemID, entry: entry)
                
                await MainActor.run {
                    // Add to cache
                    let cachedEntry = BezelEntry(
                        id: entry.id,
                        filename: entry.filename,
                        rawURL: entry.rawURL,
                        localURL: url
                    )
                    cachedBezels[entry.id] = cachedEntry
                    
                    // Update in allBezels
                    if let index = allBezels.firstIndex(where: { $0.id == entry.id }) {
                        allBezels[index] = cachedEntry
                        selectedEntry = cachedEntry
                    }
                    
                    // Reload image
                    previewImage = NSImage(contentsOf: url)
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to download: \(error.localizedDescription)"
                    isDownloading = false
                }
            }
        }
    }
    
    /// Move cached bezel to available (essentially mark it as applied)
    private func moveToAvailable(_ entry: BezelEntry) {
        // The bezel is already downloaded to local storage, it just needs to be marked
        // In this context, apply means add to the local bezels
        if let index = allBezels.firstIndex(where: { $0.id == entry.id }) {
            let updatedEntry = BezelEntry(
                id: entry.id,
                filename: entry.filename,
                rawURL: entry.rawURL,
                localURL: storageManager.bezelFilePath(systemID: systemID, gameName: entry.id)
            )
            allBezels[index] = updatedEntry
            selectedEntry = updatedEntry
            cachedBezels.removeValue(forKey: entry.id)
        }
    }
    
    /// Apply bezel to current game (placeholder - needs current ROM context)
    private func applyBezel(_ entry: BezelEntry) {
        // This needs a ROM context - for now show the action
        // In practice, this would update the current game's bezel setting
        print("[BezelBrowser] Would apply \(entry.displayName) to current game")
    }
    
    /// Open bezel in Finder
    private func openBezelInFinder(_ entry: BezelEntry) {
        if let url = entry.localURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    /// Load preview image for remote bezel (downloads small preview)
    private func loadPreviewImage(for entry: BezelEntry) {
        previewDownloadTask?.cancel()
        previewDownloadTask = Task {
            isPreviewLoading = true
            defer { if !Task.isCancelled { isPreviewLoading = false } }
            
            do {
                // Download to temp for preview
                let (tempURL, _) = try await URLSession.shared.download(from: entry.rawURL)
                let image = NSImage(contentsOf: tempURL)
                await MainActor.run {
                    previewImage = image
                }
            } catch {
                // Preview failed, continue
                print("[BezelBrowser] Failed to load preview for \(entry.filename): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Bezel Thumbnail View (for local bezels grid)

struct BezelThumbnailView: View {
    let entry: BezelEntry
    let isSelected: Bool
    
    @State private var image: NSImage?
    
    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 80)
                
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .font(.system(size: 24))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            
            // Name
            Text(entry.displayName)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.primary)
        }
        .task {
            if !Task.isCancelled, let url = entry.localURL {
                image = NSImage(contentsOf: url)
            }
        }
    }
}

// MARK: - Remote Bezel List Row

struct RemoteBezelListRow: View {
    let entry: BezelEntry
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Download status icon
            Image(systemName: entry.isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundColor(entry.isDownloaded ? .green : .secondary)
                .frame(width: 16)
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(entry.filename)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Selected indicator
            if isSelected {
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}


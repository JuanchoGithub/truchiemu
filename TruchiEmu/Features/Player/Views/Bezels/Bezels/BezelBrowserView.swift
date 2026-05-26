import SwiftUI

struct BezelBrowserView: View {
    let systemID: String
    let systemName: String
    
    @StateObject private var apiService = BezelAPIService.shared
    @StateObject private var bezelManager = BezelManager.shared
    @StateObject private var storageManager = BezelStorageManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var allBezels: [BezelEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedEntry: BezelEntry?
    @State private var isDownloading = false
    @State private var searchQuery = ""
    @State private var activeTab: BezelBrowserTab = .local
    @State private var cachedBezels: [String: BezelEntry] = [:]
    
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
            let loc = LocalizationManager.shared
            switch self {
            case .local: return loc.localized("bezel.downloadedCount").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            case .remote: return loc.localized("bezel.availableCount").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
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
            .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
            
            HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                TextField(loc.localized("bezel.searchBezels"), text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
        Text("\(localBezels.count) \(loc.localized("bezel.downloadedCount").replacingOccurrences(of: ",", with: "")) \(remoteBezels.count) \(loc.localized("bezel.availableCount"))")
            .font(.caption)
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
            .padding(10)
            .background(AppColors.cardBackgroundSubtle(colorScheme))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 4)
            
            if isLoading {
                ProgressView(loc.localized("bezel.loadingBezels"))
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
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
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
                            Label(loc.localized("bezel.applyToGame"), systemImage: "checkmark.circle")
                        }
                        Button {
                            try? bezelManager.removeBezel(systemID: systemID, gameName: entry.id)
                            Task { await loadBezels() }
                        } label: {
        Label(loc.localized("bezel.delete"), systemImage: "trash")
                    }.foregroundColor(AppColors.error(colorScheme))
                        Button {
                            openBezelInFinder(entry)
                        } label: {
                            Label(loc.localized("bezel.showInFinder"), systemImage: "folder")
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
                        ProgressView(loc.localized("bezel.loadingBezels"))
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
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                .lineLimit(1)
                    
                    // Status badge
                    HStack {
                        if entry.isDownloaded {
            Label(loc.localized("bezel.downloadedCount").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces), systemImage: "checkmark.circle.fill")
                .foregroundColor(AppColors.success(colorScheme))
                                .font(.caption)
                        } else if isCached(entry.id) {
                            Label(loc.localized("bezel.cachedPreview"), systemImage: "eye.circle.fill")
                    .foregroundColor(AppColors.brandAccent)
                                .font(.caption)
                        } else {
            Label(loc.localized("bezel.notDownloaded"), systemImage: "arrow.down.circle")
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                .font(.caption)
                        }
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    if entry.isDownloaded {
                        Button {
                            applyBezel(entry)
                        } label: {
                            Label(loc.localized("bezel.applyToCurrentGame"), systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button {
                            downloadAndCache(entry)
                        } label: {
                            if isDownloading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label(isCached(entry.id) ? loc.localized("bezel.applyToCurrentGame") : loc.localized("bezel.downloadPreview"), 
                                      systemImage: isCached(entry.id) ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isDownloading)
                        
                        if isCached(entry.id) {
                            Button {
                                moveToAvailable(entry)
                            } label: {
                                Label(loc.localized("bezel.addToAvailableBezels"), systemImage: "folder.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
            Text(loc.localized("bezel.selectBezelToPreview"))
                .foregroundColor(AppColors.textSecondary(colorScheme))
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
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        Text(loc.localized("bezel.clickBezelToPreview"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        }
    }
    
    // MARK: - Empty & Error Views
    
    private var emptyView: some View {
        VStack(spacing: 12) {
        Image(systemName: activeTab == .local ? "folder" : "cloud")
            .font(.system(size: 48))
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Text(activeTab == .local ? loc.localized("bezel.noBezelsDownloaded") : "\(loc.localized("bezel.noBezelsFound")) \(systemName)")
                .font(.headline)
        Text(activeTab == .local
            ? "\(loc.localized("bezel.noBezelsFound")) \(systemName). \(loc.localized("bezel.browseOnlineTab"))"
            : "\(loc.localized("bezel.noBezelsAvailable")) \(systemName)")
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 48))
            .foregroundColor(AppColors.warning(colorScheme))
            Text(loc.localized("bezel.couldntLoadBezels"))
                .font(.headline)
        Text(message)
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(loc.localized("bezel.tryAgain")) {
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
        
        LoggerService.info(category: "Bezel", "Loading online bezels for system: \(systemID)")
        do {
            allBezels = try await bezelManager.getBezels(systemID: systemID)
            LoggerService.info(category: "Bezel", "Loaded \(allBezels.count) bezel(s) for \(systemID) from The Bezel Project")
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
            LoggerService.error(category: "Bezel", "Failed to load bezels for \(systemID): \(error.localizedDescription) (\(error))")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // Check if a bezel is cached (preview downloaded)
    private func isCached(_ bezelID: String) -> Bool {
        cachedBezels[bezelID] != nil
    }
    
    // Download bezel for preview caching
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
    
    // Move cached bezel to available (essentially mark it as applied)
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
    
    // Apply bezel to current game (placeholder - needs current ROM context)
    private func applyBezel(_ entry: BezelEntry) {
        // This needs a ROM context - for now show the action
        // In practice, this would update the current game's bezel setting
        LoggerService.debug(category: "Bezel", "Would apply \(entry.displayName) to current game")
    }
    
    // Open bezel in Finder
    private func openBezelInFinder(_ entry: BezelEntry) {
        if let url = entry.localURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    // Load preview image for remote bezel (downloads small preview)
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
                LoggerService.debug(category: "Bezel", "Failed to load preview for \(entry.filename): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Bezel Thumbnail View (for local bezels grid)

struct BezelThumbnailView: View {
    let entry: BezelEntry
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
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
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .font(.system(size: 24))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? AppColors.brandAccent : Color.clear, lineWidth: 2)
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            // Download status icon
            Image(systemName: entry.isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundColor(entry.isDownloaded ? AppColors.success(colorScheme) : AppColors.textSecondaryNeutral(colorScheme))
                .frame(width: 16)
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.body)
                    .lineLimit(1)
            Text(entry.filename)
                .font(.caption)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                .lineLimit(1)
            }
            
            Spacer()
            
            // Selected indicator
            if isSelected {
                Image(systemName: "chevron.right")
                    .foregroundColor(AppColors.brandAccent)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}


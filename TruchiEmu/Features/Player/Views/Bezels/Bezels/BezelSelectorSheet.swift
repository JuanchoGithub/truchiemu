import SwiftUI

struct BezelSelectorSheet: View {
    let rom: ROM
    let systemID: String
    let onBezelSelected: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ROMLibrary
    
    @StateObject private var bezelManager = BezelManager.shared
    @StateObject private var apiService = BezelAPIService.shared
    @StateObject private var storageManager = BezelStorageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    
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
    
    // Filtered local bezels based on search (fuzzy word-level matching)
    var filteredLocalBezels: [BezelStorageManager.LocalBezelInfo] {
        guard !searchQuery.isEmpty else { return localBezels }
        return localBezels.filter { entry in
            let displayName = entry.id.replacingOccurrences(of: "_", with: " ")
            return matchesFuzzy(searchQuery, against: displayName) ||
                   matchesFuzzy(searchQuery, against: entry.id)
        }
    }
    
    // Filtered remote bezels based on search (fuzzy word-level matching)
    var filteredRemoteBezels: [BezelEntry] {
        guard !searchQuery.isEmpty else { return remoteBezels }
        return remoteBezels.filter { entry in
            matchesFuzzy(searchQuery, against: entry.displayName) ||
            matchesFuzzy(searchQuery, against: entry.id)
        }
    }
    
    // Fuzzy match: all words in the query must appear somewhere in the text.
    // E.g., "mario 3" matches "Super Mario Bros. 3" because both "mario" and "3" are found.
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
                    Picker(loc.localized("bezel.view"), selection: $activeTab) {
                        Text("\(loc.localized("bezel.localBezelsCount")) (\(localBezels.count))")
                            .tag(BezelTab.local)
                        Text("\(loc.localized("bezel.searchOnlineCount")) (\(remoteBezels.count))")
                            .tag(BezelTab.online)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
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
                    }
                    .padding(8)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
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
        Text(loc.localized("bezel.selectBezelToPreview"))
            .foregroundColor(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("\(loc.localized("bezel.selectBezelFor")) \(rom.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("bezel.cancel")) { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showFilePicker = true }) {
                            Label(loc.localized("bezel.importCustomBezel"), systemImage: "plus")
                        }
                        Button(role: .destructive) {
                            clearBezel()
                            dismiss()
                        } label: {
                            Label(loc.localized("bezel.clearBezel"), systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            disableBezel()
                            dismiss()
                        } label: {
                            Label(loc.localized("bezel.disableBezels"), systemImage: "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                if selectedEntry != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: { applySelectedBezel(); dismiss() }) {
                            Label(loc.localized("bezel.apply"), systemImage: "checkmark")
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
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .frame(width: 800, height: 550)
    }
    
    // MARK: - Selection helpers
    
    // Unified selected entry (either local or remote).
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
            ProgressView(loc.localized("bezel.scanningLocalBezels"))
        Text(loc.localized("bezel.lookingForBezels"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var remoteLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView(loc.localized("bezel.loadingBezels"))
        Text(loc.localized("bezel.fetchingFromBezelProject"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var localEmptyView: some View {
        VStack(spacing: 12) {
        Image(systemName: "tray")
            .font(.system(size: 36))
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Text(loc.localized("bezel.noLocalBezelsFound"))
                .font(.headline)
        Text(loc.localized("bezel.browseOnlineTab"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var remoteEmptyView: some View {
        VStack(spacing: 12) {
        Image(systemName: "photo")
            .font(.system(size: 36))
            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            Text(loc.localized("bezel.noBezelsAvailable"))
                .font(.headline)
        Text(loc.localized("bezel.tryDownloadingFromSettings"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 36))
            .foregroundColor(AppColors.warning(colorScheme))
            Text(loc.localized("bezel.unableToLoadBezels"))
                .font(.headline)
        Text(message)
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
            Button(loc.localized("bezel.retry")) {
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
                                .tint(AppColors.brandAccentSecondary)
                                .frame(width: 200)
                    Text("\(loc.localized("bezel.downloadingProgress")) \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        }
                        .frame(maxWidth: 350, maxHeight: 250)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(maxWidth: 350, maxHeight: 250)
                            .overlay {
                                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    Text(loc.localized("bezel.previewNotDownloaded"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                }
                            }
                    }
                }
            }
            .cornerRadius(8)
            
            VStack(spacing: 8) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                switch entry {
                case .local:
            Label(loc.localized("bezel.localFile"), systemImage: "checkmark.circle.fill")
                .foregroundColor(AppColors.success(colorScheme))
                        .font(.caption)
                case .remote(let remote):
                    if remote.isDownloaded {
                Label(loc.localized("bezel.downloadedCount").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces), systemImage: "checkmark.circle.fill")
                    .foregroundColor(AppColors.success(colorScheme))
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
                switch entry {
                case .local:
                    Button(action: { saveBezelFileName(entry.id); dismiss() }) {
                        Label(loc.localized("bezel.apply"), systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                case .remote(let remote):
                    if remote.isDownloaded {
                        Button(action: { applyRemoteBezel(remote); dismiss() }) {
                            Label(loc.localized("bezel.apply"), systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(action: { downloadAndApply(remote) }) {
                            if isDownloading {
                                ProgressView()
                            } else {
                                Label(loc.localized("bezel.downloadAndApply"), systemImage: "arrow.down.circle.fill")
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
        
        LoggerService.info(category: "Bezel", "Loading online bezels for system: \(systemID)")
        do {
            let entries = try await bezelManager.getBezels(systemID: systemID)
            LoggerService.info(category: "Bezel", "Loaded \(entries.count) bezel(s) for \(systemID) from The Bezel Project")
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
            LoggerService.error(category: "Bezel", "Failed to load bezels for \(systemID): \(error.localizedDescription) (\(error))")
            errorMessage = error.localizedDescription
        }
        
        isLoadingRemote = false
    }
    
    // Download a remote bezel with progress indicator and refresh the preview image
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
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayName: String {
        entry.id.replacingOccurrences(of: "_", with: " ")
    }
    
    var body: some View {
        HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(AppColors.success(colorScheme))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .lineLimit(1)
            Text(entry.fileURL.lastPathComponent)
                .font(.caption)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(AppColors.brandAccent)
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
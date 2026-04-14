import SwiftUI
import Combine
import GameController


// MARK: - Library Settings
struct LibrarySettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @State private var scanningFolders: Set<String> = []
    @State private var showingRebuildSheet = false
    @State private var rebuildTargetFolder: ROMLibraryFolder?
    @ObservedObject var prefs = SystemPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Display Options Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "eyeglasses")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("Display Options")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 0) {
                        Toggle(isOn: $prefs.showBiosFiles) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Show BIOS Files in Game List")
                                    .font(.body)
                                Text("When enabled, BIOS files will appear alongside playable games")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)

                        Divider()

                        Toggle(isOn: $prefs.showHiddenMAMEFiles) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Show Hidden MAME Files")
                                    .font(.body)
                                Text("When enabled, a 'Hidden MAME Files' section appears in the sidebar for BIOS, device, and unknown MAME entries")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                    )
                }
                
                // Library Folders Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("Library Folders")
                            .font(.headline)
                        Spacer()
                        Button(action: addLibraryFolder) {
                            Label("Add Folder", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if library.primaryFolders.isEmpty {
                        ContentUnavailableView {
                            Label("No Library Folders", systemImage: "folder")
                        } description: {
                            Text("Add folders containing your ROM files. TruchieEmu will scan them and organize games by console system.")
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .underPageBackgroundColor))
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(library.primaryFolders) { folder in
                                PrimaryFolderRow(
                                    folder: folder,
                                    isScanning: scanningFolders.contains(folder.url.path),
                                    onRescan: {
                                        Task {
                                            scanningFolders.insert(folder.url.path)
                                            await library.refreshFolder(at: folder.url)
                                            scanningFolders.remove(folder.url.path)
                                        }
                                    },
                                    onRebuild: { target in
                                        rebuildTargetFolder = target
                                        showingRebuildSheet = true
                                    }
                                )
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .underPageBackgroundColor))
                        )
                    }
                }
                
                // Maintenance Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("Maintenance")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 0) {
                        Button(action: { Task { await library.fullRescan() } }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Full Library Rescan")
                                        .font(.body)
                                    Text("Scan all folders for new or removed games")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if library.isScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Total Games: \(library.roms.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Primary Folders: \(library.primaryFolders.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                    )
                }
            }
            .padding(16)
        }
        .navigationTitle("Library")
        .sheet(isPresented: $showingRebuildSheet) {
            if let folder = rebuildTargetFolder {
                RebuildOptionsSheet(folder: folder, library: library)
            }
        }
    }
    
    private func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url {
            library.addPrimaryFolder(url: url)
        }
    }
}

// MARK: - Primary Folder Row (with expandable subfolders)
struct PrimaryFolderRow: View {
    let folder: ROMLibraryFolder
    let isScanning: Bool
    let onRescan: () -> Void
    let onRebuild: (ROMLibraryFolder) -> Void
    
    @EnvironmentObject var library: ROMLibrary
    @State private var isExpanded = false
    @State private var subfolders: [ROMLibraryFolder] = []
    @State private var isDiscovering = false
    @State private var showDeleteConfirmation = false
    @State private var discoverScanProgress: Double = 0
    @State private var showDiscoverConfirmation = false
    
    private var romCount: Int {
        let folderPath = folder.url.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return library.roms.filter { $0.path.path == folderPath || $0.path.path.hasPrefix(prefix) }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Primary folder row
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                        if isExpanded && subfolders.isEmpty {
                            Task { await discoverSubfolders() }
                        }
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                
                Image(systemName: "folder.fill")
                    .foregroundColor(.purple)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.body)
                    Text("\(romCount) game\(romCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onRescan) {
                    if isScanning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning...")
                        }
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning || library.isScanning)
                .help("Refresh: Check for new or deleted ROMs")
                
                Button(action: { onRebuild(folder) }) {
                    Label("Rebuild", systemImage: "gearshape.2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning || library.isScanning)
                .help("Rebuild: Choose what to rebuild for this folder")
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.8))
                .controlSize(.small)
                .confirmationDialog(
                    "Remove Folder",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        if let idx = library.primaryFolders.firstIndex(where: { $0.url.path == folder.url.path }) {
                            library.removePrimaryFolder(at: idx)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove '\(folder.url.lastPathComponent)' from your library?\n\nThis will also remove all subfolders that were discovered from this folder and their ROMs.\n\nSubfolders that were independently added as primary folders will NOT be affected.")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            
            // Subfolders (expanded)
            if isExpanded {
                VStack(spacing: 4) {
                    if isDiscovering {
                        HStack(spacing: 8) {
                            ProgressView(value: discoverScanProgress)
                                .progressViewStyle(.linear)
                            Text("Discovering subfolders...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)
                    } else if subfolders.isEmpty {
                        Text("No subfolders with ROMs found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(subfolders) { subfolder in
                            SubfolderRow(
                                folder: subfolder,
                                parentPath: folder.url.path,
                                isPrimary: subfolder.isPrimary,
                                depth: 0,
                                onRebuild: onRebuild
                            )
                        }
                    }
                    
                    // Discover subfolders button
                    Button(action: {
                        Task { await discoverSubfolders() }
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Discover Subfolders")
                        }
                        .font(.caption)
                    }
                    .disabled(isDiscovering)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }
    
    @MainActor
    private func discoverSubfolders() async {
        isDiscovering = true
        discoverScanProgress = 0
        
        // Only discover immediate children — let SubfolderRow discover its own nested children
        withAnimation(.linear(duration: 0.5)) { discoverScanProgress = 0.3 }
        let found = await library.discoverSubfoldersWithROMs(in: folder, maxDepth: 1)
        withAnimation(.linear(duration: 0.5)) { discoverScanProgress = 0.7 }
        
        // Merge newly discovered with existing (keep ones that were promoted to primary)
        var existingPaths = Set(subfolders.map { $0.url.path })
        var newSubfolders = subfolders
        
        for subfolder in found {
            if !existingPaths.contains(subfolder.url.path) {
                newSubfolders.append(subfolder)
                existingPaths.insert(subfolder.url.path)
                
                // Store this subfolder in the library
                if library.subfolderMap[folder.url.path] == nil {
                    library.subfolderMap[folder.url.path] = []
                }
                if !library.subfolderMap[folder.url.path]!.contains(where: { $0.url.path == subfolder.url.path }) {
                    library.subfolderMap[folder.url.path]!.append(subfolder)
                }
            }
        }
        
        // Only show immediate children (depth 1 from primary = depth 0 in our display)
        subfolders = newSubfolders.filter { $0.depthFromPrimary == 1 }.sorted { $0.url.path < $1.url.path }
        isDiscovering = false
        discoverScanProgress = 1.0
    }
}

// MARK: - Subfolder Row (recursive, supports sub-subfolders)
struct SubfolderRow: View {
    let folder: ROMLibraryFolder
    let parentPath: String
    let isPrimary: Bool // true if this subfolder was independently added as primary
    let depth: Int // nesting depth for indentation
    let onRebuild: (ROMLibraryFolder) -> Void
    
    @EnvironmentObject var library: ROMLibrary
    @State private var showDeleteConfirmation = false
    @State private var isScanning = false
    @State private var isExpanded = false
    @State private var subfolders: [ROMLibraryFolder] = []
    @State private var isDiscovering = false
    
    private var romCount: Int {
        let folderPath = folder.url.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return library.roms.filter { $0.path.path == folderPath || $0.path.path.hasPrefix(prefix) }.count
    }
    
    /// Display as "relative/path (# games)"
    private var compactPathDisplay: String {
        let relative = relativePathDisplay
        return "\(relative) (\(romCount) game\(romCount == 1 ? "" : "s"))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Expand chevron for sub-subfolders (depth < 2)
                if folderHasChildren {
                    Button(action: {
                        withAnimation {
                            isExpanded.toggle()
                            if isExpanded && subfolders.isEmpty {
                                Task { await discoverSubfolders() }
                            }
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Leaf node spacer
                    Rectangle().fill(.clear).frame(width: 16)
                }
                
                // Indent indicators - one line per depth level
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 2)
                        .padding(.horizontal, 4)
                }
                
                Image(systemName: isPrimary ? "folder.fill.badge.plus" : "folder.fill")
                    .foregroundColor(isPrimary ? .blue : .gray)
                    .font(.caption)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(compactPathDisplay)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.subheadline)
                        if isPrimary {
                            Text("(Independent)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        isScanning = true
                        await library.refreshFolder(at: folder.url)
                        isScanning = false
                    }
                }) {
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning || library.isScanning)
                .help("Refresh this subfolder")
                
                Button(action: { onRebuild(folder) }) {
                    Label("Rebuild", systemImage: "gearshape.2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanning || library.isScanning)
                .help("Rebuild: Choose what to rebuild for this subfolder")
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.8))
                .controlSize(.small)
                .disabled(folder.isPrimary)
                .confirmationDialog(
                    "Remove Subfolder",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        library.removeSubfolder(from: folder.parentPath ?? parentPath, subfolderPath: folder.url.path)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if folder.isPrimary {
                        Text("This folder was independently added as a primary folder. Remove it from the primary folders list instead.")
                    } else {
                        let parentName = folder.parentPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? URL(fileURLWithPath: parentPath).lastPathComponent
                        Text("Remove '\(folder.url.lastPathComponent)' subfolder from '\(parentName)'?\n\nROMs from this subfolder will be removed.")
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.regularMaterial.opacity(0.5))
            .cornerRadius(8)
            
            // Sub-subfolders (expanded)
            if isExpanded {
                VStack(spacing: 4) {
                    if isDiscovering {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Discovering subfolders...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)
                    } else if subfolders.isEmpty {
                        Text("No subfolders with ROMs found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(subfolders) { subfolder in
                            SubfolderRow(
                                folder: subfolder,
                                parentPath: folder.url.path,
                                isPrimary: subfolder.isPrimary,
                                depth: depth + 1,
                                onRebuild: onRebuild
                            )
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }
    
    /// Whether this folder might have children (to show expand chevron)
    private var folderHasChildren: Bool {
        // Only allow expansion up to depth 2
        guard depth < 2 else { return false }
        // If already discovered children exist, show chevron
        if !subfolders.isEmpty { return true }
        // Otherwise show chevron optimistically (will discover on expand)
        return true
    }
    
    private var relativePathDisplay: String {
        let components = folder.url.pathComponents
        let parentURL = URL(fileURLWithPath: folder.parentPath ?? parentPath)
        let parentComponents = parentURL.pathComponents
        let relative = components.dropFirst(parentComponents.count)
        return relative.joined(separator: " / ")
    }
    
    @MainActor
    private func discoverSubfolders() async {
        isDiscovering = true
        // Only discover immediate children of this folder
        let found = await library.discoverSubfoldersWithROMsInFolder(folder: folder)
        
        var existingPaths = Set(subfolders.map { $0.url.path })
        var newSubfolders = subfolders
        
        for subfolder in found {
            if !existingPaths.contains(subfolder.url.path) {
                newSubfolders.append(subfolder)
                existingPaths.insert(subfolder.url.path)
            }
        }
        
        subfolders = newSubfolders.sorted { $0.url.path < $1.url.path }
        isDiscovering = false
    }
}

// MARK: - Rebuild Options Sheet
struct RebuildOptionsSheet: View {
    let folder: ROMLibraryFolder
    @ObservedObject var library: ROMLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: RebuildOption? = nil
    @State private var isRebuilding = false
    @State private var showConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rebuild: \(folder.url.lastPathComponent)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose what to rebuild for this folder:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                ForEach(RebuildOption.allCases) { option in
                    Button(action: { selectedOption = option }) {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.title2)
                                .frame(width: 24)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.body)
                                    .fontWeight(selectedOption == option ? .semibold : .regular)
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedOption == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(12)
                        .background(selectedOption == option ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: { showConfirmation = true }) {
                    if isRebuilding {
                        ProgressView()
                            .controlSize(.small)
                        Text("Rebuilding...")
                    } else {
                        Text("Apply")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOption == nil || isRebuilding)
            }
        }
        .padding()
        .frame(width: 440, height: 420)
            .confirmationDialog(
                "Confirm Rebuild",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Rebuild", role: .destructive) {
                    Task {
                        isRebuilding = true
                        await library.rebuildFolder(folder: folder, option: selectedOption!)
                        isRebuilding = false
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will \(selectedOption?.description.lowercased() ?? "") for '\(folder.url.lastPathComponent)'.\n\nContinue?")
            }
    }
}

struct LibraryFolderRow: View {
    let folder: URL
    let index: Int
    let isScanning: Bool
    let onRescan: () -> Void
    
    @EnvironmentObject var library: ROMLibrary
    @State private var showDeleteConfirmation = false
    
    private var gameCount: Int {
        let folderPath = folder.path
        return library.roms.filter { $0.path.path.hasPrefix(folderPath) }.count
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundColor(.purple)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.body)
                Text("\(gameCount) game\(gameCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRescan) {
                if isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning...")
                    }
                } else {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isScanning || library.isScanning)
            .help("Rescan this folder for new games and clean up missing ones")
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red.opacity(0.8))
            .controlSize(.small)
            .confirmationDialog(
                "Remove Folder",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    library.removeLibraryFolder(at: index)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove '\(folder.lastPathComponent)' from your library? The ROMs from this folder will be removed from your library.")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}

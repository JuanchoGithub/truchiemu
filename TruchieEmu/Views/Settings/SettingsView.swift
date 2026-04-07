import SwiftUI
import Combine
import GameController

// MARK: - Main Settings View
struct SettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    
    private enum Page: Hashable { case general, library, cores, controllers, boxArt, display, cheats, bezels, retroAchievements, logging, about }
    @State private var selectedPage: Page = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Custom sidebar (no NavigationSplitView = no toggle button)
            List(selection: $selectedPage) {
                sidebarItem(icon: "photo.stack.fill", label: "Box Art", page: .boxArt)
                sidebarItem(icon: "wand.and.stars", label: "Cheats", page: .cheats)
                sidebarItem(icon: "gamecontroller.fill", label: "Controllers", page: .controllers)
                sidebarItem(icon: "cpu.fill", label: "Cores", page: .cores)
                sidebarItem(icon: "rectangle.on.rectangle", label: "Bezels", page: .bezels)
                sidebarItem(icon: "tv.fill", label: "Display", page: .display)
                sidebarItem(icon: "gearshape.fill", label: "General", page: .general)
                sidebarItem(icon: "book.fill", label: "Library", page: .library)
                sidebarItem(icon: "doc.text.fill", label: "Logging", page: .logging)
                sidebarItem(icon: "trophy.fill", label: "RetroAchievements", page: .retroAchievements)
                sidebarItem(icon: "info.circle.fill", label: "About", page: .about)
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Content area
            Group {
                switch selectedPage {
                case .general:     GeneralSettingsView()
                case .library:     LibrarySettingsView()
                case .cores:       CoreSettingsView()
                case .controllers: ControllerSettingsView()
                case .boxArt:      BoxArtSettingsView()
                case .display:     DisplaySettingsView()
                case .cheats:      CheatSettingsView()
                case .bezels:      BezelSettingsView()
                case .retroAchievements: RetroAchievementsSettingsView()
                case .logging:     LoggingSettingsView()
                case .about:       AboutView()
                }
            }
            .frame(minWidth: 550, minHeight: 420)
        }
        .frame(minWidth: 750, minHeight: 500)
    }
    
    private func sidebarItem(icon: String, label: String, page: Page) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .symbolVariant(.fill)
                .frame(width: 28, height: 20)
                .fixedSize()
            Text(label)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .tag(page)
    }
}

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

// MARK: - Cores
struct CoreSettingsView: View {
    @EnvironmentObject var coreManager: CoreManager

    @State private var selectedSystemID: String? = nil
    @State private var expandedCoreID: String? = nil
    @State private var systemsPanelWidth: CGFloat = 250

    private var selectedSystem: SystemInfo? {
        if let id = selectedSystemID {
            return SystemDatabase.system(forID: id)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fetching indicator
            if coreManager.isFetchingCoreList {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching core list from buildbot...")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Button("Refresh List") { Task { await coreManager.fetchAvailableCores() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(coreManager.isFetchingCoreList)
                }
                .padding(12)
                .background(.ultraThinMaterial)
            } else {
                // Refresh button
                HStack {
                    Spacer()
                    Button("Refresh List") { Task { await coreManager.fetchAvailableCores() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(coreManager.isFetchingCoreList)
                }
                .padding(8)
            }
            
            Divider()
            
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // System list (left column)
                    VStack(spacing: 0) {
                        Text("Systems")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        
                        List(selection: $selectedSystemID) {
                            ForEach(SystemDatabase.systemsForDisplay.sorted(by: { $0.name < $1.name })) { sys in
                                SystemRowView(system: sys, coreManager: coreManager)
                                    .tag(sys.id)
                            }
                        }
                        .listStyle(.plain)
                    }
                    .frame(width: systemsPanelWidth)
                    .border(.separator, width: 0.5)
                    
                    // Draggable divider
                    DraggableDivider(width: $systemsPanelWidth)
                    
                    // Cores list (right pane)
                VStack(spacing: 0) {
                    if let system = selectedSystem {
                        Text(system.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        
                        SystemCoresView(system: system, coreManager: coreManager)
                    } else {
                        ContentUnavailableView {
                            Label("Select a System", systemImage: "gamecontroller")
                        } description: {
                            Text("Choose a system from the list to see available cores.")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            }
        }
        .clipped()
        .onAppear {
            if coreManager.shouldAutoFetchCores {
                Task { await coreManager.fetchAvailableCores() }
            }
        }
    }
}

struct SystemRowView: View {
    let system: SystemInfo
    @ObservedObject var coreManager: CoreManager
    
    var installedCount: Int {
        coreManager.installedCores.filter { core in
            core.systemIDs.contains(system.id) || system.defaultCoreID == core.id
        }.count
    }
    
    var hasInstalled: Bool { installedCount > 0 }
    
    var body: some View {
        HStack(spacing: 8) {
            // Green dot indicator for installed cores (before icon)
            if hasInstalled {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .fixedSize()
            } else {
                Circle()
                    .fill(.clear)
                    .frame(width: 8, height: 8)
                    .fixedSize()
            }
            
            // System icon/image in uniform 32x32 container
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                
                if let img = system.emuImage(size: 132) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: system.iconName)
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
            .frame(width: 32, height: 32)
            .fixedSize()
            
            Text(system.name)
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .listRowSeparator(.hidden)
    }
}

struct SystemCoresView: View {
    let system: SystemInfo
    @ObservedObject var coreManager: CoreManager
    @State private var expandedCoreID: String? = nil
    @State private var showOptionsFor: String? = nil

    var coresForSystem: [RemoteCoreInfo] {
        coreManager.availableCores.filter { remoteCore in
            remoteCore.systemIDs.contains(system.id) || system.defaultCoreID == remoteCore.coreID
        }
    }
    
    var installedCoresForSystem: [LibretroCore] {
        coreManager.installedCores.filter { core in
            core.systemIDs.contains(system.id) || system.defaultCoreID == core.id
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if installedCoresForSystem.isEmpty && coresForSystem.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No cores available for this system.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    // Show installed cores first
                    if !installedCoresForSystem.isEmpty {
                        InstalledCoresSection(
                            cores: installedCoresForSystem,
                            expandedCoreID: $expandedCoreID,
                            showOptionsFor: $showOptionsFor,
                            coreManager: coreManager
                        )
                    }
                    
                    // Show available cores for download
                    if !coresForSystem.isEmpty {
                        let availableForDownload = coresForSystem.filter { remoteCore in
                            !coreManager.isInstalled(coreID: remoteCore.coreID)
                        }
                        
                        if !availableForDownload.isEmpty {
                            DownloadableCoresSection(
                                cores: availableForDownload,
                                coreManager: coreManager
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: Binding(
            get: { showOptionsFor != nil },
            set: { if !$0 { showOptionsFor = nil } }
        )) {
            if let coreID = showOptionsFor {
                CoreOptionsView(coreID: coreID)
            }
        }
    }
}

struct InstalledCoresSection: View {
    let cores: [LibretroCore]
    @Binding var expandedCoreID: String?
    @Binding var showOptionsFor: String?
    @ObservedObject var coreManager: CoreManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSTALLED")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            
            VStack(spacing: 8) {
                ForEach(cores) { core in
                    InstalledCoreRowView(
                        core: core,
                        isExpanded: expandedCoreID == core.id,
                        onToggle: {
                            withAnimation {
                                if expandedCoreID == core.id {
                                    expandedCoreID = nil
                                } else {
                                    expandedCoreID = core.id
                                }
                            }
                        },
                        onShowOptions: {
                            showOptionsFor = core.id
                        },
                        onDelete: {
                            coreManager.deleteCore(core)
                        },
                        coreManager: coreManager
                    )
                }
            }
        }
        .padding(.top, 8)
    }
}

struct DownloadableCoresSection: View {
    let cores: [RemoteCoreInfo]
    @ObservedObject var coreManager: CoreManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AVAILABLE FOR DOWNLOAD")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            
            VStack(spacing: 8) {
                ForEach(cores) { remoteCore in
                    DownloadableCoreRowView(
                        remoteCore: remoteCore,
                        coreManager: coreManager
                    )
                }
            }
        }
        .padding(.top, 8)
    }
}

struct InstalledCoreRowView: View {
    let core: LibretroCore
    let isExpanded: Bool
    let onToggle: () -> Void
    let onShowOptions: () -> Void
    let onDelete: () -> Void
    let coreManager: CoreManager
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Icon in fixed container
                    Image(systemName: "cpu")
                        .foregroundColor(.purple)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)
                        .fixedSize()
                    
                    // VStack centered vertically with button
                    VStack(alignment: .leading, spacing: 2) {
                        Text(core.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(core.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let version = core.activeVersionTag {
                            Text("v\(version)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    
                    // Options button
                    Button(action: onShowOptions) {
                        Image(systemName: "slider.vertical.3")
                    }
                    .buttonStyle(.plain)
                    .symbolVariant(.circle)
                    .help("Configure core options")
                    
                    // Delete button
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.6))
                    .symbolVariant(.circle)
                    .confirmationDialog(
                        "Delete Core",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) { onDelete() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Delete '\(core.displayName)' and all its versions? This will free up disk space.")
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(width: 16)
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Installed Versions:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !core.installedVersions.isEmpty {
                            Picker("Version", selection: Binding(
                                get: { core.activeVersionTag ?? core.installedVersions.last?.tag ?? "" },
                                set: { tag in
                                    coreManager.setActiveVersion(coreID: core.id, tag: tag)
                                }
                            )) {
                                ForEach(core.installedVersions.reversed()) { v in
                                    Text(v.tag).tag(v.tag)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    
                    let sysNames = core.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }
                    if !sysNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(sysNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.secondary.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    
                    Text("\(core.installedVersions.count) version\(core.installedVersions.count == 1 ? "" : "s") installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.05))
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

struct DownloadableCoreRowView: View {
    let remoteCore: RemoteCoreInfo
    @ObservedObject var coreManager: CoreManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon in fixed container
            Image(systemName: "cpu.badge.plus")
                .foregroundColor(.orange)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .fixedSize()
            
            // VStack centered vertically relative to button
            VStack(alignment: .leading, spacing: 2) {
                Text(remoteCore.displayName)
                    .font(.body)
                Text(remoteCore.coreID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }
            
            Spacer()
            
            let installed = coreManager.installedCores.first(where: { $0.id == remoteCore.coreID })
            
            if let inst = installed, inst.isDownloading {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: Double(inst.downloadProgress) / 100.0)
                        .frame(width: 100)
                        .tint(.orange)
                    Text("Downloading...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if let inst = installed, inst.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Download") {
                    coreManager.requestCoreDownload(for: remoteCore.coreID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(minHeight: 48)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

// MARK: - Controllers
struct ControllerSettingsView: View {
    @EnvironmentObject var controllerService: ControllerService
    @State private var selectedPlayer: Int = 1
    @State private var selectedSystemID: String = "default"
    @State private var configName: String = ""
    @State private var savedConfigs: [String: ControllerGamepadMapping] = [:]
    @State private var leftColumnWidth: CGFloat = 340
    @State private var showDeleteConfirmation = false

    @State private var activeTab = 0

    var body: some View {
        VStack(spacing: 12) {
            // Segmented control for tab switching (inside content area)
            Picker("Tab", selection: $activeTab) {
                Text("Controllers").tag(0)
                Text("Keyboard").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            // Tab content
            Group {
                if activeTab == 0 {
                    controllerContent
                } else {
                    keyboardContent
                }
            }
        }
    }

    @ViewBuilder
    private var controllerContent: some View {
        controllerTab
    }

    @ViewBuilder
    private var keyboardContent: some View {
        KeyboardContentView()
            .environmentObject(controllerService)
    }

    // MARK: - Controllers Tab
    @ViewBuilder
    private var controllerTab: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Top bar: Player selection + Config management
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // Player selection
                        Text("Player")
                            .font(.body)
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            ForEach(1...4, id: \.self) { i in
                                let connected = controllerService.connectedControllers.first(where: { $0.playerIndex == i })?.isConnected ?? false
                                Button("P\(i)") { selectedPlayer = i }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(selectedPlayer == i ? .purple : .secondary)
                                    .overlay(
                                        connected ? Circle().fill(.green).frame(width: 6, height: 6).offset(x: 8, y: -8) : nil,
                                        alignment: .topTrailing
                                    )
                            }
                        }

                        Divider().frame(height: 20)

                        // System picker
                        Picker("System", selection: $selectedSystemID) {
                            Text("Global / Default").tag("default")
                            Divider()
                            ForEach(SystemDatabase.systemsForDisplay) { sys in
                                Text(sys.name).tag(sys.id)
                            }
                        }
                        .frame(width: 180)

                        Spacer()

                        // Reset to default
                        Button("Back to Default") {
                            if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                                let vendorName = player.gcController?.vendorName ?? "Unknown"
                                let defaults = ControllerGamepadMapping.defaults(for: vendorName, systemID: selectedSystemID, handedness: controllerService.handedness)
                                controllerService.updateMapping(for: vendorName, systemID: selectedSystemID, mapping: defaults)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // Config name row: Load / Save / Delete / Config name
                    HStack(spacing: 6) {
                        Text("Config")
                            .font(.body)
                            .foregroundColor(.secondary)
                        TextField("Name", text: $configName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        Button("Save") {
                            saveCurrentConfig()
                        }
                        .disabled(configName.isEmpty)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Load") {
                            loadConfig(name: configName)
                        }
                        .disabled(configName.isEmpty || savedConfigs[configName] == nil)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            deleteConfig(name: configName)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(configName.isEmpty || savedConfigs[configName] == nil)

                        Spacer()

                        // Config selector
                        Menu {
                            ForEach(Array(savedConfigs.keys.sorted()), id: \.self) { name in
                                Button(name) {
                                    configName = name
                                    loadConfig(name: name)
                                }
                            }
                        } label: {
                            Label("Saved Configs", systemImage: "archivebox")
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)

                Divider()

                // Main content area - left panel (icon+sticks) | draggable divider | right panel (button mapping)
                if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                    HStack(spacing: 0) {
                        // Left side: Controller icon (unbounded) and stick visualization - wider, 300-380
                        ControllerLeftPanel(systemID: selectedSystemID, width: leftColumnWidth)

                        // Draggable divider
                        DraggableDivider(width: $leftColumnWidth)

                        // Right side: Button mapping list - narrower, bounded to right edge
                        ButtonMappingList(systemID: selectedSystemID, player: player, controllerService: controllerService)
                            .frame(minWidth: 140)
                    }
                    .id("\(selectedPlayer)-\(selectedSystemID)-\(leftColumnWidth)")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No controller connected for Player \(selectedPlayer).")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                selectedPlayer = controllerService.connectedControllers.first?.playerIndex ?? 1
                loadSavedConfigs()
            }
        }

    private func playerMappingBinding(for btn: RetroButton, player: PlayerController) -> Binding<GCButtonMapping?> {
        Binding<GCButtonMapping?>(
            get: { controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID).buttons[btn] },
            set: { _ in }
        )
    }

    private func saveCurrentConfig() {
        guard let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) else { return }
        guard !configName.isEmpty else { return }
        let currentMapping = controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID)
        savedConfigs[configName] = currentMapping
        saveConfigsToDisk()
    }

    private func loadConfig(name: String) {
        guard let mapping = savedConfigs[name],
              let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) else { return }
        controllerService.updateMapping(for: player.gcController?.vendorName ?? "Unknown", systemID: selectedSystemID, mapping: mapping)
        configName = name
    }

    private func deleteConfig(name: String) {
        guard !name.isEmpty, savedConfigs[name] != nil else { return }
        savedConfigs.removeValue(forKey: name)
        saveConfigsToDisk()
        if configName == name {
            configName = ""
        }
    }

    private func loadSavedConfigs() {
        // Persist controller configs to AppSettings
        if let data = AppSettings.getData("controller_saved_configs"),
           let configs = try? JSONDecoder().decode([String: ControllerGamepadMapping].self, from: data) {
            savedConfigs = configs
        }
    }

    private func saveConfigsToDisk() {
        if let data = try? JSONEncoder().encode(savedConfigs) {
            AppSettings.setData("controller_saved_configs", value: data)
        }
    }
}


// MARK: - Draggable Divider
struct DraggableDivider: View {
    @Binding var width: CGFloat
    @State private var isHovered = false
    
    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2))
            .frame(width: 4)
            .frame(maxHeight: .infinity)
            .onHover { hovering in
                isHovered = hovering
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.location.x - value.startLocation.x
                        width = max(260, min(420, width + delta))
                    }
            )
    }
}

// MARK: - Controller Left Panel (icon + sticks)
struct ControllerLeftPanel: View {
    let systemID: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ControllerIconView(systemID: systemID)
                .frame(maxWidth: 180)
            
            Divider().padding(.horizontal, 16)
            
            StickVisualizerView(systemID: systemID)
                .padding(.bottom, 8)
            
            Spacer()
        }
        .frame(width: width)
        .padding(.vertical, 8)
    }
}

// MARK: - Stick Visualizer with live state
struct StickVisualizerView: View {
    let systemID: String
    @State private var lStick: (x: Double, y: Double) = (0, 0)
    @State private var rStick: (x: Double, y: Double) = (0, 0)
    @EnvironmentObject var controllerService: ControllerService
    @StateObject private var stickManager = StickStateTracker()
    
    var body: some View {
        VStack(spacing: 6) {
            Text("Sticks")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                CompactStickView(x: stickManager.lX, y: stickManager.lY, label: "L")
                CompactStickView(x: stickManager.rX, y: stickManager.rY, label: "R")
            }
        }
    }
}

// MARK: - Button Mapping List (right panel)
struct ButtonMappingList: View {
    let systemID: String
    let player: PlayerController
    let controllerService: ControllerService
    @State private var listeningFor: RetroButton? = nil
    @State private var currentMapping: ControllerGamepadMapping
    
    init(systemID: String, player: PlayerController, controllerService: ControllerService) {
        self.systemID = systemID
        self.player = player
        self.controllerService = controllerService
        _currentMapping = State(initialValue: controllerService.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Button Mapping")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            
            Divider()
            
            List {
                ForEach(RetroButton.availableButtons(for: systemID), id: \.self) { btn in
                    MappingRowView(
                        button: btn,
                        currentMapping: currentMapping.buttons[btn],
                        isListening: listeningFor == btn,
                        onStartListening: { startListening(for: btn) },
                        onMappingCaptured: { newMapping in
                            currentMapping.buttons[btn] = newMapping
                            listeningFor = nil
                            saveMapping()
                        }
                    )
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 140)
        .onDisappear { stopListening() }
    }
    
    private func startListening(for btn: RetroButton) {
        listeningFor = btn
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.valueChangedHandler = { [self] pad, element in
            if let dpad = element as? GCControllerDirectionPad {
                if dpad.up.isPressed { capture(dpad.up) }
                else if dpad.down.isPressed { capture(dpad.down) }
                else if dpad.left.isPressed { capture(dpad.left) }
                else if dpad.right.isPressed { capture(dpad.right) }
            } else if let button = element as? GCControllerButtonInput, button.isPressed {
                capture(button)
            } else if let axis = element as? GCControllerAxisInput, abs(axis.value) > 0.6 {
                capture(axis)
            }
        }
    }
    
    private func capture(_ element: GCControllerElement) {
        let name = element.localizedName ?? "Button"
        DispatchQueue.main.async {
            currentMapping.buttons[listeningFor!] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
            listeningFor = nil
            stopListening()
            saveMapping()
        }
    }
    
    private func stopListening() {
        player.gcController?.extendedGamepad?.valueChangedHandler = nil
    }
    
    private func saveMapping() {
        controllerService.updateMapping(for: currentMapping.vendorName, systemID: systemID, mapping: currentMapping)
    }
}

// MARK: - Stick State Manager
class StickStateTracker: ObservableObject {
    @Published var lX: Double = 0
    @Published var lY: Double = 0
    @Published var rX: Double = 0
    @Published var rY: Double = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .sink { [weak self] _ in self?.startMonitoring() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .sink { [weak self] _ in
                self?.lX = 0; self?.lY = 0; self?.rX = 0; self?.rY = 0
            }
            .store(in: &cancellables)
        
        startMonitoring()
    }
    
    private func startMonitoring() {
        guard let gc = GCController.controllers().first,
              let gamepad = gc.extendedGamepad else { return }
        
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.lX = Double(x)
                self?.lY = Double(y)
            }
        }
        
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                self?.rX = Double(x)
                self?.rY = Double(y)
            }
        }
    }
}

struct ControllerMappingDetail: View {
    @EnvironmentObject var controllerService: ControllerService
    let player: PlayerController
    let systemID: String
    @State private var listeningFor: RetroButton? = nil
    @State private var mapping: ControllerGamepadMapping

    init(player: PlayerController, systemID: String) {
        self.player = player
        self.systemID = systemID
        _mapping = State(initialValue: ControllerService.shared.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Controller icon and stick visualization
            VStack(spacing: 8) {
                // Controller icon - unbounded
                ControllerIconView(systemID: systemID)

                Divider().padding(.horizontal, 12)

                // Stick visualization
                VStack(spacing: 8) {
                    Text("Sticks")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        CompactStickView(x: lStickState.x, y: lStickState.y, label: "L")
                        CompactStickView(x: rStickState.x, y: rStickState.y, label: "R")
                    }
                }
                .padding(.bottom, 8)

                Spacer()
            }
            .frame(width: 160)
            .padding(.vertical, 8)

            Divider()

            // Right side: Scrollable list of control mappings
            VStack(spacing: 0) {
                Text("Button Mapping")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                Divider()

                List {
                    ForEach(RetroButton.availableButtons(for: systemID), id: \.self) { btn in
                        MappingRowView(
                            button: btn,
                            currentMapping: mapping.buttons[btn],
                            isListening: listeningFor == btn,
                            onStartListening: {
                                listeningFor = btn
                                startListeningForButton(btn)
                            },
                            onMappingCaptured: { newMapping in
                                mapping.buttons[btn] = newMapping
                                listeningFor = nil
                                saveMapping()
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 300, maxWidth: 380)
        }
        .onAppear { startStickVisualizer() }
        .onDisappear { stopListening() }
    }

    private func startListeningForButton(_ btn: RetroButton) {
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.valueChangedHandler = { [self] pad, element in
            if let dpad = element as? GCControllerDirectionPad {
                if dpad.up.isPressed { captureMapping(dpad.up, for: btn) }
                else if dpad.down.isPressed { captureMapping(dpad.down, for: btn) }
                else if dpad.left.isPressed { captureMapping(dpad.left, for: btn) }
                else if dpad.right.isPressed { captureMapping(dpad.right, for: btn) }
            } else if let button = element as? GCControllerButtonInput, button.isPressed {
                captureMapping(button, for: btn)
            } else if let axis = element as? GCControllerAxisInput, abs(axis.value) > 0.6 {
                captureMapping(axis, for: btn)
            }
        }
    }

    private func captureMapping(_ element: GCControllerElement, for btn: RetroButton) {
        let name = element.localizedName ?? "Button"
        DispatchQueue.main.async {
            mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
            listeningFor = nil
            stopListening()
            saveMapping()
        }
    }

    private func stopListening() {
        player.gcController?.extendedGamepad?.valueChangedHandler = nil
    }

    private func saveMapping() {
        controllerService.updateMapping(for: mapping.vendorName, systemID: systemID, mapping: mapping)
    }

    @State private var lStickState: (x: Double, y: Double) = (0, 0)
    @State private var rStickState: (x: Double, y: Double) = (0, 0)

    private func startStickVisualizer() {
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.leftThumbstick.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { lStickState = (Double(x), Double(y)) }
        }
        gc.extendedGamepad?.rightThumbstick.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { rStickState = (Double(x), Double(y)) }
        }
    }
}

// MARK: - Mapping Row View
struct MappingRowView: View {
    let button: RetroButton
    let currentMapping: GCButtonMapping?
    let isListening: Bool
    let onStartListening: () -> Void
    let onMappingCaptured: (GCButtonMapping) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(button.displayName)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(isListening ? "Press..." : (currentMapping?.gcElementAlias ?? "—")) {
                onStartListening()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isListening ? .orange : .secondary)
            .fixedSize()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Compact Stick View
struct CompactStickView: View {
    let x: Double
    let y: Double
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.2))
                    .frame(width: 80, height: 80)
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 80, height: 80)

                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 80, height: 1)
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 1, height: 80)

                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 16)
                    .offset(x: CGFloat(x * 34), y: CGFloat(y * -34))
                    .shadow(color: .purple.opacity(0.5), radius: 5)
            }
            .clipShape(Circle())

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text("\(String(format: "%.2f", x)), \(String(format: "%.2f", y))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

struct StickTesterView: View {
    let x: Double
    let y: Double
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.quaternary.opacity(0.2))
                    .frame(width: 100, height: 100)
                Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 100, height: 100)
                
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 100, height: 1)
                Rectangle().fill(.secondary.opacity(0.1)).frame(width: 1, height: 100)
                
                Circle().fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 14, height: 14)
                    .offset(x: CGFloat(x * 43), y: CGFloat(y * -43))
                    .shadow(color: .purple.opacity(0.5), radius: 6)
            }
            .clipShape(Circle())
            
            Text(label).font(.caption2.bold()).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text("X: \(String(format: "%.2f", x))").font(.system(size: 9, design: .monospaced))
                Text("Y: \(String(format: "%.2f", y))").font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.background.opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.1), lineWidth: 1))
    }
}

struct ControllerIconView: View {
    let systemID: String
    
    var body: some View {
        Group {
            if let image = loadIcon(for: systemID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ControllerDrawingView()
            }
        }
    }
    
    private func loadIcon(for id: String) -> NSImage? {
        let name = id.lowercased()
        let bundle = Bundle.main
        
        if let url = bundle.url(forResource: name, withExtension: "ico", subdirectory: "ControllerIcons") {
            return NSImage(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "ControllerIcons") {
            return NSImage(contentsOf: url)
        }
        
        if let sys = SystemDatabase.systems.first(where: { $0.id == id }) {
            return sys.emuImage(size: 600)
        }
        
        return nil
    }
}

struct ControllerDrawingView: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.quaternary.opacity(0.1))
                .frame(width: 200, height: 120)
                .overlay(Capsule().stroke(.secondary.opacity(0.2), lineWidth: 1))
            
            HStack(spacing: 120) {
                Circle().fill(.quaternary.opacity(0.05)).frame(width: 60)
                Circle().fill(.quaternary.opacity(0.05)).frame(width: 60)
            }
            
            HStack(spacing: 60) {
                Circle().fill(.secondary.opacity(0.2)).frame(width: 30)
                Circle().fill(.secondary.opacity(0.2)).frame(width: 30)
            }
            .offset(y: 20)
            
            HStack(spacing: 100) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.secondary.opacity(0.3))
                VStack(spacing: 5) {
                    HStack(spacing: 5) { Circle().frame(width: 10); Circle().frame(width: 10) }
                    HStack(spacing: 5) { Circle().frame(width: 10); Circle().frame(width: 10) }
                }
                .foregroundColor(.secondary.opacity(0.3))
            }
            .offset(y: -15)
            
            Text("INPUT PREVIEW").font(.system(size: 8, weight: .black)).tracking(2)
                .foregroundColor(.secondary.opacity(0.5))
                .offset(y: -50)
        }
        .padding()
    }
}


// MARK: - Keyboard
struct KeyboardContentView: View {
    @EnvironmentObject var controllerService: ControllerService
    @State private var listeningFor: RetroButton? = nil
    @State private var selectedSystemID: String = "nes"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                Text("Keyboard Mapping").font(.title3.weight(.semibold))
                
                Picker("System", selection: $selectedSystemID) {
                    Text("Global / Default").tag("default")
                    Divider()
                    ForEach(SystemDatabase.systemsForDisplay) { sys in
                        Text(sys.name).tag(sys.id)
                    }
                }
                .frame(width: 280)
                
                Spacer()
                
                Button("Reset to Defaults") {
                    controllerService.updateKeyboardMapping(KeyboardMapping.defaults(for: selectedSystemID), for: selectedSystemID)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                let buttons = availableButtons(for: selectedSystemID)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(buttons, id: \.self) { btn in
                        HStack {
                            Text(btn.displayName).frame(width: 120, alignment: .leading)
                            Spacer()
                            KeyCaptureButton(
                                keyCode: controllerService.keyboardMapping(for: selectedSystemID).buttons[btn],
                                isListening: listeningFor == btn
                            ) { code in
                                var m = controllerService.keyboardMapping(for: selectedSystemID)
                                m.buttons[btn] = code
                                controllerService.updateKeyboardMapping(m, for: selectedSystemID)
                                listeningFor = nil
                            } onStartListening: {
                                listeningFor = btn
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func availableButtons(for systemID: String) -> [RetroButton] {
        return RetroButton.availableButtons(for: systemID)
    }
}

struct KeyCaptureButton: NSViewRepresentable {
    var keyCode: UInt16?
    var isListening: Bool
    var onCapture: (UInt16) -> Void
    var onStartListening: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .rounded
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.clicked)
        return btn
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = isListening ? "Press a key…" : (keyCode.map { keyName(for: $0) } ?? "—")
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject {
        var parent: KeyCaptureButton
        private var monitor: Any?
        init(parent: KeyCaptureButton) { self.parent = parent }

        @objc func clicked() {
            parent.onStartListening()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                DispatchQueue.main.async { self?.parent.onCapture(event.keyCode) }
                if let m = self?.monitor { NSEvent.removeMonitor(m); self?.monitor = nil }
                return nil
            }
        }
    }

    private func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",17:"T",16:"Y",32:"U",34:"I",
            31:"O",35:"P",36:"↩",53:"⎋",123:"←",124:"→",125:"↓",126:"↑",
            49:"Space",48:"⇥"
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - Box Art Settings
struct BoxArtSettingsView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var saved = false
    @State private var thumbnailBaseURLString = ""

    @State private var useLibretroThumbnails = true
    @State private var thumbnailServerURLStorage = ""
    @State private var thumbnailPriorityRaw = "boxart"
    @State private var useCRCMatching = true
    @State private var fallbackFilename = true
    @State private var useHeadCheck = false
    @State private var useLaunchBox = false
    @State private var launchBoxDownloadAfterScan = true

    var body: some View {
        Form {
            Section {
                Toggle("Use Libretro thumbnail CDN", isOn: $useLibretroThumbnails)
                TextField("CDN base URL", text: $thumbnailBaseURLString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Picker("Try first", selection: $thumbnailPriorityRaw) {
                    ForEach(LibretroThumbnailPriority.allCases) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }
                Toggle("Match ROM using CRC + No-Intro DAT", isOn: $useCRCMatching)
                Toggle("Fallback to sanitized filename if CRC not in DAT", isOn: $fallbackFilename)
                Toggle("Use HTTP HEAD before downloading (fewer bytes on miss)", isOn: $useHeadCheck)
            } header: {
                Label("Libretro Thumbnails", systemImage: "photo.on.rectangle.angled")
            } footer: {
                Text("Uses thumbnails.libretro.com with CRC-based names from Libretro DAT files when available, then Named_Boxarts → Named_Titles → Named_Snaps, with a fuzzy name pass.")
            }

            Section {
                Toggle("Enable LaunchBox GamesDB", isOn: $useLaunchBox)
                Toggle("Auto-download box art after scan", isOn: $launchBoxDownloadAfterScan)
            } header: {
                Label("LaunchBox GamesDB", systemImage: "gamecontroller.fill")
            } footer: {
                Text("Queries gamesdb.launchbox-app.com as a third-party fallback when the Libretro CDN has no box art. Enable auto-download to fill gaps after scanning your library.")
            }

            Section {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                Button("Save Credentials") {
                    BoxArtService.shared.saveCredentials(
                        BoxArtService.ScreenScraperCredentials(username: username, password: password))
                    saved = true
                }
            } header: {
                Label("ScreenScraper Account", systemImage: "person.badge.key")
            } footer: {
                Text("Optional fallback when Libretro CDN has no art. Create a free account at [screenscraper.fr](https://www.screenscraper.fr). Your credentials are stored locally on this device only.")
            }
            if saved {
                Label("Credentials saved!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            username = BoxArtService.shared.credentials?.username ?? ""
            useLibretroThumbnails = BoxArtService.shared.useLibretroThumbnails
            thumbnailServerURLStorage = BoxArtService.shared.thumbnailServerURL.absoluteString
            // Use rawValue directly (e.g., "boxart") to match the Picker tags
            thumbnailPriorityRaw = BoxArtService.shared.thumbnailPriority.rawValue
            useCRCMatching = BoxArtService.shared.useCRCMatchingForThumbnails
            fallbackFilename = BoxArtService.shared.fallbackToFilenameForThumbnails
            useHeadCheck = BoxArtService.shared.useHeadBeforeThumbnailDownload
            useLaunchBox = LaunchBoxGamesDBService.shared.isEnabled
            launchBoxDownloadAfterScan = LaunchBoxGamesDBService.shared.downloadAfterScan
            thumbnailBaseURLString = thumbnailServerURLStorage.isEmpty
                ? LibretroThumbnailResolver.defaultBaseURL.absoluteString
                : thumbnailServerURLStorage
        }
        .onChange(of: thumbnailBaseURLString) { _, newValue in
            thumbnailServerURLStorage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: thumbnailServerURLStorage), url.scheme != nil {
                BoxArtService.shared.thumbnailServerURL = url
            }
            AppSettings.set("thumbnail_server_url", value: thumbnailServerURLStorage)
        }
        .onChange(of: useLibretroThumbnails) { _, newVal in BoxArtService.shared.useLibretroThumbnails = newVal; AppSettings.setBool("thumbnail_use_libretro", value: newVal) }
        .onChange(of: thumbnailPriorityRaw) { _, newValue in
            if let p = LibretroThumbnailPriority(rawValue: newValue) {
                BoxArtService.shared.thumbnailPriority = p
                AppSettings.set("thumbnail_priority", value: newValue)
            }
        }
        .onChange(of: useCRCMatching) { _, newVal in BoxArtService.shared.useCRCMatchingForThumbnails = newVal; AppSettings.setBool("thumbnail_use_crc_matching", value: newVal) }
        .onChange(of: fallbackFilename) { _, newVal in BoxArtService.shared.fallbackToFilenameForThumbnails = newVal; AppSettings.setBool("thumbnail_fallback_filename", value: newVal) }
        .onChange(of: useHeadCheck) { _, newVal in BoxArtService.shared.useHeadBeforeThumbnailDownload = newVal; AppSettings.setBool("thumbnail_use_head_check", value: newVal) }
        .onChange(of: useLaunchBox) { _, newVal in LaunchBoxGamesDBService.shared.isEnabled = newVal; AppSettings.setBool("launchbox_use_for_boxart", value: newVal) }
        .onChange(of: launchBoxDownloadAfterScan) { _, newVal in LaunchBoxGamesDBService.shared.downloadAfterScan = newVal; AppSettings.setBool("launchbox_download_after_scan", value: newVal) }
    }
}

// MARK: - Display Settings
struct DisplaySettingsView: View {
    @State private var selectedPresetID: String = "builtin-crt-classic"
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @StateObject private var shaderManager = ShaderManager.shared
    
    var body: some View {
        Form {
            Section("Shader Presets") {
                LabeledContent("Default Shader") {
                    Button(ShaderManager.displayName(for: selectedPresetID)) {
                        presentShaderWindow()
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("Select a default shader preset for all games. Individual games can override this in their settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Quick Preview") {
                VStack(spacing: 8) {
                    ForEach(ShaderPreset.allPresets.prefix(4), id: \.id) { preset in
                        HStack {
                            Image(systemName: shaderIcon(for: preset.shaderType))
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                    .font(.subheadline)
                                Text(preset.description ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if preset.recommendedSystems.isEmpty {
                                Text("All systems")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(preset.recommendedSystems.prefix(3).joined(separator: ", ").uppercased())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Bezel") {
                Text("Bezel options are available in the in-game HUD (shown on hover).")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
        .onAppear {
            selectedPresetID = AppSettings.get("display_default_shader_preset", type: String.self) ?? "builtin-crt-classic"
        }
    }
    
    @MainActor
    private func presentShaderWindow() {
        if shaderWindowSettings == nil {
            shaderWindowSettings = ShaderWindowSettings(
                shaderPresetID: selectedPresetID,
                uniformValues: extractUniformValuesFromSettings()
            )
        } else {
            shaderWindowSettings?.shaderPresetID = selectedPresetID
        }
        
        let windowController = ShaderWindowController(
            settings: shaderWindowSettings!
        ) { [self] newPresetID, newUniformValues in
            selectedPresetID = newPresetID
            if let preset = ShaderPreset.preset(id: newPresetID) {
                shaderManager.activatePreset(preset)
            }
            // Update shader manager uniform values
            for (key, value) in newUniformValues {
                shaderManager.updateUniform(key, value: value)
            }
        }
        
        ShaderWindowController.shared = windowController
        windowController.show()
    }
    
    private func extractUniformValuesFromSettings() -> [String: Float] {
        var values: [String: Float] = [:]
        values["scanlineIntensity"] = 0.35 // default
        values["barrelAmount"] = 0.12 // default
        values["colorBoost"] = 1.0 // default
        return values
    }
    
    private func shaderIcon(for type: ShaderType) -> String {
        switch type {
        case .crt: return "tv"
        case .lcd: return "iphone"
        case .smoothing: return "sparkles"
        case .composite: return "waveform.path"
        case .custom: return "wrench"
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @StateObject private var launchboxService = LaunchBoxGamesDBService.shared
    @State private var autoSaveOnExit = false
    @State private var autoLoadOnStart = false
    @State private var compressSaveStates = true
    @State private var showHiddenGamesCategory: Bool = true
    @State private var launchboxEnabled: Bool = true
    @State private var showSyncConfirmation = false
    @State private var lastSyncText: String = "Never"
    
    var body: some View {
        Form {
            Section("Save States") {
                Toggle("Auto-save on game exit", isOn: $autoSaveOnExit)
                Toggle("Auto-load on game start", isOn: $autoLoadOnStart)
                Toggle("Compress save states (LZ4)", isOn: $compressSaveStates)
                
                LabeledContent("Save states location") {
                    Text("~/Library/Application Support/TruchieEmu/saves/states/")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            
            Section("Hidden Games") {
                Toggle("Show \"Hidden Games\" category in sidebar", isOn: $showHiddenGamesCategory)
                Text("When disabled, hidden games will still exist but the category won't be visible in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("LaunchBox GamesDB") {
                Toggle("Enable LaunchBox GamesDB", isOn: $launchboxEnabled)
                Text("Automatically fetch game metadata — descriptions, developer, publisher, genre, max players, cooperative play, and ESRB ratings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                LabeledContent("Last sync") {
                    if launchboxService.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Syncing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(lastSyncText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if launchboxService.isSyncing {
                    VStack(spacing: 8) {
                        ProgressView(value: launchboxService.syncProgress)
                        Text(launchboxService.syncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button("Sync All Games Now") {
                    showSyncConfirmation = true
                }
                .disabled(launchboxService.isSyncing || !launchboxEnabled)
                .confirmationDialog(
                    "Sync All Games",
                    isPresented: $showSyncConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Start Sync") {
                        Task {
                            await launchboxService.batchSyncLibrary(library: library) { _, _, _ in }
                            updateLastSyncText()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will search the LaunchBox Games Database for all games in your library that are missing metadata. This may take a while depending on your library size.")
                }
            }
            
            Section("Application") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
            showHiddenGamesCategory = AppSettings.getBool("showHiddenGamesCategory", defaultValue: true)
            launchboxEnabled = launchboxService.isEnabled
            autoSaveOnExit = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
            autoLoadOnStart = AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: false)
            compressSaveStates = AppSettings.getBool("saveState_compress", defaultValue: true)
            updateLastSyncText()
        }
        .onChange(of: showHiddenGamesCategory) { _, newValue in
            AppSettings.setBool("showHiddenGamesCategory", value: newValue)
        }
        .onChange(of: launchboxEnabled) { _, newValue in
            launchboxService.setEnabled(newValue)
        }
        .onChange(of: autoSaveOnExit) { _, newValue in
            AppSettings.setBool("saveState_autoSaveOnExit", value: newValue)
        }
        .onChange(of: autoLoadOnStart) { _, newValue in
            AppSettings.setBool("saveState_autoLoadOnStart", value: newValue)
        }
        .onChange(of: compressSaveStates) { _, newValue in
            AppSettings.setBool("saveState_compress", value: newValue)
        }
    }
    
    private func updateLastSyncText() {
        if let date = launchboxService.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            lastSyncText = formatter.localizedString(for: date, relativeTo: Date())
        } else {
            lastSyncText = "Never"
        }
    }
}

// MARK: - About
struct AboutView: View {
    @State private var expandedSections: Set<String> = []
    
    var body: some View {

        ScrollView {
            VStack(spacing: 24) {
                // App Identity
                VStack(spacing: 12) {
                    Image(systemName: "arcade.stick")
                        .font(.system(size: 60))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("TruchieEmu")
                        .font(.largeTitle.weight(.bold))
                    Text("A beautiful macOS libretro frontend")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                Divider()
                
                // Third-Party Dependencies
                VStack(alignment: .leading, spacing: 16) {
                    Text("Third-Party Software & Services")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // --- Core Engine ---
                    DependencySection(
                        title: "Emulation Cores (libretro)",
                        isExpanded: Binding(
                            get: { expandedSections.contains("cores") },
                            set: { if $0 { expandedSections.insert("cores") } else { expandedSections.remove("cores") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "RetroArch / libretro",
                            url: "https://libretro.com",
                            license: "GPL-3.0",
                            licenseURL: "https://github.com/libretro/RetroArch/blob/master/COPYING",
                            description: "libretro API — the universal emulation interface that enables cores to run within any compatible frontend."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Nestopia (NES core)",
                            url: "https://github.com/libretro/nestopia-libretro",
                            license: "GPL-2.0-or-later",
                            licenseURL: "https://github.com/libretro/nestopia-libretro/blob/master/COPYING",
                            description: "Cycle-accurate NES/Famicom emulator with libretro interface. Based on the Nestopia JG fork by Rupert Carmichael."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Snes9x (SNES core)",
                            url: "https://www.snes9x.com",
                            license: "Non-Commercial Freeware",
                            licenseURL: "https://github.com/libretro/snes9x/blob/master/LICENSE",
                            description: "Portable Super Nintendo Entertainment System emulator. Licensed for non-commercial personal use only. Commercial use requires explicit permission from the copyright holders."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Mupen64Plus-Next (N64 core)",
                            url: "https://github.com/libretro/mupen64plus-libretro-nx",
                            license: "GPL-2.0",
                            licenseURL: "https://github.com/libretro/mupen64plus-libretro-nx/blob/develop/LICENSE",
                            description: "N64 emulation library for the libretro API, based on Mupen64Plus. Incorporates GLideN64, cxd4, parallel-rsp, and angrylion-rdp-plus."
                        )
                        
                        Divider()
                        
                        Text("Additional cores (mGBA, Genesis Plus GX, DOSBox Pure, ScummVM, MAME variants, etc.) are available from the libretro buildbot and each carries its own license. Visit the individual repositories on GitHub for details.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    // --- Databases & Content ---
                    DependencySection(
                        title: "Game Databases & Content",
                        isExpanded: Binding(
                            get: { expandedSections.contains("databases") },
                            set: { if $0 { expandedSections.insert("databases") } else { expandedSections.remove("databases") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "libretro database",
                            url: "https://github.com/libretro/libretro-database",
                            license: "CC-BY-SA-4.0",
                            licenseURL: "https://github.com/libretro/libretro-database/blob/master/LICENSE",
                            description: "Cheat code files, game metadata (ROM scanning, naming, thumbnails), and content data files used for game identification and library management. Contains data imported from No-Intro, Redump, TOSEC, GameTDB, MAME, and community contributions."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "Game Database (No-Intro, Redump, TOSEC)",
                            url: "https://www.no-intro.org",
                            license: "Various",
                            licenseURL: nil,
                            description: "Third-party ROM databases (No-Intro, Redump, TOSEC) included in the libretro database for game identification and naming. Each maintains its own licensing terms."
                        )
                    }
                    
                    // --- Bezel Project ---
                    DependencySection(
                        title: "Visual Overlays",
                        isExpanded: Binding(
                            get: { expandedSections.contains("bezels") },
                            set: { if $0 { expandedSections.insert("bezels") } else { expandedSections.remove("bezels") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "The Bezel Project",
                            url: "https://github.com/thebezelproject",
                            license: "Various (per-repository)",
                            licenseURL: nil,
                            description: "Community-created PNG bezel overlays for retro gaming systems. Bezels are provided per-system and cover a vast library of games."
                        )
                    }
                    
                    // --- Box Art ---
                    DependencySection(
                        title: "Box Art & Thumbnails",
                        isExpanded: Binding(
                            get: { expandedSections.contains("boxart") },
                            set: { if $0 { expandedSections.insert("boxart") } else { expandedSections.remove("boxart") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "libretro thumbnails CDN",
                            url: "https://thumbnails.libretro.com",
                            license: "Various",
                            licenseURL: nil,
                            description: "Official libretro thumbnail hosting for box art, screenshots, and game media. Thumbnail filenames derived from the libretro database naming conventions."
                        )
                        
                        Divider()
                        
                        DependencyGroup(
                            name: "ScreenScraper",
                            url: "https://www.screenscraper.fr",
                            license: "CC-BY-NC-SA-4.0",
                            licenseURL: "https://www.screenscraper.fr",
                            description: "Optional fallback box art and metadata API. Media and data contributed by the ScreenScraper community. Licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. Requires a free account for API access."
                        )                        
                        Divider()
                        
                        DependencyGroup(
                            name: "LaunchBox GamesDB",
                            url: "https://gamesdb.launchbox-app.com",
                            license: "Various",
                            licenseURL: nil,
                            description: "Game media and boxart database powering the LaunchBox and Big Box frontends. Used as an optional third-party fallback source for game artwork."
                        )
                    }
                    
                    // --- RetroAchievements ---
                    DependencySection(
                        title: "Achievement Tracking",
                        isExpanded: Binding(
                            get: { expandedSections.contains("achievements") },
                            set: { if $0 { expandedSections.insert("achievements") } else { expandedSections.remove("achievements") } }
                        )
                    ) {
                        DependencyGroup(
                            name: "RetroAchievements",
                            url: "https://retroachievements.org",
                            license: "Proprietary — Service",
                            licenseURL: nil,
                            description: "Community-driven platform for retro gaming achievements. TruchieEmu integrates with the RetroAchievements API to display and track achievements. All achievement data, badges, and sets are the property of RetroAchievements and their contributors."
                        )
                    }
                    
                    Divider()
                    
                    // --- General Notes ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Acknowledgment")
                            .font(.headline)
                        Text("TruchieEmu is built entirely on the shoulders of giants. The emulation cores, game databases, artwork, and achievement systems are all the result of thousands of hours of volunteer work by the retro gaming community. This app would not be possible without their generosity.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Collapsible Dependency Section
struct DependencySection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.top, 8)
                .padding(.leading, 20)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Dependency Group (name + license + link)
struct DependencyGroup: View {
    let name: String
    let url: String
    let license: String
    let licenseURL: String?
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                if let validURL = URL(string: url) {
                    Link(destination: validURL) {
                        Image(systemName: "link")
                            .font(.caption)
                    }
                }
            }
            HStack(spacing: 4) {
                Text("License:")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(license)
                    .font(.caption)
                    .foregroundColor(.purple)
                if let licenseURL = licenseURL, let url = URL(string: licenseURL) {
                    Link(destination: url) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .help("View full license")
                }
            }
            Text(description)
                .foregroundColor(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
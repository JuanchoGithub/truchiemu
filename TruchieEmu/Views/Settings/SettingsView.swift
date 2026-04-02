import SwiftUI
import GameController

// MARK: - Main Settings View
struct SettingsView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService

    private enum Page: Hashable { case general, library, cores, controllers, keyboard, boxArt, display, retroAchievements, about }
    @State private var selectedPage: Page = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                sidebarItem(icon: "gearshape.fill", label: "General", page: .general)
                sidebarItem(icon: "book.fill", label: "Library", page: .library)
                sidebarItem(icon: "cpu.fill", label: "Cores", page: .cores)
                sidebarItem(icon: "gamecontroller.fill", label: "Controllers", page: .controllers)
                sidebarItem(icon: "keyboard.fill", label: "Keyboard", page: .keyboard)
                sidebarItem(icon: "photo.stack.fill", label: "Box Art", page: .boxArt)
                sidebarItem(icon: "tv.fill", label: "Display", page: .display)
                sidebarItem(icon: "trophy.fill", label: "RetroAchievements", page: .retroAchievements)
                sidebarItem(icon: "info.circle.fill", label: "About", page: .about)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            .scrollContentBackground(.hidden)
        } detail: {
            Group {
                switch selectedPage {
                case .general:     GeneralSettingsView()
                case .library:     LibrarySettingsView()
                case .cores:       CoreSettingsView()
                case .controllers: ControllerSettingsView()
                case .keyboard:    KeyboardSettingsView()
                case .boxArt:      BoxArtSettingsView()
                case .display:     DisplaySettingsView()
                case .retroAchievements: RetroAchievementsSettingsView()
                case .about:       AboutView()
                }
            }
            .frame(minWidth: 550, minHeight: 420)
        }
        .navigationSplitViewStyle(.prominentDetail)
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
    @State private var scanningFolders: Set<Int> = []
    @ObservedObject var prefs = SystemPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Display Options Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Display Options", systemImage: "eyeglasses")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 0) {
                        Toggle(isOn: $prefs.showBiosFiles) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show BIOS Files in Game List")
                                    .font(.body)
                                Text("When enabled, BIOS files will appear alongside playable games")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.top, 4)
                }
                
                // Library Folders Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Library Folders", systemImage: "folder.fill")
                            .font(.headline)
                        Spacer()
                        Button(action: addLibraryFolder) {
                            Label("Add Folder", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if library.libraryFolders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("No library folders added yet")
                                .foregroundColor(.secondary)
                            Text("Add a folder containing your ROM files to get started.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.top, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(library.libraryFolders.enumerated()), id: \.element) { index, folder in
                                LibraryFolderRow(
                                    folder: folder,
                                    index: index,
                                    isScanning: scanningFolders.contains(index)
                                ) {
                                    Task {
                                        scanningFolders.insert(index)
                                        await library.rescanLibrary(at: folder)
                                        scanningFolders.remove(index)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Maintenance Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Maintenance", systemImage: "wrench.and.screwdriver")
                            .font(.headline)
                    }
                    
                    VStack(spacing: 0) {
                        Button(action: { Task { await library.fullRescan() } }) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                VStack(alignment: .leading) {
                                    Text("Full Library Rebuild")
                                        .font(.body)
                                    Text("Clear and rebuild all game data from folders")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if library.isScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Total Games: \(library.roms.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Folders: \(library.libraryFolders.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Library")
    }
    
    private func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url {
            library.addLibraryFolder(url: url)
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

    private var selectedSystem: SystemInfo? {
        if let id = selectedSystemID {
            return SystemDatabase.system(forID: id)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // System selection header - with proper top padding
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TruchieEmu Settings")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Select System")
                            .font(.headline)
                    }
                    Spacer()
                    Button("Refresh List") { Task { await coreManager.fetchAvailableCores() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(coreManager.isFetchingCoreList)
                }
                
                if coreManager.isFetchingCoreList {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching core list from buildbot...")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
            .padding(.bottom, 12)

            Divider()
            
            HStack(spacing: 0) {
                // System list (middle column)
                VStack(spacing: 0) {
                    Text("Systems")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    
                    List(selection: $selectedSystemID) {
                        ForEach(SystemDatabase.systems.sorted(by: { $0.name < $1.name })) { sys in
                            SystemRowView(system: sys, coreManager: coreManager)
                                .tag(sys.id)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 220, maxWidth: 300)
                }
                .border(.separator, width: 0.5)
                
                Divider()
                
                // Cores list (right pane)
                VStack(spacing: 0) {
                    if let system = selectedSystem {
                        Text(system.name)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        
                        SystemCoresView(system: system, coreManager: coreManager)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "gamecontroller")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Select a system to see available cores")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .clipped()
        .onAppear {
            if coreManager.availableCores.isEmpty {
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
        HStack(spacing: 10) {
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
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer()
            
            if hasInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                    .frame(width: 16)
                    .fixedSize()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
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
    @State private var selectedPlayer: Int = 0
    @State private var selectedSystemID: String = "default"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // Player tabs
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { i in
                        let connected = controllerService.connectedControllers.first(where: { $0.playerIndex == i })?.isConnected ?? false
                        Button("P\(i)") { selectedPlayer = i }
                            .buttonStyle(.bordered)
                            .tint(selectedPlayer == i ? .purple : .secondary)
                            .overlay(
                                connected ? Circle().fill(.green).frame(width: 6, height: 6).offset(x: 10, y: -10) : nil,
                                alignment: .topTrailing
                            )
                    }
                }
                
                Spacer()
                
                Picker("Mapping for System", selection: $selectedSystemID) {
                    Text("Global / Default").tag("default")
                    Divider()
                    ForEach(SystemDatabase.systems) { sys in
                        Text(sys.name).tag(sys.id)
                    }
                }
                .frame(width: 280)
            }
            .padding([.horizontal, .top])

            Divider()

            if let player = controllerService.connectedControllers.first(where: { $0.playerIndex == selectedPlayer }) {
                ControllerMappingDetail(player: player, systemID: selectedSystemID)
                    .id("\(selectedPlayer)-\(selectedSystemID)")
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
        .onAppear { selectedPlayer = controllerService.connectedControllers.first?.playerIndex ?? 1 }
    }
}

struct ControllerMappingDetail: View {
    @EnvironmentObject var controllerService: ControllerService
    let player: PlayerController
    let systemID: String
    @State private var listeningFor: RetroButton? = nil
    @State private var mapping: ControllerMapping

    init(player: PlayerController, systemID: String) {
        self.player = player
        self.systemID = systemID
        _mapping = State(initialValue: ControllerService.shared.mapping(for: player.gcController?.vendorName ?? "Unknown", systemID: systemID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.purple)
                Text(player.name)
                    .font(.headline)
                Spacer()
                Button("Reset to Defaults") {
                    mapping = ControllerMapping.defaults(for: player.mapping.vendorName, systemID: systemID)
                    save()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 32) {
                        ControllerIconView(systemID: systemID)
                        
                        Divider().frame(height: 100)
                        
                        HStack(spacing: 20) {
                            StickTesterView(x: lStickState.x, y: lStickState.y, label: "LEFT STICK")
                            StickTesterView(x: rStickState.x, y: rStickState.y, label: "RIGHT STICK")
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.secondary.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        let buttons = RetroButton.availableButtons(for: systemID)
                        ForEach(buttons, id: \.self) { btn in
                            buttonRow(btn)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .onAppear { startStickVisualizer() }
    }

    private func buttonRow(_ btn: RetroButton) -> some View {
        HStack {
            Text(btn.displayName)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Button(listeningFor == btn ? "Press a button…" : (mapping.buttons[btn]?.gcElementAlias ?? "—")) {
                listeningFor = btn
                listenForButton(btn)
            }
            .buttonStyle(.bordered)
            .tint(listeningFor == btn ? .orange : .secondary)
        }
    }

    private func listenForButton(_ btn: RetroButton) {
        guard let gc = player.gcController else { return }
        gc.extendedGamepad?.valueChangedHandler = { pad, element in
            if let dpad = element as? GCControllerDirectionPad {
                if dpad.up.isPressed { save(dpad.up) }
                else if dpad.down.isPressed { save(dpad.down) }
                else if dpad.left.isPressed { save(dpad.left) }
                else if dpad.right.isPressed { save(dpad.right) }
            } else if let button = element as? GCControllerButtonInput, button.isPressed {
                save(button)
            } else if let axis = element as? GCControllerAxisInput, abs(axis.value) > 0.6 {
                save(axis)
            }
        }
        
        func save(_ element: GCControllerElement) {
            let name = element.localizedName ?? "Button"
            DispatchQueue.main.async {
                mapping.buttons[btn] = GCButtonMapping(gcElementName: name, gcElementAlias: name)
                listeningFor = nil
                gc.extendedGamepad?.valueChangedHandler = nil
                self.save()
            }
        }
    }

    private func save() {
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
                
                Circle().fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
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
        if let image = loadIcon(for: systemID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 110)
                .padding(8)
                .background(.white.opacity(0.05))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        } else {
            ControllerDrawingView()
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

struct KeyboardSettingsView: View {
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
                    ForEach(SystemDatabase.systems) { sys in
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

    @AppStorage("thumbnail_use_libretro") private var useLibretroThumbnails = true
    @AppStorage("thumbnail_server_url") private var thumbnailServerURLStorage = ""
    @AppStorage("thumbnail_priority_type") private var thumbnailPriorityRaw = LibretroThumbnailPriority.boxart.rawValue
    @AppStorage("thumbnail_use_crc_matching") private var useCRCMatching = true
    @AppStorage("thumbnail_fallback_filename") private var fallbackFilename = true
    @AppStorage("thumbnail_use_head_check") private var useHeadCheck = false

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
            thumbnailBaseURLString = thumbnailServerURLStorage.isEmpty
                ? LibretroThumbnailResolver.defaultBaseURL.absoluteString
                : thumbnailServerURLStorage
        }
        .onChange(of: thumbnailBaseURLString) { newValue in
            thumbnailServerURLStorage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - Display Settings
struct DisplaySettingsView: View {
    @AppStorage("display_default_shader_preset") private var selectedPresetID: String = "builtin-crt-classic"
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
                    ForEach(ShaderPreset.builtinPresets.prefix(4), id: \.id) { preset in
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
    }
    
    @MainActor
    private func presentShaderWindow() {
        if shaderWindowSettings == nil {
            shaderWindowSettings = ShaderWindowSettings(
                shaderPresetID: selectedPresetID,
                uniformValues: [:]
            )
        } else {
            shaderWindowSettings?.shaderPresetID = selectedPresetID
        }
        
        let windowController = ShaderWindowController(
            settings: shaderWindowSettings!
        ) { [self] newPresetID in
            selectedPresetID = newPresetID
            if let preset = ShaderPreset.preset(id: newPresetID) {
                shaderManager.activatePreset(preset)
            }
        }
        
        ShaderWindowController.shared = windowController
        windowController.show()
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
    @AppStorage("logging_enabled") private var loggingEnabled = false
    @AppStorage("logging_level") private var loggingLevel: Int = 1 // 0=None, 1=Info, 2=Debug
    @AppStorage("auto_save_on_exit") private var autoSaveOnExit = true
    @AppStorage("auto_load_on_start") private var autoLoadOnStart = true
    @AppStorage("compress_save_states") private var compressSaveStates = false
    
    var body: some View {
        Form {
            Section("Save States") {
                Toggle("Auto-save on game exit", isOn: $autoSaveOnExit)
                    .toggleStyle(.switch)
                Toggle("Auto-load on game start", isOn: $autoLoadOnStart)
                    .toggleStyle(.switch)
                Toggle("Compress save states (LZ4)", isOn: $compressSaveStates)
                    .toggleStyle(.switch)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save states are stored in:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("~/Library/Application Support/TruchieEmu/saves/states/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
            
            Section("Logging") {
                Toggle("Enable Logging", isOn: $loggingEnabled)
                    .toggleStyle(.switch)
                
                if loggingEnabled {
                    Picker("Log Level", selection: $loggingLevel) {
                        Text("None").tag(0)
                        Text("Info").tag(1)
                        Text("Debug").tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log levels:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Info: Core loading, game launches, shader changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Debug: Metal pipeline, frame rendering, detailed emulation info")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundColor(.secondary)
                    Text("Logs appear in Console.app (filter by 'TruchieEmu') or Xcode debug console")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    }
}

// MARK: - About
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arcade.stick")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("TruchieEmu")
                .font(.largeTitle.weight(.bold))
            Text("A beautiful macOS libretro frontend")
                .foregroundColor(.secondary)
            Divider().frame(width: 200)
            VStack(spacing: 8) {
                Link("libretro.com", destination: URL(string: "https://libretro.com")!)
                Link("screenscraper.fr", destination: URL(string: "https://screenscraper.fr")!)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
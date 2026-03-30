import SwiftUI

struct LibraryGridView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    var filter: LibraryFilter
    @Binding var selectedROM: ROM?
    @Binding var searchText: String

    @Environment(\.openWindow) private var openWindow
    @State private var renamingROM: ROM? = nil
    @State private var renameText: String = ""
    @State private var gameWindowController: StandaloneGameWindowController? = nil

    @State private var viewMode: ViewMode = .grid
    @AppStorage("gridColumns") private var columnCount: Int = 4
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject var boxArtService = BoxArtService.shared
    @State private var manualBoxArtSearchROM: ROM?

    private enum ViewMode: String { case grid, list }

    private var displayedROMs: [ROM] {
        let base: [ROM]
        switch filter {
        case .all:
            base = library.roms
        case .favorites:
            base = library.roms.filter { $0.isFavorite }
        case .recent:
            base = library.roms.filter { $0.lastPlayed != nil }
                .sorted { ($0.lastPlayed ?? Date.distantPast) > ($1.lastPlayed ?? Date.distantPast) }
        case .system(let system):
            base = library.roms.filter { $0.systemID == system.id }
        }

        if searchText.isEmpty {
            return base
        } else {
            let searchTerms = searchText.split(separator: " ")
            return base.filter { rom in
                searchTerms.allSatisfy { term in
                    rom.displayName.localizedCaseInsensitiveContains(term)
                }
            }
        }
    }
    @State private var columns: [GridItem] = []

    var body: some View {
        VStack(spacing: 0) {
            searchField
            
            ZStack {
                if library.isScanning {
                    scanningOverlay
                } else if displayedROMs.isEmpty {
                    emptyState
                } else if viewMode == .grid {
                    gridView
                } else {
                    listView
                }
                
                if boxArtService.isDownloadingBatch {
                    VStack {
                        Spacer()
                        downloadingArtOverlay
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Rename Game", isPresented: Binding(
            get: { renamingROM != nil },
            set: { if !$0 { renamingROM = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let rom = renamingROM {
                    var updated = rom
                    updated.customName = renameText.isEmpty ? nil : renameText
                    library.updateROM(updated)
                }
                renamingROM = nil
            }
            Button("Cancel", role: .cancel) {
                renamingROM = nil
            }
        }
        .toolbar {
            ToolbarItemGroup {
                // Controller Selection
                Menu {
                    Button(action: { controllerService.activePlayerIndex = 0 }) {
                        Label("Keyboard", systemImage: "keyboard")
                            .symbolVariant(controllerService.activePlayerIndex == 0 ? .fill : .none)
                    }
                    
                    Divider()
                    
                    if controllerService.connectedControllers.isEmpty {
                        Text("No Controllers Detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(controllerService.connectedControllers) { controller in
                            Button(action: { controllerService.activePlayerIndex = controller.playerIndex }) {
                                Label(controller.name, systemImage: "gamecontroller")
                                    .symbolVariant(controllerService.activePlayerIndex == controller.playerIndex ? .fill : .none)
                            }
                        }
                    }
                } label: {
                    let activeName = controllerService.activePlayerIndex == 0 ? "Keyboard" : 
                        (controllerService.connectedControllers.first(where: { $0.playerIndex == controllerService.activePlayerIndex })?.name ?? "Disconnected")
                    
                    HStack(spacing: 4) {
                        Image(systemName: controllerService.activePlayerIndex == 0 ? "keyboard" : "gamecontroller")
                        Text(activeName)
                            .font(.caption)
                    }
                }

                // Language Selection
                Menu {
                    Picker("System Language", selection: Binding(
                        get: { prefs.systemLanguage },
                        set: { prefs.systemLanguage = $0 }
                    )) {
                        ForEach(EmulatorLanguage.allCases) { lang in
                            Text(lang.name).tag(lang)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(prefs.systemLanguage.name)
                            .font(.caption)
                    }
                }

                // Log Level Selection
                Menu {
                    Picker("Core Logs", selection: Binding(
                        get: { prefs.coreLogLevel },
                        set: { prefs.coreLogLevel = $0 }
                    )) {
                        ForEach(CoreLogLevel.allCases) { level in
                            Text(level.name).tag(level)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle")
                        Text(prefs.coreLogLevel == .info ? "Verbose" : (prefs.coreLogLevel == .none ? "Silenced" : "Logs"))
                            .font(.caption)
                    }
                }

                if case .system(let system) = filter {
                    Menu {
                        Picker("Box Type", selection: Binding(
                            get: { prefs.boxType(for: system.id) },
                            set: { prefs.setBoxType($0, for: system.id) }
                        )) {
                            ForEach(BoxType.allCases) { type in
                                Label(type.rawValue, systemImage: type.iconName).tag(type)
                            }
                        }
                    } label: {
                        Image(systemName: prefs.boxType(for: system.id).iconName)
                    }
                    .opacity(viewMode == .grid ? 1 : 0)
                }

                Slider(value: Binding(
                    get: { Double(columnCount) },
                    set: { columnCount = Int($0) }
                ), in: 2...8, step: 1)
                .frame(width: 80)
                .opacity(viewMode == .grid ? 1 : 0)

                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 70)

                Button {
                    Task {
                        await BoxArtService.shared.batchDownloadBoxArtLibretro(for: displayedROMs, library: library)
                    }
                } label: {
                    Label("Fetch missing art", systemImage: "arrow.down.circle")
                }
                .help("Download missing box art from Libretro CDN (CRC + DAT when enabled)")
            }
        }
        .sheet(item: $manualBoxArtSearchROM) { rom in
            BoxArtPickerView(rom: rom)
        }
        .onAppear { 
            updateColumns()
        }
        .onChange(of: columnCount) { _ in updateColumns() }
    }


    private func updateColumns() {
        columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(displayedROMs) { rom in
                    GameCardView(rom: rom, isSelected: selectedROM?.id == rom.id)
                        .contentShape(Rectangle()) // Ensure the whole card is tappable
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    // Instant selection on "push down"
                                    if selectedROM?.id != rom.id {
                                        selectedROM = rom
                                    }
                                }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                launchGame(rom)
                            }
                        )
                        .contextMenu { contextMenu(for: rom) }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List(displayedROMs, selection: $selectedROM) { rom in
            GameListRowView(rom: rom)
                .tag(rom)
                .onTapGesture(count: 2) {
                    launchGame(rom)
                }
                .contextMenu { contextMenu(for: rom) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            ProgressView(value: library.scanProgress)
                .frame(width: 280)
            Text("Scanning your ROM library…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var downloadingArtOverlay: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Downloading Box Art… \(boxArtService.downloadedCount) / \(boxArtService.downloadQueueCount)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No games found" : "No results for \(searchText)")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for rom: ROM) -> some View {
        Button {
            openWindow(id: "game-info", value: rom.id)
        } label: {
            Label("See Game Info", systemImage: "info.circle")
        }
        
        Button {
            launchGame(rom)
        } label: {
            Label("Launch Game", systemImage: "play.fill")
        }

        Button {
            renameText = rom.customName ?? rom.metadata?.title ?? rom.name
            renamingROM = rom
        } label: {
            Label("Rename Game", systemImage: "pencil")
        }

        Divider()
        Button(rom.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            var updated = rom
            updated.isFavorite.toggle()
            library.updateROM(updated)
        }
        Divider()
        Button("Get Box Art") {
            manualBoxArtSearchROM = rom
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(rom.path.path, inFileViewerRootedAtPath: "")
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search games…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 8)
    }

    private func launchGame(_ rom: ROM) {
        // Find system and core
        guard let sysID = rom.systemID,
              let system = SystemDatabase.system(forID: sysID) else { return }
        
        // Check if preferred core is installed
        let sysPrefs = SystemPreferences.shared
        let coreID = rom.useCustomCore ? (rom.selectedCoreID ?? sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID) : (sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)
        
        guard let cid = coreID else { return }
        
        // Ensure the core is actually installed on disk
        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID)
            return
        }

        // Log game played
        library.markPlayed(rom)
        
        // Launch in standalone window
        let runner = EmulatorRunner.forSystem(sysID)
        let controller = StandaloneGameWindowController(runner: runner)
        self.gameWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        runner.launch(rom: rom, coreID: cid)
    }
}

// MARK: - Game Card

struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    @State private var isHovered = false
    @State private var image: NSImage?
    @ObservedObject var prefs = SystemPreferences.shared

    private var boxType: BoxType {
        prefs.boxType(for: rom.systemID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artworkView
            Text(rom.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 32, alignment: .topLeading)
                .foregroundColor(.primary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .task(id: rom.boxArtPath) {
            if let artPath = rom.boxArtPath {
                // Load image asynchronously
                self.image = await ImageCache.shared.image(for: artPath)
            } else {
                self.image = nil
            }
        }
    }

    private var artworkView: some View {
        ZStack {
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholderArt
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(boxType.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }


    private var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors: [systemColor.opacity(0.6), systemColor.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                if let sys = SystemDatabase.system(forID: rom.systemID ?? ""),
                   let img = sys.emuImage(size: 600) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: systemIcon)
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Text(rom.displayName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var systemIcon: String {
        SystemDatabase.system(forID: rom.systemID ?? "")?.iconName ?? "gamecontroller"
    }

    private var systemColor: Color {
        let colors: [Color] = [.purple, .blue, .cyan, .green, .orange, .red, .pink]
        let hash = abs((rom.systemID ?? "x").hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - List Row

struct GameListRowView: View {
    let rom: ROM
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            artThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(rom.displayName)
                    .font(.body.weight(.medium))
                if let sys = SystemDatabase.system(forID: rom.systemID ?? "") {
                    HStack(spacing: 4) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
                        Text(sys.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if rom.isFavorite {
                Image(systemName: "heart.fill").foregroundColor(.pink).font(.caption)
            }
            if let played = rom.lastPlayed {
                Text(played, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: rom.boxArtPath) {
            if let artPath = rom.boxArtPath {
                self.thumb = await ImageCache.shared.image(for: artPath)
            } else {
                self.thumb = nil
            }
        }
    }

    private var artThumb: some View {
        Group {
            if let img = thumb {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                let sys = SystemDatabase.system(forID: rom.systemID ?? "")
                if let emuImg = sys?.emuImage(size: 132) {
                    Image(nsImage: emuImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: sys?.iconName ?? "gamecontroller")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.1))
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

import SwiftUI
import AppKit

actor ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSURL, NSImage>()
    
    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Load on background thread
        let image = await Task.detached(priority: .userInitiated) {
            return NSImage(contentsOf: url)
        }.value
        
        if let image = image {
            cache.setObject(image, forKey: url as NSURL)
        }
        
        return image
    }
    
    func clear() {
        cache.removeAllObjects()
    }
    
    func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}

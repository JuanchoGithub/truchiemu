import SwiftUI

struct LibraryGridView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    var filter: LibraryFilter
    @Binding var selectedROM: ROM?
    @Binding var searchText: String

    @State private var showingInfoROM: ROM? = nil
    @State private var gameWindowController: StandaloneGameWindowController? = nil

    @State private var viewMode: ViewMode = .grid
    @AppStorage("gridColumns") private var columnCount: Int = 4
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject var boxArtService = BoxArtService.shared
    @State private var manualBoxArtSearchROM: ROM?

    private enum ViewMode: String { case grid, list }

    private var filteredROMs: [ROM] {
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

        if searchText.isEmpty { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }
    var body: some View {
        VStack(spacing: 0) {
            searchField
            
            ZStack {
                if library.isScanning {
                    scanningOverlay
                } else if filteredROMs.isEmpty {
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
        .sheet(item: $showingInfoROM) { rom in
            GameDetailView(rom: rom)
                .frame(minWidth: 500, minHeight: 600)
        }
        .toolbar {
            ToolbarItemGroup {
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
            }
        }
        .sheet(item: $manualBoxArtSearchROM) { rom in
            AutoBoxArtPickerView(rom: rom)
        }
    }

    private var gridView: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredROMs) { rom in
                    GameCardView(rom: rom, isSelected: selectedROM?.id == rom.id)
                        .onTapGesture { selectedROM = rom }
                        .onTapGesture(count: 2) { 
                            selectedROM = rom
                            launchGame(rom)
                        }
                        .contextMenu { contextMenu(for: rom) }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List(filteredROMs, selection: $selectedROM) { rom in
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
            showingInfoROM = rom
        } label: {
            Label("See Game Info", systemImage: "info.circle")
        }
        
        Button {
            launchGame(rom)
        } label: {
            Label("Launch Game", systemImage: "play.fill")
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
    }

    private var artworkView: some View {
        ZStack {
            if let artPath = rom.boxArtPath,
               let nsImage = NSImage(contentsOf: artPath) {
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
                Image(systemName: systemIcon)
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
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

    var body: some View {
        HStack(spacing: 12) {
            artThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(rom.displayName)
                    .font(.body.weight(.medium))
                if let sys = SystemDatabase.system(forID: rom.systemID ?? "") {
                    Text(sys.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    }

    private var artThumb: some View {
        Group {
            if let artPath = rom.boxArtPath, let img = NSImage(contentsOf: artPath) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: SystemDatabase.system(forID: rom.systemID ?? "")?.iconName ?? "gamecontroller")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Manual Box Art Picker

struct AutoBoxArtPickerView: View {
    let rom: ROM
    @State private var candidates: [URL]? = nil
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var library: ROMLibrary
    
    var body: some View {
        VStack {
            Text("Select Box Art for \(rom.displayName)")
                .font(.headline)
                .padding()
            
            if let candidates = candidates {
                if candidates.isEmpty {
                    Text("No box art found.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(candidates, id: \.self) { url in
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFit()
                                    } else if phase.error != nil {
                                        Color.red.overlay(Text("Failed to load").foregroundColor(.white).font(.caption))
                                    } else {
                                        ProgressView()
                                    }
                                }
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 4)
                                .onTapGesture {
                                    Task {
                                        if let stored = await BoxArtService.shared.downloadAndCache(artURL: url, for: rom) {
                                            var updated = rom
                                            updated.boxArtPath = stored
                                            await MainActor.run { library.updateROM(updated) }
                                        }
                                        dismiss()
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Searching Google Images and DuckDuckGo...")
                        .foregroundColor(.secondary)
                }
                .padding(40)
            }
            
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            candidates = await BoxArtService.shared.fetchBoxArtCandidates(query: rom.displayName, systemID: rom.systemID ?? "")
        }
    }
}

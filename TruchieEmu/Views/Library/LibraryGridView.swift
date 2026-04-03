import SwiftUI
import AppKit

// MARK: - Game Filter Options

/// Filter chips for refining the game library view
enum GameFilterOption: String, CaseIterable, Identifiable {
    case noBoxArt      = "noBoxArt"
    case neverPlayed   = "neverPlayed"
    case notFavorite   = "notFavorite"
    case unscanned     = "unscanned"
    case multiplayer   = "multiplayer"
    case hasMetadata   = "hasMetadata"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .noBoxArt:     return "photo"
        case .neverPlayed:  return "play.slash"
        case .notFavorite:  return "heart.slash"
        case .unscanned:    return "qrcode.viewfinder"
        case .multiplayer:  return "person.2.fill"
        case .hasMetadata:  return "info.circle"
        }
    }
    
    var label: String {
        switch self {
        case .noBoxArt:     return "No Box Art"
        case .neverPlayed:  return "Never Played"
        case .notFavorite:  return "Not Favorite"
        case .unscanned:    return "Unidentified"
        case .multiplayer:  return "Multiplayer"
        case .hasMetadata:  return "Has Metadata"
        }
    }
    
    var tooltip: String {
        switch self {
        case .noBoxArt:     return "Games missing cover art"
        case .neverPlayed:  return "Games that have never been launched"
        case .notFavorite:  return "Games not marked as favorites"
        case .unscanned:    return "Games lacking identification data"
        case .multiplayer:  return "Games supporting 2+ players"
        case .hasMetadata:  return "Games with a metadata title"
        }
    }
    
    func matches(_ rom: ROM) -> Bool {
        let fm = FileManager.default
        switch self {
        case .noBoxArt:
            if let p = rom.boxArtPath { return !fm.fileExists(atPath: p.path) }
            return true
        case .neverPlayed:
            return rom.lastPlayed == nil
        case .notFavorite:
            return !rom.isFavorite
        case .unscanned:
            return rom.crc32 == nil && rom.thumbnailLookupSystemID == nil
        case .multiplayer:
            return (rom.metadata?.players ?? 0) >= 2
        case .hasMetadata:
            let title = rom.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !title.isEmpty
        }
    }
    
    var activeColor: Color {
        switch self {
        case .noBoxArt:     return .orange
        case .neverPlayed:  return .purple
        case .notFavorite:  return .pink
        case .unscanned:    return .yellow
        case .multiplayer:  return .green
        case .hasMetadata:  return .cyan
        }
    }
}

// MARK: - Sort Options

/// Sort orders for the main game library list
enum GameSortOption: String, CaseIterable, Identifiable {
    case name       // A-Z alphabetical
    case lastPlayed // Most recently played first
    case system     // Grouped by system name, then alphabetical by game name
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        case .lastPlayed: return "Last Played"
        case .system: return "System"
        }
    }
    
    var iconName: String {
        switch self {
        case .name: return "textformat"
        case .lastPlayed: return "clock"
        case .system: return "cpu"
        }
    }
}


struct LibraryGridView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @StateObject private var dragState = GameDragState.shared
    @Binding var showCreateCategorySheet: Bool
    var filter: LibraryFilter
    @Binding var selectedROM: ROM?
    @Binding var searchText: String

    @Environment(\.openWindow) private var openWindow
    @State private var renamingROM: ROM? = nil
    @State private var renameText: String = ""
    @StateObject private var gameLauncher = GameLauncher.shared

    @State private var viewMode: ViewMode = .grid
    @AppStorage("gridColumns") private var columnCount: Int = 4
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject var boxArtService = BoxArtService.shared
    @State private var manualBoxArtSearchROM: ROM?
    
    // Smooth pinch-to-zoom state
    @State private var continuousZoom: Double = 0.5
    @State private var lastMagnification: Double = 1.0
    
    // Multi-select state
    @State private var selectedROMs: Set<UUID> = []
    @State private var lastSelectedIndex: Int? = nil
    
    // Drag and drop
    @State private var draggedROMs: [ROM] = []
    
    // Filter chips
    @State private var activeFilters: Set<String> = []
    @State private var sortOption: GameSortOption = .name

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
        case .system(let system):
            base = library.roms.filter { $0.systemID == system.id }
        case .category(let categoryID):
            base = categoryManager.gamesInCategory(categoryID: categoryID, fromROMs: library.roms)
        }

        // Filter out BIOS files unless "Show BIOS Files" is enabled
        var filtered = prefs.showBiosFiles ? base : base.filter { !$0.isHidden }

        // Apply filter chips
        if !activeFilters.isEmpty {
            filtered = filtered.filter { rom in
                for rawValue in activeFilters {
                    if let option = GameFilterOption(rawValue: rawValue) {
                        if !option.matches(rom) {
                            return false
                        }
                    }
                }
                return true
            }
        }

        // Apply search text filter
        if !searchText.isEmpty {
            let searchTerms = searchText.split(separator: " ")
            filtered = filtered.filter { rom in
                searchTerms.allSatisfy { term in
                    rom.displayName.localizedCaseInsensitiveContains(term)
                }
            }
        }

        // Apply sort
        let sorted = applySorting(to: filtered)
        return sorted
    }

    private func applySorting(to roms: [ROM]) -> [ROM] {
        switch sortOption {
        case .name:
            return roms.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .lastPlayed:
            return roms.sorted { a, b in
                switch (a.lastPlayed, b.lastPlayed) {
                case (nil, nil):
                    return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                case (_, nil):
                    return true  // played sorts before never-played
                case (nil, _):
                    return false // never-played sorts after
                case let (dateA?, dateB?):
                    return dateA > dateB  // most recent first
                }
            }
        case .system:
            return roms.sorted { a, b in
                let sysNameA = SystemDatabase.system(forID: a.systemID ?? "")?.name ?? "ZZZZ"
                let sysNameB = SystemDatabase.system(forID: b.systemID ?? "")?.name ?? "ZZZZ"
                let sysCompare = sysNameA.localizedCaseInsensitiveCompare(sysNameB)
                if sysCompare != .orderedSame {
                    return sysCompare == .orderedAscending
                }
                // Secondary sort by game name within same system
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
    }
    @State private var columns: [GridItem] = []

    var body: some View {
        VStack(spacing: 0) {
            searchField
            filterChips
            
            // Active filter summary bar
            if !activeFilters.isEmpty {
                activeFilterSummary
            }
            
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
                            .font(.caption)
                        Text(activeName)
                            .font(.caption)
                    }
                }
                .help("Select input device")

                // Language Selection
                Menu {
                    ForEach(EmulatorLanguage.allCases) { lang in
                        Button {
                            prefs.systemLanguage = lang
                        } label: {
                            HStack {
                                Text("\(lang.name) \(lang.flagEmoji)")
                                if prefs.systemLanguage == lang {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(prefs.systemLanguage.flagEmoji)
                        Text(prefs.systemLanguage.name)
                            .font(.caption)
                    }
                }
                .help("System language")

                if case .system(let system) = filter {
                    Menu {
                        ForEach(BoxType.allCases) { type in
                            Button {
                                prefs.setBoxType(type, for: system.id)
                            } label: {
                                HStack {
                                    Label(type.rawValue, systemImage: type.iconName)
                                    if prefs.boxType(for: system.id) == type {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: prefs.boxType(for: system.id).iconName)
                    }
                    .opacity(viewMode == .grid ? 1 : 0)
                    .help("Box art type")
                }

                // Zoom slider
                Slider(value: $continuousZoom, in: 0...1, step: 1.0/7.0)
                    .frame(width: 120)
                    .help("Zoom level")

                // Sort menu
                Menu {
                    ForEach(GameSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Label(option.displayName, systemImage: option.iconName)
                                if sortOption == option {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortOption.iconName)
                        Text(sortOption.displayName)
                            .font(.caption)
                    }
                }
                .help("Sort games")

                // View mode toggle
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 70)
                .help("View mode")

                Button {
                    Task {
                        await BoxArtService.shared.batchDownloadBoxArtLibretro(for: displayedROMs, library: library)
                    }
                } label: {
                    Label("Fetch missing art", systemImage: "arrow.down.circle")
                }
                .labelStyle(.iconOnly)
                .help("Download missing box art from Libretro CDN")

                // Settings button
                Button {
                    if let mainMenu = NSApp.mainMenu {
                        for item in mainMenu.items {
                            if let submenu = item.submenu {
                                for subItem in submenu.items {
                                    if subItem.title == "Settings…" || subItem.title == "Preferences…" {
                                        if let action = subItem.action {
                                            NSApp.sendAction(action, to: subItem.target, from: subItem)
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                    NSApp.windows.first { $0.identifier?.rawValue == "settings" }?.makeKeyAndOrderFront(nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings")
            }
        }
        .sheet(item: $manualBoxArtSearchROM) { rom in
            BoxArtPickerView(rom: rom)
        }
        .onAppear { 
            updateColumns()
            continuousZoom = 1.0 - Double(columnCount - 1) / 7.0
        }
    }

    private func updateColumns() {
        columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(displayedROMs.enumerated()), id: \.element.id) { index, rom in
                    let isSelected = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                    GameCardView(rom: rom, isSelected: isSelected, isMultiSelected: selectedROMs.contains(rom.id), zoomLevel: zoomLevel)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleTap(on: rom, at: index)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                launchGame(rom)
                            }
                        )
                        .contextMenu { contextMenu(for: rom) }
                        .onDrag {
                            let items = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                                ? selectedROMs.compactMap { id in displayedROMs.first(where: { $0.id == id }) }
                                : [rom]
                            draggedROMs = items
                            dragState.startDrag(gameIDs: items.map { $0.id })
                            let provider = NSItemProvider(object: NSString(string: items.map { $0.id.uuidString }.joined(separator: ",")))
                            return provider
                        }
                }
            }
            .padding()
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let scale = value / lastMagnification
                    let zoomDelta = (scale - 1.0) * 0.3
                    continuousZoom = max(0, min(1, continuousZoom + zoomDelta))
                    lastMagnification = value
                }
                .onEnded { _ in
                    let snapped = round(continuousZoom * 7.0) / 7.0
                    continuousZoom = snapped
                    columnCount = max(1, min(8, Int(round((1.0 - snapped) * 7.0) + 1)))
                    lastMagnification = 1.0
                }
        )
        .onDrop(of: [.url], isTargeted: nil) { items, location in
            return false
        }
    }
    
    private func handleTap(on rom: ROM, at index: Int) {
        let modifiers = NSEvent.modifierFlags
        
        if modifiers.contains(.command) {
            if selectedROMs.contains(rom.id) {
                selectedROMs.remove(rom.id)
                if selectedROMs.isEmpty {
                    selectedROM = nil
                }
            } else {
                selectedROMs.insert(rom.id)
                selectedROM = rom
            }
            lastSelectedIndex = index
        } else if modifiers.contains(.shift), let lastIndex = lastSelectedIndex {
            let range = min(lastIndex, index)...max(lastIndex, index)
            let rangeIDs = range.compactMap { i in
                i < displayedROMs.count ? displayedROMs[i].id : nil
            }
            selectedROMs.formUnion(rangeIDs)
            selectedROM = rom
        } else {
            selectedROMs.removeAll()
            selectedROM = rom
            lastSelectedIndex = index
        }
    }

    private var listView: some View {
        List(selection: $selectedROM) {
            ForEach(Array(displayedROMs.enumerated()), id: \.element.id) { index, rom in
                let isSelected = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                GameListRowView(rom: rom, isSelected: isSelected, zoomLevel: zoomLevel)
                    .tag(rom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleListTap(on: rom, at: index)
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            launchGame(rom)
                        }
                    )
                    .contextMenu { contextMenu(for: rom) }
                    .onDrag {
                        let items = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                            ? selectedROMs.compactMap { id in displayedROMs.first(where: { $0.id == id }) }
                            : [rom]
                        draggedROMs = items
                        dragState.startDrag(gameIDs: items.map { $0.id })
                        let provider = NSItemProvider(object: NSString(string: items.map { $0.id.uuidString }.joined(separator: ",")))
                        return provider
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let scale = value / lastMagnification
                    let zoomDelta = (scale - 1.0) * 0.8
                    continuousZoom = max(0, min(1, continuousZoom + zoomDelta))
                    lastMagnification = value
                }
                .onEnded { _ in
                    let snapped = round(continuousZoom * 7.0) / 7.0
                    continuousZoom = snapped
                    columnCount = max(1, min(8, Int(round((1.0 - snapped) * 7.0) + 1)))
                    lastMagnification = 1.0
                }
        )
    }
    
    private func handleListTap(on rom: ROM, at index: Int) {
        let modifiers = NSEvent.modifierFlags
        
        if modifiers.contains(.command) {
            if selectedROMs.contains(rom.id) {
                selectedROMs.remove(rom.id)
                if selectedROMs.isEmpty {
                    selectedROM = nil
                }
            } else {
                selectedROMs.insert(rom.id)
                selectedROM = rom
            }
            lastSelectedIndex = index
        } else if modifiers.contains(.shift), let lastIndex = lastSelectedIndex {
            let range = min(lastIndex, index)...max(lastIndex, index)
            let rangeIDs = range.compactMap { i in
                i < displayedROMs.count ? displayedROMs[i].id : nil
            }
            selectedROMs.formUnion(rangeIDs)
            selectedROM = rom
        } else {
            selectedROMs.removeAll()
            selectedROM = rom
            lastSelectedIndex = index
        }
    }

    private var zoomLevel: Double {
        1.0 - Double(columnCount - 1) / 7.0
    }

    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            ProgressView(value: library.scanProgress)
                .frame(width: 280)
            Text("Scanning your ROM library…")
                .foregroundColor(.secondary)
            Button(role: .cancel) {
                library.stopScan()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
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
            if !activeFilters.isEmpty && searchText.isEmpty {
                Text("No games match the active filters")
                    .font(.title3)
                    .foregroundColor(.secondary)
            } else if !searchText.isEmpty {
                Text("No results for \(searchText)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            } else {
                Text("No games found")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
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
        
        Menu {
            Button {
                showCreateCategorySheet = true
            } label: {
                Label("New Category...", systemImage: "plus.circle")
            }
            
            if !categoryManager.categories.isEmpty {
                Divider()
            }
            
            ForEach(categoryManager.categories) { category in
                let isInCategory = category.gameIDs.contains(rom.id)
                Button {
                    if isInCategory {
                        categoryManager.removeGamesFromCategory(gameIDs: [rom.id], categoryID: category.id)
                    } else {
                        categoryManager.addGamesToCategory(gameIDs: [rom.id], categoryID: category.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: category.iconName)
                            .foregroundColor(Color(hex: category.colorHex) ?? .blue)
                        Text(category.name)
                        Spacer()
                        if isInCategory {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            let categoriesForGame = categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
            if !categoriesForGame.isEmpty {
                Divider()
                Button(role: .destructive) {
                    for category in categoriesForGame {
                        categoryManager.removeGamesFromCategory(gameIDs: [rom.id], categoryID: category.id)
                    }
                } label: {
                    Label("Remove from All Categories", systemImage: "folder.badge.minus")
                }
            }
        } label: {
            Label("Categories", systemImage: "folder.badge.plus")
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

    // MARK: - Search & Filters

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
        .padding(.bottom, 4)
    }
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(GameFilterOption.allCases) { option in
                    FilterChipView(
                        option: option,
                        isActive: activeFilters.contains(option.rawValue),
                        action: { toggleFilter(option) }
                    )
                }
                
                if !activeFilters.isEmpty {
                    Button {
                        activeFilters.removeAll()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                            Text("Clear")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
    
    private var activeFilterSummary: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundColor(.accentColor)
                .font(.caption)
            
            let activeNames = activeFilters.compactMap { rawValue -> String? in
                GameFilterOption(rawValue: rawValue)?.label
            }
            
            Text("Filtering: " + activeNames.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(displayedROMs.count) game\(displayedROMs.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }
    
    private func toggleFilter(_ option: GameFilterOption) {
        if activeFilters.contains(option.rawValue) {
            activeFilters.remove(option.rawValue)
        } else {
            activeFilters.insert(option.rawValue)
        }
    }

    @MainActor
    private func launchGame(_ rom: ROM) {
        guard let sysID = rom.systemID,
              let system = SystemDatabase.system(forID: sysID) else { return }
        
        let sysPrefs = SystemPreferences.shared
        let coreID = rom.useCustomCore ? (rom.selectedCoreID ?? sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID) : (sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)
        
        guard let cid = coreID else { return }
        
        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID)
            return
        }

        gameLauncher.launchGame(
            rom: rom,
            coreID: cid,
            library: library
        )
    }
}

// MARK: - Filter Chip View

struct FilterChipView: View {
    let option: GameFilterOption
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 9, weight: .medium))
                Text(option.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? option.activeColor : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help(option.tooltip)
    }
}

// MARK: - Game Card

struct GameCardView: View {
    let rom: ROM
    let isSelected: Bool
    let isMultiSelected: Bool
    let zoomLevel: Double
    @State private var isHovered = false
    @State private var image: NSImage?
    @ObservedObject var prefs = SystemPreferences.shared
    @EnvironmentObject var categoryManager: CategoryManager

    private var boxType: BoxType {
        prefs.boxType(for: rom.systemID ?? "")
    }
    
    private var titleFontSize: CGFloat {
        10 + zoomLevel * 6
    }
    
    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                artworkView
                
                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            
            Text(rom.displayName)
                .font(.system(size: titleFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)
            
            if !categoryBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(categoryBadges) { category in
                            CategoryBadgeView(category: category)
                        }
                    }
                }
            }
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
                    .font(.system(size: titleFontSize * 0.8))
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
    let isSelected: Bool
    let zoomLevel: Double
    @State private var thumb: NSImage?
    @EnvironmentObject var categoryManager: CategoryManager
    
    private var titleFontSize: CGFloat {
        12 + zoomLevel * 8
    }
    
    private var subtitleFontSize: CGFloat {
        9 + zoomLevel * 5
    }
    
    private var thumbSize: CGFloat {
        36 + zoomLevel * 24
    }
    
    private var categoryBadges: [GameCategory] {
        categoryManager.categories.filter { $0.gameIDs.contains(rom.id) }
    }
    
    // MARK: - Formatted Playtime
    
    private var formattedPlaytime: String? {
        guard rom.totalPlaytimeSeconds > 0 else { return nil }
        let seconds = rom.totalPlaytimeSeconds
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    private var timesPlayedLabel: String? {
        guard rom.timesPlayed > 0 else { return nil }
        if rom.timesPlayed == 1 {
            return "1 play"
        } else {
            return "\(rom.timesPlayed) plays"
        }
    }
    
    private var metadataLine1: String? {
        var parts: [String] = []
        if let year = rom.metadata?.year, !year.isEmpty {
            parts.append(year)
        }
        if let dev = rom.metadata?.developer, !dev.isEmpty {
            parts.append(dev)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{2022} ")
    }
    
    private var metadataLine2: String? {
        var parts: [String] = []
        if let genre = rom.metadata?.genre, !genre.isEmpty {
            parts.append(genre)
        }
        if let players = rom.metadata?.players, players > 0 {
            parts.append(players == 1 ? "1 player" : "\(players) players")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{2022} ")
    }

    var body: some View {
        HStack(spacing: 12) {
            artThumb
            
            // Left side: game info
            VStack(alignment: .leading, spacing: 2) {
                Text(rom.displayName)
                    .font(.system(size: titleFontSize, weight: .medium))
                
                // System name
                if let sys = SystemDatabase.system(forID: rom.systemID ?? "") {
                    HStack(spacing: 4) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
                        Text(sys.name)
                            .font(.system(size: subtitleFontSize))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Category badges
                if !categoryBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(categoryBadges) { category in
                                CategoryBadgeView(category: category)
                            }
                        }
                    }
                }
                
                // Metadata: Year/Developer
                if let line1 = metadataLine1 {
                    Text(line1)
                        .font(.system(size: subtitleFontSize - 1))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                // Metadata: Genre/Players
                if let line2 = metadataLine2 {
                    Text(line2)
                        .font(.system(size: subtitleFontSize - 1))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Right side: stats column
            VStack(alignment: .trailing, spacing: 2) {
                // Playtime
                if let playtime = formattedPlaytime {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: subtitleFontSize - 0.5))
                        Text(playtime)
                            .font(.system(size: subtitleFontSize))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
                
                // Times played
                if let timesPlayed = timesPlayedLabel {
                    Text(timesPlayed)
                        .font(.system(size: subtitleFontSize))
                        .foregroundColor(.secondary)
                }
                
                // Last played
                if let played = rom.lastPlayed {
                    Text(played, style: .relative)
                        .font(.system(size: subtitleFontSize - 0.5))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                // Favorite indicator
                if rom.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                        .font(.system(size: subtitleFontSize))
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
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
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
// MARK: - Category Badge

struct CategoryBadgeView: View {
    let category: GameCategory
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.iconName)
                .font(.system(size: 7))
            Text(category.name)
                .font(.system(size: 8))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color(hex: category.colorHex) ?? .blue)
        .cornerRadius(4)
    }
}

// MARK: - Add to Category Sheet

struct AddToCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var categoryManager: CategoryManager
    let gameIDs: [UUID]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(categoryManager.categories) { category in
                    let alreadyContains = !Set(category.gameIDs).intersection(gameIDs).isEmpty
                    Button {
                        categoryManager.addGamesToCategory(gameIDs: gameIDs, categoryID: category.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundColor(Color(hex: category.colorHex) ?? .blue)
                            Text(category.name)
                            Spacer()
                            if alreadyContains {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add to Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 300, height: 300)
    }
}

// MARK: - Image Cache

actor ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSURL, NSImage>()
    
    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        let image = NSImage(contentsOf: url)
        
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

import SwiftUI
import AppKit

// GridCardBoxArtView and GridCardZoomableFullScreenView are defined in ZoomableBoxArtView.swift
// GameCardView and CategoryBadgesRow are defined in GameCardView.swift

// MARK: - Full Screen Zoomable Box Art View (alias for backwards compat)

/// A full-screen sheet that shows a zoomable image with a close button.
struct GridCardZoomableFullScreenView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(1.0, lastScale * value), 5.0)
                        }
                        .onEnded { _ in
                            if scale < 1.1 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastScale = 1.0
                                    lastOffset = .zero
                                }
                            } else {
                                lastScale = scale
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastScale = 1.0
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(showControls ? 1 : 0)
                }
                Spacer()
                Text("Pinch to zoom")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
                    .opacity(showControls ? 1 : 0)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
    }
}

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
        // Unified accent color — lets box art, not filter chips, provide the palette
        return .accentColor
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
    @State private var columnCount: Int = {
        let zoom = AppSettings.getDouble("gridZoomLevel", defaultValue: 0.0)
        let effectiveZoom = zoom != 0.0 ? zoom : 0.5
        return max(1, min(8, Int(round((1.0 - effectiveZoom) * 7.0) + 1)))
    }()
    @ObservedObject var prefs = SystemPreferences.shared
    @ObservedObject var boxArtService = BoxArtService.shared
    @State private var manualBoxArtSearchROM: ROM?
    
    
    // Delete/hide game states
    @State private var gameToDelete: ROM?
    @State private var showDeleteConfirmation = false
    
    // Smooth pinch-to-zoom state
    @State private var continuousZoom: Double = {
        // Read saved zoom level at init time
        let saved = AppSettings.getDouble("gridZoomLevel", defaultValue: 0.0)
        return saved != 0.0 ? saved : 0.5
    }()
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

    /// Filtered and sorted ROMs. The sorting step is deferred to a lazy sequence
    /// so that SwiftUI's LazyVGrid only computes the visible range on each pass.
    private var displayedROMs: [ROM] {
        let base: [ROM]
        switch filter {
        case .all:
            base = library.roms.filter { !$0.isHidden }
        case .favorites:
            base = library.roms.filter { $0.isFavorite && !$0.isHidden }
        case .recent:
            base = library.roms.filter { $0.lastPlayed != nil && !$0.isHidden }
        case .system(let system):
            let systemIDs = SystemDatabase.allInternalIDs(forDisplayID: system.id)
            base = library.roms.filter { systemIDs.contains($0.systemID ?? "") && !$0.isHidden }
        case .category(let categoryID):
            base = categoryManager.gamesInCategory(categoryID: categoryID, fromROMs: library.roms).filter { !$0.isHidden }
        case .hidden:
            base = library.roms.filter { $0.isHidden }
        }

        var filtered = base
        if !activeFilters.isEmpty {
            filtered = filtered.filter { rom in
                for rawValue in activeFilters {
                    if let option = GameFilterOption(rawValue: rawValue) {
                        if !option.matches(rom) { return false }
                    }
                }
                return true
            }
        }

        if !searchText.isEmpty {
            let searchTerms = searchText.split(separator: " ")
            filtered = filtered.filter { rom in
                searchTerms.allSatisfy { term in
                    rom.displayName.localizedCaseInsensitiveContains(term)
                }
            }
        }

        return applySorting(to: filtered)
    }

    private func applySorting(to roms: [ROM]) -> [ROM] {
        guard !roms.isEmpty else { return [] }
        
        switch sortOption {
        case .name:
            // Schwartzian transform: pre-compute display names once to avoid N log N regex stripping calls
            return roms
                .map { (rom: $0, key: $0.displayName) }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { $0.rom }
                
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
            // Schwartzian transform: pre-compute system names and display names
            struct SortEntry {
                let rom: ROM
                let systemName: String
                let displayName: String
            }
            
            return roms
                .map { rom in
                    let sysName = SystemDatabase.displaySystem(forInternalID: rom.systemID ?? "")?.name ?? "ZZZZ"
                    return SortEntry(rom: rom, systemName: sysName, displayName: rom.displayName)
                }
                .sorted { a, b in
                    let sysCompare = a.systemName.localizedCaseInsensitiveCompare(b.systemName)
                    if sysCompare != .orderedSame {
                        return sysCompare == .orderedAscending
                    }
                    return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                }
                .map { $0.rom }
        }
    }
    @State private var columns: [GridItem] = []

    // MARK: - Focused field for Cmd+F
    enum FocusableField: Hashable { case search }
    @FocusState private var focusedField: FocusableField?
    
    var body: some View {
        VStack(spacing: 0) {
            searchField
                .focused($focusedField, equals: .search)
            
            // Visible zoom slider
            if viewMode == .grid {
                zoomSlider
            }
            
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
                    GeometryReader { geometry in
                        gridView
                            .onChange(of: geometry.size.width) { _, newWidth in
                                gridWidth = newWidth
                                updateColumns()
                            }
                    }
                    .frame(minHeight: 0)
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
        .confirmationDialog(
            "Delete Game: \(gameToDelete?.displayName ?? "")",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move ROM File to Trash & Remove from Library", role: .destructive) {
                if let rom = gameToDelete {
                    deleteGameAndROM(rom)
                }
                gameToDelete = nil
            }
            Button("Hide from Library Only", role: .destructive) {
                if let rom = gameToDelete {
                    hideGame(rom)
                }
                gameToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                gameToDelete = nil
            }
        } message: {
            if let rom = gameToDelete {
                Text("""
                This will remove \"\(rom.displayName)\" from your library.

                • "Move ROM File to Trash & Remove from Library" — The game file (\(rom.path.lastPathComponent)) will be moved to your system Trash, and the game will be removed from your library.

                • "Hide from Library Only" — The game will be hidden from your library view, but the ROM file will remain on disk. You can unhide it later from the Hidden Games section.

                You can restore the ROM file from Trash if you change your mind.
                """)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                // ─── Group 1: Input (Controller + Language) ───
                Menu {
                    Section("Input Device") {
                        Button(action: { controllerService.activePlayerIndex = 0 }) {
                            Label("Keyboard", systemImage: "keyboard")
                                .symbolVariant(controllerService.activePlayerIndex == 0 ? .fill : .none)
                        }
                        if !controllerService.connectedControllers.isEmpty {
                            ForEach(controllerService.connectedControllers) { controller in
                                Button(action: { controllerService.activePlayerIndex = controller.playerIndex }) {
                                    Label(controller.name, systemImage: "gamecontroller")
                                        .symbolVariant(controllerService.activePlayerIndex == controller.playerIndex ? .fill : .none)
                                }
                            }
                        } else {
                            Text("No Controllers")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("Language") {
                        ForEach(EmulatorLanguage.allCases) { lang in
                            Button {
                                prefs.systemLanguage = lang
                            } label: {
                                HStack {
                                    Text("\(lang.flagEmoji) \(lang.name)")
                                    if prefs.systemLanguage == lang {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: controllerService.activePlayerIndex == 0 ? "keyboard" : "gamecontroller")
                            .font(.caption)
                        Text(prefs.systemLanguage.flagEmoji)
                            .font(.caption)
                    }
                }
                .help("Input device and language")

                // ─── Group 2: View (Sort + Zoom + View Mode) ───
                Menu {
                    Section("Sort By") {
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
                    }

                    Section("Zoom Level") {
                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { continuousZoom },
                                set: { newValue in
                                    continuousZoom = newValue
                                    applyZoomToColumnCount(animate: false)
                                }
                            ), in: 0...1)
                                .padding(.horizontal, 2)
                            Image(systemName: "plus.magnifyingglass")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("View") {
                        Button {
                            viewMode = .grid
                        } label: {
                            Label("Grid View", systemImage: "square.grid.2x2")
                            if viewMode == .grid { Spacer(); Image(systemName: "checkmark") }
                        }
                        Button {
                            viewMode = .list
                        } label: {
                            Label("List View", systemImage: "list.bullet")
                            if viewMode == .list { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortOption.iconName)
                            .font(.caption)
                        Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                            .font(.caption)
                    }
                }
                .help("View options: sort, zoom, layout")

                // ─── Group 3: Art (Box type + Fetch art, system views only) ───
                if case .system(let system) = filter, viewMode == .grid {
                    Menu {
                        Section("Box Art Style") {
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
                        }

                        Button {
                            Task {
                                await BoxArtService.shared.batchDownloadBoxArtLibretro(for: displayedROMs, library: library)
                                await LaunchBoxGamesDBService.shared.batchDownloadBoxArt(for: displayedROMs, library: library)
                            }
                        } label: {
                            Label("Download Missing Box Art", systemImage: "arrow.down.circle")
                                .help("Cleans broken boxart and downloads missing art for all games")
                        }
                    } label: {
                        Image(systemName: "photo.stack")
                    }
                    .help("Box art options and downloads")
                }

                // ─── Group 4: Settings ───
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
            // Recompute columns from saved zoom level
            applyZoomToColumnCount(animate: false)
            updateColumns()
            
            // When a new system/filter appears, preload its visible ROMs immediately.
            // The ContentView handles global preloading (current filter → smallest systems),
            // but this ensures newly visible filters get preloaded on-demand too.
            preloadCurrentViewIfNotCached()
        }
        .onDisappear {
            // Save zoom level persistently
            AppSettings.setDouble("gridZoomLevel", value: continuousZoom)
        }
        // Refresh grid when box art is updated from elsewhere (e.g., game info page)
        // We do NOT clear the entire ImageCache or trigger full-grid reloads.
        // Each GameCardView's .task(id: rom.boxArtPath) will automatically reload
        // when its specific boxArtPath changes.
        // MARK: - Keyboard Shortcuts
        // Cmd+F focuses search field
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in }
        .keyboardShortcut(KeyEquivalent("f"), modifiers: .command)
        // Return launches selected game
        .onSubmit {
            if let rom = selectedROM {
                launchGame(rom)
            }
        }
        // Note: Delete key handling via onKeyPress requires macOS 14+
        // For macOS 13, users can use context menu or confirm delete action
    }

    @State private var gridWidth: CGFloat = 800

    private func updateColumns() {
        // Card width must be fixed for all columns to ensure uniform card sizes.
        // Using the same value for min and max prevents columns from stretching independently.
        let cardWidth: CGFloat = 80 + (continuousZoom * 200)
        // Spacing shrinks as cards get bigger
        let spacing: CGFloat = max(6, 16 - (continuousZoom * 8))
        
        // Calculate how many columns fit in the current grid width
        let availableWidth = gridWidth - (gridPadding.leading + gridPadding.trailing)
        let computedColumns = max(1, min(8, Int((availableWidth + spacing) / (cardWidth + spacing))))
        columnCount = computedColumns
        
        columns = Array(
            repeating: GridItem(.flexible(minimum: cardWidth, maximum: cardWidth), spacing: spacing),
            count: columnCount
        )
    }

    private var gridView: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(Array(displayedROMs.enumerated()), id: \.element.id) { index, rom in
                    let isSelected = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                    GameCardView(rom: rom, isSelected: isSelected, isMultiSelected: selectedROMs.contains(rom.id), zoomLevel: continuousZoom)
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
            .padding(gridPadding)
            .animation(.none, value: continuousZoom) // No animation during live pinch for responsiveness
        }
        .clipped() // Prevent content from drawing outside bounds (e.g., behind sidebar)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // Continuous zoom: adjust cards smoothly during pinch
                    let scale = value / lastMagnification
                    let zoomDelta = (scale - 1.0) * 0.15
                    let newZoom = max(0, min(1, continuousZoom + zoomDelta))
                    // Only update columns when zoom crosses a step boundary
                    let newColumnCount = max(1, min(8, Int(round((1.0 - newZoom) * 7.0) + 1)))
                    if newColumnCount != columnCount {
                        columnCount = newColumnCount
                        updateColumns()
                    }
                    continuousZoom = newZoom
                    lastMagnification = value
                }
                .onEnded { _ in
                    // Smooth snap to nearest predefined step when pinch ends
                    let snapped = round(continuousZoom * 7.0) / 7.0
                    withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                        continuousZoom = snapped
                        columnCount = max(1, min(8, Int(round((1.0 - snapped) * 7.0) + 1)))
                        updateColumns()
                    }
                    lastMagnification = 1.0
                }
        )
        .onDrop(of: [.url], isTargeted: nil) { items, location in
            return false
        }
    }
    
    // MARK: - Zoom Calculations
    
    /// The scale factor applied to the entire grid content
    private var gridScale: CGFloat {
        // Base scale starts at 0.7 and goes up to 1.3
        0.7 + (continuousZoom * 0.6)
    }
    
    /// Dynamic spacing between grid items based on zoom
    private var gridSpacing: CGFloat {
        // Less spacing when zoomed in (cards are bigger)
        8 + ((1.0 - continuousZoom) * 12)
    }
    
    /// Horizontal padding adjusts with zoom to prevent edge clipping
    private var horizontalPadding: CGFloat {
        8 + ((1.0 - continuousZoom) * 12)
    }
    
    /// Combined grid padding
    private var gridPadding: EdgeInsets {
        EdgeInsets(top: 12, leading: horizontalPadding, bottom: 12, trailing: horizontalPadding)
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
        continuousZoom
    }
    
    /// Applies the current continuousZoom value to columnCount and updates the grid.
    /// Shared between slider, pinch gesture, and onAppear restoration.
    private func applyZoomToColumnCount(animate: Bool = false) {
        let newColumnCount = max(1, min(8, Int(round((1.0 - continuousZoom) * 7.0) + 1)))
        if newColumnCount != columnCount {
            columnCount = newColumnCount
            if animate {
                withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                    updateColumns()
                }
            } else {
                updateColumns()
            }
        }
    }

    @State private var scanningMessageIndex = 0
    
    private var scanningMessages: [String] {
        [
            "Scanning your ROM library…",
            "Identifying classic games…",
            "Building your game shelf…",
            "Fetching box art references…",
            "Organizing by platform…",
            "Almost ready to play…"
        ]
    }
    
    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            ZStack {
                // Animated pulse ring
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + library.scanProgress * 0.5)
                    .opacity(1.0 - library.scanProgress * 0.8)
                
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + library.scanProgress * 0.3)
                    .opacity(0.5)
                
                // Controller icon
                Image(systemName: "arcade.stick")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .modifier(ScanningPulseAnimation())
            
            ProgressView(value: library.scanProgress)
                .frame(width: 280)
            
            Group {
                Text(scanningMessages[scanningMessageIndex])
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
            }
            .font(.body)
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if library.isScanning {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scanningMessageIndex = (scanningMessageIndex + 1) % scanningMessages.count
                    }
                }
            }
            
            // Fun stats during scan
            if library.roms.count > 0 {
                Text("\(library.roms.count) game\(library.roms.count == 1 ? "" : "s") found so far")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
            }
            
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

    @State private var boxArtMessageIndex = 0
    
    private var boxArtMessages: [String] {
        [
            "Fetching box art…",
            "Dressing up your games…",
            "Making your library pretty…",
            "Finding cover art gems…",
            "Wrapping ROMs in beautiful cases…"
        ]
    }
    
    private var downloadingArtOverlay: some View {
        HStack(spacing: 12) {
            // Animated book icon
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.0 + boxArtService.downloadProgress * 0.2)
                    .opacity(1.0 - boxArtService.downloadProgress * 0.5)
                
                Image(systemName: "book.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .modifier(BoxArtPulseAnimation())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(boxArtMessages[boxArtMessageIndex])
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                
                Text("\(boxArtService.downloadedCount) / \(boxArtService.downloadQueueCount) covers downloaded")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            if boxArtService.isDownloadingBatch {
                withAnimation(.easeInOut(duration: 0.3)) {
                    boxArtMessageIndex = (boxArtMessageIndex + 1) % boxArtMessages.count
                }
            }
        }
        .onChange(of: boxArtService.isDownloadingBatch) { _, isDownloading in
            if isDownloading {
                boxArtMessageIndex = 0
            }
        }
    }

    @State private var emptyStateAppeared = false
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 56))
                .foregroundColor(.secondary)
                .scaleEffect(emptyStateAppeared ? 1 : 0.8)
                .offset(y: emptyStateAppeared ? 0 : 10)
                .onAppear {
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        emptyStateAppeared = true
                    } else {
                        withAnimation(.interpolatingSpring(stiffness: 170, damping: 20).delay(0.05)) {
                            emptyStateAppeared = true
                        }
                    }
                }
                .modifier(EmptyStateFloatAnimation())
            Text(emptyStateTitle)
                .font(.title3)
                .foregroundColor(.secondary)
                .opacity(emptyStateAppeared ? 1 : 0)
                .offset(y: emptyStateAppeared ? 0 : 8)
            Text(emptyStateDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .opacity(emptyStateAppeared ? 1 : 0)
                .offset(y: emptyStateAppeared ? 0 : 8)
            if activeFilters.isEmpty && searchText.isEmpty {
                Button {
                    pickFolder()
                } label: {
                    Label("Add ROM Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .opacity(emptyStateAppeared ? 1 : 0)
                .offset(y: emptyStateAppeared ? 0 : 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                emptyStateAppeared = true
            }
        }
    }
    
    private var emptyStateIcon: String {
        if !activeFilters.isEmpty && searchText.isEmpty {
            return "line.3.horizontal.decrease.circle"
        } else if !searchText.isEmpty {
            return "magnifyingglass"
        } else {
            return "tray"
        }
    }
    
    private var emptyStateTitle: String {
        if !activeFilters.isEmpty && searchText.isEmpty {
            return "No games match your filters"
        } else if !searchText.isEmpty {
            return "Nothing matching \"\(searchText)\""
        } else {
            return "Your gaming shelf is empty"
        }
    }
    
    private var emptyStateDescription: String {
        if !activeFilters.isEmpty && searchText.isEmpty {
            return "Try loosening your filters to rediscover some games."
        } else if !searchText.isEmpty {
            return "That title might be hiding under a different name. Try a different search."
        } else {
            return "Add a folder of ROMs and TruchieEmu will organize your collection by system, complete with box art."
        }
    }
    
    /// Opens a folder picker to add ROM folders to the library.
    /// This empty-state CTA gives users a direct path to value when no games exist.
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more folders containing your ROM files"
        panel.prompt = "Add Folders"
        if panel.runModal() == .OK {
            for url in panel.urls {
                library.addLibraryFolder(url: url)
            }
        }
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
        
        Divider()
        if rom.isHidden {
            Button("Unhide Game") {
                unhideGame(rom)
            }
        } else {
            Button("Hide Game") {
                hideGame(rom)
            }
            Button(role: .destructive) {
                gameToDelete = rom
                showDeleteConfirmation = true
            } label: {
                Label("Delete Game...", systemImage: "trash")
            }
        }
    }

    // MARK: - Delete/Hide Game Actions

    private func hideGame(_ rom: ROM) {
        var updated = rom
        updated.isHidden = true
        library.updateROM(updated)
    }

    private func unhideGame(_ rom: ROM) {
        var updated = rom
        updated.isHidden = false
        library.updateROM(updated)
    }

    private func deleteGameAndROM(_ rom: ROM) {
        // Move the ROM file to trash using FileManager
        do {
            var trashURL: NSURL?
            try FileManager.default.trashItem(at: rom.path, resultingItemURL: &trashURL)
            LoggerService.info(category: "LibraryGridView", "ROM file moved to trash: \(rom.path.lastPathComponent)")
        } catch {
            LoggerService.warning(category: "LibraryGridView", "Failed to move ROM to trash: \(error.localizedDescription). Removing from library anyway.")
        }
        
        // Remove the ROM from the library
        removeROMFromLibrary(rom)
    }

    private func removeROMFromLibrary(_ rom: ROM) {
        library.roms.removeAll { $0.id == rom.id }
        LibraryMetadataStore.shared.deleteMetadata(for: rom)
        let repo = ROMRepository(context: SwiftDataContainer.shared.mainContext)
        repo.deleteROMsByPath([rom.path.path])
        library.updateCounts()
        library.saveROMsToDatabase()

        // If this ROM was selected, deselect it
        if selectedROM?.id == rom.id {
            selectedROM = nil
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
    
    /// Visible zoom slider for the grid view
    /// Uses onEditingChanged to avoid column recalculation on every tiny value change
    /// during scroll (which causes scroll lock/jank).
    private var zoomSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 16)
            
            Slider(value: $continuousZoom, in: 0...1, step: 1.0/7.0,
                   onEditingChanged: { isEditing in
                       if !isEditing {
                           // Only recalculate columns when user releases the slider
                           withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                               applyZoomToColumnCount(animate: true)
                           }
                       }
                   })
            
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 16)
            
            Text("\(Int(continuousZoom * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 30)
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

    /// Preload box art for the currently displayed ROMs in the grid.
    /// OPT-IN: Only preloads when explicitly triggered (e.g., from settings).
    /// The grid view relies on lazy .task(id: rom.boxArtPath) for on-demand loading.
    private func preloadCurrentViewIfNotCached() {
        // Preloading is now opt-in, not automatic.
        // Images load on-demand as cards appear in the LazyVGrid.
        // To manually preload: BoxArtPreloaderService.shared.preloadBoxArt(for: displayedROMs)
    }

    @MainActor
    private func launchGame(_ rom: ROM) {
        guard let sysID = rom.systemID,
              let system = SystemDatabase.system(forID: sysID) else { return }
        
        let sysPrefs = SystemPreferences.shared
        let coreID = rom.useCustomCore ? (rom.selectedCoreID ?? sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID) : (sysPrefs.preferredCoreID(for: sysID) ?? system.defaultCoreID)
        
        guard let cid = coreID else { return }
        
        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID, romID: rom.id, slotToLoad: nil)
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
    
    @Namespace private var chipAnimation
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 10, weight: .medium))
                    .scaleEffect(isActive ? 1.1 : 1)
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(
                Capsule()
                    .fill(isActive ? option.activeColor : Color.secondary.opacity(0.12))
                    .scaleEffect(isHovered ? 1.05 : 1)
                    .shadow(color: isActive ? option.activeColor.opacity(0.3) : .clear, radius: isHovered ? 4 : 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .help(option.tooltip)
        .accessibilityLabel(option.label)
        .accessibilityHint(option.tooltip)
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.2), value: isActive)
    }
    
    @State private var isHovered = false
}

// MARK: - List Row

struct GameListRowView: View {
    let rom: ROM
    let isSelected: Bool
    let zoomLevel: Double
    @State private var thumb: NSImage?
    @EnvironmentObject var library: ROMLibrary
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
            // Lazy-resolve local boxart on-demand if not already set
            if let resolvedPath = BoxArtService.shared.resolveLocalBoxArtIfNeeded(for: rom, library: library) {
                self.thumb = await ImageCache.shared.thumbnail(for: resolvedPath)
            } else if let artPath = rom.boxArtPath {
                self.thumb = await ImageCache.shared.thumbnail(for: artPath)
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
                .font(.system(size: 9, weight: .medium))
            Text(category.name)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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

// MARK: - Box Art Pulse Animation

/// A subtle pulse animation for the box art download icon
struct BoxArtPulseAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.15 : 1)
            .animation(
                Animation.easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Scanning Pulse Animation

/// A subtle pulse animation for the scanning overlay icon
struct ScanningPulseAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.08 : 1)
            .animation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Empty State Float Animation

/// A subtle floating animation for empty state icons to make the view feel alive
struct EmptyStateFloatAnimation: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isAnimating ? -4 : 0)
            .animation(
                Animation.easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                    .delay(0.5),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}


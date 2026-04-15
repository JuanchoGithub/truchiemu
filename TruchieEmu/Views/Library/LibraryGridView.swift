import SwiftUI
import AppKit

// MARK: - Library Grid View

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
    @State private var sortByLastPlayed: Bool = false

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
            var systemRoms = library.roms.filter { systemIDs.contains($0.systemID ?? "") && !$0.isHidden }
            
            // For MAME, show only runnable/playable games
            if system.id == "mame" {
                // First filter: hide BIOS/device/mechanical entries
                systemRoms = systemRoms.filter { rom in
                    rom.mameRomType == "game" || rom.mameRomType == nil
                }
                // Second filter: if we have XML-based runnable data, further filter to only runnable games
                let runnableSet = MAMEDependencyService.shared.rachableShortNamesForCurrentCores
                if !runnableSet.isEmpty {
                    systemRoms = systemRoms.filter { rom in
                        runnableSet.contains(rom.path.lastPathComponent.replacingOccurrences(of: ".zip", with: "").lowercased())
                    }
                }
            }
            
            base = systemRoms
        case .category(let categoryID):
            base = categoryManager.gamesInCategory(categoryID: categoryID, fromROMs: library.roms).filter { !$0.isHidden }
        case .hidden:
            base = library.roms.filter { $0.isHidden }
        case .mameNonGames:
            // Show MAME files that are not games (BIOS, device, mechanical, unknown) with grayish styling
            base = library.roms.filter { rom in
                rom.systemID == "mame" && rom.mameRomType != "game"
            }
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

    private func applySorting(to roms:[ROM]) -> [ROM] {
        guard !roms.isEmpty else { return[] }
        
        if sortByLastPlayed {
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
        } else {
            // Schwartzian transform: pre-compute display names once to avoid N log N regex stripping calls
            return roms
                .map { (rom: $0, key: $0.displayName) }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { $0.rom }
        }
    }
    @State private var columns: [GridItem] = []
    @State private var lastSelectedFilterID: String? = nil

    // MARK: - Focused field for Cmd+F
    enum FocusableField: Hashable { case search }
    @FocusState private var focusedField: FocusableField?
    
    var body: some View {
        VStack(spacing: 0) {
            searchField
                .focused($focusedField, equals: .search)
            
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
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        gridWidth = geometry.size.width
                                        updateColumns()
                                    }
                                    .onChange(of: geometry.size.width) { _, newWidth in
                                        gridWidth = newWidth
                                        updateColumns()
                                    }
                            }
                        )
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
                // ─── Group 0: Library Actions ───
                Button {
                    pickFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add ROM folder")

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

                // ─── Group 2: View Mode (Segmented Picker) ───
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .help("Switch between grid and list view")

                // ─── Group 4: Box Art (Merged menu) ───
                Menu {
                    Section("Box Art Style") {
                        ForEach(BoxType.allCases) { type in
                            Button {
                                if case .system(let system) = filter {
                                    prefs.setBoxType(type, for: system.id)
                                }
                            } label: {
                                HStack {
                                    Label(type.rawValue, systemImage: type.iconName)
                                    if case .system(let system) = filter, prefs.boxType(for: system.id) == type {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .disabled(!isSystemView)
                        }
                    }
                    
                    Divider()
                    
                    Section("Download") {
                        Button {
                            Task {
                                let targetROMs = selectedROMs.isEmpty
                                    ? displayedROMs
                                    : displayedROMs.filter { selectedROMs.contains($0.id) || selectedROM?.id == $0.id }
                                guard !targetROMs.isEmpty else { return }
                                await BoxArtService.shared.batchDownloadBoxArtLibretro(for: targetROMs, library: library)
                                await LaunchBoxGamesDBService.shared.batchDownloadBoxArt(for: targetROMs, library: library)
                            }
                        } label: {
                            Label(
                                selectedROMs.isEmpty ? "Download Missing Box Art" : "Download Box Art for Selected (\(selectedROMs.count))",
                                systemImage: "arrow.down.circle"
                            )
                        }
                        
                        Button {
                            Task {
                                let romsNeedingArt = BoxArtService.shared.romsNeedingBoxArt(in: displayedROMs)
                                guard !romsNeedingArt.isEmpty else { return }
                                await BoxArtService.shared.batchDownloadBoxArtLibretro(for: romsNeedingArt, library: library)
                            }
                        } label: {
                            Label("Download Missing Box Art Only", systemImage: "photo.badge.plus")
                        }
                        
                        Button {
                            Task {
                                await BoxArtService.shared.batchDownloadBoxArtLibretro(for: displayedROMs, library: library)
                                await LaunchBoxGamesDBService.shared.batchDownloadBoxArt(for: displayedROMs, library: library)
                            }
                        } label: {
                            Label("Download All Box Art", systemImage: "arrow.down.circle.fill")
                        }
                    }
                } label: {
                    Image(systemName: "photo.stack")
                }
                .help("Box art options and downloads")

                // ─── Group 5: Settings ───
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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Zoom slider in the toolbar (always visible)
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 14)
                    
                    Slider(value: $continuousZoom, in: 0...1, step: 1.0/7.0,
                           onEditingChanged: { isEditing in
                               if viewMode == .grid, !isEditing {
                                   // On release, snap to nearest step
                                   withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                                       applyZoomToColumnCount(animate: true)
                                   }
                               }
                           })
                           .onChange(of: continuousZoom) { _, newZoom in
                               // Update columns in real-time during slider drag for smooth reflow
                               if viewMode == .grid {
                                   let newColumnCount = max(1, min(8, Int(round((1.0 - newZoom) * 7.0) + 1)))
                                   if newColumnCount != columnCount {
                                       columnCount = newColumnCount
                                       updateColumns()
                                   }
                               }
                           }
                        .frame(width: 100)
                    
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 14)
                    
                    Text("\(Int(continuousZoom * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .sheet(item: $manualBoxArtSearchROM) { rom in
            BoxArtPickerView(rom: rom)
        }
        .onAppear { 
            // Recompute columns from saved zoom level
            applyZoomToColumnCount(animate: false)
            sortByLastPlayed = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
            
            // When a new system/filter appears, preload its visible ROMs immediately.
            // The ContentView handles global preloading (current filter → smallest systems),
            // but this ensures newly visible filters get preloaded on-demand too.
            preloadCurrentViewIfNotCached()
            
            // Contextually resolve local boxarts for the current view
            handleFilterChange(filter)
        }
        .onChange(of: filter) { _, newFilter in
            handleFilterChange(newFilter)
        }
        .onDisappear {
            // Save zoom level persistently
            AppSettings.setDouble("gridZoomLevel", value: continuousZoom)
        }
        // Refresh grid when box art is updated from elsewhere (e.g., game info page)
        // We do NOT clear the entire ImageCache or trigger full-grid reloads.
        // Each GameCardView's .task(id: rom.id) will automatically reload
        // when its specific hasBoxArt changes.
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

    /// Whether the current filter is a system view (used to enable/disable box art style).
    private var isSystemView: Bool {
        if case .system = filter { return true }
        return false
    }

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
                    
                    let draggedItemsForCard: [ROM] = {
                        if isSelected {
                            var dragIDs = selectedROMs
                            if let singleSelection = selectedROM {
                                dragIDs.insert(singleSelection.id)
                            }
                            return displayedROMs.filter { dragIDs.contains($0.id) }
                        } else {
                            return [rom]
                        }
                    }()

                    GameCardView(
                        rom: rom, 
                        isSelected: isSelected, 
                        isMultiSelected: selectedROMs.contains(rom.id), 
                        zoomLevel: continuousZoom,
                        draggedROMs: draggedItemsForCard,
                        onTap: { handleTap(on: rom, at: index) },
                        contextMenu: { contextMenu(for: rom) },
                        onDrag: {
                            draggedROMs = draggedItemsForCard
                            dragState.startDrag(gameIDs: draggedItemsForCard.map { $0.id })
                            let provider = NSItemProvider(object: NSString(string: draggedItemsForCard.map { $0.id.uuidString }.joined(separator: ",")))
                            return provider
                        }
                    )                    
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            launchGame(rom)
                        }
                    )
                }
            }
            .padding(gridPadding)
            .animation(.none, value: continuousZoom) // No animation during live zoom for responsiveness
        }
        .clipped() // Prevent content from drawing outside bounds (e.g., behind sidebar)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // Continuous zoom: adjust cards smoothly during pinch
                    let scale = value / lastMagnification
                    let zoomDelta = (scale - 1.0) * 0.15
                    let newZoom = max(0, min(1, continuousZoom + zoomDelta))
                    continuousZoom = newZoom
                    // Update columns in real-time for smooth reflow
                    let newColumnCount = max(1, min(8, Int(round((1.0 - newZoom) * 7.0) + 1)))
                    if newColumnCount != columnCount {
                        columnCount = newColumnCount
                        updateColumns()
                    }
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
        .onDrop(of:[.url], isTargeted: nil) { items, location in
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
                        let items: [ROM]
                        if isSelected {
                            var dragIDs = selectedROMs
                            if let singleSelection = selectedROM {
                                dragIDs.insert(singleSelection.id)
                            }
                            items = displayedROMs.filter { dragIDs.contains($0.id) }
                        } else {
                            items = [rom]
                        }
                        
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
    
    private var scanningMessages: [String] {[
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
                            colors:[Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)],
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
    
    private var boxArtMessages: [String] {[
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
                            colors:[Color(red: 0.1, green: 0.6, blue: 0.35), Color(red: 0.15, green: 0.65, blue: 0.55)],
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

    private func contextMenu(for rom: ROM) -> AnyView {
        let targetIDs = Array(selectedROMs.union([rom.id]))
        let targetIDsSet = Set(targetIDs)
        return AnyView(
            Group {
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
                                categoryManager.removeGamesFromCategory(gameIDs: targetIDs, categoryID: category.id)
                            } else {
                                categoryManager.addGamesToCategory(gameIDs: targetIDs, categoryID: category.id)
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

                    let categoriesForTargetGames = categoryManager.categories.filter { category in
                        category.gameIDs.contains { targetIDsSet.contains($0) }
                    }
                    if !categoriesForTargetGames.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            for category in categoriesForTargetGames {
                                categoryManager.removeGamesFromCategory(gameIDs: targetIDs, categoryID: category.id)
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
        )
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
    @State private var isSortHovered = false
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Last Played sort toggle chip
                Button {
                    sortByLastPlayed.toggle()
                    AppSettings.setBool("sortByLastPlayed", value: sortByLastPlayed)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortByLastPlayed ? "clock.fill" : "clock")
                            .font(.system(size: 10, weight: .medium))
                            .scaleEffect(sortByLastPlayed ? 1.1 : 1)
                        Text("Last Played")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(sortByLastPlayed ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 30)
                    .background(
                        Capsule()
                            .fill(sortByLastPlayed ? Color.orange : Color.secondary.opacity(0.12))
                            .scaleEffect(isSortHovered ? 1.05 : 1)
                            .shadow(color: sortByLastPlayed ? Color.orange.opacity(0.3) : .clear, radius: isSortHovered ? 4 : 0, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .help(sortByLastPlayed ? "Sorting by Last Played — click to sort by Name" : "Sorting by Name — click to sort by Last Played")
                .onHover { hovering in
                    let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if shouldAnimate {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isSortHovered = hovering
                        }
                    } else {
                        isSortHovered = hovering
                    }
                }
                .animation(.easeOut(duration: 0.2), value: sortByLastPlayed)

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
    /// The grid view relies on lazy .task(id: rom.id) for on-demand loading.
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

    private func handleFilterChange(_ filter: LibraryFilter) {
        // Only run for specific categories or systems so we don't scan 4000 items at once
        if case .system = filter {
            let missingArt = displayedROMs.filter { !$0.hasBoxArt }
            guard !missingArt.isEmpty else { return }
            
            let service = self.boxArtService
            Task {
                let resolved = await Task.detached(priority: .background) {
                    return service.resolveLocalBoxArtBatch(for: missingArt)
                }.value
                
                if !resolved.isEmpty {
                    let modifiedIDs = resolved.map { $0.id }
                    await MainActor.run {
                        for rom in resolved {
                            library.updateROM(rom, persist: false)
                        }
                        library.saveROMsToDatabase(only: modifiedIDs)
                    }
                }
            }
        }
    }
}

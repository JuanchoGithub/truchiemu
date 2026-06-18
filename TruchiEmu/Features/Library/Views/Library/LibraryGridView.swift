import SwiftUI
import AppKit

// MARK: - Library Grid View

struct SystemPickerItem: Identifiable {
    let id = UUID()
    let roms: [ROM]
}

struct LibraryGridView: View {
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @StateObject private var dragState = GameDragState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var showCreateCategorySheet: Bool
    @Binding var filter: LibraryFilter
    @Binding var selectedROM: ROM?
    @Binding var searchText: String

    // These are now passed in via init to allow ViewModel initialization
    @ObservedObject var library: ROMLibrary
    let categoryManager: CategoryManager
    @StateObject private var viewModel: LibraryViewModel


    @Environment(\.openWindow) private var openWindow

    init(
        showCreateCategorySheet: Binding<Bool>,
        filter: Binding<LibraryFilter>,
        selectedROM: Binding<ROM?>,
        searchText: Binding<String>,
        library: ROMLibrary,
        categoryManager: CategoryManager
    ) {
        self._showCreateCategorySheet = showCreateCategorySheet
        self._filter = filter
        self._selectedROM = selectedROM
        self._searchText = searchText
        self.library = library
        self.categoryManager = categoryManager
        self._viewModel = StateObject(wrappedValue: LibraryViewModel(
            library: library,
            categoryManager: categoryManager,
            initialFilter: filter.wrappedValue,
            initialSearchText: searchText.wrappedValue
        ))
    }

 @ViewBuilder
 private var inputDeviceButtons: some View {
 let hasControllers = controllerService.connectedControllers.contains(where: { !$0.isKeyboard })
 Button {
 openControllerSettings(selecting: ControllerService.keyboardId)
 } label: {
 Label(loc.localized("toolbar.keyboard"), systemImage: "keyboard")
 }
 ForEach(controllerService.connectedControllers, id: \.id) { player in
 if !player.isKeyboard {
 Button {
 openControllerSettings(selecting: player.id)
 } label: {
 Label(player.name, systemImage: "gamecontroller")
 }
 }
 }
 if hasControllers {
 Divider()
 Button {
 openControllerSettings(selecting: nil)
 } label: {
 Label(loc.localized("toolbar.configure"), systemImage: "gear")
 }
 }
 }

 private func openControllerSettings(selecting controllerId: UUID?) {
 if case .system(let system) = filter {
 AppSettings.set("pending_settings_system_id", value: system.id)
 }
 AppSettings.set("pending_settings_page", value: SettingsView.Page.controllers.rawValue)
 if let id = controllerId {
 AppSettings.set("pending_settings_controller_id", value: id.uuidString)
 }
 NotificationCenter.default.post(name: .openAppSettings, object: nil)
 }

    @ViewBuilder
    private var regionButtons: some View {
        ForEach(EmulatorLanguage.allCases) { lang in
            Button { prefs.systemLanguage = lang } label: {
                HStack {
                    Text("\(lang.flagEmoji) \(lang.name)")
                    if prefs.systemLanguage == lang { Image(systemName: "checkmark") }
                }
            }
        }
    }

    private var currentRegionName: String {
        "\(prefs.systemLanguage.flagEmoji) \(prefs.systemLanguage.name)"
    }

    private func triggerBatchDownload(reDownload: Bool) {
        Task {
            guard !viewModel.displayedROMs.isEmpty else { return }

            isDownloading = true
            downloadProgress = (0, 0)
            carouselBoxArtURLs = viewModel.displayedROMs.compactMap { rom -> URL? in
                guard rom.hasBoxArt, FileManager.default.fileExists(atPath: rom.boxArtLocalPath.path) else { return nil }
                return rom.boxArtLocalPath
            }
            marqueeOffset = 0

            let needIdentify = viewModel.displayedROMs.filter { $0.needsAutomaticIdentification && !$0.isHidden }
            if !needIdentify.isEmpty {
                for rom in needIdentify {
                    guard isDownloading else { break }
                    currentDownloadGameName = rom.displayName
                    let result = await ROMIdentifierService.shared.identify(rom: rom, preferNameMatch: true)
                    if let updated = library.applyIdentificationResult(result, to: rom, persist: true, silent: true) {
                        var refreshed = updated
                        refreshed.refreshDerivedFields()
                        if let idx = viewModel.displayedROMs.firstIndex(where: { $0.id == rom.id }) {
                            viewModel.displayedROMs[idx] = refreshed
                        }
                    }
                }
            }

            guard isDownloading else { return }

            await BoxArtService.shared.batchDownloadBoxArtLibretro(
                for: viewModel.displayedROMs,
                library: library,
                reDownloadForNewRegion: reDownload,
                onItemProgress: { current, total, gameName, boxArtURL in
                    Task { @MainActor in
                        downloadProgress = (current, total)
                        currentDownloadGameName = gameName
                        if let url = boxArtURL, !carouselBoxArtURLs.contains(url) {
                            carouselBoxArtURLs.append(url)
                        }
                    }
                }
            )

            isDownloading = false
            currentDownloadGameName = nil
            carouselBoxArtURLs = []
            marqueeOffset = 0
        }
    }






    @Environment(\.colorScheme) private var colorScheme
    @State private var renamingROM: ROM? = nil
    @State private var renameText: String = ""
    @StateObject private var gameLauncher = GameLauncher.shared

    @State private var viewMode: ViewMode = .grid
    @State private var columnCount: Int = 4
@ObservedObject var prefs = SystemPreferences.shared
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

    // System picker
    @State private var systemPickerItem: SystemPickerItem?
    
    // Drag and drop
    @State private var draggedROMs: [ROM] = []
    
    // Filter chips
    @State private var activeFilters: Set<String> = []
    @State private var sortByLastPlayed: Bool = false
    @State private var sortByLastAdded: Bool = false
    @State private var selectedGenres: Set<String> = []
    @State private var showGenrePicker: Bool = false
    @ObservedObject private var notificationHistory = NotificationHistoryManager.shared
    @State private var showNotificationPopover: Bool = false
    @State private var showNotificationCenterSheet: Bool = false
    @State private var showRegionChangeAlert: Bool = false
    @State private var showHelpSheet: Bool = false
    @State private var isDownloading = false
    @State private var downloadProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentDownloadGameName: String? = nil
    @State private var carouselBoxArtURLs: [URL] = []
    @State private var marqueeOffset: CGFloat = 0
    @State private var pendingReDownload: Bool = false

    private enum ViewMode: String { case grid, list }

    @State private var columns: [GridItem] = []
    @State private var lastSelectedFilterID: String? = nil

    // MARK: - Focused field for Cmd+F
    enum FocusableField: Hashable { case search }
    @FocusState private var focusedField: FocusableField?

    private var activeFilterDisplayText: String {
        let filterNames: [String] = activeFilters.compactMap { rawValue -> String? in
            GameFilterOption(rawValue: rawValue)?.label
        }
        var allNames = filterNames
        if !selectedGenres.isEmpty {
            allNames.append(contentsOf: selectedGenres.sorted())
        }
        return allNames.joined(separator: ", ")
    }
    
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
                Group {
                    if library.isScanning {
                        scanningOverlay
                    } else if isDownloading {
                        boxArtDownloadOverlay
                    } else if viewModel.displayedROMs.isEmpty {
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
                }
.transition(.opacity.combined(with: .scale(scale: 0.97)))
}
}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(loc.localized("library.renameGame"), isPresented: Binding(
            get: { renamingROM != nil },
            set: { if !$0 { renamingROM = nil } }
        )) {
            TextField(loc.localized("library.name"), text: $renameText)
            Button(loc.localized("library.save")) {
                if let rom = renamingROM {
                    var updated = rom
                    updated.customName = renameText.isEmpty ? nil : renameText
                    library.updateROM(updated)
                }
                renamingROM = nil
            }
            Button(loc.localized("library.cancel"), role: .cancel) {
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
            ToolbarItem(placement: .primaryAction) {
                Spacer()
            }
            ToolbarItem(placement: .primaryAction) {
            Button { pickFolder() } label: { Image(systemName: "folder.badge.plus") }
            .help(loc.localized("toolbar.addROMFolder"))
            .foregroundStyle(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
            }
            ToolbarItem(placement: .primaryAction) {
                Color.clear
                    .frame(width: 8)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(continuousZoom == 0.0 && ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
                    Slider(value: $continuousZoom, in: 0...1, step: 1.0/7.0,
                           onEditingChanged: { isEditing in
                               if viewMode == .grid, !isEditing {
                                   withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                                       applyZoomToColumnCount(animate: true)
                                   }
                               }
                           })
                .onChange(of: continuousZoom) { _, _ in
                    if viewMode == .grid {
                        updateColumns()
                    }
                }
.frame(width: 160)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(continuousZoom == 1.0 && ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
                    Text("\(Int(continuousZoom * 100))%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .frame(width: 36)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                AccentSegmentedControl(
                    selection: $viewMode,
                    options: [(ViewMode.grid, "square.grid.2x2"), (ViewMode.list, "list.bullet")],
                    accentColor: ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .blue
                )
                .frame(width: 80)
                .help(loc.localized("toolbar.switchViewMode"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section(loc.localized("toolbar.boxArtStyle")) {
                        ForEach(BoxType.allCases) { type in
                            Button {
                                if case .system(let system) = filter {
                                    prefs.setBoxType(type, for: system.id)
                                }
                            } label: {
                                HStack {
                                    Label(type.rawValue, systemImage: type.iconName)
                                    if case .system(let system) = filter, prefs.boxType(for: system.id) == type {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .disabled(!isSystemView)
                        }
                    }
                    Divider()
                    Section(loc.localized("toolbar.download")) {
                        Button {
                            guard !isDownloading else { return }
                            let regionSuffix = SystemPreferences.shared.systemLanguage.regionSuffix
                            let stale = BoxArtService.shared.romsWithStaleRegion(in: viewModel.displayedROMs, currentRegionSuffix: regionSuffix)
                            if stale.isEmpty {
                                triggerBatchDownload(reDownload: false)
                            } else {
                                showRegionChangeAlert = true
                            }
                        } label: {
                            Label(loc.localized("toolbar.downloadAllBoxArt"), systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(isDownloading)
                    }
         } label: {
                Image(systemName: "photo.stack")
            }
            .help(loc.localized("toolbar.boxArtOptions"))
            .tint(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section(loc.localized("toolbar.inputDevice")) {
                        inputDeviceButtons
                    }
                    Section(loc.localized("toolbar.region")) {
                        regionButtons
                    }
        } label: {
 HStack(spacing: 4) {
 let hasControllers = controllerService.connectedControllers.contains(where: { !$0.isKeyboard })
 if hasControllers {
 Image(systemName: "keyboard")
 Image(systemName: "gamecontroller")
 } else {
 Image(systemName: "keyboard")
 }
 Text(prefs.systemLanguage.flagEmoji)
                }
            }
        .help(loc.localized("toolbar.inputDeviceAndRegion"))
        .tint(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showNotificationPopover.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                    if notificationHistory.unreadCount > 0 {
                    Text("\(notificationHistory.unreadCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.textOnAccent(colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppColors.brandAccent)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .foregroundStyle(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
            .help(loc.localized("toolbar.notifications"))
            .popover(isPresented: $showNotificationPopover, arrowEdge: .bottom) {
                NotificationPopoverView(showAll: $showNotificationCenterSheet)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showHelpSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help(loc.localized("toolbar.help"))
            .foregroundStyle(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
        }
        ToolbarItem(placement: .primaryAction) {
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
                Label(loc.localized("app.settings"), systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 4)
            .help(loc.localized("app.settings"))
            .foregroundStyle(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
        }
    }
    .confirmationDialog(loc.localized("toolbar.regionChangedTitle"), isPresented: $showRegionChangeAlert, titleVisibility: .visible) {
        Button("\(loc.localized("toolbar.regionReDownload")) (\(prefs.systemLanguage.name))") {
            triggerBatchDownload(reDownload: true)
        }
        Button(loc.localized("toolbar.regionDownloadMissing")) {
            triggerBatchDownload(reDownload: false)
        }
        Button("Cancel", role: .cancel) { }
    } message: {
        Text(loc.localized("toolbar.regionChangedMessage"))
    }
    .sheet(item: $manualBoxArtSearchROM) { rom in
        BoxArtPickerView(rom: rom)
    }
    .sheet(isPresented: $showNotificationCenterSheet) {
        NotificationCenterSheetView()
    }
    .sheet(isPresented: $showHelpSheet) {
        HelpSheetView()
    }
    .sheet(item: $systemPickerItem, onDismiss: { systemPickerItem = nil }) { item in
        SystemPickerView(roms: item.roms, library: library) {
            systemPickerItem = nil
        }
    }
    .onAppear {
            // Recompute columns from saved zoom level
            applyZoomToColumnCount(animate: false)
            sortByLastPlayed = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
            sortByLastAdded = AppSettings.getBool("sortByLastAdded", defaultValue: false)
            
            // Initialize view mode from settings
            if let savedMode = AppSettings.getString("gridViewMode") {
                viewMode = savedMode == "list" ? .list : .grid
            }
            
            // Sync view model with restored sort settings
viewModel.updateFilters(
                filter: filter,
                searchText: searchText,
                activeFilters: activeFilters,
                sortByLastPlayed: sortByLastPlayed,
                sortByLastAdded: sortByLastAdded,
                selectedGenres: selectedGenres
            )

            // Contextually resolve local boxarts for the current view
            handleFilterChange(filter)
            
            // Add notification observers for menu commands
            setupMenuNotificationObservers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addROMFolder)) { _ in
            pickFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewModeChanged)) { notification in
            if let mode = notification.object as? String {
                if mode == "grid" {
                    viewMode = .grid
                } else if mode == "list" {
                    viewMode = .list
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sortChanged)) { _ in
            sortByLastPlayed = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
            sortByLastAdded = AppSettings.getBool("sortByLastAdded", defaultValue: false)
            viewModel.updateFilters(
                filter: filter,
                searchText: searchText,
                activeFilters: activeFilters,
                sortByLastPlayed: sortByLastPlayed,
                sortByLastAdded: sortByLastAdded,
                selectedGenres: selectedGenres
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterToggled)) { notification in
            if let rawValue = notification.object as? String {
                if activeFilters.contains(rawValue) {
                    activeFilters.remove(rawValue)
                } else {
                    activeFilters.insert(rawValue)
                }
                viewModel.updateFilters(
                    filter: filter,
                    searchText: searchText,
                    activeFilters: activeFilters,
                    sortByLastPlayed: sortByLastPlayed,
                    sortByLastAdded: sortByLastAdded,
                    selectedGenres: selectedGenres
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomChanged)) { notification in
            guard let action = notification.object as? String else { return }
            withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                switch action {
                case "in":
                    continuousZoom = min(1.0, continuousZoom + 0.1)
                case "out":
                    continuousZoom = max(0.0, continuousZoom - 0.1)
                case "reset":
                    continuousZoom = 0.5
                default:
                    break
                }
            }
            applyZoomToColumnCount(animate: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // Language changes are handled by SystemPreferences automatically via AppSettings
        }
        .onReceive(NotificationCenter.default.publisher(for: .boxArtStyleChanged)) { _ in
            // Trigger UI refresh for box art style change
        }
        .onReceive(NotificationCenter.default.publisher(for: .boxArtVisibilityChanged)) { _ in
            // Trigger UI refresh - handled by AppSettings getBool in view
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFilter)) { notification in
            if let filterID = notification.object as? String {
                if let newFilter = restoreFilter(from: filterID) {
                    filter = newFilter
                }
            }
        }
        .onChange(of: filter) { _, newFilter in
            handleFilterChange(newFilter)
            viewModel.updateFilters(
                filter: newFilter,
                searchText: searchText,
                activeFilters: activeFilters,
                sortByLastPlayed: sortByLastPlayed,
                sortByLastAdded: sortByLastAdded,
                selectedGenres: selectedGenres
            )
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.updateFilters(
                filter: filter,
                searchText: newValue,
                activeFilters: activeFilters,
                sortByLastPlayed: sortByLastPlayed,
                sortByLastAdded: sortByLastAdded,
                selectedGenres: selectedGenres
            )
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
        .background {
            Button("") { focusedField = .search }
                .keyboardShortcut(KeyEquivalent("f"), modifiers: .command)
                .hidden()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in }
        // Note: Delete key handling via onKeyPress requires macOS 14+
        // For macOS 13, users can use context menu or confirm delete action
    }

    @State private var gridWidth: CGFloat = 800

    // Whether the current filter is a system view (used to enable/disable box art style).
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
            repeating: GridItem(.flexible(minimum: 1, maximum: cardWidth), spacing: spacing),
            count: columnCount
        )
    }
    
    private func setupMenuNotificationObservers() {
        // Observers added via onReceive modifiers above
    }
    
    private func restoreFilter(from id: String) -> LibraryFilter? {
        if id == "all" { return .all }
        if id == "favorites" { return .favorites }
        if id == "recent" { return .recent }
        if id == "lastAdded" { return .lastAdded }
        if id == "playHistory" { return .recent } // Play History shows all games sorted by last played
        if id == "hidden" { return .hidden }
        if id == "mameNonGames" { return .mameNonGames }
        if id.hasPrefix("category-") {
            let catID = String(id.dropFirst("category-".count))
            return .category(catID)
        }
        if id.hasPrefix("system-") {
            let sysID = String(id.dropFirst("system-".count))
            if let system = SystemDatabase.system(forID: sysID) {
                return .system(system)
            }
        }
        return nil
    }
    
    private var gridView: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(Array(viewModel.displayedROMs.enumerated()), id: \.element.id) { index, rom in
                    let isSelected = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                    
                    let draggedItemsForCard: [ROM] = {
                        if isSelected {
                            var dragIDs = selectedROMs
                            if let singleSelection = selectedROM {
                                dragIDs.insert(singleSelection.id)
                            }
                            return viewModel.displayedROMs.filter { dragIDs.contains($0.id) }
                        } else {
                            return [rom]
                        }
                    }()

        GameCardView(
          rom: rom,
          isSelected: isSelected,
          isMultiSelected: selectedROMs.contains(rom.id),
          zoomLevel: continuousZoom,
          filter: filter,
          onTap: { handleTap(on: rom, at: index) },
          contextMenu: { contextMenu(for: rom) }
        )
        .onDrag {
          draggedROMs = draggedItemsForCard
          dragState.startDrag(gameIDs: draggedItemsForCard.map { $0.id })
          let provider = NSItemProvider(object: NSString(string: draggedItemsForCard.map { $0.id.uuidString }.joined(separator: ",")))
          return provider
        } preview: {
          DragPreviewStack(
            mainROM: rom,
            mainImage: nil,
            draggedROMs: draggedItemsForCard.filter { $0.id != rom.id },
            zoomLevel: continuousZoom
          )
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Task {
                    await launchGame(rom)
                }
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
                let scale = value / lastMagnification
                let zoomDelta = (scale - 1.0) * 0.15
                let newZoom = max(0, min(1, continuousZoom + zoomDelta))
                continuousZoom = newZoom
                updateColumns()
                lastMagnification = value
            }
            .onEnded { _ in
                let snapped = round(continuousZoom * 7.0) / 7.0
                withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                    continuousZoom = snapped
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
    
    // The scale factor applied to the entire grid content
    private var gridScale: CGFloat {
        // Base scale starts at 0.7 and goes up to 1.3
        0.7 + (continuousZoom * 0.6)
    }
    
    // Dynamic spacing between grid items based on zoom
    private var gridSpacing: CGFloat {
        // Less spacing when zoomed in (cards are bigger)
        8 + ((1.0 - continuousZoom) * 12)
    }
    
    // Horizontal padding adjusts with zoom to prevent edge clipping
    private var horizontalPadding: CGFloat {
        8 + ((1.0 - continuousZoom) * 12)
    }
    
    // Combined grid padding
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
                i < viewModel.displayedROMs.count ? viewModel.displayedROMs[i].id : nil
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
            ForEach(Array(viewModel.displayedROMs.enumerated()), id: \.element.id) { index, rom in
                let isSelected = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
            GameListRowView(rom: rom, isSelected: isSelected, isEvenRow: index.isMultiple(of: 2), zoomLevel: zoomLevel, filter: filter, contextMenu: { contextMenu(for: rom) })
                .tag(rom)
                .listRowBackground(Color.clear)
                .contentShape(Rectangle())
.onTapGesture {
                handleListTap(on: rom, at: index)
            }
            .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Task {
                    await launchGame(rom)
                }
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
            items = viewModel.displayedROMs.filter { dragIDs.contains($0.id) }
          } else {
            items = [rom]
          }

          draggedROMs = items
          dragState.startDrag(gameIDs: items.map { $0.id })
          let provider = NSItemProvider(object: NSString(string: items.map { $0.id.uuidString }.joined(separator: ",")))
          return provider
        } preview: {
          DragPreviewStack(
            mainROM: rom,
            mainImage: nil,
            draggedROMs: (isSelected ? viewModel.displayedROMs.filter { 
              var dragIDs = selectedROMs
              if let singleSelection = selectedROM {
                dragIDs.insert(singleSelection.id)
              }
              return dragIDs.contains($0.id) && $0.id != rom.id
            } : []),
            zoomLevel: zoomLevel
          )
        }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
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
                i < viewModel.displayedROMs.count ? viewModel.displayedROMs[i].id : nil
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
    
    // Applies the current continuousZoom value to columnCount and updates the grid.
    // Shared between slider, pinch gesture, and onAppear restoration.
    private func applyZoomToColumnCount(animate: Bool = false) {
        if animate {
            withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
                updateColumns()
            }
        } else {
            updateColumns()
        }
    }

    @State private var scanningMessageIndex = 0
    
    private var scanningMessages: [String] {[
            loc.localized("library.scanningLibrary"),
            loc.localized("library.identifyingGames"),
            loc.localized("library.buildingShelf"),
            loc.localized("library.fetchingBoxArt"),
            loc.localized("library.organizingByPlatform"),
            loc.localized("library.almostReady")
        ]
    }
    
    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            ZStack {
                // CRT monitor frame
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 2)
                    .frame(width: 72, height: 72)

                // Warm glow
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.brandAccent.opacity(0.08))
                    .frame(width: 72, height: 72)

                // Animated pulse ring
                Circle()
                    .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + library.scanProgress * 0.5)
                    .opacity(1.0 - library.scanProgress * 0.8)

                // Controller icon with warm glow
                Image(systemName: "arcade.stick")
                    .font(.system(size: 28))
                    .foregroundStyle(AppGradients.accent)
                    .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 6)

                // CRT scan line
                ScanningScanLine()
                    .frame(width: 56, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .modifier(ScanningPulseAnimation())

            BouncingProgressBar()
                .frame(width: 320)

            Group {
		Text(scanningMessages[scanningMessageIndex])
		.foregroundColor(AppColors.textSecondary(colorScheme))
                    .contentTransition(.numericText())
            }
            .font(.body)
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if library.isScanning {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        scanningMessageIndex = (scanningMessageIndex + 1) % scanningMessages.count
                    }
                }
            }

            // Fun stats during scan
            if library.roms.count > 0 {
		Text("\(library.roms.count) \(loc.localized("library.gamesFound"))")
		.font(.caption)
		.foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    .contentTransition(.numericText())
            }

            Button(role: .cancel) {
                library.stopScan()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
.clipped()
    }

    @State private var boxArtDownloadMessageIndex = 0

    private var boxArtDownloadMessages: [String] {[
        loc.localized("library.boxArtDownloading"),
        loc.localized("library.boxArtFetchingCovers"),
        loc.localized("library.boxArtMatchingRegion"),
        loc.localized("library.boxArtAlmostDone")
    ]}

    private var boxArtDownloadProgress: Double {
        guard downloadProgress.total > 0 else { return 0 }
        return Double(downloadProgress.current) / Double(downloadProgress.total)
    }

    private var boxArtDownloadOverlay: some View {
        VStack(spacing: 20) {
            if carouselBoxArtURLs.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 2)
                        .frame(width: 72, height: 72)

                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppColors.brandAccent.opacity(0.08))
                        .frame(width: 72, height: 72)

                    Circle()
                        .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .scaleEffect(1.0 + boxArtDownloadProgress * 0.3)
                        .opacity(1.0 - boxArtDownloadProgress * 0.6)

                    Image(systemName: "photo.artframe")
                        .font(.system(size: 28))
                        .foregroundStyle(AppGradients.accent)
                        .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 6)
                }
                .modifier(ScanningPulseAnimation())
            } else {
                BoxArtMarquee(urls: carouselBoxArtURLs, offset: $marqueeOffset)
                    .frame(height: 180)
                    .padding(.horizontal, -20)
                    .mask(
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                            Rectangle().fill(Color.white)
                            LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                        }
                    )
            }

            if downloadProgress.total > 0 {
                ProgressView(value: boxArtDownloadProgress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.brandAccent)
                    .frame(width: 280)

                Text("\(downloadProgress.current)/\(downloadProgress.total)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .contentTransition(.numericText())
            } else {
                BouncingProgressBar()
                    .frame(width: 280)
            }

            Group {
                Text(boxArtDownloadMessages[boxArtDownloadMessageIndex])
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .contentTransition(.numericText())
            }
            .font(.body)
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if isDownloading {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        boxArtDownloadMessageIndex = (boxArtDownloadMessageIndex + 1) % boxArtDownloadMessages.count
                    }
                }
            }

            if let gameName = currentDownloadGameName {
                Text(verbatim: gameName)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
                    .contentTransition(.numericText())
                    .id(gameName)
            }

            Button(role: .cancel) {
                isDownloading = false
                currentDownloadGameName = nil
                carouselBoxArtURLs = []
                marqueeOffset = 0
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @State private var emptyStateAppeared = false
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                EmptyStateIllustration()
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
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .opacity(emptyStateAppeared ? 1 : 0)
                    .offset(y: emptyStateAppeared ? 0 : 8)
                Text(emptyStateDescription)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .opacity(emptyStateAppeared ? 1 : 0)
                    .offset(y: emptyStateAppeared ? 0 : 8)
                if activeFilters.isEmpty && searchText.isEmpty && library.roms.isEmpty {
                    Button {
                        pickFolder()
                    } label: {
                        Label(loc.localized("library.addRomFolder"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.brandAccentSecondary)
                    .opacity(emptyStateAppeared ? 1 : 0)
                    .offset(y: emptyStateAppeared ? 0 : 8)
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
        .background(AppDecorativeGradients.warmGlow)
        .clipped()
        .sheet(item: $manualBoxArtSearchROM) { rom in
            BoxArtPickerView(rom: rom)
        }
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
        } else if library.roms.isEmpty {
            return "tray"
        } else {
            return "tray"
        }
    }
    
    private var emptyStateTitle: String {
        if !activeFilters.isEmpty && searchText.isEmpty {
            return loc.localized("library.noGamesMatchFilters")
        } else if !searchText.isEmpty {
            return loc.localized("library.nothingMatching").replacingOccurrences(of: "{0}", with: searchText)
        } else if library.roms.isEmpty {
            return loc.localized("library.gamingShelfEmpty")
        } else {
            return loc.localized("library.nothingHere")
        }
    }
    
    private var emptyStateDescription: String {
        if !activeFilters.isEmpty && searchText.isEmpty {
            return loc.localized("library.tryLooseningFilters")
        } else if !searchText.isEmpty {
            return loc.localized("library.tryDifferentSearch")
        } else if library.roms.isEmpty {
            return loc.localized("library.addFolderDescription")
        } else {
            return loc.localized("library.tryDifferentCategory")
        }
    }
    
    // Opens a folder picker to add ROM folders to the library.
    // This empty-state CTA gives users a direct path to value when no games exist.
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = loc.localized("library.selectFolders")
        panel.prompt = loc.localized("library.addFolders")
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
                    Label(loc.localized("contextMenu.seeGameInfo"), systemImage: "info.circle")
                }

                Button {
                    Task {
                        await launchGame(rom)
                    }
                } label: {
                    Label(loc.localized("contextMenu.launchGame"), systemImage: "play.fill")
                }

                Button {
                    renameText = rom.customName ?? rom.metadata?.title ?? rom.name
                    renamingROM = rom
                } label: {
                    Label(loc.localized("contextMenu.renameGame"), systemImage: "pencil")
                }

                Divider()

                Menu {
                    Button {
                        showCreateCategorySheet = true
                    } label: {
                        Label(loc.localized("contextMenu.newCategory"), systemImage: "plus.circle")
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
                                        .foregroundColor(AppColors.brandAccent)
                                } else {
			Image(systemName: "plus.circle")
				.foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
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
                            Label(loc.localized("contextMenu.removeFromAllCategories"), systemImage: "folder.badge.minus")
                        }
                    }
                } label: {
                    Label(loc.localized("contextMenu.categories"), systemImage: "folder.badge.plus")
                }

                    Divider()
                    Button {
                        let targetROMs = library.roms.filter { targetIDsSet.contains($0.id) }
                        systemPickerItem = SystemPickerItem(roms: targetROMs)
                    } label: {
                        Label(loc.localized("contextMenu.moveToSystem"), systemImage: "arrow.triangle.swap")
                    }
                    
                    Divider()
                    Button {
                    var updated = rom
                    updated.isFavorite.toggle()
                    library.updateROM(updated)
                } label: {
                    Label(
                        rom.isFavorite ? loc.localized("contextMenu.removeFromFavorites") : loc.localized("contextMenu.addToFavorites"),
                        systemImage: rom.isFavorite ? "star.slash" : "star"
                    )
                }
                Divider()
                Button {
                    manualBoxArtSearchROM = rom
                } label: {
                    Label(loc.localized("contextMenu.getBoxArt"), systemImage: "photo")
                }
                Button {
                    NSWorkspace.shared.selectFile(rom.path.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label(loc.localized("contextMenu.revealInFinder"), systemImage: "folder")
                }

                Divider()
                if rom.isHidden {
                    Button {
                        unhideGame(rom)
                    } label: {
                        Label(loc.localized("contextMenu.unhideGame"), systemImage: "eye")
                    }
                } else {
                    Button {
                        hideGame(rom)
                    } label: {
                        Label(loc.localized("contextMenu.hideGame"), systemImage: "eye.slash")
                    }
                    Button(role: .destructive) {
                        gameToDelete = rom
                        showDeleteConfirmation = true
                    } label: {
                        Label(loc.localized("contextMenu.deleteGame"), systemImage: "trash")
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

        NotificationHistoryManager.shared.post(
            icon: "eye.slash",
            title: loc.localized("pill.gameHidden"),
            subtitle: rom.displayName,
            autoDismissDelay: 5,
            actionLabel: loc.localized("pill.undo"),
            actionType: "undoHide",
            actionPayload: ROMActionPayload(romID: rom.id)
        )
    }

    private func unhideGame(_ rom: ROM) {
        var updated = rom
        updated.isHidden = false
        library.updateROM(updated)
    }

    private func deleteGameAndROM(_ rom: ROM) {
        var trashURL: URL?

        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: rom.path, resultingItemURL: &resultingURL)
            trashURL = resultingURL as? URL
            LoggerService.info(category: "LibraryGridView", "ROM file moved to trash: \(rom.path.lastPathComponent)")
        } catch {
            LoggerService.warning(category: "LibraryGridView", "Failed to move ROM to trash: \(error.localizedDescription). Removing from library anyway.")
        }

        removeROMFromLibrary(rom)

        let romJSON = (try? JSONEncoder().encode(rom)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

        NotificationHistoryManager.shared.post(
            icon: "trash",
            title: loc.localized("pill.gameTrashed"),
            subtitle: rom.displayName,
            autoDismissDelay: 5,
            actionLabel: loc.localized("pill.undo"),
            actionType: "undoTrash",
            actionPayload: TrashActionPayload(romID: rom.id, originalPath: rom.path.path, romJSON: romJSON)
        )

        if let trashURL = trashURL {
            AppSettings.set("pendingTrashRestore_\(rom.id.uuidString)", value: trashURL.path)
        }
    }

private func removeROMFromLibrary(_ rom: ROM) {
    library.roms.removeAll { $0.id == rom.id }
    LibraryMetadataStore.shared.deleteMetadata(for: rom)
    let repo = ROMRepository(context: SwiftDataContainer.shared.mainContext)
    repo.deleteROMsByPath([rom.path.path])
    library.updateCounts()

        // If this ROM was selected, deselect it
        if selectedROM?.id == rom.id {
            selectedROM = nil
        }
    }

    // MARK: - Search & Filters

    private var searchField: some View {
        HStack {
		Image(systemName: "magnifyingglass")
		.foregroundColor(AppColors.textSecondary(colorScheme))
            TextField(loc.localized("library.searchGames"), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
			Image(systemName: "xmark.circle.fill")
				.foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(10)
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 4)
    }
    
    // Visible zoom slider for the grid view
    // Uses onEditingChanged to avoid column recalculation on every tiny value change
    // during scroll (which causes scroll lock/jank).
    private var zoomSlider: some View {
        HStack(spacing: 8) {
		Image(systemName: "minus.magnifyingglass")
		.font(.system(size: 12))
		.foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.6))
		.frame(width: 16)

		Slider(value: $continuousZoom, in: 0...1, step: 1.0/7.0,
			onEditingChanged: { isEditing in
			if !isEditing {
				// On release, snap to nearest step
				withAnimation(.interpolatingSpring(stiffness: 150, damping: 20)) {
				applyZoomToColumnCount(animate: true)
				}
			}
			})

		Image(systemName: "plus.magnifyingglass")
		.font(.system(size: 12))
		.foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.6))
		.frame(width: 16)

		Text("\(Int(continuousZoom * 100))%")
		.font(.system(size: 11, weight: .medium, design: .monospaced))
		.foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
		.frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    @State private var isLastPlayedHovered = false
    @State private var isLastAddedHovered = false
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Last Played sort toggle chip
                Button {
                    sortByLastPlayed.toggle()
                    AppSettings.setBool("sortByLastPlayed", value: sortByLastPlayed)
                    viewModel.updateFilters(
                        filter: filter,
                        searchText: searchText,
                        activeFilters: activeFilters,
                        sortByLastPlayed: sortByLastPlayed,
                        sortByLastAdded: sortByLastAdded
                    )
                } label: {

                    HStack(spacing: 4) {
                        Image(systemName: sortByLastPlayed ? "clock.fill" : "clock")
                            .font(.system(size: 10, weight: .medium))
                            .scaleEffect(sortByLastPlayed ? 1.1 : 1)
                        Text(loc.localized("library.lastPlayed"))
                            .font(.system(size: 11, weight: .medium))
                    }
.foregroundColor(sortByLastPlayed ? AppColors.textOnAccent(colorScheme) : (isLastPlayedHovered ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme)))
	.padding(.horizontal, 10)
	.padding(.vertical, 6)
	.frame(minHeight: 30)
	.background(
		Capsule()
		.fill(sortByLastPlayed ? AppColors.brandAccent : (isLastPlayedHovered ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme)))
		.scaleEffect(isLastPlayedHovered ? 1.05 : 1)
		.shadow(color: sortByLastPlayed ? AppColors.brandAccent.opacity(0.3) : (isLastPlayedHovered ? AppColors.brandAccent.opacity(0.2) : .clear), radius: isLastPlayedHovered ? 4 : 0, y: 2)
	)
                }
                .buttonStyle(.plain)
                .help(sortByLastPlayed ? "Sorting by Last Played — click to sort by Name" : "Sorting by Name — click to sort by Last Played")
                .onHover { hovering in
                    let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if shouldAnimate {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isLastPlayedHovered = hovering
                        }
                    } else {
                        isLastPlayedHovered = hovering
                    }
                }
                .animation(.easeOut(duration: 0.2), value: sortByLastPlayed)

                // Last Added sort toggle chip
                Button {
                    sortByLastAdded.toggle()
                    AppSettings.setBool("sortByLastAdded", value: sortByLastAdded)
                    viewModel.updateFilters(
                        filter: filter,
                        searchText: searchText,
                        activeFilters: activeFilters,
                        sortByLastPlayed: sortByLastPlayed,
                        sortByLastAdded: sortByLastAdded
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortByLastAdded ? "calendar" : "calendar")
                            .font(.system(size: 10, weight: .medium))
                            .scaleEffect(sortByLastAdded ? 1.1 : 1)
                        Text(loc.localized("library.lastAdded"))
                            .font(.system(size: 11, weight: .medium))
                    }
.foregroundColor(sortByLastAdded ? AppColors.textOnAccent(colorScheme) : (isLastAddedHovered ? AppColors.brandAccent : AppColors.textSecondaryNeutral(colorScheme)))
	.padding(.horizontal, 10)
	.padding(.vertical, 6)
	.frame(minHeight: 30)
	.background(
		Capsule()
		.fill(sortByLastAdded ? AppColors.brandAccent : (isLastAddedHovered ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme)))
		.scaleEffect(isLastAddedHovered ? 1.05 : 1)
		.shadow(color: sortByLastAdded ? AppColors.brandAccent.opacity(0.3) : (isLastAddedHovered ? AppColors.brandAccent.opacity(0.2) : .clear), radius: isLastAddedHovered ? 4 : 0, y: 2)
	)
                }
                .buttonStyle(.plain)
                .help(sortByLastAdded ? "Sorting by Last Added — click to sort by Name" : "Sorting by Name — click to sort by Last Added")
                .onHover { hovering in
                    let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if shouldAnimate {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isLastAddedHovered = hovering
                        }
                    } else {
                        isLastAddedHovered = hovering
                    }
                }
                .animation(.easeOut(duration: 0.2), value: sortByLastAdded)

                ForEach(GameFilterOption.allCases) { option in
                    FilterChipView(
                        option: option,
                        isActive: activeFilters.contains(option.rawValue),
                        action: { toggleFilter(option) }
                    )
                }

                // Genre filter chip
                Button {
                    showGenrePicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedGenres.isEmpty ? "tag" : "tag.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text(loc.localized("library.genre"))
                            .font(.system(size: 11, weight: .medium))
                        if !selectedGenres.isEmpty {
                            Text("(\(selectedGenres.count))")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(selectedGenres.isEmpty ? .secondary : AppColors.textOnAccent(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 30)
                    .background(Capsule().fill(selectedGenres.isEmpty ? AppColors.cardBackgroundSubtle(colorScheme) : AppColors.brandAccent))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGenrePicker) {
                    GenrePickerView(
                        selectedGenres: $selectedGenres,
                        allGenres: GenreManager.shared.getAllDisplayGenres(from: library.roms),
                        onApply: {
                            viewModel.updateFilters(
                                filter: filter,
                                searchText: searchText,
                                activeFilters: activeFilters,
                                sortByLastPlayed: sortByLastPlayed,
                                sortByLastAdded: sortByLastAdded,
                                selectedGenres: selectedGenres
                            )
                        }
                    )
                }

                if !activeFilters.isEmpty || !selectedGenres.isEmpty {
                    Button {
                        activeFilters.removeAll()
                        selectedGenres.removeAll()
                        viewModel.updateFilters(
                            filter: filter,
                            searchText: searchText,
                            activeFilters: activeFilters,
                            sortByLastPlayed: sortByLastPlayed,
                            sortByLastAdded: sortByLastAdded,
                            selectedGenres: selectedGenres
                        )
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                            Text("Clear")
                                .font(.system(size: 10, weight: .medium))
                        }
		.foregroundColor(AppColors.textOnAccent(colorScheme))
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.frame(minHeight: 30)
		.background(AppColors.brandAccent)
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
                .foregroundColor(AppColors.brandAccent)
                .font(.caption)
            
            Text("Filtering: " + activeFilterDisplayText)
                .font(.caption)
	.foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
	.lineLimit(1)

	Spacer()

	Text("\(viewModel.displayedROMs.count) game\(viewModel.displayedROMs.count == 1 ? "" : "s")")
	.font(.caption)
	.foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
    }
    
    private func toggleFilter(_ option: GameFilterOption) {
        if activeFilters.contains(option.rawValue) {
            activeFilters.remove(option.rawValue)
        } else {
            activeFilters.insert(option.rawValue)
        }
        
        viewModel.updateFilters(
            filter: filter,
            searchText: searchText,
            activeFilters: activeFilters,
            sortByLastPlayed: sortByLastPlayed,
            sortByLastAdded: sortByLastAdded
        )
    }


@MainActor
    private func launchGame(_ rom: ROM) async {
        guard let sysID = rom.systemID,
              let system = SystemDatabase.system(forID: sysID) else { return }

        // Use centralized helper to resolve core ID (eliminates code duplication)
        let cid = coreManager.resolveCoreID(for: rom, system: system)

        if !coreManager.isInstalled(coreID: cid) {
            coreManager.requestCoreDownload(for: cid, systemID: sysID, romID: rom.id, slotToLoad: nil)
            return
        }

        await gameLauncher.launchGame(
            rom: library.roms.first { $0.id == rom.id } ?? rom,
            coreID: cid,
            library: library
        )
    }

    private func handleFilterChange(_ filter: LibraryFilter) {
        // Only run for specific categories or systems so we don't scan 4000 items at once
        if case .system = filter {
            let missingArt = viewModel.displayedROMs.filter { !$0.hasBoxArt }
            guard !missingArt.isEmpty else { return }
            
            let service = BoxArtService.shared
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

    // MARK: - Empty State Illustration

private struct EmptyStateIllustration: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // TV/monitor body
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    colorScheme == .dark
                        ? Color.black.opacity(0.4)
                        : AppColors.brandAccent.opacity(0.06)
                )
                .frame(width: 80, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.brandAccent.opacity(0.3), lineWidth: 1.5)
                )

            // Warm glow behind
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.brandAccent.opacity(0.06))
                .frame(width: 80, height: 64)
                .blur(radius: 8)

            // Screen area
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    colorScheme == .dark
                        ? Color.black.opacity(0.6)
                        : Color.white.opacity(0.5)
                )
                .frame(width: 60, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.brandAccent.opacity(0.15), lineWidth: 1)
                )

            // Game controller icon
            Image(systemName: "gamecontroller")
                .font(.system(size: 20))
                .foregroundStyle(AppGradients.accent)

            // Scanline overlay
            AppRetroEffects.scanlineOverlay(opacity: 0.04)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 60, height: 44)
        }
        .frame(width: 80, height: 64)
    }
}

// MARK: - Box Art Marquee Carousel

private struct BoxArtMarquee: View {
    let urls: [URL]
    @Binding var offset: CGFloat
    @State private var slots: [(url: URL?, vi: Int)] = (0..<6).map { (url: nil, vi: $0) }
    @State private var timer: Timer?
    @State private var appeared = false

    private let itemWidth: CGFloat = 150
    private let spacing: CGFloat = 14
    private let stride: CGFloat = 164
    private let speed: CGFloat = 1.4
    private let slotCount = 6
    private let visibleSlots = 3

    // Slot is off-screen left when its right edge < -itemWidth (fully past clip)
    // We recycle when it's past that by at least one stride to guarantee it's invisible.
    private let leftKillX: CGFloat = -320

    private var viewportWidth: CGFloat { CGFloat(visibleSlots - 1) * stride + itemWidth }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<slotCount, id: \.self) { i in
                slotView(at: i)
            }
        }
        .frame(width: viewportWidth, height: 180)
        .clipped()
        .onAppear {
            if slots[0].url == nil { seedSlots() }
            if !appeared {
                appeared = true
                timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
                    DispatchQueue.main.async { tick() }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            appeared = false
            slots = (0..<6).map { (url: nil, vi: $0) }
        }
    }

    @ViewBuilder
    private func slotView(at i: Int) -> some View {
        if i < slots.count {
            let xPos = CGFloat(slots[i].vi) * stride - offset
            if let url = slots[i].url, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: itemWidth, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: xPos)
            } else {
                Color.clear
                    .frame(width: itemWidth, height: 180)
                    .offset(x: xPos)
            }
        }
    }

    private func seedSlots() {
        slots = []
        var seen = Set<Int>()
        for i in 0..<slotCount {
            let url: URL? = urls.isEmpty ? nil : {
                guard urls.count > seen.count else { return nil }
                var idx: Int
                repeat { idx = Int.random(in: 0..<urls.count) } while seen.contains(idx)
                seen.insert(idx)
                return urls[idx]
            }()
            slots.append((url: url, vi: i))
        }
    }

    private func tick() {
        offset += speed
        for i in 0..<slotCount {
            let xPos = CGFloat(slots[i].vi) * stride - offset
            if xPos < leftKillX {
                let maxVI = slots.map(\.vi).max() ?? 0
                slots[i].vi = maxVI + 1
                slots[i].url = pickRandom()
            }
        }
    }

    private func pickRandom() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls[Int.random(in: 0..<urls.count)]
    }
}

// MARK: - Scanning Scan Line

private struct ScanningScanLine: View {
    @State private var scanOffset: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 1)
                .fill(AppGradients.warmAccent.opacity(0.5))
                .frame(width: geo.size.width * 0.5, height: 2)
                .offset(x: geo.size.width * scanOffset)
                .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 4)
                .onAppear {
                    withAnimation(
                        Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)
                    ) {
    scanOffset = 0.3
                }
            }
        }
    }
}
}


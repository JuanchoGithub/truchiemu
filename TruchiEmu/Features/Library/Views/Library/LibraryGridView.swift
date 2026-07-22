import SwiftUI
import AppKit

private struct GamepadCycleStep: Equatable {
    let sortByLastPlayed: Bool
    let sortByLastAdded: Bool
    let filter: GameFilterOption?
    let genre: String?
}

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
    @ObservedObject private var raService = RetroAchievementsService.shared
    @Binding var showCreateCategorySheet: Bool
    @Binding var filter: LibraryFilter
    @Binding var selectedROM: ROM?
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding

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
        searchFocused: FocusState<Bool>.Binding,
        library: ROMLibrary,
        categoryManager: CategoryManager
    ) {
        self._showCreateCategorySheet = showCreateCategorySheet
        self._filter = filter
        self._selectedROM = selectedROM
        self._searchText = searchText
        self.searchFocused = searchFocused
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
    @ObservedObject private var gamepadNav = GamepadNavigationManager.shared

    @State private var viewMode: ViewMode = .grid
    @State private var columnCount: Int = 4
@ObservedObject var prefs = SystemPreferences.shared
@State private var manualBoxArtSearchROM: ROM?
    
    
    // Delete/hide game states
    @State private var gameToDelete: ROM?
    @State private var confirmDeleteTap = false
    
    // Smooth pinch-to-zoom state
    @State private var continuousZoom: Double = AppSettings.getDouble("gridZoomLevel", defaultValue: 0.5)
    @State private var lastMagnification: Double = 1.0
    
    // Multi-select state
    @State private var selectedROMs: Set<UUID> = []
    @State private var lastSelectedIndex: Int? = nil

    // System picker
    @State private var systemPickerItem: SystemPickerItem?
    
    // Drag and drop
    @State private var draggedROMs: [ROM] = []
    // Scroll target for gamepad navigation
    @State private var gridScrollTarget: Int?
    
    // Filter chips
    @State private var activeFilters: Set<String> = []
    @State private var sortByLastPlayed: Bool = false
    @State private var sortByLastAdded: Bool = false
    @State private var selectedGenres: Set<String> = []
    @State private var showGenrePicker: Bool = false
    @State private var showOtherFilters: Bool = false
    @State private var r3CycleIndex: Int = 0
    @ObservedObject private var notificationHistory = NotificationHistoryManager.shared
    @State private var showNotificationPopover: Bool = false
    @State private var showNotificationCenterSheet: Bool = false
    @State private var showBoxArtDownloadSheet: Bool = false
    @State private var showHelpSheet: Bool = false
    @State private var isDownloading = false
    @State private var downloadProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentDownloadGameName: String? = nil
    @State private var carouselBoxArtURLs: [URL] = []
    @State private var marqueeOffset: CGFloat = 0
    private enum ViewMode: String { case grid, list, tv }
    private var previousViewMode: ViewMode { get { _previousViewMode } set { _previousViewMode = newValue } }
    @State private var _previousViewMode: ViewMode = .grid

    @State private var lastSelectedFilterID: String? = nil
    @State private var isScrolling = false
    @State private var scrollMonitor: Any?
    @State private var scrollDebounceTimer: Timer?
    @State private var keyMonitor: Any?

    // When searching, the system filter is honored only when a specific system is
    // selected (so clicking a system in the sidebar during search narrows results
    // to that system's matching games). Otherwise all systems are matched.
    private var effectiveFilter: LibraryFilter {
        searchText.isEmpty ? filter : (filter.isSystemView ? filter : .all)
    }

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
            Color.clear
                .frame(height: 0)
                .onChange(of: continuousZoom) { _, newValue in
                    AppSettings.setDouble("gridZoomLevel", value: newValue)
                }
            
            filterChips
            
            if !activeFilters.isEmpty || !selectedGenres.isEmpty || !searchText.isEmpty {
                filterStatusStrip
            }

            if raService.isMatchingAll {
                HStack(spacing: 12) {
                    BouncingProgressBar()
                        .frame(width: 240)
                    if raService.isImportingRACache {
                        let format = loc.localized("retroAchievements.importingCacheProgress")
                        Text(format
                            .replacingOccurrences(of: "{0}", with: "\(raService.importRACacheStep)")
                            .replacingOccurrences(of: "{1}", with: "\(raService.importRACacheTotal)"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        let format = loc.localized("retroAchievements.matchedOfTotal")
                        Text(format
                            .replacingOccurrences(of: "{0}", with: "\(raService.matchedAllCount)")
                            .replacingOccurrences(of: "{1}", with: "\(raService.matchedAllTotal)"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
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
                    } else {
                        listView
                    }
                }
.transition(.opacity.combined(with: .scale(scale: 0.97)))
}
.modifier(GamepadNavReceiver(
    onLaunch: { [self] in if let rom = selectedROM { Task { await launchGame(rom) } } },
    onFocusSearch: { [self] in searchFocused.wrappedValue = true },
    onNavigateUp: { [self] in handleGamepadNavUp(columnCount: viewMode == .grid ? columnCount : 1, totalCount: viewModel.displayedROMs.count) },
    onNavigateDown: { [self] in handleGamepadNavDown(columnCount: viewMode == .grid ? columnCount : 1, totalCount: viewModel.displayedROMs.count) },
    onNavigateLeft: { [self] in handleGamepadNavLeft() },
    onNavigateRight: { [self] in handleGamepadNavRight(totalCount: viewModel.displayedROMs.count) },
    onToggleViewMode: { [self] in viewMode = viewMode == .grid ? .list : .grid },
    onCycleSortOrder: { [self] in handleGamepadCycleSort() },
    onShowContextMenu: { [self] in handleGamepadContextMenu() },
    onShowNotifications: { [self] in showNotificationPopover = true }
))
.highPriorityGesture(
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
.onChange(of: viewModel.displayedROMs.count) { _, newCount in
    gamepadNav.contentItemCount = newCount
    gamepadNav.clampCurrentIndex()
}
.onAppear {
    gamepadNav.contentItemCount = viewModel.displayedROMs.count
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
        .sheet(item: $gameToDelete) { rom in
            DeleteConfirmationView(
                rom: rom,
                confirmDeleteTap: $confirmDeleteTap,
                onDelete: {
                    deleteGameAndROM(rom)
                    gameToDelete = nil
                },
                onHide: {
                    hideGame(rom)
                    gameToDelete = nil
                },
                onCancel: {
                    gameToDelete = nil
                }
            )
            .onDisappear {
                confirmDeleteTap = false
            }
            .gamepadDismissable { gameToDelete = nil }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Spacer()
            }
            ToolbarItem(placement: .primaryAction) {
            Button { pickFolder() } label: {
                Label(loc.localized("toolbar.addROMFolder"), systemImage: "folder.badge.plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help(loc.localized("toolbar.addROMFolder"))
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
                                       updateColumnCountFromZoom()
                                   }
                               }
                           })
.frame(width: 160)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(continuousZoom == 1.0 && ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
                    Text("\(Int(continuousZoom * 100))%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .frame(width: 36)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                AccentSegmentedControl(
                    selection: $viewMode,
                    options: [(ViewMode.grid, "square.grid.2x2"), (ViewMode.list, "list.bullet"), (ViewMode.tv, "tv")],
                    accentColor: ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .blue
                )
                .frame(width: 120)
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
                            showBoxArtDownloadSheet = true
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
            } label: {
 HStack(spacing: 4) {
 let hasControllers = controllerService.connectedControllers.contains(where: { !$0.isKeyboard })
 if hasControllers {
 Image(systemName: "keyboard")
 Image(systemName: "gamecontroller")
 } else {
 Image(systemName: "keyboard")
 }
                }
            }
        .help(loc.localized("toolbar.inputDevice"))
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
                    .gamepadDismissable { showNotificationPopover = false }
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
            .popover(isPresented: $showHelpSheet, arrowEdge: .bottom) {
                HelpSheetView()
                    .gamepadDismissable { showHelpSheet = false }
            }
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
    .sheet(isPresented: $showBoxArtDownloadSheet) {
        BoxArtDownloadSheet(
            isPresented: $showBoxArtDownloadSheet,
            onDownload: { reDownload in
                triggerBatchDownload(reDownload: reDownload)
            }
        )
    }
    .sheet(item: $manualBoxArtSearchROM) { rom in
        BoxArtPickerView(rom: rom)
            .gamepadDismissable { manualBoxArtSearchROM = nil }
    }
    .sheet(isPresented: $showNotificationCenterSheet) {
        NotificationCenterSheetView()
            .gamepadDismissable { showNotificationCenterSheet = false }
    }
    .sheet(item: $systemPickerItem, onDismiss: { systemPickerItem = nil }) { item in
        SystemPickerView(roms: item.roms, library: library) {
            systemPickerItem = nil
        }
        .gamepadDismissable { systemPickerItem = nil }
    }
    .onAppear {
            // Recompute columns from saved zoom level
            updateColumnCountFromZoom()
            sortByLastPlayed = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
            sortByLastAdded = AppSettings.getBool("sortByLastAdded", defaultValue: false)
            
            // Initialize view mode from settings
            if let savedMode = AppSettings.getString("gridViewMode"),
               let parsed = ViewMode(rawValue: savedMode),
               parsed != .tv {
                viewMode = parsed
            }
            
            // Sync view model with restored sort settings
viewModel.updateFilters(
                filter: effectiveFilter,
                searchText: searchText,
                activeFilters: activeFilters,
                sortByLastPlayed: sortByLastPlayed,
                sortByLastAdded: sortByLastAdded,
                selectedGenres: selectedGenres
            )

            // Contextually resolve local boxarts for the current view
            handleFilterChange(effectiveFilter)
            
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
                } else if mode == "tv" {
                    viewMode = .tv
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sortChanged)) { _ in
            sortByLastPlayed = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
            sortByLastAdded = AppSettings.getBool("sortByLastAdded", defaultValue: false)
            viewModel.updateFilters(
                filter: effectiveFilter,
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
                    filter: effectiveFilter,
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
            updateColumnCountFromZoom()
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
                filter: effectiveFilter,
                searchText: newValue,
                activeFilters: activeFilters,
                sortByLastPlayed: sortByLastPlayed,
                sortByLastAdded: sortByLastAdded,
                selectedGenres: selectedGenres
            )
        }
        .onChange(of: viewMode) { _, newMode in
            if newMode != .tv { _previousViewMode = newMode }
            AppSettings.set("gridViewMode", value: newMode.rawValue)
            gamepadNav.columnCount = newMode == .list ? 1 : columnCount
            if newMode == .tv {
                TVModeSettingsManager.shared.enter()
                let restore = previousViewMode
                DispatchQueue.main.async { viewMode = restore }
            }
        }
        .onDisappear {
            // Save zoom level persistently (backup)
            AppSettings.setDouble("gridZoomLevel", value: continuousZoom)
        }
        // Refresh grid when box art is updated from elsewhere (e.g., game info page)
        // We do NOT clear the entire ImageCache or trigger full-grid reloads.
        // Each GameCardView's .task(id: rom.id) will automatically reload
        // when its specific hasBoxArt changes.
        // MARK: - Keyboard Shortcuts
        // Cmd+F focuses search field
        .background {
            Button("") { searchFocused.wrappedValue = true }
                .keyboardShortcut(KeyEquivalent("f"), modifiers: .command)
                .hidden()
        }
        // Note: Delete key handling via onKeyPress requires macOS 14+
        // For macOS 13, users can use context menu or confirm delete action
    }

    // Whether the current filter is a system view (used to enable/disable box art style).
    private var isSystemView: Bool {
        if case .system = filter { return true }
        return false
    }

    private func updateColumnCount(width: CGFloat) {
        let cardWidth: CGFloat = 80 + (continuousZoom * 200)
        let spacing: CGFloat = max(6, 16 - (continuousZoom * 8))
        let availableWidth = width - (gridPadding.leading + gridPadding.trailing)
        let computedColumns = max(1, min(8, Int((availableWidth + spacing) / (cardWidth + spacing))))
        columnCount = computedColumns
        gamepadNav.columnCount = computedColumns
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
        GridCollectionViewRepresentable(
            roms: $viewModel.displayedROMs,
            selection: $selectedROMs,
            primarySelection: Binding(
                get: { selectedROM },
                set: { selectedROM = $0 }
            ),
            zoomLevel: continuousZoom,
            filter: filter,
            raEnabled: raService.isEnabled,
            gridPadding: gridPadding,
            onDoubleClick: { rom in
                Task { await launchGame(rom) }
            },
            onTap: { [self] rom, index in
                handleTap(on: rom, at: index)
            },
            contextMenuProvider: { [self] rom in contextMenu(for: rom) },
            library: library,
            categoryManager: categoryManager
        )
        .onChange(of: gamepadNav.contentIndex) { _, newIndex in
            guard gamepadNav.activeZone == .content else { return }
            gridScrollTarget = newIndex
        }
        .onChange(of: gridScrollTarget) { _, newIndex in
            guard newIndex != nil else { return }
            gridScrollTarget = nil
        }
    }
    
    // MARK: - Gamepad Navigation Handlers

    private func handleGamepadNavUp(columnCount: Int, totalCount: Int) {
        guard gamepadNav.activeZone == .content else { return }
        if gamepadNav.contentIndex >= columnCount {
            gamepadNav.contentIndex -= columnCount
        }
    }

    private func handleGamepadNavDown(columnCount: Int, totalCount: Int) {
        guard gamepadNav.activeZone == .content else { return }
        let newIndex = gamepadNav.contentIndex + columnCount
        guard newIndex < totalCount else { return }
        gamepadNav.contentIndex = newIndex
    }

    private func handleGamepadNavLeft() {
        guard gamepadNav.activeZone == .content else { return }
        if gamepadNav.contentIndex > 0 {
            gamepadNav.contentIndex -= 1
        }
    }

    private func handleGamepadNavRight(totalCount: Int) {
        guard gamepadNav.activeZone == .content else { return }
        if gamepadNav.contentIndex < totalCount - 1 {
            gamepadNav.contentIndex += 1
        }
    }

    private func handleGamepadCycleSort() {
        let genres = GenreManager.shared.getAllDisplayGenres(from: library.roms)

        let allSteps: [GamepadCycleStep] = [
            GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: false, filter: nil, genre: nil),
            GamepadCycleStep(sortByLastPlayed: true,  sortByLastAdded: false, filter: nil, genre: nil),
            GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: true,  filter: nil, genre: nil),
            GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: false, filter: .noBoxArt, genre: nil),
            GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: false, filter: .neverPlayed, genre: nil),
            GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: false, filter: .unscanned, genre: nil),
            GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: false, filter: .multiplayer, genre: nil),
        ] + genres.map { GamepadCycleStep(sortByLastPlayed: false, sortByLastAdded: false, filter: nil, genre: $0) }

        let currentStep = GamepadCycleStep(
            sortByLastPlayed: sortByLastPlayed,
            sortByLastAdded: sortByLastAdded,
            filter: activeFilters.compactMap { GameFilterOption(rawValue: $0) }.first,
            genre: selectedGenres.count == 1 ? selectedGenres.first : nil
        )

        let currentIdx: Int = allSteps.firstIndex(of: currentStep) ?? 0
        let next = (currentIdx + 1) % allSteps.count
        r3CycleIndex = next
        applyCycleStep(allSteps[next])
    }

    private func applyCycleStep(_ step: GamepadCycleStep) {
        sortByLastPlayed = step.sortByLastPlayed
        sortByLastAdded = step.sortByLastAdded
        activeFilters.removeAll()
        if let f = step.filter { activeFilters.insert(f.rawValue) }
        selectedGenres.removeAll()
        if let g = step.genre { selectedGenres.insert(g) }

        AppSettings.setBool("sortByLastPlayed", value: sortByLastPlayed)
        AppSettings.setBool("sortByLastAdded", value: sortByLastAdded)
        viewModel.updateFilters(
            filter: filter,
            searchText: searchText,
            activeFilters: activeFilters,
            sortByLastPlayed: sortByLastPlayed,
            sortByLastAdded: sortByLastAdded,
            selectedGenres: selectedGenres
        )
    }

    private func handleGamepadContextMenu() {
        if gamepadNav.activeZone == .sidebar {
            NotificationCenter.default.post(name: .gamepadSidebarContextMenu, object: nil)
        } else if gamepadNav.activeZone == .content {
            handleGamepadContentContextMenu()
        }
    }

    private func handleGamepadContentContextMenu() {
        guard gamepadNav.contentIndex >= 0,
              gamepadNav.contentIndex < viewModel.displayedROMs.count else { return }
        let rom = viewModel.displayedROMs[gamepadNav.contentIndex]
        selectedROM = rom
        let targetIDs = Array(selectedROMs.union([rom.id]))
        let targetIDsSet = Set(targetIDs)
        var items: [GamepadContextMenuItem] = [
            .init(title: loc.localized("contextMenu.seeGameInfo")) { [self] in openWindow(id: "game-info", value: rom.id) },
            .init(title: loc.localized("contextMenu.launchGame")) { [self] in Task { await launchGame(rom) } },
            .separator
        ]
        for category in categoryManager.categories {
            let isInCategory = category.gameIDs.contains(rom.id)
            if isInCategory {
                items.append(.init(title: "✓ \(category.name)") { [self] in
                    categoryManager.removeGamesFromCategory(gameIDs: [rom.id], categoryID: category.id)
                })
            } else {
                items.append(.init(title: category.name) { [self] in
                    categoryManager.addGamesToCategory(gameIDs: [rom.id], categoryID: category.id)
                })
            }
        }
        let categoriesForTargetGames = categoryManager.categories.filter { category in
            category.gameIDs.contains { targetIDsSet.contains($0) }
        }
        if !categoriesForTargetGames.isEmpty {
            items.append(.init(title: loc.localized("contextMenu.removeFromAllCategories")) { [self] in
                for category in categoriesForTargetGames {
                    categoryManager.removeGamesFromCategory(gameIDs: targetIDs, categoryID: category.id)
                }
            })
        }
        items.append(.separator)
        items.append(.init(title: loc.localized("contextMenu.moveToSystem")) { [self] in
            let targetROMs = library.roms.filter { targetIDsSet.contains($0.id) }
            systemPickerItem = SystemPickerItem(roms: targetROMs)
        })
        items.append(.separator)
        let favTitle = rom.isFavorite ? loc.localized("contextMenu.removeFromFavorites") : loc.localized("contextMenu.addToFavorites")
        items.append(.init(title: favTitle) { [self] in
            var updated = rom
            updated.isFavorite.toggle()
            library.updateROM(updated)
        })
        items.append(.init(title: loc.localized("contextMenu.renameGame")) { [self] in
            renameText = rom.customName ?? rom.metadata?.title ?? rom.name
            renamingROM = rom
        })
        items.append(.init(title: loc.localized("contextMenu.getBoxArt")) { manualBoxArtSearchROM = rom })
        items.append(.init(title: loc.localized("contextMenu.revealInFinder")) { NSWorkspace.shared.selectFile(rom.path.path, inFileViewerRootedAtPath: "") })
        items.append(.separator)
        if rom.isHidden {
            items.append(.init(title: loc.localized("contextMenu.unhideGame")) { [self] in unhideGame(rom) })
        } else {
            items.append(.init(title: loc.localized("contextMenu.hideGame")) { [self] in hideGame(rom) })
            items.append(.init(title: loc.localized("contextMenu.deleteGame"), isDestructive: true) { showDeleteSheet(for: rom) })
        }
        GamepadContextMenuState.shared.show(items)
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
        ScrollViewReader { proxy in
        List(selection: $selectedROM) {
            ForEach(Array(viewModel.displayedROMs.enumerated()), id: \.element.id) { index, rom in
                let isSelected = selectedROMs.contains(rom.id) || selectedROM?.id == rom.id
                let isGamepadFocused = gamepadNav.activeZone == .content && gamepadNav.contentIndex == index
                GameListRowView(rom: rom, isSelected: isSelected, isEvenRow: index.isMultiple(of: 2), zoomLevel: zoomLevel, filter: filter, raEnabled: raService.isEnabled, contextMenu: { contextMenu(for: rom) }, isScrolling: isScrolling)
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
        .overlay {
            if isGamepadFocused {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .id(rom.id)
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
        .onAppear {
            gamepadNav.columnCount = 1
            gamepadNav.contentItemCount = viewModel.displayedROMs.count
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
                if !isScrolling { isScrolling = true }
                scrollDebounceTimer?.invalidate()
                scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    isScrolling = false
                }
                return event
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if (event.keyCode == 36 || event.keyCode == 76),
                   !searchFocused.wrappedValue,
                   let rom = selectedROM {
                    Task { await launchGame(rom) }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            scrollDebounceTimer?.invalidate()
        }
        .onChange(of: gamepadNav.contentIndex) { _, newIndex in
            guard gamepadNav.activeZone == .content, viewMode == .list else { return }
            guard newIndex >= 0, newIndex < viewModel.displayedROMs.count else { return }
            let rom = viewModel.displayedROMs[newIndex]
            selectedROM = rom
            withAnimation {
                proxy.scrollTo(rom.id, anchor: .center)
            }
        }
        .onChange(of: viewModel.displayedROMs.count) { _, newCount in
            gamepadNav.contentItemCount = newCount
            gamepadNav.clampCurrentIndex()
        }
        }
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
    
    private func updateColumnCountFromZoom() {
        let cardWidth: CGFloat = 80 + (continuousZoom * 200)
        let spacing: CGFloat = max(6, 16 - (continuousZoom * 8))
        let cols = max(1, min(8, Int((800 + spacing) / (cardWidth + spacing))))
        columnCount = cols
        gamepadNav.columnCount = cols
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
                .gamepadDismissable { manualBoxArtSearchROM = nil }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                emptyStateAppeared = true
            }
        }
    }
    
    private var currentSystem: SystemInfo? {
        if case .system(let system) = filter { return system }
        return nil
    }

    private var emptyStateIcon: String {
        if let system = currentSystem {
            return system.iconName
        } else if !activeFilters.isEmpty && searchText.isEmpty {
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
        if let system = currentSystem {
            let name = system.sidebarDisplayName
            if !searchText.isEmpty {
                return loc.localized("library.nothingMatchingInSystem")
                    .replacingOccurrences(of: "{0}", with: name)
                    .replacingOccurrences(of: "{1}", with: searchText)
            }
            return loc.localized("library.noGamesInSystem").replacingOccurrences(of: "{0}", with: name)
        } else if !activeFilters.isEmpty && searchText.isEmpty {
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
        if currentSystem != nil {
            return loc.localized("library.tryOtherSystems")
        } else if !activeFilters.isEmpty && searchText.isEmpty {
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
                                GameCategoryIconView(category: category, size: 18)
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
                        showDeleteSheet(for: rom)
                    } label: {
                        Label(loc.localized("contextMenu.deleteGame"), systemImage: "trash")
                    }
                }
            }
        )
    }

    // MARK: - Delete/Hide Game Actions

    private func showDeleteSheet(for rom: ROM) {
        gameToDelete = rom
    }

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
        if let innerPath = rom.innerROMPath,
           ArchiveExtractor.archiveExtensions.contains(rom.path.pathExtension.lowercased()) {
            deleteROMInArchive(rom, innerPath: innerPath)
        } else {
            deleteRegularFile(rom)
        }
    }

    private func deleteRegularFile(_ rom: ROM) {
        var trashURL: URL?
        var referencedTrashPairs: [(original: URL, trash: URL)] = []

        let containerExts: Set<String> = ["cue", "m3u", "gdi", "ccd", "toc", "mds"]
        let isContainer = containerExts.contains(rom.path.pathExtension.lowercased())
        let referencedFiles = isContainer ? ROMIdentifier.getReferencedFiles(in: rom.path) : []

        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: rom.path, resultingItemURL: &resultingURL)
            trashURL = resultingURL as? URL
            LoggerService.info(category: "LibraryGridView", "ROM file moved to trash: \(rom.path.lastPathComponent)")
        } catch {
            LoggerService.warning(category: "LibraryGridView", "Failed to move ROM to trash: \(error.localizedDescription). Removing from library anyway.")
        }

        for refURL in referencedFiles {
            guard FileManager.default.fileExists(atPath: refURL.path) else { continue }
            do {
                var refResult: NSURL?
                try FileManager.default.trashItem(at: refURL, resultingItemURL: &refResult)
                if let trashRefURL = refResult as URL? {
                    referencedTrashPairs.append((refURL, trashRefURL))
                    LoggerService.info(category: "LibraryGridView", "Referenced file moved to trash: \(refURL.lastPathComponent)")
                }
            } catch {
                LoggerService.warning(category: "LibraryGridView", "Failed to trash referenced file \(refURL.lastPathComponent): \(error.localizedDescription)")
            }
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
            actionPayload: TrashActionPayload(
                romID: rom.id,
                originalPath: rom.path.path,
                romJSON: romJSON,
                referencedOriginalPaths: referencedTrashPairs.map(\.original.path)
            )
        )

        if let trashURL = trashURL {
            AppSettings.set("pendingTrashRestore_\(rom.id.uuidString)", value: trashURL.path)
        }
        for (index, pair) in referencedTrashPairs.enumerated() {
            AppSettings.set("pendingTrashRestore_\(rom.id.uuidString)_ref_\(index)", value: pair.trash.path)
        }
    }

    private func deleteROMInArchive(_ rom: ROM, innerPath: String) {
        let otherLibraryROMs = library.roms.filter {
            $0.path.path == rom.path.path && $0.id != rom.id
        }

        if otherLibraryROMs.isEmpty {
            // Cases 1 & 2: No other library games in this archive — trash the whole archive
            deleteRegularFile(rom)
        } else {
            // Case 3: Other library ROMs share this archive — only remove the inner file
            do {
                try ArchiveExtractor.removeItem(fromZipAt: rom.path, itemPath: innerPath)
                removeSingleROMFromLibrary(rom)
                ArchiveExtractor.shared.removeCacheFor(archiveURL: rom.path)
                LoggerService.info(category: "LibraryGridView", "Removed '\(innerPath)' from archive: \(rom.path.lastPathComponent)")
            } catch {
                LoggerService.error(category: "LibraryGridView", "Failed to remove file from archive: \(error.localizedDescription)")
                return
            }

            NotificationHistoryManager.shared.post(
                icon: "trash",
                title: loc.localized("pill.gameTrashed"),
                subtitle: rom.displayName,
                autoDismissDelay: 5
            )
        }
    }

    private func removeROMFromLibrary(_ rom: ROM) {
        library.roms.removeAll { $0.id == rom.id }
        LibraryMetadataStore.shared.deleteMetadata(for: rom)
        let repo = ROMRepository(context: SwiftDataContainer.shared.mainContext)
        repo.deleteROMsByPath([rom.path.path])
        library.updateCounts()

        if selectedROM?.id == rom.id {
            selectedROM = nil
        }
    }

    private func removeSingleROMFromLibrary(_ rom: ROM) {
        library.roms.removeAll { $0.id == rom.id }
        LibraryMetadataStore.shared.deleteMetadata(for: rom)
        let repo = ROMRepository(context: SwiftDataContainer.shared.mainContext)
        repo.deleteROMs(ids: [rom.id])
        library.updateCounts()

        if selectedROM?.id == rom.id {
            selectedROM = nil
        }
    }

    // MARK: - Search & Filters

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
                        filter: effectiveFilter,
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
                        filter: effectiveFilter,
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

                ForEach(GameFilterOption.primaryFilters) { option in
                    FilterChipView(
                        option: option,
                        isActive: activeFilters.contains(option.rawValue),
                        action: { toggleFilter(option) }
                    )
                }

                let otherActiveCount = GameFilterOption.otherFilters.filter { activeFilters.contains($0.rawValue) }.count
                Button {
                    showOtherFilters.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: otherActiveCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 10, weight: .medium))
                        Text(loc.localized("library.otherFilters"))
                            .font(.system(size: 11, weight: .medium))
                        if otherActiveCount > 0 {
                            Text("(\(otherActiveCount))")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(otherActiveCount > 0 ? AppColors.textOnAccent(colorScheme) : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 30)
                    .background(Capsule().fill(otherActiveCount > 0 ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOtherFilters) {
                    OtherFiltersPopover(
                        activeFilters: $activeFilters,
                        onToggle: { toggleFilter($0) }
                    )
                    .gamepadDismissable { showOtherFilters = false }
                }

                // Genre filter chip
                Button {
                    showGenrePicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedGenres.isEmpty ? "tag" : "tag.fill")
                            .font(.system(size: 10, weight: .medium))
                        if selectedGenres.count == 1, let genre = selectedGenres.first {
                            Text(genre)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        } else {
                            Text(loc.localized("library.genre"))
                                .font(.system(size: 11, weight: .medium))
                            if selectedGenres.count > 1 {
                                Text("(\(selectedGenres.count))")
                                    .font(.system(size: 10))
                            }
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
                        onChange: {
                            viewModel.updateFilters(
                                filter: effectiveFilter,
                                searchText: searchText,
                                activeFilters: activeFilters,
                                sortByLastPlayed: sortByLastPlayed,
                                sortByLastAdded: sortByLastAdded,
                                selectedGenres: selectedGenres
                            )
                        }
                    )
                    .gamepadDismissable { showGenrePicker = false }
                }

                if !activeFilters.isEmpty || !selectedGenres.isEmpty {
                    Button {
                        activeFilters.removeAll()
                        selectedGenres.removeAll()
                        viewModel.updateFilters(
                            filter: effectiveFilter,
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
    
    private var filterStatusStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.caption)
            Text("Filtering: " + activeFilterDisplayText)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text("\(viewModel.displayedROMs.count) game\(viewModel.displayedROMs.count == 1 ? "" : "s")")
                .font(.caption)
        }
        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
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

            // Capture the filter id we *just* switched to. If the user switches again
            // before the background lookup completes, we'll discard the result — both
            // because those ROMs are no longer visible AND because the write-back to
            // library.roms would otherwise re-publish on $roms and re-trigger a
            // filter storm during navigation.
            let targetFilterID = viewModel.currentFilterID
            let service = BoxArtService.shared
            Task.detached(priority: .background) {
                let resolved = service.resolveLocalBoxArtBatch(for: missingArt)
                guard !resolved.isEmpty else { return }

                // Hop back to MainActor briefly just to read currentFilterID; if the
                // user has already moved on, drop the work without touching anything.
                let stillRelevant = await MainActor.run { viewModel.currentFilterID == targetFilterID }
                guard stillRelevant else { return }

                // We deliberately avoid `library.saveROMsToDatabase` here: this runs
                // mid-navigation and forces a full FetchDescriptor over the entire
                // library plus per-ROM XML writes on MainActor. The next time we land
                // on this system, the in-memory `roms` are already correct (because
                // we still update them in-memory below); persistence coalesces on
                // the next regular save path (e.g. ROMLibrary finalizers, scanners,
                // or settings persistence).
                await MainActor.run {
                    for rom in resolved {
                        library.updateROM(rom, persist: false, silent: true)
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
    @State private var images: [URL: NSImage] = [:]
    @State private var timer: Timer?
    @State private var appeared = false

    private let itemWidth: CGFloat = 150
    private let spacing: CGFloat = 14
    private let stride: CGFloat = 164
    private let speed: CGFloat = 1.4
    private let slotCount = 6
    private let visibleSlots = 3

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
            loadVisibleImages()
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
            if let url = slots[i].url, let nsImage = images[url] {
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

    private func loadVisibleImages() {
        for slot in slots {
            guard let url = slot.url, images[url] == nil else { continue }
            Task {
                if let img = await ImageCache.shared.thumbnail(for: url, preferredSize: .tiny) {
                    images[url] = img
                }
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
        loadVisibleImages()
    }

    private func tick() {
        offset += speed
        for i in 0..<slotCount {
            let xPos = CGFloat(slots[i].vi) * stride - offset
            if xPos < leftKillX {
                let maxVI = slots.map(\.vi).max() ?? 0
                slots[i].vi = maxVI + 1
                slots[i].url = pickRandom()
                if let url = slots[i].url, images[url] == nil {
                    Task {
                        if let img = await ImageCache.shared.thumbnail(for: url, preferredSize: .tiny) {
                            images[url] = img
                        }
                    }
                }
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

// MARK: - Delete Confirmation View

private struct DeleteConfirmationView: View {
    let rom: ROM
    @Binding var confirmDeleteTap: Bool
    let onDelete: () -> Void
    let onHide: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var boxArtImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let img = boxArtImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(placeholderGradient)
                        .frame(height: 120)
                        .overlay(
                            Image(systemName: systemIcon)
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Text(rom.displayName)
                .font(.title3.weight(.semibold))
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let sysID = rom.systemID, sysID != "unknown" {
                Text(sysID.uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.textMuted(colorScheme))
                    .padding(.top, 2)
            }

            Text(explanation)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 32)
                .padding(.top, 12)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                Button(role: .destructive) {
                    if confirmDeleteTap {
                        onDelete()
                    } else {
                        confirmDeleteTap = true
                    }
                } label: {
                    Text(confirmDeleteTap ? loc.localized("settings.confirmDelete") : loc.localized("contextMenu.deleteGame"))
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(confirmDeleteTap ? .red : AppColors.brandAccent)
                .controlSize(.large)

                Button {
                    onHide()
                } label: {
                    Text("Hide from Library Only")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.textSecondary(colorScheme))
                .controlSize(.large)

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text(loc.localized("library.cancel"))
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.textSecondary(colorScheme))
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 320)
        .background(AppColors.windowBackground(colorScheme, tinted: false))
        .onAppear {
            var artPath = rom.boxArtLocalPath
            if !FileManager.default.fileExists(atPath: artPath.path) {
                if let resolved = BoxArtService.shared.resolveLocalBoxArt(for: rom) {
                    artPath = resolved
                }
            }
            if FileManager.default.fileExists(atPath: artPath.path) {
                // Off-main decode via ImageCache (uses the .medium thumbnail if
                // already generated, otherwise downsamples on a detached task).
                Task { @MainActor in
                    boxArtImage = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .medium)
                }
            }
        }
        .onDisappear {
            confirmDeleteTap = false
        }
    }

    private var explanation: String {
        if rom.innerROMPath != nil {
            return loc.localized("settings.deleteExplanationArchive")
        }
        return loc.localized("settings.deleteExplanationFile")
    }

    private var systemIcon: String {
        SystemDatabase.system(forID: rom.systemID ?? "")?.iconName ?? "gamecontroller"
    }

    private var placeholderGradient: LinearGradient {
        let hash = abs((rom.systemID ?? "x").hashValue)
        let palettes: [(Color, Color)] = [
            (Color(hue: 0.08, saturation: 0.55, brightness: 0.75), Color(hue: 0.06, saturation: 0.40, brightness: 0.55)),
            (Color(hue: 0.04, saturation: 0.50, brightness: 0.70), Color(hue: 0.03, saturation: 0.35, brightness: 0.50)),
            (Color(hue: 0.12, saturation: 0.50, brightness: 0.80), Color(hue: 0.10, saturation: 0.35, brightness: 0.60)),
        ]
        let colors = palettes[hash % palettes.count]
        return LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
}

private struct GamepadNavReceiver: ViewModifier {
    var onLaunch: () -> Void
    var onFocusSearch: () -> Void
    var onNavigateUp: () -> Void
    var onNavigateDown: () -> Void
    var onNavigateLeft: () -> Void
    var onNavigateRight: () -> Void
    var onToggleViewMode: () -> Void
    var onCycleSortOrder: () -> Void
    var onShowContextMenu: (() -> Void)?
    var onShowNotifications: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .gamepadLaunchGame)) { _ in onLaunch() }
            .onReceive(NotificationCenter.default.publisher(for: .gamepadFocusSearch)) { _ in onFocusSearch() }
            .onReceive(NotificationCenter.default.publisher(for: .gamepadNavigateUp)) { _ in onNavigateUp() }
            .onReceive(NotificationCenter.default.publisher(for: .gamepadNavigateDown)) { _ in onNavigateDown() }
            .onReceive(NotificationCenter.default.publisher(for: .gamepadNavigateLeft)) { _ in onNavigateLeft() }
            .onReceive(NotificationCenter.default.publisher(for: .gamepadNavigateRight)) { _ in onNavigateRight() }
            .onReceive(NotificationCenter.default.publisher(for: .gamepadToggleViewMode)) { _ in onToggleViewMode() }
              .onReceive(NotificationCenter.default.publisher(for: .gamepadCycleSortOrder)) { _ in onCycleSortOrder() }
              .onReceive(NotificationCenter.default.publisher(for: .gamepadShowContextMenu)) { _ in onShowContextMenu?() }
              .onReceive(NotificationCenter.default.publisher(for: .gamepadShowNotifications)) { _ in onShowNotifications?() }
      }
}

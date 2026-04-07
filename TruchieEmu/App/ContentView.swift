import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var libraryAutomation: LibraryAutomationCoordinator
    @EnvironmentObject var controllerService: ControllerService
    @StateObject private var metadataSync = MetadataSyncCoordinator.shared
    @ObservedObject var wizard = SetupWizardState.shared
    
    @State private var selectedFilter: LibraryFilter = .recent
    @State private var selectedROM: ROM? = nil
    @State private var showOnboarding = false
    @State private var searchText = ""
    @State private var showCreateCategorySheet = false
    @State private var editingCategory: GameCategory? = nil

    var body: some View {
        Group {
            if !library.hasCompletedOnboarding && !wizard.hasCompletedWizard {
                // Show the setup wizard for first-time users
                SetupWizardView(wizard: wizard)
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
            } else {
                mainInterface
            }
        }
    }

    private var mainInterface: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationSplitView {
                    SystemSidebarView(
                        selectedFilter: $selectedFilter,
                        showCreateCategorySheet: $showCreateCategorySheet,
                        editingCategory: $editingCategory
                    )
                } detail: {
                    LibraryGridView(
                        showCreateCategorySheet: $showCreateCategorySheet,
                        filter: selectedFilter,
                        selectedROM: $selectedROM,
                        searchText: $searchText
                    )
                    .navigationTitle(navigationTitle)
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar(removing: .sidebarToggle)
                .sheet(isPresented: $showCreateCategorySheet) {
                    CreateCategorySheet()
                }
                .sheet(item: $editingCategory) { category in
                    EditCategorySheet(category: category)
                }

                // Status bar for library automation or metadata sync
                if let activeStatus = activeBackgroundTask {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: activeStatus.progress)
                            .progressViewStyle(.linear)
                        Text(activeStatus.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
            }
            
            // Confetti overlay for celebration moments
            ConfettiOverlay()
        }
        .sheet(item: $coreManager.pendingDownload) { pending in
            CoreDownloadSheet(pending: pending)
        }
        .task {
            // Initialize the ROM library asynchronously after the view appears.
            // This defers expensive database loads to after the UI is visible.
            library.initializeIfNeeded()
            
            // Wait for scanning to finish before preloading.
            while library.isScanning {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
            
            // Smart preload strategy:
            // 1. Preload the CURRENTLY selected filter's ROMs first
            // 2. Then preload remaining systems ordered by smallest ROM count first
            await preloadSmartInitialCache()
        }
        .onAppear {
            // After wizard completion, start on All Games until at least one game has been played.
            let hasPlayedGames = library.roms.contains { $0.lastPlayed != nil || $0.timesPlayed > 0 }
            if !hasPlayedGames {
                selectedFilter = .all
            }
        }
        // Set ideal window size so the window doesn't start stretched larger than needed
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 650, idealHeight: 750)
    }

    /// Shows whichever background task is currently active (library automation takes precedence).
    private var activeBackgroundTask: (progress: Double, statusLine: String)? {
        if libraryAutomation.isActive {
            return (libraryAutomation.progress, libraryAutomation.statusLine)
        }
        if metadataSync.isActive {
            return (metadataSync.progress, metadataSync.statusLine)
        }
        return nil
    }

    private var navigationTitle: String {
        switch selectedFilter {
        case .all: return "All Games"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .system(let sys): return sys.name
        case .category(let id):
            if let category = categoryManager.categories.first(where: { $0.id == id }) {
                return category.name
            }
            return "Category"
        case .hidden: return "Hidden Games"
        case .mameNonGames: return "Hidden MAME Files"
        }
    }
    
    /// Smart preloading strategy:
    /// 1. Preload the currently visible filter's ROMs first so the current view is instant
    /// 2. Then preload remaining systems ordered by smallest ROM count first (quick wins)
    private func preloadSmartInitialCache() async {
        // Step 1: Preload the current filter's ROMs
        let currentROMs: [ROM]
        switch selectedFilter {
        case .all:
            currentROMs = library.roms
        case .favorites:
            currentROMs = library.roms.filter { $0.isFavorite }
        case .recent:
            currentROMs = library.roms.filter { $0.lastPlayed != nil }
        case .system(let sys):
            let systemIDs = SystemDatabase.allInternalIDs(forDisplayID: sys.id)
            currentROMs = library.roms.filter { systemIDs.contains($0.systemID ?? "") }
        case .category(let id):
            currentROMs = categoryManager.gamesInCategory(categoryID: id, fromROMs: library.roms)
        case .hidden:
            currentROMs = library.roms.filter { $0.isHidden }
        case .mameNonGames:
            currentROMs = library.roms.filter { rom in
                rom.systemID == "mame" && rom.mameRomType != "game"
            }
        }
        
        let currentWithArt = currentROMs.filter { $0.boxArtPath != nil }
        if !currentWithArt.isEmpty {
            LoggerService.info(category: "ContentView", "Preloading current view: \(currentWithArt.count) ROMs")
            await BoxArtPreloaderService.shared.preloadBoxArt(for: currentWithArt)
        }
        
        // Step 2: Preload remaining systems ordered by smallest count first
        if case .system(let currentSys) = selectedFilter {
            let currentIDs = SystemDatabase.allInternalIDs(forDisplayID: currentSys.id)
            let otherSystems = library.roms.filter { !currentIDs.contains($0.systemID ?? "") }
            
            // Group remaining ROMs by system and count them
            var systemGroups: [String: [ROM]] = [:]
            for rom in otherSystems where rom.boxArtPath != nil {
                systemGroups[rom.systemID ?? "unknown", default: []].append(rom)
            }
            
            // Sort by smallest first, then preload each
            let sortedGroups = systemGroups.sorted { $0.value.count < $1.value.count }
            for (systemID, roms) in sortedGroups {
                LoggerService.info(category: "ContentView", "Preloading system \(systemID): \(roms.count) ROMs")
                await BoxArtPreloaderService.shared.preloadBoxArt(for: roms)
            }
        } else if case .all = selectedFilter {
            // For All Games view, also preload by smallest system first
            var systemGroups: [String: [ROM]] = [:]
            for rom in library.roms where rom.boxArtPath != nil {
                systemGroups[rom.systemID ?? "unknown", default: []].append(rom)
            }
            
            let sortedGroups = systemGroups.sorted { $0.value.count < $1.value.count }
            for (systemID, roms) in sortedGroups {
                LoggerService.info(category: "ContentView", "Preloading system \(systemID): \(roms.count) ROMs")
                await BoxArtPreloaderService.shared.preloadBoxArt(for: roms)
            }
        }
        
        // Also enforce disk cache limits on launch
        _ = await BoxArtPreloaderService.shared.enforceDiskCacheLimit()
        LoggerService.info(category: "ContentView", "Smart preloading complete")
    }
}

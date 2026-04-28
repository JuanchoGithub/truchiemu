import Foundation
import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    // Dependencies
    private let library: ROMLibrary
    private let categoryManager: CategoryManager
    
    // State
    @Published var displayedROMs: [ROM] = []
    @Published var isProcessing: Bool = false
    
    // Filter/Sort State
    var currentFilter: LibraryFilter = .all
    var currentSearchText: String = ""
    var activeFilters: Set<String> = []
var sortByLastPlayed: Bool = false
    var sortByLastAdded: Bool = false
    var selectedGenres: Set<String> = []

    private var cancellables = Set<AnyCancellable>()
    
    init(
        library: ROMLibrary,
        categoryManager: CategoryManager,
        initialFilter: LibraryFilter = .all,
        initialSearchText: String = "",
        initialActiveFilters: Set<String> = [],
        initialSortByLastPlayed: Bool = false,
        initialSortByLastAdded: Bool = false
    ) {
        self.library = library
        self.categoryManager = categoryManager
        self.currentFilter = initialFilter
        self.currentSearchText = initialSearchText
        self.activeFilters = initialActiveFilters
        self.sortByLastPlayed = initialSortByLastPlayed
        self.sortByLastAdded = initialSortByLastAdded
        
        // Observe the library for changes
        library.$roms
            .combineLatest(library.$lastChangeDate)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
            
        // Observe category changes
        categoryManager.objectWillChange
            .sink { [weak self] in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
func updateFilters(filter: LibraryFilter, searchText: String, activeFilters: Set<String>, sortByLastPlayed: Bool, sortByLastAdded: Bool, selectedGenres: Set<String> = []) {
        self.currentFilter = filter
        self.currentSearchText = searchText
        self.activeFilters = activeFilters
        self.sortByLastPlayed = sortByLastPlayed
        self.sortByLastAdded = sortByLastAdded
        self.selectedGenres = selectedGenres

        refreshData()
    }
    
    private func refreshData() {
        Task {
            // Wait until not processing
            while isProcessing {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
            }
            
            // Re-check because another task might have started while we were sleeping
            guard !isProcessing else { return }
            
            isProcessing = true
            
// Capture current state
        let filter = currentFilter
        let searchText = currentSearchText
        let activeFilters = activeFilters
        let sortByLastPlayed = sortByLastPlayed
        let sortByLastAdded = sortByLastAdded
        let selectedGenres = selectedGenres
        let allRoms = library.roms
        let categories = categoryManager.categories

        let filtered = computeFilteredAndSorted(
            roms: allRoms,
            categories: categories,
            filter: filter,
            searchText: searchText,
            activeFilters: activeFilters,
            sortByLastPlayed: sortByLastPlayed,
            sortByLastAdded: sortByLastAdded,
            selectedGenres: selectedGenres
        )
            
            self.displayedROMs = filtered
            self.isProcessing = false
        }
    }
    
    // This method runs on main actor to access GenreManager
    private func computeFilteredAndSorted(
        roms: [ROM],
        categories: [GameCategory],
        filter: LibraryFilter,
        searchText: String,
        activeFilters: Set<String>,
        sortByLastPlayed: Bool,
        sortByLastAdded: Bool,
        selectedGenres: Set<String>
    ) -> [ROM] {
        // 1. Base Filtering
        var base: [ROM]
        switch filter {
        case .all:
            base = roms.filter { !$0.isHidden }
        case .favorites:
            base = roms.filter { $0.isFavorite && !$0.isHidden }
        case .recent:
            base = roms.filter { $0.lastPlayed != nil && !$0.isHidden }
        case .lastAdded:
            base = roms.filter { !$0.isHidden }
        case .system(let system):
            let systemIDs = SystemDatabase.allInternalIDs(forDisplayID: system.id)
            var systemRoms = roms.filter { systemIDs.contains($0.systemID ?? "") && !$0.isHidden }
            
            if system.id == "mame" {
                systemRoms = systemRoms.filter { rom in
                    rom.mameRomType == "game" || rom.mameRomType == nil
                }
                let runnableSet = MAMEDependencyService.shared.rachableShortNamesForCurrentCores
                if !runnableSet.isEmpty {
                    systemRoms = systemRoms.filter { rom in
                        runnableSet.contains(rom.path.lastPathComponent.replacingOccurrences(of: ".zip", with: "").lowercased())
                    }
                }
            }
            base = systemRoms
        case .category(let categoryID):
            // Use the passed-in categories instead of the categoryManager
            let category = categories.first { $0.id == categoryID }
            let categoryGameIDs = category?.gameIDs ?? []
            base = roms.filter { categoryGameIDs.contains($0.id) && !$0.isHidden }
        case .hidden:
            base = roms.filter { $0.isHidden }
        case .mameNonGames:
            base = roms.filter { rom in
                rom.systemID == "mame" && rom.mameRomType != "game"
            }
        }
        
        // 2. Active Filter Chips
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
        
// 3. Search Text
    let searchTerms = searchText.split(separator: " ").map(String.init)
    if !searchText.isEmpty {
        filtered = filtered.filter { rom in
            searchTerms.allSatisfy { term in
                rom.displayName.localizedCaseInsensitiveContains(term)
            }
        }
    }

    // 4. Genre Filter
    if !selectedGenres.isEmpty {
        filtered = filtered.filter { rom in
            let displayGenre = GenreManager.shared.effectiveDisplayName(for: rom.metadata?.genre)
            return selectedGenres.contains(displayGenre)
        }
    }

    // 5. Sorting
        return applySorting(to: filtered, sortByLastPlayed: sortByLastPlayed, sortByLastAdded: sortByLastAdded)
    }
    
    // This method is now nonisolated and only works on the data passed to it
    nonisolated private func applySorting(to roms: [ROM], sortByLastPlayed: Bool, sortByLastAdded: Bool) -> [ROM] {
        guard !roms.isEmpty else { return [] }
        
        if sortByLastPlayed {
            return roms.sorted { a, b in
                switch (a.lastPlayed, b.lastPlayed) {
                case (nil, nil):
                    return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                case (_, nil):
                    return true
                case (nil, _):
                    return false
                case let (dateA?, dateB?):
                    return dateA > dateB
                }
            }
        } else if sortByLastAdded {
            return roms.sorted { $0.dateAdded > $1.dateAdded }
        } else {
            return roms
                .map { (rom: $0, key: $0.displayName) }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { $0.rom }
        }
    }
}

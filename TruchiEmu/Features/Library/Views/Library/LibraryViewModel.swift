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
    var sortOrder: LibrarySortOrder = .name
    /// True for ascending (A→Z, 0→9, oldest first); false for descending
    /// (Z→A, 9→0, most recent / longest first). Ignored when `sortOrder == .name`.
    var sortAscending: Bool = false
    var selectedGenres: Set<String> = []

    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var lastComputedSignature: FilterSignature?

    init(
        library: ROMLibrary,
        categoryManager: CategoryManager,
        initialFilter: LibraryFilter = .all,
        initialSearchText: String = "",
        initialActiveFilters: Set<String> = [],
        initialSortOrder: LibrarySortOrder = .name,
        initialSortAscending: Bool = false
    ) {
        self.library = library
        self.categoryManager = categoryManager
        self.currentFilter = initialFilter
        self.currentSearchText = initialSearchText
        self.activeFilters = initialActiveFilters
        self.sortOrder = initialSortOrder
        self.sortAscending = initialSortAscending

        // Observe the library for changes. Debounced + deduplicated so a single
        // system switch triggers one filter pass instead of one per ROM mutation
        // (the publisher would otherwise fire ~30x during a system switch due to
        // handleFilterChange's art-resolution write-back).
        library.$roms
            .combineLatest(library.$lastChangeDate)
            .map { [weak self] _ in self?.currentInputsFingerprint() ?? 0 }
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)

        // Observe category changes — debounced + deduplicated.
        categoryManager.objectWillChange
            .map { [weak self] _ in self?.currentInputsFingerprint() ?? 0 }
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)

        // System preference changes (mergeGBC, etc.) — debounced + deduplicated.
        SystemPreferences.shared.$updateTrigger
            .map { [weak self] _ in self?.currentInputsFingerprint() ?? 0 }
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)

        // Folder removal (ROMs deleted from the library) — force a refresh so the
        // grid/list and any active search re-run against the new library contents
        // immediately, even if the debounced $roms pipeline would otherwise be
        // coalesced. This guarantees removed games disappear from the view.
        NotificationCenter.default.publisher(for: .libraryROMsRemoved)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshData() }
            .store(in: &cancellables)
    }

    private func currentInputsFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(currentFilter)
        hasher.combine(currentSearchText)
        hasher.combine(activeFilters)
        hasher.combine(sortOrder)
        hasher.combine(sortAscending)
        hasher.combine(selectedGenres)
        hasher.combine(library.roms.count)
        hasher.combine(library.lastChangeDate)
        return hasher.finalize()
    }

    /// Stable identifier for the current filter, for matching against filter-scoped
    /// background work started in `handleFilterChange`.
    var currentFilterID: String { currentFilter.id }

    func updateFilters(filter: LibraryFilter, searchText: String, activeFilters: Set<String>, sortOrder: LibrarySortOrder, sortAscending: Bool, selectedGenres: Set<String> = []) {
        self.currentFilter = filter
        self.currentSearchText = searchText
        self.activeFilters = activeFilters
        self.sortOrder = sortOrder
        self.sortAscending = sortAscending
        self.selectedGenres = selectedGenres

        refreshData()
    }

    private func refreshData() {
        let signature = FilterSignature(
            filter: currentFilter,
            searchText: currentSearchText,
            activeFilters: activeFilters,
            sortOrder: sortOrder,
            sortAscending: sortAscending,
            selectedGenres: selectedGenres,
            romsCount: library.roms.count,
            lastChangeDate: library.lastChangeDate
        )

        // Skip work if inputs haven't materially changed since the last refresh.
        // This prevents publisher cascades from triggering redundant filter runs.
        if signature == lastComputedSignature { return }
        lastComputedSignature = signature

        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Snapshot inputs ON the MainActor (state we need is MainActor-isolated).
            // For GenreManager (which is @MainActor), pre-resolve unique genres to a
            // plain dictionary so the off-MainActor filter can do dict lookups only.
            // Each raw genre may resolve to multiple display names (catver split).
            let rawGenres = Set(self.library.roms.compactMap { $0.metadata?.genre })
            var genreLookup: [String: [String]] = [:]
            for raw in rawGenres {
                genreLookup[raw] = GenreManager.shared.effectiveDisplayNames(for: raw)
            }

            // For .system filters, resolve the merged internal IDs here on the
            // MainActor — SystemDatabase.allInternalIDs(forDisplayID:) calls into
            // AppSettings.getBool which uses MainActor.assumeIsolated and cannot be
            // safely called from the detached filter task. Snapshot once, then
            // pass the resolved set to the off-MainActor filter.
            let precomputedSystemIDs: Set<String>?
            if case .system(let sys) = self.currentFilter {
                precomputedSystemIDs = Set(SystemDatabase.allInternalIDs(forDisplayID: sys.id))
            } else {
                precomputedSystemIDs = nil
            }

            // Snapshot MAMEDependencyService's runnable set on MainActor. The
            // service mutates its underlying dict from @MainActor methods; reading
            // it from a detached task would race against those mutations. The
            // snapshot is a cheap value-type copy of [String].
            let mameRunnableSet = MAMEDependencyService.shared.rachableShortNamesForCurrentCores

            let inputs = FilterInputs(
                roms: self.library.roms,
                categories: self.categoryManager.categories,
                filter: self.currentFilter,
                searchText: self.currentSearchText,
                activeFilters: self.activeFilters,
                sortOrder: self.sortOrder,
                sortAscending: self.sortAscending,
                selectedGenres: self.selectedGenres,
                mameRunnableSet: mameRunnableSet,
                genreLookup: genreLookup,
                precomputedSystemIDs: precomputedSystemIDs
            )

            // Heavy filter+sort runs OFF the MainActor so a 4 000-ROM MAME filter
            // doesn't stall the UI. UI stays responsive showing the previous
            // grid until the new filter is ready.
            let filtered = await Task.detached(priority: .userInitiated) {
                Self.computeFilteredAndSorted(inputs: inputs)
            }.value

            if Task.isCancelled { return }
            self.displayedROMs = filtered
        }
    }

    private nonisolated static func computeFilteredAndSorted(inputs: FilterInputs) -> [ROM] {
        // 1. Base Filtering
        var base: [ROM]
        switch inputs.filter {
        case .all:
            base = inputs.roms.filter { !$0.isHidden }
        case .favorites:
            base = inputs.roms.filter { $0.isFavorite && !$0.isHidden }
        case .recent:
            base = inputs.roms.filter { $0.lastPlayed != nil && !$0.isHidden }
        case .lastAdded:
            base = inputs.roms.filter { !$0.isHidden }
        case .system(let system):
            // Use the precomputed merged internal IDs captured on MainActor.
            // Calling SystemDatabase.allInternalIDs(forDisplayID:) here would
            // crash because AppSettings.getBool uses MainActor.assumeIsolated.
            let systemIDs: Set<String> = inputs.precomputedSystemIDs ?? [system.id]
            var systemRoms = inputs.roms.filter { systemIDs.contains($0.systemID ?? "") && !$0.isHidden }

            if system.id == "mame" {
                systemRoms = systemRoms.filter { rom in
                    rom.mameRomType == "game" || rom.mameRomType == nil
                }
                let runnableSet = inputs.mameRunnableSet
                if !runnableSet.isEmpty {
                    systemRoms = systemRoms.filter { rom in
                        runnableSet.contains(rom.path.lastPathComponent.replacingOccurrences(of: ".zip", with: "").lowercased())
                    }
                }
            }
            base = systemRoms
        case .category(let categoryID):
            let category = inputs.categories.first { $0.id == categoryID }
            let categoryGameIDs = category?.gameIDs ?? []
            base = inputs.roms.filter { categoryGameIDs.contains($0.id) && !$0.isHidden }
        case .hidden:
            base = inputs.roms.filter { $0.isHidden }
        case .mameNonGames:
            base = inputs.roms.filter { rom in
                rom.systemID == "mame" && rom.mameRomType != "game"
            }
        case .retroAchievements:
            base = inputs.roms.filter { $0.raMatchStatus == "matched" && !$0.isHidden }
        }

        // 2. Active Filter Chips
        var filtered = base
        if !inputs.activeFilters.isEmpty {
            filtered = filtered.filter { rom in
                for rawValue in inputs.activeFilters {
                    if let option = GameFilterOption(rawValue: rawValue) {
                        if !option.matches(rom) { return false }
                    }
                }
                return true
            }
        }

        // 3. Search Text
        let searchTerms = inputs.searchText.split(separator: " ").map(String.init)
        if !inputs.searchText.isEmpty {
            filtered = filtered.filter { rom in
                searchTerms.allSatisfy { term in
                    rom.displayName.localizedCaseInsensitiveContains(term)
                }
            }
        }

        // 4. Genre Filter
        if !inputs.selectedGenres.isEmpty {
            filtered = filtered.filter { rom in
                let displayGenres = inputs.genreLookup[rom.metadata?.genre ?? ""] ?? ["Unknown"]
                return displayGenres.contains(where: { inputs.selectedGenres.contains($0) })
            }
        }

        // 5. Sorting
        return applySorting(to: filtered, sortOrder: inputs.sortOrder, ascending: inputs.sortAscending)
    }

    nonisolated private static func applySorting(to roms: [ROM], sortOrder: LibrarySortOrder, ascending: Bool) -> [ROM] {
        guard !roms.isEmpty else { return [] }

        // `name` is always A→Z; direction is ignored.
        if sortOrder == .name {
            return roms
                .map { (rom: $0, key: $0.displayName) }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { $0.rom }
        }

        // For every other order, compute a per-ROM sort key, then sort.
        return roms.sorted { a, b in
            let cmp = Self.compare(a, b, by: sortOrder)
            return ascending ? cmp < 0 : cmp > 0
        }
    }

    /// Returns a `ComparisonResult`-like sign: negative if `a` should come
    /// before `b`, positive if after, zero if equal. Nil ranks sort last in
    /// descending mode (= best first) and first in ascending mode (= worst
    /// first); the picker flips them via the direction flag.
    nonisolated private static func compare(_ a: ROM, _ b: ROM, by order: LibrarySortOrder) -> Int {
        switch order {
        case .name:
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName).rawValue
        case .lastPlayed:
            // Nil-last semantics: when one is nil, it ranks "after" the
            // non-nil value in ascending mode (oldest first ⇒ nil = no data
            // is treated as oldest). Direction flag flips it.
            switch (a.lastPlayed, b.lastPlayed) {
            case (nil, nil): return 0
            case (_, nil):   return 1
            case (nil, _):   return -1
            case let (dA?, dB?): return dA.compare(dB).rawValue
            }
        case .lastAdded:
            return a.dateAdded.compare(b.dateAdded).rawValue
        case .playtime:
            if a.totalPlaytimeSeconds == b.totalPlaytimeSeconds { return 0 }
            return a.totalPlaytimeSeconds < b.totalPlaytimeSeconds ? -1 : 1
        case .timeToBeat:
            let aHours = a.metadata?.hltbMainStoryHours ?? 0
            let bHours = b.metadata?.hltbMainStoryHours ?? 0
            let aHas = (a.metadata?.hltbMainStoryHours ?? 0) > 0
            let bHas = (b.metadata?.hltbMainStoryHours ?? 0) > 0
            if aHas != bHas { return aHas ? -1 : 1 }
            if aHours == bHours { return 0 }
            return aHours < bHours ? -1 : 1
        }
    }
}

// MARK: - Filter inputs (snapshot sent to background filter task)

struct FilterInputs: Sendable {
    let roms: [ROM]
    let categories: [GameCategory]
    let filter: LibraryFilter
    let searchText: String
    let activeFilters: Set<String>
    let sortOrder: LibrarySortOrder
    let sortAscending: Bool
    let selectedGenres: Set<String>
    let mameRunnableSet: Set<String>
    let genreLookup: [String: [String]]
    /// Pre-resolved merged internal IDs for `.system(...)` filters, captured
    /// on the MainActor before the filter ran off-actor. Nil for non-system
    /// filters.
    let precomputedSystemIDs: Set<String>?
}

struct FilterSignature: Equatable {
    let filter: LibraryFilter
    let searchText: String
    let activeFilters: Set<String>
    let sortOrder: LibrarySortOrder
    let sortAscending: Bool
    let selectedGenres: Set<String>
    let romsCount: Int
    let lastChangeDate: Date

    static func == (lhs: FilterSignature, rhs: FilterSignature) -> Bool {
        lhs.filter == rhs.filter
            && lhs.searchText == rhs.searchText
            && lhs.activeFilters == rhs.activeFilters
            && lhs.sortOrder == rhs.sortOrder
            && lhs.sortAscending == rhs.sortAscending
            && lhs.selectedGenres == rhs.selectedGenres
            && lhs.romsCount == rhs.romsCount
            && lhs.lastChangeDate == rhs.lastChangeDate
    }
}

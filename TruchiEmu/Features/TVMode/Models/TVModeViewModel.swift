import Foundation
import SwiftUI
import Combine

@MainActor
final class TVModeViewModel: ObservableObject {
    @Published var row1Entries: [TVModeEntry] = []
    @Published var selectedEntryIndex: Int = 0
    @Published var games: [ROM] = []
    @Published var selectedGameIndex: Int = 0
    @Published var page: Page = .row1
    @Published var theme: TVModeSettings.Theme

    /// Sort mode applied to the games row. Mirrors the main library's
    /// two-value sort (`sortByLastPlayed` / `sortByLastAdded` AppSettings
    /// booleans) but as a single tri-state so the L3 rotate action can
    /// cycle through them. Reset by pressing L3+R3.
    @Published var sortMode: SortMode = .alphabetical

    /// Brief HUD overlay shown after `cycleSortMode()` / `resetSortMode()`.
    /// `nil` when no overlay is on screen.
    @Published var sortHudLabel: String? = nil

    enum SortMode: String, CaseIterable {
        case alphabetical
        case lastPlayed
        case lastAdded

        var localizationKey: String {
            switch self {
            case .alphabetical: return "tvMode.sortHUD.alphabetical"
            case .lastPlayed:    return "app.lastPlayed"
            case .lastAdded:     return "app.lastAdded"
            }
        }
    }

    enum Page: Equatable {
        case row1      // systems row focused
        case row2      // games row focused
        case detail    // page 2: game detail
    }

    @Published private(set) var loadingDetailROM: ROM? = nil
    @Published private(set) var downloadedDetailROM: ROM? = nil

    private let library: ROMLibrary
    private let systemDatabase: SystemDatabaseWrapper
    private let prefs = SystemPreferences.shared
    private let raService = RetroAchievementsService.shared
    private var cancellables = Set<AnyCancellable>()

    /// LibraryFilter id (e.g. "system-snes") the user was on in the main
    /// window when TV-mode was opened. Drives the initial selectedEntryIndex
    /// so TV-mode opens at the same system/filter the main window was on
    /// instead of always jumping to "All Games".
    private let initialEntryID: String?

    init(library: ROMLibrary, systemDatabase: SystemDatabaseWrapper, initialEntryID: String? = nil) {
        self.library = library
        self.systemDatabase = systemDatabase
        self.initialEntryID = initialEntryID
        self.theme = TVModeSettings.theme
        rebuildEntries()
        recomputeGames()
        observeChanges()
    }

    func reloadSettings() {
        theme = TVModeSettings.theme
        rebuildEntries()
        recomputeGames()
    }

    // MARK: - Entries

    var selectedEntry: TVModeEntry? {
        guard row1Entries.indices.contains(selectedEntryIndex) else { return nil }
        return row1Entries[selectedEntryIndex]
    }

    var selectedGame: ROM? {
        guard games.indices.contains(selectedGameIndex) else { return nil }
        return games[selectedGameIndex]
    }

    func selectEntryByOffset(_ delta: Int) {
        guard !row1Entries.isEmpty else { return }
        let count = row1Entries.count
        var newIndex = selectedEntryIndex + delta
        newIndex = ((newIndex % count) + count) % count
        if newIndex != selectedEntryIndex {
            withAnimation(.easeOut(duration: 0.22)) {
                selectedEntryIndex = newIndex
                recomputeGames()
                selectedGameIndex = games.isEmpty ? 0 : min(selectedGameIndex, games.count - 1)
            }
        }
    }

    func selectGameByOffset(_ delta: Int) {
        guard !games.isEmpty else { return }
        let count = games.count
        var newIndex = selectedGameIndex + delta
        newIndex = ((newIndex % count) + count) % count
        if newIndex != selectedGameIndex {
            withAnimation(.easeOut(duration: 0.22)) {
                selectedGameIndex = newIndex
            }
        }
    }

    func moveDownFromRow1() {
        if games.isEmpty { return }
        page = .row2
        if !games.indices.contains(selectedGameIndex) { selectedGameIndex = 0 }
    }

    func enterDetail() {
        guard let rom = selectedGame else { return }
        loadingDetailROM = rom
        downloadedDetailROM = rom
        page = .detail
        Task { await fetchDetailArt(for: rom) }
    }

    /// Move to a neighbouring game while already on the detail page. Updates
    /// both the hero ROM and the art-fetch task so the next frame reflects the
    /// newly-selected game and begins loading its boxart/title/snaps.
    func shiftDetailGame(by delta: Int) {
        guard page == .detail, !games.isEmpty else { return }
        let count = games.count
        var newIndex = selectedGameIndex + delta
        newIndex = ((newIndex % count) + count) % count
        guard newIndex != selectedGameIndex,
              games.indices.contains(newIndex) else { return }
        let rom = games[newIndex]
        withAnimation(.easeOut(duration: 0.22)) {
            selectedGameIndex = newIndex
        }
        loadingDetailROM = rom
        downloadedDetailROM = rom
        Task { await fetchDetailArt(for: rom) }
    }

    func exitDetail() {
        page = .row2
        downloadedDetailROM = nil
        loadingDetailROM = nil
    }

    func exitRow2() { page = .row1 }

    // MARK: - Launch

    /// Launches the currently selected game forcing fullscreen.
    ///
    /// Mirrors `LibraryGridView.launchGame`: resolves the core via the
    /// centralized `CoreManager.resolveCoreID` helper (which honors the user's
    /// per-system preferred core, e.g. picodrive over the SMS default
    /// genesis_plus_gx) and requests a core download when the resolved core
    /// isn't installed yet. Without this, TV-mode silently ignored the
    /// preferred-core setting and bypassed the core-download sheet, so the
    /// runner hit "Core dylib not found" for systems whose default core wasn't
    /// on disk — even when an alternative core the user had installed could
    /// have run the game.
    ///
    /// Auto-fullscreen is set globally on TV-mode entry (handled by
    /// `TVModeSettingsManager.enter()`), so we don't toggle it here ourselves.
    /// The controller's `init` reads the global at construction time, ensuring
    /// both direct launches and post-core-download launches go fullscreen.
    func launchSelected() async {
        guard let rom = (page == .detail ? downloadedDetailROM : selectedGame) ?? selectedGame else { return }
        guard let systemID = rom.systemID,
              let system = SystemDatabase.system(forID: systemID) else { return }

        let coreManager = CoreManager.shared
        let coreID = coreManager.resolveCoreID(for: rom, system: system)
        guard !coreID.isEmpty else { return }

        if !coreManager.isInstalled(coreID: coreID) {
            coreManager.requestCoreDownload(
                for: coreID,
                systemID: systemID,
                romID: rom.id,
                slotToLoad: nil
            )
            return
        }

        await GameLauncher.shared.launchGame(
            rom: rom,
            coreID: coreID,
            library: library
        )
    }

    // MARK: - Internal

    private func observeChanges() {
        library.$roms
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildEntries()
                self?.recomputeGames()
            }
            .store(in: &cancellables)

        library.$romCounts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildEntries()
                self?.recomputeGames()
            }
            .store(in: &cancellables)

        raService.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildEntries() }
            .store(in: &cancellables)
    }

    /// Called from the View's `.onChange(of: systemDatabase.systems)` because
    /// `@Observable` classes don't expose Combine publishers for property
    /// changes.
    func handleExternalSystemsChange() {
        rebuildEntries()
        recomputeGames()
    }

    private func rebuildEntries() {
        var entries: [TVModeEntry] = []
        for smart in TVModeSettings.shownSmartEntries {
            if count(for: smart.filter) > 0 {
                entries.append(TVModeEntry(filter: smart.filter))
            }
        }
        if TVModeSettings.showSystems {
            let displayIDs = Set(library.romCounts.keys)
            let display: [(SystemInfo, [String])] = systemDatabase.systemsForDisplay.compactMap { sys in
                let internalIDs = systemDatabase.allInternalIDs(forDisplayID: sys.id)
                let total = internalIDs.reduce(0) { $0 + (displayIDs.contains($1) ? library.romCounts[$1] ?? 0 : 0) }
                return total > 0 ? (sys, internalIDs) : nil
            }
            .sorted { $0.0.sidebarDisplayName.localizedCaseInsensitiveCompare($1.0.sidebarDisplayName) == .orderedAscending }
            for (sys, _) in display {
                entries.append(TVModeEntry(filter: .system(sys)))
            }
        }
        row1Entries = entries

        if let initialEntryID,
           let index = entries.firstIndex(where: { $0.id == initialEntryID }) {
            // Restore the same filter the main window was on when the
            // user opened TV mode.
            selectedEntryIndex = index
        } else if selectedEntryIndex >= entries.count {
            selectedEntryIndex = max(0, entries.count - 1)
        }
    }

    private func recomputeGames() {
        guard let entry = selectedEntry else {
            games = []
            selectedGameIndex = 0
            return
        }
        let roms: [ROM]
        switch entry.filter {
        case .all:
            roms = library.roms.filter { !$0.isHidden }
        case .favorites:
            roms = library.roms.filter { $0.isFavorite && !$0.isHidden }
        case .recent:
            // "Recent" entry filters to games that have been played; the
            // sort mode decides ordering (defaulting to last-played).
            roms = library.roms.filter { $0.lastPlayed != nil && !$0.isHidden }
        case .lastAdded:
            // "Last Added" entry shows all games (regardless of sort mode);
            // the sort mode decides ordering (defaulting to last-added).
            roms = library.roms.filter { !$0.isHidden }
        case .system(let sys):
            let internalIDs = Set(systemDatabase.allInternalIDs(forDisplayID: sys.id))
            var filtered = library.roms.filter { internalIDs.contains($0.systemID ?? "") && !$0.isHidden }
            if sys.id == "mame" {
                filtered = filtered.filter { rom in rom.mameRomType == "game" || rom.mameRomType == nil }
            }
            roms = filtered
        case .retroAchievements:
            roms = library.roms.filter { $0.raMatchStatus == "matched" && !$0.isHidden }
        case .hidden:
            roms = library.roms.filter { $0.isHidden }
        case .mameNonGames:
            roms = library.roms.filter { $0.systemID == "mame" && $0.mameRomType != "game" }
        case .category:
            roms = []
        }
        games = applySort(roms)
        if selectedGameIndex >= roms.count { selectedGameIndex = max(0, roms.count - 1) }
    }

    /// Sorts `roms` per the current `sortMode`. The `.recent` entry always
    /// sorts by last-played (its whole point), `.lastAdded` always by
    /// date-added. Other entries follow `sortMode`.
    private func applySort(_ roms: [ROM]) -> [ROM] {
        guard let entry = selectedEntry else { return roms }
        switch entry.filter {
        case .recent:    return roms.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .lastAdded: return roms.sorted { $0.dateAdded > $1.dateAdded }
        default: break
        }
        switch sortMode {
        case .alphabetical:
            return roms.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .lastPlayed:
            return roms.sorted { a, b in
                switch (a.lastPlayed, b.lastPlayed) {
                case (nil, nil): return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                case (_, nil):   return true
                case (nil, _):   return false
                case let (dA, dB): return dA! > dB!
                }
            }
        case .lastAdded:
            return roms.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    /// Rotates `sortMode` through alphabetical → lastPlayed → lastAdded →
    /// alphabetical → …, applies it to the games row, and flashes the HUD.
    func cycleSortMode() {
        let all = SortMode.allCases
        guard let idx = all.firstIndex(of: sortMode) else { sortMode = .alphabetical; return }
        sortMode = all[(idx + 1) % all.count]
        recomputeGames()
        flashSortHud()
    }

    /// Resets `sortMode` to alphabetical and re-applies the row.
    func resetSortMode() {
        guard sortMode != .alphabetical else { flashSortHud(); return }
        sortMode = .alphabetical
        recomputeGames()
        flashSortHud()
    }

    /// Surfaces the `sortHudLabel` for ~1.6 s — long enough for the user to
    /// read the new mode without disowning the row. The auto-hide is one-time
    /// per cycle (cancel-and-replace: rapid R3 presses refresh the timer).
    private var sortHudWorkItem: DispatchWorkItem?
    private func flashSortHud() {
        let loc = LocalizationManager.shared
        sortHudLabel = loc.localized(sortMode.localizationKey)
        sortHudWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sortHudLabel = nil }
        sortHudWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func count(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all: return library.roms.filter { !$0.isHidden }.count
        case .favorites: return library.roms.filter { $0.isFavorite && !$0.isHidden }.count
        case .recent: return library.roms.filter { $0.lastPlayed != nil && !$0.isHidden }.count
        case .lastAdded: return library.roms.filter { !$0.isHidden }.count
        case .retroAchievements: return raService.isEnabled ? library.roms.filter { $0.raMatchStatus == "matched" }.count : 0
        case .hidden: return library.roms.filter { $0.isHidden }.count
        case .mameNonGames: return library.roms.filter { $0.systemID == "mame" && $0.mameRomType != "game" }.count
        case .system(let sys):
            let internalIDs = Set(systemDatabase.allInternalIDs(forDisplayID: sys.id))
            return library.roms.filter { internalIDs.contains($0.systemID ?? "") && !$0.isHidden }.count
        case .category: return 0
        }
    }

    private func fetchDetailArt(for rom: ROM) async {
        // Matches GameInfoWindow/GameDetailView behaviour: lazy download of
        // title screen + snaps on first reveal of the detail page.
        _ = await BoxArtService.shared.downloadTitleScreen(for: rom)
        if rom.screenshotPaths.isEmpty {
            _ = await BoxArtService.shared.downloadScreenshots(for: rom)
        }
        if page == .detail {
            loadingDetailROM = rom
            downloadedDetailROM = rom
        }
    }
}

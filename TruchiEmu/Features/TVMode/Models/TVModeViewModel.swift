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

    /// Sort mode applied to the games row. Mirrors `LibrarySortOrder` in the
    /// main library but as a single source-of-truth state for the L3 rotate
    /// action to cycle through. Reset by pressing L3+R3.
    @Published var sortMode: SortMode = .alphabetical

    /// Brief HUD overlay shown after `cycleSortMode()` / `resetSortMode()`.
    /// `nil` when no overlay is on screen.
    @Published var sortHudLabel: String? = nil

    enum SortMode: String, CaseIterable {
        case alphabetical
        case lastPlayed
        case lastAdded
        case playtime
        case timeToBeat

        var localizationKey: String {
            switch self {
            case .alphabetical: return "tvMode.sortHUD.alphabetical"
            case .lastPlayed:    return "app.lastPlayed"
            case .lastAdded:     return "app.lastAdded"
            case .playtime:      return "app.sortByPlaytime"
            case .timeToBeat:    return "app.sortByTimeToBeat"
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

    /// Most recently-modified save slot for the currently focused game on
    /// the detail page. Used to surface a "Continue" affordance in TV-mode
    /// (mirrors the desktop `GameDetailView.mostRecentSaveSlot`/Continue
    /// button flow) and to feed `slotToLoad` into `launchSelected` when the
    /// user presses A on a game that has a save.
    @Published private(set) var mostRecentSaveSlot: SlotInfo? = nil

    private let library: ROMLibrary
    private let systemDatabase: SystemDatabaseWrapper
    private let saveStateManager = SaveStateManager()
    private let prefs = SystemPreferences.shared
    private let raService = RetroAchievementsService.shared
    private var cancellables = Set<AnyCancellable>()

    /// LibraryFilter id (e.g. "system-snes") the user was on in the main
    /// window when TV-mode was opened. Drives the initial selectedEntryIndex
    /// so TV-mode opens at the same system/filter the main window was on
    /// instead of always jumping to "All Games".
    private var initialEntryID: String?

    init(library: ROMLibrary, systemDatabase: SystemDatabaseWrapper, initialEntryID: String? = nil) {
        self.library = library
        self.systemDatabase = systemDatabase
        self.initialEntryID = initialEntryID
        self.theme = TVModeSettings.theme
        rebuildEntries()
        // Pick the same row-1 entry the main window was on, then load its
        // games and seed the selected game off the persisted ROM id.
        // `initialEntryID` (from current main window) takes priority over the
        // cross-session saved value, so opening TV-mode immediately syncs
        // the filter from the main window position.
        if let initialEntryID,
           let idx = row1Entries.firstIndex(where: { $0.id == initialEntryID }) {
            selectedEntryIndex = idx
        } else if let raw = AppSettings.getString("tvMode_lastFilter"),
                  let idx = row1Entries.firstIndex(where: { $0.id == raw }) {
            selectedEntryIndex = idx
        }
        recomputeGames()
        // Restore the same game the main window was on. We check both the
        // cross-session setting and the live main window reference, preferring
        // main.
        if let mainROM = AppSettings.getString("tvMode_entryROM"), let uuid = UUID(uuidString: mainROM),
           let idx = games.firstIndex(where: { $0.id == uuid }) {
            selectedGameIndex = idx
        } else if let saved = AppSettings.getString("tvMode_lastROM"), let uuid = UUID(uuidString: saved),
                  let idx = games.firstIndex(where: { $0.id == uuid }) {
            selectedGameIndex = idx
        }
        observeChanges()
        // Snapshot the initial selection so an immediate exit (without any
        // user nav) still has a valid filter+ROM pair to restore.
        syncStateForMainWindow()
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

    /// Identifier of the currently selected row-1 entry (the system or smart
    /// filter TV-mode is showing). Mirrors `LibraryFilter.id` so the value is
    /// interchangeable with ContentView's `selectedFilter.id` — used to keep
    /// the two surfaces in sync (see `syncStateForMainWindow()`).
    var selectedFilterID: String? {
        selectedEntry?.filter.id
    }

    /// UUID string of the currently selected game. May differ from the
    /// equivalent position in the main view because filters and sort orders
    /// can change between modes — readers look up the ROM directly.
    var selectedRomID: String? {
        selectedGame?.id.uuidString
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
                syncStateForMainWindow()
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
                syncStateForMainWindow()
            }
        }
    }

    func moveDownFromRow1() {
        if games.isEmpty { return }
        page = .row2
        if !games.indices.contains(selectedGameIndex) { selectedGameIndex = 0 }
        syncStateForMainWindow()
    }

    func enterDetail() {
        guard let rom = selectedGame else { return }
        loadingDetailROM = rom
        downloadedDetailROM = rom
        page = .detail
        refreshMostRecentSaveSlot(for: rom)
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
            syncStateForMainWindow()
        }
        loadingDetailROM = rom
        downloadedDetailROM = rom
        refreshMostRecentSaveSlot(for: rom)
        Task { await fetchDetailArt(for: rom) }
    }

    func exitDetail() {
        page = .row2
        downloadedDetailROM = nil
        loadingDetailROM = nil
        mostRecentSaveSlot = nil
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
    ///
    /// - Parameters:
    ///   - slotToLoad: Optional save slot to load on start. `nil` launches the
    ///     game fresh (or honors the global `saveState_autoLoadOnStart`
    ///     setting, which the runner window handles on its own). Passing a slot
    ///     mirrors the desktop "Continue" button so TV-mode users can resume
    ///     previous play without having to dig into the save-state picker.
    ///   - progressiveVersion: Optional progressive slot version to load. Only
    ///     used together with `slotToLoad` — `SaveStateManager` walks the
    ///     progressive versions to find the newest one and surfaces it via
    ///     `mostRecentSaveSlot`, so the caller can pass that version straight
    ///     through to `GameLauncher` for an exact restore.
    ///   - disableAutoLoad: When `true`, the runner's `effectiveShouldAutoLoad`
    ///     gate returns `false` for this launch only — used by the "Y — Play
    ///     from start" affordance to skip auto-load even when the user has
    ///     `saveState_autoLoadOnStart` enabled. Default `false` keeps every
    ///     other caller's behaviour unchanged.
    func launchSelected(slotToLoad: Int? = nil, progressiveVersion: Int? = nil, disableAutoLoad: Bool = false) async {
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
                slotToLoad: slotToLoad
            )
            return
        }

        await GameLauncher.shared.launchGame(
            rom: rom,
            coreID: coreID,
            slotToLoad: slotToLoad,
            progressiveVersion: progressiveVersion,
            disableAutoLoadOnStart: disableAutoLoad,
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
            // user opened TV mode. This is a one-shot seed: consume it
            // so subsequent rebuilds (triggered by library.roms publishes
            // from markPlayed at launch / recordPlaySession at exit) do not
            // snap the user's row-1 navigation back to the entry they
            // opened TV mode on.
            selectedEntryIndex = index
            self.initialEntryID = nil
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
        case .playtime:
            return roms.sorted { a, b in
                if a.totalPlaytimeSeconds != b.totalPlaytimeSeconds {
                    return a.totalPlaytimeSeconds > b.totalPlaytimeSeconds
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        case .timeToBeat:
            return roms.sorted { a, b in
                let aHours = a.metadata?.hltbMainStoryHours ?? 0
                let bHours = b.metadata?.hltbMainStoryHours ?? 0
                let aHasData = a.metadata?.hltbMainStoryHours != nil && a.metadata!.hltbMainStoryHours! > 0
                let bHasData = b.metadata?.hltbMainStoryHours != nil && b.metadata!.hltbMainStoryHours! > 0
                if aHasData != bHasData { return aHasData }
                if aHours != bHours { return aHours > bHours }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
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

    /// Mirrors the current selection out to AppSettings so the main window
    /// can resume from the same system/filter and game the user was on when
    /// TV-mode exits (and conversely, know what is being entered with).
    /// Cheap (a couple of dictionary writes) — called on every nav action.
    func syncStateForMainWindow() {
        AppSettings.setString("tvMode_lastFilter", value: selectedFilterID)
        AppSettings.setString("tvMode_lastROM", value: selectedRomID)
        // Also write the canonical main-window key so any code path that
        // reads `lastSelectedFilter` (ContentView's `.onAppear`, future
        // restore flows) sees the same value. Removes the asymmetry where
        // the main-window value diverged from the TV-mode snapshot.
        AppSettings.setString("lastSelectedFilter", value: selectedFilterID)
    }

    /// Restores `selectedGameIndex` from a previously persisted ROM UUID
    /// (saved by an earlier session of TV-mode or by the main window's
    /// auto-save on every change). Returns true if a match was found and
    /// applied. Safe to call multiple times — last write wins.
    @discardableResult
    func restoreLastROM() -> Bool {
        guard let raw = AppSettings.getString("tvMode_lastROM"),
              let uuid = UUID(uuidString: raw) else { return false }
        if let idx = games.firstIndex(where: { $0.id == uuid }) {
            selectedGameIndex = idx
            return true
        }
        return false
    }

    /// Restores `selectedEntryIndex` from a previously persisted filter id.
    /// Called after `rebuildEntries()` so entries are populated first.
    @discardableResult
    func restoreLastFilter() -> Bool {
        guard let raw = AppSettings.getString("tvMode_lastFilter") else { return false }
        if let idx = row1Entries.firstIndex(where: { $0.id == raw }) {
            selectedEntryIndex = idx
            return true
        }
        return false
    }

    /// Convenience: restore both filter and ROM in the right order. Filter
    /// must be restored before `recomputeGames()` runs so the games list
    /// contains the ROM we're trying to match.
    func restoreStateFromMainWindow() {
        restoreLastFilter()
        recomputeGames()
        restoreLastROM()
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

    /// Recomputes `mostRecentSaveSlot` for the given ROM so the detail view
    /// can surface a "Continue" affordance. Matches `GameDetailView`'s
    /// `loadMostRecentSaveState()` formatting — the game name encodes the
    /// running key that `SaveStateManager` keys on (`displayName__<id prefix>`).
    /// Hard-core gate isn't checked here because this only displays whether a
    /// save file exists; the load attempt itself is gated by `HardcoreModeManager`
    /// at launch time.
    private func refreshMostRecentSaveSlot(for rom: ROM) {
        let gameName = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
        let systemID = rom.systemID ?? ""
        mostRecentSaveSlot = saveStateManager.mostRecentSaveState(gameName: gameName, systemID: systemID)
    }
}

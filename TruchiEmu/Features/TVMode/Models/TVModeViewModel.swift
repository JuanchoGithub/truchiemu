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

    init(library: ROMLibrary, systemDatabase: SystemDatabaseWrapper) {
        self.library = library
        self.systemDatabase = systemDatabase
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

    /// Launches the currently selected game forcing fullscreen. The TV mode
    /// goroutine owns the autoFullscreen setting for the duration of the launch.
    func launchSelected() async {
        guard let rom = (page == .detail ? downloadedDetailROM : selectedGame) ?? selectedGame else { return }
        let systemID = rom.systemID ?? ""
        let coreID: String
        if rom.useCustomCore, let cid = rom.selectedCoreID, !cid.isEmpty {
            coreID = cid
        } else {
            coreID = SystemDatabase.system(forID: systemID)?.defaultCoreID ?? ""
        }
        guard !coreID.isEmpty else { return }

        let priorAuto = AppSettings.getBool("autoFullscreenEnabled", defaultValue: false)
        AppSettings.setBool("autoFullscreenEnabled", value: true)
        await GameLauncher.shared.launchGame(
            rom: rom,
            coreID: coreID,
            library: library
        ) { _ in
            AppSettings.setBool("autoFullscreenEnabled", value: priorAuto)
        }
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
        if selectedEntryIndex >= entries.count { selectedEntryIndex = max(0, entries.count - 1) }
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
            roms = library.roms.filter { $0.lastPlayed != nil && !$0.isHidden }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .lastAdded:
            roms = library.roms.filter { !$0.isHidden }
            .sorted { $0.dateAdded > $1.dateAdded }
        case .system(let sys):
            let internalIDs = Set(systemDatabase.allInternalIDs(forDisplayID: sys.id))
            var filtered = library.roms.filter { internalIDs.contains($0.systemID ?? "") && !$0.isHidden }
            if sys.id == "mame" {
                filtered = filtered.filter { rom in rom.mameRomType == "game" || rom.mameRomType == nil }
            }
            roms = filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .retroAchievements:
            roms = library.roms.filter { $0.raMatchStatus == "matched" && !$0.isHidden }
        case .hidden:
            roms = library.roms.filter { $0.isHidden }
        case .mameNonGames:
            roms = library.roms.filter { $0.systemID == "mame" && $0.mameRomType != "game" }
        case .category:
            roms = []
        }
        games = roms
        if selectedGameIndex >= roms.count { selectedGameIndex = max(0, roms.count - 1) }
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

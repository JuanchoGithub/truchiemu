import Foundation
import Combine
import SwiftData
import SwiftUI

// MARK: - CancellationToken

final class ScanCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return _isCancelled
    }
    func cancel() { lock.lock(); _isCancelled = true; lock.unlock() }
    func reset() { lock.lock(); _isCancelled = false; lock.unlock() }
}

// MARK: - File Signature

private struct FileSignature: Codable, Hashable {
    let size: Int64
    let modTime: TimeInterval
}

// MARK: - Library Folder Model

struct ROMLibraryFolder: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let parentPath: String?
    let isPrimary: Bool

    var displayName: String { url.lastPathComponent }
    var depthFromPrimary: Int {
        guard let parentPath = parentPath else { return 0 }
        let remainder = url.path.replacingOccurrences(of: parentPath + "/", with: "")
        return remainder.components(separatedBy: "/").filter { !$0.isEmpty }.count
    }
    var isLevelOneSubfolder: Bool {
        guard let parentPath = parentPath else { return false }
        return url.path.hasPrefix(parentPath + "/") && depthFromPrimary == 1
    }
    static func == (lhs: ROMLibraryFolder, rhs: ROMLibraryFolder) -> Bool { lhs.url.path == rhs.url.path }
}

// MARK: - Rebuild Options

enum RebuildOption: String, CaseIterable, Identifiable {
    case refresh, idRebuild, boxartRebuild, everything
    var id: String { rawValue }
    var title: String {
        switch self {
        case .refresh: "Refresh ROMs"; case .idRebuild: "Rebuild Identification"
        case .boxartRebuild: "Rebuild Boxart"; case .everything: "Rebuild Everything"
        }
    }
    var description: String {
        switch self {
        case .refresh: "Scan for new or deleted ROMs"
        case .idRebuild: "Clear all ROM identification and re-identify"
        case .boxartRebuild: "Clear all boxart and re-download"
        case .everything: "Refresh ROMs, rebuild identification, and re-download boxart"
        }
    }
    var icon: String {
        switch self {
        case .refresh: "arrow.clockwise"; case .idRebuild: "fingerprint"
        case .boxartRebuild: "photo"; case .everything: "gearshape.2"
        }
    }
}

// MARK: - ROM Library

@MainActor
class ROMLibrary: ObservableObject {

    var lastAddedROMs: [ROM] = []

    // MARK: - Path Validation

    private var appInternalPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("TruchieEmu").path
    }
    private func isInternalPath(_ url: URL) -> Bool { url.path.hasPrefix(appInternalPath) }

    private static let excludedLibraryPaths = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences",
        "/Library/Logs", "/Library/Saved Application State", "/Library/Containers",
        "/Library/Group Containers", "/Library/Autosave Information", "/Library/Calendars",
        "/Library/Mail", "/Library/Messages", "/Library/Notes", "/Library/Passes",
        "/Library/Photos", "/Library/Safari", "/Library/Sounds", "/Library/Spelling",
        "/Library/VoiceMemos",
    ]
    private func isExcludedLibraryPath(_ url: URL) -> Bool {
        Self.excludedLibraryPaths.contains { url.path.contains($0) }
    }

    // MARK: - Published Properties

    @Published var roms: [ROM] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    private let scanCancellationToken = ScanCancellationToken()
    @Published var hasCompletedOnboarding: Bool
    @Published var primaryFolders: [ROMLibraryFolder] = []
    @Published var subfolderMap: [String: [ROMLibraryFolder]] = [:]
    @Published var libraryFolders: [URL] = []
    @Published var romCounts: [String: Int] = [:]
    @Published var lastChangeDate = Date()
    @Published var bezelUpdateToken: Int = 0
    var romFolderURL: URL? { libraryFolders.first }

    // MARK: - SwiftData Persistence

    let repository: ROMRepository
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyRomsKey = "saved_roms"
    private let legacyFoldersKey = "library_folders_bookmarks_v2"
    private let legacyOnboardingKey = "has_completed_onboarding"
    private let legacyIndexKey = "rom_file_index_v1"
    private var fileIndex: [String: FileSignature] = [:]

    // MARK: - Init

    init() {
        self.repository = ROMRepository(context: SwiftDataContainer.shared.mainContext)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
    }

    func initializeIfNeeded() {
        guard roms.isEmpty else { return }
        initializeLibrary()
    }

    func restoreLibraryAccess() {
        let savedFolders = repository.loadPrimaryFolders()
        if savedFolders.isEmpty {
            libraryFolders = []
            primaryFolders = []
            subfolderMap = [:]
            return
        }
        
        libraryFolders = savedFolders.compactMap {
            var stale = false
            return try? URL(resolvingBookmarkData: $0.1, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        }
        
        primaryFolders = savedFolders.map { ROMLibraryFolder(url: URL(fileURLWithPath: $0.0), parentPath: $0.2, isPrimary: $0.3) }
        for primary in primaryFolders {
            subfolderMap[primary.url.path] = repository.loadSubfolders(parentPath: primary.url.path).map {
                ROMLibraryFolder(url: URL(fileURLWithPath: $0.0), parentPath: $0.2, isPrimary: $0.3)
            }
        }
    }

    private func loadROMsFromRepository() { roms = repository.allROMs() }

    func saveROMsToDatabase(only ids: [UUID]? = nil) {
        if let ids = ids {
            let idSet = Set(ids)
            repository.saveROMs(roms.filter { idSet.contains($0.id) })
        } else { repository.saveROMs(roms) }
    }

    // This method is called after any folder removal to ensure we don't keep orphaned ROM entries
    private func purgeROMsOutsideLibraryFolders() {
        let validPaths = primaryFolders.map { $0.url.path } + subfolderMap.values.flatMap { $0.map { $0.url.path } }
        guard !validPaths.isEmpty else {
            if !roms.isEmpty { roms.removeAll(); repository.deleteROMsByPath(roms.map{$0.path.path}); fileIndex.removeAll() }
            return
        }

        let orphans = roms.filter { rom in
            let romPath = rom.path.path
            return !validPaths.contains { romPath == $0 || romPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        guard !orphans.isEmpty else { return }

        let idsToPurge = orphans.map { $0.id }
        roms.removeAll { idsToPurge.contains($0.id) }
        repository.deleteROMs(ids: idsToPurge)
        saveROMsToDatabase()
    }



    // MARK: - Legacy Migration & Purges
    
    private func migrateLegacyUserDefaultsToSwiftData() {
        let needsRomMigration = defaults.data(forKey: legacyRomsKey) != nil
        let needsFolderMigration = defaults.array(forKey: legacyFoldersKey) as? [Data] != nil || defaults.data(forKey: "rom_folder_bookmark") != nil
        if needsRomMigration { migrateLegacyROMs() }
        if needsFolderMigration { migrateLegacyLibraryFolders() }
        if defaults.data(forKey: legacyIndexKey) != nil { defaults.removeObject(forKey: legacyIndexKey) }
    }

    private func migrateLegacyROMs() {
        guard let data = defaults.data(forKey: legacyRomsKey) else { return }
        if let legacyRoms = try? decoder.decode([ROM].self, from: data) { repository.saveROMs(legacyRoms) }
        defaults.removeObject(forKey: legacyRomsKey)
    }

    private func migrateLegacyLibraryFolders() {
        if let bookmarks = defaults.array(forKey: legacyFoldersKey) as? [Data] {
            var urlPathPairs: [(String, Data)] = []
            for data in bookmarks {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                    urlPathPairs.append((url.path, data))
                }
            }
            repository.saveLibraryFolders(urlPathPairs.map { ($0.0, $0.1, nil, true) })
            defaults.removeObject(forKey: legacyFoldersKey)
        }
    }


    // 2. The new "Incremental" one (Used for adding new ROMs)
    func updateCounts(for newROMs: [ROM]? = nil) {
        if let roms = newROMs { 
            
            // Perform incremental updates on your dictionary
            for rom in roms where !rom.isHidden {
                romCounts["all", default: 0] += 1
                if rom.isFavorite { romCounts["favorites", default: 0] += 1 }
                if rom.lastPlayed != nil { romCounts["recent", default: 0] += 1 }
                
                let sysID = rom.systemID ?? "unknown"
                if sysID == "mame" {
                    if rom.mameRomType == "game" || rom.mameRomType == nil {
                        romCounts[sysID, default: 0] += 1
                    }
                } else {
                    romCounts[sysID, default: 0] += 1
                }
            }
            // If we have no ROMs, just do a full update
        } else {
            var counts: [String: Int] = [:]
            counts["all"] = roms.filter { !$0.isHidden }.count
            counts["favorites"] = roms.filter { $0.isFavorite && !$0.isHidden }.count
            counts["recent"] = roms.filter { $0.lastPlayed != nil && !$0.isHidden }.count
            counts["hidden"] = roms.filter { $0.isHidden }.count
            counts["mameNonGames"] = roms.filter { $0.systemID == "mame" && $0.mameRomType != nil && $0.mameRomType != "game" }.count

            let grouped = Dictionary(grouping: roms) { $0.systemID ?? "unknown" }
            for (sysID, list) in grouped {
                var visible = list.filter { !$0.isHidden }
                if sysID == "mame" { visible = visible.filter { $0.mameRomType == "game" || $0.mameRomType == nil } }
                counts[sysID] = visible.count
            }
            self.romCounts = counts
            return
        }
        self.lastChangeDate = Date()
        self.updateCounts() 
    }

    // MARK: - Onboarding & Library Folders

    func completeOnboarding(folderURL: URL) {
        addPrimaryFolder(url: folderURL)
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
    }

    func addLibraryFolder(url: URL) { addPrimaryFolder(url: url) }

    func removeLibraryFolder(at index: Int) {
        guard index < libraryFolders.count else { return }
        let url = libraryFolders[index]
        let folderPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        let removedROMs = roms.filter { $0.path.path.hasPrefix(folderPath) || $0.path.path == url.path }

        libraryFolders.remove(at: index)
        saveSecurityScopedBookmarks()
        
        let removedIDs = removedROMs.map { $0.id }
        roms.removeAll { removedIDs.contains($0.id) }
        repository.deleteROMsByPath([folderPath])

        if libraryFolders.isEmpty {
            roms.removeAll()
            fileIndex.removeAll()
        } else {
            for path in Set(removedROMs.map { $0.path.path }) { fileIndex.removeValue(forKey: path) }
        }

        LibraryMetadataStore.shared.deleteMetadataEntries(Set(removedROMs.map { LibraryMetadataStore.pathKey(for: $0) }))
        updateCounts()
        saveROMsToDatabase()
        cleanupScummVMCaches()
    }

    // MARK: - Core Scanning Method (Optimized)

    func scanROMs(in folder: URL, runAutomationAfter: Bool = true) async {
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.debug(category: "ROMLibrary", "Deferring ROM scan for \(folder.path) — game is running")
            return
        } else {
            LoggerService.info(category: "ROMLibrary", "Starting ROM scan for folder: \(folder.path)")
        }

        let scanStart = Date()
        isScanning = true
        scanProgress = 0
        scanCancellationToken.reset()
        
        // 1. Scan the folder
        let scanner = ROMScanner()
        let scannedROMs = await scanner.scan(folder: folder, cancellationToken: scanCancellationToken) { progress in
            Task { @MainActor in self.scanProgress = progress }
        }

        // 2. Identify new items (Fast O(1) duplicate prevention)
        let existingROMPaths = Set(roms.map { $0.path.path })
        let newROMs = scannedROMs.filter { !existingROMPaths.contains($0.path.path) }
        
        if !newROMs.isEmpty {
            var processedROMs: [ROM] = []
            
            // 3. Process only the new items
            for var rom in newROMs {
                if rom.systemID == "mame" {
                    self.applyMAMEIdentificationInline(to: &rom, url: rom.path)
                }
                // Add metadata merging
                let merged = LibraryMetadataStore.shared.mergedROM(rom)
                processedROMs.append(merged)
            }

            // 4. Update UI state incrementally
            self.roms.append(contentsOf: processedROMs)
            self.lastAddedROMs = processedROMs
            self.roms.sort { $0.displayName < $1.displayName }
            self.updateCounts(for: processedROMs) // Uses your new incremental method
            
            // 5. Persist only the new items
            repository.saveROMs(processedROMs)
            for rom in processedROMs { 
                LoggerService.debug(category: "ROMLibrary", "Persisting new ROM: \(rom.displayName)")
                LibraryMetadataStore.shared.persist(rom: rom) 
            }
            LibraryMetadataStore.shared.flushToSwiftData()
            
            LoggerService.info(category: "ROMLibrary", "Scan extracted \(newROMs.count) new ROMs in \(String(format: "%.2f", Date().timeIntervalSince(scanStart)))s")
        }

        // 6. Post-scan tasks (only for new systems)
        let detectedSystems = Set(scannedROMs.compactMap { $0.systemID })
        Task { await scanner.downloadDatsForDiscoveredSystems(detectedSystems) }

        self.scanProgress = 1.0
        isScanning = false
        cleanupScummVMCaches()

        // 7. Automation
        if runAutomationAfter {
            guard !RunningGamesTracker.shared.isGameRunning else { return }
            // NOTE: If these coordinators perform global scans, you should check 
            // if they can be made to only target the 'newROMs' or 'folder'
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self, targetROMs: self.lastAddedROMs)
            await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(library: self, targetROMs: self.lastAddedROMs)
        }
    }

    /// Apply MAME identification inline during scanning.
    private func applyMAMEIdentificationInline(to rom: inout ROM, url: URL) {
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()
        var description: String?
        var isPlayable: Bool?
        var type: String?

        // Check user's selected core first, if applicable
        if let coreID = rom.selectedCoreID {
            if let lookup = MAMEDependencyService.shared.lookupGame(for: coreID, shortName: shortName) {
                description = lookup.description
                type = lookup.type
                isPlayable = lookup.isPlayable
            }
        }

        // Fall back to multi-core unified lookup
        if description == nil {
            if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
                description = unifiedEntry.description
                type = unifiedEntry.isBIOS ? "bios" : (unifiedEntry.isRunnableInAnyCore ? "game" : "unplayable")
                isPlayable = unifiedEntry.isRunnableInAnyCore && !unifiedEntry.isBIOS
            }
        }

        guard let description = description, let type = type, let isPlayable = isPlayable else {
            rom.mameRomType = nil
            rom.isHidden = true
            rom.isBios = true
            rom.category = "bios"
            return
        }

        rom.mameRomType = type
        if isPlayable {
            rom.name = description
            rom.isHidden = false
            rom.category = "game"
            if rom.metadata == nil { rom.metadata = ROMMetadata() }
            rom.metadata?.title = description
        } else {
            rom.isHidden = true
            rom.isBios = true
            rom.category = "bios"
        }
    }

    private func cleanupScummVMCaches() {
        let activeScummVMPaths = Set(roms.filter { $0.systemID == "scummvm" }.map { $0.path.path })
        ScummVMCacheManager.cleanupOrphanedCaches(activeScummvmPaths: activeScummVMPaths)
    }

    func deleteAllFoldersAndROMs() {
        for idx in libraryFolders.indices.reversed() { removeLibraryFolder(at: idx) }
        roms.removeAll()
        fileIndex.removeAll()
        saveROMsToDatabase()
    }

    func fullRescan() async {
        isScanning = true
        scanProgress = 0
        
        // 1. Clear UI state
        roms = []
        fileIndex = [:]

        // 2. CLEAR THE DATABASE
        repository.deleteAllROMS()
        LibraryMetadataStore.shared.deleteAllMetadata()

        for (i, folder) in libraryFolders.enumerated() {
            if !isScanning { break }
            let last = i == libraryFolders.count - 1
            await scanROMs(in: folder, runAutomationAfter: last)
        }
        updateCounts()
        isScanning = false
    }

    func stopScan() { scanCancellationToken.cancel(); isScanning = false }

    func updateROM(_ rom: ROM, persist: Bool = true, silent: Bool = false) {
        if let idx = roms.firstIndex(where: { $0.id == rom.id }) {
            let oldBezel = roms[idx].settings.bezelFileName
            
            // Only send updates if not silent
            if !silent { objectWillChange.send() }
            roms[idx] = rom
            if oldBezel != rom.settings.bezelFileName { bezelUpdateToken += 1 }
            LibraryMetadataStore.shared.persist(rom: rom)
            
            // Only update counts if not silent
            if !silent { updateCounts() }
            if persist {
                updateGamesXML(for: rom)
                saveROMsToDatabase(only: [rom.id])
            }
        }
    }

    @discardableResult
    func identifyROM(_ rom: ROM, preferNameMatch: Bool = true, persist: Bool = true) async -> ROMIdentifyResult {
        let result = await ROMIdentifierService.shared.identify(rom: rom, preferNameMatch: preferNameMatch)
        applyIdentificationResult(result, to: rom, persist: persist)
        return result
    }

    func applyIdentificationResult(_ result: ROMIdentifyResult, to rom: ROM, persist: Bool = true, silent: Bool = false) -> ROM? {
        switch result {
            case .identified(let info), .identifiedFromName(let info):
                var updated = rom; updated.crc32 = info.crc; updated.thumbnailLookupSystemID = info.thumbnailLookupSystemID
                if updated.metadata == nil { updated.metadata = ROMMetadata() }
                updated.metadata?.title = info.name; updated.metadata?.year = info.year
                updated.metadata?.publisher = info.publisher; updated.metadata?.developer = info.developer; updated.metadata?.genre = info.genre
                updateROM(updated, persist: persist, silent: silent)
                return updated
                
            case .crcNotInDatabase(let crc):
                var updated = rom; updated.crc32 = crc
                if updated.metadata?.title != nil {
                    updated.metadata?.title = nil; updated.metadata?.year = nil
                    updated.metadata?.publisher = nil; updated.metadata?.developer = nil; updated.metadata?.genre = nil
                }
                updateROM(updated, persist: persist, silent: silent)
                return updated
                
            case .identificationCleared:
                var updated = rom
                if updated.metadata?.title != nil {
                    updated.metadata?.title = nil; updated.metadata?.year = nil
                    updated.metadata?.publisher = nil; updated.metadata?.developer = nil; updated.metadata?.genre = nil
                    updated.thumbnailLookupSystemID = nil
                    updateROM(updated, persist: persist, silent: silent)
                    return updated
                }
            
            case .databaseUnavailable, .noSystem, .romReadFailed: 
                return nil
        }
        return nil
    }

    func clearIdentification(for rom: ROM, persist: Bool = true) {
        var updated = rom
        if updated.metadata?.title != nil {
            updated.metadata?.title = nil; updated.metadata?.year = nil
            updated.metadata?.publisher = nil; updated.metadata?.developer = nil; updated.metadata?.genre = nil
            updated.thumbnailLookupSystemID = nil
            updateROM(updated, persist: persist)
        }
    }

    private func updateGamesXML(for rom: ROM) {
        let folder = rom.path.deletingLastPathComponent()
        let xmlPath = folder.appendingPathComponent("games.xml")
        let xml: XMLDocument; let root: XMLElement

        if FileManager.default.fileExists(atPath: xmlPath.path), let doc = try? XMLDocument(contentsOf: xmlPath, options: []) {
            xml = doc; root = doc.rootElement() ?? XMLElement(name: "gameList")
        } else {
            root = XMLElement(name: "gameList")
            xml = XMLDocument(rootElement: root); xml.version = "1.0"; xml.characterEncoding = "UTF-8"
        }

        let relPath = "./\(rom.path.lastPathComponent)"
        var gameNode = (root.children as? [XMLElement])?.first { $0.name == "game" && $0.elements(forName: "path").first?.stringValue == relPath }
        
        if let existing = gameNode { existing.setChildren(nil) }
        else { let newGame = XMLElement(name: "game"); root.addChild(newGame); gameNode = newGame }
        guard let node = gameNode else { return }

        node.addChild(XMLElement(name: "path", stringValue: relPath))
        if let title = rom.metadata?.title { node.addChild(XMLElement(name: "name", stringValue: title)) }
        if let year = rom.metadata?.year { node.addChild(XMLElement(name: "year", stringValue: year)) }
        if let publisher = rom.metadata?.publisher { node.addChild(XMLElement(name: "publisher", stringValue: publisher)) }
        if let developer = rom.metadata?.developer { node.addChild(XMLElement(name: "developer", stringValue: developer)) }
        if let genre = rom.metadata?.genre { node.addChild(XMLElement(name: "genre", stringValue: genre)) }
        if let desc = rom.metadata?.description { node.addChild(XMLElement(name: "desc", stringValue: desc)) }

        try? xml.xmlData(options: .nodePrettyPrint).write(to: xmlPath)
    }

    func markPlayed(_ rom: ROM) { var updated = rom; updated.lastPlayed = Date(); updateROM(updated) }
    func recordPlaySession(_ rom: ROM, duration: TimeInterval) {
        var updated = rom; updated.lastPlayed = Date(); updated.timesPlayed += 1; updated.totalPlaytimeSeconds += duration; updateROM(updated)
    }

    // MARK: - SwiftData Persistence

    func saveSingleROM(_ rom: ROM) { repository.saveROM(rom) }



    // 1. Used only when adding a single folder
    func saveSingleLibraryFolderBookmark(_ folder: ROMLibraryFolder) {
        _ = folder.url.startAccessingSecurityScopedResource()
        if let data = try? folder.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            // Send only this one row to the repository
            repository.saveLibraryFolders([(folder.url.path, data, folder.parentPath, folder.isPrimary)])
        }
    }

    // 2. Used only if you need to perform a full sync (e.g., after removing a folder)
    private func saveAllLibraryFolders() {
        var rows: [(String, Data, String?, Bool)] = []
        
        // Flatten your folders into the rows array
        for folder in primaryFolders {
            if let data = getBookmarkData(for: folder.url) {
                rows.append((folder.url.path, data, nil, true))
            }
        }
        for subfolders in subfolderMap.values {
            for sub in subfolders where sub.isPrimary {
                if let data = getBookmarkData(for: sub.url) {
                    rows.append((sub.url.path, data, sub.parentPath, true))
                }
            }
        }
        repository.saveLibraryFolders(rows)
    }

    // Helper to keep code clean
    private func getBookmarkData(for url: URL) -> Data? {
        _ = url.startAccessingSecurityScopedResource()
        return try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    
    private func saveSecurityScopedBookmarks() {
        var rows: [(String, Data, String?, Bool)] = []
        for folder in primaryFolders {
            _ = folder.url.startAccessingSecurityScopedResource()
            if let data = try? folder.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                rows.append((folder.url.path, data, nil, true))
            }
        }
        for (_, subfolders) in subfolderMap {
            for sub in subfolders where sub.isPrimary {
                _ = sub.url.startAccessingSecurityScopedResource()
                if let data = try? sub.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    rows.append((sub.url.path, data, sub.parentPath, true))
                }
            }
        }
        if !rows.isEmpty { repository.saveLibraryFolders(rows) }
    }

    // MARK: - Folder Add/Remove Logic
    
    private func findParentForPath(_ path: String) -> String? { primaryFolders.first { path.hasPrefix($0.url.path + "/") }?.url.path }
    
    @MainActor func discoverSubfoldersWithROMs(in primaryFolder: ROMLibraryFolder, maxDepth: Int = 2) async -> [ROMLibraryFolder] {
        await ROMScanner().findFoldersWithROMs(baseURL: primaryFolder.url, maxDepth: maxDepth).map {
            ROMLibraryFolder(url: $0, parentPath: primaryFolder.url.path, isPrimary: repository.isFolderPrimary(urlPath: $0.path))
        }
    }
    @MainActor func discoverSubfoldersWithROMsInFolder(folder: ROMLibraryFolder) async -> [ROMLibraryFolder] {
        await ROMScanner().findFoldersWithROMs(baseURL: folder.url, maxDepth: 1).map {
            ROMLibraryFolder(url: $0, parentPath: folder.url.path, isPrimary: repository.isFolderPrimary(urlPath: $0.path))
        }
    }

    @MainActor func addPrimaryFolder(url: URL, scanAfter: Bool = true) {
        guard !isInternalPath(url), !url.path.isEmpty, !isExcludedLibraryPath(url) else { return }
        guard !primaryFolders.contains(where: { $0.url.path == url.path }) else { return }

        let folder = ROMLibraryFolder(url: url, parentPath: nil, isPrimary: true)
        primaryFolders.append(folder)

        if !libraryFolders.contains(url) { libraryFolders.append(url) }
        
        // Save only this bookmark
        saveSingleLibraryFolderBookmark(folder)

        // Trigger an incremental scan for ONLY this folder
        if scanAfter { 
            Task { 
                await scanROMs(in: url, runAutomationAfter: true) 
            } 
        }
    }

    @MainActor func removePrimaryFolder(at index: Int) {
        guard index < primaryFolders.count else { return }
        let folder = primaryFolders[index]
        let folderPath = folder.url.path

        let affectedSubfolders = (subfolderMap[folderPath] ?? []).filter { !$0.isPrimary && !repository.isFolderPrimary(urlPath: $0.url.path) }
        var pathsToRemove = [folderPath]; pathsToRemove.append(contentsOf: affectedSubfolders.map { $0.url.path })

        primaryFolders.remove(at: index)
        for sub in affectedSubfolders { subfolderMap[folderPath]?.removeAll { $0.url.path == sub.url.path } }
        if subfolderMap[folderPath]?.isEmpty == true { subfolderMap.removeValue(forKey: folderPath) }

        roms.removeAll { rom in pathsToRemove.contains { rom.path.path == $0 || rom.path.path.hasPrefix($0 + "/") } }
        libraryFolders.removeAll { $0.path == folderPath || $0.path.hasPrefix(folderPath + "/") }
        repository.removeLibraryFolder(urlPath: folderPath, removeSubfolders: true)

        repository.deleteROMsByPath(pathsToRemove)
        saveSecurityScopedBookmarks(); updateCounts(); saveROMsToDatabase()
    }

    @MainActor func removeSubfolder(from primaryFolderPath: String, subfolderPath: String) {
        if repository.isFolderPrimary(urlPath: subfolderPath) { return }
        let prefix = subfolderPath.hasSuffix("/") ? subfolderPath : subfolderPath + "/"
        
        subfolderMap[primaryFolderPath]?.removeAll { $0.url.path == subfolderPath }
        if subfolderMap[primaryFolderPath]?.isEmpty == true { subfolderMap.removeValue(forKey: primaryFolderPath) }

        roms.removeAll { $0.path.path == subfolderPath || $0.path.path.hasPrefix(prefix) }
        repository.removeLibraryFolder(urlPath: subfolderPath, removeSubfolders: true)
        updateCounts(); saveROMsToDatabase()
    }

    @MainActor func addSubfolder(folder: ROMLibraryFolder) {
        guard !isInternalPath(folder.url), !isExcludedLibraryPath(folder.url), let parentPath = findParentForPath(folder.url.path) else { return }
        if subfolderMap[parentPath] == nil { subfolderMap[parentPath] = [] }
        if !subfolderMap[parentPath]!.contains(where: { $0.url.path == folder.url.path }) {
            subfolderMap[parentPath]!.append(folder)
            saveSecurityScopedBookmarks()
            Task { await scanROMs(in: folder.url) }
        }
    }



    // MARK: - File Index & Rebuild

    func shouldRescanFile(path: String, size: Int64, modTime: TimeInterval) -> Bool {
        guard let sig = fileIndex[path] else { return true }
        return sig.size != size || sig.modTime != modTime
    }
    func recordFileInIndex(path: String, size: Int64, modTime: TimeInterval) { fileIndex[path] = FileSignature(size: size, modTime: modTime) }
    private func loadFileIndexFromStorage() { fileIndex = [:] }

    func rebuildLibrary(modes: Set<RebuildOption>) async {
        if modes.contains(.boxartRebuild) { for i in 0..<roms.count { roms[i].hasBoxArt = false } }
        if modes.contains(.idRebuild) {
            for i in 0..<roms.count {
                roms[i].crc32 = nil; roms[i].thumbnailLookupSystemID = nil
                roms[i].metadata?.title = nil; roms[i].metadata?.year = nil; roms[i].metadata?.publisher = nil; roms[i].metadata?.developer = nil; roms[i].metadata?.genre = nil
            }
        }
        if modes.contains(.refresh) || modes.contains(.everything) || modes.contains(.idRebuild) {
            saveROMsToDatabase()
            let folders = primaryFolders.map { $0.url }
            for folder in folders { await scanROMs(in: folder, runAutomationAfter: folder == folders.last) }
        } else if modes.contains(.boxartRebuild) { saveROMsToDatabase() }
    }

    @MainActor func rescanLibrary(at folderURL: URL) async {
        isScanning = true
        await scanROMs(in: folderURL, runAutomationAfter: true)
        isScanning = false
    }

    @MainActor func refreshFolder(at folderURL: URL) async {
        isScanning = true; scanCancellationToken.reset()
        let folderPath = folderURL.path; let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        let existingROMs = roms.filter { $0.path.path == folderPath || $0.path.path.hasPrefix(prefix) }
        let existingPaths = Set(existingROMs.map { $0.path.path })

        let scanner = ROMScanner()
        let romFileURLs = await scanner.getROMFiles(in: folderURL) { p in DispatchQueue.main.async { self.scanProgress = p } }
        let scannedPaths = Set(romFileURLs.map { $0.path })

        let newFileURLs = romFileURLs.filter { !existingPaths.contains($0.path) }
        var newROMsToAdd: [ROM] = []
        if !newFileURLs.isEmpty {
            newROMsToAdd = await scanner.scan(urls: newFileURLs) { _ in }.map { LibraryMetadataStore.shared.mergedROM($0) }
        }

        let deletedROMs = existingROMs.filter { !scannedPaths.contains($0.path.path) }

        if !newROMsToAdd.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) { self.roms.append(contentsOf: newROMsToAdd); self.roms.sort { $0.displayName < $1.displayName } }
            repository.saveROMs(newROMsToAdd)
        }

        if !deletedROMs.isEmpty {
            let deletedIDs = Set(deletedROMs.map { $0.id })
            roms.removeAll { deletedIDs.contains($0.id) }
            repository.deleteROMs(ids: deletedROMs.map { $0.id })
            LibraryMetadataStore.shared.deleteMetadataEntries(Set(deletedROMs.map { LibraryMetadataStore.pathKey(for: $0) }))
            for path in Set(deletedROMs.map { $0.path.path }) { fileIndex.removeValue(forKey: path) }
        }

        updateCounts(); isScanning = false
    }

    @MainActor func rebuildFolder(folder: ROMLibraryFolder, option: RebuildOption) async { await rebuildLibrary(modes: [option]) }

    private func initializeLibrary() {
        migrateLegacyUserDefaultsToSwiftData()
        restoreLibraryAccess()
        loadROMsFromRepository()
        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }
        purgeROMsOutsideLibraryFolders()
        loadFileIndexFromStorage()
        updateCounts()
        
        Task {
            //Stop refreshing the library on every launch
            //await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
            //await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(library: self)
        }
    }

}

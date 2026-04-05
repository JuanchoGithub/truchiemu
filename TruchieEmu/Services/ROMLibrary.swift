import Foundation
import Combine

/// A thread-safe cancellation token that can be safely shared between MainActor and the ROMScanner actor
final class ScanCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }
    
    func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
    
    func reset() {
        lock.lock()
        _isCancelled = false
        lock.unlock()
    }
}

// MARK: - File Signature

private struct FileSignature: Codable, Hashable {
    let size: Int64
    let modTime: TimeInterval
}

// MARK: - Library Folder Model

/// Represents a folder in the library with subfolder tracking.
struct LibraryFolder: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let parentPath: String?  // nil = top-level (user directly added this folder)
    let isPrimary: Bool      // true = user explicitly added this folder
    
    /// Display name for the folder.
    var displayName: String {
        url.lastPathComponent
    }
    
    /// How many levels deep this folder is from its primary ancestor.
    var depthFromPrimary: Int {
        guard let parentPath = parentPath else { return 0 }
        let remainder = url.path.replacingOccurrences(of: parentPath + "/", with: "")
        let segments = remainder.components(separatedBy: "/").filter { !$0.isEmpty }
        return segments.count
    }
    
    /// Whether this folder is a direct child of a primary folder (level 1).
    var isLevelOneSubfolder: Bool {
        guard let parentPath = parentPath else { return false }
        return url.path.hasPrefix(parentPath + "/") && depthFromPrimary == 1
    }
    
    static func == (lhs: LibraryFolder, rhs: LibraryFolder) -> Bool {
        lhs.url.path == rhs.url.path
    }
}

/// Rebuild options for the rebuild dialog.
enum RebuildOption: String, CaseIterable, Identifiable {
    case refresh = "refresh"
    case idRebuild = "idRebuild"
    case boxartRebuild = "boxartRebuild"
    case everything = "everything"
    
    var id: String { rawValue }
    var title: String {
        switch self {
        case .refresh: return "Refresh ROMs"
        case .idRebuild: return "Rebuild Identification"
        case .boxartRebuild: return "Rebuild Boxart"
        case .everything: return "Rebuild Everything"
        }
    }
    var description: String {
        switch self {
        case .refresh: return "Scan for new or deleted ROMs"
        case .idRebuild: return "Clear all ROM identification and re-identify. Unidentified games keep their ROM name."
        case .boxartRebuild: return "Clear all boxart and re-download"
        case .everything: return "Refresh ROMs, rebuild identification, and re-download boxart"
        }
    }
    var icon: String {
        switch self {
        case .refresh: return "arrow.clockwise"
        case .idRebuild: return "fingerprint"
        case .boxartRebuild: return "photo"
        case .everything: return "gearshape.2"
        }
    }
}

// MARK: - ROM Library

@MainActor
class ROMLibrary: ObservableObject {
    
    // MARK: - Internal Directory Validation
    
    /// Path to the app\'s own Application Support directory (where cache files are stored).
    private var appInternalPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu").path
    }
    
    /// Check if a folder URL is inside the app\'s own internal directory.
    private func isInternalPath(_ url: URL) -> Bool {
        return url.path.hasPrefix(appInternalPath)
    }
    
    /// Known system Library subfolders that should never be added as ROM folders.
    private static let excludedLibraryPaths = [
        "/Library/Application Support",
        "/Library/Caches",
        "/Library/Preferences",
        "/Library/Logs",
        "/Library/Saved Application State",
        "/Library/Containers",
        "/Library/Group Containers",
        "/Library/Autosave Information",
        "/Library/Calendars",
        "/Library/Mail",
        "/Library/Messages",
        "/Library/Notes",
        "/Library/Passes",
        "/Library/Photos",
        "/Library/Safari",
        "/Library/Sounds",
        "/Library/Spelling",
        "/Library/VoiceMemos",
    ]
    
    /// Check if a folder URL is inside a macOS user Library subfolder that
    /// should never contain ROM files (e.g. Application Support, Caches).
    private func isExcludedLibraryPath(_ url: URL) -> Bool {
        Self.excludedLibraryPaths.contains { url.path.contains($0) }
    }
    
    @Published var roms: [ROM] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    private let scanCancellationToken = ScanCancellationToken()
    @Published var hasCompletedOnboarding: Bool
    /// Primary folders that the user has explicitly added (top-level).
    @Published var primaryFolders: [LibraryFolder] = []
    /// Subfolder mapping: parentPath -> [subfolders]. Only stored up to 2 levels deep.
    @Published var subfolderMap: [String: [LibraryFolder]] = [:]
    /// All flattened folder entries (primary + subfolders) for backwards compatibility.
    var allFolders: [LibraryFolder] {
        primaryFolders + subfolderMap.values.flatMap { $0 }
    }
    /// Legacy: provides URLs of primary folders for backward compatibility.
    @Published var libraryFolders: [URL] = []
    @Published var romCounts: [String: Int] = [:]
    @Published var lastChangeDate = Date()
    @Published var bezelUpdateToken: Int = 0
    var romFolderURL: URL? { libraryFolders.first }

    // SQLite persistence managed by the shared DatabaseManager.
    // The old UserDefaults keys ("saved_roms", "library_folders_bookmarks_v2", etc.)
    // are migrated once on first launch, then removed.

    // Legacy defaults still used only for the onboarding migration check.
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Legacy keys (used for migration detection only)
    private let legacyRomsKey = "saved_roms"
    private let legacyFoldersKey = "library_folders_bookmarks_v2"
    private let legacyOnboardingKey = "has_completed_onboarding"
    private let legacyIndexKey = "rom_file_index_v1"
    
    // Legacy file index for smart rescan (migrated to SQLite)
    private var fileIndex: [String: FileSignature] = [:]

    init() {
        // 0. Open the SQLite database — this is the ROOT CAUSE of data loss on restart.
        // The DatabaseManager singleton's `db` property is nil until open() is called.
        // Without this, every SQLite write silently returns (guard db != nil) and
        // every read returns empty, making the app lose all data on every launch.
        DatabaseManager.shared.open()
        
        // 1. Initialize required properties before using self
        self.hasCompletedOnboarding = DatabaseManager.shared.getBoolSetting("has_completed_onboarding", defaultValue: false)
        
        // 2. Migrate UserDefaults -> SQLite if needed (one-time)
        migrateLegacyUserDefaultsToSQLite()
        
        // 3. Load state from SQLite
        loadROMsFromDatabase()
        LibraryMetadataStore.shared.migrateLegacySidecarsIfStoreEmpty(roms: roms)
        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }
        restoreLibraryAccess()
        
        // 4. Purge orphaned ROMs that don't belong to any library folder
        purgeROMsOutsideLibraryFolders()
        
        loadFileIndexFromStorage()
        updateCounts()
    }

    // MARK: - Migration from UserDefaults to SQLite

    private func migrateLegacyUserDefaultsToSQLite() {
        let needsRomMigration = defaults.data(forKey: legacyRomsKey) != nil
        let needsFolderMigration = defaults.array(forKey: legacyFoldersKey) as? [Data] != nil || defaults.data(forKey: "rom_folder_bookmark") != nil
        let needsIndexMigration = defaults.data(forKey: legacyIndexKey) != nil
        
        guard needsRomMigration || needsFolderMigration || needsIndexMigration else { return }
        
        LoggerService.info(category: "ROMLibrary", "Starting migration from UserDefaults to SQLite")

        if needsRomMigration {
            migrateLegacyROMs()
        }

        if needsFolderMigration {
            migrateLegacyLibraryFolders()
        }

        if needsIndexMigration {
            migrateLegacyFileIndex()
        }

        LoggerService.info(category: "ROMLibrary", "Legacy UserDefaults migration complete")
    }

    private func migrateLegacyROMs() {
        guard let data = defaults.data(forKey: legacyRomsKey) else { return }
        guard let legacyRoms = try? decoder.decode([ROM].self, from: data) else {
            LoggerService.warning(category: "ROMLibrary", "Failed to decode legacy ROMs from UserDefaults — data may be corrupted")
            UserDefaults.standard.removeObject(forKey: legacyRomsKey)
            return
        }

        LoggerService.info(category: "ROMLibrary", "Migrating \(legacyRoms.count) ROMs from UserDefaults to SQLite")

        let romRows: [(String, String, String, String?, String?, Bool, Double?, Double, Int, String?, String?, Bool, String?, Bool, Bool, String, String?, String?, String?, String?, Bool)] = legacyRoms.map { rom in
            let metaJson: String? = rom.metadata.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let settingsJson: String? = (try? JSONEncoder().encode(rom.settings)).flatMap { String(data: $0, encoding: .utf8) }
            let ssPathsJson: String? = rom.screenshotPaths.isEmpty ? nil : (try? JSONEncoder().encode(rom.screenshotPaths.map { $0.path })).flatMap { String(data: $0, encoding: .utf8) }
            return (
                rom.id.uuidString,
                rom.name,
                rom.path.path,
                rom.systemID,
                rom.boxArtPath?.path,
                rom.isFavorite,
                rom.lastPlayed?.timeIntervalSince1970,
                rom.totalPlaytimeSeconds,
                rom.timesPlayed,
                rom.selectedCoreID,
                rom.customName,
                rom.useCustomCore,
                metaJson,
                rom.isBios,
                rom.isHidden,
                rom.category,
                rom.crc32,
                rom.thumbnailLookupSystemID,
                ssPathsJson,
                settingsJson,
                rom.crc32 != nil
            )
        }

        DatabaseManager.shared.migrateROMsFromUserDefaults(romRows)
        UserDefaults.standard.removeObject(forKey: legacyRomsKey)
        LoggerService.info(category: "ROMLibrary", "Removed legacy UserDefaults key: \(legacyRomsKey)")
    }

    private func migrateLegacyLibraryFolders() {
        // Try v2 format first
        if let bookmarks = defaults.array(forKey: legacyFoldersKey) as? [Data] {
            var urlPathPairs: [(String, Data)] = []
            for data in bookmarks {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                    urlPathPairs.append((url.path, data))
                }
            }
            DatabaseManager.shared.migrateLibraryFoldersFromUserDefaults(urlPathPairs)
            LoggerService.info(category: "ROMLibrary", "Migrated \(urlPathPairs.count) library folders from UserDefaults v2")
            UserDefaults.standard.removeObject(forKey: legacyFoldersKey)
        }

        // Try legacy v1 format
        if let legacyData = defaults.data(forKey: "rom_folder_bookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: legacyData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                DatabaseManager.shared.migrateLibraryFoldersFromUserDefaults([(url.path, legacyData)])
                LoggerService.info(category: "ROMLibrary", "Migrated legacy library folder from UserDefaults v1")
                UserDefaults.standard.removeObject(forKey: "rom_folder_bookmark")
            }
        }
    }

    private func migrateLegacyFileIndex() {
        guard let data = defaults.data(forKey: legacyIndexKey) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var indexEntries: [(String, Int64, Double)] = []
        for (path, sigDict) in json {
            if let sig = sigDict as? [String: Any],
               let size = sig["size"] as? Int64,
               let modTime = sig["modTime"] as? Double {
                indexEntries.append((path, size, modTime))
            }
        }

        if !indexEntries.isEmpty {
            DatabaseManager.shared.migrateFileIndexEntries(indexEntries)
            LoggerService.info(category: "ROMLibrary", "Migrated \(indexEntries.count) file index entries")
        }

        UserDefaults.standard.removeObject(forKey: legacyIndexKey)
    }

    // MARK: - Migration of onboarding flag

    private func migrateOnboardingIfNeeded() {
        // If the onboarding flag exists in UserDefaults but not in SQLite, migrate it
        if defaults.bool(forKey: legacyOnboardingKey) && !DatabaseManager.shared.getBoolSetting("has_completed_onboarding", defaultValue: false) {
            DatabaseManager.shared.setBoolSetting("has_completed_onboarding", value: true)
            UserDefaults.standard.removeObject(forKey: legacyOnboardingKey)
        }
    }

    // MARK: - Counts

    func updateCounts() {
        var counts: [String: Int] = [:]
        counts["all"] = roms.filter { !$0.isHidden }.count
        counts["favorites"] = roms.filter { $0.isFavorite && !$0.isHidden }.count
        counts["recent"] = roms.filter { $0.lastPlayed != nil && !$0.isHidden }.count
        counts["hidden"] = roms.filter { $0.isHidden }.count
        
        let grouped = Dictionary(grouping: roms) { $0.systemID ?? "unknown" }
        for (sysID, list) in grouped {
            counts[sysID] = list.filter { !$0.isHidden }.count
        }
        self.romCounts = counts
        self.lastChangeDate = Date()
    }

    /// Purge any ROMs whose path is not inside a user-assigned library folder.
    /// This handles the case where ROMs were added from excluded Library paths
    /// (e.g., RetroArch configs) and should be cleaned up on startup.
    private func purgeROMsOutsideLibraryFolders() {
        // Build set of valid library folder paths
        let validPaths = primaryFolders.map { $0.url.path } + subfolderMap.values.flatMap { $0.map { $0.url.path } }
        
        guard !validPaths.isEmpty else {
            // No folders at all? Clean up everything
            if !roms.isEmpty {
                let count = roms.count
                let allPaths = roms.map { $0.path.path }
                roms.removeAll()
                DatabaseManager.shared.deleteROMsByPath(allPaths)
                fileIndex.removeAll()
                LoggerService.info(category: "ROMLibrary", "No library folders found. Purged \(count) orphaned ROM(s).")
            }
            return
        }
        
        let orphans = roms.filter { rom in
            let romPath = rom.path.path
            return !validPaths.contains { romPath == $0 || romPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        
        guard !orphans.isEmpty else { return }
        
        LoggerService.info(category: "ROMLibrary", "Found \(orphans.count) orphaned ROM(s) outside library folders. Purging.")
        roms.removeAll { orphan in orphans.contains { $0.id == orphan.id } }
        DatabaseManager.shared.deleteROMsByPath(orphans.map { $0.path.path })
        saveROMsToDatabase()
    }

    // MARK: - Onboarding & Library Folders

    func completeOnboarding(folderURL: URL) {
        addPrimaryFolder(url: folderURL)
        hasCompletedOnboarding = true
        DatabaseManager.shared.setBoolSetting("has_completed_onboarding", value: true)
    }

    func addLibraryFolder(url: URL) {
        addPrimaryFolder(url: url)
    }

    func removeLibraryFolder(at index: Int) {
        guard index < libraryFolders.count else { return }
        let url = libraryFolders[index]
        
        // Build a proper prefix that won't false-match sibling folders
        // e.g. "/ROMs" must NOT match "/ROMs2" — we append a trailing "/"
        // so the prefix requires a path separator after the folder name.
        let folderPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        
        // Count ROMs that will be removed before filtering
        let removedROMs = roms.filter { $0.path.path.hasPrefix(folderPath) || $0.path.path == url.path }
        let removedCount = removedROMs.count
        
        LoggerService.info(category: "ROMLibrary", "Removing library folder: \(url.path) (\(removedCount) ROM(s) will be purged)")
        
        libraryFolders.remove(at: index)
        saveSecurityScopedBookmarks()
        
        // Remove ROMs that are descendants of this folder
        roms.removeAll { $0.path.path.hasPrefix(folderPath) || $0.path.path == url.path }

        // Delete the removed ROMs from the database so they don't reappear on restart
        DatabaseManager.shared.deleteROMsByPath(removedROMs.map { $0.path.path })

        // If no library folders remain, purge ALL orphaned ROMs from the database
        // that don't belong to any user-assigned folder
        if libraryFolders.isEmpty {
            let orphanedROMs = roms
            let orphanedPaths = orphanedROMs.map { $0.path.path }
            roms.removeAll()
            DatabaseManager.shared.deleteROMsByPath(orphanedPaths)
            // Wipe entire file index
            fileIndex.removeAll()
            LoggerService.info(category: "ROMLibrary", "No library folders remain. Purged \(orphanedROMs.count) orphaned ROM(s).")
        } else {
            // Clean up file index entries for removed ROMs
            let removedPaths = Set(removedROMs.map { $0.path.path })
            for path in removedPaths {
                fileIndex.removeValue(forKey: path)
            }
            if !fileIndex.isEmpty {
                saveFileIndexToStorage()
            }
        }
        
        // Clean up orphaned metadata entries from SQLite
        for rom in removedROMs {
            let key = LibraryMetadataStore.pathKey(for: rom)
            DatabaseManager.shared.deleteMetadataEntry(key)
        }
        
        updateCounts()
        saveROMsToDatabase()
        
        // Clean up orphaned ScummVM extracted caches
        cleanupScummVMCaches()
    }

    func scanROMs(in folder: URL, runAutomationAfter: Bool = true) async {
        // Pause scanning if a game is currently running — background I/O and
        // network activity during gameplay degrade performance and cause lag.
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.debug(category: "ROMLibrary", "Deferring ROM scan — game is running")
            return
        }
        
        isScanning = true
        scanProgress = 0
        scanCancellationToken.reset()
        let scanner = ROMScanner()
        let found = await scanner.scan(folder: folder, cancellationToken: scanCancellationToken) { progress in
            Task { @MainActor in self.scanProgress = progress }
        }
        
        let detectedSystems = Set(found.compactMap { $0.systemID })
        Task { await scanner.downloadDatsForDiscoveredSystems(detectedSystems) }
        
        // Merge: keep existing metadata, add new
        var existing = Dictionary(uniqueKeysWithValues: roms.map { ($0.path.path, $0) })
        for rom in found where existing[rom.path.path] == nil {
            existing[rom.path.path] = rom
        }
        
        let ignored = await scanner.getIgnoredFiles(in: folder)
        let folderPath = folder.path
        roms = existing.values.filter { rom in
            if rom.path.path.hasPrefix(folderPath) {
                return !ignored.contains(rom.path.standardized.path)
            }
            return true
        }.sorted { $0.displayName < $1.displayName }
        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }
        updateCounts()
        isScanning = false
        saveROMsToDatabase()
        
        // Clean up orphaned ScummVM extracted caches
        cleanupScummVMCaches()
        
        if runAutomationAfter {
            // Only run post-scan automation when no game is running.
            // These tasks (identification, box-art downloads, metadata sync) are
            // network- and I/O-heavy and should not execute during gameplay.
            guard !RunningGamesTracker.shared.isGameRunning else {
                LoggerService.debug(category: "ROMLibrary", "Skipping post-scan automation — game is running")
                return
            }
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
            await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(library: self)
        }
    }
    
    /// Clean up ScummVM extracted caches for games no longer in the library.
    private func cleanupScummVMCaches() {
        let activeScummVMPaths = Set(roms.filter { $0.systemID == "scummvm" }.map { $0.path.path })
        ScummVMCacheManager.cleanupOrphanedCaches(activeScummvmPaths: activeScummVMPaths)
    }

    func fullRescan() async {
        isScanning = true
        scanProgress = 0
        
        roms = []
        fileIndex = [:]
        saveROMsToDatabase()
        saveFileIndexToStorage()
        
        for (i, folder) in libraryFolders.enumerated() {
            if !isScanning { break }
            let last = i == libraryFolders.count - 1
            await scanROMs(in: folder, runAutomationAfter: last)
        }
        
        isScanning = false
    }

    func stopScan() {
        scanCancellationToken.cancel()
        isScanning = false
    }

    func updateROM(_ rom: ROM) {
        if let idx = roms.firstIndex(where: { $0.id == rom.id }) {
            let oldBezel = roms[idx].settings.bezelFileName
            objectWillChange.send()
            roms[idx] = rom
            if oldBezel != rom.settings.bezelFileName {
                bezelUpdateToken += 1
            }
            LibraryMetadataStore.shared.persist(rom: rom)
            updateGamesXML(for: rom)
            updateCounts()
            saveROMsToDatabase()
        }
    }

    @discardableResult
    func identifyROM(_ rom: ROM) async -> ROMIdentifyResult {
        var working = rom
        if let sid = rom.systemID,
           let c = ROMIdentifierService.shared.computeCRC(for: rom.path, systemID: sid) {
            working.crc32 = c
        }

        let result = await ROMIdentifierService.shared.identify(rom: rom)
        switch result {
        case .identified(let info), .identifiedFromName(let info):
            var updated = working
            updated.crc32 = info.crc
            updated.thumbnailLookupSystemID = info.thumbnailLookupSystemID
            if updated.metadata == nil { updated.metadata = ROMMetadata() }
            updated.metadata?.title = info.name
            updated.metadata?.year = info.year
            updated.metadata?.publisher = info.publisher
            updated.metadata?.developer = info.developer
            updated.metadata?.genre = info.genre
            updateROM(updated)
        case .crcNotInDatabase(let crc):
            var updated = working
            updated.crc32 = crc
            updateROM(updated)
        default:
            if working.crc32 != rom.crc32 {
                updateROM(working)
            }
        }
        return result
    }

    private func updateGamesXML(for rom: ROM) {
        let folder = rom.path.deletingLastPathComponent()
        let xmlPath = folder.appendingPathComponent("games.xml")
        
        let fm = FileManager.default
        let xml: XMLDocument
        let root: XMLElement
        
        if fm.fileExists(atPath: xmlPath.path),
           let doc = try? XMLDocument(contentsOf: xmlPath, options: []) {
            xml = doc
            if let existingRoot = doc.rootElement() {
                root = existingRoot
            } else {
                root = XMLElement(name: "gameList")
                xml.setRootElement(root)
            }
        } else {
            root = XMLElement(name: "gameList")
            xml = XMLDocument(rootElement: root)
            xml.version = "1.0"
            xml.characterEncoding = "UTF-8"
        }
        
        let filename = rom.path.lastPathComponent
        let relPath = "./\(filename)"
        
        var gameNode: XMLElement?
        if let children = root.children as? [XMLElement] {
            gameNode = children.first { node in
                node.name == "game" && 
                node.elements(forName: "path").first?.stringValue == relPath
            }
        }
        
        if let existing = gameNode {
            existing.setChildren(nil)
        } else {
            let newGame = XMLElement(name: "game")
            root.addChild(newGame)
            gameNode = newGame
        }
        
        guard let node = gameNode else { return }
        
        node.addChild(XMLElement(name: "path", stringValue: relPath))
        if let title = rom.metadata?.title { node.addChild(XMLElement(name: "name", stringValue: title)) }
        if let year = rom.metadata?.year { node.addChild(XMLElement(name: "year", stringValue: year)) }
        if let publisher = rom.metadata?.publisher { node.addChild(XMLElement(name: "publisher", stringValue: publisher)) }
        if let developer = rom.metadata?.developer { node.addChild(XMLElement(name: "developer", stringValue: developer)) }
        if let genre = rom.metadata?.genre { node.addChild(XMLElement(name: "genre", stringValue: genre)) }
        if let desc = rom.metadata?.description { node.addChild(XMLElement(name: "desc", stringValue: desc)) }
        
        let data = xml.xmlData(options: .nodePrettyPrint)
        try? data.write(to: xmlPath)
    }

    func markPlayed(_ rom: ROM) {
        var updated = rom
        updated.lastPlayed = Date()
        updateROM(updated)
    }

    func recordPlaySession(_ rom: ROM, duration: TimeInterval) {
        var updated = rom
        updated.lastPlayed = Date()
        updated.timesPlayed += 1
        updated.totalPlaytimeSeconds += duration
        updateROM(updated)
    }

    // MARK: - SQLite Persistence

    /// Persist the current ROMs array to the SQLite database.
    func saveROMsToDatabase() {
        // We do a bulk upsert — this is fast enough for typical library sizes.
        // For very large libraries (10k+ ROMs), could diff and only update changed rows.
        let romRows: [(id: String, name: String, path: String, systemID: String?, boxArtPath: String?, isFavorite: Bool, lastPlayed: Double?, totalPlaytime: Double, timesPlayed: Int, selectedCoreID: String?, customName: String?, useCustomCore: Bool, metadataJSON: String?, isBios: Bool, isHidden: Bool, category: String, crc32: String?, thumbnailSystemID: String?, screenshotPathsJSON: String?, settingsJSON: String?, isIdentified: Bool)] = roms.map { rom in
            let metaJSON: String? = rom.metadata.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let settingsJSON: String? = (try? JSONEncoder().encode(rom.settings)).flatMap { String(data: $0, encoding: .utf8) }
            let ssJSON: String? = rom.screenshotPaths.isEmpty ? nil : (try? JSONEncoder().encode(rom.screenshotPaths.map { $0.path })).flatMap { String(data: $0, encoding: .utf8) }
            return (
                rom.id.uuidString,
                rom.name,
                rom.path.path,
                rom.systemID,
                rom.boxArtPath?.path,
                rom.isFavorite,
                rom.lastPlayed?.timeIntervalSince1970,
                rom.totalPlaytimeSeconds,
                rom.timesPlayed,
                rom.selectedCoreID,
                rom.customName,
                rom.useCustomCore,
                metaJSON,
                rom.isBios,
                rom.isHidden,
                rom.category,
                rom.crc32,
                rom.thumbnailLookupSystemID,
                ssJSON,
                settingsJSON,
                rom.crc32 != nil
            )
        }
        DatabaseManager.shared.saveROMs(romRows)
    }

    /// Load ROMs from the SQLite database.
    private func loadROMsFromDatabase() {
        roms = DatabaseManager.shared.loadROMs()
    }

    /// Save all primary folders with their bookmarks to the database.
    /// This also persists any subfolders that have been stored separately.
    private func saveSecurityScopedBookmarks() {
        var bookmarkRows: [DatabaseManager.LibraryFolderRow] = []
        var failedPaths: [String] = []
        
        // Save primary folders
        for folder in primaryFolders {
            _ = folder.url.startAccessingSecurityScopedResource()
            if let data = try? folder.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                bookmarkRows.append((folder.url.path, data, nil, true))
            } else {
                LoggerService.warning(category: "ROMLibrary", "Bookmark creation failed for \(folder.url.path), saving via path fallback")
                failedPaths.append(folder.url.path)
            }
        }
        
        // Save subfolders that were added as primary independently
        for (_, subfolders) in subfolderMap {
            for subfolder in subfolders where subfolder.isPrimary {
                _ = subfolder.url.startAccessingSecurityScopedResource()
                if let data = try? subfolder.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarkRows.append((subfolder.url.path, data, subfolder.parentPath, true))
                } else {
                    failedPaths.append(subfolder.url.path)
                }
            }
        }
        
        // Handle failed bookmarks
        for path in failedPaths {
            let url = URL(fileURLWithPath: path)
            if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                // Find if this is a primary folder or subfolder
                if let pf = primaryFolders.first(where: { $0.url.path == path }) {
                    bookmarkRows.append((path, data, nil, true))
                } else {
                    // It's a subfolder — find its parent
                    let parentPath = findParentForPath(path)
                    bookmarkRows.append((path, data, parentPath, true))
                }
            } else {
                LoggerService.warning(category: "ROMLibrary", "Bookmark creation failed completely for \(path)")
                let parentPath = findParentForPath(path)
                bookmarkRows.append((path, Data([0x00, 0x00, 0x00, 0x00]), parentPath, true))
            }
        }
        
        // Save everything in one combined operation
        if !bookmarkRows.isEmpty {
            DatabaseManager.shared.saveLibraryFolders(bookmarkRows)
        }
    }

    // MARK: - Subfolder Management
    
    /// Find the primary folder that contains the given path.
    private func findParentForPath(_ path: String) -> String? {
        for primary in primaryFolders {
            if path.hasPrefix(primary.url.path + "/") {
                return primary.url.path
            }
        }
        return nil
    }
    
    /// Discover subfolders with ROMs within a primary folder (up to 2 levels deep).
    /// Returns folders that contain at least one ROM file.
    @MainActor
    func discoverSubfoldersWithROMs(in primaryFolder: LibraryFolder, maxDepth: Int = 2) async -> [LibraryFolder] {
        let scanner = ROMScanner()
        return await scanner.findFoldersWithROMs(
            baseURL: primaryFolder.url,
            maxDepth: maxDepth
        ).map { url in
            LibraryFolder(
                url: url,
                parentPath: primaryFolder.url.path,
                isPrimary: DatabaseManager.shared.isFolderPrimary(urlPath: url.path)
            )
        }
    }
    
    /// Discover immediate child folders with ROMs for a given folder.
    /// Used by SubfolderRow to discover its direct children only.
    @MainActor
    func discoverSubfoldersWithROMsInFolder(folder: LibraryFolder) async -> [LibraryFolder] {
        let scanner = ROMScanner()
        return await scanner.findFoldersWithROMs(
            baseURL: folder.url,
            maxDepth: 1
        ).map { url in
            LibraryFolder(
                url: url,
                parentPath: folder.url.path,
                isPrimary: DatabaseManager.shared.isFolderPrimary(urlPath: url.path)
            )
        }
    }
    
    /// Add a primary folder to the library. If the folder is already tracked as a subfolder,
    /// it will be promoted to primary (independent) status.
    @MainActor
    func addPrimaryFolder(url: URL, scanAfter: Bool = true) {
        guard !isInternalPath(url), !url.path.isEmpty else { return }
        guard !isExcludedLibraryPath(url) else {
            LoggerService.warning(category: "ROMLibrary", "Refused to add excluded Library path: \(url.path)")
            return
        }
        
        // Check if this folder is already a primary folder
        if primaryFolders.contains(where: { $0.url.path == url.path }) {
            LoggerService.info(category: "ROMLibrary", "Folder already exists as primary: \(url.path)")
            return
        }
        
        // If this path exists as a subfolder under another primary, promote it
        var parentPathOfSubfolder: String? = nil
        for (parentPath, subfolders) in subfolderMap {
            if subfolders.contains(where: { $0.url.path == url.path }) {
                parentPathOfSubfolder = parentPath
                break
            }
        }
        
        let folder = LibraryFolder(url: url, parentPath: parentPathOfSubfolder, isPrimary: true)
        primaryFolders.append(folder)
        
        // If it was a subfolder, mark it as primary in the DB
        if let oldParentPath = parentPathOfSubfolder {
            DatabaseManager.shared.markFolderAsPrimary(urlPath: url.path, parentPath: oldParentPath)
            // Update the subfolder in the map
            if let idx = subfolderMap[oldParentPath]?.firstIndex(where: { $0.url.path == url.path }) {
                subfolderMap[oldParentPath]?[idx] = folder
            }
        }
        
        // Update legacy libraryFolders for backward compatibility
        if !libraryFolders.contains(url) {
            libraryFolders.append(url)
        }
        
        saveSecurityScopedBookmarks()
        
        if scanAfter {
            Task { await scanROMs(in: url) }
        }
    }
    
    /// Remove a primary folder and all its subfolder-derived entries.
    /// If a subfolder was independently added as primary, it will be preserved.
    @MainActor
    func removePrimaryFolder(at index: Int) {
        guard index < primaryFolders.count else { return }
        let folder = primaryFolders[index]
        let folderPath = folder.url.path
        let folderPathPrefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        
        LoggerService.info(category: "ROMLibrary", "Removing primary folder: \(folderPath)")
        
        // Find which subfolders will be affected (those not independently primary)
        let affectedSubfolders = (subfolderMap[folderPath] ?? []).filter { subfolder in
            !subfolder.isPrimary && !DatabaseManager.shared.isFolderPrimary(urlPath: subfolder.url.path)
        }
        
        // Build list of all paths to remove from library
        var pathsToRemove = [folderPath]
        pathsToRemove.append(contentsOf: affectedSubfolders.map { $0.url.path })
        
        // Count ROMs that will be removed (only from paths that are being fully removed)
        let removedROMs = roms.filter { rom in
            let romPath = rom.path.path
            return pathsToRemove.contains { romPath == $0 || romPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        let removedCount = removedROMs.count
        
        // Remove primary folder from in-memory state
        primaryFolders.remove(at: index)
        
        // Remove affected subfolders from in-memory state
        for subfolder in affectedSubfolders {
            if let idx = subfolderMap[folderPath]?.firstIndex(where: { $0.url.path == subfolder.url.path }) {
                subfolderMap[folderPath]?.remove(at: idx)
            }
        }
        if subfolderMap[folderPath]?.isEmpty == true {
            subfolderMap.removeValue(forKey: folderPath)
        }
        
        // Remove ROMs
        roms.removeAll { rom in
            let romPath = rom.path.path
            return pathsToRemove.contains { romPath == $0 || romPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        
        // Update legacy libraryFolders
        libraryFolders.removeAll { $0.path == folderPath || $0.path.hasPrefix(folderPathPrefix) }
        
        // Persist: remove from DB (removes folder and all subfolder entries that have this as parent)
        DatabaseManager.shared.removeLibraryFolder(urlPath: folderPath, removeSubfolders: true)
        
        // Delete ROMs from database
        if !removedROMs.isEmpty {
            DatabaseManager.shared.deleteROMsByPath(removedROMs.map { $0.path.path })
            
            // Clean up file index
            for path in Set(removedROMs.map { $0.path.path }) {
                fileIndex.removeValue(forKey: path)
            }
            if !fileIndex.isEmpty {
                saveFileIndexToStorage()
            }
            
            // Clean up orphaned metadata
            for rom in removedROMs {
                let key = LibraryMetadataStore.pathKey(for: rom)
                DatabaseManager.shared.deleteMetadataEntry(key)
            }
            LoggerService.info(category: "ROMLibrary", "Purged \(removedCount) ROM(s) and associated metadata")
        }
        
        // If no primary folders remain, purge ALL orphaned ROMs from the database
        if primaryFolders.isEmpty && subfolderMap.isEmpty {
            let orphanedROMs = roms
            let orphanedPaths = orphanedROMs.map { $0.path.path }
            roms.removeAll()
            DatabaseManager.shared.deleteROMsByPath(orphanedPaths)
            fileIndex.removeAll()
            LoggerService.info(category: "ROMLibrary", "No primary folders remain. Purged \(orphanedROMs.count) orphaned ROM(s).")
        }
        
        // Re-persist remaining folders (subfolders that were independently added are still in DB,
        // but we need to re-save the full state to ensure consistency)
        saveSecurityScopedBookmarks()
        
        updateCounts()
        saveROMsToDatabase()
        cleanupScummVMCaches()
    }
    
    /// Remove a subfolder from a primary folder (without removing the primary folder itself).
    /// This only works for subfolders that were NOT independently added as primary.
    @MainActor
    func removeSubfolder(from primaryFolderPath: String, subfolderPath: String) {
        // Check if the subfolder is independently primary
        if DatabaseManager.shared.isFolderPrimary(urlPath: subfolderPath) {
            LoggerService.info(category: "ROMLibrary", "Cannot remove subfolder \(subfolderPath) — it was independently added as primary. Remove it from primary folders instead.")
            return
        }
        
        let subfolderPathPrefix = subfolderPath.hasSuffix("/") ? subfolderPath : subfolderPath + "/"
        
        // Find and remove affected ROMs
        let removedROMs = roms.filter { rom in
            let romPath = rom.path.path
            return romPath == subfolderPath || romPath.hasPrefix(subfolderPathPrefix)
        }
        
        // Remove from in-memory subfolder map
        subfolderMap[primaryFolderPath]?.removeAll { $0.url.path == subfolderPath }
        if subfolderMap[primaryFolderPath]?.isEmpty == true {
            subfolderMap.removeValue(forKey: primaryFolderPath)
        }
        
        // Remove ROMs
        let removedIDs = Set(removedROMs.map { $0.id })
        roms.removeAll { removedIDs.contains($0.id) }
        
        // Remove from DB
        DatabaseManager.shared.removeLibraryFolder(urlPath: subfolderPath, removeSubfolders: false)
        
        // Delete ROMs from database
        if !removedROMs.isEmpty {
            DatabaseManager.shared.deleteROMsByPath(removedROMs.map { $0.path.path })
            
            for path in Set(removedROMs.map { $0.path.path }) {
                fileIndex.removeValue(forKey: path)
            }
            if !fileIndex.isEmpty {
                saveFileIndexToStorage()
            }
            for rom in removedROMs {
                let key = LibraryMetadataStore.pathKey(for: rom)
                DatabaseManager.shared.deleteMetadataEntry(key)
            }
            LoggerService.info(category: "ROMLibrary", "Purged \(removedROMs.count) ROM(s) from subfolder \(subfolderPath)")
        }
        
        updateCounts()
        saveROMsToDatabase()
        cleanupScummVMCaches()
    }
    
    /// Refresh a specific folder (check for new/deleted ROMs only).
    @MainActor
    func refreshFolder(at url: URL) async {
        LoggerService.info(category: "ROMLibrary", "Refreshing folder: \(url.path)")
        await rescanLibrary(at: url)
    }
    
    /// Rebuild folder with the specified option.
    @MainActor
    func rebuildFolder(folder: LibraryFolder, option: RebuildOption) async {
        let folderURL = folder.url
        let folderPath = folderURL.path
        
        // Build prefix for matching ROMs in this folder tree
        let folderPathPrefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        
        switch option {
        case .refresh:
            // Just scan for new/deleted ROMs
            await refreshFolder(at: folderURL)
            
        case .idRebuild:
            // Clear identification for all ROMs in this folder tree, then re-identify
            LoggerService.info(category: "ROMLibrary", "Rebuilding identification for folder: \(folderPath)")
            
            let romsToReidentify = roms.filter { rom in
                rom.path.path == folderPath || rom.path.path.hasPrefix(folderPathPrefix)
            }
            
            // Clear identification but keep the ROM
            for rom in romsToReidentify {
                var updated = rom
                updated.crc32 = nil
                updated.thumbnailLookupSystemID = nil
                updated.metadata?.title = nil
                updated.metadata?.year = nil
                updated.metadata?.publisher = nil
                updated.metadata?.developer = nil
                updated.metadata?.genre = nil
                updated.metadata?.description = nil
                // Name stays as the ROM file name (displayName)
                updateROM(updated)
            }
            
            // Re-scan to get fresh ROM list
            await refreshFolder(at: folderURL)
            
            // Re-identify all ROMs in the folder
            let romsInFolder = roms.filter { rom in
                rom.path.path == folderPath || rom.path.path.hasPrefix(folderPathPrefix)
            }
            
            LoggerService.info(category: "ROMLibrary", "Re-identifying \(romsInFolder.count) ROM(s)")
            for rom in romsInFolder {
                _ = await identifyROM(rom)
            }
            
        case .boxartRebuild:
            // Clear boxart for all ROMs in this folder tree, then re-download
            LoggerService.info(category: "ROMLibrary", "Rebuilding boxart for folder: \(folderPath)")
            
            let romsToReboxart = roms.filter { rom in
                rom.path.path == folderPath || rom.path.path.hasPrefix(folderPathPrefix)
            }
            
            // Clear boxart
            for rom in romsToReboxart {
                var updated = rom
                updated.boxArtPath = nil
                updateROM(updated)
            }
            
            // Re-resolve boxart
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
            
        case .everything:
            // Refresh + ID Rebuild + Boxart Rebuild
            LoggerService.info(category: "ROMLibrary", "Rebuilding everything for folder: \(folderPath)")
            
            // Clear identification and boxart
            let romsToClear = roms.filter { rom in
                rom.path.path == folderPath || rom.path.path.hasPrefix(folderPathPrefix)
            }
            
            for rom in romsToClear {
                var updated = rom
                updated.crc32 = nil
                updated.thumbnailLookupSystemID = nil
                updated.boxArtPath = nil
                updated.metadata?.title = nil
                updated.metadata?.year = nil
                updated.metadata?.publisher = nil
                updated.metadata?.developer = nil
                updated.metadata?.genre = nil
                updated.metadata?.description = nil
                updateROM(updated)
            }
            
            // Re-scan
            await refreshFolder(at: folderURL)
            
            // Re-identify
            let romsInFolder = roms.filter { rom in
                rom.path.path == folderPath || rom.path.path.hasPrefix(folderPathPrefix)
            }
            
            LoggerService.info(category: "ROMLibrary", "Re-identifying \(romsInFolder.count) ROM(s)")
            for rom in romsInFolder {
                _ = await identifyROM(rom)
            }
            
            // Re-download boxart
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
        }
    }

    private func restoreLibraryAccess() {
        let folderEntries = DatabaseManager.shared.loadLibraryFolderEntries()
        
        // If no folder entries found, try fallback
        if folderEntries.isEmpty {
            let rawPaths = DatabaseManager.shared.loadLibraryFolderPaths()
            if !rawPaths.isEmpty {
                LoggerService.warning(category: "ROMLibrary", "loadLibraryFolderEntries returned 0; falling back to \(rawPaths.count) raw folder paths")
                for path in rawPaths {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: path) {
                        _ = url.startAccessingSecurityScopedResource()
                        libraryFolders.append(url)
                    }
                }
            }
            if !libraryFolders.isEmpty {
                hasCompletedOnboarding = true
            }
            return
        }
        
        // Reconstruct primary folders and subfolder map from database entries
        var resolvedPrimaryFolders: [LibraryFolder] = []
        var resolvedSubfolderMap: [String: [LibraryFolder]] = [:]
        var resolvedLibraryURLs: [URL] = []
        var failedCount = 0
        
        for (urlPath, bookmarkData, parentPath, isPrimary) in folderEntries {
            var resolvedURL: URL?
            
            // Try resolving with security scope first
            var stale: Bool = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                resolvedURL = url
            } else {
                // Try without security scope as fallback
                stale = false
                if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    _ = url.startAccessingSecurityScopedResource()
                    resolvedURL = url
                } else {
                    // Both bookmark resolution methods failed — raw path fallback
                    LoggerService.warning(category: "ROMLibrary", "Bookmark failed to resolve for \(urlPath), using raw path")
                    failedCount += 1
                    let fallbackURL = URL(fileURLWithPath: urlPath)
                    if FileManager.default.fileExists(atPath: urlPath) {
                        _ = fallbackURL.startAccessingSecurityScopedResource()
                        resolvedURL = fallbackURL
                    }
                }
            }
            
            guard let url = resolvedURL else { continue }
            
            // Filter out excluded Library paths (e.g. RetroArch config folders)
            if isExcludedLibraryPath(url) {
                LoggerService.info(category: "ROMLibrary", "Removing excluded Library path from library: \(urlPath)")
                DatabaseManager.shared.removeLibraryFolder(urlPath: urlPath, removeSubfolders: true)
                continue
            }
            
            let folder = LibraryFolder(url: url, parentPath: parentPath, isPrimary: isPrimary)
            
            if isPrimary && parentPath == nil {
                resolvedPrimaryFolders.append(folder)
            } else if parentPath != nil {
                // Subfolder (whether primary or discovered)
                if resolvedSubfolderMap[parentPath!] == nil {
                    resolvedSubfolderMap[parentPath!] = []
                }
                resolvedSubfolderMap[parentPath!]?.append(folder)
            }
            
            resolvedLibraryURLs.append(url)
        }
        
        primaryFolders = resolvedPrimaryFolders.sorted { $0.url.path < $1.url.path }
        subfolderMap = resolvedSubfolderMap
        libraryFolders = resolvedLibraryURLs
        
        // Update onboarding flag
        if !libraryFolders.isEmpty {
            hasCompletedOnboarding = true
        }
        
        // If some bookmarks failed, persist fresh bookmarks
        if failedCount > 0 {
            LoggerService.warning(category: "ROMLibrary", "\(failedCount) bookmarks stale; persisting fresh bookmarks")
            saveSecurityScopedBookmarks()
        }
    }

    private func loadFileIndexFromStorage() {
        let rawIndex = DatabaseManager.shared.loadFileIndex()
        fileIndex = rawIndex.mapValues { FileSignature(size: $0.size, modTime: $0.modTime) }
    }

    private func saveFileIndexToStorage() {
        DatabaseManager.shared.saveFileIndex(fileIndex.mapValues { (size: $0.size, modTime: $0.modTime) })
    }

    func rescanLibrary(at url: URL) async {
        isScanning = true
        scanProgress = 0
        scanCancellationToken.reset()

        let fm = FileManager.default
        let scanner = ROMScanner()
        
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                                             options: [.skipsHiddenFiles]) else { isScanning = false; return }

        var candidates: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), vals.isRegularFile == true {
                candidates.append(fileURL)
            }
        }

        var newIndex: [String: FileSignature] = [:]
        var changed: [URL] = []
        for u in candidates {
            let path = u.path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let mod = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let sig = FileSignature(size: size, modTime: mod)
            newIndex[path] = sig
            if fileIndex[path] != sig { changed.append(u) }
        }

        let folderPath = url.path
        let currentPaths = Set(candidates.map { $0.path })
        let romsInThisFolder = roms.filter { $0.path.path.hasPrefix(folderPath) }
        let romPathsInThisFolder = Set(romsInThisFolder.map { $0.path.path })
        let deletedPaths = romPathsInThisFolder.subtracting(currentPaths)
        if !deletedPaths.isEmpty {
            roms.removeAll { deletedPaths.contains($0.path.path) }
        }

        let imported = await scanner.scan(urls: changed) { p in
            Task { @MainActor in self.scanProgress = p }
        }

        let detectedSystems = Set(imported.compactMap { $0.systemID })
        Task { await scanner.downloadDatsForDiscoveredSystems(detectedSystems) }

        var byPath = Dictionary(uniqueKeysWithValues: roms.map { ($0.path.path, $0) })
        for r in imported { byPath[r.path.path] = r }
        
        let ignored = await scanner.getIgnoredFiles(in: url)
        roms = byPath.values.filter { rom in
            if rom.path.path.hasPrefix(folderPath) {
                return !ignored.contains(rom.path.standardized.path)
            }
            return true
        }.sorted { $0.displayName < $1.displayName }

        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }

        fileIndex = newIndex
        saveFileIndexToStorage()
        saveROMsToDatabase()

        isScanning = false
        cleanupScummVMCaches()
        await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
        await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(library: self)
    }
    
}

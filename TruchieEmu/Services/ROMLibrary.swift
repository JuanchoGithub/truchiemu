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
    
    @Published var roms: [ROM] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    private let scanCancellationToken = ScanCancellationToken()
    @Published var hasCompletedOnboarding: Bool
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
        saveROMsToDatabase()
        restoreLibraryAccess()
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

    private func updateCounts() {
        var counts: [String: Int] = [:]
        counts["all"] = roms.count
        counts["favorites"] = roms.filter { $0.isFavorite }.count
        counts["recent"] = roms.filter { $0.lastPlayed != nil }.count
        
        let grouped = Dictionary(grouping: roms) { $0.systemID ?? "unknown" }
        for (sysID, list) in grouped {
            counts[sysID] = list.count
        }
        self.romCounts = counts
        self.lastChangeDate = Date()
    }

    // MARK: - Onboarding & Library Folders

    func completeOnboarding(folderURL: URL) {
        if isInternalPath(folderURL) {
            LoggerService.info(category: "ROMLibrary", "Rejected adding internal path as library folder: \(folderURL.path)")
            return
        }
        addLibraryFolder(url: folderURL)
        hasCompletedOnboarding = true
        DatabaseManager.shared.setBoolSetting("has_completed_onboarding", value: true)
    }

    func addLibraryFolder(url: URL) {
        if isInternalPath(url) {
            LoggerService.info(category: "ROMLibrary", "Rejected adding internal path as library folder: \(url.path)")
            return
        }
        if !libraryFolders.contains(url) {
            libraryFolders.append(url)
            saveSecurityScopedBookmarks()
        }
        Task { await scanROMs(in: url) }
    }

    func removeLibraryFolder(at index: Int) {
        guard index < libraryFolders.count else { return }
        let url = libraryFolders[index]
        libraryFolders.remove(at: index)
        saveSecurityScopedBookmarks()
        
        // Remove ROMs that are descendants of this folder
        let folderPath = url.path
        roms.removeAll { $0.path.path.hasPrefix(folderPath) }
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
    private func saveROMsToDatabase() {
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

    private func saveSecurityScopedBookmarks() {
        let bookmarks: [(String, Data)] = libraryFolders.compactMap { url -> (String, Data)? in
            _ = url.startAccessingSecurityScopedResource()
            guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
            return (url.path, data)
        }
        DatabaseManager.shared.saveLibraryFolders(bookmarks)
    }

    private func restoreLibraryAccess() {
        let folders = DatabaseManager.shared.loadLibraryFolders()
        for (_, bookmarkData) in folders {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                if !libraryFolders.contains(url) {
                    libraryFolders.append(url)
                }
            }
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

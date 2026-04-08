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
        // Initialize SwiftData repository
        self.repository = ROMRepository(context: SwiftDataContainer.shared.mainContext)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
    }

    /// Perform heavy initialization asynchronously. Call this from `.task {}` in the view.
    /// On first call this loads the ROM library and metadata; subsequent calls are no-ops.
    func initializeIfNeeded() {
        guard roms.isEmpty else { return }
        initializeLibrary()
    }

    private func initializeLibrary() {
        // Migrate legacy UserDefaults data to SwiftData (one-time)
        migrateLegacyUserDefaultsToSwiftData()

        // Load state from SwiftData
        restoreLibraryAccess()
        loadROMsFromRepository()
        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }

        // Purge orphaned ROMs
        purgeROMsOutsideLibraryFolders()

        loadFileIndexFromStorage()
        updateCounts()
        
        // Resume any pending identification or box art downloads from a previous session
        Task {
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
            await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(library: self)
        }
        
        // Box art images are now loaded on-demand via ImageCache as cards appear on screen.
        // Startup preloading was removed because it was blocking the UI while reporting 0% cache hit rate.
    }

    // MARK: - Legacy Migration

    private func migrateLegacyUserDefaultsToSwiftData() {
        let needsRomMigration = defaults.data(forKey: legacyRomsKey) != nil
        let needsFolderMigration = defaults.array(forKey: legacyFoldersKey) as? [Data] != nil
            || defaults.data(forKey: "rom_folder_bookmark") != nil
        let needsIndexMigration = defaults.data(forKey: legacyIndexKey) != nil

        guard needsRomMigration || needsFolderMigration || needsIndexMigration else { return }

        LoggerService.info(category: "ROMLibrary", "Starting migration from UserDefaults to SwiftData")

        if needsRomMigration { migrateLegacyROMs() }
        if needsFolderMigration { migrateLegacyLibraryFolders() }
        if needsIndexMigration { migrateLegacyFileIndex() }

        LoggerService.info(category: "ROMLibrary", "Legacy UserDefaults migration complete")
    }

    private func migrateLegacyROMs() {
        guard let data = defaults.data(forKey: legacyRomsKey) else { return }
        guard let legacyRoms = try? decoder.decode([ROM].self, from: data) else {
            LoggerService.warning(category: "ROMLibrary", "Failed to decode legacy ROMs")
            defaults.removeObject(forKey: legacyRomsKey)
            return
        }

        LoggerService.info(category: "ROMLibrary", "Migrating \(legacyRoms.count) ROMs from UserDefaults")
        repository.saveROMs(legacyRoms)
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

        if let legacyData = defaults.data(forKey: "rom_folder_bookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: legacyData, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                repository.saveLibraryFolders([(url.path, legacyData, nil, true)])
                defaults.removeObject(forKey: "rom_folder_bookmark")
            }
        }
    }

    private func migrateLegacyFileIndex() {
        guard defaults.data(forKey: legacyIndexKey) != nil else { return }
        // File index entries are not migrated to SwiftData (kept as-is in UserDefaults for migration)
        defaults.removeObject(forKey: legacyIndexKey)
    }

    // MARK: - Counts

    func updateCounts() {
        var counts: [String: Int] = [:]
        counts["all"] = roms.filter { !$0.isHidden }.count
        counts["favorites"] = roms.filter { $0.isFavorite && !$0.isHidden }.count
        counts["recent"] = roms.filter { $0.lastPlayed != nil && !$0.isHidden }.count
        counts["hidden"] = roms.filter { $0.isHidden }.count

        // Count MAME non-game files separately (BIOS, device, mechanical only - not unknown)
        counts["mameNonGames"] = roms.filter { rom in
            rom.systemID == "mame" && rom.mameRomType != nil && rom.mameRomType != "game"
        }.count

        let grouped = Dictionary(grouping: roms) { $0.systemID ?? "unknown" }
        for (sysID, list) in grouped {
            var visible = list.filter { !$0.isHidden }
            // For MAME, count games (type="game") and unknown entries (nil)
            if sysID == "mame" {
                visible = visible.filter { $0.mameRomType == "game" || $0.mameRomType == nil }
            }
            counts[sysID] = visible.count
        }
        self.romCounts = counts
        self.lastChangeDate = Date()
    }

    private func purgeROMsOutsideLibraryFolders() {
        let validPaths = primaryFolders.map { $0.url.path } + subfolderMap.values.flatMap { $0.map { $0.url.path } }
        guard !validPaths.isEmpty else {
            if !roms.isEmpty {
                let count = roms.count
                let allPaths = roms.map { $0.path.path }
                roms.removeAll()
                repository.deleteROMsByPath(allPaths)
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

        LoggerService.info(category: "ROMLibrary", "Found \(orphans.count) orphaned ROM(s). Purging.")
        let idsToPurge = orphans.map { $0.id }
        roms.removeAll { orphan in idsToPurge.contains(orphan.id) }
        repository.deleteROMs(ids: idsToPurge)
        saveROMsToDatabase()
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
        
        // Use folder path for efficient range deletion in DB
        repository.deleteROMsByPath([folderPath])

        if libraryFolders.isEmpty {
            let orphanedIDs = roms.map { $0.id }
            roms.removeAll()
            repository.deleteROMs(ids: orphanedIDs)
            fileIndex.removeAll()
        } else {
            for path in Set(removedROMs.map { $0.path.path }) { fileIndex.removeValue(forKey: path) }
            if !fileIndex.isEmpty { saveFileIndexToStorage() }
        }

        let metadataKeys = Set(removedROMs.map { LibraryMetadataStore.pathKey(for: $0) })
        LibraryMetadataStore.shared.deleteMetadataEntries(metadataKeys)

        updateCounts()
        saveROMsToDatabase()
        cleanupScummVMCaches()
    }

    /// Scan ROMs in a folder, updating the UI incrementally as ROMs are found.
    /// This keeps the interface responsive by showing ROMs as they are discovered.
    func scanROMs(in folder: URL, runAutomationAfter: Bool = true) async {
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.debug(category: "ROMLibrary", "Deferring ROM scan — game is running")
            return
        }

        let scanStart = Date()
        LoggerService.info(category: "ROMLibrary", "=== SCAN STARTED: \(folder.path) ===")
        
        isScanning = true
        scanProgress = 0
        scanCancellationToken.reset()
        let scanner = ROMScanner()

        // Track total files found so we can estimate progress
        let fm = FileManager.default
        let enumStart = Date()
        _ = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        // Collect ALL files first, then process
        let urls = collectFilesInFolder(folder: folder)
        let totalURLs = urls.count
        let enumTime = Date().timeIntervalSince(enumStart)
        LoggerService.info(category: "ROMLibrary", "Enumeration: \(totalURLs) files found in \(String(format: "%.2f", enumTime))s")

        // Build a Set of existing ROM paths for O(1) deduplication
        let existingROMPaths = Set(roms.map { $0.path.path })

        var scannedCount = 0
        var skippedCount = 0
        var romFoundCount = 0
        var zipCount = 0
        var biosCount = 0
        var newROMs: [ROM] = []
        
        LoggerService.info(category: "ROMLibrary", "Processing \(totalURLs) files, \(existingROMPaths.count) already in library...")
        
        for url in urls {
            if scanCancellationToken.isCancelled { break }

            scannedCount += 1
            
            // Update progress and log periodically
            if scannedCount % 100 == 0 {
                let elapsed = Date().timeIntervalSince(scanStart)
                let rate = Double(scannedCount) / max(elapsed, 0.001)
                LoggerService.info(category: "ROMLibrary", "Progress: \(scannedCount)/\(totalURLs) (\(String(format: "%.1f", rate)) files/sec, \(String(format: "%.1f", elapsed))s elapsed)")
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms yield
            }
            
            self.scanProgress = Double(scannedCount) / max(Double(totalURLs), 1.0)

            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }
            if Self.shouldSkipExtension(ext) { skippedCount += 1; continue }
            if url.path.contains("/Contents/") || url.path.hasSuffix(".app") { skippedCount += 1; continue }

            // Identify system
            let system = identifySystemForURL(url: url, extension: ext)
            guard system != nil else { skippedCount += 1; continue }
            
            if ext == "zip" || ext == "7z" { zipCount += 1 }

            let name = url.deletingPathExtension().lastPathComponent
            var rom = ROM(id: UUID(), name: name, path: url, systemID: system?.id)

            // BIOS Detection
            if KnownBIOS.isKnownBios(filename: url.lastPathComponent) {
                rom.isBios = true
                rom.isHidden = true
                rom.category = "bios"
                biosCount += 1
            }

            // MAME ROM Detection
            if rom.systemID == "mame" {
                applyMAMEIdentificationInline(to: &rom, url: url)
            }

            // Skip if this ROM path already exists in the library (O(1) Set lookup)
            guard !existingROMPaths.contains(rom.path.path) else { continue }

            romFoundCount += 1
            newROMs.append(rom)
        }
        
        let scanTime = Date().timeIntervalSince(scanStart)
        LoggerService.info(category: "ROMLibrary", "=== SCAN COMPLETE: \(romFoundCount) new ROMs found, \(skippedCount) skipped, \(biosCount) BIOS in \(String(format: "%.2f", scanTime))s ===")
        
        // Batch merge metadata and add to UI ONCE (not per-batch)
        if !newROMs.isEmpty {
            let mergedROMs = newROMs.map { LibraryMetadataStore.shared.mergedROM($0) }
            self.roms.append(contentsOf: mergedROMs)
            // Sort once at the end
            self.roms.sort { $0.displayName < $1.displayName }
            self.updateCounts()
        }

        // Final progress update
        await MainActor.run {
            self.scanProgress = 1.0
        }

        // Apply final filtering and sorting
        let detectedSystems = Set(roms.compactMap { $0.systemID })
        Task { await scanner.downloadDatsForDiscoveredSystems(detectedSystems) }

        // Get ignored files and apply to final ROM list
        let ignored = await scanner.getIgnoredFiles(in: folder)
        let folderPath = folder.path
        roms = roms.filter { rom in
            rom.path.path.hasPrefix(folderPath) ? !ignored.contains(rom.path.standardized.path) : true
        }
        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }

        // Batch persist: merge all metadata changes, then flush once to SwiftData
        for rom in roms {
            LibraryMetadataStore.shared.persist(rom: rom)
        }
        LibraryMetadataStore.shared.flushToSwiftData()

        updateCounts()
        isScanning = false
        saveROMsToDatabase()
        cleanupScummVMCaches()

        LoggerService.info(category: "ROMLibrary", "Scan complete for \(folder.lastPathComponent)")

        if runAutomationAfter {
            guard !RunningGamesTracker.shared.isGameRunning else {
                LoggerService.debug(category: "ROMLibrary", "Skipping post-scan automation — game is running")
                return
            }
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
            await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(library: self)
        }
    }

    /// Collect all files in a folder, sorted by path for consistent processing order.
    /// Non-ZIP files come first (fast), ZIPs last (slower due to fingerprinting).
    private func collectFilesInFolder(folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let allFiles = enumerator.allObjects
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        
        // Split: non-ZIPs first, ZIPs last
        var nonZipFiles: [URL] = []
        var zipFiles: [URL] = []
        for url in allFiles {
            let ext = url.pathExtension.lowercased()
            if ext == "zip" || ext == "7z" {
                zipFiles.append(url)
            } else {
                nonZipFiles.append(url)
            }
        }
        
        return (nonZipFiles + zipFiles).sorted { $0.path < $1.path }
    }

    /// Identify system for a single URL (delegates to shared ROMIdentifier).
    private func identifySystemForURL(url: URL, extension ext: String) -> SystemInfo? {
        ROMIdentifier.identifySystem(url: url, extension: ext)
    }

    // MARK: - Non-ROM File Extensions (static Set for O(1) lookup)
    
    private static let nonROMExtensions: Set<String> = [
        "txt", "xml", "jpg", "jpeg", "png", "gif", "bmp", "pdf", "mp3", "mp4", "avi", "mkv", "nfo", "dat", "db", "json",
        "py", "pyc", "pyo", "pyw", "dylib", "so", "app", "icns", "plist", "strings", "loc", "lproj", "nib", "xib",
        "md", "rmd", "html", "htm", "css", "js", "ts", "jsx", "tsx"
    ]
    
    /// Returns true if this extension should be skipped during ROM scanning.
    private static func shouldSkipExtension(_ ext: String) -> Bool {
        nonROMExtensions.contains(ext)
    }


    /// Apply MAME identification inline during scanning.
    /// Prefers per-core dependency data (downloaded XML) over bundled fallback JSON.
    private func applyMAMEIdentificationInline(to rom: inout ROM, url: URL) {
        let shortName = url.deletingPathExtension().lastPathComponent.lowercased()

        // Prefer per-core deps if selectedCoreID exists and has cached data
        var source = "mame_rom_data.json"
        var description: String?
        var isPlayable: Bool?
        var type: String?
        var parentROM: String?

        if let coreID = rom.selectedCoreID {
            if let lookup = MAMEDependencyService.shared.lookupGame(for: coreID, shortName: shortName) {
                description = lookup.description
                type = lookup.type
                isPlayable = lookup.isPlayable
                parentROM = lookup.parent
                source = lookup.source
            }
        }

        // Only use bundled fallback if per-core lookup returned nil
        if description == nil {
            if let unifiedEntry = MAMEUnifiedService.shared.lookup(shortName: shortName) {
                description = unifiedEntry.description
                type = unifiedEntry.isBIOS ? "bios" : (unifiedEntry.isRunnableInAnyCore ? "game" : "unplayable")
                isPlayable = unifiedEntry.isRunnableInAnyCore && !unifiedEntry.isBIOS
                parentROM = nil
                source = "mame_unified.json"
            }
        }

        guard let description = description,
              let type = type,
              let isPlayable = isPlayable else {
            LoggerService.debug(category: "ROMLibrary", "MAME lookup MISS for '\(shortName)' — hiding (not in any known database)")
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
            LoggerService.debug(category: "ROMLibrary", "MAME SELECT '\(shortName)' → game='\(description)' type=\(type) parent=\(parentROM ?? "none") [source: \(source)]")

            if rom.metadata == nil {
                rom.metadata = ROMMetadata()
            }
            rom.metadata?.title = description
        } else {
            rom.isHidden = true
            rom.isBios = true
            rom.category = "bios"
            LoggerService.debug(category: "ROMLibrary", "MAME HIDE '\(shortName)' → type=\(type) description='\(description)' [source: \(source)]")
        }
    }

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

    func stopScan() { scanCancellationToken.cancel(); isScanning = false }

    func updateROM(_ rom: ROM, persist: Bool = true) {
        if let idx = roms.firstIndex(where: { $0.id == rom.id }) {
            let oldBezel = roms[idx].settings.bezelFileName
            objectWillChange.send()
            roms[idx] = rom
            if oldBezel != rom.settings.bezelFileName { bezelUpdateToken += 1 }
            LibraryMetadataStore.shared.persist(rom: rom)
            updateGamesXML(for: rom)
            updateCounts()
            
            // Persist this single ROM immediately if requested.
            // For batch operations, pass persist: false and call saveROMsToDatabase() at the end.
            if persist {
                saveSingleROM(rom)
            }
        }
    }

    @discardableResult
    func identifyROM(_ rom: ROM, persist: Bool = true) async -> ROMIdentifyResult {
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
            updateROM(updated, persist: persist)
        case .crcNotInDatabase(let crc):
            var updated = working
            updated.crc32 = crc
            if updated.metadata?.title != nil {
                LoggerService.info(category: "ROMLibrary", "Identification failed — using filename")
                updated.metadata?.title = nil
                updated.metadata?.year = nil
                updated.metadata?.publisher = nil
                updated.metadata?.developer = nil
                updated.metadata?.genre = nil
            }
            updateROM(updated, persist: persist)
        case .identificationCleared:
            if working.metadata?.title != nil {
                LoggerService.info(category: "ROMLibrary", "Identification cleared — reverting to filename")
                working.metadata?.title = nil
                working.metadata?.year = nil
                working.metadata?.publisher = nil
                working.metadata?.developer = nil
                working.metadata?.genre = nil
                working.thumbnailLookupSystemID = nil
                updateROM(working, persist: persist)
            }
        case .databaseUnavailable, .noSystem:
            if working.crc32 != rom.crc32 { updateROM(working, persist: persist) }
        case .romReadFailed:
            break
        }
        return result
    }

    func clearIdentification(for rom: ROM, persist: Bool = true) {
        var updated = rom
        if updated.metadata?.title != nil {
            LoggerService.info(category: "ROMLibrary", "Clearing identification for '\(rom.displayName)'")
            updated.metadata?.title = nil
            updated.metadata?.year = nil
            updated.metadata?.publisher = nil
            updated.metadata?.developer = nil
            updated.metadata?.genre = nil
            updated.thumbnailLookupSystemID = nil
            updateROM(updated, persist: persist)
        }
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
            root = doc.rootElement() ?? XMLElement(name: "gameList")
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
            gameNode = children.first { $0.name == "game" && $0.elements(forName: "path").first?.stringValue == relPath }
        }
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

    func markPlayed(_ rom: ROM) {
        var updated = rom; updated.lastPlayed = Date(); updateROM(updated)
    }

    func recordPlaySession(_ rom: ROM, duration: TimeInterval) {
        var updated = rom
        updated.lastPlayed = Date()
        updated.timesPlayed += 1
        updated.totalPlaytimeSeconds += duration
        updateROM(updated)
    }

    // MARK: - SwiftData Persistence

    /// Bulk save all ROMs to the database. Use after scan/import operations.
    func saveROMsToDatabase() {
        repository.saveROMs(roms)
    }

    /// Save a single ROM to the database. Use for targeted user-initiated updates
    /// (favorites, play sessions, custom cores) that should persist immediately.
    func saveSingleROM(_ rom: ROM) {
        repository.saveROM(rom)
    }

    private func loadROMsFromRepository() {
        roms = repository.allROMs()
    }

    private func saveSecurityScopedBookmarks() {
        var bookmarkRows: [(String, Data, String?, Bool)] = []
        var failedPaths: [String] = []

        for folder in primaryFolders {
            _ = folder.url.startAccessingSecurityScopedResource()
            if let data = try? folder.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                bookmarkRows.append((folder.url.path, data, nil, true))
            } else {
                LoggerService.warning(category: "ROMLibrary", "Bookmark creation failed for \(folder.url.path)")
                failedPaths.append(folder.url.path)
            }
        }

        for (_, subfolders) in subfolderMap {
            for subfolder in subfolders where subfolder.isPrimary {
                _ = subfolder.url.startAccessingSecurityScopedResource()
                if let data = try? subfolder.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarkRows.append((subfolder.url.path, data, subfolder.parentPath, true))
                } else { failedPaths.append(subfolder.url.path) }
            }
        }

        for path in failedPaths {
            let url = URL(fileURLWithPath: path)
            if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                if primaryFolders.first(where: { $0.url.path == path }) != nil {
                    bookmarkRows.append((path, data, nil, true))
                } else {
                    let parentPath = findParentForPath(path)
                    bookmarkRows.append((path, data, parentPath, true))
                }
            } else {
                let parentPath = findParentForPath(path)
                bookmarkRows.append((path, Data([0x00, 0x00, 0x00, 0x00]), parentPath, true))
            }
        }

        if !bookmarkRows.isEmpty {
            repository.saveLibraryFolders(bookmarkRows)
        }
    }

    // MARK: - Subfolder Management

    private func findParentForPath(_ path: String) -> String? {
        for primary in primaryFolders {
            if path.hasPrefix(primary.url.path + "/") { return primary.url.path }
        }
        return nil
    }

    @MainActor
    func discoverSubfoldersWithROMs(in primaryFolder: ROMLibraryFolder, maxDepth: Int = 2) async -> [ROMLibraryFolder] {
        let scanner = ROMScanner()
        return await scanner.findFoldersWithROMs(baseURL: primaryFolder.url, maxDepth: maxDepth).map { url in
            ROMLibraryFolder(url: url, parentPath: primaryFolder.url.path, isPrimary: repository.isFolderPrimary(urlPath: url.path))
        }
    }

    @MainActor
    func discoverSubfoldersWithROMsInFolder(folder: ROMLibraryFolder) async -> [ROMLibraryFolder] {
        let scanner = ROMScanner()
        return await scanner.findFoldersWithROMs(baseURL: folder.url, maxDepth: 1).map { url in
            ROMLibraryFolder(url: url, parentPath: folder.url.path, isPrimary: repository.isFolderPrimary(urlPath: url.path))
        }
    }

    @MainActor
    func addPrimaryFolder(url: URL, scanAfter: Bool = true) {
        guard !isInternalPath(url), !url.path.isEmpty else { return }
        guard !isExcludedLibraryPath(url) else {
            LoggerService.warning(category: "ROMLibrary", "Refused to add excluded Library path: \(url.path)")
            return
        }

        if primaryFolders.contains(where: { $0.url.path == url.path }) {
            LoggerService.info(category: "ROMLibrary", "Folder already exists as primary: \(url.path)")
            return
        }

        var parentPathOfSubfolder: String? = nil
        for (parentPath, subfolders) in subfolderMap {
            if subfolders.contains(where: { $0.url.path == url.path }) {
                parentPathOfSubfolder = parentPath
                break
            }
        }

        let folder = ROMLibraryFolder(url: url, parentPath: parentPathOfSubfolder, isPrimary: true)
        primaryFolders.append(folder)

        if let oldParentPath = parentPathOfSubfolder {
            repository.markFolderAsPrimary(urlPath: url.path, parentPath: oldParentPath)
            if let idx = subfolderMap[oldParentPath]?.firstIndex(where: { $0.url.path == url.path }) {
                subfolderMap[oldParentPath]?[idx] = folder
            }
        }

        if !libraryFolders.contains(url) { libraryFolders.append(url) }
        saveSecurityScopedBookmarks()
        if scanAfter { Task { await scanROMs(in: url) } }
    }

    @MainActor
    func removePrimaryFolder(at index: Int) {
        guard index < primaryFolders.count else { return }
        let folder = primaryFolders[index]
        let folderPath = folder.url.path
        let folderPathPrefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"

        LoggerService.info(category: "ROMLibrary", "Removing primary folder: \(folderPath)")

        let affectedSubfolders = (subfolderMap[folderPath] ?? []).filter { subfolder in
            !subfolder.isPrimary && !repository.isFolderPrimary(urlPath: subfolder.url.path)
        }

        var pathsToRemove = [folderPath]
        pathsToRemove.append(contentsOf: affectedSubfolders.map { $0.url.path })

        let removedROMs = roms.filter { rom in
            let romPath = rom.path.path
            return pathsToRemove.contains { romPath == $0 || romPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }

        primaryFolders.remove(at: index)
        for subfolder in affectedSubfolders {
            if let idx = subfolderMap[folderPath]?.firstIndex(where: { $0.url.path == subfolder.url.path }) {
                subfolderMap[folderPath]?.remove(at: idx)
            }
        }
        if subfolderMap[folderPath]?.isEmpty == true { subfolderMap.removeValue(forKey: folderPath) }

        roms.removeAll { rom in
            let romPath = rom.path.path
            return pathsToRemove.contains { romPath == $0 || romPath.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }

        libraryFolders.removeAll { $0.path == folderPath || $0.path.hasPrefix(folderPathPrefix) }
        repository.removeLibraryFolder(urlPath: folderPath, removeSubfolders: true)

        if !removedROMs.isEmpty {
            // Efficiency: Pass the few folder paths to deleteROMsByPath instead of 4000 individual paths.
            // This triggers range queries in the DB which are nearly instantaneous.
            repository.deleteROMsByPath(pathsToRemove)
            
            for path in Set(removedROMs.map { $0.path.path }) { fileIndex.removeValue(forKey: path) }
            if !fileIndex.isEmpty { saveFileIndexToStorage() }
            let metadataKeys = Set(removedROMs.map { LibraryMetadataStore.pathKey(for: $0) })
            LibraryMetadataStore.shared.deleteMetadataEntries(metadataKeys)
            LoggerService.info(category: "ROMLibrary", "Purged \(removedROMs.count) ROM(s)")
        }

        if primaryFolders.isEmpty && subfolderMap.isEmpty {
            let orphanedIDs = roms.map { $0.id }
            roms.removeAll()
            repository.deleteROMs(ids: orphanedIDs)
            fileIndex.removeAll()
            LoggerService.info(category: "ROMLibrary", "No primary folders remain. Purged \(orphanedIDs.count) ROM(s).")
        }

        saveSecurityScopedBookmarks()
        updateCounts()
        saveROMsToDatabase()
        cleanupScummVMCaches()
    }

    @MainActor
    func removeSubfolder(from primaryFolderPath: String, subfolderPath: String) {
        if repository.isFolderPrimary(urlPath: subfolderPath) {
            LoggerService.info(category: "ROMLibrary", "Cannot remove subfolder — independently added as primary")
            return
        }

        let subfolderPathPrefix = subfolderPath.hasSuffix("/") ? subfolderPath : subfolderPath + "/"
        let removedROMs = roms.filter { $0.path.path == subfolderPath || $0.path.path.hasPrefix(subfolderPathPrefix) }

        if let idx = subfolderMap[primaryFolderPath]?.firstIndex(where: { $0.url.path == subfolderPath }) {
            subfolderMap[primaryFolderPath]?.remove(at: idx)
        }
        if subfolderMap[primaryFolderPath]?.isEmpty == true { subfolderMap.removeValue(forKey: primaryFolderPath) }

        roms.removeAll { $0.path.path == subfolderPath || $0.path.path.hasPrefix(subfolderPathPrefix) }
        for path in Set(removedROMs.map { $0.path.path }) { fileIndex.removeValue(forKey: path) }
        if !fileIndex.isEmpty { saveFileIndexToStorage() }
        let metadataKeys = Set(removedROMs.map { LibraryMetadataStore.pathKey(for: $0) })
        LibraryMetadataStore.shared.deleteMetadataEntries(metadataKeys)

        repository.removeLibraryFolder(urlPath: subfolderPath, removeSubfolders: true)
        updateCounts()
        saveROMsToDatabase()
    }

    @MainActor
    func addSubfolder(folder: ROMLibraryFolder) {
        guard !isInternalPath(folder.url), !isExcludedLibraryPath(folder.url) else { return }
        guard let parentPath = findParentForPath(folder.url.path) else { return }

        if subfolderMap[parentPath] == nil { subfolderMap[parentPath] = [] }
        if !subfolderMap[parentPath]!.contains(where: { $0.url.path == folder.url.path }) {
            subfolderMap[parentPath]!.append(folder)
            saveSecurityScopedBookmarks()
            Task { await scanROMs(in: folder.url) }
        }
    }

    // MARK: - Restore Library Access

    func restoreLibraryAccess() {
        let savedFolders = repository.loadPrimaryFolders()
        if savedFolders.isEmpty {
            libraryFolders = []
            primaryFolders = []
            subfolderMap = [:]
            return
        }

        libraryFolders = savedFolders.compactMap { (urlPath, data, _, _) -> URL? in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        }
        primaryFolders = savedFolders.map { url, data, parentPath, isPrimary in
            ROMLibraryFolder(url: URL(fileURLWithPath: url), parentPath: parentPath, isPrimary: isPrimary)
        }

        // Load subfolders
        for primary in primaryFolders {
            let subs = repository.loadSubfolders(parentPath: primary.url.path)
            subfolderMap[primary.url.path] = subs.map { url, data, parentPath, isPrimary in
                ROMLibraryFolder(url: URL(fileURLWithPath: url), parentPath: parentPath, isPrimary: isPrimary)
            }
        }
    }

    // MARK: - File Index

    func shouldRescanFile(path: String, size: Int64, modTime: TimeInterval) -> Bool {
        guard let sig = fileIndex[path] else { return true }
        return sig.size != size || sig.modTime != modTime
    }

    func recordFileInIndex(path: String, size: Int64, modTime: TimeInterval) {
        fileIndex[path] = FileSignature(size: size, modTime: modTime)
        saveFileIndexToStorage()
    }

    private func loadFileIndexFromStorage() {
        // File index is kept as-is during migration, not reloaded from SwiftData
        fileIndex = [:]
    }

    private func saveFileIndexToStorage() {
        // File index is not persisted in SwiftData migration — rebuilt on scan
    }

    // MARK: - Rebuild

    func rebuildLibrary(modes: Set<RebuildOption>) async {
        if modes.contains(.boxartRebuild) {
            for i in 0..<roms.count {
                roms[i].hasBoxArt = false
            }
        }

        if modes.contains(.idRebuild) {
            for i in 0..<roms.count {
                roms[i].crc32 = nil
                roms[i].thumbnailLookupSystemID = nil
                roms[i].metadata?.title = nil
                roms[i].metadata?.year = nil
                roms[i].metadata?.publisher = nil
                roms[i].metadata?.developer = nil
                roms[i].metadata?.genre = nil
            }
        }

        if modes.contains(.refresh) || modes.contains(.everything) || modes.contains(.idRebuild) {
            saveROMsToDatabase()
            let folders = primaryFolders.map { $0.url }
            for folder in folders {
                await scanROMs(in: folder, runAutomationAfter: folder == folders.last)
            }
        } else if modes.contains(.boxartRebuild) {
            saveROMsToDatabase()
        }
    }

    // MARK: - Folder Operations

    @MainActor
    func rescanLibrary(at folderURL: URL) async {
        isScanning = true
        await scanROMs(in: folderURL, runAutomationAfter: true)
        isScanning = false
    }

    @MainActor
    func refreshFolder(at folderURL: URL) async {
        isScanning = true
        scanCancellationToken.reset()

        // Step 1: Collect all existing ROMs for this folder
        let folderPath = folderURL.path
        let folderPathPrefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        let existingROMsInFolder = roms.filter { rom in
            rom.path.path == folderPath || rom.path.path.hasPrefix(folderPathPrefix)
        }
        let existingPathsInLibrary = Set(existingROMsInFolder.map { $0.path.path })

        // Step 2: Lightweight scan — just file paths, NO identification
        let scanner = ROMScanner()
        let romFileURLs = await scanner.getROMFiles(in: folderURL) { progress in
            DispatchQueue.main.async {
                self.scanProgress = progress
            }
        }

        // Step 3: Build set of physical paths found on disk
        let scannedPaths = Set(romFileURLs.map { $0.path })

        // Step 4: Find genuinely new files (on disk but NOT in library)
        let newFileURLs = romFileURLs.filter { fileURL in
            !existingPathsInLibrary.contains(fileURL.path)
        }

        // Step 5: Identify ONLY the new files
        var newROMsToAdd: [ROM] = []
        if !newFileURLs.isEmpty {
            LoggerService.info(category: "ROMLibrary", "Refresh: Identifying \(newFileURLs.count) new ROM(s) in \(folderURL.lastPathComponent)")
            newROMsToAdd = await scanner.scan(urls: newFileURLs) { _ in }
                .map { LibraryMetadataStore.shared.mergedROM($0) }
        }

        // Step 6: Find ROMs to remove (in library but no longer on disk)
        let deletedROMs = existingROMsInFolder.filter { rom in
            !scannedPaths.contains(rom.path.path)
        }

        // Step 7: Apply additions
        if !newROMsToAdd.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.roms.append(contentsOf: newROMsToAdd)
                self.roms.sort { $0.displayName < $1.displayName }
            }
            LoggerService.info(category: "ROMLibrary", "Refresh: Added \(newROMsToAdd.count) new ROM(s) to \(folderURL.lastPathComponent)")

            // Persist new ROMs
            repository.saveROMs(newROMsToAdd)
        }

        // Step 8: Apply deletions — only affects target folder
        if !deletedROMs.isEmpty {
            LoggerService.info(category: "ROMLibrary", "Refresh: Removing \(deletedROMs.count) ROM(s) no longer in \(folderURL.lastPathComponent)")
            let deletedIDs = Set(deletedROMs.map { $0.id })
            roms.removeAll { deletedIDs.contains($0.id) }

            // Delete from SwiftData using IDs for O(N) performance
            repository.deleteROMs(ids: deletedROMs.map { $0.id })

            // Delete metadata entries in bulk
            let metadataKeys = Set(deletedROMs.map { LibraryMetadataStore.pathKey(for: $0) })
            LibraryMetadataStore.shared.deleteMetadataEntries(metadataKeys)

            // Update file index
            for path in Set(deletedROMs.map { $0.path.path }) {
                fileIndex.removeValue(forKey: path)
            }
        }

        // If nothing was added or removed, nothing was written — that's fine.
        if newROMsToAdd.isEmpty && deletedROMs.isEmpty {
            LoggerService.info(category: "ROMLibrary", "Refresh: No changes needed for \(folderURL.lastPathComponent)")
        }

        // Step 9: Final updates
        updateCounts()
        isScanning = false
    }

    @MainActor
    func rebuildFolder(folder: ROMLibraryFolder, option: RebuildOption) async {
        await rebuildLibrary(modes: [option])
    }
}

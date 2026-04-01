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

@MainActor
class ROMLibrary: ObservableObject {
    
    // MARK: - Internal Directory Validation
    
    /// Path to the app's own Application Support directory (where cache files are stored).
    private var appInternalPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu").path
    }
    
    /// Check if a folder URL is inside the app's own internal directory.
    /// Prevents users from accidentally adding the ScummVMExtracted cache as a library folder.
    private func isInternalPath(_ url: URL) -> Bool {
        return url.path.hasPrefix(appInternalPath)
    }
    
    @Published var roms: [ROM] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    private let scanCancellationToken = ScanCancellationToken()
    @Published var hasCompletedOnboarding: Bool
    @Published var libraryFolders: [URL] = []
    @Published var romCounts: [String: Int] = [:] // "all", "favorites", "recent", or systemID
    @Published var lastChangeDate = Date()
    var romFolderURL: URL? { libraryFolders.first }

    // File signature index for smart rescan
    private struct FileSignature: Codable, Hashable { let size: Int64; let modTime: TimeInterval }
    private let indexKey = "rom_file_index_v1"
    private var fileIndex: [String: FileSignature] = [:] // path -> signature

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let romsKey = "saved_roms"
    private let onboardingKey = "has_completed_onboarding"
    private let foldersKey = "library_folders_bookmarks_v2"

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        loadROMsFromDisk()
        LibraryMetadataStore.shared.migrateLegacySidecarsIfStoreEmpty(roms: roms)
        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }
        saveROMsToDisk()
        restoreLibraryAccess()
        loadFileIndex()
        updateCounts()
    }

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

    func completeOnboarding(folderURL: URL) {
        // Validate: don't allow adding internal app directories
        if isInternalPath(folderURL) {
            print("[ROMLibrary] Rejected adding internal path as library folder: \(folderURL.path)")
            return
        }
        addLibraryFolder(url: folderURL)
        hasCompletedOnboarding = true
        defaults.set(true, forKey: onboardingKey)
    }

    func addLibraryFolder(url: URL) {
        // Validate: don't allow adding internal app directories
        if isInternalPath(url) {
            print("[ROMLibrary] Rejected adding internal path as library folder: \(url.path)")
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
        saveROMsToDisk()
        
        // Clean up orphaned ScummVM extracted caches
        cleanupScummVVCaches()
    }

    func scanROMs(in folder: URL, runAutomationAfter: Bool = true) async {
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
        saveROMsToDisk()
        
        // Clean up orphaned ScummVM extracted caches
        cleanupScummVVCaches()
        
        if runAutomationAfter {
            await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
        }
    }
    
    /// Clean up ScummVM extracted caches for games no longer in the library.
    private func cleanupScummVVCaches() {
        let activeScummvmPaths = Set(roms.filter { $0.systemID == "scummvm" }.map { $0.path.path })
        ScummVMCacheManager.cleanupOrphanedCaches(activeScummvmPaths: activeScummvmPaths)
    }

    func fullRescan() async {
        isScanning = true
        scanProgress = 0
        
        // Clear all except maybe favorites? 
        // User said "rebuild from scratch", so let's wipe roms but keep metadata on disk.
        roms = []
        fileIndex = [:]
        saveROMsToDisk()
        saveFileIndex()
        
        for (i, folder) in libraryFolders.enumerated() {
            if !isScanning { break } // Allow cancellation during full rescan
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
            roms[idx] = rom
            LibraryMetadataStore.shared.persist(rom: rom)
            updateGamesXML(for: rom)
            updateCounts()
            saveROMsToDisk()
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
        
        // Find existing game entry with relative path
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

    // MARK: - Persistence
    private func saveROMsToDisk() {
        if let data = try? encoder.encode(roms) {
            defaults.set(data, forKey: romsKey)
        }
    }

    private func loadROMsFromDisk() {
        guard let data = defaults.data(forKey: romsKey),
              let saved = try? decoder.decode([ROM].self, from: data) else { return }
        roms = saved
    }

    private func saveSecurityScopedBookmarks() {
        let bookmarks = libraryFolders.compactMap { url -> Data? in
            _ = url.startAccessingSecurityScopedResource()
            return try? url.bookmarkData(options: .withSecurityScope,
                                          includingResourceValuesForKeys: nil,
                                          relativeTo: nil)
        }
        defaults.set(bookmarks, forKey: foldersKey)
    }

    private func restoreLibraryAccess() {
        if let bookmarks = defaults.array(forKey: foldersKey) as? [Data] {
            for data in bookmarks {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &stale) {
                    _ = url.startAccessingSecurityScopedResource()
                    libraryFolders.append(url)
                }
            }
        } else if let legacyData = defaults.data(forKey: "rom_folder_bookmark") {
            // Migration
            var stale = false
            if let url = try? URL(resolvingBookmarkData: legacyData,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                libraryFolders.append(url)
                saveSecurityScopedBookmarks() // Move to new format
            }
        }
    }

    private func loadFileIndex() {
        if let data = defaults.data(forKey: indexKey),
           let idx = try? JSONDecoder().decode([String: FileSignature].self, from: data) {
            fileIndex = idx
        }
    }

    private func saveFileIndex() {
        if let data = try? JSONEncoder().encode(fileIndex) {
            defaults.set(data, forKey: indexKey)
        }
    }

    func rescanLibrary(at url: URL) async {
        isScanning = true
        scanProgress = 0
        scanCancellationToken.reset()

        // Enumerate current files
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

        // Build new index and detect changes
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

        // Remove deleted
        let currentPaths = Set(candidates.map { $0.path })
        let deletedPaths = Set(roms.map { $0.path.path }).subtracting(currentPaths)
        if !deletedPaths.isEmpty {
            roms.removeAll { deletedPaths.contains($0.path.path) }
        }

        // Scan only changed/new files
        let imported = await scanner.scan(urls: changed) { p in
            Task { @MainActor in self.scanProgress = p }
        }

        let detectedSystems = Set(imported.compactMap { $0.systemID })
        Task { await scanner.downloadDatsForDiscoveredSystems(detectedSystems) }

        // Merge
        var byPath = Dictionary(uniqueKeysWithValues: roms.map { ($0.path.path, $0) })
        for r in imported { byPath[r.path.path] = r }
        
        let ignored = await scanner.getIgnoredFiles(in: url)
        let folderPath = url.path
        roms = byPath.values.filter { rom in
            if rom.path.path.hasPrefix(folderPath) {
                return !ignored.contains(rom.path.standardized.path)
            }
            return true
        }.sorted { $0.displayName < $1.displayName }

        roms = roms.map { LibraryMetadataStore.shared.mergedROM($0) }

        // Save index and roms
        fileIndex = newIndex
        saveFileIndex()
        saveROMsToDisk()

        isScanning = false
        
        // Clean up orphaned ScummVM extracted caches
        cleanupScummVVCaches()
        
        await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: self)
    }
}

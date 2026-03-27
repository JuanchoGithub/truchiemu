import Foundation
import Combine

@MainActor
class ROMLibrary: ObservableObject {
    @Published var roms: [ROM] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
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
        addLibraryFolder(url: folderURL)
        hasCompletedOnboarding = true
        defaults.set(true, forKey: onboardingKey)
    }

    func addLibraryFolder(url: URL) {
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
    }

    func scanROMs(in folder: URL) async {
        isScanning = true
        scanProgress = 0
        let scanner = ROMScanner()
        await scanner.registerDats(in: folder)
        let found = await scanner.scan(folder: folder) { progress in
            Task { @MainActor in self.scanProgress = progress }
        }
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
        updateCounts()
        isScanning = false
        saveROMsToDisk()
        // Task { await BoxArtService.shared.batchDownloadBoxArtGoogle(for: self.roms, library: self) }
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
        
        for folder in libraryFolders {
            await scanROMs(in: folder)
        }
        
        isScanning = false
    }

    func updateROM(_ rom: ROM) {
        if let idx = roms.firstIndex(where: { $0.id == rom.id }) {
            roms[idx] = rom
            
            // Per user request: save rom info to <romname_info>.json in rom folder
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let meta = rom.metadata,
               let data = try? encoder.encode(meta) {
                try? data.write(to: rom.infoLocalPath)
            }
            
            updateGamesXML(for: rom)
            updateCounts()
            saveROMsToDisk()
        }
    }

    func identifyROM(_ rom: ROM) async {
        let identifier = ROMIdentifierService.shared
        if let info = identifier.identify(rom: rom) {
            var updated = rom
            if updated.metadata == nil { updated.metadata = ROMMetadata() }
            updated.metadata?.title = info.name
            updated.metadata?.year = info.year
            updated.metadata?.publisher = info.publisher
            
            updateROM(updated)
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

        // Enumerate current files
        let fm = FileManager.default
        let scanner = ROMScanner()
        await scanner.registerDats(in: url)
        
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

        // Save index and roms
        fileIndex = newIndex
        saveFileIndex()
        saveROMsToDisk()

        isScanning = false
        
        // Task { await BoxArtService.shared.batchDownloadBoxArtGoogle(for: self.roms, library: self) }
    }
}

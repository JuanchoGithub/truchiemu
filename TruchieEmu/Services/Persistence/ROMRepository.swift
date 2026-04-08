import Foundation
import SwiftData

// MARK: - ROM Repository

/// Typed repository for ROM and library folder operations using SwiftData.
/// Encapsulates all persistence logic for ROMEntry and LibraryFolder models.
@MainActor
final class ROMRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - ROM Operations

    /// Fetch all ROMs and map them to ROM structs.
    func allROMs() -> [ROM] {
        let descriptor = FetchDescriptor<ROMEntry>()
        do {
            let entries = try context.fetch(descriptor)
            return entries.compactMap { rom(from: $0) }
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to fetch ROMs: \(error.localizedDescription)")
            return []
        }
    }

    /// Bulk upsert ROM entries into the store.
    /// Uses a single batch fetch + dictionary lookup to avoid N+1 queries.
    /// All inserts/updates happen before a single context.save() to minimize WAL flushes.
    func saveROMs(_ roms: [ROM]) {
        guard !roms.isEmpty else { return }

        // 1. Single batch fetch of ALL existing ROM entries (one SQLite query)
        let allDescriptor = FetchDescriptor<ROMEntry>()
        let existingEntries: [ROMEntry]
        do {
            existingEntries = try context.fetch(allDescriptor)
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to fetch existing ROMs for batch save: \(error.localizedDescription)")
            return
        }

        // 2. Build UUID → ROMEntry lookup map for O(1) access
        var existingMap: [UUID: ROMEntry] = [:]
        for entry in existingEntries {
            existingMap[entry.id] = entry
        }

        // 3. Upsert all ROMs using the in-memory map (no additional queries)
        for rom in roms {
            if let existing = existingMap[rom.id] {
                updateROMEntry(existing, from: rom)
            } else {
                let entry = romEntry(from: rom)
                context.insert(entry)
            }
        }

        // 4. Single save — triggers one WAL commit instead of N
        do {
            try context.save()
            LoggerService.info(category: "ROMRepository", "Saved \(roms.count) ROMs.")
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to save ROMs: \(error.localizedDescription)")
        }
    }

    /// Save a single ROM entry by ID. Use for targeted updates (favorites, play sessions, etc.).
    func saveROM(_ rom: ROM) {
        let descriptor = FetchDescriptor<ROMEntry>(
            predicate: #Predicate { $0.id == rom.id }
        )
        do {
            let results = try context.fetch(descriptor)
            if let existing = results.first {
                updateROMEntry(existing, from: rom)
            } else {
                let entry = romEntry(from: rom)
                context.insert(entry)
            }
            try context.save()
            LoggerService.info(category: "ROMRepository", "Saved ROM '\(rom.name)'.")
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to save ROM '\(rom.name)': \(error.localizedDescription)")
        }
    }

    /// Delete ROMs by their unique identifiers.
    /// This is the most efficient way to delete specific entries when IDs are already known.
    func deleteROMs(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        
        let idSet = Set(ids)
        do {
            // 1. Fetch all entries to delete
            // Note: SwiftData #Predicate doesn't support Set.contains with 1000+ items well due to SQLite limits.
            // We fetch all and filter in memory, which is O(N) where N is total ROMs, but avoids the O(N*M) complexity.
            let descriptor = FetchDescriptor<ROMEntry>()
            let allEntries = try context.fetch(descriptor)
            let entriesToDelete = allEntries.filter { idSet.contains($0.id) }
            
            let count = entriesToDelete.count
            for entry in entriesToDelete {
                context.delete(entry)
            }
            
            if count > 0 {
                try context.save()
                LoggerService.info(category: "ROMRepository", "Deleted \(count) ROM entries by ID.")
            }
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to delete ROMs by ID: \(error.localizedDescription)")
        }
    }

    /// Delete ROMs whose path starts with any of the given path prefixes.
    /// Uses range-based fetching for common folder deletions to avoid fetching the entire database.
    func deleteROMsByPath(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        
        do {
            var entriesToDelete: [ROMEntry] = []
            
            // If we have just a few paths (e.g. folder removals), use efficient range queries.
            if paths.count < 10 {
                for path in paths {
                    // range query: path >= folder && path < folder + "\u{FFFF}"
                    let nextPath = path + "\u{FFFF}"
                    let descriptor = FetchDescriptor<ROMEntry>(
                        predicate: #Predicate<ROMEntry> { $0.path >= path && $0.path < nextPath }
                    )
                    entriesToDelete.append(contentsOf: try context.fetch(descriptor))
                }
            } else {
                // Many paths: fall back to O(N) fetch + O(1) Set lookup
                let pathSet = Set(paths)
                let allDescriptor = FetchDescriptor<ROMEntry>()
                let allEntries = try context.fetch(allDescriptor)
                entriesToDelete = allEntries.filter { entry in
                    pathSet.contains(entry.path) || paths.contains { entry.path.hasPrefix($0) }
                }
            }
            
            let count = entriesToDelete.count
            for entry in entriesToDelete {
                context.delete(entry)
            }
            
            if count > 0 {
                try context.save()
                LoggerService.info(category: "ROMRepository", "Deleted \(count) ROM entries by path.")
            }
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to delete ROMs by path: \(error.localizedDescription)")
        }
    }

    // MARK: - Library Folder Operations

    /// Load all library folders.
    func loadLibraryFolders() -> [(urlPath: String, bookmarkData: Data, parentPath: String?, isPrimary: Bool)] {
        let descriptor = FetchDescriptor<LibraryFolder>()
        do {
            let folders = try context.fetch(descriptor)
            return folders.map { ($0.urlPath, $0.bookmarkData, $0.parentPath, $0.isPrimary) }
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to load library folders: \(error.localizedDescription)")
            return []
        }
    }

    /// Bulk upsert library folders.
    func saveLibraryFolders(_ folders: [(String, Data, String?, Bool)]) {
        for (urlPath, bookmarkData, parentPath, isPrimary) in folders {
            let descriptor = FetchDescriptor<LibraryFolder>(
                predicate: #Predicate { $0.urlPath == urlPath }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.bookmarkData = bookmarkData
                existing.parentPath = parentPath
                existing.isPrimary = isPrimary
            } else {
                let folder = LibraryFolder(
                    urlPath: urlPath,
                    bookmarkData: bookmarkData,
                    parentPath: parentPath,
                    isPrimary: isPrimary
                )
                context.insert(folder)
            }
        }

        do {
            try context.save()
            LoggerService.info(category: "ROMRepository", "Saved \(folders.count) library folders.")
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to save library folders: \(error.localizedDescription)")
        }
    }

    /// Remove a library folder, optionally deleting subfolders too.
    func removeLibraryFolder(urlPath: String, removeSubfolders: Bool) {
        do {
            let descriptor = FetchDescriptor<LibraryFolder>()
            let folders = try context.fetch(descriptor)

            for folder in folders {
                if folder.urlPath == urlPath {
                    context.delete(folder)
                } else if removeSubfolders && folder.parentPath == urlPath {
                    context.delete(folder)
                }
            }

            try context.save()
            LoggerService.info(category: "ROMRepository", "Removed library folder: \(urlPath)")
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to remove library folder: \(error.localizedDescription)")
        }
    }

    /// Check if a folder is marked as primary.
    func isFolderPrimary(urlPath: String) -> Bool {
        let descriptor = FetchDescriptor<LibraryFolder>(
            predicate: #Predicate { $0.urlPath == urlPath && $0.isPrimary }
        )
        return (try? context.fetch(descriptor).count) ?? 0 > 0
    }

    /// Mark a folder as primary, and update sibling subfolders.
    func markFolderAsPrimary(urlPath: String, parentPath: String?) {
        do {
            // If this is a top-level folder, clear other top-level primary flags
            if parentPath == nil {
                let topFolders = FetchDescriptor<LibraryFolder>(
                    predicate: #Predicate<LibraryFolder> { $0.parentPath == nil }
                )
                let folders = try context.fetch(topFolders)
                for folder in folders {
                    folder.isPrimary = (folder.urlPath == urlPath)
                }
            }

            try context.save()
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to mark folder as primary: \(error.localizedDescription)")
        }
    }

    /// Load primary folders (isPrimary=true or parentPath=nil).
    func loadPrimaryFolders() -> [(String, Data, String?, Bool)] {
        do {
            let descriptor = FetchDescriptor<LibraryFolder>(
                predicate: #Predicate<LibraryFolder> { $0.isPrimary || $0.parentPath == nil }
            )
            let folders = try context.fetch(descriptor)
            return folders.map { ($0.urlPath, $0.bookmarkData, $0.parentPath, $0.isPrimary) }
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to load primary folders: \(error.localizedDescription)")
            return []
        }
    }

    /// Load subfolders of a given parent path.
    func loadSubfolders(parentPath: String) -> [(String, Data, String?, Bool)] {
        let descriptor = FetchDescriptor<LibraryFolder>(
            predicate: #Predicate { $0.parentPath == parentPath }
        )
        do {
            let folders = try context.fetch(descriptor)
            return folders.map { ($0.urlPath, $0.bookmarkData, $0.parentPath, $0.isPrimary) }
        } catch {
            LoggerService.error(category: "ROMRepository", "Failed to load subfolders: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Mapping Helpers

    /// Create a ROM struct from a ROMEntry @Model.
    private func rom(from entry: ROMEntry) -> ROM? {
        let metadata: ROMMetadata? = entry.metadataJSON.flatMap {
            let decoder = JSONDecoder()
            return try? decoder.decode(ROMMetadata.self, from: Data($0.utf8))
        }

        let screenshotPaths: [URL] = entry.screenshotPathsJSON.flatMap {
            let decoder = JSONDecoder()
            return try? decoder.decode([String].self, from: Data($0.utf8))
        }?.map { URL(fileURLWithPath: $0) } ?? []

        let settings: ROMSettings? = entry.settingsJSON.flatMap {
            let decoder = JSONDecoder()
            return try? decoder.decode(ROMSettings.self, from: Data($0.utf8))
        }

        return ROM(
            id: entry.id,
            name: entry.name,
            path: URL(fileURLWithPath: entry.path),
            systemID: entry.systemID,
            isFavorite: entry.isFavorite,
            lastPlayed: entry.lastPlayed,
            totalPlaytimeSeconds: entry.totalPlaytimeSeconds,
            timesPlayed: entry.timesPlayed,
            selectedCoreID: entry.selectedCoreID,
            customName: entry.customName,
            useCustomCore: entry.useCustomCore,
            metadata: metadata,
            isBios: entry.isBios,
            isHidden: entry.isHidden,
            category: entry.category,
            crc32: entry.crc32,
            thumbnailLookupSystemID: entry.thumbnailLookupSystemID,
            screenshotPaths: screenshotPaths,
            settings: settings ?? ROMSettings()
        )
    }

    private static let sharedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Create a ROMEntry @Model from a ROM struct.
    private func romEntry(from rom: ROM) -> ROMEntry {
        let metadataJSON: String? = rom.metadata.flatMap {
            return String(data: try! Self.sharedEncoder.encode($0), encoding: .utf8)
        }

        let screenshotPathsJSON: String? = {
            let paths = rom.screenshotPaths.map { $0.path }
            return String(data: try! Self.sharedEncoder.encode(paths), encoding: .utf8)
        }()

        let settingsJSON: String? = {
            return String(data: try! Self.sharedEncoder.encode(rom.settings), encoding: .utf8)
        }()

        return ROMEntry(
            id: rom.id,
            name: rom.name,
            path: rom.path,
            systemID: rom.systemID,
            isFavorite: rom.isFavorite,
            lastPlayed: rom.lastPlayed,
            totalPlaytimeSeconds: rom.totalPlaytimeSeconds,
            timesPlayed: rom.timesPlayed,
            selectedCoreID: rom.selectedCoreID,
            customName: rom.customName,
            useCustomCore: rom.useCustomCore,
            metadataJSON: metadataJSON,
            isBios: rom.isBios,
            isHidden: rom.isHidden,
            category: rom.category,
            crc32: rom.crc32,
            thumbnailLookupSystemID: rom.thumbnailLookupSystemID,
            screenshotPathsJSON: screenshotPathsJSON,
            settingsJSON: settingsJSON,
            isIdentified: false
        )
    }

    /// Update an existing ROMEntry with data from a ROM struct.
    private func updateROMEntry(_ entry: ROMEntry, from rom: ROM) {
        if entry.name != rom.name { entry.name = rom.name }
        if entry.path != rom.path.path { entry.path = rom.path.path }
        if entry.systemID != rom.systemID { entry.systemID = rom.systemID }
        if entry.isFavorite != rom.isFavorite { entry.isFavorite = rom.isFavorite }
        if entry.lastPlayed != rom.lastPlayed { entry.lastPlayed = rom.lastPlayed }
        if entry.totalPlaytimeSeconds != rom.totalPlaytimeSeconds { entry.totalPlaytimeSeconds = rom.totalPlaytimeSeconds }
        if entry.timesPlayed != rom.timesPlayed { entry.timesPlayed = rom.timesPlayed }
        if entry.selectedCoreID != rom.selectedCoreID { entry.selectedCoreID = rom.selectedCoreID }
        if entry.customName != rom.customName { entry.customName = rom.customName }
        if entry.useCustomCore != rom.useCustomCore { entry.useCustomCore = rom.useCustomCore }
        if entry.isBios != rom.isBios { entry.isBios = rom.isBios }
        if entry.isHidden != rom.isHidden { entry.isHidden = rom.isHidden }
        if entry.category != rom.category { entry.category = rom.category }
        if entry.crc32 != rom.crc32 { entry.crc32 = rom.crc32 }
        if entry.thumbnailLookupSystemID != rom.thumbnailLookupSystemID { entry.thumbnailLookupSystemID = rom.thumbnailLookupSystemID }

        // Update JSON fields only if they changed
        let newMetadataJSON: String? = rom.metadata.flatMap {
            return String(data: try! Self.sharedEncoder.encode($0), encoding: .utf8)
        }
        if entry.metadataJSON != newMetadataJSON { entry.metadataJSON = newMetadataJSON }

        let newScreenshotPathsJSON: String? = {
            let paths = rom.screenshotPaths.map { $0.path }
            return String(data: try! Self.sharedEncoder.encode(paths), encoding: .utf8)
        }()
        if entry.screenshotPathsJSON != newScreenshotPathsJSON { entry.screenshotPathsJSON = newScreenshotPathsJSON }

        let newSettingsJSON: String? = {
            return String(data: try! Self.sharedEncoder.encode(rom.settings), encoding: .utf8)
        }()
        if entry.settingsJSON != newSettingsJSON { entry.settingsJSON = newSettingsJSON }
    }
}
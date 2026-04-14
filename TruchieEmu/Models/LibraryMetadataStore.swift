import Foundation
import SwiftData

/// Single-file library metadata (migrated to SwiftData ROMMetadataEntry).
struct ROMLibraryMetadataFile: Codable {
    var version: Int = 1
    /// Key: standardized filesystem path to the ROM file.
    var entries: [String: ROMMetadataRecord] = [:]
}

/// Persisted fields for one ROM; extends beyond `ROMMetadata` with hashes and asset paths.
struct ROMMetadataRecord: Codable, Hashable {
    var crc32: String?
    var title: String?
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var players: Int?
    var description: String?
    var rating: Double?
    var cooperative: Bool?
    var esrbRating: String?
    /// Matches `ROM.thumbnailLookupSystemID` for Libretro CDN.
    var thumbnailLookupSystemID: String?
    /// Whether this ROM has box art.
    var hasBoxArt: Bool
    /// Reserved: title screen / Libretro Named_Titles.
    var titleScreenPath: String?
    /// Array of screenshot image paths for the game
    var screenshotPaths: [String] = []
    /// Custom core ID selected by the user for this ROM.
    var customCoreID: String?

    init() {
        hasBoxArt = false
    }

    init(from rom: ROM) {
        crc32 = rom.crc32
        title = rom.metadata?.title
        year = rom.metadata?.year
        developer = rom.metadata?.developer
        publisher = rom.metadata?.publisher
        genre = rom.metadata?.genre
        players = rom.metadata?.players
        description = rom.metadata?.description
        // rating field removed from ROMMetadata
        cooperative = rom.metadata?.cooperative
        esrbRating = rom.metadata?.esrbRating
        thumbnailLookupSystemID = rom.thumbnailLookupSystemID
        hasBoxArt = rom.hasBoxArt
        titleScreenPath = nil
        screenshotPaths = rom.screenshotPaths.map { $0.path }
    }

    func applying(to rom: ROM) -> ROM {
        var r = rom
        r.crc32 = crc32 ?? r.crc32
        var meta = r.metadata ?? ROMMetadata()
        if let title { meta.title = title }
        if let year { meta.year = year }
        if let developer { meta.developer = developer }
        if let publisher { meta.publisher = publisher }
        if let genre { meta.genre = genre }
        if let players { meta.players = players }
        if let description { meta.description = description }
        // rating field removed from ROMMetadata
        if let cooperative { meta.cooperative = cooperative }
        if let esrbRating { meta.esrbRating = esrbRating }
        r.metadata = meta
        if let t = thumbnailLookupSystemID { r.thumbnailLookupSystemID = t }
        r.hasBoxArt = hasBoxArt
        if !screenshotPaths.isEmpty {
            r.screenshotPaths = screenshotPaths.compactMap {
                let url = URL(fileURLWithPath: $0)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }
        return r
    }
}

// MARK: - SwiftData helpers

extension ROMMetadataEntry {
    static func from(pathKey: String, record: ROMMetadataRecord) -> ROMMetadataEntry {
        let screenshotJSON: String?
        if !record.screenshotPaths.isEmpty,
           let data = try? JSONEncoder().encode(record.screenshotPaths),
           let str = String(data: data, encoding: .utf8) {
            screenshotJSON = str
        } else {
            screenshotJSON = nil
        }
        return ROMMetadataEntry(
            pathKey: pathKey,
            crc32: record.crc32,
            title: record.title,
            year: record.year,
            developer: record.developer,
            publisher: record.publisher,
            genre: record.genre,
            players: record.players,
            gameDescription: record.description,
            rating: record.rating,
            cooperative: record.cooperative,
            esrbRating: record.esrbRating,
            thumbnailSystemID: record.thumbnailLookupSystemID,
            hasBoxArt: record.hasBoxArt,
            titleScreenPath: record.titleScreenPath,
            screenshotPathsJSON: screenshotJSON,
            customCoreID: record.customCoreID
        )
    }

    func toRecord() -> ROMMetadataRecord {
        var record = ROMMetadataRecord()
        record.crc32 = crc32
        record.title = title
        record.year = year
        record.developer = developer
        record.publisher = publisher
        record.genre = genre
        record.players = players
        record.description = gameDescription
        record.rating = rating
        record.cooperative = cooperative
        record.esrbRating = esrbRating
        record.thumbnailLookupSystemID = thumbnailSystemID
        record.hasBoxArt = hasBoxArt
        record.titleScreenPath = titleScreenPath
        record.customCoreID = customCoreID
        if let json = screenshotPathsJSON,
           let data = json.data(using: .utf8),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            record.screenshotPaths = paths
        }
        return record
    }
}

@MainActor
final class LibraryMetadataStore: ObservableObject {
    static let shared = LibraryMetadataStore()

    // MARK: - In-memory cache

    private var entries: [String: ROMMetadataRecord] = [:]
    private let context: ModelContext

    /// Track which entries have been modified in memory but not yet flushed to SwiftData.
    private var dirtyKeys: Set<String> = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Legacy JSON migration

    private var legacyFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/library_metadata.json", isDirectory: false)
    }

    private init() {
        self.context = SwiftDataContainer.shared.mainContext
        migrateLegacyJSONToSwiftData()
        loadChildrenFromSwiftData()
    }

    private func migrateLegacyJSONToSwiftData() {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }
        // Check if we already migrated
        let descriptor = FetchDescriptor<ROMMetadataEntry>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else {
            LoggerService.info(category: "MetadataStore", "SwiftData already has metadata entries, skipping JSON migration")
            let migratedURL = legacyFileURL.appendingPathExtension("migrated")
            try? FileManager.default.moveItem(at: legacyFileURL, to: migratedURL)
            return
        }

        LoggerService.info(category: "MetadataStore", "Migrating library_metadata.json to SwiftData")
        do {
            let rawData = try Data(contentsOf: legacyFileURL)
            let file = try decoder.decode(ROMLibraryMetadataFile.self, from: rawData)

            if !file.entries.isEmpty {
                for (key, record) in file.entries {
                    let entry = ROMMetadataEntry.from(pathKey: key, record: record)
                    context.insert(entry)
                }
                try context.save()
                LoggerService.info(category: "MetadataStore", "Migrated \(file.entries.count) metadata entries to SwiftData")
            }

            let migratedURL = legacyFileURL.appendingPathExtension("migrated")
            try FileManager.default.moveItem(at: legacyFileURL, to: migratedURL)
        } catch {
            LoggerService.warning(category: "MetadataStore", "JSON migration failed: \(error.localizedDescription)")
        }
    }

    private func loadChildrenFromSwiftData() {
        let descriptor = FetchDescriptor<ROMMetadataEntry>()
        do {
            let loaded = try context.fetch(descriptor)
            for entry in loaded {
                entries[entry.pathKey] = entry.toRecord()
            }
            LoggerService.info(category: "MetadataStore", "Loaded \(loaded.count) metadata entries from SwiftData")
        } catch {
            LoggerService.error(category: "MetadataStore", "Failed to load metadata: \(error.localizedDescription)")
        }
    }

    static func pathKey(for rom: ROM) -> String {
        rom.path.standardizedFileURL.path
    }

    /// Flush entire cache to SwiftData (used on init after sidecar migration).
    private func flushAllToSwiftData() {
        do {
            let descriptor = FetchDescriptor<ROMMetadataEntry>()
            let existing = try context.fetch(descriptor)
            let existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.pathKey, $0) })

            for (key, record) in entries {
                if let model = existingMap[key] {
                    updateEntryFromRecord(model, record)
                } else {
                    let entry = ROMMetadataEntry.from(pathKey: key, record: record)
                    context.insert(entry)
                }
            }
            try context.save()
        } catch {
            LoggerService.error(category: "MetadataStore", "Failed to flush metadata: \(error.localizedDescription)")
        }
    }

    private func updateEntryFromRecord(_ entry: ROMMetadataEntry, _ record: ROMMetadataRecord) {
        entry.crc32 = record.crc32
        entry.title = record.title
        entry.year = record.year
        entry.developer = record.developer
        entry.publisher = record.publisher
        entry.genre = record.genre
        entry.players = record.players
        entry.gameDescription = record.description
        entry.rating = record.rating
        entry.cooperative = record.cooperative
        entry.esrbRating = record.esrbRating
        entry.thumbnailSystemID = record.thumbnailLookupSystemID
        entry.hasBoxArt = record.hasBoxArt
        entry.titleScreenPath = record.titleScreenPath
        entry.customCoreID = record.customCoreID
        if !record.screenshotPaths.isEmpty,
           let data = try? JSONEncoder().encode(record.screenshotPaths),
           let str = String(data: data, encoding: .utf8) {
            entry.screenshotPathsJSON = str
        }
    }

    func mergedROM(_ rom: ROM) -> ROM {
        guard let rec = entries[Self.pathKey(for: rom)] else { return rom }
        return rec.applying(to: rom)
    }

    func persist(rom: ROM) {
        let key = Self.pathKey(for: rom)
        var rec = ROMMetadataRecord(from: rom)

        // Preserve fields that aren't in ROM but in the record
        if let existing = entries[key] {
            if rec.titleScreenPath == nil { rec.titleScreenPath = existing.titleScreenPath }
            if rec.screenshotPaths.isEmpty && !existing.screenshotPaths.isEmpty {
                rec.screenshotPaths = existing.screenshotPaths
            }
        }

        entries[key] = rec
        dirtyKeys.insert(key)
        objectWillChange.send()
    }

    /// Flush only dirty entries to SwiftData. More efficient than flushAllToSwiftData()
    /// when only a subset of ROMs have been modified.
    func flushDirtyToSwiftData() {
        guard !dirtyKeys.isEmpty else { return }
        let keysToFlush = dirtyKeys
        dirtyKeys.removeAll()

        do {
            let descriptor = FetchDescriptor<ROMMetadataEntry>()
            let existing = try context.fetch(descriptor)
            let existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.pathKey, $0) })

            for key in keysToFlush {
                guard let record = entries[key] else { continue }
                if let model = existingMap[key] {
                    updateEntryFromRecord(model, record)
                } else {
                    let entry = ROMMetadataEntry.from(pathKey: key, record: record)
                    context.insert(entry)
                }
            }
            try context.save()
        } catch {
            LoggerService.error(category: "MetadataStore", "Failed to flush dirty metadata: \(error.localizedDescription)")
        }
    }

    /// Batch flush all in-memory entries to SwiftData.
    /// Call this after a batch operation (e.g., scan, import) instead of per-ROM persist().
    func flushToSwiftData() {
        guard !entries.isEmpty else { return }
        flushAllToSwiftData()
    }

    private func upsertMetadataEntry(key: String, record: ROMMetadataRecord) {
        let descriptor = FetchDescriptor<ROMMetadataEntry>(
            predicate: #Predicate { $0.pathKey == key }
        )
        do {
            let results = try context.fetch(descriptor)
            if let existing = results.first {
                updateEntryFromRecord(existing, record)
            } else {
                let entry = ROMMetadataEntry.from(pathKey: key, record: record)
                context.insert(entry)
            }
            try context.save()
        } catch {
            LoggerService.error(category: "MetadataStore", "Failed to persist metadata: \(error.localizedDescription)")
        }
    }

    private func importLegacySidecarJSON(roms: [ROM]) {
        var any = false
        for rom in roms {
            let key = Self.pathKey(for: rom)
            guard entries[key] == nil else { continue }
            guard let jsonData = try? Data(contentsOf: rom.infoLocalPath),
                  let meta = try? decoder.decode(ROMMetadata.self, from: jsonData) else { continue }
            var r = rom
            r.metadata = meta
            entries[key] = ROMMetadataRecord(from: r)
            upsertMetadataEntry(key: key, record: ROMMetadataRecord(from: r))
            any = true
        }
        if any { objectWillChange.send() }
    }

    /// Imports legacy `<name>_info.json` when the central file has no entries yet.
    func migrateLegacySidecarsIfStoreEmpty(roms: [ROM]) {
        guard entries.isEmpty else { return }
        importLegacySidecarJSON(roms: roms)
    }

    // MARK: - Custom Core Management

    func customCore(for rom: ROM) -> String? {
        entries[Self.pathKey(for: rom)]?.customCoreID
    }

    func setCustomCore(_ coreID: String, for rom: ROM) {
        let key = Self.pathKey(for: rom)
        if entries[key] == nil {
            entries[key] = ROMMetadataRecord(from: rom)
        }
        entries[key]?.customCoreID = coreID
        upsertMetadataEntry(key: key, record: entries[key]!)
        objectWillChange.send()
    }

    func clearCustomCore(for rom: ROM) {
        let key = Self.pathKey(for: rom)
        entries[key]?.customCoreID = nil
        if let rec = entries[key] {
            upsertMetadataEntry(key: key, record: rec)
        }
        objectWillChange.send()
    }

    // MARK: - Deletion

    func deleteAllMetadata() {
        entries.removeAll()
        let descriptor = FetchDescriptor<ROMMetadataEntry>()
        do {
            let allItems = try context.fetch(descriptor)
            for item in allItems { context.delete(item) }
            try context.save()
            LoggerService.info(category: "MetadataStore", "Deleted all metadata entries.")
        } catch {
            LoggerService.error(category: "MetadataStore", "Failed to delete all metadata: \(error.localizedDescription)")
        }
    }

    func deleteMetadata(for rom: ROM) {
        deleteMetadataEntry(Self.pathKey(for: rom))
    }

    /// Delete a metadata entry by its path key.
    func deleteMetadataEntry(_ key: String) {
        deleteMetadataEntries(Set([key]))
    }

    /// Delete multiple metadata entries by their path keys in a single batch.
    /// This avoids the massive overhead of multiple context.save() calls.
    func deleteMetadataEntries(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        
        for key in keys { entries.removeValue(forKey: key) }
        
        do {
            // Predicate with too many items can fail, so if keys.count is large, 
            // fetch all and filter or chunk. Given metadata count is usually reachable,
            // fetching all relevant items is safest and fastest.
            let descriptor = FetchDescriptor<ROMMetadataEntry>()
            let allItems = try context.fetch(descriptor)
            let itemsToDelete = allItems.filter { keys.contains($0.pathKey) }
            
            for item in itemsToDelete {
                context.delete(item)
            }
            
            if !itemsToDelete.isEmpty {
                try context.save()
                LoggerService.info(category: "MetadataStore", "Deleted \(itemsToDelete.count) metadata entries in bulk.")
            }
        } catch {
            LoggerService.error(category: "MetadataStore", "Failed to delete metadata entries: \(error.localizedDescription)")
        }
    }
}

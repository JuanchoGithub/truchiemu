import Foundation

/// Single-file library metadata (migrated to SQLite rom_metadata table).
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
    /// Cached box art path (usually beside the ROM).
    var boxArtPath: String?
    /// Reserved: title screen / Libretro Named_Titles.
    var titleScreenPath: String?
    /// Array of screenshot image paths for the game
    var screenshotPaths: [String] = []
    /// Custom core ID selected by the user for this ROM.
    var customCoreID: String?

    init() {}

    init(from rom: ROM) {
        crc32 = rom.crc32
        title = rom.metadata?.title
        year = rom.metadata?.year
        developer = rom.metadata?.developer
        publisher = rom.metadata?.publisher
        genre = rom.metadata?.genre
        players = rom.metadata?.players
        description = rom.metadata?.description
        rating = rom.metadata?.rating
        cooperative = rom.metadata?.cooperative
        esrbRating = rom.metadata?.esrbRating
        thumbnailLookupSystemID = rom.thumbnailLookupSystemID
        boxArtPath = rom.boxArtPath?.path
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
        if let rating { meta.rating = rating }
        if let cooperative { meta.cooperative = cooperative }
        if let esrbRating { meta.esrbRating = esrbRating }
        r.metadata = meta
        if let t = thumbnailLookupSystemID { r.thumbnailLookupSystemID = t }
        if let p = boxArtPath, FileManager.default.fileExists(atPath: p) {
            r.boxArtPath = URL(fileURLWithPath: p)
        }
        if !screenshotPaths.isEmpty {
            r.screenshotPaths = screenshotPaths.compactMap {
                let url = URL(fileURLWithPath: $0)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }
        return r
    }
}

// MARK: - DatabaseManager.MetadataRowInt helpers

extension DatabaseManager.MetadataRowInt {
    init(pathKey: String, record: ROMMetadataRecord) {
        self.pathKey = pathKey
        self.crc32 = record.crc32
        self.title = record.title
        self.year = record.year
        self.developer = record.developer
        self.publisher = record.publisher
        self.genre = record.genre
        self.players = record.players
        self.description = record.description
        self.rating = record.rating
        self.thumbnailSystemID = record.thumbnailLookupSystemID
        self.boxArtPath = record.boxArtPath
        self.titleScreenPath = record.titleScreenPath
        if !record.screenshotPaths.isEmpty,           let data = try? JSONEncoder().encode(record.screenshotPaths),           let str = String(data: data, encoding: .utf8) {
            self.screenshotPathsJSON = str
        } else {
            self.screenshotPathsJSON = nil
        }
        self.customCoreID = record.customCoreID
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
        record.description = description
        record.rating = rating
        record.thumbnailLookupSystemID = thumbnailSystemID
        record.boxArtPath = boxArtPath
        record.titleScreenPath = titleScreenPath
        record.customCoreID = customCoreID
        if let json = screenshotPathsJSON,           let data = json.data(using: .utf8),           let paths = try? JSONDecoder().decode([String].self, from: data) {
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
        migrateLegacyJSONToSQLite()
        loadChildrenFromSQLite()
    }

    private func migrateLegacyJSONToSQLite() {
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }
        // Check if we already migrated (no entries in SQLite for this)
        let existingCount = DatabaseManager.shared.metadataEntryCount()
        guard existingCount == 0 else {
            LoggerService.info(category: "MetadataStore", "SQLite already has metadata entries, skipping JSON migration")
            // Still rename the JSON file if it exists to avoid double-migration attempt
            let migratedURL = legacyFileURL.appendingPathExtension("migrated")
            try? FileManager.default.moveItem(at: legacyFileURL, to: migratedURL)
            return
        }

        LoggerService.info(category: "MetadataStore", "Migrating library_metadata.json to SQLite")
        do {
            let rawData = try Data(contentsOf: legacyFileURL)
            let file = try decoder.decode(ROMLibraryMetadataFile.self, from: rawData)

            if !file.entries.isEmpty {
                let rows = file.entries.map { DatabaseManager.MetadataRowInt(pathKey: $0.key, record: $0.value) }
                DatabaseManager.shared.bulkUpsertMetadataEntries(rows)
                LoggerService.info(category: "MetadataStore", "Migrated \(rows.count) metadata entries to SQLite")
            }

            // Rename the old file
            let migratedURL = legacyFileURL.appendingPathExtension("migrated")
            try FileManager.default.moveItem(at: legacyFileURL, to: migratedURL)
        } catch {
            LoggerService.warning(category: "MetadataStore", "JSON migration failed: \(error.localizedDescription)")
        }
    }

    private func loadChildrenFromSQLite() {
        let rows = DatabaseManager.shared.loadAllMetadataEntries()
        for row in rows {
            entries[row.pathKey] = row.toRecord()
        }
        LoggerService.info(category: "MetadataStore", "Loaded \(rows.count) metadata entries from SQLite")
    }

    static func pathKey(for rom: ROM) -> String {
        rom.path.standardizedFileURL.path
    }

    /// Flush entire cache to SQLite (used on init after sidecar migration and after bulk operations).
    private func flushAllToSQLite() {
        let rows = entries.map { DatabaseManager.MetadataRowInt(pathKey: $0.key, record: $0.value) }
        DatabaseManager.shared.bulkUpsertMetadataEntries(rows)
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

        // Upsert single row to SQLite
        DatabaseManager.shared.upsertMetadataEntry(DatabaseManager.MetadataRowInt(pathKey: key, record: rec))
        objectWillChange.send()
    }

    private func importLegacySidecarJSON(roms: [ROM]) {
        var any = false
        for rom in roms {
            let key = Self.pathKey(for: rom)
            guard entries[key] == nil else { continue }
            guard let jsonData = try? Data(contentsOf: rom.infoLocalPath),
                  let meta = try? decoder.decode(ROMMetadata.self, from: jsonData) else { continue }
            var r = rom
            if r.metadata == nil { r.metadata = meta } else {
                r.metadata = meta
            }
            entries[key] = ROMMetadataRecord(from: r)
            DatabaseManager.shared.upsertMetadataEntry(DatabaseManager.MetadataRowInt(pathKey: key, record: ROMMetadataRecord(from: r)))
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
        let row = DatabaseManager.MetadataRowInt(pathKey: key, record: entries[key]!)
        DatabaseManager.shared.upsertMetadataEntry(row)
        objectWillChange.send()
    }

    func clearCustomCore(for rom: ROM) {
        let key = Self.pathKey(for: rom)
        entries[key]?.customCoreID = nil
        if let rec = entries[key] {
            DatabaseManager.shared.upsertMetadataEntry(DatabaseManager.MetadataRowInt(pathKey: key, record: rec))
        }
        objectWillChange.send()
    }
}

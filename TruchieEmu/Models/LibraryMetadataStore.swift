import Foundation

/// Single-file library metadata (Application Support/TruchieEmu/library_metadata.json).
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
    /// Matches `ROM.thumbnailLookupSystemID` for Libretro CDN.
    var thumbnailLookupSystemID: String?
    /// Cached box art path (usually beside the ROM).
    var boxArtPath: String?
    /// Reserved: title screen / Libretro Named_Titles.
    var titleScreenPath: String?
    /// Reserved: snap / screenshot.
    var screenshotPath: String?

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
        thumbnailLookupSystemID = rom.thumbnailLookupSystemID
        boxArtPath = rom.boxArtPath?.path
        titleScreenPath = nil
        screenshotPath = nil
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
        r.metadata = meta
        if let t = thumbnailLookupSystemID { r.thumbnailLookupSystemID = t }
        if let p = boxArtPath, FileManager.default.fileExists(atPath: p) {
            r.boxArtPath = URL(fileURLWithPath: p)
        }
        return r
    }
}

@MainActor
final class LibraryMetadataStore: ObservableObject {
    static let shared = LibraryMetadataStore()

    private var data = ROMLibraryMetadataFile()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/library_metadata.json", isDirectory: false)
    }

    private init() {
        loadFromDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let raw = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(ROMLibraryMetadataFile.self, from: raw) else {
            return
        }
        data = decoded
    }

    func saveToDisk() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let out = try? encoder.encode(data) else { return }
        let tmp = fileURL.appendingPathExtension("tmp")
        do {
            try out.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } catch {
            try? out.write(to: fileURL, options: .atomic)
            try? FileManager.default.removeItem(at: tmp)
        }
        objectWillChange.send()
    }

    static func pathKey(for rom: ROM) -> String {
        rom.path.standardizedFileURL.path
    }

    func mergedROM(_ rom: ROM) -> ROM {
        guard let rec = data.entries[Self.pathKey(for: rom)] else { return rom }
        return rec.applying(to: rom)
    }

    func persist(rom: ROM) {
        var rec = ROMMetadataRecord(from: rom)
        if let existing = data.entries[Self.pathKey(for: rom)] {
            if rec.titleScreenPath == nil { rec.titleScreenPath = existing.titleScreenPath }
            if rec.screenshotPath == nil { rec.screenshotPath = existing.screenshotPath }
        }
        data.entries[Self.pathKey(for: rom)] = rec
        saveToDisk()
    }

    private func importLegacySidecarJSON(roms: [ROM]) {
        var any = false
        for rom in roms {
            let key = Self.pathKey(for: rom)
            guard data.entries[key] == nil else { continue }
            guard let jsonData = try? Data(contentsOf: rom.infoLocalPath),
                  let meta = try? decoder.decode(ROMMetadata.self, from: jsonData) else { continue }
            var r = rom
            if r.metadata == nil { r.metadata = meta } else {
                r.metadata = meta
            }
            data.entries[key] = ROMMetadataRecord(from: r)
            any = true
        }
        if any { saveToDisk() }
    }

    /// Imports legacy `<name>_info.json` when the central file has no entries yet.
    func migrateLegacySidecarsIfStoreEmpty(roms: [ROM]) {
        guard data.entries.isEmpty else { return }
        importLegacySidecarJSON(roms: roms)
    }
}

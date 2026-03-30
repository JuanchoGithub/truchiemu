import Foundation

struct ROM: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: URL
    var systemID: String?
    var boxArtPath: URL?
    var isFavorite: Bool = false
    var lastPlayed: Date?
    var selectedCoreID: String?
    var customName: String?
    var useCustomCore: Bool = false
    var metadata: ROMMetadata?
    /// No-Intro / identification CRC32 (hex), persisted in library metadata file.
    var crc32: String?
    /// Libretro thumbnail CDN folder (`Nintendo - Game Boy` vs `GBC`) when identification matched a different DB (e.g. GB ROM in merged GB+GBC set).
    var thumbnailLookupSystemID: String?
    var settings: ROMSettings = ROMSettings()

    // Derived
    var displayName: String { customName ?? metadata?.title ?? name }
    var fileExtension: String { path.pathExtension.lowercased() }

    /// Post-scan automation: fetch No-Intro title when missing.
    var needsAutomaticIdentification: Bool {
        if customName != nil { return false }
        let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty
    }

    /// Post-scan automation: fetch art when no file on disk yet.
    var needsAutomaticBoxArt: Bool {
        let fm = FileManager.default
        if let p = boxArtPath, fm.fileExists(atPath: p.path) { return false }
        return !fm.fileExists(atPath: boxArtLocalPath.path)
    }

    // Persistent storage paths
    var boxArtLocalPath: URL {
        path.deletingLastPathComponent()
            .appendingPathComponent("boxart")
            .appendingPathComponent("\(name)_boxart.jpg")
    }
    
    var infoLocalPath: URL {
        path.deletingLastPathComponent()
            .appendingPathComponent("\(name)_info.json")
    }
}

struct ROMSettings: Codable, Hashable {
    var crtEnabled: Bool = false
    var scanlinesEnabled: Bool = true
    var scanlineIntensity: Float = 0.35
    var barrelEnabled: Bool = false
    var barrelAmount: Float = 0.12
    var phosphorEnabled: Bool = false
    var scanlineSmooth: Bool = false
    var colorBoost: Float = 1.0
    var bezelStyle: String = "none"
}

struct ROMMetadata: Codable, Hashable {
    var title: String?
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var players: Int?
    var description: String?
    var rating: Double?
}

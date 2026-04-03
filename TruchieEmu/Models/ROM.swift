import Foundation

struct ROM: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: URL
    var systemID: String?
    var boxArtPath: URL?
    var isFavorite: Bool = false
    var lastPlayed: Date?
    /// Total playtime across all sessions (in seconds)
    var totalPlaytimeSeconds: Double = 0
    /// Number of times this game has been launched
    var timesPlayed: Int = 0
    var selectedCoreID: String?
    var customName: String?
    var useCustomCore: Bool = false
    var metadata: ROMMetadata?
    
    // MARK: - BIOS & Categorization
    /// Whether this ROM is a BIOS file (not a playable game)
    var isBios: Bool = false
    /// Whether this ROM should be hidden from the main game list
    var isHidden: Bool = false
    /// Category: "game", "bios", "system"
    var category: String = "game"
    /// No-Intro / identification CRC32 (hex), persisted in library metadata file.
    var crc32: String?
    /// Libretro thumbnail CDN folder (`Nintendo - Game Boy` vs `GBC`) when identification matched a different DB (e.g. GB ROM in merged GB+GBC set).
    var thumbnailLookupSystemID: String?
    /// Array of screenshot image paths for the game
    var screenshotPaths: [URL] = []
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
    var crtEnabled: Bool = true
    var scanlinesEnabled: Bool = true
    var scanlineIntensity: Float = 0.35
    var barrelEnabled: Bool = true
    var barrelAmount: Float = 0.12
    var phosphorEnabled: Bool = true
    var scanlineSmooth: Bool = false
    var colorBoost: Float = 1.0
    
    // Legacy bezel style (deprecated - use bezelFileName instead)
    var bezelStyle: String = "none"
    
    // New shader preset system
    var shaderPresetID: String = "builtin-crt-classic"  // Default to CRT Classic
    
    // Bezel: filename of the selected bezel, empty = auto-detect, "none" = disabled
    var bezelFileName: String = ""
    
    // MARK: - Game Boy Colorization
    /// Whether to apply color palettes to original Game Boy (DMG) games.
    /// Defaults to true (colorization enabled). Only relevant for GB system games.
    var gbColorizationEnabled: Bool = true
    
    /// Colorization mode for Game Boy games.
    /// "auto" = auto-select best palette, "disabled" = monochrome
    /// Maps to gambatte's gb_colorization, mGBA's model, sameboy's model
    var gbColorizationMode: String = "auto"
    
    // Check if using legacy toggle-based shaders (for migration)
    var isLegacyShaderMode: Bool {
        return shaderPresetID.isEmpty
    }
    
    /// Migrate from legacy toggle-based shaders to preset system
    mutating func migrateFromLegacyShaders() {
        guard isLegacyShaderMode else { return }
        
        if crtEnabled || scanlinesEnabled || barrelEnabled || phosphorEnabled {
            // User had custom CRT settings - use CRT Classic preset
            shaderPresetID = "builtin-crt-classic"
        } else {
            // No shaders enabled - use raw pixels
            shaderPresetID = "builtin-none"
        }
    }
    
    /// Migrate legacy bezelStyle to bezelFileName
    mutating func migrateFromLegacyBezels() {
        // Legacy bezelStyle only had simple styles, no specific bezel assignment
        // This is a no-op since we're moving to per-game bezel selection
        // The bezelStyle value is kept for backward compatibility but not used for new bezel system
    }
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
    /// Whether the game supports cooperative (co-op) play.
    var cooperative: Bool?
    /// ESRB rating (e.g. "E", "E10+", "T", "M", "AO", "RP").
    var esrbRating: String?
}

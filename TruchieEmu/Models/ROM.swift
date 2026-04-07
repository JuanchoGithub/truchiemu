import Foundation

struct ROM: Identifiable, Codable, Hashable, Sendable {
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
    /// MAME ROM type: "game", "bios", "device", "mechanical" (nil if not a MAME ROM)
    var mameRomType: String?
    /// No-Intro / identification CRC32 (hex), persisted in library metadata file.
    var crc32: String?
    /// Libretro thumbnail CDN folder (`Nintendo - Game Boy` vs `GBC`) when identification matched a different DB (e.g. GB ROM in merged GB+GBC set).
    var thumbnailLookupSystemID: String?
    /// Array of screenshot image paths for the game
    var screenshotPaths: [URL] = []
    var settings: ROMSettings = ROMSettings()
    
    // Derived
    var displayName: String {
        // If custom name is set, use it
        if let custom = customName {
            return GameNameFormatter.stripTags(custom)
        }
        
        // For MAME games, try to get the human-readable description from the lookup database
        if let mameEntry = MAMEImportService.lookup(shortName: shortNameForMAME) {
            return GameNameFormatter.stripTags(mameEntry.description)
        }
        
        // Fall back to metadata title or filename
        let baseName = metadata?.title ?? displayNameFromROM()
        return GameNameFormatter.stripTags(baseName)
    }
    
    /// Returns the ROM filename without extension as a fallback display name.
    private func displayNameFromROM() -> String {
        path.deletingPathExtension().lastPathComponent
    }
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
            .appendingPathComponent("\(path.lastPathComponent)_boxart.png")
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
    
    /// Which internal palette to use when mode is "internal".
    var gbInternalPalette: String = "GB - DMG"
    
    /// Whether to use SGB borders when a Super Game Boy enhanced game is detected.
    /// Works with mGBA's "GB: Borders" option.
    var gbSGBBordersEnabled: Bool = true
    
    /// Color correction (Gambatte core only).
    var gbColorCorrectionMode: String = "gbc_only"
}

struct ROMMetadata: Codable, Hashable {
    var genre: String?
    var publisher: String?
    var developer: String?
    var description: String?
    var title: String?
    var releaseDate: String?
    var players: Int = 1
    var year: String?
    
    // ESRB & other ratings
    var esrbRating: String?
    var cooperative: Bool = false
    
    // MAME 2003+ video/display metadata
    /// Screen orientation: "vertical" or "horizontal"
    var orientation: String?
    /// Aspect ratio X component (e.g., 3 for 3:4 vertical, 4 for 4:3 horizontal)
    var aspectX: Int?
    /// Aspect ratio Y component
    var aspectY: Int?
    /// Native screen width in pixels
    var screenWidth: Int?
    /// Native screen height in pixels
    var screenHeight: Int?
    /// Refresh rate in Hz
    var refreshRate: Double?
    /// Screen type: "raster" or "vector"
    var screenType: String?
    /// CPU name
    var cpuName: String?
    /// CPU clock speed in Hz
    var cpuClock: Double?
    /// Audio chip names
    var audioChips: [String]?
}

// MARK: - MAME Helpers

extension ROM {
    /// Get the MAME short name from the ROM.
    /// Falls back to filename without extension.
    var shortNameForMAME: String {
        // Always use filename without extension — this is the canonical MAME short name
        filenameWithoutExtension
    }
    
    /// Get filename without extension and lowercase.
    var filenameWithoutExtension: String {
        let name = path.lastPathComponent
            .replacingOccurrences(of: ".zip", with: "")
            .replacingOccurrences(of: ".7z", with: "")
            .replacingOccurrences(of: ".rom", with: "")
        return name.lowercased()
    }
}

// MARK: - ROM Category Enum

extension ROM {
    enum Category: String, Codable, Hashable {
        case game = "game"
        case bios = "bios"
        case system = "system"
        case homebrew = "homebrew"
        case demo = "demo"
        case prototype = "prototype"
        case translation = "translation"
        case hack = "hack"
        case unlicensed = "unlicensed"
        case pirate = "pirate"
        case afterMarket = "aftermarket"
        case betaPrototype = "beta"
        case testProgram = "test_program"
        case debugMode = "debug"
        case sample = "sample"
        
        var isPlayable: Bool {
            switch self {
            case .game, .homebrew, .hack, .translation, .unlicensed, .demo, .afterMarket:
                return true
            default:
                return false
            }
        }
    }
}
import Foundation

struct ROM: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var path: URL
    var systemID: String?
    var originalSystemID: String?
    var hasBoxArt: Bool = false
    var isFavorite: Bool = false
    var lastPlayed: Date?
    var dateAdded: Date = Date()
    // Total playtime across all sessions (in seconds)
    var totalPlaytimeSeconds: Double = 0
    // Number of times this game has been launched
    var timesPlayed: Int = 0
    var selectedCoreID: String?
    var customName: String?
    var useCustomCore: Bool = false
    var metadata: ROMMetadata?
    
    // MARK: - BIOS & Categorization
    // Whether this ROM is a BIOS file (not a playable game)
    var isBios: Bool = false
    // Whether this ROM should be hidden from the main game list
    var isHidden: Bool = false
    // Category: "game", "bios", "system"
    var category: String = "game"
    // MAME ROM type: "game", "bios", "device", "mechanical" (nil if not a MAME ROM)
    var mameRomType: String?
    // No-Intro / identification CRC32 (hex), persisted in library metadata file.
    var crc32: String?
    var md5: String?
    // Libretro thumbnail CDN folder (`Nintendo - Game Boy` vs `GBC`) when identification matched a different DB (e.g. GB ROM in merged GB+GBC set).
    var thumbnailLookupSystemID: String?
    // Array of screenshot image paths for the game
    var screenshotPaths: [URL] = []
    var settings: ROMSettings = ROMSettings()
    
    // Derived (Stored)
    var displayName: String = ""
    var fileExtension: String = ""
    var needsAutomaticIdentification: Bool = true
    var needsAutomaticBoxArt: Bool = true
    var boxArtLocalPath: URL = URL(fileURLWithPath: "")
    var infoLocalPath: URL = URL(fileURLWithPath: "")
    var shortNameForMAME: String = ""
    var filenameWithoutExtension: String = ""
    
    // For ROMs inside archives: relative path of the ROM file within the archive (e.g. "game.nes").
    // nil for regular files and archive-aware systems (MAME, ScummVM, etc.) that use the whole archive.
    var innerROMPath: String?

    // Box art region tracking
    // Which region was requested when this boxart was downloaded (e.g., "(Spain)")
    var boxArtRequestedRegion: String?
    // Which region tag was actually resolved in the URL (e.g., "(USA)" if Spain wasn't available)
    var boxArtRegionTag: String?
    // When the boxart was last downloaded/fetched
    var boxArtFetchedAt: Date?

    // RetroAchievements metadata
    var raGameId: Int?
    var raMatchStatus: String?
    var enrichmentAttempted: Bool = false
    var enrichmentFailed: Bool = false

    // Updates all stored derived properties based on current state.
    mutating func refreshDerivedFields() {
        // 1. filenameWithoutExtension
        let rawName: String
        if let inner = innerROMPath {
            rawName = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            rawName = path.lastPathComponent
                .replacingOccurrences(of: ".zip", with: "")
                .replacingOccurrences(of: ".7z", with: "")
                .replacingOccurrences(of: ".rar", with: "")
                .replacingOccurrences(of: ".rom", with: "")
        }
        self.filenameWithoutExtension = rawName.lowercased()

        // 2. shortNameForMAME
        self.shortNameForMAME = self.filenameWithoutExtension

        // 3. fileExtension
        if let inner = innerROMPath {
            self.fileExtension = URL(fileURLWithPath: inner).pathExtension.lowercased()
        } else {
            self.fileExtension = path.pathExtension.lowercased()
        }

        // 4. displayName
        if let custom = customName {
            self.displayName = GameNameFormatter.stripTags(custom)
        } else {
            let baseName = metadata?.title ?? rawName
            self.displayName = GameNameFormatter.stripTags(baseName)
        }

        // 5. needsAutomaticIdentification
        if customName != nil {
            self.needsAutomaticIdentification = false
        } else {
            let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.needsAutomaticIdentification = title.isEmpty
        }

        // 6. needsAutomaticBoxArt
        self.needsAutomaticBoxArt = !hasBoxArt

        // 7. boxArtLocalPath
        let boxartDir = path.deletingLastPathComponent().appendingPathComponent("boxart")
        let romNameWithoutExt: String
        if let inner = innerROMPath {
            romNameWithoutExt = URL(fileURLWithPath: inner).deletingPathExtension().lastPathComponent
        } else {
            romNameWithoutExt = path.deletingPathExtension().lastPathComponent
        }
        let baseName = "\(romNameWithoutExt)_boxart"
        let pngPath = boxartDir.appendingPathComponent("\(baseName).png")
        let jpgPath = boxartDir.appendingPathComponent("\(baseName).jpg")
        let jpegPath = boxartDir.appendingPathComponent("\(baseName).jpeg")

        if FileManager.default.fileExists(atPath: pngPath.path) {
            self.boxArtLocalPath = pngPath
        } else if FileManager.default.fileExists(atPath: jpgPath.path) {
            self.boxArtLocalPath = jpgPath
        } else if FileManager.default.fileExists(atPath: jpegPath.path) {
            self.boxArtLocalPath = jpegPath
        } else {
            self.boxArtLocalPath = pngPath
            if hasBoxArt {
                hasBoxArt = false
                needsAutomaticBoxArt = true
            }
        }

        // 8. infoLocalPath
        self.infoLocalPath = path.deletingLastPathComponent().appendingPathComponent("\(name)_info.json")
    }

    // Unique key for tracking running games. Includes innerROMPath when present
    // so that multiple ROMs from the same archive are tracked separately.
    var runningKey: String {
        if let inner = innerROMPath {
            return "\(path.path)!\(inner)"
        }
        return path.path
    }

    var boxArtIsExactRegion: Bool {
        guard let requested = boxArtRequestedRegion, let resolved = boxArtRegionTag else { return true }
        return requested == resolved
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
    var shaderPresetID: String = ""
    
    // Shader uniform overrides (persisted per-ROM)
    var shaderUniformOverrides: [String: Float] = [:]
    
    // Bezel: filename of the selected bezel, empty = auto-detect, "none" = disabled
    var bezelFileName: String = ""

    var cheatsEnabled: Bool? = nil
    var analogMouseEnabled: Bool? = nil
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
    var crc32: String?

    // User-set player count override — nil means no override (use library data or default).
    // If set, libretro library data will overwrite it (non-nil library data takes precedence).
    var userPlayerOverride: Int?

    // ESRB & other ratings
    var esrbRating: String?
    var cooperative: Bool = false
    
    // MAME 2003+ video/display metadata
    // Screen orientation: "vertical" or "horizontal"
    var orientation: String?
    // Aspect ratio X component (e.g 3 for 3:4 vertical, 4 for 4:3 horizontal)
    var aspectX: Int?
    // Aspect ratio Y component
    var aspectY: Int?
    // Native screen width in pixels
    var screenWidth: Int?
    // Native screen height in pixels
    var screenHeight: Int?
    // Refresh rate in Hz
    var refreshRate: Double?
    // Screen type: "raster" or "vector"
    var screenType: String?
    // CPU name
    var cpuName: String?
    // CPU clock speed in Hz
    var cpuClock: Double?
    // Audio chip names
    var audioChips: [String]?
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
import Foundation

/// Maps internal system IDs to Bezel Project repository names and configurations.
enum BezelSystemMapping {
    
    /// All supported system configurations.
    static let configurations: [String: BezelSystemConfig] = [
        // Nintendo consoles
        "nes": BezelSystemConfig(systemID: "nes", bezelProjectName: "NES"),
        "snes": BezelSystemConfig(systemID: "snes", bezelProjectName: "SNES"),
        "n64": BezelSystemConfig(systemID: "n64", bezelProjectName: "N64"),
        "gb": BezelSystemConfig(systemID: "gb", bezelProjectName: "Game-Boy"),
        "gbc": BezelSystemConfig(systemID: "gbc", bezelProjectName: "Game-Boy-Color"),
        "gba": BezelSystemConfig(systemID: "gba", bezelProjectName: "Game-Boy-Advance"),
        "nds": BezelSystemConfig(systemID: "nds", bezelProjectName: "Nintendo-DS"),
        "vb": BezelSystemConfig(systemID: "vb", bezelProjectName: "Virtual-Boy"),
        
        // Sega consoles
        "sms": BezelSystemConfig(systemID: "sms", bezelProjectName: "Sega-Master-System"),
        "genesis": BezelSystemConfig(systemID: "genesis", bezelProjectName: "Sega-Mega-Drive"),
        "megadrive": BezelSystemConfig(systemID: "genesis", bezelProjectName: "Sega-Mega-Drive"),
        "segacd": BezelSystemConfig(systemID: "segacd", bezelProjectName: "Sega-CD"),
        "gamegear": BezelSystemConfig(systemID: "gamegear", bezelProjectName: "Sega-Game-Gear"),
        "saturn": BezelSystemConfig(systemID: "saturn", bezelProjectName: "Sega-Saturn"),
        "dreamcast": BezelSystemConfig(systemID: "dreamcast", bezelProjectName: "Sega-Dreamcast"),
        
        // Sony consoles
        "psx": BezelSystemConfig(systemID: "psx", bezelProjectName: "Sony-PlayStation"),
        "ps2": BezelSystemConfig(systemID: "ps2", bezelProjectName: "Sony-PlayStation-2"),
        "psp": BezelSystemConfig(systemID: "psp", bezelProjectName: "Sony-PSP"),
        
        // Atari consoles
        "atari2600": BezelSystemConfig(systemID: "atari2600", bezelProjectName: "Atari-2600"),
        "atari5200": BezelSystemConfig(systemID: "atari5200", bezelProjectName: "Atari-5200"),
        "atari7800": BezelSystemConfig(systemID: "atari7800", bezelProjectName: "Atari-7800"),
        "lynx": BezelSystemConfig(systemID: "lynx", bezelProjectName: "Atari-Lynx"),
        "jaguar": BezelSystemConfig(systemID: "jaguar", bezelProjectName: "Atari-Jaguar"),
        
        // SNK / Neo Geo
        "ngp": BezelSystemConfig(systemID: "ngp", bezelProjectName: "Neo-Geo-Pocket"),
        "ngc": BezelSystemConfig(systemID: "ngp", bezelProjectName: "Neo-Geo-Pocket-Color"),
        "neogeo": BezelSystemConfig(systemID: "neogeo", bezelProjectName: "SNK-Neo-Geo"),
        
        // Other consoles
        "3do": BezelSystemConfig(systemID: "3do", bezelProjectName: "3DO"),
        
        // PC-Engine / TurboGrafx
        "pce": BezelSystemConfig(systemID: "pce", bezelProjectName: "PC-Engine"),
        "pcfx": BezelSystemConfig(systemID: "pcfx", bezelProjectName: "PC-FX"),
        
        // Arcade
        "mame": BezelSystemConfig(systemID: "mame", bezelProjectName: "MAME"),
        "fba": BezelSystemConfig(systemID: "fba", bezelProjectName: "FBNeo"),
        
        // Computers
        "dos": BezelSystemConfig(systemID: "dos", bezelProjectName: "MS-DOS"),
    ]
    
    /// Get the bezel configuration for a system ID.
    static func config(for systemID: String) -> BezelSystemConfig? {
        // Direct match first
        if let config = configurations[systemID] {
            return config
        }
        // Try lowercase
        let lower = systemID.lowercased()
        if let config = configurations[lower] {
            return config
        }
        // Handle alternate IDs
        switch lower {
        case "md":
            return configurations["genesis"]
        case "gg":
            return configurations["gamegear"]
        case "32x":
            return configurations["genesis"] // 32X games use Genesis bezels
        case "fc":
            return configurations["nes"]
        case "sfc":
            return configurations["snes"]
        default:
            return nil
        }
    }
    
    /// Check if a system has bezel support.
    static func hasBezelSupport(for systemID: String) -> Bool {
        return config(for: systemID) != nil
    }
    
    /// Get all system IDs that support bezels.
    static let supportedSystemIDs = Set(configurations.keys)
    
    /// Generate a raw download URL for a bezel without needing the config.
    static func rawURL(bezelProjectName: String, filename: String) -> URL? {
        let encodedFilename = filename.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? filename
        let urlString = "https://raw.githubusercontent.com/thebezelproject/bezelproject-\(bezelProjectName)/master/overlays/GameBezels/\(bezelProjectName)/\(encodedFilename)"
        return URL(string: urlString)
    }
}
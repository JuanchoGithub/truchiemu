import Foundation

// Maps internal system IDs to Bezel Project repository names and configurations.
enum BezelSystemMapping {
    
    // All supported system configurations.
    static let configurations: [String: BezelSystemConfig] = [
        // Nintendo consoles
        "nes": BezelSystemConfig(systemID: "nes", bezelProjectName: "NES"),
        "snes": BezelSystemConfig(systemID: "snes", bezelProjectName: "SNES"),
        "n64": BezelSystemConfig(systemID: "n64", bezelProjectName: "N64"),
        "gb": BezelSystemConfig(systemID: "gb", bezelProjectName: "GB"),
        "gbc": BezelSystemConfig(systemID: "gbc", bezelProjectName: "GBC"),
        "gba": BezelSystemConfig(systemID: "gba", bezelProjectName: "GBA"),
        "nds": BezelSystemConfig(systemID: "nds", bezelProjectName: "NDS"),
        "vb": BezelSystemConfig(systemID: "vb", bezelProjectName: "Virtualboy"),
        
        // Sega consoles
        "sms": BezelSystemConfig(systemID: "sms", bezelProjectName: "MasterSystem"),
        "genesis": BezelSystemConfig(systemID: "genesis", bezelProjectName: "MegaDrive"),
        "megadrive": BezelSystemConfig(systemID: "genesis", bezelProjectName: "MegaDrive"),
        "segacd": BezelSystemConfig(systemID: "segacd", bezelProjectName: "SegaCD"),
        "gamegear": BezelSystemConfig(systemID: "gamegear", bezelProjectName: "GameGear"),
        "32x": BezelSystemConfig(systemID: "32x", bezelProjectName: "Sega32X"),
        "saturn": BezelSystemConfig(systemID: "saturn", bezelProjectName: "Saturn"),
        "dreamcast": BezelSystemConfig(systemID: "dreamcast", bezelProjectName: "Dreamcast"),
        "sg1000": BezelSystemConfig(systemID: "sg1000", bezelProjectName: "SG-1000"),
        "naomi": BezelSystemConfig(systemID: "naomi", bezelProjectName: "Naomi"),
        "atomiswave": BezelSystemConfig(systemID: "atomiswave", bezelProjectName: "Atomiswave"),
        
        // Sony consoles
        "psx": BezelSystemConfig(systemID: "psx", bezelProjectName: "PSX"),
        "ps2": BezelSystemConfig(systemID: "ps2", bezelProjectName: "PS2"),
        "psp": BezelSystemConfig(systemID: "psp", bezelProjectName: "PSP"),
        
        // Atari consoles
        "atari2600": BezelSystemConfig(systemID: "atari2600", bezelProjectName: "Atari2600"),
        "atari5200": BezelSystemConfig(systemID: "atari5200", bezelProjectName: "Atari5200"),
        "atari7800": BezelSystemConfig(systemID: "atari7800", bezelProjectName: "Atari7800"),
        "lynx": BezelSystemConfig(systemID: "lynx", bezelProjectName: "AtariLynx"),
        "jaguar": BezelSystemConfig(systemID: "jaguar", bezelProjectName: "AtariJaguar"),
        "atarist": BezelSystemConfig(systemID: "atarist", bezelProjectName: "AtariST"),
        
        // SNK / Neo Geo
        "ngp": BezelSystemConfig(systemID: "ngp", bezelProjectName: "NGP"),
        "ngc": BezelSystemConfig(systemID: "ngc", bezelProjectName: "NGPC"),
        
        // Other consoles
        "3do": BezelSystemConfig(systemID: "3do", bezelProjectName: "3DO"),
        "wii": BezelSystemConfig(systemID: "wii", bezelProjectName: "Wii"),
        "3ds": BezelSystemConfig(systemID: "3ds", bezelProjectName: "N3DS"),
        "gcn": BezelSystemConfig(systemID: "gcn", bezelProjectName: "GC"),
        "colecovision": BezelSystemConfig(systemID: "colecovision", bezelProjectName: "ColecoVision"),
        "wonderswan": BezelSystemConfig(systemID: "wonderswan", bezelProjectName: "WonderSwan"),
        "wswanc": BezelSystemConfig(systemID: "wonderswan", bezelProjectName: "WonderSwan"),
        
        // PC-Engine / TurboGrafx
        "pce": BezelSystemConfig(systemID: "pce", bezelProjectName: "PCEngine"),
        "pcecd": BezelSystemConfig(systemID: "pcecd", bezelProjectName: "PCE-CD"),
        "supergrafx": BezelSystemConfig(systemID: "supergrafx", bezelProjectName: "SuperGrafx"),
        "pcfx": BezelSystemConfig(systemID: "pcfx", bezelProjectName: "PCFX"),
        
        // Arcade
        "mame": BezelSystemConfig(systemID: "mame", bezelProjectName: "MAME"),
        
        // Computers
        "amiga": BezelSystemConfig(systemID: "amiga", bezelProjectName: "Amiga"),
        "c64": BezelSystemConfig(systemID: "c64", bezelProjectName: "C64"),
        "cd32": BezelSystemConfig(systemID: "cd32", bezelProjectName: "CD32"),
        "cdtv": BezelSystemConfig(systemID: "cdtv", bezelProjectName: "CDTV"),
        "msx": BezelSystemConfig(systemID: "msx", bezelProjectName: "MSX"),
        "msx2": BezelSystemConfig(systemID: "msx2", bezelProjectName: "MSX2"),
        "zx_spectrum": BezelSystemConfig(systemID: "zx_spectrum", bezelProjectName: "ZXSpectrum"),
        "x68000": BezelSystemConfig(systemID: "x68000", bezelProjectName: "X68000"),
        "scummvm": BezelSystemConfig(systemID: "scummvm", bezelProjectName: "ScummVM"),
        
        // Famicom aliases
        "fds": BezelSystemConfig(systemID: "fds", bezelProjectName: "FDS"),
        "fc": BezelSystemConfig(systemID: "nes", bezelProjectName: "Famicom"),
        
        // SFC alias
        "sfc": BezelSystemConfig(systemID: "snes", bezelProjectName: "SFC")
    ]
    
    // Get the bezel configuration for a system ID.
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
            return configurations["32x"] // 32X has its own bezels (Sega32X)
        case "fc":
            return configurations["nes"]
        case "sfc":
            return configurations["snes"]
        default:
            return nil
        }
    }
    
    // Check if a system has bezel support.
    static func hasBezelSupport(for systemID: String) -> Bool {
        return config(for: systemID) != nil
    }
    
    // Get all system IDs that support bezels.
    static let supportedSystemIDs = Set(configurations.keys)
    
    // Generate a raw download URL for a bezel without needing the config.
    static func rawURL(bezelProjectName: String, filename: String) -> URL? {
        let encodedFilename = filename.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? filename
        let urlString = "https://raw.githubusercontent.com/thebezelproject/bezelproject-\(bezelProjectName)/master/retroarch/overlay/GameBezels/\(bezelProjectName)/\(encodedFilename)"
        return URL(string: urlString)
    }
}
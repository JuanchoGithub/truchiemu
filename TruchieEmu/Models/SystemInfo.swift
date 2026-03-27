import Foundation

struct SystemInfo: Identifiable, Codable, Hashable {
    var id: String           // e.g. "nes", "snes", "mame", "gba"
    var name: String         // e.g. "Nintendo Entertainment System"
    var manufacturer: String
    var extensions: [String] // without dot, e.g. ["nes", "fds"]
    var defaultCoreID: String?
    var iconName: String     // SF Symbol or bundled asset
    var emuIconName: String? // Name in Resources/EmulatorIcons
    var year: String?
    var sortOrder: Int

    static let all: [SystemInfo] = SystemDatabase.systems

    func emuImage(size: Int) -> NSImage? {
        guard let iconName = emuIconName else { return nil }
        let bundle = Bundle.main
        let is132 = size == 132
        
        var namesToTry = [String]()
        if is132 {
            namesToTry.append("\(iconName.lowercased())@132w")
            namesToTry.append("\(iconName.uppercased())@132w")
            namesToTry.append("\(iconName)@132w")
        } else {
            namesToTry.append(iconName)
            namesToTry.append(iconName.lowercased())
            namesToTry.append(iconName.uppercased())
        }
        
        let subdirs = [
            "EmulatorIcons/\(size)",
            "\(size)",
            "EmulatorIcons",
            ""
        ]
        
        for name in namesToTry {
            // 1. Try NSImage(named:)
            if let img = NSImage(named: name) { return img }
            if let img = NSImage(named: "\(name).png") { return img }
            if let img = NSImage(named: NSImage.Name(name)) { return img }
            
            // 2. Try URL lookup in various subdirs
            for subdir in subdirs {
                for ext in ["png", "PNG"] {
                    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                        if let img = NSImage(contentsOf: url) {
                            return img
                        }
                    }
                }
            }
        }
        
        // Final fallback: search the whole bundle resources folder
        for name in namesToTry {
            if let path = bundle.path(forResource: name, ofType: "png") {
                if let img = NSImage(contentsOfFile: path) { return img }
            }
        }
        
        // Development fallback: check source directory directly
        let sourcePath = "/Users/jayjay/gitrepos/truchiemu/TruchieEmu/Resources/EmulatorIcons"
        for name in namesToTry {
            let fullPath = "\(sourcePath)/\(size)/\(name).png"
            if FileManager.default.fileExists(atPath: fullPath) {
                return NSImage(contentsOfFile: fullPath)
            }
            // Try different dir structure
            let altPath = "\(sourcePath)/\(name).png"
            if FileManager.default.fileExists(atPath: altPath) {
                return NSImage(contentsOfFile: altPath)
            }
        }
        
        return nil
    }
}

// MARK: - Known system list (seeded locally, refreshed from core-info repo)
enum SystemDatabase {
    static let systems: [SystemInfo] = [
        SystemInfo(id: "nes",          name: "Nintendo Entertainment System",   manufacturer: "Nintendo",   extensions: ["nes", "fds", "unf", "unif"], defaultCoreID: "nestopia_libretro",           iconName: "gamecontroller", emuIconName: "FC",       year: "1983", sortOrder: 1),
        SystemInfo(id: "snes",         name: "Super Nintendo",                  manufacturer: "Nintendo",   extensions: ["snes", "smc", "sfc", "fig", "bs"],  defaultCoreID: "snes9x_libretro",      iconName: "gamecontroller", emuIconName: "SFC",      year: "1990", sortOrder: 2),
        SystemInfo(id: "n64",          name: "Nintendo 64",                     manufacturer: "Nintendo",   extensions: ["n64", "v64", "z64", "ndd"],  defaultCoreID: "mupen64plus_next_libretro",   iconName: "gamecontroller", emuIconName: "N64",      year: "1996", sortOrder: 3),
        SystemInfo(id: "psx",          name: "PlayStation",                     manufacturer: "Sony",       extensions: ["cue", "toc", "m3u", "pbp"],   defaultCoreID: "mednafen_psx_libretro",      iconName: "opticaldisc",    emuIconName: "PS",       year: "1994", sortOrder: 20),
        SystemInfo(id: "gba",          name: "Game Boy Advance",                manufacturer: "Nintendo",   extensions: ["gba"],                        defaultCoreID: "mgba_libretro",              iconName: "iphone",         emuIconName: "GBA",      year: "2001", sortOrder: 4),
        SystemInfo(id: "gb",           name: "Game Boy",                        manufacturer: "Nintendo",   extensions: ["gb"],                         defaultCoreID: "mgba_libretro",              iconName: "iphone",         emuIconName: "GB",       year: "1989", sortOrder: 5),
        SystemInfo(id: "gbc",          name: "Game Boy Color",                  manufacturer: "Nintendo",   extensions: ["gbc"],                        defaultCoreID: "mgba_libretro",              iconName: "iphone",         emuIconName: "GBC",      year: "1998", sortOrder: 6),
        SystemInfo(id: "nds",          name: "Nintendo DS",                     manufacturer: "Nintendo",   extensions: ["nds", "dsi"],                 defaultCoreID: "desmume_libretro",           iconName: "ipad",           emuIconName: "NDS",      year: "2004", sortOrder: 7),
        SystemInfo(id: "genesis",      name: "Sega Genesis / Mega Drive",       manufacturer: "Sega",       extensions: ["md", "gen", "bin", "smd"],    defaultCoreID: "genesis_plus_gx_libretro",   iconName: "gamecontroller.fill", emuIconName: "MD",  year: "1988", sortOrder: 10),
        SystemInfo(id: "sms",          name: "Sega Master System",              manufacturer: "Sega",       extensions: ["sms"],                        defaultCoreID: "genesis_plus_gx_libretro",   iconName: "gamecontroller.fill", emuIconName: "MS",  year: "1985", sortOrder: 11),
        SystemInfo(id: "gamegear",     name: "Sega Game Gear",                  manufacturer: "Sega",       extensions: ["gg"],                         defaultCoreID: "genesis_plus_gx_libretro",   iconName: "iphone",         emuIconName: "GG",       year: "1990", sortOrder: 12),
        SystemInfo(id: "saturn",       name: "Sega Saturn",                     manufacturer: "Sega",       extensions: ["cue", "toc", "m3u"],          defaultCoreID: "mednafen_saturn_libretro",   iconName: "opticaldisc",    emuIconName: "SATURN",   year: "1994", sortOrder: 13),
        SystemInfo(id: "dreamcast",    name: "Sega Dreamcast",                  manufacturer: "Sega",       extensions: ["cdi", "gdi", "chd"],          defaultCoreID: "flycast_libretro",           iconName: "opticaldisc",    emuIconName: "DC",       year: "1998", sortOrder: 14),
        SystemInfo(id: "ps2",          name: "PlayStation 2",                   manufacturer: "Sony",       extensions: ["iso", "chd"],                 defaultCoreID: "pcsx2_libretro",             iconName: "opticaldisc",    emuIconName: "PS",       year: "2000", sortOrder: 21),
        SystemInfo(id: "psp",          name: "PlayStation Portable",            manufacturer: "Sony",       extensions: ["iso", "cso", "pbp"],          defaultCoreID: "ppsspp_libretro",            iconName: "ipad.landscape", emuIconName: "PSP",      year: "2004", sortOrder: 22),
        SystemInfo(id: "mame",         name: "Arcade (MAME)",                   manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "mame2003_plus_libretro",     iconName: "arcade.stick",   emuIconName: "MAME",     year: nil,    sortOrder: 30),
        SystemInfo(id: "fba",          name: "Arcade (FinalBurn Neo)",          manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "fbneo_libretro",             iconName: "arcade.stick",   emuIconName: "FBNEO",    year: nil,    sortOrder: 31),
        SystemInfo(id: "atari2600",    name: "Atari 2600",                      manufacturer: "Atari",      extensions: ["a26", "bin"],                 defaultCoreID: "stella_libretro",            iconName: "gamecontroller", emuIconName: "ATARI2600", year: "1977", sortOrder: 40),
        SystemInfo(id: "atari5200",    name: "Atari 5200",                      manufacturer: "Atari",      extensions: ["a52", "bin"],                 defaultCoreID: "a5200_libretro",             iconName: "gamecontroller", emuIconName: "ATARI5200", year: "1982", sortOrder: 41),
        SystemInfo(id: "atari7800",    name: "Atari 7800",                      manufacturer: "Atari",      extensions: ["a78", "bin"],                 defaultCoreID: "prosystem_libretro",         iconName: "gamecontroller", emuIconName: "ATARI7800", year: "1986", sortOrder: 42),
        SystemInfo(id: "lynx",         name: "Atari Lynx",                      manufacturer: "Atari",      extensions: ["lnx"],                        defaultCoreID: "handy_libretro",             iconName: "iphone.landscape", emuIconName: "LYNX",     year: "1989", sortOrder: 43),
        SystemInfo(id: "ngp",          name: "Neo Geo Pocket",                  manufacturer: "SNK",        extensions: ["ngp", "ngc"],                 defaultCoreID: "mednafen_ngp_libretro",      iconName: "iphone",         emuIconName: "NGP",      year: "1998", sortOrder: 50),
        SystemInfo(id: "pce",          name: "PC Engine / TurboGrafx-16",       manufacturer: "NEC",        extensions: ["pce", "cue"],                 defaultCoreID: "mednafen_pce_libretro",      iconName: "gamecontroller", emuIconName: "PCE",      year: "1987", sortOrder: 60),
        SystemInfo(id: "pcfx",         name: "PC-FX",                           manufacturer: "NEC",        extensions: ["cue", "toc"],                 defaultCoreID: "mednafen_pcfx_libretro",     iconName: "opticaldisc",    emuIconName: "PCFX",     year: "1994", sortOrder: 61),
    ]


    static func system(forExtension ext: String) -> SystemInfo? {
        let lower = ext.lowercased()
        return systems.first { $0.extensions.contains(lower) }
    }

    static func system(forID id: String) -> SystemInfo? {
        systems.first { $0.id == id }
    }
}

// MARK: - Views and Layout preferences
import SwiftUI
import Combine

enum BoxType: String, CaseIterable, Identifiable {
    case vertical = "Vertical"
    case box = "Box"
    case landscape = "Landscape"
    
    var id: String { self.rawValue }

    var aspectRatio: CGFloat {
        switch self {
        case .vertical: return 3.0 / 4.0
        case .box: return 1.0
        case .landscape: return 4.0 / 3.0
        }
    }
    
    var iconName: String {
        switch self {
        case .vertical: return "rectangle.portrait"
        case .box: return "square"
        case .landscape: return "rectangle"
        }
    }
}

enum EmulatorLanguage: Int, CaseIterable, Identifiable {
    case english = 0
    case japanese = 1
    case french = 2
    case german = 3
    case spanish = 4
    case italian = 5
    case dutch = 6
    case portuguese = 7
    case russian = 8
    case korean = 9
    case chineseTraditional = 10
    case chineseSimplified = 11
    case esperanto = 12
    case polish = 13
    case vietnamese = 14
    case arabic = 15
    case greek = 16
    case turkish = 17
    case britishEnglish = 28
    
    var id: Int { self.rawValue }
    
    var name: String {
        switch self {
        case .english: return "English"
        case .japanese: return "Japanese"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .dutch: return "Dutch"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .korean: return "Korean"
        case .chineseTraditional: return "Chinese (Trad)"
        case .chineseSimplified: return "Chinese (Simp)"
        case .esperanto: return "Esperanto"
        case .polish: return "Polish"
        case .vietnamese: return "Vietnamese"
        case .arabic: return "Arabic"
        case .greek: return "Greek"
        case .turkish: return "Turkish"
        case .britishEnglish: return "British English"
        }
    }
}

enum CoreLogLevel: Int, CaseIterable, Identifiable {
    case info = 0
    case warn = 1
    case error = 2
    case none = 3
    
    var id: Int { self.rawValue }
    var name: String {
        switch self {
        case .info: return "All Logs"
        case .warn: return "Warnings & Errors"
        case .error: return "Errors Only"
        case .none: return "No Logs"
        }
    }
}

class SystemPreferences: ObservableObject {
    static let shared = SystemPreferences()
    @Published var updateTrigger: Int = 0
    
    @Published var systemLanguage: EmulatorLanguage = .english {
        didSet {
            UserDefaults.standard.set(systemLanguage.rawValue, forKey: "systemLanguage")
            updateTrigger += 1
        }
    }
    
    @Published var coreLogLevel: CoreLogLevel = .warn {
        didSet {
            UserDefaults.standard.set(coreLogLevel.rawValue, forKey: "coreLogLevel")
            updateTrigger += 1
        }
    }

    init() {
        let langRaw = UserDefaults.standard.integer(forKey: "systemLanguage")
        self.systemLanguage = EmulatorLanguage(rawValue: langRaw) ?? .english
        let logRaw = UserDefaults.standard.object(forKey: "coreLogLevel") as? Int ?? CoreLogLevel.warn.rawValue
        self.coreLogLevel = CoreLogLevel(rawValue: logRaw) ?? .warn
    }
    
    func boxType(for systemID: String) -> BoxType {
        let rawValue = UserDefaults.standard.string(forKey: "boxType_\(systemID)") ?? BoxType.vertical.rawValue
        return BoxType(rawValue: rawValue) ?? .vertical
    }
    
    func setBoxType(_ type: BoxType, for systemID: String) {
        UserDefaults.standard.set(type.rawValue, forKey: "boxType_\(systemID)")
        updateTrigger += 1
    }

    func preferredCoreID(for systemID: String) -> String? {
        UserDefaults.standard.string(forKey: "preferredCore_\(systemID)")
    }

    func setPreferredCoreID(_ coreID: String?, for systemID: String) {
        UserDefaults.standard.set(coreID, forKey: "preferredCore_\(systemID)")
        updateTrigger += 1
    }
}

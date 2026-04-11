import Foundation
import SwiftUI // Required for @Published in SystemPreferences and LibretroInfoManager

// MARK: - Box Type (must be before SystemInfo since SystemInfo uses it)
enum BoxType: String, CaseIterable, Identifiable, Codable {
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

// MARK: - Known MAME/Arcade BIOS Files
enum KnownBIOS {
    static let mameFiles: Set<String> = [
        "neogeo", "cpzn1", "cpzn2", "cvs", "decocass", "konamigx",
        "nmk004", "pgm", "playch10", "skns", "stvbios", "vmax3",
        "eeprom", "f355dlx", "gaelco", "gaelco2", "gq863", "isgsm",
        "itoch3", "midssio", "nba99hsk", "nscd15", "ssv", "ym2608",
        "coh1000c", "coh3002c", "ym2413", "cchip", "sprc2kb", "segas16b",
        "skimaxx", "cworld", "k054539", "n64sound", "dc_boot", "dc_flash",
        "naomi", "hod2bios", "awbios", "cis4.5b", "cis4.5c",
        "gts1s", "gts1", "gts1h", "gts1a", "gts1b", "gts1c", "gts1d", "gts1e", "gts1f", "gts1g",
        "gts1h2", "gts1h3", "gts1h4", "gts1h5", "gts1h6", "gts1h7", "gts1h8", "gts1h9",
        "model2", "model2a", "model2b", "model2c", "model3a", "model3b", "model3c", "model3d",
        "system16", "system18", "system24", "system32", "system24e",
        "cps1", "cps2", "cps2a", "cps2b", "cps_changer",
        "pgm", "pgma", "pgmb", "pgmc", "pgmd", "pgme", "pgmf",
        "taito_f3", "taito_gnet", "taito_type1", "taito_type2", "taito_type3",
        "atomiswave", "naomi2", "naomigd", "hikaru", "lindbergh",
        "neocdz", "ym2610", "ym2612", "ym3438", "ymf278b", "ymf271",
        "cv1000", "m72", "m84", "m90", "m92", "m107",
        "jalmah", "jaleco_gambl", "airlet", "taito_f1", "taito_f2"
    ]
    
    static func isKnownBios(filename: String) -> Bool {
        let nameWithoutExt = (filename as NSString).deletingPathExtension.lowercased()
        return mameFiles.contains(nameWithoutExt)
    }
}

struct SystemInfo: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var manufacturer: String
    var extensions: [String]
    var defaultCoreID: String?
    var iconName: String
    var emuIconName: String?
    var year: String?
    var sortOrder: Int
    var defaultBoxType: BoxType = .vertical
    var displayInUI: Bool = true

    /// The aspect ratio reported directly by the Libretro core.
    var coreReportedAspectRatio: CGFloat?

    /// The correct display aspect ratio for this system's output.
    /// RESOLVED FIXME: Uses coreReportedAspectRatio if available, else falls back to system defaults.
    var displayAspectRatio: CGFloat {
        if let coreAR = coreReportedAspectRatio, coreAR > 0.0 {
            return coreAR
        }
        
        switch id {
        case "psx", "ps1", "ps2", "n64", "saturn", "dreamcast", "3do":
            return 4.0 / 3.0
        case "nds":
            return 2.0 / 3.0
        default:
            return 4.0 / 3.0
        }
    }
    
    func emuImage(size: Int) -> NSImage? {
        LoggerService.extreme(category: "SystemInfo", "Loading emu image for system: \(id)")
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
        
        let subdirs = [ "EmulatorIcons/\(size)", "\(size)", "EmulatorIcons", "" ]
        
        for name in namesToTry {
            if let img = NSImage(named: name) { return img }
            if let img = NSImage(named: "\(name).png") { return img }
            if let img = NSImage(named: NSImage.Name(name)) { return img }
            
            for subdir in subdirs {
                for ext in ["png", "PNG"] {
                    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                        if let img = NSImage(contentsOf: url) { return img }
                    }
                }
            }
        }
        
        for name in namesToTry {
            LoggerService.extreme(category: "SystemInfo", "Loading emu image for system: \(id) with name: \(name)")
            if let path = bundle.path(forResource: name, ofType: "png") {
                if let img = NSImage(contentsOfFile: path) { return img }
            }
        }
        return nil
    }
    
    var sidebarDisplayName: String {
        switch id {
        case "nes": return "Nintendo NES"
        case "genesis": return "Sega Genesis"
        default: return name
        }
    }
}

// MARK: - SystemDatabase
class SystemDatabase {
    private static let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TruchieEmu", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("SystemDatabase.json")
    }()

    /// Changed from `let` to `var` so LibretroInfoManager and AspectRatio fetching can update it dynamically
    static var systems: [SystemInfo] = loadSystems()

    static let defaultSystems: [SystemInfo] = [
        SystemInfo(id: "nes",          name: "Nintendo Entertainment System",   manufacturer: "Nintendo",   extensions: ["nes", "fds", "unf", "unif"], defaultCoreID: "nestopia_libretro",           iconName: "gamecontroller", emuIconName: "FC",       year: "1983", sortOrder: 1, defaultBoxType: .vertical),
        SystemInfo(id: "snes",         name: "Super Nintendo",                  manufacturer: "Nintendo",   extensions: ["snes", "smc", "sfc", "fig", "bs"],  defaultCoreID: "snes9x_libretro",      iconName: "gamecontroller", emuIconName: "SFC",      year: "1990", sortOrder: 2, defaultBoxType: .vertical),
        SystemInfo(id: "n64",          name: "Nintendo 64",                     manufacturer: "Nintendo",   extensions: ["n64", "v64", "z64", "ndd"],  defaultCoreID: "mupen64plus_next_libretro",   iconName: "gamecontroller", emuIconName: "N64",      year: "1996", sortOrder: 3, defaultBoxType: .landscape),
        SystemInfo(id: "psx",          name: "PlayStation",                     manufacturer: "Sony",       extensions: ["cue", "toc", "m3u", "pbp"],   defaultCoreID: "mednafen_psx_libretro",      iconName: "opticaldisc",    emuIconName: "PS",       year: "1994", sortOrder: 20, defaultBoxType: .landscape),
        SystemInfo(id: "gba",          name: "Game Boy Advance",                manufacturer: "Nintendo",   extensions: ["gba"],                        defaultCoreID: "mgba_libretro",              iconName: "iphone",         emuIconName: "GBA",      year: "2001", sortOrder: 4, defaultBoxType: .vertical),
        SystemInfo(id: "gb",           name: "Game Boy",                        manufacturer: "Nintendo",   extensions: ["gb"],                         defaultCoreID: "mgba_libretro",              iconName: "iphone",         emuIconName: "GB",       year: "1989", sortOrder: 5, defaultBoxType: .vertical),
        SystemInfo(id: "gbc",          name: "Game Boy Color",                  manufacturer: "Nintendo",   extensions: ["gbc"],                        defaultCoreID: "mgba_libretro",              iconName: "iphone",         emuIconName: "GBC",      year: "1998", sortOrder: 6, defaultBoxType: .vertical, displayInUI: false),
        SystemInfo(id: "nds",          name: "Nintendo DS",                     manufacturer: "Nintendo",   extensions: ["nds", "dsi"],                 defaultCoreID: "desmume_libretro",           iconName: "ipad",           emuIconName: "NDS",      year: "2004", sortOrder: 7, defaultBoxType: .landscape),
        SystemInfo(id: "genesis",      name: "Sega Genesis / Mega Drive",       manufacturer: "Sega",       extensions: ["md", "gen", "bin", "smd"],    defaultCoreID: "genesis_plus_gx_libretro",   iconName: "gamecontroller.fill", emuIconName: "MD",  year: "1988", sortOrder: 10, defaultBoxType: .vertical),
        SystemInfo(id: "sms",          name: "Sega Master System",              manufacturer: "Sega",       extensions: ["sms"],                        defaultCoreID: "genesis_plus_gx_libretro",   iconName: "gamecontroller.fill", emuIconName: "MS",  year: "1985", sortOrder: 11, defaultBoxType: .vertical),
        SystemInfo(id: "gamegear",     name: "Sega Game Gear",                  manufacturer: "Sega",       extensions: ["gg"],                         defaultCoreID: "genesis_plus_gx_libretro",   iconName: "iphone",         emuIconName: "GG",       year: "1990", sortOrder: 12, defaultBoxType: .vertical),
        SystemInfo(id: "32x",          name: "Sega 32X",                        manufacturer: "Sega",       extensions: ["32x", "smd", "bin", "md"],     defaultCoreID: "picodrive_libretro",         iconName: "gamecontroller.fill", emuIconName: "32X",  year: "1994", sortOrder: 15, defaultBoxType: .vertical),
        SystemInfo(id: "saturn",       name: "Sega Saturn",                     manufacturer: "Sega",       extensions: ["cue", "toc", "m3u"],          defaultCoreID: "mednafen_saturn_libretro",   iconName: "opticaldisc",    emuIconName: "SATURN",   year: "1994", sortOrder: 13, defaultBoxType: .landscape),
        SystemInfo(id: "3do",          name: "3DO",                             manufacturer: "Panasonic",  extensions: ["iso", "bin", "cue", "chd"],   defaultCoreID: "opera_libretro",             iconName: "opticaldisc",    emuIconName: "3DO",      year: "1993", sortOrder: 16, defaultBoxType: .landscape),
        SystemInfo(id: "dreamcast",    name: "Sega Dreamcast",                  manufacturer: "Sega",       extensions: ["cdi", "gdi", "chd"],          defaultCoreID: "flycast_libretro",           iconName: "opticaldisc",    emuIconName: "DC",       year: "1998", sortOrder: 14, defaultBoxType: .landscape),
        SystemInfo(id: "ps2",          name: "PlayStation 2",                   manufacturer: "Sony",       extensions: ["iso", "chd"],                 defaultCoreID: "play_libretro",             iconName: "opticaldisc",    emuIconName: "PS",       year: "2000", sortOrder: 21, defaultBoxType: .landscape),
        SystemInfo(id: "psp",          name: "PlayStation Portable",            manufacturer: "Sony",       extensions: ["iso", "cso", "pbp"],          defaultCoreID: "ppsspp_libretro",            iconName: "ipad.landscape", emuIconName: "PSP",      year: "2004", sortOrder: 22, defaultBoxType: .landscape),
        SystemInfo(id: "mame",         name: "Arcade (MAME)",                   manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "mame2010_libretro",     iconName: "arcade.stick",   emuIconName: "MAME",     year: nil,    sortOrder: 30, defaultBoxType: .vertical),
        SystemInfo(id: "fba",          name: "Arcade (FinalBurn Neo)",          manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "fbneo_libretro",             iconName: "arcade.stick",   emuIconName: "FBNEO",    year: nil,    sortOrder: 31, defaultBoxType: .vertical),
        SystemInfo(id: "atari2600",    name: "Atari 2600",                      manufacturer: "Atari",      extensions: ["a26", "bin"],                 defaultCoreID: "stella_libretro",            iconName: "gamecontroller", emuIconName: "ATARI2600", year: "1977", sortOrder: 40, defaultBoxType: .vertical),
        SystemInfo(id: "atari5200",    name: "Atari 5200",                      manufacturer: "Atari",      extensions: ["a52", "bin"],                 defaultCoreID: "a5200_libretro",             iconName: "gamecontroller", emuIconName: "ATARI5200", year: "1982", sortOrder: 41, defaultBoxType: .vertical),
        SystemInfo(id: "atari7800",    name: "Atari 7800",                      manufacturer: "Atari",      extensions: ["a78", "bin"],                 defaultCoreID: "prosystem_libretro",         iconName: "gamecontroller", emuIconName: "ATARI7800", year: "1986", sortOrder: 42, defaultBoxType: .vertical),
        SystemInfo(id: "lynx",         name: "Atari Lynx",                      manufacturer: "Atari",      extensions: ["lnx"],                        defaultCoreID: "handy_libretro",             iconName: "iphone.landscape", emuIconName: "LYNX",     year: "1989", sortOrder: 43, defaultBoxType: .vertical),
        SystemInfo(id: "jaguar",       name: "Atari Jaguar",                    manufacturer: "Atari",      extensions: ["j64", "jag"],                 defaultCoreID: "virtualjaguar_libretro",     iconName: "gamecontroller", emuIconName: "JAGUAR",   year: "1993", sortOrder: 44, defaultBoxType: .vertical),
        SystemInfo(id: "ngp",          name: "Neo Geo Pocket",                  manufacturer: "SNK",        extensions: ["ngp", "ngc"],                 defaultCoreID: "mednafen_ngp_libretro",      iconName: "iphone",         emuIconName: "NGP",      year: "1998", sortOrder: 50, defaultBoxType: .vertical),
        SystemInfo(id: "pce",          name: "PC Engine / TurboGrafx-16",       manufacturer: "NEC",        extensions: ["pce", "cue"],                 defaultCoreID: "mednafen_pce_libretro",      iconName: "gamecontroller", emuIconName: "PCE",      year: "1987", sortOrder: 60, defaultBoxType: .landscape),
        SystemInfo(id: "pcfx",         name: "PC-FX",                           manufacturer: "NEC",        extensions: ["cue", "toc"],                 defaultCoreID: "mednafen_pcfx_libretro",     iconName: "opticaldisc",    emuIconName: "PCFX",     year: "1994", sortOrder: 61, defaultBoxType: .landscape),
        SystemInfo(id: "scummvm",      name: "ScummVM",                         manufacturer: "Various",    extensions: ["zip", "scummvm"],             defaultCoreID: "scummvm_libretro",           iconName: "gamecontroller", emuIconName: "SCUMMVM", year: nil,    sortOrder: 75, defaultBoxType: .landscape),
        SystemInfo(id: "dos",          name: "MS-DOS",                          manufacturer: "Microsoft",  extensions: ["zip", "dosz", "conf", "exe", "bat", "iso", "img", "cue", "ins"], defaultCoreID: "dosbox_pure_libretro", iconName: "desktopcomputer", emuIconName: "DOS", year: "1981", sortOrder: 70, defaultBoxType: .landscape),
        SystemInfo(id: "unknown",      name: "Unknown System",                  manufacturer: "Unknown",    extensions: ["*"],          defaultCoreID: nil,                        iconName: "questionmark.circle",   emuIconName: nil,    year: nil,    sortOrder: 99, defaultBoxType: .vertical),
    ]

    static func loadSystems() -> [SystemInfo] {
        LoggerService.debug(category: "SystemDatabase", "Loading systems")
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([SystemInfo].self, from: data) else {
            return defaultSystems
        }
        return decoded
    }
    
    static func saveSystems(_ updatedSystems: [SystemInfo]) {
        LoggerService.debug(category: "SystemDatabase", "Saving systems")
        self.systems = updatedSystems.sorted { $0.sortOrder < $1.sortOrder }
        if let data = try? JSONEncoder().encode(self.systems) {
            try? data.write(to: cacheURL)
        }
    }

    static var systemsForDisplay: [SystemInfo] { systems.filter { $0.displayInUI } }

    static func allInternalIDs(forDisplayID id: String) -> [String] {
        switch id {
        case "gb", "gbc": return ["gb", "gbc"]
        default: return [id]
        }
    }

    static func displaySystem(forInternalID id: String) -> SystemInfo? {
        switch id {
        case "gbc": return systems.first { $0.id == "gb" }
        default: return systems.first { $0.id == id }
        }
    }

    static func system(forExtension ext: String) -> SystemInfo? {
        let lower = ext.lowercased()
        return systems.first { $0.extensions.contains(lower) }
    }

    static func system(forID id: String) -> SystemInfo? {
        systems.first { $0.id == id }
    }
}

// MARK: - Language and Log Level enums
enum EmulatorLanguage: Int, CaseIterable, Identifiable {
    case english = 0, japanese = 1, french = 2, german = 3, spanish = 4, italian = 5
    case dutch = 6, portuguese = 7, russian = 8, korean = 9, chineseTraditional = 10
    case chineseSimplified = 11, esperanto = 12, polish = 13, vietnamese = 14
    case arabic = 15, greek = 16, turkish = 17, britishEnglish = 28
    
    var id: Int { self.rawValue }
    
    var noIntroRegionPreference: [String] {
        switch self {
        case .english: return ["(USA)", "(World)", "(En,", "(En)", "(U)"]
        case .britishEnglish: return ["(Europe)", "(UK)", "(En,", "(World)"]
        case .japanese: return ["(Japan)", "(JP)", "(Ja)"]
        case .french: return ["(France)", "(Europe)", "(World)", "(Fr,", "(Fr)"]
        case .german: return ["(Germany)", "(Europe)", "(World)", "(De,", "(De)"]
        case .spanish: return ["(Spain)", "(Europe)", "(World)", "(Es,", "(Es)", "(USA)"]
        case .italian: return ["(Italy)", "(Europe)", "(World)", "(It,", "(It)"]
        case .dutch: return ["(Netherlands)", "(Europe)", "(World)", "(Nl)"]
        case .portuguese: return ["(Brazil)", "(Portugal)", "(Europe)", "(World)"]
        case .russian: return ["(Russia)", "(Europe)", "(World)", "(Ru)"]
        case .korean: return ["(Korea)", "(KR)", "(Ko)"]
        case .chineseTraditional: return ["(Taiwan)", "(Hong Kong)", "(Traditional)"]
        case .chineseSimplified: return ["(China)", "(Simplified)"]
        case .esperanto: return ["(World)", "(Europe)"]
        case .polish: return ["(Poland)", "(Europe)", "(World)"]
        case .vietnamese: return ["(Vietnam)"]
        case .arabic: return ["(Arab world)"]
        case .greek: return ["(Greece)", "(Europe)", "(World)"]
        case .turkish: return ["(Turkey)", "(Europe)", "(World)"]
        }
    }

    var flagEmoji: String {
        switch self {
        case .english: return "🇺🇸"
        case .japanese: return "🇯🇵"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .spanish: return "🇪🇸"
        case .italian: return "🇮🇹"
        case .dutch: return "🇳🇱"
        case .portuguese: return "🇧🇷"
        case .russian: return "🇷🇺"
        case .korean: return "🇰🇷"
        case .chineseTraditional: return "🇹🇼"
        case .chineseSimplified: return "🇨🇳"
        case .esperanto: return "🌍"
        case .polish: return "🇵🇱"
        case .vietnamese: return "🇻🇳"
        case .arabic: return "🇸🇦"
        case .greek: return "🇬🇷"
        case .turkish: return "🇹🇷"
        case .britishEnglish: return "🇬🇧"
        }
    }

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
    case info = 0, warn = 1, error = 2, none = 3
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

    private static let keyShowBiosFiles = "showBiosFiles"
    private static let keyShowHiddenMAMEFiles = "showHiddenMAMEFiles"
    private static let keySystemLanguage = "systemLanguage"
    private static let keyCoreLogLevel = "coreLogLevel"
    private static let keyApplyCheatsOnLaunch = "applyCheatsOnLaunch"
    private static let keyShowCheatNotifications = "showCheatNotifications"
    private static let keyBoxTypePrefix = "boxType_"
    private static let keyPreferredCorePrefix = "preferredCore_"

    @Published var showBiosFiles: Bool = false {
        didSet { AppSettings.setBool(Self.keyShowBiosFiles, value: showBiosFiles); updateTrigger += 1 }
    }

    @Published var showHiddenMAMEFiles: Bool = false {
        didSet { AppSettings.setBool(Self.keyShowHiddenMAMEFiles, value: showHiddenMAMEFiles); updateTrigger += 1 }
    }

    @Published var systemLanguage: EmulatorLanguage = .english {
        didSet { AppSettings.set(Self.keySystemLanguage, value: String(systemLanguage.rawValue)); updateTrigger += 1 }
    }

    @Published var coreLogLevel: CoreLogLevel = .warn {
        didSet { AppSettings.set(Self.keyCoreLogLevel, value: String(coreLogLevel.rawValue)); updateTrigger += 1 }
    }

    func boxType(for systemID: String) -> BoxType {
        let key = "\(Self.keyBoxTypePrefix)\(systemID)"
        if let rawValue = AppSettings.get(key, type: String.self), let type = BoxType(rawValue: rawValue) { return type }
        return SystemDatabase.system(forID: systemID)?.defaultBoxType ?? .vertical
    }

    func setBoxType(_ type: BoxType, for systemID: String) {
        AppSettings.set("\(Self.keyBoxTypePrefix)\(systemID)", value: type.rawValue)
        updateTrigger += 1
    }

    @Published var applyCheatsOnLaunch: Bool = false {
        didSet { AppSettings.setBool(Self.keyApplyCheatsOnLaunch, value: applyCheatsOnLaunch)}
    }

    @Published var showCheatNotifications: Bool = true {
        didSet { AppSettings.setBool(Self.keyShowCheatNotifications, value: showCheatNotifications) }
    }

    func preferredCoreID(for systemID: String) -> String? {
        AppSettings.get("\(Self.keyPreferredCorePrefix)\(systemID)", type: String.self)
    }

    func setPreferredCoreID(_ coreID: String?, for systemID: String) {
        AppSettings.set("\(Self.keyPreferredCorePrefix)\(systemID)", value: coreID ?? "")
        updateTrigger += 1
        LoggerService.debug(category: "SystemPreferences", "Set Preferred core ID for \(systemID): \(coreID)")
    }

    init() {
        self.showBiosFiles = AppSettings.getBool(Self.keyShowBiosFiles, defaultValue: false)
        self.showHiddenMAMEFiles = AppSettings.getBool(Self.keyShowHiddenMAMEFiles, defaultValue: false)
        let langRaw = Int(AppSettings.get(Self.keySystemLanguage, type: String.self) ?? "0") ?? 0
        self.systemLanguage = EmulatorLanguage(rawValue: langRaw) ?? .english
        let logRaw = Int(AppSettings.get(Self.keyCoreLogLevel, type: String.self) ?? "0") ?? CoreLogLevel.warn.rawValue
        self.coreLogLevel = CoreLogLevel(rawValue: logRaw) ?? .warn
        self.applyCheatsOnLaunch = AppSettings.getBool(Self.keyApplyCheatsOnLaunch, defaultValue: false)
        self.showCheatNotifications = AppSettings.getBool(Self.keyShowCheatNotifications, defaultValue: true)
    }
}

extension SystemDatabase {
    static func normalizeSystemID(_ libretroID: String) -> String {
        switch libretroID {
        case "2048": return "2048"
        case "32x": return "32x"
        case "3do": return "3do"
        case "3ds": return "3ds"
        case "anarch": return "anarch"
        case "apple_ii": return "apple_ii"
        case "arcadia": return "arcadia"
        case "arduboy": return "arduboy"
        case "atari_2600": return "atari2600"
        case "atari_5200": return "atari5200"
        case "atari_7800": return "atari7800"
        case "atari_lynx": return "lynx"
        case "atari_st": return "atari_st"
        case "bbcmicro": return "bbcmicro"
        case "bomberman": return "bomberman"
        case "cdi": return "cdi"
        case "chailove": return "chailove"
        case "chip_8": return "chip_8"
        case "colecovision": return "colecovision"
        case "commodore_64": return "commodore_64"
        case "commodore_amiga": return "commodore_amiga"
        case "commodore_c128": return "commodore_c128"
        case "commodore_c64": return "commodore_c64"
        case "commodore_c64_supercpu": return "commodore_c64_supercpu"
        case "commodore_cbm2": return "commodore_cbm2"
        case "commodore_cbm5x0": return "commodore_cbm5x0"
        case "commodore_pet": return "commodore_pet"
        case "commodore_plus4": return "commodore_plus4"
        case "commodore_vic20": return "commodore_vic20"
        case "cpc": return "cpc"
        case "craft": return "craft"
        case "dice": return "dice"
        case "dinothawr": return "dinothawr"
        case "doom": return "doom"
        case "doom_3": return "doom_3"
        case "dos": return "dos"
        case "dreamcast": return "dreamcast"
        case "ep128": return "ep128"
        case "epochcv": return "epochcv"
        case "fb_alpha": return "fba"
        case "gam4980": return "gam4980"
        case "game_boy": return "gb"
        case "game_boy_advance": return "gba"
        case "game_music": return "game_music"
        case "gamecube": return "gamecube"
        case "gamegear": return "gamegear"
        case "gba": return "gba"
        case "gong": return "gong"
        case "intellivision": return "intellivision"
        case "J2ME": return "J2ME"
        case "jaguar": return "jaguar"
        case "jollycv": return "jollycv"
        case "jumpnbump": return "jumpnbump"
        case "laserdisc": return "laserdisc"
        case "lowresnx": return "lowresnx"
        case "mac68k": return "mac68k"
        case "mame": return "mame"
        case "master_system": return "sms"
        case "mega_drive": return "genesis"
        case "mega_duck": return "mega_duck"
        case "msx": return "msx"
        case "music": return "music"
        case "n64": return "n64"
        case "nds": return "nds"
        case "neo_geo_pocket": return "ngp"
        case "neogeo": return "neogeo"
        case "nes": return "nes"
        case "nxengine": return "nxengine"
        case "odyssey2": return "odyssey2"
        case "p2000t": return "p2000t"
        case "pc_88": return "pc_88"
        case "pc_98": return "pc_98"
        case "pc_engine": return "pce"
        case "pcfx": return "pcfx"
        case "pcxt": return "pcxt"
        case "pico8": return "pico8"
        case "playstation": return "psx"
        case "playstation_portable": return "psp"
        case "playstation2": return "ps2"
        case "pokemon_mini": return "pokemon_mini"
        case "quake_1": return "quake_1"
        case "quake_2": return "quake_2"
        case "quake_3": return "quake_3"
        case "rs": return "rs"
        case "scummvm": return "scummvm"
        case "sega_saturn": return "saturn"
        case "sharp_x1": return "sharp_x1"
        case "sharp_x68000": return "sharp_x68000"
        case "super_nes": return "snes"
        case "nintendo_nes": return "nes"
        case "nintendo_64": return "n64"
        case "sega_genesis": return "genesis" 
        default: return libretroID
        }
    }
}

// MARK: - RESOLVED FIXME: Libretro Core Info Refresh Service
class LibretroInfoManager: ObservableObject {
    static let shared = LibretroInfoManager()
    
    @Published var isRefreshing = false
    @Published var refreshStatus = ""
    
    // Add a static dictionary to act as our "Source of Truth"
    static var coreToSystemMap: [String: Set<String>] = [:]
    // Add a helper to save/load this mapping (like you did for SystemDatabase)

    static func saveMappings() {
        if let data = try? JSONEncoder().encode(coreToSystemMap.mapValues { Array($0) }) {
            try? data.write(to: mapURL)
            LoggerService.debug(category: "LibretroInfoManager", "Saved core-to-system mappings")
        }
    }

    private let githubZipURL = URL(string: "https://github.com/libretro/libretro-core-info/archive/refs/heads/master.zip")!
    
    func refreshCoreInfo() async {
        DispatchQueue.main.async {
            self.isRefreshing = true
            self.refreshStatus = "Downloading libretro info..."
        }
        do {
            let (zipData, _) = try await URLSession.shared.data(from: githubZipURL)
            LoggerService.info(category: "LibretroInfoManager", "Downloading libretro info from \(githubZipURL)")
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("master.zip")
            try zipData.write(to: zipPath)
            LoggerService.debug(category: "LibretroInfoManager", "Downloaded libretro info to \(zipPath)")
            
            DispatchQueue.main.async { self.refreshStatus = "Extracting files..." }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", zipPath.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            LoggerService.debug(category: "LibretroInfoManager", "Extracted libretro info to \(tempDir)")
            
            DispatchQueue.main.async { self.refreshStatus = "Parsing system info..." }
            
let extractedFolder = tempDir.appendingPathComponent("libretro-core-info-master")
            var newExtensionsDict: [String: Set<String>] = [:] 
            
            // 🔥 NEW: Track names and manufacturers for newly discovered systems
            var systemNamesFromInfo:[String: String] = [:]
            var systemMfgFromInfo: [String: String] = [:]
            
            LoggerService.debug(category: "LibretroInfoManager", "Parsing system info from \(extractedFolder)")
            if let enumerator = FileManager.default.enumerator(at: extractedFolder, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator where fileURL.pathExtension == "info" {
                    let infoDict = parseInfoFile(at: fileURL)

                    // 1. Handle System/Core Mapping & Discovery
                    if let sysIDString = infoDict["systemid"] { 
                        let coreID = fileURL.deletingPathExtension().lastPathComponent 
                        let ids = sysIDString.components(separatedBy: "|").map { SystemDatabase.normalizeSystemID($0) }
                        LibretroInfoManager.coreToSystemMap[coreID] = Set(ids)
                        
                        // Extract human-readable names and manufacturer
                        let names = infoDict["systemname"]?.components(separatedBy: "|") ?? []
                        let mfg = infoDict["manufacturer"] ?? "Various"
                        
                        for (index, id) in ids.enumerated() {
                            if systemNamesFromInfo[id] == nil {
                                if index < names.count {
                                    systemNamesFromInfo[id] = names[index]
                                } else if let firstName = names.first {
                                    systemNamesFromInfo[id] = firstName
                                } else {
                                    systemNamesFromInfo[id] = id.capitalized
                                }
                            }
                            if systemMfgFromInfo[id] == nil {
                                systemMfgFromInfo[id] = mfg
                            }
                        }
                    }

                    // 2. Handle File Extensions
                    if let sysName = infoDict["systemname"], let exts = infoDict["supported_extensions"] {
                        let parsedExts = exts.components(separatedBy: "|").map { $0.lowercased() }
                        if newExtensionsDict[sysName] == nil { newExtensionsDict[sysName] = [] }
                        newExtensionsDict[sysName]?.formUnion(parsedExts)
                    }
                }
            }

            DispatchQueue.main.async { self.refreshStatus = "Updating database..." }
            LoggerService.debug(category: "LibretroInfoManager", "Updating database...")
            
            var currentSystems = SystemDatabase.systems
            let existingIDs = Set(currentSystems.map { $0.id })
            
            // 🔥 INJECT NEWLY DISCOVERED SYSTEMS INTO THE DATABASE
            for (id, name) in systemNamesFromInfo {
                if !existingIDs.contains(id) && id != "unknown" {
                    let newSystem = SystemInfo(
                        id: id,
                        name: name,
                        manufacturer: systemMfgFromInfo[id] ?? "Various",
                        extensions:[],
                        defaultCoreID: nil,
                        iconName: "gamecontroller", 
                        emuIconName: nil,
                        year: nil,
                        sortOrder: 80, // Place after main hardcoded systems
                        defaultBoxType: .landscape,
                        displayInUI: true
                    )
                    currentSystems.append(newSystem)
                    LoggerService.debug(category: "LibretroInfoManager", "Dynamically added new system: \(name) (\(id))")
                }
            }
            
            // Update extensions for ALL systems (including the newly injected ones)
            for i in 0..<currentSystems.count {
                let matchedKey = newExtensionsDict.keys.first { $0.contains(currentSystems[i].name) || currentSystems[i].name.contains($0) }
                if let key = matchedKey, let freshExts = newExtensionsDict[key] {
                    let combined = Set(currentSystems[i].extensions).union(freshExts)
                    currentSystems[i].extensions = Array(combined).sorted()
                }
            }
            
            SystemDatabase.saveSystems(currentSystems)
            LibretroInfoManager.saveMappings() // The fix from the previous step!
            
            LoggerService.debug(category: "LibretroInfoManager", "Saved systems to database")
            try FileManager.default.removeItem(at: tempDir)
            
            LoggerService.debug(category: "LibretroInfoManager", "Removed temporary directory")
            
            DispatchQueue.main.async {
                LoggerService.info(category: "LibretroInfoManager", "Update Complete!")
                self.isRefreshing = false
                self.refreshStatus = "Update Complete!"
                SystemPreferences.shared.updateTrigger += 1
            }
            
        } catch {
            LoggerService.error(category: "LibretroInfoManager", "Failed to refresh libretro info: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.refreshStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private static let mapURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu/CoreSystemMappings.json")
    }()

    static func loadMappings() {
        if let data = try? Data(contentsOf: mapURL),
        let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            coreToSystemMap = decoded.mapValues { Set($0) }
        }
    }
    
    private func parseInfoFile(at url: URL) -> [String: String] {
        LoggerService.debug(category: "LibretroInfoManager", "Parsing system info from \(url)")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0) }
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                result[key] = value
                if key == "supported_systems" || key == "systemid" {
                    // value is often "nes|snes|gameboy"
                    result["systemid"] = value 
                }
                LoggerService.debug(category: "LibretroInfoManager", "Parsed key: \(key), value: \(value)")
            }
        }
        LoggerService.debug(category: "LibretroInfoManager", "Parsed system info: \(result)")
        return result
    }
}

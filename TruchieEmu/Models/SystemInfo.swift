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
        SystemInfo(id: "ps2",          name: "PlayStation 2",                   manufacturer: "Sony",       extensions: ["iso", "chd"],                 defaultCoreID: "pcsx2_libretro",             iconName: "opticaldisc",    emuIconName: "PS",       year: "2000", sortOrder: 21, defaultBoxType: .landscape),
        SystemInfo(id: "psp",          name: "PlayStation Portable",            manufacturer: "Sony",       extensions: ["iso", "cso", "pbp"],          defaultCoreID: "ppsspp_libretro",            iconName: "ipad.landscape", emuIconName: "PSP",      year: "2004", sortOrder: 22, defaultBoxType: .landscape),
        SystemInfo(id: "mame",         name: "Arcade (MAME)",                   manufacturer: "Various",    extensions: ["zip", "7z"],                  defaultCoreID: "mame2003_plus_libretro",     iconName: "arcade.stick",   emuIconName: "MAME",     year: nil,    sortOrder: 30, defaultBoxType: .vertical),
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
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([SystemInfo].self, from: data) else {
            return defaultSystems
        }
        return decoded
    }
    
    static func saveSystems(_ updatedSystems: [SystemInfo]) {
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
        didSet { AppSettings.setBool(Self.keyApplyCheatsOnLaunch, value: applyCheatsOnLaunch) }
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

// MARK: - RESOLVED FIXME: Libretro Core Info Refresh Service
class LibretroInfoManager: ObservableObject {
    static let shared = LibretroInfoManager()
    
    @Published var isRefreshing = false
    @Published var refreshStatus = ""
    
    private let githubZipURL = URL(string: "https://github.com/libretro/libretro-core-info/archive/refs/heads/master.zip")!
    
    func refreshCoreInfo() async {
        DispatchQueue.main.async {
            self.isRefreshing = true
            self.refreshStatus = "Downloading libretro info..."
        }
        
        do {
            let (zipData, _) = try await URLSession.shared.data(from: githubZipURL)
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("master.zip")
            try zipData.write(to: zipPath)
            
            DispatchQueue.main.async { self.refreshStatus = "Extracting files..." }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", zipPath.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async { self.refreshStatus = "Parsing system info..." }
            
            let extractedFolder = tempDir.appendingPathComponent("libretro-core-info-master")
            var newExtensionsDict: [String: Set<String>] = [:] 
            
            if let enumerator = FileManager.default.enumerator(at: extractedFolder, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator where fileURL.pathExtension == "info" {
                    let infoDict = parseInfoFile(at: fileURL)
                    if let sysName = infoDict["systemname"], let exts = infoDict["supported_extensions"] {
                        let parsedExts = exts.components(separatedBy: "|").map { $0.lowercased() }
                        if newExtensionsDict[sysName] == nil { newExtensionsDict[sysName] = [] }
                        newExtensionsDict[sysName]?.formUnion(parsedExts)
                    }
                }
            }
            
            DispatchQueue.main.async { self.refreshStatus = "Updating database..." }
            var currentSystems = SystemDatabase.systems
            
            for i in 0..<currentSystems.count {
                let matchedKey = newExtensionsDict.keys.first { $0.contains(currentSystems[i].name) || currentSystems[i].name.contains($0) }
                if let key = matchedKey, let freshExts = newExtensionsDict[key] {
                    let combined = Set(currentSystems[i].extensions).union(freshExts)
                    currentSystems[i].extensions = Array(combined).sorted()
                }
            }
            
            SystemDatabase.saveSystems(currentSystems)
            try FileManager.default.removeItem(at: tempDir)
            
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.refreshStatus = "Update Complete!"
                SystemPreferences.shared.updateTrigger += 1
            }
            
        } catch {
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.refreshStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func parseInfoFile(at url: URL) -> [String: String] {
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
            }
        }
        return result
    }
}
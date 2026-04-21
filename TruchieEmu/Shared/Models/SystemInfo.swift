import Foundation
import SwiftUI // Required for @Published in SystemPreferences and LibretroInfoManager

// MARK: - System Action
enum SystemAction {
    case refresh
    case settings(String) // coreID
    case selectCore(SystemInfo)
    case cheats
    case bezels
    case controllers
    case library
    case shaders
    case defaultShadersForDefaults(String, String) // systemID, shaderPresetID
    case defaultShadersForAll(String, String) // systemID, shaderPresetID
}

// Request used to open system-specific settings via a sheet
struct SystemSettingsRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let system: SystemInfo
    let page: SettingsView.Page

    init(system: SystemInfo, page: SettingsView.Page) {
        self.id = UUID()
        self.system = system
        self.page = page
    }
}

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
struct MagicHeader: Codable, Hashable {
    let offset: UInt64
    let bytes: String? // Changed to optional to allow 'null' in JSON
    
    var data: Data? {
        guard let bytes = bytes else { return nil }
        return bytes.data(using: .utf8)
    }
}
struct SystemInfo: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    let pathKeywords: [String]
    let magicHeaders: [MagicHeader]
    let filenamePatterns: [String]
    var manufacturer: String
    var extensions: [String]
    var defaultCoreID: String?
    var defaultShaderPresetID: String?
    var iconName: String
    var emuIconName: String?
    var year: String?
    var sortOrder: Int
    var defaultBoxType: BoxType = .vertical
    var displayInUI: Bool = true
    var isDiskBased: Bool = false

    var coreReportedAspectRatio: CGFloat?

    // The correct display aspect ratio for this system's output.
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
    
    // Explicit CodingKeys ensure both custom Decoding and automatic Encoding work perfectly
    enum CodingKeys: String, CodingKey {
        case id, name, pathKeywords, magicHeaders, filenamePatterns, manufacturer
        case extensions, defaultCoreID, defaultShaderPresetID, iconName, emuIconName, year, sortOrder
        case defaultBoxType, displayInUI, coreReportedAspectRatio, isDiskBased
    }
    
    // Custom Decoder to handle missing JSON fields safely
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // FIX: Explicitly using [String]() and[MagicHeader]() so the compiler never gets confused
        pathKeywords = try container.decodeIfPresent([String].self, forKey: .pathKeywords) ?? [String]()
        magicHeaders = try container.decodeIfPresent([MagicHeader].self, forKey: .magicHeaders) ?? [MagicHeader]()
        filenamePatterns = try container.decodeIfPresent([String].self, forKey: .filenamePatterns) ?? [String]()
        extensions = try container.decodeIfPresent([String].self, forKey: .extensions) ?? [String]()
        
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer) ?? "Unknown"
        defaultCoreID = try container.decodeIfPresent(String.self, forKey: .defaultCoreID)
        defaultShaderPresetID = try container.decodeIfPresent(String.self, forKey: .defaultShaderPresetID)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "gamecontroller"
        emuIconName = try container.decodeIfPresent(String.self, forKey: .emuIconName)
        year = try container.decodeIfPresent(String.self, forKey: .year)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 99
        defaultBoxType = try container.decodeIfPresent(BoxType.self, forKey: .defaultBoxType) ?? .vertical
        displayInUI = try container.decodeIfPresent(Bool.self, forKey: .displayInUI) ?? true
        isDiskBased = try container.decodeIfPresent(Bool.self, forKey: .isDiskBased) ?? false
        coreReportedAspectRatio = try container.decodeIfPresent(CGFloat.self, forKey: .coreReportedAspectRatio)
    }
    
    // Keep the standard init so LibretroInfoManager can still create objects dynamically
    init(id: String, name: String, pathKeywords: [String], magicHeaders:[MagicHeader], filenamePatterns: [String], manufacturer: String, extensions: [String], defaultCoreID: String?, defaultShaderPresetID: String? = nil, iconName: String, emuIconName: String?, year: String?, sortOrder: Int, defaultBoxType: BoxType, displayInUI: Bool, isDiskBased: Bool = false) {
        self.id = id
        self.name = name
        self.pathKeywords = pathKeywords
        self.magicHeaders = magicHeaders
        self.filenamePatterns = filenamePatterns
        self.manufacturer = manufacturer
        self.extensions = extensions
        self.defaultCoreID = defaultCoreID
        self.defaultShaderPresetID = defaultShaderPresetID
        self.iconName = iconName
        self.emuIconName = emuIconName
        self.year = year
        self.sortOrder = sortOrder
        self.defaultBoxType = defaultBoxType
        self.displayInUI = displayInUI
        self.isDiskBased = isDiskBased
        self.coreReportedAspectRatio = nil
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
                for ext in["png", "PNG"] {
                    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                        if let img = NSImage(contentsOf: url) { return img }
                    }
                }
            }
        }
        
        for name in namesToTry {
            LoggerService.extreme(category: "SystemInfo", "Loading emu image for system: \(id) with name: \(name)")
            if let path = bundle.path(forResource: name, ofType: "png") {
                if let img = NSImage(contentsOf: URL(fileURLWithPath: path)) { return img }
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
    static var systems: [SystemInfo] = loadSystems()

    private static let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TruchieEmu", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("SystemDatabase.json")
    }()

    static func loadSystems() -> [SystemInfo] {
        // 1. Load the BASE systems from the App Bundle (Source of Truth for hardcoded data)
        var bundledSystems: [String: SystemInfo] = [:]
        if let bundleURL = Bundle.main.url(forResource: "SystemDatabase", withExtension: "json") {
            do {
                let data = try Data(contentsOf: bundleURL)
                let parsedBundle = try JSONDecoder().decode([SystemInfo].self, from: data)
                for sys in parsedBundle {
                    bundledSystems[sys.id] = sys
                }
                LoggerService.debug(category: "SystemDatabase", "✅ SUCCESS: Loaded \(bundledSystems.count) systems from Xcode Bundle! from \(bundleURL)")
            } catch DecodingError.dataCorrupted(let context) {
                LoggerService.error(category: "SystemDatabase", "🚨 JSON SYNTAX ERROR: \(context.debugDescription)")
            } catch DecodingError.keyNotFound(let key, let context) {
                LoggerService.error(category: "SystemDatabase", "🚨 JSON MISSING KEY: '\(key.stringValue)' not found. \(context.debugDescription)")
            } catch DecodingError.typeMismatch(let type, let context) {
                LoggerService.error(category: "SystemDatabase", "🚨 JSON TYPE MISMATCH: Expected \(type) but found something else. \(context.debugDescription)")
            } catch {
                LoggerService.error(category: "SystemDatabase", "🚨 OTHER JSON ERROR: \(error.localizedDescription)")
            }
        } else {
            LoggerService.error(category: "SystemDatabase", "🚨 FILE NOT FOUND: SystemDatabase.json is NOT in the App Bundle!, path: \(cacheURL)")
        }

        // 2. Load the CACHED systems (Libretro discoveries, user preferences)
        var cachedSystems: [String: SystemInfo] = [:]
        if let data = try? Data(contentsOf: cacheURL),
        let parsedCache = try? JSONDecoder().decode([SystemInfo].self, from: data) {
            for sys in parsedCache {
                cachedSystems[sys.id] = sys
            }
        }

        // 3. MERGE THEM
        var finalSystems: [SystemInfo] = []
        var processedIDs = Set<String>()

        // Phase A: Use Bundled data as the foundation
        for (id, bundleSys) in bundledSystems {
            processedIDs.insert(id)
            
                if let cacheSys = cachedSystems[id] {
                    // MERGE: Take the important bundled data, but keep cached dynamic changes
                    var mergedSys = bundleSys
                    
                    // Union the extensions (Bundle + Libretro discoveries)
                    let combinedExtensions = Set(bundleSys.extensions).union(cacheSys.extensions)
                    mergedSys.extensions = Array(combinedExtensions).sorted()
                    
                    // Preserve user states from cache
                    mergedSys.displayInUI = cacheSys.displayInUI
                    mergedSys.defaultShaderPresetID = cacheSys.defaultShaderPresetID
                    mergedSys.defaultCoreID = cacheSys.defaultCoreID
                    
                    finalSystems.append(mergedSys)
                } else {
                // Found in bundle, but not in cache yet (brand new install or you added a new system)
                finalSystems.append(bundleSys)
            }
        }

        // Phase B: Add dynamically discovered systems that aren't in your bundle
        for (id, cacheSys) in cachedSystems {
            if !processedIDs.contains(id) {
                // This is a system exclusively found by Libretro (like your '32x' before you added it to JSON)
                finalSystems.append(cacheSys)
            }
        }

        // Inject disk-based flag for known systems (since bundle JSON cannot be modified)
        let diskBasedIDs: Set<String> = ["psx", "ps1", "ps2", "saturn", "dreamcast", "3do", "psp"]
        for i in 0..<finalSystems.count {
            if diskBasedIDs.contains(finalSystems[i].id) {
                finalSystems[i].isDiskBased = true
            }
        }

        // 4. Return sorted by your defined order
        return finalSystems.sorted { $0.sortOrder < $1.sortOrder }
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
        case "gc", "wii": return ["gc", "wii"]
        default: return [id]
        }
    }

    static func multiSystemGroups() -> [String: [String]] {
        return [
            "gb": ["gb", "gbc"],
            "gbc": ["gb", "gbc"],
            "gc": ["gc", "wii"],
            "wii": ["gc", "wii"]
        ]
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
    case english = 0, japanese = 1, german = 2, spanish = 3, italian = 4
    case portuguese = 6, britishEnglish = 7
    
    var id: Int { self.rawValue }
    
    var noIntroRegionPreference: [String] {
        switch self {
        case .spanish: return ["(Spain)", "(Europe)", "(World)", "(Es,", "(Es)", "(USA)"]
        case .english: return ["(USA)", "(World)", "(En,", "(En)", "(U)"]
        case .britishEnglish: return ["(Europe)", "(UK)", "(En,", "(World)"]
        case .german: return ["(Germany)", "(Europe)", "(World)", "(De,", "(De)"]
        case .italian: return ["(Italy)", "(Europe)", "(World)", "(It,", "(It)"]
        case .portuguese: return ["(Brazil)", "(Portugal)", "(Europe)", "(World)"]
        case .japanese: return ["(Japan)", "(JP)", "(Ja)"]
        }
    }
    
    var flagEmoji: String {
        switch self {
        case .spanish: return "🇦🇷"
        case .english: return "🇺🇸"
        case .japanese: return "🇯🇵"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇧🇷"
        case .britishEnglish: return "🇬🇧"
        }
    }
    
    var name: String {
        switch self {
        case .english: return "English"
        case .japanese: return "Japanese"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
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
        LoggerService.debug(category: "SystemPreferences", "Set Preferred core ID for \(systemID): \(coreID ?? "unknown")")
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
    // FIXME: Add all the systems from systems dynamically here using this schema (already in the json)
    // But for that we need to check since these are used across the app already
    static func normalizeSystemID(_ libretroID: String) -> String {
        switch libretroID {
        case "atari_2600": return "atari2600"
        case "atari_5200": return "atari5200"
        case "atari_7800": return "atari7800"
        case "atari_lynx": return "lynx"
        case "fb_alpha": return "fba"
        case "game_boy": return "gb"
        case "game_boy_advance": return "gba"
        case "master_system": return "sms"
        case "mega_drive": return "genesis"
        case "neo_geo_pocket": return "ngp"
        case "pc_engine": return "pce"
        case "playstation": return "psx"
        case "playstation_portable": return "psp"
        case "playstation2": return "ps2"
        case "sega_saturn": return "saturn"
        case "super_nes": return "snes"
        case "nintendo_nes": return "nes"
        case "nintendo_64": return "n64"
        case "sega_genesis": return "genesis" 
        default: return libretroID
        }
    }
}

// MARK: - Libretro Core Info Refresh Service
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

    static func loadMappings() {
        if let data = try? Data(contentsOf: mapURL),
           let parsed = try? JSONDecoder().decode([String: [String]].self, from: data) {
            coreToSystemMap = parsed.mapValues { Set($0) }
            LoggerService.debug(category: "LibretroInfoManager", "Loaded core-to-system mappings")
        } else {
            LoggerService.debug(category: "LibretroInfoManager", "No existing core-to-system mappings found to load")
        }
    }

    private static let mapURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchieEmu/CoreSystemMappings.json")
    }()

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
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
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
                        pathKeywords: [],
                        magicHeaders: [],
                        filenamePatterns: [],
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
            }
        }
        return result
    }
}

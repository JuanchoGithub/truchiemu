import Foundation
import AppKit
import SwiftUI // Required for @Published in SystemPreferences and LibretroInfoManager

// MARK: - System Action
enum SystemAction {
    case refresh
    case settings(String?) // coreID — nil means use system mode
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
    var isRedumpOnly: Bool = false
    var database: [String]? = nil

    var customDisplayName: String?
    var customIconPath: String?
    var coreReportedAspectRatio: CGFloat?

    // The correct display aspect ratio for this system's output.
    var displayAspectRatio: CGFloat {
        if let coreAR = coreReportedAspectRatio, coreAR > 0.0 {
            return coreAR
        }
        return 4.0 / 3.0 // Default aspect ratio for most systems
    }
    
    // Explicit CodingKeys ensure both custom Decoding and automatic Encoding work perfectly
    enum CodingKeys: String, CodingKey {
        case id, name, pathKeywords, magicHeaders, filenamePatterns, manufacturer
        case extensions, defaultCoreID, defaultShaderPresetID, iconName, emuIconName, year, sortOrder
        case defaultBoxType, displayInUI, coreReportedAspectRatio, isDiskBased, isRedumpOnly, customDisplayName, customIconPath, database
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
        isRedumpOnly = try container.decodeIfPresent(Bool.self, forKey: .isRedumpOnly) ?? false
        coreReportedAspectRatio = try container.decodeIfPresent(CGFloat.self, forKey: .coreReportedAspectRatio)
        customDisplayName = try container.decodeIfPresent(String.self, forKey: .customDisplayName)
        customIconPath = try container.decodeIfPresent(String.self, forKey: .customIconPath)
        database = try container.decodeIfPresent([String].self, forKey: .database)
    }
    
    // Keep the standard init so LibretroInfoManager can still create objects dynamically
    init(id: String, name: String, pathKeywords: [String], magicHeaders:[MagicHeader], filenamePatterns: [String], manufacturer: String, extensions: [String], defaultCoreID: String?, defaultShaderPresetID: String? = nil, iconName: String, emuIconName: String?, year: String?, sortOrder: Int, defaultBoxType: BoxType, displayInUI: Bool, isDiskBased: Bool = false, isRedumpOnly: Bool = false) {
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
        self.isRedumpOnly = isRedumpOnly
        self.coreReportedAspectRatio = nil
        self.customDisplayName = nil
        self.customIconPath = nil
    }
    
    func emuImage(size: Int, includeCustom: Bool = true) -> NSImage? {
        #if LOG_EXTREME
        LoggerService.extreme(category: "SystemInfo", "Loading emu image for system: \(id)")
        #endif
        if includeCustom, let customPath = customIconPath {
            let cacheKey = "custom-\(id)-\(size)" as NSString
            if let cached = Self.iconCache.object(forKey: cacheKey) {
                return cached
            }
            let url = URL(fileURLWithPath: customPath)
            if let img = NSImage(contentsOf: url) {
                let cost = Int(img.size.width * img.size.height * 4)
                Self.iconCache.setObject(img, forKey: cacheKey, cost: cost)
                return img
            }
        }

        guard let iconName = emuIconName else { return nil }

        let cacheKey = "\(iconName)-\(size)" as NSString
        if let cached = Self.iconCache.object(forKey: cacheKey) {
            return cached
        }

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
            if let img = NSImage(named: name) {
                let cost = Int(img.size.width * img.size.height * 4)
                Self.iconCache.setObject(img, forKey: cacheKey, cost: cost)
                return img
            }
            if let img = NSImage(named: "\(name).png") {
                let cost = Int(img.size.width * img.size.height * 4)
                Self.iconCache.setObject(img, forKey: cacheKey, cost: cost)
                return img
            }
            if let img = NSImage(named: NSImage.Name(name)) {
                let cost = Int(img.size.width * img.size.height * 4)
                Self.iconCache.setObject(img, forKey: cacheKey, cost: cost)
                return img
            }

            for subdir in subdirs {
                for ext in["png", "PNG"] {
                    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                        if let img = NSImage(contentsOf: url) {
                            let cost = Int(img.size.width * img.size.height * 4)
                            Self.iconCache.setObject(img, forKey: cacheKey, cost: cost)
                            return img
                        }
                    }
                }
            }
        }

        for name in namesToTry {
            #if LOG_EXTREME
            LoggerService.extreme(category: "SystemInfo", "Loading emu image for system: \(id) with name: \(name)")
            #endif
            if let path = bundle.path(forResource: name, ofType: "png") {
                if let img = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                    let cost = Int(img.size.width * img.size.height * 4)
                    Self.iconCache.setObject(img, forKey: cacheKey, cost: cost)
                    return img
                }
            }
        }
        return nil
    }

    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 10 * 1024 * 1024
        return cache
    }()

    static func invalidateIconCache(forSystemID id: String) {
        for size in [132, 600, 120] {
            iconCache.removeObject(forKey: "custom-\(id)-\(size)" as NSString)
        }
    }
    
    var sidebarDisplayName: String {
        if let custom = customDisplayName, !custom.isEmpty {
            return custom
        }
        return name
    }
}

// MARK: - SystemDatabase
class SystemDatabase {
    static var systems: [SystemInfo] {
        get { SystemDatabaseWrapper.shared.systems }
        set { SystemDatabaseWrapper.shared.systems = newValue }
    }

    private static let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TruchiEmu", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("SystemDatabase.json")
    }()

    private static let bundleFingerprintKey = "systemDBBundleFingerprint"

    private static func fingerprint(_ data: Data) -> String {
        let sum = data.reduce(UInt64(0)) { $0 &+ UInt64($1) }
        return "\(data.count).\(sum)"
    }

    static func _loadSystems() -> [SystemInfo] {
        // 1. Load the BASE systems from the App Bundle (Source of Truth for hardcoded data)
        var bundledSystems: [String: SystemInfo] = [:]
        var bundleFingerprint = ""
        if let bundleURL = Bundle.main.url(forResource: "SystemDatabase", withExtension: "json") {
            do {
                let data = try Data(contentsOf: bundleURL)
                bundleFingerprint = fingerprint(data)
                let parsedBundle = try JSONDecoder().decode([SystemInfo].self, from: data)
                for sys in parsedBundle {
                    bundledSystems[sys.id] = sys
                }
                #if LOG_DEBUG
                LoggerService.debug(category: "SystemDatabase", "✅ SUCCESS: Loaded \(bundledSystems.count) systems from Xcode Bundle! from \(bundleURL)")
                #endif
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

        // Detect bundle update — discard cache if bundled JSON changed
        let lastFingerprint = UserDefaults.standard.string(forKey: Self.bundleFingerprintKey) ?? ""
        let bundleChanged = !bundleFingerprint.isEmpty && bundleFingerprint != lastFingerprint
        if !bundleFingerprint.isEmpty {
            UserDefaults.standard.set(bundleFingerprint, forKey: Self.bundleFingerprintKey)
        }

        // 2. Load the CACHED systems (Libretro discoveries, user preferences)
        var cachedSystems: [String: SystemInfo] = [:]
        if bundleChanged {
            #if LOG_DEBUG
            LoggerService.debug(category: "SystemDatabase", "Bundle fingerprint changed — discarding stale cache")
            #endif
            try? FileManager.default.removeItem(at: cacheURL)
        } else if let data = try? Data(contentsOf: cacheURL),
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
            mergedSys.customDisplayName = cacheSys.customDisplayName
            mergedSys.customIconPath = cacheSys.customIconPath

            // Always take database from bundle (source of truth) — never from stale cache
            mergedSys.database = bundleSys.database

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

    static func _saveSystems(_ updatedSystems: [SystemInfo]) {
        #if LOG_DEBUG
        LoggerService.debug(category: "SystemDatabase", "Saving systems")
        #endif
        if let data = try? JSONEncoder().encode(updatedSystems) {
            try? data.write(to: cacheURL)
        }
    }

    static func saveSystems(_ updatedSystems: [SystemInfo]) {
        SystemDatabaseWrapper.shared.systems = updatedSystems
    }

    static var systemsForDisplay: [SystemInfo] {
        let mergeGBGBC = AppSettings.getBool("mergeGBGBC", defaultValue: true)
        let mergeMameFBA = AppSettings.getBool("mergeMameFBA", defaultValue: true)
        return systems.filter { system in
            if system.id == "gbc" { return !mergeGBGBC }
            if system.id == "fba" { return !mergeMameFBA }
            return system.displayInUI
        }
    }

    static func allInternalIDs(forDisplayID id: String) -> [String] {
        let mergeGBGBC = AppSettings.getBool("mergeGBGBC", defaultValue: true)
        let mergeMameFBA = AppSettings.getBool("mergeMameFBA", defaultValue: true)
        switch id {
        case "gb", "gbc": return mergeGBGBC ? ["gb", "gbc"] : [id]
        case "mame", "fba": return mergeMameFBA ? ["mame", "fba"] : [id]
        default: return [id]
        }
    }

    static func compatibleIDs(for id: String) -> Set<String> {
        Set(allInternalIDs(forDisplayID: id))
    }

    static func multiSystemGroups() -> [String: [String]] {
        let mergeGBGBC = AppSettings.getBool("mergeGBGBC", defaultValue: true)
        let mergeMameFBA = AppSettings.getBool("mergeMameFBA", defaultValue: true)
        var groups: [String: [String]] = [:]
        if mergeGBGBC {
            groups["gb"] = ["gb", "gbc"]
            groups["gbc"] = ["gb", "gbc"]
        }
        if mergeMameFBA {
            groups["mame"] = ["mame", "fba"]
            groups["fba"] = ["mame", "fba"]
        }
        return groups
    }

    static func displaySystem(forInternalID id: String) -> SystemInfo? {
        let mergeGBGBC = AppSettings.getBool("mergeGBGBC", defaultValue: true)
        let mergeMameFBA = AppSettings.getBool("mergeMameFBA", defaultValue: true)
        switch id {
        case "gbc": return mergeGBGBC ? systems.first { $0.id == "gb" } : systems.first { $0.id == "gbc" }
        case "fba": return mergeMameFBA ? systems.first { $0.id == "mame" } : systems.first { $0.id == "fba" }
        default: return systems.first { $0.id == id }
        }
    }

    static func systemName(forInternalID id: String) -> String {
        let mergeGBGBC = AppSettings.getBool("mergeGBGBC", defaultValue: true)
        let mergeMameFBA = AppSettings.getBool("mergeMameFBA", defaultValue: true)
        switch id {
        case "gb", "gbc": return mergeGBGBC ? "Game Boy" : system(forID: id)?.name ?? id
        case "mame", "fba": return mergeMameFBA ? "Arcade (MAME / FBNeo)" : system(forID: id)?.name ?? id
        default: return system(forID: id)?.name ?? id
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
    case northAmerica = 0, japan = 1, spain = 3, brazil = 6
    case world = 8, europe = 9

    var id: Int { self.rawValue }

    var libretroRawValue: Int {
        switch self {
        case .northAmerica, .world, .europe: return 0  // RETRO_LANGUAGE_ENGLISH
        case .japan: return 1  // RETRO_LANGUAGE_JAPANESE
        case .spain: return 4  // RETRO_LANGUAGE_SPANISH
        case .brazil: return 7 // RETRO_LANGUAGE_PORTUGUESE
        }
    }

    var regionSuffix: String? {
        switch self {
        case .northAmerica: return "(USA)"
        case .world: return "(World)"
        case .europe: return "(Europe)"
        case .japan: return "(Japan)"
        case .brazil: return "(Brazil)"
        case .spain: return "(Spain)"
        }
    }

    var noIntroRegionPreference: [String] {
        switch self {
        case .northAmerica: return ["(USA)", "(World)", "(Canada)", "(En,", "(En)", "(U)"]
        case .world: return ["(World)", "(USA)", "(Europe)", "(Japan)"]
        case .europe: return ["(Europe)", "(World)", "(UK)", "(Germany)", "(Spain)", "(France)", "(Italy)"]
        case .japan: return ["(Japan)", "(JP)", "(Ja)"]
        case .brazil: return ["(Brazil)", "(Portugal)", "(Europe)", "(World)"]
        case .spain: return ["(Spain)", "(Europe)", "(World)", "(Es,", "(Es)", "(USA)"]
        }
    }

    var flagEmoji: String {
        switch self {
        case .northAmerica: return "🇺🇸"
        case .world: return "🌍"
        case .europe: return "🇪🇺"
        case .japan: return "🇯🇵"
        case .brazil: return "🇧🇷"
        case .spain: return "🇦🇷"
        }
    }

    var name: String {
        switch self {
        case .northAmerica: return "North America"
        case .world: return "World"
        case .europe: return "Europe"
        case .japan: return "Japan"
        case .brazil: return "Brazil"
        case .spain: return "Spain"
        }
    }

    var localizedName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .northAmerica: return loc.localized("region.northAmerica")
        case .world: return loc.localized("region.world")
        case .europe: return loc.localized("region.europe")
        case .japan: return loc.localized("region.japan")
        case .brazil: return loc.localized("region.brazil")
        case .spain: return loc.localized("region.spain")
        }
    }
}

class SystemPreferences: ObservableObject {
    static let shared = SystemPreferences()
    @Published var updateTrigger: Int = 0

    private static let keyShowBiosFiles = "showBiosFiles"
    private static let keyShowHiddenMAMEFiles = "showHiddenMAMEFiles"
    private static let keySystemLanguage = "coreSystemLanguage"
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

    @Published var systemLanguage: EmulatorLanguage = .northAmerica {
        didSet { AppSettings.set(Self.keySystemLanguage, value: String(systemLanguage.rawValue)); updateTrigger += 1 }
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
        #if LOG_DEBUG
        LoggerService.debug(category: "SystemPreferences", "Set Preferred core ID for \(systemID): \(coreID ?? "unknown")")
        #endif
    }

    init() {
        self.showBiosFiles = AppSettings.getBool(Self.keyShowBiosFiles, defaultValue: false)
        self.showHiddenMAMEFiles = AppSettings.getBool(Self.keyShowHiddenMAMEFiles, defaultValue: false)
        let langRaw = Int(AppSettings.get(Self.keySystemLanguage, type: String.self) ?? "0") ?? 0
        if let lang = EmulatorLanguage(rawValue: langRaw) {
            self.systemLanguage = lang
        } else {
            // Migration from removed cases: german(2), italian(4), britishEnglish(7) → europe
            self.systemLanguage = switch langRaw {
            case 2, 4, 7: .europe
            default: .northAmerica
            }
        }
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
    
/// Looks up the system ID from a libretro database name by checking all systems' database fields
    static func systemIDFromDatabaseName(_ dbName: String) -> String? {
        let trimmed = dbName.trimmingCharacters(in: .whitespaces)
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroInfoManager", "Looking up database entry: '\(trimmed)'")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroInfoManager", "Total systems in database: \(systems.count)")
        #endif
        
        // Search through all systems to find one whose database field contains this name
        for system in systems {
            if let dbArray = system.database {
                #if LOG_DEBUG
                LoggerService.debug(category: "LibretroInfoManager", "Checking system '\(system.id)' with database: \(dbArray)")
                #endif
                for dbEntry in dbArray {
                    if dbEntry == trimmed {
                        #if LOG_DEBUG
                        LoggerService.debug(category: "LibretroInfoManager", "✓ Found match: '\(trimmed)' -> '\(system.id)'")
                        #endif
                        return system.id
                    }
                }
            }
        }
        LoggerService.warning(category: "LibretroInfoManager", "✗ No match found for '\(trimmed)'")
        return nil
    }
}

// MARK: - Libretro Core Info Refresh Service
class LibretroInfoManager: ObservableObject {
    static let shared = LibretroInfoManager()
    
    @Published var isRefreshing = false
    @Published var refreshStatus = ""
    
    // Wrapper to persist both the mapping and the timestamp
    struct CoreInfoCache: Codable {
        let coreToSystemMap: [String: [String]]
        let lastUpdated: Date
    }
    
    // The current in-memory mapping
    static var coreToSystemMap: [String: Set<String>] = [:]
    
    // Helper to check if we have any mappings at all
    static var hasMappings: Bool {
        !coreToSystemMap.isEmpty
    }
    
    static func saveMappings() {
        do {
            let cache = CoreInfoCache(
                coreToSystemMap: coreToSystemMap.mapValues { Array($0) },
                lastUpdated: Date()
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: mapURL)
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "✅ Saved core-to-system mappings to \(mapURL.lastPathComponent)")
            #endif
        } catch {
            LoggerService.error(category: "LibretroInfoManager", "❌ Failed to save core-to-system mappings: \(error.localizedDescription)")
        }
    }
    
    static func loadMappings() {
        do {
            let data = try Data(contentsOf: mapURL)
            let cache = try JSONDecoder().decode(CoreInfoCache.self, from: data)
            coreToSystemMap = cache.coreToSystemMap.mapValues { Set($0) }
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "✅ Loaded core-to-system mappings (Last updated: \(cache.lastUpdated))")
            #endif
        } catch {
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "ℹ️ No existing core-to-system mappings found or failed to load: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Determines if the core info needs a refresh based on age or remote changes
    static func shouldRefreshInfo() async -> Bool {
        // 1. If no mappings exist, we definitely need them
        guard hasMappings else { return true }
        
        // 2. Check if data is older than 30 days
        do {
            let data = try Data(contentsOf: mapURL)
            let cache = try JSONDecoder().decode(CoreInfoCache.self, from: data)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            
            if cache.lastUpdated < thirtyDaysAgo {
                #if LOG_DEBUG
                LoggerService.debug(category: "LibretroInfoManager", "Mappings are older than 30 days. Triggering refresh.")
                #endif
                return true
            }
            
            // 3. Check GitHub for updates using a HEAD request
            let githubZipURL = URL(string: "https://github.com/libretro/libretro-core-info/archive/refs/heads/master.zip")!
            var request = URLRequest(url: githubZipURL)
            request.httpMethod = "HEAD"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let lastModifiedString = httpResponse.value(forHTTPHeaderField: "Last-Modified"),
               let lastModifiedDate = LibretroInfoManager.parseHTTPDate(lastModifiedString) {
                
                if lastModifiedDate > cache.lastUpdated {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "LibretroInfoManager", "GitHub info is newer (\(lastModifiedDate)) than local (\(cache.lastUpdated)). Triggering refresh.")
                    #endif
                    return true
                }
            }
            
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Mappings are up to date.")
            #endif
            return false
            
        } catch {
            LoggerService.error(category: "LibretroInfoManager", "Error during shouldRefreshInfo check: \(error.localizedDescription)")
            // If we can't even read the cache, assume we need to refresh
            return true
        }
    }
    
    private static let mapURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let coreInfoDir = appSupport.appendingPathComponent("TruchiEmu/CoreInfo", isDirectory: true)
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: coreInfoDir, withIntermediateDirectories: true)
        return coreInfoDir.appendingPathComponent("CoreSystemMappings.json")
    }()

    /// Parses an RFC 1123 date string (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
    static func parseHTTPDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: dateString)
    }

    private let githubZipURL = URL(string: "https://github.com/libretro/libretro-core-info/archive/refs/heads/master.zip")!
    
    @MainActor
    func refreshCoreInfo() async {
        isRefreshing = true
        refreshStatus = "Downloading libretro info..."
        do {
            let (zipData, _) = try await URLSession.shared.data(from: githubZipURL)
            LoggerService.info(category: "LibretroInfoManager", "Downloading libretro info from \(githubZipURL)")
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let zipPath = tempDir.appendingPathComponent("master.zip")
            try zipData.write(to: zipPath)
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Downloaded libretro info to \(zipPath)")
            #endif
            
            refreshStatus = "Extracting files..."
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", zipPath.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Extracted libretro info to \(tempDir)")
            #endif
            
            refreshStatus = "Parsing system info..."
            
            let extractedFolder = tempDir.appendingPathComponent("libretro-core-info-master")
            var newExtensionsDict: [String: Set<String>] = [:] 
            
            // 🔥 NEW: Track names and manufacturers for newly discovered systems
            var systemNamesFromInfo:[String: String] = [:]
            var systemMfgFromInfo: [String: String] = [:]
            
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Parsing system info from \(extractedFolder)")
            #endif
            if let contents = try? FileManager.default.contentsOfDirectory(at: extractedFolder, includingPropertiesForKeys: nil) {
                for fileURL in contents where fileURL.pathExtension == "info" {
                    let infoDict = parseInfoFile(at: fileURL)
        
                    // 1. Handle System/Core Mapping & Discovery
                    if let sysIDString = infoDict["systemid"] { 
                        let coreID = fileURL.deletingPathExtension().lastPathComponent 
                        var ids = sysIDString.components(separatedBy: "|").map { SystemDatabase.normalizeSystemID($0) }
                        
                        // Handle cores like Dolphin that declare a single systemid but have compound systemname like "GameCube / Wii"
                        if let systemName = infoDict["systemname"], systemName.contains("/") && ids.count == 1 {
                            let firstID = ids[0]
                            if firstID == "gamecube" && systemName.lowercased().contains("wii") {
                                ids.append("wii")
                            } else if firstID == "wii" && systemName.lowercased().contains("gamecube") {
                                ids.append("gamecube")
                            }
                        }
                        
                        // 2. ALSO parse the "database" field to capture additional systems
                        // e.g., picodrive has systemid="mega_drive" but database includes "Sega - 32X"
                        if let databaseString = infoDict["database"] {
                            let databaseEntries = databaseString.components(separatedBy: "|")
                            for entry in databaseEntries {
                                if let systemID = SystemDatabase.systemIDFromDatabaseName(entry) {
                                    ids.append(systemID)
                                    #if LOG_DEBUG
                                    LoggerService.debug(category: "LibretroInfoManager", "Mapped database entry '\(entry)' to system ID '\(systemID)' for core '\(coreID)'")
                                    #endif
                                } else {
                                    LoggerService.warning(category: "LibretroInfoManager", "Could not map database entry '\(entry)' for core '\(coreID)'. Total systems loaded: \(SystemDatabase.systems.count)")
                                }
                            }
                        }
                        
                        LibretroInfoManager.coreToSystemMap[coreID] = Set(ids)
                        
                        // Extract human-readable names and manufacturer
                        _ = infoDict["systemname"]?.components(separatedBy: "|") ?? []
                        let mfg = infoDict["manufacturer"] ?? "Various"
                        
                        for (_, id) in ids.enumerated() {
                            if systemNamesFromInfo[id] == nil {
                                // Use the canonical name from SystemDatabase if available
                                if let system = SystemDatabase.systems.first(where: { $0.id == id }) {
                                    systemNamesFromInfo[id] = system.name
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
            
            refreshStatus = "Updating database..."
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Updating database...")
            #endif
            
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
                    #if LOG_DEBUG
                    LoggerService.debug(category: "LibretroInfoManager", "Dynamically added new system: \(name) (\(id))")
                    #endif
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
            
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Saved systems to database")
            #endif
            try FileManager.default.removeItem(at: tempDir)
            
            #if LOG_DEBUG
            LoggerService.debug(category: "LibretroInfoManager", "Removed temporary directory")
            #endif
            
            LoggerService.info(category: "LibretroInfoManager", "Update Complete!")
            isRefreshing = false
            refreshStatus = "Update Complete!"
            SystemPreferences.shared.updateTrigger += 1
            
        } catch {
            LoggerService.error(category: "LibretroInfoManager", "Failed to refresh libretro info: \(error.localizedDescription)")
            isRefreshing = false
            refreshStatus = "Failed: \(error.localizedDescription)"
        }
    }
    
    private func parseInfoFile(at url: URL) -> [String: String] {
        #if LOG_DEBUG
        LoggerService.debug(category: "LibretroInfoManager", "Parsing system info from \(url)")
        #endif
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

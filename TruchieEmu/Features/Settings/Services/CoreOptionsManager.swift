import Foundation
import Combine

// MARK: - Core Options Manager
// Manages core options lifecycle: stores parsed options from cores, persists user overrides,
// and serves values back to the libretro environment callback.
@MainActor
class CoreOptionsManager: ObservableObject {
    static let shared = CoreOptionsManager()
    
    // All options for the currently loaded core, indexed by versioned key (e.g., "key_V1")
    @Published private(set) var options: [String: CoreOption] = [:]
    
    // Categories for the currently loaded core
    @Published private(set) var categories: [String: CoreOptionCategory] = [:]
    
    // The core ID we're managing (set when loading a core)
    private var currentCoreID: String?
    
    // Directory for per-core options config files (.cfg)
    private let optionsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/CoreOptions", isDirectory: true)
    }()

    // Directory for per-core option definitions (.json)
    private let definitionsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/CoreOptionDefinitions", isDirectory: true)
    }()
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        try? FileManager.default.createDirectory(at: optionsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: definitionsDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    
    // Allow reading options for an arbitrary core (not just the currently loaded one)
    nonisolated func setCoreIDForReading(_ coreID: String) {
        // This is a no-op since we just expose loadUserOverrides(coreID:)
    }
    
    nonisolated func loadUserOverrides(for coreID: String) -> [String: String] {
        let configURL = optionsDirectory.appendingPathComponent("\(coreID).cfg")
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if let range = trimmed.range(of: "=") {
                let key = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                var value = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty { result[key] = value }
            }
        }
        LoggerService.debug(category: "CoreOptionsManager", "User Overrides: \(result)")
        return result
    }
    
    nonisolated func saveOverride(for coreID: String, values: [String: String]) {
        let configURL = optionsDirectory.appendingPathComponent("\(coreID).cfg")
        LoggerService.debug(category: "CoreOptionsManager", "For \(coreID): Saving Override \(values) in file: \(configURL)")
        let content = values.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n")
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Core Lifecycle
    
    // Called when a new core is loaded. Clears previous options and loads persisted overrides.
    func prepareForCore(coreID: String) {
        LoggerService.debug(category: "CoreOptionsManager", "New core \(coreID) loaded, cleaning all optiones and overrides")
        currentCoreID = coreID
        options.removeAll()
        categories.removeAll()
    }

    // Loads definitions and overrides from disk for a specific core.
    // Used when the core is not running (e.g., in Settings).
    func loadForCore(coreID: String, dylibPath: String? = nil, romPath: String? = nil) {
        LoggerService.debug(category: "CoreOptionsManager", "Loading options from core: \(coreID)")
        currentCoreID = coreID
        
        // 1. Load Definitions
        let defURL = definitionsDirectory.appendingPathComponent("\(coreID).json")
        //LoggerService.debug(category: "CoreOptionsManager", "Definitions file For \(currentCoreID): \(defURL)")
    
        guard let data = try? Data(contentsOf: defURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            options.removeAll()
            categories.removeAll()
    
            LoggerService.debug(category: "CoreOptionsManager", "For \(coreID): cleaned up. Definitions not found.")
            return
        }
 
        // Parse categories

        // 1. Load Categories
        if let cats = json["categories"] as? [String: [String: String]] {
            self.categories = cats.reduce(into: [:]) { res, entry in
                res[entry.key] = CoreOptionCategory(key: entry.key, description: entry.value["desc"] ?? entry.key, info: entry.value["info"] ?? "")
            }
        }        
 
        // 2. Load Options
        if let opts = json["options"] as? [String: [String: Any]] {
            self.options.removeAll()
            for (jsonKey, d) in opts {
                // jsonKey is the base key (e.g. "gambatte_gb_bootloader_V2")
                
                // Create the internal key safely
                let internalKey = makeInternalKey(baseKey: jsonKey, version: .v2)
                
                options[internalKey] = CoreOption(
                    key: jsonKey,
                    description: d["desc"] as? String ?? jsonKey,
                    info: d["info"] as? String ?? "",
                    category: d["category"] as? String ?? "general",
                    values: (d["values"] as? [[String: String]])?.map { CoreOptionValue(value: $0["value"] ?? "", label: $0["label"] ?? "") } ?? [],
                    defaultValue: d["defaultValue"] as? String ?? "",
                    currentValue: d["currentValue"] as? String ?? "",
                    version: .v2
                )
            }
        }
 
        // 3. Apply Overrides
        let overrides = loadUserOverrides(for: coreID)
        for (key, value) in overrides {
            // Look for the versioned key that matches the config key
            if let vKey = options.keys.first(where: { $0.hasPrefix("\(key)_") }) {
                options[vKey]?.currentValue = value
            }
        }
    }

    private func makeInternalKey(baseKey: String, version: CoreOptionVersion) -> String {
        let suffix = "_\(version.rawValue)"
        if baseKey.hasSuffix(suffix) {
            return baseKey // It already has it (like Gambatte)
        }
        return "\(baseKey)\(suffix)" // Add it (for other cores)
    }

    /// Triggers the discovery of core options by launching a headless core session.
    /// This is used when definitions are missing.
    func discoverOptions(for coreID: String, dylibPath: String, romPath: String?) async {
        LoggerService.debug(category: "CoreOptionsManager", "Starting discovery for core: \(coreID)")
        
        // 1. Launch the core in headless mode to trigger environment callbacks.
        // We provide a dummy ROM path if possible to prevent crashes in cores that require a valid game context.
        var dummyRomPath: String? = nil
        if let systemID = CoreManager.supportedSystems(for: coreID).first {
            let repository = ROMRepository(context: SwiftDataContainer.shared.mainContext)
            if let rom = repository.firstROM(forSystemID: systemID) {
                dummyRomPath = rom.path.path
            }
        }

        await LibretroBridge.loadCore(forOptions: dylibPath, coreID: coreID, romPath: dummyRomPath)
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), Core loaded")
        
        // 2. Fetch the captured options and categories from the bridge
        let optionsDict = LibretroBridge.getOptionsDictionary() ?? [:]
        let categoriesDict = LibretroBridge.getCategoriesDictionary() ?? [:]
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), options: \(optionsDict), categories: \(categoriesDict)")
        
        // 3. Convert the bridge dictionaries into our internal models
        var newOptions: [CoreOption] = []
        var newCategories: [CoreOptionCategory] = []
        
        // Parse Categories
        for (catKey, catData) in categoriesDict {
            let desc = catData["description"] as? String ?? catKey
            let info = catData["info"] as? String ?? ""
            newCategories.append(CoreOptionCategory(key: catKey, description: desc, info: info))
        }
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), new Categories: \(newCategories)")
        
        // Parse Options
        for (key, optData) in optionsDict {
            let desc = optData["description"] as? String ?? key
            let info = optData["info"] as? String ?? ""
            let catKey = optData["category"] as? String
            let defaultVal = optData["defaultValue"] as? String ?? ""
            let currentVal = optData["currentValue"] as? String ?? defaultVal
            
            var values: [CoreOptionValue] = []
            if let valsArr = optData["values"] as? [[String: String]] {
                for v in valsArr {
                    values.append(CoreOptionValue(value: v["value"] ?? "", label: v["label"] ?? v["value"] ?? ""))
                }
            }
            
            if values.isEmpty {
                values = [CoreOptionValue(value: currentVal, label: currentVal)]
            }
            
            newOptions.append(CoreOption(
                key: key,
                description: desc,
                info: info,
                category: catKey,
                values: values,
                defaultValue: defaultVal,
                currentValue: currentVal,
                version: .v2
            ))
        }
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), Parsed options")
        
        // 4. Update the manager and persist
        await MainActor.run {
            self.prepareForCore(coreID: coreID)
            self.setOptions(newOptions, categories: newCategories)
            LoggerService.debug(category: "CoreOptionsManager", "Discovery complete. Persisted \(newOptions.count) options.")
        }
    }
    
    // Set the full options list (called from ObjC bridge when core calls SET_CORE_OPTIONS_V2).
    func setOptions(_ newOptions: [CoreOption], categories: [CoreOptionCategory]) {
        // 1. Setup Categories
        var updatedCategories = Dictionary(uniqueKeysWithValues: categories.map { ($0.key, $0) })
        let fallbackKey = "general"
        if updatedCategories[fallbackKey] == nil {
            updatedCategories[fallbackKey] = CoreOptionCategory(key: fallbackKey, description: "General Settings", info: "")
        }
        self.categories = updatedCategories
        
        let persisted = loadUserOverrides()
        
        for var option in newOptions {
            // 2. Clean Category
            if option.category == nil || option.category?.isEmpty == true {
                option.category = fallbackKey
            }
            
            // 3. Apply Overrides
            if let savedValue = persisted[option.key] {
                option.currentValue = savedValue
            }
            
            // 4. SMART INTERNAL KEY (No more _V2_V2)
            let internalKey = makeInternalKey(baseKey: option.key, version: option.version)
            self.options[internalKey] = option
        }

        // Persist these definitions so they can be loaded when the core isn't running
        if let coreID = currentCoreID {
            persistDefinitions(for: coreID)
        }
    }
    
    // Set options from a V1 core (simpler struct).
    func setOptionsV1(_ newOptions: [CoreOption]) {
        self.categories.removeAll()
        let persisted = loadUserOverrides()

        for var option in newOptions {
            // Ensure version is set to v1 if not already
            let versionedKey = "\(option.key)_\(CoreOptionVersion.v1.rawValue)"
            if let savedValue = persisted[option.key],
               option.values.contains(where: { $0.value == savedValue }) {
                option.currentValue = savedValue
            }
            var v1Option = option
            v1Option.version = .v1
            self.options[versionedKey] = v1Option
        }
    }
    
    // MARK: - Reading Values (used by GET_VARIABLE callback)
    
    // Get the current value for a key. Called from the bridge's GET_VARIABLE handler.
    func getValue(for key: String) -> String? {
        // Try V1 then V2
        if let v1Value = options["\(key)_\(CoreOptionVersion.v1.rawValue)"]?.currentValue {
            return v1Value
        }
        return options["\(key)_\(CoreOptionVersion.v2.rawValue)"]?.currentValue
    }
    
    // Get all raw key-value pairs for passing back to the core
    func allValues() -> [String: String] {
        var result: [String: String] = [:]
        let v1Suffix = "_\(CoreOptionVersion.v1.rawValue)"
        let v2Suffix = "_\(CoreOptionVersion.v2.rawValue)"
        
        for (versionedKey, option) in options {
            var baseKey = versionedKey
            if baseKey.hasSuffix(v1Suffix) {
                baseKey = String(baseKey.dropLast(v1Suffix.count))
            } else if baseKey.hasSuffix(v2Suffix) {
                baseKey = String(baseKey.dropLast(v2Suffix.count))
            }
            result[baseKey] = option.currentValue
        }
        return result
    }
    
    // MARK: - Writing Values
    
    // Update a single option value and persist.
    func updateValue(_ value: String, for key: String) {
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID): updating key: \(key), value \(value)")
        
        // We find all versioned keys that match this base key and update them.
        // This ensures that if the UI is showing both V1 and V2, they both update.
        let matchingKeys = options.keys.filter { $0.hasPrefix("\(key)_") }
        
        if !matchingKeys.isEmpty {
            for vKey in matchingKeys {
                options[vKey]?.currentValue = value
            }
            persistOverride(key: key, value: value)
        }
    }
    
    // Reset a single option to its core-default.
    func resetToDefault(key: String) {
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID): resetting key: \(key)")
        
        // Find all versioned keys that match this base key and reset them.
        let matchingKeys = options.keys.filter { $0.hasPrefix("\(key)_") }
        
        if !matchingKeys.isEmpty {
            for vKey in matchingKeys {
                options[vKey]?.currentValue = options[vKey]!.defaultValue
            }
            persistOverride(key: key, value: options[matchingKeys.first!]!.defaultValue)
        }
    }
    
    // Reset ALL options to their core-defined defaults.
    func resetAllToDefaults() {
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID): resetting ALL KEYS")
        for key in options.keys {
            options[key]!.currentValue = options[key]!.defaultValue
        }
        clearAllOverrides()
        
        // Also persist the reset values to the definitions cache
        if let coreID = currentCoreID {
            persistDefinitions(for: coreID)
        }
    }
    
    // MARK: - Persistence
    
    // File path for the RetroArch-compatible core options file
    private func optionsFileURL(_ coreID: String) -> URL {
        optionsDirectory.appendingPathComponent("\(coreID).cfg")
    }
    
    // Save a key-value override to the per-core config file.
    private func persistOverride(key: String, value: String) {
        guard let coreID = currentCoreID else { return }
        var allOverrides = loadUserOverrides()
        allOverrides[key] = value
        
        let configURL = optionsFileURL(coreID)
        let content = allOverrides.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n")
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
        LoggerService.debug(category: "CoreOptionsManager", "For \(coreID): Saving content \(content) into file \(configURL)")
    }
    
    // Load all user overrides from the per-core config file.
    // Returns a dictionary [key: value] of persisted values.
    public func loadUserOverrides() -> [String: String] {
        guard let coreID = currentCoreID else { return [:] }
        let configURL = optionsFileURL(coreID)
        
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return [:]
        }
        
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            // Parse RetroArch format: key = "value"
            if let range = trimmed.range(of: "=") {
                let key = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                var value = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
                
                // Strip surrounding quotes
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                
                if !key.isEmpty {
                    result[key] = value
                }
            }
        }
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID): Loaded user overrides: \(result)")        
        return result
    }
    
    // Clear all persistend options for the current core.
    private func clearAllOverrides() {
        guard let coreID = currentCoreID else { return }
        let configURL = optionsFileURL(coreID)
        try? FileManager.default.removeItem(at: configURL)
        
        // Also clear the definitions cache
        let defURL = definitionsDirectory.appendingPathComponent("\(coreID).json")
        try? FileManager.default.removeItem(at: defURL)
    }
    
    // MARK: - Definition Persistence
    private func persistDefinitions(for coreID: String) {
        // Map categories
        let catsPayload = categories.mapValues { ["desc": $0.description, "info": $0.info] }
        
        // Map options using the BASE key as the JSON key
        var optsPayload: [String: Any] = [:]
        for (_, option) in options {
            optsPayload[option.key] = [ // <--- USE option.key (Base), NOT the dictionary key
                "desc": option.description,
                "info": option.info,
                "category": option.category ?? "general",
                "defaultValue": option.defaultValue,
                "currentValue": option.currentValue,
                "values": option.values.map { ["value": $0.value, "label": $0.label] }
            ]
        }

        let payload: [String: Any] = ["categories": catsPayload, "options": optsPayload]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            let url = definitionsDirectory.appendingPathComponent("\(coreID).json")
            try? data.write(to: url)
        }
    }

    // MARK: - Export / Import (RetroArch compatibility)
    
    // Export options in RetroArch-compatible .cfg format
    func exportAsRetroArchConfig() -> String {
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID): Exporting data as retroarch config")
        let lines = options.values.map { opt in
            "\(opt.key) = \"\(opt.currentValue)\""
        }
        return lines.joined(separator: "\n")
    }
}

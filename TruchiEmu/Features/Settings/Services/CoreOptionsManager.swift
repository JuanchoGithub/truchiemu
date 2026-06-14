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

    // Scope for persistence: system-level or per-game
    private var currentSystemID: String?
    private var currentGameFilename: String?

    // Directory for per-core option definitions (.json)
    private let definitionsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/CoreOptionDefinitions", isDirectory: true)
    }()

    // Directory for the per-core/per-system override hierarchy
    private let overridesDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/CoreOverrides", isDirectory: true)
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        try? FileManager.default.createDirectory(at: definitionsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: overridesDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    // Allow reading options for an arbitrary core (not just the currently loaded one)
    nonisolated func setCoreIDForReading(_ coreID: String) {
    }

    private nonisolated func parseCfgFile(at url: URL) -> [String: String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
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
        return result
    }

    // MARK: - System-Level and Game-Level Overrides

    nonisolated func saveSystemOverride(for coreID: String, systemID: String, values: [String: String]) {
        let dir = overridesDirectory.appendingPathComponent(coreID).appendingPathComponent(systemID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("overrides.cfg")
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "Saving system override for \(coreID)/\(systemID): \(values)")
        #endif
        let content = values.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n")
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    nonisolated func loadSystemOverrides(for coreID: String, systemID: String) -> [String: String] {
        let configURL = overridesDirectory.appendingPathComponent(coreID).appendingPathComponent(systemID).appendingPathComponent("overrides.cfg")
        return parseCfgFile(at: configURL)
    }

    nonisolated func saveGameOverride(for coreID: String, systemID: String, gameFilename: String, values: [String: String]) {
        let dir = overridesDirectory.appendingPathComponent(coreID).appendingPathComponent(systemID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("\(gameFilename).cfg")
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "Saving game override for \(coreID)/\(systemID)/\(gameFilename): \(values)")
        #endif
        let content = values.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n")
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    nonisolated func loadGameOverrides(for coreID: String, systemID: String, gameFilename: String) -> [String: String] {
        let configURL = overridesDirectory.appendingPathComponent(coreID).appendingPathComponent(systemID).appendingPathComponent("\(gameFilename).cfg")
        return parseCfgFile(at: configURL)
    }

    nonisolated func deleteGameOverride(for coreID: String, systemID: String, gameFilename: String) {
        let configURL = overridesDirectory.appendingPathComponent(coreID).appendingPathComponent(systemID).appendingPathComponent("\(gameFilename).cfg")
        try? FileManager.default.removeItem(at: configURL)
    }

    nonisolated func deleteSystemOverride(for coreID: String, systemID: String) {
        let configURL = overridesDirectory.appendingPathComponent(coreID).appendingPathComponent(systemID).appendingPathComponent("overrides.cfg")
        try? FileManager.default.removeItem(at: configURL)
    }

    // MARK: - Core Lifecycle

    func prepareForCore(coreID: String) {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "New core \(coreID) loaded, cleaning all optiones and overrides")
        #endif
        currentCoreID = coreID
        currentSystemID = nil
        currentGameFilename = nil
        options.removeAll()
        categories.removeAll()
    }

    func setScope(systemID: String?, gameFilename: String? = nil) {
        currentSystemID = systemID
        currentGameFilename = gameFilename
    }

    // MARK: - Override Layer Application

    private func applyOverrideLayers(to option: inout CoreOption, coreID: String) {
        let coreDefault = option.defaultValue
        var currentValue = coreDefault
        var source: OverrideSource = .coreDefault
        var previousLayerValue = coreDefault

        // Layer 1: Bundled app defaults
        let appDefaults = CoreOverrideService.shared.getOverrides(for: coreID, scope: "default")
        if let appValue = appDefaults[option.key] {
            currentValue = appValue
            source = .appDefault
            previousLayerValue = coreDefault
        }

        // Layer 2: Bundled system-specific overrides (e.g., gambatte_gb.json)
        if let sysID = currentSystemID {
            let systemOverrides = CoreOverrideService.shared.getOverrides(for: coreID, scope: sysID)
            if let sysValue = systemOverrides[option.key] {
                previousLayerValue = currentValue
                currentValue = sysValue
                source = .appSystemDefault
            }
        }

        // Layer 3: User system-level overrides
        if let sysID = currentSystemID {
            let userSystem = loadSystemOverrides(for: coreID, systemID: sysID)
            if let userSysValue = userSystem[option.key] {
                previousLayerValue = currentValue
                currentValue = userSysValue
                source = .systemOverride
            }
        }

        // Layer 4: User game-level overrides
        if let gameFilename = currentGameFilename, let sysID = currentSystemID {
            let userGame = loadGameOverrides(for: coreID, systemID: sysID, gameFilename: gameFilename)
            if let gameValue = userGame[option.key] {
                previousLayerValue = currentValue
                currentValue = gameValue
                source = .gameOverride
            }
        }

        option.currentValue = currentValue
        option.overrideSource = source
        option.previousLayerValue = previousLayerValue
    }

    // Loads definitions and overrides from disk for a specific core.
    // Used when the core is not running (e.g., in Settings).
    func loadForCore(coreID: String, dylibPath: String? = nil, romPath: String? = nil) {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "Loading options from core: \(coreID)")
        #endif
        currentCoreID = coreID

        let defURL = definitionsDirectory.appendingPathComponent("\(coreID).json")

        guard let data = try? Data(contentsOf: defURL),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            options.removeAll()
            categories.removeAll()
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreOptionsManager", "For \(coreID): cleaned up. Definitions not found.")
            #endif
            return
        }

        if let cats = json["categories"] as? [String: [String: String]] {
            self.categories = cats.reduce(into: [:]) { res, entry in
                res[entry.key] = CoreOptionCategory(key: entry.key, description: entry.value["desc"] ?? entry.key, info: entry.value["info"] ?? "")
            }
        }

        if let opts = json["options"] as? [String: [String: Any]] {
            self.options.removeAll()
            for (jsonKey, d) in opts {
                let internalKey = makeInternalKey(baseKey: jsonKey, version: .v2)

                var option = CoreOption(
                    key: jsonKey,
                    description: d["desc"] as? String ?? jsonKey,
                    info: d["info"] as? String ?? "",
                    category: d["category"] as? String ?? "general",
                    values: (d["values"] as? [[String: String]])?.map { CoreOptionValue(value: $0["value"] ?? "", label: $0["label"] ?? "") } ?? [],
                    defaultValue: d["defaultValue"] as? String ?? "",
                    currentValue: d["currentValue"] as? String ?? "",
                    version: .v2
                )
                applyOverrideLayers(to: &option, coreID: coreID)
                options[internalKey] = option
            }
        }
    }

    private func makeInternalKey(baseKey: String, version: CoreOptionVersion) -> String {
        let suffix = "_\(version.rawValue)"
        if baseKey.hasSuffix(suffix) {
            return baseKey
        }
        return "\(baseKey)\(suffix)"
    }

    private func versionedKeys(for baseKey: String) -> [String] {
        options.keys.filter { $0 == "\(baseKey)_V1" || $0 == "\(baseKey)_V2" }
    }

    /// Triggers the discovery of core options AND input descriptors by launching a headless core session.
    func discoverOptions(for coreID: String, dylibPath: String, romPath: String?) async {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "Starting discovery for core: \(coreID)")
        #endif

        var dummyRomPath: String? = nil
        if let systemID = CoreManager.supportedSystems(for: coreID).first {
            let repository = ROMRepository(context: SwiftDataContainer.shared.mainContext)
            if let rom = repository.firstROM(forSystemID: systemID) {
                dummyRomPath = rom.path.path
            }
        }

        XPCBridgeAdapter.shared.loadCoreForOptions(dylibPath: dylibPath, coreID: coreID, romPath: dummyRomPath)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), Core loaded")
        #endif

        let optionsDict = (XPCBridgeAdapter.shared.getOptionsDictionary() as? [String: [String: Any]]) ?? [:]
        let categoriesDict = (XPCBridgeAdapter.shared.getCategoriesDictionary() as? [String: [String: Any]]) ?? [:]
        let rawDescriptors = XPCBridgeAdapter.shared.getInputDescriptorsDictionary() ?? [:]
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), options: \(optionsDict), categories: \(categoriesDict), inputDescriptors: \(rawDescriptors)")
        #endif

        var newOptions: [CoreOption] = []
        var newCategories: [CoreOptionCategory] = []

        for (catKey, catData) in categoriesDict {
            let desc = catData["desc"] as? String ?? catKey
            let info = catData["info"] as? String ?? ""
            newCategories.append(CoreOptionCategory(key: catKey, description: desc, info: info))
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), new Categories: \(newCategories)")
        #endif

        for (key, optData) in optionsDict {
            let desc = optData["desc"] as? String ?? key
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
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), Parsed options")
        #endif

        var buttonDescriptors: [InputButtonDescriptor] = []
        for (_, value) in rawDescriptors {
            if let buttons = value as? [[String: Any]] {
                for buttonDict in buttons {
                    if let id = buttonDict["id"] as? Int, let desc = buttonDict["description"] as? String {
                        buttonDescriptors.append(InputButtonDescriptor(id: id, description: desc))
                    }
                }
            } else if let buttons = value as? [Any] {
                for button in buttons {
                    if let dict = button as? [String: Any],
                       let id = dict["id"] as? Int, let desc = dict["description"] as? String {
                        buttonDescriptors.append(InputButtonDescriptor(id: id, description: desc))
                    }
                }
            }
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For: \(coreID), parsed \(buttonDescriptors.count) input descriptors")
        #endif

        await MainActor.run {
            self.prepareForCore(coreID: coreID)
            self.setOptions(newOptions, categories: newCategories)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreOptionsManager", "Discovery complete. Persisted \(newOptions.count) options.")
            #endif

            if !buttonDescriptors.isEmpty {
                InputDescriptorsManager.shared.setDescriptors(buttonDescriptors, for: coreID)
                #if LOG_DEBUG
                LoggerService.debug(category: "CoreOptionsManager", "Discovery complete. Persisted \(buttonDescriptors.count) input descriptors.")
                #endif
            }
        }
    }

    // Set the full options list (called from ObjC bridge when core calls SET_CORE_OPTIONS_V2).
    func setOptions(_ newOptions: [CoreOption], categories: [CoreOptionCategory]) {
        var updatedCategories = Dictionary(uniqueKeysWithValues: categories.map { ($0.key, $0) })
        let fallbackKey = "general"
        if updatedCategories[fallbackKey] == nil {
            updatedCategories[fallbackKey] = CoreOptionCategory(key: fallbackKey, description: "General Settings", info: "")
        }
        self.categories = updatedCategories

        let coreID = currentCoreID ?? ""

        for var option in newOptions {
            if option.category == nil || option.category?.isEmpty == true {
                option.category = fallbackKey
            }
            applyOverrideLayers(to: &option, coreID: coreID)
            let internalKey = makeInternalKey(baseKey: option.key, version: option.version)
            self.options[internalKey] = option
        }

        if let coreID = currentCoreID {
            persistDefinitions(for: coreID)
        }
    }

    // Set options from a V1 core (simpler struct).
    func setOptionsV1(_ newOptions: [CoreOption]) {
        self.categories.removeAll()
        let coreID = currentCoreID ?? ""

        for var option in newOptions {
            applyOverrideLayers(to: &option, coreID: coreID)
            var v1Option = option
            v1Option.version = .v1
            let versionedKey = "\(option.key)_\(CoreOptionVersion.v1.rawValue)"
            self.options[versionedKey] = v1Option
        }
    }

    // MARK: - Reading Values (used by GET_VARIABLE callback)

    func getValue(for key: String) -> String? {
        if let v1Value = options["\(key)_\(CoreOptionVersion.v1.rawValue)"]?.currentValue {
            return v1Value
        }
        return options["\(key)_\(CoreOptionVersion.v2.rawValue)"]?.currentValue
    }

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

    func updateValue(_ value: String, for key: String) {
        let matchingKeys = versionedKeys(for: key)

        guard !matchingKeys.isEmpty else { return }

        let baseResult = computeBaseValue(for: key)

        if value == baseResult.value {
            for vKey in matchingKeys {
                options[vKey]?.currentValue = value
                options[vKey]?.overrideSource = baseResult.source
                options[vKey]?.previousLayerValue = baseResult.previousLayerValue
            }
            removeOverrideAtCurrentScope(key: key)
        } else {
            let source: OverrideSource = currentGameFilename != nil ? .gameOverride : .systemOverride
            for vKey in matchingKeys {
                options[vKey]?.previousLayerValue = baseResult.value
                options[vKey]?.currentValue = value
                options[vKey]?.overrideSource = source
            }
            persistOverride(key: key, value: value)
        }

        // Push the change to the running core immediately so it takes effect
        // at runtime — not just on the next launch.
        XPCBridgeAdapter.shared.setOptionValue(value, forKey: key)
    }

    private struct BaseValueResult {
        let value: String
        let source: OverrideSource
        let previousLayerValue: String
    }

    private func computeBaseValue(for key: String) -> BaseValueResult {
        guard let coreID = currentCoreID else {
            return BaseValueResult(value: "", source: .coreDefault, previousLayerValue: "")
        }

        let coreDefault: String
        if let firstKey = versionedKeys(for: key).first,
            let opt = options[firstKey] {
            coreDefault = opt.defaultValue
        } else {
            return BaseValueResult(value: "", source: .coreDefault, previousLayerValue: "")
        }

        var value = coreDefault
        var source: OverrideSource = .coreDefault
        var prevLayer = coreDefault

        let appDefaults = CoreOverrideService.shared.getOverrides(for: coreID, scope: "default")
        if let appValue = appDefaults[key] {
            prevLayer = value
            value = appValue
            source = .appDefault
        }

        if let sysID = currentSystemID {
            let systemOverrides = CoreOverrideService.shared.getOverrides(for: coreID, scope: sysID)
            if let sysValue = systemOverrides[key] {
                prevLayer = value
                value = sysValue
                source = .appSystemDefault
            }

            let userSystem = loadSystemOverrides(for: coreID, systemID: sysID)
            if let userSysValue = userSystem[key] {
                prevLayer = value
                value = userSysValue
                source = .systemOverride
            }
        }

        return BaseValueResult(value: value, source: source, previousLayerValue: prevLayer)
    }

    func restoreToPreviousLayer(key: String) {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID ?? "unknown"): restoring key: \(key) to previous layer")
        #endif

        let matchingKeys = versionedKeys(for: key)
        guard !matchingKeys.isEmpty else { return }

        let baseResult = computeBaseValue(for: key)

        for vKey in matchingKeys {
            options[vKey]?.currentValue = baseResult.value
            options[vKey]?.overrideSource = baseResult.source
            options[vKey]?.previousLayerValue = baseResult.previousLayerValue
        }

        removeOverrideAtCurrentScope(key: key)

        // Push the restored value to the running core immediately
        XPCBridgeAdapter.shared.setOptionValue(baseResult.value, forKey: key)
    }

    func resetToDefault(key: String) {
        restoreToPreviousLayer(key: key)
    }

    func resetAllToDefaults() {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID ?? "unknown"): resetting ALL KEYS")
        #endif
        clearAllOverrides()

        for (vKey, _) in options {
            if let optKey = options[vKey]?.key {
                let baseResult = computeBaseValue(for: optKey)
                options[vKey]?.currentValue = baseResult.value
                options[vKey]?.overrideSource = baseResult.source
                options[vKey]?.previousLayerValue = baseResult.previousLayerValue

                // Push each restored value to the running core
                XPCBridgeAdapter.shared.setOptionValue(baseResult.value, forKey: optKey)
            }
        }

        if let coreID = currentCoreID {
            persistDefinitions(for: coreID)
        }
    }

    // MARK: - Persistence

    private func persistOverride(key: String, value: String) {
        guard let coreID = currentCoreID, let systemID = currentSystemID else { return }

        if let gameFilename = currentGameFilename {
            var allOverrides = loadGameOverrides(for: coreID, systemID: systemID, gameFilename: gameFilename)
            allOverrides[key] = value
            saveGameOverride(for: coreID, systemID: systemID, gameFilename: gameFilename, values: allOverrides)
        } else {
            var allOverrides = loadSystemOverrides(for: coreID, systemID: systemID)
            allOverrides[key] = value
            saveSystemOverride(for: coreID, systemID: systemID, values: allOverrides)
        }
    }

    private func removeOverrideAtCurrentScope(key: String) {
        guard let coreID = currentCoreID, let systemID = currentSystemID else { return }

        if let gameFilename = currentGameFilename {
            var allOverrides = loadGameOverrides(for: coreID, systemID: systemID, gameFilename: gameFilename)
            allOverrides.removeValue(forKey: key)
            if allOverrides.isEmpty {
                deleteGameOverride(for: coreID, systemID: systemID, gameFilename: gameFilename)
            } else {
                saveGameOverride(for: coreID, systemID: systemID, gameFilename: gameFilename, values: allOverrides)
            }
        } else {
            var allOverrides = loadSystemOverrides(for: coreID, systemID: systemID)
            allOverrides.removeValue(forKey: key)
            if allOverrides.isEmpty {
                deleteSystemOverride(for: coreID, systemID: systemID)
            } else {
                saveSystemOverride(for: coreID, systemID: systemID, values: allOverrides)
            }
        }
    }

    public func loadUserOverrides() -> [String: String] {
        guard let coreID = currentCoreID, let systemID = currentSystemID else { return [:] }

        var result = loadSystemOverrides(for: coreID, systemID: systemID)
        if let gameFilename = currentGameFilename {
            let gameOverrides = loadGameOverrides(for: coreID, systemID: systemID, gameFilename: gameFilename)
            result.merge(gameOverrides) { _, new in new }
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For \(coreID)/\(systemID): Loaded overrides: \(result)")
        #endif
        return result
    }

    private func clearAllOverrides() {
        guard let coreID = currentCoreID else { return }

        if let systemID = currentSystemID {
            if let gameFilename = currentGameFilename {
                deleteGameOverride(for: coreID, systemID: systemID, gameFilename: gameFilename)
            } else {
                deleteSystemOverride(for: coreID, systemID: systemID)
            }
        }

        let defURL = definitionsDirectory.appendingPathComponent("\(coreID).json")
        try? FileManager.default.removeItem(at: defURL)
    }

    // MARK: - Definition Persistence
    private func persistDefinitions(for coreID: String) {
        let catsPayload = categories.mapValues { ["desc": $0.description, "info": $0.info] }

        var optsPayload: [String: Any] = [:]
        for (_, option) in options {
            optsPayload[option.key] = [
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

    nonisolated func resolveEffectiveValue(for key: String, coreID: String, systemID: String?, gameFilename: String?) -> (value: String, source: OverrideSource) {
        let persistedDefs = definitionsDirectory.appendingPathComponent("\(coreID).json")
        guard let data = try? Data(contentsOf: persistedDefs),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let opts = json["options"] as? [String: [String: Any]],
              let optData = opts[key],
              let defVal = optData["defaultValue"] as? String else {
            return (value: "", source: .coreDefault)
        }

        var value = defVal
        var source: OverrideSource = .coreDefault

        let appDefaults = CoreOverrideService.shared.getOverrides(for: coreID, scope: "default")
        if let appValue = appDefaults[key] {
            value = appValue
            source = .appDefault
        }

        if let sysID = systemID {
            let systemOverrides = CoreOverrideService.shared.getOverrides(for: coreID, scope: sysID)
            if let sysValue = systemOverrides[key] {
                value = sysValue
                source = .appSystemDefault
            }

            let userSystem = loadSystemOverrides(for: coreID, systemID: sysID)
            if let userSysValue = userSystem[key] {
                value = userSysValue
                source = .systemOverride
            }

            if let game = gameFilename {
                let userGame = loadGameOverrides(for: coreID, systemID: sysID, gameFilename: game)
                if let gameValue = userGame[key] {
                    value = gameValue
                    source = .gameOverride
                }
            }
        }

        return (value: value, source: source)
    }

    // MARK: - Auto-Discovery Helpers

    nonisolated func definitionsFileExists(for coreID: String) -> Bool {
        let url = definitionsDirectory.appendingPathComponent("\(coreID).json")
        return FileManager.default.fileExists(atPath: url.path)
    }

    @MainActor func discoverOptionsIfNeeded(for coreID: String, romPath: String? = nil) {
        guard !definitionsFileExists(for: coreID) else { return }
        guard let core = CoreManager.shared.installedCores.first(where: { $0.id == coreID }) else { return }
        let dylibPath = core.activeVersion?.dylibPath.path
            ?? core.installedVersions.first(where: { FileManager.default.fileExists(atPath: $0.dylibPath.path) })?.dylibPath.path
        guard let dylib = dylibPath else { return }
        Task {
            await discoverOptions(for: coreID, dylibPath: dylib, romPath: romPath)
        }
    }

    // MARK: - Export / Import (RetroArch compatibility)

    func exportAsRetroArchConfig() -> String {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreOptionsManager", "For \(currentCoreID ?? "unknown"): Exporting data as retroarch config")
        #endif
        let lines = options.values.map { opt in
            "\(opt.key) = \"\(opt.currentValue)\""
        }
        return lines.joined(separator: "\n")
    }
}

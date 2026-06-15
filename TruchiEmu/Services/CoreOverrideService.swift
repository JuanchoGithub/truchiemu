import Foundation

final class CoreOverrideService {
    static let shared = CoreOverrideService()

    // Key: coreID, Value: [scope: [optionKey: optionValue]]
    // scope is "default" or a systemID like "gb", "gbc"
    private var overrides: [String: [String: [String: String]]] = [:]

    static let coreOverridesDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/CoreOverrides", isDirectory: true)
    }()

    private init() {
        loadOverrides()
    }

    private func loadOverrides() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            LoggerService.info(category: "CoreOverrideService", "No bundled CoreOverrides found")
            return
        }

        for url in urls {
            let filename = url.deletingPathExtension().lastPathComponent

            guard filename.contains("_libretro_") else { continue }
            guard let libretroRange = filename.range(of: "_libretro") else { continue }
            let coreID = String(filename[..<libretroRange.upperBound])
            let remainder = String(filename[libretroRange.upperBound...])
            guard remainder.hasPrefix("_") else { continue }
            let scope = String(remainder.dropFirst())

            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            var scopeOverrides: [String: String] = [:]
            for (key, value) in json {
                if let str = value as? String {
                    scopeOverrides[key] = str
                } else if let num = value as? NSNumber {
                    scopeOverrides[key] = num.stringValue
                }
            }

            if overrides[coreID] == nil {
                overrides[coreID] = [:]
            }
            overrides[coreID]?[scope] = scopeOverrides
            LoggerService.info(category: "CoreOverrideService", "Loaded bundled override: \(coreID)/\(scope) (\(scopeOverrides.count) options)")
        }

        LoggerService.info(category: "CoreOverrideService", "Loaded bundled overrides for \(self.overrides.count) cores")
    }

    func syncBundledOverridesToAppSupport() {
        let baseDir = Self.coreOverridesDirectory
        let fm = FileManager.default

        guard let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return }

        let versionFile = baseDir.appendingPathComponent(".bundle_version")
        let currentVersion = try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let isVersionChange = currentVersion != bundleVersion

        do {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            LoggerService.error(category: "CoreOverrideService", "Failed to create CoreOverrides directory: \(error)")
            return
        }

        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return
        }

        var syncedCount = 0
        for url in urls {
            let filename = url.deletingPathExtension().lastPathComponent
            guard filename.contains("_libretro_") else { continue }
            guard let libretroRange = filename.range(of: "_libretro") else { continue }
            let coreID = String(filename[..<libretroRange.upperBound])
            let remainder = String(filename[libretroRange.upperBound...])
            guard remainder.hasPrefix("_") else { continue }
            let scope = String(remainder.dropFirst())

            let coreDir = baseDir.appendingPathComponent(coreID, isDirectory: true)
            try? fm.createDirectory(at: coreDir, withIntermediateDirectories: true)

            let dest = coreDir.appendingPathComponent("\(scope).json")
            let destExists = fm.fileExists(atPath: dest.path)

            if destExists && !isVersionChange {
                continue
            }

            if destExists {
                try? fm.removeItem(at: dest)
            }
            do {
                try fm.copyItem(at: url, to: dest)
                syncedCount += 1
            } catch {
                LoggerService.error(category: "CoreOverrideService", "Failed to sync override \(coreID)/\(scope): \(error)")
            }
        }

        try? bundleVersion.write(to: versionFile, atomically: true, encoding: .utf8)
        if syncedCount > 0 {
            LoggerService.info(category: "CoreOverrideService", "Synced \(syncedCount) bundled override files to CoreOverrides (bundle \(bundleVersion))")
        }
    }

    func reloadOverrides() {
        LoggerService.info(category: "CoreOverrideService", "Reloading core overrides...")
        loadOverrides()
    }

    func getOverrides(for coreID: String) -> [String: String] {
        var result: [String: String] = [:]
        if let scopes = overrides[coreID] {
            if let defaults = scopes["default"] {
                result.merge(defaults) { _, new in new }
            }
            for (scope, values) in scopes where scope != "default" {
                result.merge(values) { _, new in new }
            }
        }
        return result
    }

    func getOverrides(for coreID: String, systemID: String?) -> [String: String] {
        var result: [String: String] = [:]
        if let scopes = overrides[coreID] {
            if let defaults = scopes["default"] {
                result.merge(defaults) { _, new in new }
            }
            if let sysID = systemID, let systemOverrides = scopes[sysID] {
                result.merge(systemOverrides) { _, new in new }
            }
        }
        return result
    }

    func getOverrides(for coreID: String, scope: String) -> [String: String] {
        return overrides[coreID]?[scope] ?? [:]
    }

    func getOverride(for coreID: String, optionKey: String) -> String? {
        let all = getOverrides(for: coreID)
        return all[optionKey]
    }

    func hasOverrides(for coreID: String) -> Bool {
        return overrides[coreID]?.isEmpty == false
    }

    var supportedCoreIDs: [String] {
        return Array(overrides.keys)
    }

    func getOverrideDescription(for coreID: String) -> String? {
        return overrides[coreID]?["default"]?["override_description"]
    }

    func applyConfigurationUpdate(_ updates: [CoreOverrideUpdate]) {
        for update in updates {
            if update.type == .upsert {
                if overrides[update.coreID] == nil {
                    overrides[update.coreID] = [:]
                }
                if overrides[update.coreID]?["default"] == nil {
                    overrides[update.coreID]?["default"] = [:]
                }
                overrides[update.coreID]?["default"]?[update.optionKey] = update.optionValue
            } else if update.type == .delete {
                overrides[update.coreID]?["default"]?.removeValue(forKey: update.optionKey)
            }
        }
    }
}

struct CoreOverrideUpdate {
    enum UpdateType {
        case upsert
        case delete
    }

    let coreID: String
    let optionKey: String
    let optionValue: String?
    let type: UpdateType

    init(coreID: String, optionKey: String, optionValue: String?, type: UpdateType = .upsert) {
        self.coreID = coreID
        self.optionKey = optionKey
        self.optionValue = optionValue
        self.type = type
    }
}

@objc class CoreOverrideBridge: NSObject {

    @objc static func hasOverride(for coreID: NSString, optionKey: NSString) -> Bool {
        return CoreOverrideService.shared.getOverride(for: coreID as String, optionKey: optionKey as String) != nil
    }

    @objc static func getOverride(for coreID: NSString, optionKey: NSString) -> NSString? {
        return CoreOverrideService.shared.getOverride(for: coreID as String, optionKey: optionKey as String) as NSString?
    }

    @objc static func logOverrides(for coreID: NSString) {
        let overrides = CoreOverrideService.shared.getOverrides(for: coreID as String)
        #if LOG_DEBUG
        if overrides.isEmpty {
            LoggerService.debug(category: "CoreOverrideBridge", "No overrides for core: \(coreID)")
        } else {
            for (key, value) in overrides {
                LoggerService.debug(category: "CoreOverrideBridge", " \(key) = \(value)")
            }
        }
        #endif
    }

    @objc static func getOverrideKeys(for coreID: NSString) -> [String] {
        return Array(CoreOverrideService.shared.getOverrides(for: coreID as String).keys)
    }

    @objc static func getAllOverrides(for coreID: NSString) -> NSDictionary {
        return CoreOverrideService.shared.getOverrides(for: coreID as String) as NSDictionary
    }
}

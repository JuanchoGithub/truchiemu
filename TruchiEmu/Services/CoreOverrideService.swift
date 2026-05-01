import Foundation
import OSLog

/// Service for loading and applying core-specific option overrides from configuration files.
/// This replaces hardcoded overrides in LibretroCallbacks.mm with data-driven configuration.
final class CoreOverrideService {
    static let shared = CoreOverrideService()
    
    private var overrides: [String: [String: String]] = [:]
    private let logger = Logger(subsystem: "com.truchiemu", category: "CoreOverrideService")
    
    private init() {
        loadOverrides()
    }
    
    /// Loads core-specific overrides from CoreOverrides.json
    private func loadOverrides() {
        var url = Bundle.main.url(forResource: "CoreOverrides", withExtension: "json", subdirectory: "Config")
        
        if url == nil {
            logger.warning("CoreOverrides.json not found in 'Config' subdirectory, searching bundle root...")
            url = Bundle.main.url(forResource: "CoreOverrides", withExtension: "json")
        }
        
        guard let finalUrl = url else {
            logger.error("CoreOverrides.json not found in bundle (checked 'Config/' and root)")
            return
        }
        
        logger.info("Loading overrides from: \(finalUrl.path)")
        
        do {
            let data = try Data(contentsOf: finalUrl)
            let decoder = JSONDecoder()
            let container = try decoder.decode(CoreOverridesContainer.self, from: data)
            
        overrides = container.overrides
        logger.info("Loaded \(self.overrides.count) core override configurations")
        
        // Log loaded overrides for debugging
        for (coreID, options) in self.overrides {
            logger.debug("Overrides for \(coreID): \(options.count) options")
        }
        } catch {
            logger.error("Failed to load CoreOverrides.json: \(error.localizedDescription)")
        }
    }
    
    /// Reloads overrides from disk (useful for development or config updates)
    func reloadOverrides() {
        logger.info("Reloading core overrides...")
        loadOverrides()
    }
    
    /// Gets all overrides for a specific core
    func getOverrides(for coreID: String) -> [String: String] {
        let result = overrides[coreID] ?? [:]
        if result.isEmpty {
            logger.debug("No overrides found for coreID: '\(coreID)'. Available keys: \(self.overrides.keys.joined(separator: ", "))")
        }
        return result
    }
    
    /// Gets a specific override value for a core option
    func getOverride(for coreID: String, optionKey: String) -> String? {
        let val = overrides[coreID]?[optionKey]
        if val != nil {
            logger.info("Match found for \(coreID)[\(optionKey)] = \(val!)")
        }
        return val
    }
    
    /// Checks if any overrides exist for a core
    func hasOverrides(for coreID: String) -> Bool {
        return overrides[coreID]?.isEmpty == false
    }
    
    /// Gets all core IDs that have configured overrides
    var supportedCoreIDs: [String] {
        return Array(overrides.keys)
    }
    
    /// Gets the description for a core's overrides
    func getOverrideDescription(for coreID: String) -> String? {
        return overrides[coreID]?["override_description"]
    }
    
    /// Applies a configuration update at runtime (for future hot-reload capability)
    func applyConfigurationUpdate(_ updates: [CoreOverrideUpdate]) {
        logger.info("Applying \(updates.count) configuration updates")
        
        for update in updates {
            if update.type == .upsert {
                if overrides[update.coreID] == nil {
                    overrides[update.coreID] = [:]
                }
                overrides[update.coreID]?[update.optionKey] = update.optionValue
            } else if update.type == .delete {
                overrides[update.coreID]?.removeValue(forKey: update.optionKey)
            }
        }
        
        logger.debug("Configuration updates applied successfully")
    }
}

// MARK: - Data Models

private struct CoreOverridesContainer: Codable {
    let comment: String
    let overrides: [String: [String: String]]
}

/// Represents a configuration update for a core option override
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

// MARK: - Objective-C Bridge for C code

/// Objective-C bridge for accessing CoreOverrideService from C code
@objc class CoreOverrideBridge: NSObject {
    
    @objc static func hasOverride(for coreID: NSString, optionKey: NSString) -> Bool {
        return CoreOverrideService.shared.getOverride(for: coreID as String, optionKey: optionKey as String) != nil
    }
    
    @objc static func getOverride(for coreID: NSString, optionKey: NSString) -> NSString? {
        return CoreOverrideService.shared.getOverride(for: coreID as String, optionKey: optionKey as String) as NSString?
    }
    
    @objc static func logOverrides(for coreID: NSString) {
        let overrides = CoreOverrideService.shared.getOverrides(for: coreID as String)
        let logger = Logger(subsystem: "com.truchiemu", category: "CoreOverrideBridge")
        
        if overrides.isEmpty {
            logger.debug("No overrides for core: \(coreID)")
        } else {
            logger.info("Overrides for \(coreID): \(overrides.count) options")
            for (key, value) in overrides {
                logger.debug(" \(key) = \(value)")
            }
        }
    }
    
    @objc static func getOverrideKeys(for coreID: NSString) -> [String] {
        return Array(CoreOverrideService.shared.getOverrides(for: coreID as String).keys)
    }
}

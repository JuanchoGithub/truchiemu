import Foundation
import SwiftData

// MARK: - Core Options Repository

/// Repository for core options persistence using SwiftData.
@MainActor
final class CoreOptionsRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Read Methods

    /// Get all options for a given core as a dictionary.
    func getOptions(for coreID: String) -> [String: String] {
        let descriptor = FetchDescriptor<CoreOptionEntry>(
            predicate: #Predicate { $0.coreID == coreID }
        )
        do {
            let entries = try context.fetch(descriptor)
            var options: [String: String] = [:]
            for entry in entries {
                if let value = entry.optionValue {
                    options[entry.optionKey] = value
                }
            }
            return options
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to get options for core \(coreID): \(error.localizedDescription)")
            return [:]
        }
    }

    /// Get override-only options for a core (user-specified overrides).
    func getOverrideOptions(for coreID: String) -> [String: String] {
        let descriptor = FetchDescriptor<CoreOptionEntry>(
            predicate: #Predicate { $0.coreID == coreID && $0.isOverride }
        )
        do {
            let entries = try context.fetch(descriptor)
            var options: [String: String] = [:]
            for entry in entries {
                if let value = entry.optionValue {
                    options[entry.optionKey] = value
                }
            }
            return options
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to get override options: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Get all core option entries across all cores.
    func getAllOptions() -> [CoreOptionEntry] {
        let descriptor = FetchDescriptor<CoreOptionEntry>()
        do {
            return try context.fetch(descriptor)
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to get all options: \(error.localizedDescription)")
            return []
        }
    }

    /// Get a single option value for a given core.
    func getOption(key: String, for coreID: String) -> String? {
        let compositeKey = "\(coreID)::\(key)"
        let descriptor = FetchDescriptor<CoreOptionEntry>(
            predicate: #Predicate { $0.compositeKey == compositeKey }
        )
        do {
            return try context.fetch(descriptor).first?.optionValue
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to get option: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Write Methods

    /// Set a single option for a given core.
    func setOption(key: String, value: String, for coreID: String) {
        let compositeKey = "\(coreID)::\(key)"
        let descriptor = FetchDescriptor<CoreOptionEntry>(
            predicate: #Predicate { $0.compositeKey == compositeKey }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.optionValue = value
            } else {
                let entry = CoreOptionEntry(
                    coreID: coreID,
                    optionKey: key,
                    optionValue: value
                )
                context.insert(entry)
            }
            try context.save()
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to set option: \(error.localizedDescription)")
        }
    }

    /// Set multiple options for a given core, overwriting existing ones.
    func setOptions(_ options: [String: String], for coreID: String) {
        // Get existing entries to detect removals
        let existingDescriptor = FetchDescriptor<CoreOptionEntry>(
            predicate: #Predicate { $0.coreID == coreID }
        )
        let existingKeys: Set<String>
        do {
            let existing = try context.fetch(existingDescriptor)
            existingKeys = Set(existing.map { $0.optionKey })
        } catch {
            existingKeys = []
        }

        let keysToRemove = existingKeys.subtracting(options.keys)

        // Remove keys that are no longer present
        for keyToRemove in keysToRemove {
            let compositeKey = "\(coreID)::\(keyToRemove)"
            let descriptor = FetchDescriptor<CoreOptionEntry>(
                predicate: #Predicate { $0.compositeKey == compositeKey }
            )
            if let existing = try? context.fetch(descriptor).first {
                context.delete(existing)
            }
        }

        // Upsert new options
        for (key, value) in options {
            let compositeKey = "\(coreID)::\(key)"
            let descriptor = FetchDescriptor<CoreOptionEntry>(
                predicate: #Predicate { $0.compositeKey == compositeKey }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.optionValue = value
            } else {
                let entry = CoreOptionEntry(
                    coreID: coreID,
                    optionKey: key,
                    optionValue: value
                )
                context.insert(entry)
            }
        }

        do {
            try context.save()
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to set options: \(error.localizedDescription)")
        }
    }

    /// Clear all options for a given core.
    func clearOptions(for coreID: String) {
        let descriptor = FetchDescriptor<CoreOptionEntry>(
            predicate: #Predicate { $0.coreID == coreID }
        )
        do {
            let entries = try context.fetch(descriptor)
            for entry in entries {
                context.delete(entry)
            }
            try context.save()
            LoggerService.info(category: "CoreOptionsRepository", "Cleared options for core \(coreID).")
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to clear options: \(error.localizedDescription)")
        }
    }

    /// Clear all options across all cores.
    func clearAllOptions() {
        do {
            let descriptor = FetchDescriptor<CoreOptionEntry>()
            let entries = try context.fetch(descriptor)
            for entry in entries {
                context.delete(entry)
            }
            try context.save()
            LoggerService.info(category: "CoreOptionsRepository", "Cleared all core options.")
        } catch {
            LoggerService.error(category: "CoreOptionsRepository", "Failed to clear all options: \(error.localizedDescription)")
        }
    }
}
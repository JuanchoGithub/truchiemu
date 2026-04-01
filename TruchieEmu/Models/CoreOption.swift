import Foundation
import Combine

// MARK: - Core Option Models

/// A value that a core option can take.
struct CoreOptionValue: Identifiable, Codable, Hashable {
    var id: String { value }
    let value: String       /// The actual value string sent to the core
    let label: String       /// Display-friendly label
    
    init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

/// A single configurable option exposed by a libretro core.
struct CoreOption: Identifiable, Codable, Hashable {
    var id: String { key }
    let key: String                 /// Unique key, e.g. "mupen64plus-cpucore"
    let description: String         /// Short display name
    let info: String                /// Help/description text
    let category: String?           /// Category key (nil = uncategorized)
    var values: [CoreOptionValue]   /// Possible values
    let defaultValue: String        /// Default value from core
    var currentValue: String        /// Live/current value
    
    /// The label for the currently selected value
    var currentLabel: String {
        values.first { $0.value == currentValue }?.label ?? currentValue
    }
    
    /// Whether this option has a non-default value
    var isModified: Bool {
        currentValue != defaultValue
    }
    
    init(key: String, description: String, info: String = "", category: String? = nil,
         values: [CoreOptionValue], defaultValue: String, currentValue: String? = nil) {
        self.key = key
        self.description = description
        self.info = info
        self.category = category
        self.values = values
        self.defaultValue = defaultValue
        self.currentValue = currentValue ?? defaultValue
    }
}

/// A category for grouping V2 core options.
struct CoreOptionCategory: Identifiable, Codable, Hashable {
    var id: String { key }
    let key: String
    let description: String
    let info: String
}
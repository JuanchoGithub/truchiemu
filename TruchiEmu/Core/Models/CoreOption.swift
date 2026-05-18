import Foundation
import Combine

// MARK: - Core Option Models

enum OverrideSource: String, Codable, CaseIterable {
    case coreDefault
    case appDefault
    case appSystemDefault
    case systemOverride
    case gameOverride
}

// A value that a core option can take.
struct CoreOptionValue: Identifiable, Codable, Hashable {
    var id: String { value }
    let value: String
    let label: String

    init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

struct CoreOption: Identifiable, Codable, Hashable {
    var id: String { key }
    let key: String
    let description: String
    let info: String
    var category: String?
    var version: CoreOptionVersion
    var values: [CoreOptionValue]
    let defaultValue: String
    var currentValue: String
    var overrideSource: OverrideSource
    var previousLayerValue: String

    var currentLabel: String {
        values.first { $0.value == currentValue }?.label ?? currentValue
    }

    var isModified: Bool {
        currentValue != defaultValue
    }

    var restoreValue: String {
        overrideSource == .coreDefault ? defaultValue : previousLayerValue
    }

    init(key: String, description: String, info: String = "", category: String? = nil,
         values: [CoreOptionValue], defaultValue: String, currentValue: String? = nil,
         version: CoreOptionVersion = .v2, overrideSource: OverrideSource = .coreDefault,
         previousLayerValue: String? = nil) {
        self.key = key
        self.description = description
        self.info = info
        self.category = category
        self.values = values
        self.defaultValue = defaultValue
        self.currentValue = currentValue ?? defaultValue
        self.version = version
        self.overrideSource = overrideSource
        self.previousLayerValue = previousLayerValue ?? defaultValue
    }
}

struct CoreOptionCategory: Identifiable, Codable, Hashable {
    var id: String { key }
    let key: String
    let description: String
    let info: String
    let version: CoreOptionVersion?

    init(key: String, description: String, info: String = "", version: CoreOptionVersion? = nil) {
        self.key = key
        self.description = description
        self.info = info
        self.version = version
    }
}

enum CoreOptionVersion: String, Codable, CaseIterable, Hashable {
    case v1 = "V1"
    case v2 = "V2"
}

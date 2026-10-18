import Foundation
import SwiftUI

@Observable
final class SystemDatabaseWrapper {
    static let shared = SystemDatabaseWrapper()

    var systems: [SystemInfo] {
        didSet {
            indexByID = Dictionary(systems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            saveToDisk()
        }
    }

    // O(1) lookup; mirrors `systems.first { $0.id == id }` (first wins).
    private var indexByID: [String: SystemInfo] = [:]

    var mergeGBGBC: Bool = true {
        didSet {
            AppSettings.setBool("mergeGBGBC", value: mergeGBGBC)
            SystemPreferences.shared.updateTrigger += 1
        }
    }
    var mergeMameFBA: Bool = true {
        didSet {
            AppSettings.setBool("mergeMameFBA", value: mergeMameFBA)
            SystemPreferences.shared.updateTrigger += 1
        }
    }

    var systemsForDisplay: [SystemInfo] {
        systems.filter { system in
            if system.id == "gbc" { return !mergeGBGBC }
            if system.id == "fba" { return !mergeMameFBA }
            return system.displayInUI
        }
    }

    init() {
        self.systems = SystemDatabase._loadSystems()
        self.mergeGBGBC = AppSettings.getBool("mergeGBGBC", defaultValue: true)
        self.mergeMameFBA = AppSettings.getBool("mergeMameFBA", defaultValue: true)
        self.indexByID = Dictionary(systems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func system(forID id: String) -> SystemInfo? {
        indexByID[id] ?? systems.first { $0.id == id }
    }

    func system(forExtension ext: String) -> SystemInfo? {
        let lower = ext.lowercased()
        return systems.first { $0.extensions.contains(lower) }
    }

    func allInternalIDs(forDisplayID id: String) -> [String] {
        SystemDatabase.allInternalIDs(forDisplayID: id)
    }

    func updateSystemShaderPreset(systemID: String, presetID: String) {
        #if LOG_DEBUG
        LoggerService.debug(category: "ShaderPicker", "updateSystemShaderPreset called: systemID=\(systemID), presetID=\(presetID)")
        #endif
        guard let index = systems.firstIndex(where: { $0.id == systemID }) else {
            #if LOG_DEBUG
            LoggerService.debug(category: "ShaderPicker", "System not found: \(systemID)")
            #endif
            return
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "ShaderPicker", "Found system at index: \(index)")
        #endif
        systems[index].defaultShaderPresetID = presetID
        #if LOG_DEBUG
        LoggerService.debug(category: "ShaderPicker", "Updated systems[\(index)].defaultShaderPresetID = \(presetID)")
        #endif
    }

    private func saveToDisk() {
        SystemDatabase._saveSystems(systems)
    }
}
import Foundation
import SwiftUI

@Observable
final class SystemDatabaseWrapper {
    static let shared = SystemDatabaseWrapper()

    var systems: [SystemInfo] {
        didSet {
            saveToDisk()
        }
    }

    var systemsForDisplay: [SystemInfo] {
        systems.filter { $0.displayInUI }
    }

    init() {
        self.systems = SystemDatabase._loadSystems()
    }

    func system(forID id: String) -> SystemInfo? {
        systems.first { $0.id == id }
    }

    func system(forExtension ext: String) -> SystemInfo? {
        let lower = ext.lowercased()
        return systems.first { $0.extensions.contains(lower) }
    }

    func allInternalIDs(forDisplayID id: String) -> [String] {
        SystemDatabase.allInternalIDs(forDisplayID: id)
    }

    func updateSystemShaderPreset(systemID: String, presetID: String) {
        LoggerService.debug(category: "ShaderPicker", "updateSystemShaderPreset called: systemID=\(systemID), presetID=\(presetID)")
        guard let index = systems.firstIndex(where: { $0.id == systemID }) else {
            LoggerService.debug(category: "ShaderPicker", "System not found: \(systemID)")
            return
        }
        LoggerService.debug(category: "ShaderPicker", "Found system at index: \(index)")
        systems[index].defaultShaderPresetID = presetID
        LoggerService.debug(category: "ShaderPicker", "Updated systems[\(index)].defaultShaderPresetID = \(presetID)")
    }

    private func saveToDisk() {
        SystemDatabase._saveSystems(systems)
    }
}
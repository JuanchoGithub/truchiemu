import SwiftUI
import AppKit

@MainActor
class LiveShaderEditManager: ObservableObject {
    static let shared = LiveShaderEditManager()

    private var activeGameController: StandaloneGameWindowController?
    private var activeShaderController: ShaderWindowController?
    private var activeROMSettings: ROMSettings?
    private var activeRomID: UUID?
    private weak var library: ROMLibrary?

    private init() {}

    func start(rom: ROM, coreID: String, library: ROMLibrary?, shaderUniformOverrides: [String: Float] = [:]) {
        // If the game is already running for this ROM, just open/reuse the shader picker
        if activeGameController != nil, activeRomID == rom.id {
            showShaderPicker(rom: rom)
            return
        }

        // Set up the shader preset before launching
        let presetID = rom.settings.shaderPresetID
        if !presetID.isEmpty, let preset = ShaderPreset.preset(id: presetID) {
            ShaderManager.shared.activatePresetWithOverrides(presetID: presetID, overrides: shaderUniformOverrides)
        }

        activeROMSettings = rom.settings
        activeRomID = rom.id
        self.library = library

        // Launch the game
        Task {
            await GameLauncher.shared.launchGame(
                rom: rom,
                coreID: coreID,
                library: library,
                shaderUniformOverrides: shaderUniformOverrides,
                checkMAMEDeps: true
            ) { [weak self] controller in
                guard let self = self, let controller = controller else { return }
                self.activeGameController = controller

                // Open the shader picker after the game window appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showShaderPicker(rom: rom)
                }
            }
        }
    }

    private func showShaderPicker(rom: ROM) {
        let settings = ShaderWindowSettings(
            shaderPresetID: rom.settings.shaderPresetID,
            uniformValues: extractCurrentUniformValues(from: rom.settings),
            systemID: nil
        )

        let controller = ShaderWindowController(settings: settings)
        controller.onPresetChanged = { [weak self] newPresetID, newUniformValues, _ in
            guard let self = self else { return }

            // Apply to the running game immediately via ShaderManager
            if let preset = ShaderPreset.preset(id: newPresetID) {
                ShaderManager.shared.activatePresetWithOverrides(presetID: newPresetID, overrides: newUniformValues)
            }

            // Persist to ROM settings
            var updated = rom
            updated.settings.shaderPresetID = newPresetID
            applyUniformValues(newUniformValues, to: &updated.settings)

            if let library = self.library {
                library.updateROM(updated)
            }

            self.activeShaderController = nil
        }

        ShaderWindowController.shared = controller
        activeShaderController = controller
        controller.show()
    }

    func stop() {
        activeGameController?.window?.close()
        activeGameController = nil
        activeShaderController?.window?.close()
        activeShaderController = nil
        activeRomID = nil
        activeROMSettings = nil
    }

    private func extractCurrentUniformValues(from settings: ROMSettings) -> [String: Float] {
        var values: [String: Float] = [:]
        values["scanlineIntensity"] = settings.scanlineIntensity
        values["barrelAmount"] = settings.barrelAmount
        values["colorBoost"] = settings.colorBoost
        values["crtEnabled"] = settings.crtEnabled ? 1.0 : 0.0
        values["scanlinesEnabled"] = settings.scanlinesEnabled ? 1.0 : 0.0
        values["barrelEnabled"] = settings.barrelEnabled ? 1.0 : 0.0
        values["phosphorEnabled"] = settings.phosphorEnabled ? 1.0 : 0.0
        return values
    }

    private func applyUniformValues(_ values: [String: Float], to settings: inout ROMSettings) {
        if let v = values["scanlineIntensity"] { settings.scanlineIntensity = v }
        if let v = values["barrelAmount"] { settings.barrelAmount = v }
        if let v = values["colorBoost"] { settings.colorBoost = v }
        if let v = values["crtEnabled"] { settings.crtEnabled = v != 0.0 }
        if let v = values["scanlinesEnabled"] { settings.scanlinesEnabled = v != 0.0 }
        if let v = values["barrelEnabled"] { settings.barrelEnabled = v != 0.0 }
        if let v = values["phosphorEnabled"] { settings.phosphorEnabled = v != 0.0 }
    }
}
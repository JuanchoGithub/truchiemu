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
    private var isActive: Bool = false

    private init() {}

    func start(rom: ROM, coreID: String, library: ROMLibrary?, shaderUniformOverrides: [String: Float] = [:]) {
        // If the game is already running for this ROM, just open/reuse the shader picker
        if activeGameController != nil, activeRomID == rom.id {
            showShaderPicker(rom: rom)
            return
        }

        // Set up the shader preset before launching - check built-in, saved, and slang presets
        let presetID = rom.settings.shaderPresetID
        if !presetID.isEmpty {
            if ShaderPreset.preset(id: presetID) != nil {
                ShaderManager.shared.activatePresetWithOverrides(presetID: presetID, overrides: shaderUniformOverrides)
            } else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == presetID }) {
                var merged = shaderUniformOverrides
                for (name, value) in savedPreset.uniformValues {
                    if merged[name] == nil { merged[name] = value }
                }
                // For slang-based saved presets the merge above needs to flow into the
                // slang chain; activateSavedPreset handles both Metal and slang bases,
                // but it applies only savedPreset.uniformValues. If the saved base is
                // slang, apply the per-game merge through the slang override path.
                if SlangPresetDiscoveryService.shared.presets.contains(where: { $0.path.path == savedPreset.basePresetID }),
                   let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == savedPreset.basePresetID }) {
                    ShaderManager.shared.activateSlangPreset(slangPreset, overrides: merged)
                } else {
                    ShaderManager.shared.activateSavedPreset(savedPreset)
                }
            } else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == presetID }) {
                ShaderManager.shared.activateSlangPreset(slangPreset, overrides: shaderUniformOverrides)
            }
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

                // Mark as active live edit session
                self.isActive = true

                // Disable auto-fullscreen for live shader edit sessions
                controller.autoFullscreenEnabled = false

                // Set up callback to close both windows when either closes
                controller.onWindowWillClose = { [weak self] in
                    self?.cleanup()
                }

                // Open the shader picker after the game window appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showShaderPicker(rom: rom)
                }
            }
        }
    }

    private func showShaderPicker(rom: ROM) {
        let boxArtData: Data? = {
            if let url = BoxArtService.shared.resolveLocalBoxArt(for: rom) {
                return try? Data(contentsOf: url)
            }
            return nil
        }()
        let settings = ShaderWindowSettings(
            shaderPresetID: rom.settings.shaderPresetID,
            uniformValues: extractCurrentUniformValues(from: rom.settings),
            systemID: nil,
            contextDescription: rom.displayName,
            contextImageData: boxArtData
        )

        let controller = ShaderWindowController(settings: settings)
        controller.onPresetChanged = { [weak self] newPresetID, newUniformValues, _ in
            guard let self = self else { return }

            // Apply to the running game immediately via ShaderManager
            var activatedSlang = false
            if ShaderPreset.preset(id: newPresetID) != nil {
                ShaderManager.shared.activatePresetWithOverrides(presetID: newPresetID, overrides: newUniformValues)
            } else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == newPresetID }) {
                ShaderManager.shared.activateSavedPreset(savedPreset)
                activatedSlang = ShaderManager.shared.activeSlangPreset != nil
            } else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == newPresetID }) {
                ShaderManager.shared.activateSlangPreset(slangPreset, overrides: newUniformValues)
                activatedSlang = true
            }
            if !activatedSlang {
                for (name, value) in newUniformValues {
                    ShaderManager.shared.updateUniform(name, value: value)
                }
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

        // Set up delegate to catch window close
        controller.onWindowWillClose = { [weak self] in
            self?.cleanup()
        }

        ShaderWindowController.shared = controller
        activeShaderController = controller
        controller.show()
    }

    func stop() {
        // Clear callbacks first to prevent re-entrancy when closing windows
        activeGameController?.onWindowWillClose = nil
        activeShaderController?.onWindowWillClose = nil

        activeGameController?.window?.close()
        activeGameController = nil
        activeShaderController?.window?.close()
        activeShaderController = nil
        activeRomID = nil
        activeROMSettings = nil
        isActive = false
    }

    private func cleanup() {
        guard isActive else { return }
        isActive = false  // Set flag first to prevent re-entrancy
        stop()
    }

    private func extractCurrentUniformValues(from settings: ROMSettings) -> [String: Float] {
        var values: [String: Float] = [:]
        // Merge any persisted generic overrides (incl. slang params) first.
        for (k, v) in settings.shaderUniformOverrides {
            values[k] = v
        }
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
        // Persist the full generic dict (covers slang params + arbitrary overrides)
        settings.shaderUniformOverrides = values
        if let v = values["scanlineIntensity"] { settings.scanlineIntensity = v }
        if let v = values["barrelAmount"] { settings.barrelAmount = v }
        if let v = values["colorBoost"] { settings.colorBoost = v }
        if let v = values["crtEnabled"] { settings.crtEnabled = v != 0.0 }
        if let v = values["scanlinesEnabled"] { settings.scanlinesEnabled = v != 0.0 }
        if let v = values["barrelEnabled"] { settings.barrelEnabled = v != 0.0 }
        if let v = values["phosphorEnabled"] { settings.phosphorEnabled = v != 0.0 }
    }
}
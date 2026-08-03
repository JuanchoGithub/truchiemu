import SwiftUI
import AppKit

@MainActor
class LiveShaderEditManager: ObservableObject {
    static let shared = LiveShaderEditManager()

    private var activeGameController: StandaloneGameWindowController?
    private var activeROMSettings: ROMSettings?
    private var activeRomID: UUID?
    private weak var library: ROMLibrary?
    private var isActive: Bool = false

    private init() {}

    func start(rom: ROM, coreID: String, library: ROMLibrary?, shaderUniformOverrides: [String: Float] = [:]) {
        // If the game is already running for this ROM, just reopen the sidebar
        if activeGameController != nil, activeRomID == rom.id {
            showShaderSidebar(rom: rom)
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

                // Open the shader sidebar after the game window appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showShaderSidebar(rom: rom)
                }
            }
        }
    }

    private func showShaderSidebar(rom: ROM) {
        guard let controller = activeGameController else { return }

        let settings = ShaderWindowSettings(
            shaderPresetID: rom.settings.shaderPresetID,
            uniformValues: extractCurrentUniformValues(from: rom.settings),
            systemID: nil,
            contextDescription: rom.displayName,
            contextImageData: boxArtData(for: rom)
        )

        // Apply + persist to the ROM without closing the sidebar (live editing).
        controller.showShaderEditor(
            settings: settings,
            onApply: { [weak self] newPresetID, newUniformValues in
                guard let self = self else { return }
                self.applyToRunningGame(presetID: newPresetID, uniformValues: newUniformValues)

                var updated = rom
                updated.settings.shaderPresetID = newPresetID
                self.applyUniformValues(newUniformValues, to: &updated.settings)

                if let library = self.library {
                    library.updateROM(updated)
                }
            },
            onDiscard: { [weak self] in
                self?.cleanup()
            },
            onApplyAndClose: { [weak self] in
                guard let self = self else { return }
                let settings = self.activeGameController?.shaderEditorSettings
                let presetID = settings?.shaderPresetID ?? rom.settings.shaderPresetID
                let uniforms = settings?.uniformValues ?? [:]

                var updated = rom
                updated.settings.shaderPresetID = presetID
                self.applyUniformValues(uniforms, to: &updated.settings)

                if let library = self.library {
                    library.updateROM(updated)
                }
                self.cleanup()
            }
        )
    }

    private func applyToRunningGame(presetID: String, uniformValues: [String: Float]) {
        var activatedSlang = false
        if ShaderPreset.preset(id: presetID) != nil {
            ShaderManager.shared.activatePresetWithOverrides(presetID: presetID, overrides: uniformValues)
        } else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == presetID }) {
            ShaderManager.shared.activateSavedPreset(savedPreset)
            activatedSlang = ShaderManager.shared.activeSlangPreset != nil
        } else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == presetID }) {
            ShaderManager.shared.activateSlangPreset(slangPreset, overrides: uniformValues)
            activatedSlang = true
        }
        if !activatedSlang {
            for (name, value) in uniformValues {
                ShaderManager.shared.updateUniform(name, value: value)
            }
        }
    }

    private func cleanup() {
        guard isActive else { return }
        isActive = false  // Set flag first to prevent re-entrancy
        stop()
    }

    func stop() {
        // Clear callbacks first to prevent re-entrancy when closing windows
        activeGameController?.onWindowWillClose = nil
        activeGameController?.dismissShaderEditor()

        activeGameController?.window?.close()
        activeGameController = nil
        activeRomID = nil
        activeROMSettings = nil
        isActive = false
    }

    private func boxArtData(for rom: ROM) -> Data? {
        guard let url = BoxArtService.shared.resolveLocalBoxArt(for: rom) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func extractCurrentUniformValues(from settings: ROMSettings) -> [String: Float] {        var values: [String: Float] = [:]
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
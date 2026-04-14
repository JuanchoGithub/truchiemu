import SwiftUI

// MARK: - Display Settings
struct DisplaySettingsView: View {
    @State private var selectedPresetID: String = "builtin-crt-classic"
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @StateObject private var shaderManager = ShaderManager.shared
    
    var body: some View {
        Form {
            Section("Shader Presets") {
                LabeledContent("Default Shader") {
                    Button(ShaderManager.displayName(for: selectedPresetID)) {
                        presentShaderWindow()
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("Select a default shader preset for all games. Individual games can override this in their settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Quick Preview") {
                VStack(spacing: 8) {
                    ForEach(ShaderPreset.allPresets.prefix(4), id: \.id) { preset in
                        HStack {
                            Image(systemName: shaderIcon(for: preset.shaderType))
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                    .font(.subheadline)
                                Text(preset.description ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if preset.recommendedSystems.isEmpty {
                                Text("All systems")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(preset.recommendedSystems.prefix(3).joined(separator: ", ").uppercased())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Bezel") {
                Text("Bezel options are available in the in-game HUD (shown on hover).")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
        .onAppear {
            selectedPresetID = AppSettings.get("display_default_shader_preset", type: String.self) ?? "builtin-crt-classic"
        }
    }
    
    @MainActor
    private func presentShaderWindow() {
        if shaderWindowSettings == nil {
            shaderWindowSettings = ShaderWindowSettings(
                shaderPresetID: selectedPresetID,
                uniformValues: extractUniformValuesFromSettings()
            )
        } else {
            shaderWindowSettings?.shaderPresetID = selectedPresetID
        }
        
        let windowController = ShaderWindowController(
            settings: shaderWindowSettings!
        ) { [self] newPresetID, newUniformValues in
            selectedPresetID = newPresetID
            if let preset = ShaderPreset.preset(id: newPresetID) {
                shaderManager.activatePreset(preset)
            }
            // Update shader manager uniform values
            for (key, value) in newUniformValues {
                shaderManager.updateUniform(key, value: value)
            }
        }
        
        ShaderWindowController.shared = windowController
        windowController.show()
    }
    
    private func extractUniformValuesFromSettings() -> [String: Float] {
        var values: [String: Float] = [:]
        values["scanlineIntensity"] = 0.35 // default
        values["barrelAmount"] = 0.12 // default
        values["colorBoost"] = 1.0 // default
        return values
    }
    
    private func shaderIcon(for type: ShaderType) -> String {
        switch type {
        case .crt: return "tv"
        case .lcd: return "iphone"
        case .smoothing: return "sparkles"
        case .composite: return "waveform.path"
        case .custom: return "wrench"
        }
    }
}

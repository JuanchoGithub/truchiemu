import SwiftUI

// MARK: - Display Settings
struct DisplaySettingsView: View {
    @State private var selectedPresetID: String = ""
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @StateObject private var shaderManager = ShaderManager.shared
    
    @Binding var searchText: String
    
    static let searchKeywords: String = "display screen shader preset bezel crt lcd"
    
    init(searchText: Binding<String> = .constant("")) {
        self._searchText = searchText
    }
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    private func matchesSearch(_ keywords: String) -> Bool {
        if searchText.isEmpty { return true }
        return keywords.localizedLowercase.fuzzyMatch(searchText) || 
               keywords.localizedLowercase.contains(searchText.lowercased())
    }
    
    var body: some View {
        Form {
            // Shader Presets Section
            if !isSearching || matchesSearch("Shader Presets display screen shader preset default") {
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
            }
            
            // Quick Preview Section
            if !isSearching || matchesSearch("Quick Preview shader preset display screen") {
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
            }
            
            // Bezel Section
            if !isSearching || matchesSearch("Bezel display screen bezel frame") {
                Section("Bezel") {
                    Text("Bezel options are available in the in-game HUD (shown on hover).")
                        .foregroundColor(.secondary)
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("No matching settings found for \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Display")
        .onAppear {
            selectedPresetID = AppSettings.get("display_default_shader_preset", type: String.self) ?? ""
        }
    }
    
    private var hasMatchingSections: Bool {
        matchesSearch("Shader Presets display screen shader preset default") ||
        matchesSearch("Quick Preview shader preset display screen") ||
        matchesSearch("Bezel display screen bezel frame")
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
        ) { [self] newPresetID, newUniformValues, _ in
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

import SwiftUI

// MARK: - Display Settings
struct DisplaySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPresetID: String = ""
    @State private var shaderWindowSettings: ShaderWindowSettings?
    @StateObject private var shaderManager = ShaderManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
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
                Section(header: Label(loc.localized("display.shaderPresets"), systemImage: "wand.and.rays")) {
                    LabeledContent(loc.localized("display.defaultShader")) {
                        Button(ShaderManager.displayName(for: selectedPresetID)) {
                            presentShaderWindow()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text(loc.localized("display.defaultShaderDescription"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            }
            
            // Quick Preview Section
            if !isSearching || matchesSearch("Quick Preview shader preset display screen") {
                Section(header: Label(loc.localized("display.quickPreview"), systemImage: "eye")) {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(ShaderPreset.allPresets.prefix(4), id: \.id) { preset in
                            HStack {
                                Image(systemName: shaderIcon(for: preset.shaderType))
                                    .foregroundStyle(AppColors.brandAccent)
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                        .font(.subheadline)
                                    Text(preset.description ?? "")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                }
                                Spacer()
                                if preset.recommendedSystems.isEmpty {
                                    Text(loc.localized("display.allSystems"))
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                } else {
                                    Text(preset.recommendedSystems.prefix(3).joined(separator: ", ").uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                                }
                            }
                            .padding(.vertical, AppSpacing.xs)
                        }
                    }
                }
            }
            
            // Bezel Section
            if !isSearching || matchesSearch("Bezel display screen bezel frame") {
                Section(header: Label(loc.localized("display.bezel"), systemImage: "rectangle.on.rectangle")) {
                    Text(loc.localized("display.bezelDescription"))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            }
            
            // No results message
            if isSearching && !hasMatchingSections {
                Section {
                    Text("\(loc.localized("display.noMatchingSettings")) \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppSpacing.xl)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(loc.localized("display.title"))
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
            LoggerService.info(category: "ShaderPicker", "Callback received: presetID=\(newPresetID), uniformValues=\(newUniformValues)")
            
            // Only update uniforms - DON'T call activatePreset here as it resets everything
            // The preset will be activated when the game launches via GameLauncher
            for (key, value) in newUniformValues {
                LoggerService.info(category: "ShaderPicker", "Updating uniform: \(key)=\(value)")
                shaderManager.updateUniform(key, value: value)
            }
        }
        
        ShaderWindowController.shared = windowController
        windowController.show()
    }
    
    private func extractUniformValuesFromSettings() -> [String: Float] {
        // Get actual current uniform values from ShaderManager
        return ShaderManager.shared.uniformValues
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

import SwiftUI

struct ShaderSection: View {
    let rom: ROM
    let library: ROMLibrary
    @Binding var shaderWindowSettings: ShaderWindowSettings?
    @Environment(\.colorScheme) private var colorScheme

    private var shaderManager: ShaderManager { ShaderManager.shared }

    private var isShaderCustomized: Bool {
        rom.settings.shaderPresetID != systemDefaultShaderID
    }

    private var systemDefaultShaderID: String { "" }

    var body: some View {
        ModernSectionCard(
            title: "Shader",
            icon: "tv",
            badge: isShaderCustomized ? "Custom" : nil
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Shader")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(ShaderManager.displayName(for: rom.settings.shaderPresetID))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }

                    Spacer()

                    Button("Customize") {
                        presentShaderWindow()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.8))
                    .cornerRadius(8)
                }

                Divider().overlay(AppColors.divider(colorScheme))

                VStack(spacing: 6) {
                    let recommended = shaderManager.recommendedPresets(for: rom.systemID ?? "")
                    let presetsToShow = recommended.isEmpty
                        ? Array(ShaderPreset.allPresets.prefix(4))
                        : recommended

                    ForEach(presetsToShow.prefix(4), id: \.id) { preset in
                        Button {
                            updateSettings { $0.shaderPresetID = preset.id }
                        } label: {
                            HStack {
                                Image(systemName: shaderIcon(for: preset.shaderType))
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Text(preset.name)
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                Spacer()
                                if rom.settings.shaderPresetID == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                                if let desc = preset.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(AppColors.textMuted(colorScheme))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                rom.settings.shaderPresetID == preset.id
                                    ? Color.blue.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(AppColors.divider(colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Default")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Text("Reset to default shader for this system")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted(colorScheme))
                    }
                    Spacer()
                    Button("Use Default") {
                        updateSettings { $0.shaderPresetID = systemDefaultShaderID }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.cardBackground(colorScheme))
                    .cornerRadius(6)
                    .disabled(!isShaderCustomized)
                }
            }
        }
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

    @MainActor
    private func presentShaderWindow() {
        let settings = ShaderWindowSettings(
            shaderPresetID: rom.settings.shaderPresetID,
            uniformValues: extractUniformValues(from: rom.settings)
        )

        let windowController = ShaderWindowController(
            settings: settings
        ) { newPresetID, newUniformValues, _ in
            updateSettings { romSettings in
                romSettings.shaderPresetID = newPresetID
                applyUniformValues(newUniformValues, to: &romSettings)
            }
            if let preset = ShaderPreset.preset(id: newPresetID) {
                ShaderManager.shared.activatePreset(preset)
            }
        }

        ShaderWindowController.shared = windowController
        windowController.show()
    }

    private func extractUniformValues(from settings: ROMSettings) -> [String: Float] {
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

    private func updateSettings(_ action: (inout ROMSettings) -> Void) {
        var updated = rom
        action(&updated.settings)
        library.updateROM(updated)
    }
}
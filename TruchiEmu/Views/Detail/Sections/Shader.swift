import SwiftUI

extension GameDetailView {
    var shaderSection: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.shader"),
            icon: "display",
            badge: isShaderCustomized ? loc.localized("shader.custom") : nil
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // MARK: - Current shader stat
                HStack(spacing: AppSpacing.md) {
                    let currentPresetID = ShaderManager.effectivePresetID(for: currentROM)
                    let currentPresetType = ShaderPreset.preset(id: currentPresetID)?.shaderType ?? .custom
                    DetailStatBadge(
                        icon: shaderIcon(for: currentPresetType),
                        value: ShaderManager.displayName(for: currentPresetID),
                        unit: loc.localized("gameDetail.shader"),
                        tint: isShaderCustomized ? AppColors.warning(colorScheme) : AppColors.brandAccent
                    )
                    Spacer(minLength: 0)
                    SettingsActionButton(loc.localized("shader.customize"), prominent: true) { presentShaderWindow() }
                    SettingsActionButton(loc.localized("shader.liveShaderEdit")) { presentLiveShaderEdit() }
                }

                Divider().overlay(AppColors.divider(colorScheme))

                // MARK: - Preset gallery
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.sm) {
                            let recommended = shaderManager.recommendedPresets(for: currentROM.systemID ?? "")
                            let presetsToShow = recommended.isEmpty ? Array(ShaderPreset.allPresets.prefix(6)) : recommended
                            ForEach(presetsToShow, id: \.id) { preset in
                                ShaderPresetChip(
                                    preset: preset,
                                    icon: shaderIcon(for: preset.shaderType),
                                    isSelected: currentROM.settings.shaderPresetID == preset.id
                                ) {
                                    updateSettings { $0.shaderPresetID = preset.id }
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                Divider().overlay(AppColors.divider(colorScheme))

                // MARK: - System default
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("shader.systemDefault"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                        Text(loc.localized("shader.resetToDefault"))
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer()
                    SettingsActionButton(loc.localized("shader.useDefault")) {
                        updateSettings { $0.resetShaderSettings() }
                    }
                    .disabled(!isShaderCustomized)
                }
            }
        }
    }

    private struct ShaderPresetChip: View {
        let preset: ShaderPreset
        let icon: String
        let isSelected: Bool
        let action: () -> Void

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? AppColors.textOnAccent(colorScheme) : AppColors.brandAccent)
                            .frame(width: 16, height: 16)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColors.textOnAccent(colorScheme))
                        }
                    }

                    Text(preset.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppColors.textOnAccent(colorScheme) : AppColors.textPrimary(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if !preset.localizedDescription.isEmpty {
                        Text(preset.localizedDescription)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? AppColors.textOnAccent(colorScheme).opacity(0.8) : AppColors.textTertiary(colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(AppSpacing.sm)
                .frame(width: 150, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(isSelected ? AppColors.brandAccent : AppColors.cardBackgroundSubtle(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppColors.brandAccent : AppColors.cardBorder(colorScheme),
                            lineWidth: 1
                        )
                )
                .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1.0)
                .animation(AppMotion.micro, value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    func shaderIcon(for type: ShaderType) -> String {
        switch type {
        case .crt: return "tv"
        case .lcd: return "iphone"
        case .smoothing: return "sparkles"
        case .composite: return "waveform.path"
        case .text: return "textformat"
        case .custom: return "wrench"
        }
    }

    @MainActor
    func presentShaderWindow() {
        let systemName = SystemDatabase.system(forID: currentROM.systemID ?? "")?.name ?? ""
        let context = systemName.isEmpty ? currentROM.displayName : "\(systemName) / \(currentROM.displayName)"

        let boxArtData: Data? = {
            if let url = BoxArtService.shared.resolveLocalBoxArt(for: currentROM) {
                return try? Data(contentsOf: url)
            }
            return nil
        }()

        if shaderWindowSettings == nil {
            shaderWindowSettings = ShaderWindowSettings(
                shaderPresetID: ShaderManager.effectivePresetID(for: currentROM),
                uniformValues: extractUniformValues(from: currentROM.settings),
                systemID: nil,  // Don't pass systemID to hide Application Mode picker in Game Info
                contextDescription: context,
                contextImageData: boxArtData
            )
        } else {
            shaderWindowSettings?.shaderPresetID = ShaderManager.effectivePresetID(for: currentROM)
            shaderWindowSettings?.systemID = nil
        }

let windowController = ShaderWindowController(
settings: shaderWindowSettings!
)
windowController.onPresetChanged = { [self] newPresetID, newUniformValues, selectedGameIDs in
#if LOG_DEBUG
LoggerService.debug(category: "ShaderPicker", "=== APPLY BUTTON PRESSED ===")
#endif
#if LOG_DEBUG
LoggerService.debug(category: "ShaderPicker", "Received: presetID=\(newPresetID), uniformCount=\(newUniformValues.count)")
#endif
#if LOG_DEBUG
LoggerService.debug(category: "ShaderPicker", "Settings context: systemID=\(String(describing: shaderWindowSettings?.systemID)), initialPresetID=\(shaderWindowSettings?.shaderPresetID ?? "nil")")
#endif

// Activate the shader if a game is currently running with this runner
var activatedSlang = false
var slangFailureName: String?
if let preset = ShaderPreset.preset(id: newPresetID) {
    ShaderManager.shared.activatePreset(preset)
} else if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == newPresetID }) {
    if !ShaderManager.shared.activateSavedPreset(savedPreset) {
        slangFailureName = savedPreset.name
    }
    activatedSlang = ShaderManager.shared.activeSlangPreset != nil
} else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == newPresetID }) {
    if !ShaderManager.shared.activateSlangPreset(slangPreset, overrides: newUniformValues) {
        slangFailureName = slangPreset.name
    }
    activatedSlang = ShaderManager.shared.activeSlangPreset != nil
}

if let slangFailureName = slangFailureName {
    // Compile failed: the previously active shader keeps running. Keep
    // the window open so the message stays visible, and do not persist
    // the failed selection.
    shaderWindowSettings?.notificationMessage = String(
        format: LocalizationManager.shared.localized("shader.compileFailed"),
        slangFailureName
    )
    return
}

// Confirmed-persisted uniform overrides for a slang preset were applied during
// activation above; only route remaining (Metal) uniforms through the in-house store.
if !activatedSlang {
    for (name, value) in newUniformValues {
        ShaderManager.shared.updateUniform(name, value: value)
    }
}

updateSettings { romSettings in
    romSettings.shaderPresetID = newPresetID
    romSettings.shaderUniformOverrides = newUniformValues
    applyUniformValues(newUniformValues, to: &romSettings)
}
ShaderWindowController.shared?.close()
}
        ShaderWindowController.shared = windowController
        windowController.show()
    }

    @MainActor
    func presentLiveShaderEdit() {
        guard let sysID = currentROM.systemID, let system = SystemDatabase.system(forID: sysID) else { return }
        let cid = activeCoreID ?? system.defaultCoreID ?? ""

        LiveShaderEditManager.shared.start(
            rom: currentROM,
            coreID: cid,
            library: library,
            shaderUniformOverrides: currentROM.settings.shaderUniformOverrides
        )
    }

    func extractUniformValues(from settings: ROMSettings) -> [String: Float] {
        var values: [String: Float] = [:]
        // Merge any persisted general overrides (incl. slang params) first.
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

    func applyUniformValues(_ values: [String: Float], to settings: inout ROMSettings) {
        if let v = values["scanlineIntensity"] { settings.scanlineIntensity = v }
        if let v = values["barrelAmount"] { settings.barrelAmount = v }
        if let v = values["colorBoost"] { settings.colorBoost = v }
        if let v = values["crtEnabled"] { settings.crtEnabled = v != 0.0 }
        if let v = values["scanlinesEnabled"] { settings.scanlinesEnabled = v != 0.0 }
        if let v = values["barrelEnabled"] { settings.barrelEnabled = v != 0.0 }
        if let v = values["phosphorEnabled"] { settings.phosphorEnabled = v != 0.0 }
    }
}

import SwiftUI
import SwiftData

extension GameDetailView {
    var shaderSection: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.shader"),
            icon: "tv",
            badge: isShaderCustomized ? loc.localized("shader.custom") : nil
        ) {
VStack(alignment: .leading, spacing: 0) {
HStack {
VStack(alignment: .leading, spacing: 2) {
Text(loc.localized("shader.currentShader"))
.font(.subheadline)
.fontWeight(.medium)
.foregroundColor(AppColors.textPrimary(colorScheme))
Text(ShaderManager.displayName(for: currentROM.settings.shaderPresetID))
.font(.caption)
.foregroundColor(AppColors.textSecondary(colorScheme))
}
Spacer()
        Button { presentShaderWindow() } label: {
Text(loc.localized("shader.customize"))
        .font(.subheadline)
        .foregroundColor(AppColors.textOnAccent(colorScheme))
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.brandAccent)
                .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)

        Button { presentLiveShaderEdit() } label: {
            Text(loc.localized("shader.liveShaderEdit"))
                .font(.subheadline)
                .foregroundColor(AppColors.brandAccent)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.brandAccent.opacity(0.15))
                .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
}
.padding(.vertical, AppSpacing.xs)

                Divider().overlay(AppColors.divider(colorScheme))

                VStack(spacing: 6) {
                    let recommended = shaderManager.recommendedPresets(for: currentROM.systemID ?? "")
                    let presetsToShow = recommended.isEmpty ? Array(ShaderPreset.allPresets.prefix(4)) : recommended
                    ForEach(presetsToShow.prefix(4), id: \.id) { preset in
                        Button { updateSettings { $0.shaderPresetID = preset.id } } label: {
                            HStack {
                                Image(systemName: shaderIcon(for: preset.shaderType))
                                    .foregroundColor(AppColors.brandAccent).frame(width: 20)
                                Text(preset.name).font(.subheadline).foregroundColor(AppColors.textPrimary(colorScheme))
                                Spacer()
                                if currentROM.settings.shaderPresetID == preset.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(AppColors.brandAccent)
                                }
                                if !preset.localizedDescription.isEmpty {
                                    Text(preset.localizedDescription).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineLimit(1)
                                }
                            }
.padding(.vertical, AppSpacing.xs)
.padding(.horizontal, AppSpacing.lg)
.background(currentROM.settings.shaderPresetID == preset.id ? AppColors.brandAccent.opacity(0.5) : Color.clear)
.cornerRadius(AppRadius.sm)
                        }
                        .buttonStyle(.plain)
}
}
.padding(.vertical, AppSpacing.xs)

Divider().overlay(AppColors.divider(colorScheme))

HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("shader.systemDefault")).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("shader.resetToDefault")).font(.caption).foregroundColor(AppColors.textTertiary(colorScheme))
                    }
                    Spacer()
        Button { updateSettings { $0.shaderPresetID = systemDefaultShaderID } } label: {
            Text(loc.localized("shader.useDefault"))
                .font(.caption)
                .foregroundColor(AppColors.brandAccent)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.brandAccent.opacity(0.15))
                .cornerRadius(AppRadius.sm)
        }
        .buttonStyle(.plain)
        .disabled(!isShaderCustomized)
}
.padding(.vertical, AppSpacing.xs)
            }
        }
    }

    func shaderIcon(for type: ShaderType) -> String {
        switch type {
        case .crt: return "tv"
        case .lcd: return "iphone"
        case .smoothing: return "sparkles"
        case .composite: return "waveform.path"
        case .custom: return "wrench"
        }
    }

    @MainActor
    func presentShaderWindow() {
        if shaderWindowSettings == nil {
            shaderWindowSettings = ShaderWindowSettings(
                shaderPresetID: currentROM.settings.shaderPresetID,
                uniformValues: extractUniformValues(from: currentROM.settings),
                systemID: nil  // Don't pass systemID to hide Application Mode picker in Game Info
            )
        } else {
            shaderWindowSettings?.shaderPresetID = currentROM.settings.shaderPresetID
            shaderWindowSettings?.systemID = nil
        }

let windowController = ShaderWindowController(
settings: shaderWindowSettings!
)
windowController.onPresetChanged = { [self] newPresetID, newUniformValues, selectedGameIDs in
LoggerService.debug(category: "ShaderPicker", "=== APPLY BUTTON PRESSED ===")
LoggerService.debug(category: "ShaderPicker", "Received: presetID=\(newPresetID), uniformCount=\(newUniformValues.count)")
LoggerService.debug(category: "ShaderPicker", "Settings context: systemID=\(String(describing: shaderWindowSettings?.systemID)), initialPresetID=\(shaderWindowSettings?.shaderPresetID ?? "nil")")

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

    private func applyToAllGamesInSystem(systemID: String, presetID: String, uniforms: [String: Float]) {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let modelContext = SwiftDataContainer.shared.container.mainContext
        
        let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.systemID == systemID })
        guard let entries = try? modelContext.fetch(descriptor) else { 
            LoggerService.error(category: "ShaderPicker", "Failed to fetch ROM entries for systemID: \(systemID)")
            return 
        }
        
        LoggerService.debug(category: "ShaderPicker", "applyToAllGamesInSystem: systemID=\(systemID), entries found=\(entries.count)")
        
        for entry in entries {
            var settings: ROMSettings
            if let json = entry.settingsJSON, let data = json.data(using: .utf8),
               let decoded = try? decoder.decode(ROMSettings.self, from: data) {
                settings = decoded
            } else {
                settings = ROMSettings()
            }
            
            // Override even custom settings
            settings.shaderPresetID = presetID
            applyUniformValues(uniforms, to: &settings)
            
            if let encoded = try? encoder.encode(settings),
               let json = String(data: encoded, encoding: .utf8) {
                entry.settingsJSON = json
                
                // Also update in-memory library for each ROM
                if let rom = library.roms.first(where: { $0.id == entry.id }) {
                    var updatedROM = rom
                    updatedROM.settings.shaderPresetID = presetID
                    applyUniformValues(uniforms, to: &updatedROM.settings)
                    library.updateROM(updatedROM, persist: false, silent: true)
                }
            }
        }
        
        do {
            try modelContext.save()
            LibraryMetadataStore.shared.flushDirtyToSwiftData()
            LoggerService.debug(category: "ShaderPicker", "Saved \(entries.count) entries with shader: \(presetID)")
        } catch {
            LoggerService.error(category: "ShaderPicker", "Failed to save: \(error.localizedDescription)")
        }
    }

    func extractUniformValues(from settings: ROMSettings) -> [String: Float] {
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
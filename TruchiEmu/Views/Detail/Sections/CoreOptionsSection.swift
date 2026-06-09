import SwiftUI

extension GameDetailView {
    var coreOptionsSection: some View {
        gbColorizationSection
    }

    var gbColorizationSection: some View {
        ModernSectionCard(title: loc.localized("gameInfo.gameBoyColorization"), icon: "paintpalette") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "paintpalette.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("gameInfo.enableColorization"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { gbColorizationEnabled },
                        set: { newValue in
                            gbColorizationEnabled = newValue
                            applyGBColorizationSettings()
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                }
                .padding(.vertical, AppSpacing.xs)

                if gbColorizationEnabled {
                    Divider().overlay(AppColors.divider(colorScheme))
                    gbPaletteModeRow

                    if gbColorizationMode == "internal" {
                        Divider().overlay(AppColors.divider(colorScheme))
                        if isGambatteCore {
                            gbInternalPaletteRow
                        } else {
                            gbInternalPaletteRow.opacity(0.4).disabled(true)
                                .help(loc.localized("gameInfo.gambatteCoreOnly"))
                        }
                    }

                    Divider().overlay(AppColors.divider(colorScheme))
                    gbSGBBordersRow

                    Divider().overlay(AppColors.divider(colorScheme))
                    if isGambatteCore {
                        gbColorCorrectionRow
                    } else {
                        gbColorCorrectionRow.opacity(0.4).disabled(true)
                            .help(loc.localized("gameInfo.gambatteCoreOnlyColorCorrection"))
                    }

                    Divider().overlay(AppColors.divider(colorScheme))
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "info.circle").foregroundColor(AppColors.textMuted(colorScheme)).font(.caption)
                        Text(loc.localized("gameInfo.applyColorPalettes"))
                            .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                    }
                    .padding(.vertical, AppSpacing.xs)
                } else {
                    Divider().overlay(AppColors.divider(colorScheme))
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "info.circle").foregroundColor(AppColors.textMuted(colorScheme)).font(.caption)
                        Text(loc.localized("gameInfo.gamesDisplayMonochrome"))
                            .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    var gbPaletteModeRow: some View {
        HStack {
            Image(systemName: "eyedropper").foregroundColor(AppColors.brandAccent).frame(width: 20)
            Text(loc.localized("gameInfo.paletteMode"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary(colorScheme))
            Spacer()
            Picker(loc.localized("gameInfo.paletteMode"), selection: Binding(
                get: { gbColorizationMode },
                set: { newValue in
                    gbColorizationMode = newValue
                    applyGBColorizationSettings()
                }
            )) {
                Text(loc.localized("gameInfo.autoSelect")).tag("auto")
                Text(loc.localized("gameInfo.gameBoyColor")).tag("gbc")
                Text(loc.localized("gameInfo.superGameBoy")).tag("sgb")
                Text(loc.localized("gameInfo.internalPalette")).tag("internal")
                Text(loc.localized("gameInfo.customPalettes")).tag("custom")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    var gbInternalPaletteRow: some View {
        HStack {
            Image(systemName: "paintpalette").foregroundColor(AppColors.brandAccent).frame(width: 20)
            Text(loc.localized("gameInfo.internalPalette"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary(colorScheme))
            Spacer()
            Picker(loc.localized("gameInfo.internalPalette"), selection: Binding(
                get: { gbInternalPalette },
                set: { newValue in
                    gbInternalPalette = newValue
                    applyGBColorizationSettings()
                }
            )) {
                Section(header: Text(loc.localized("gameInfo.gameBoy"))) {
                    Text("GB - DMG (Green)").tag("GB - DMG")
                    Text("GB - Pocket").tag("GB - Pocket")
                    Text("GB - Light").tag("GB - Light")
                }
                Section(header: Text(loc.localized("gameInfo.gameBoyColor"))) {
                    Text("GBC - Blue").tag("GBC - Blue")
                    Text("GBC - Brown").tag("GBC - Brown")
                    Text("GBC - Dark Blue").tag("GBC - Dark Blue")
                    Text("GBC - Dark Brown").tag("GBC - Dark Brown")
                    Text("GBC - Dark Green").tag("GBC - Dark Green")
                    Text("GBC - Grayscale").tag("GBC - Grayscale")
                    Text("GBC - Green").tag("GBC - Green")
                    Text("GBC - Inverted").tag("GBC - Inverted")
                    Text("GBC - Orange").tag("GBC - Orange")
                    Text("GBC - Pastel Mix").tag("GBC - Pastel Mix")
                    Text("GBC - Red").tag("GBC - Red")
                    Text("GBC - Yellow").tag("GBC - Yellow")
                }
                Section(header: Text(loc.localized("gameInfo.superGameBoy"))) {
                    Text("SGB - 1A").tag("SGB - 1A")
                    Text("SGB - 1B").tag("SGB - 1B")
                    Text("SGB - 2A").tag("SGB - 2A")
                    Text("SGB - 2B").tag("SGB - 2B")
                    Text("SGB - 3A").tag("SGB - 3A")
                    Text("SGB - 3B").tag("SGB - 3B")
                    Text("SGB - 4A").tag("SGB - 4A")
                    Text("SGB - 4B").tag("SGB - 4B")
                }
                Section(header: Text(loc.localized("gameInfo.special"))) {
                    Text("Special 1").tag("Special 1")
                    Text("Special 2").tag("Special 2")
                    Text("Special 3").tag("Special 3")
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    var gbSGBBordersRow: some View {
        HStack {
            Image(systemName: "rectangle.on.rectangle").foregroundColor(AppColors.brandAccent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.localized("gameInfo.superGameBoyBorders"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Text(loc.localized("gameInfo.showSGBBorders"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
            Spacer()
            if isGambatteCore {
                Text(loc.localized("gameInfo.mgbaCore"))
                    .font(.caption2)
                    .foregroundColor(AppColors.textMuted(colorScheme))
            }
            Toggle("", isOn: Binding(
                get: { gbSGBBordersEnabled },
                set: { newValue in
                    gbSGBBordersEnabled = newValue
                    applyGBColorizationSettings()
                }
            ))
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    var gbColorCorrectionRow: some View {
        HStack {
            Image(systemName: "sun.max").foregroundColor(AppColors.brandAccent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.localized("gameInfo.colorCorrection"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Text(loc.localized("gameInfo.matchOutputColors"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
            Spacer()
            Picker(loc.localized("gameInfo.colorCorrection"), selection: Binding(
                get: { gbColorCorrectionMode },
                set: { newValue in
                    gbColorCorrectionMode = newValue
                    applyGBColorizationSettings()
                }
            )) {
                Text(loc.localized("gameInfo.gbcGamesOnly")).tag("gbc_only")
                Text(loc.localized("gameInfo.always")).tag("always")
                Text(loc.localized("gameInfo.disabled")).tag("disabled")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    func loadGBColorizationSettings() {
        guard let sysID = currentROM.systemID,
        (sysID == "gb" || sysID == "gbc"),
        let coreID = activeCoreID else { return }
        let gameFilename = currentROM.filenameWithoutExtension
        let coreBaseID = coreID.replacingOccurrences(of: "_libretro", with: "")
        let ext = currentROM.path.pathExtension.lowercased()
        if coreBaseID.contains("gambatte") {
            let colorization = CoreOptionsManager.shared.resolveEffectiveValue(for: "gambatte_gb_colorization", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if colorization.value.isEmpty {
                if ext == "gbc" { gbColorizationEnabled = true; gbColorizationMode = "gbc" }
                else { gbColorizationEnabled = false }
            } else if colorization.value == "disabled" {
                gbColorizationEnabled = false
            } else {
                gbColorizationEnabled = true
                gbColorizationMode = colorization.value
            }
            let palette = CoreOptionsManager.shared.resolveEffectiveValue(for: "gambatte_gb_internal_palette", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if !palette.value.isEmpty {
                gbInternalPalette = palette.value
            }
            let correction = CoreOptionsManager.shared.resolveEffectiveValue(for: "gambatte_gbc_color_correction", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if !correction.value.isEmpty {
                switch correction.value {
                case "GBC only": gbColorCorrectionMode = "gbc_only"
                case "always": gbColorCorrectionMode = "always"
                default: gbColorCorrectionMode = "disabled"
                }
            }
        } else if coreBaseID.contains("mgba") {
            let model = CoreOptionsManager.shared.resolveEffectiveValue(for: "mgba_gb_model", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if model.value.isEmpty {
                if ext == "gbc" { gbColorizationEnabled = true; gbColorizationMode = "gbc" }
                else { gbColorizationEnabled = false }
            } else {
                switch model.value {
                case "Game Boy": gbColorizationEnabled = false
                case "Autodetect": gbColorizationEnabled = true; gbColorizationMode = "auto"
                case "Game Boy Color": gbColorizationEnabled = true; gbColorizationMode = "gbc"
                case "Super Game Boy": gbColorizationEnabled = true; gbColorizationMode = "sgb"
                default: break
                }
            }
            let borders = CoreOptionsManager.shared.resolveEffectiveValue(for: "mgba_sgb_borders", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if !borders.value.isEmpty {
                gbSGBBordersEnabled = (borders.value == "ON")
            }
        } else if coreBaseID.contains("sameboy") {
            let model = CoreOptionsManager.shared.resolveEffectiveValue(for: "sameboy_model", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if model.value.isEmpty {
                if ext == "gbc" { gbColorizationEnabled = true; gbColorizationMode = "gbc" }
                else { gbColorizationEnabled = false }
            } else {
                switch model.value {
                case "Game Boy": gbColorizationEnabled = false
                case "Auto": gbColorizationEnabled = true; gbColorizationMode = "auto"
                case "Game Boy Color": gbColorizationEnabled = true; gbColorizationMode = "gbc"
                default: break
                }
            }
            let correction = CoreOptionsManager.shared.resolveEffectiveValue(for: "sameboy_color_correction_mode", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
            if !correction.value.isEmpty {
                switch correction.value {
                case "off": gbColorCorrectionMode = "disabled"
                default: gbColorCorrectionMode = "gbc_only"
                }
            }
        } else if coreBaseID.contains("gearboy") {
            let colorization = CoreOptionsManager.shared.resolveEffectiveValue(for: "gearboy_colorization", coreID: coreID, systemID: sysID, gameFilename: gameFilename)
        if colorization.value.isEmpty {
            if ext == "gbc" { gbColorizationEnabled = true; gbColorizationMode = "gbc" }
            else { gbColorizationEnabled = false }
        } else {
            gbColorizationEnabled = (colorization.value == "enabled")
        }
    }
    }

    func applyGBColorizationSettings() {
        guard let sysID = currentROM.systemID,
              (sysID == "gb" || sysID == "gbc"),
              let coreID = activeCoreID else { return }
        let gameFilename = currentROM.filenameWithoutExtension
        var overrides = CoreOptionsManager.shared.loadGameOverrides(for: coreID, systemID: sysID, gameFilename: gameFilename)
        let coreBaseID = coreID.replacingOccurrences(of: "_libretro", with: "")
        if coreBaseID.contains("gambatte") {
            overrides["gambatte_gb_colorization"] = gbColorizationEnabled ? gbColorizationMode : "disabled"
            overrides["gambatte_gb_internal_palette"] = gbInternalPalette
            switch gbColorCorrectionMode {
            case "gbc_only": overrides["gambatte_gbc_color_correction"] = "GBC only"
            case "always": overrides["gambatte_gbc_color_correction"] = "always"
            default: overrides["gambatte_gbc_color_correction"] = "disabled"
            }
        } else if coreBaseID.contains("mgba") {
            if !gbColorizationEnabled {
                overrides["mgba_gb_model"] = "Game Boy"
            } else {
                switch gbColorizationMode {
                case "auto": overrides["mgba_gb_model"] = "Autodetect"
                case "gbc": overrides["mgba_gb_model"] = "Game Boy Color"
                case "sgb": overrides["mgba_gb_model"] = "Super Game Boy"
                default: overrides["mgba_gb_model"] = "Game Boy Color"
                }
            }
            overrides["mgba_sgb_borders"] = gbSGBBordersEnabled ? "ON" : "OFF"
        } else if coreBaseID.contains("sameboy") {
            if !gbColorizationEnabled {
                overrides["sameboy_model"] = "Game Boy"
            } else {
                switch gbColorizationMode {
                case "auto": overrides["sameboy_model"] = "Auto"
                case "gbc", "internal", "sgb", "custom": overrides["sameboy_model"] = "Game Boy Color"
                default: overrides["sameboy_model"] = "Auto"
                }
            }
            let isGBCROM = sysID == "gbc"
            if isGBCROM {
                switch gbColorCorrectionMode {
                case "disabled", "off": overrides["sameboy_color_correction_mode"] = "off"
                default: overrides["sameboy_color_correction_mode"] = "correct curves"
                }
            }
        } else if coreBaseID.contains("gearboy") {
            overrides["gearboy_colorization"] = gbColorizationEnabled ? "enabled" : "disabled"
        }
        if !overrides.isEmpty {
            CoreOptionsManager.shared.saveGameOverride(for: coreID, systemID: sysID, gameFilename: gameFilename, values: overrides)
        }
    }
}

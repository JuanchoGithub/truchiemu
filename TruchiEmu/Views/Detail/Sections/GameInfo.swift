import SwiftUI

extension GameDetailView {
    var gameInfoSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                identifyButton
                fetchBoxArtButton
                fetchMetadataButton
            }

            if !screenshotImages.isEmpty { screenshotsRow }

            ModernSectionCard(showHeader: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if currentROM.systemID == "gb" || currentROM.systemID == "gbc" {
                        HStack {
                            Text(loc.localized("gameInfo.system"))
                            Spacer()
                            Picker(loc.localized("gameInfo.system"), selection: Binding(
                                get: { currentROM.systemID ?? "gb" },
                                set: { newID in
                                    var updated = currentROM
                                    updated.systemID = newID
                                    library.updateROM(updated)
                                }
                            )) {
                                Text(loc.localized("gameInfo.gameBoy")).tag("gb")
                                Text(loc.localized("gameInfo.gameBoyColor")).tag("gbc")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .padding(.vertical, 8)
                        .foregroundColor(AppColors.textPrimary(colorScheme))

                        Divider().overlay(AppColors.divider(colorScheme))
                    }
                    MetadataRow(label: loc.localized("gameInfo.fileName"), value: currentROM.path.lastPathComponent)
                    Divider().overlay(AppColors.divider(colorScheme))
                    MetadataRow(
                        label: loc.localized("gameInfo.path"),
                        value: currentROM.path.deletingLastPathComponent().path,
                        copyAction: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(currentROM.path.path, forType: .string)
                        }
                    )
                    if let size = fileSize {
                        Divider().overlay(AppColors.divider(colorScheme))
                        MetadataRow(label: loc.localized("gameInfo.fileSize"), value: size)
                    }
                    if let crc = crcHash {
                        Divider().overlay(AppColors.divider(colorScheme))
                        MetadataRow(
                            label: loc.localized("gameInfo.crc32"),
                            value: crc,
                            isMonospaced: true,
                            copyAction: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(crc, forType: .string)
                            }
                        )
                    }
                    if let meta = currentROM.metadata {
                        if let original = meta.title, currentROM.customName != nil {
                            Divider().overlay(AppColors.divider(colorScheme))
                            MetadataRow(label: loc.localized("gameInfo.originalName"), value: original)
                        }
                        if let dev = meta.developer {
                            Divider().overlay(AppColors.divider(colorScheme))
                            MetadataRow(label: loc.localized("gameInfo.developer"), value: dev)
                        }
                        if let pub = meta.publisher {
                            Divider().overlay(AppColors.divider(colorScheme))
                            MetadataRow(label: loc.localized("gameInfo.publisher"), value: pub)
                        }
if meta.genre != nil {
        Divider().overlay(AppColors.divider(colorScheme))
        MetadataRow(label: loc.localized("gameInfo.genre"), value: GenreManager.shared.effectiveDisplayName(for: meta.genre))
    }
                        playersRow
                        if let esrb = meta.esrbRating {
                            Divider().overlay(AppColors.divider(colorScheme))
                            HStack(alignment: .top, spacing: 16) {
                                Text(loc.localized("gameInfo.esrb").uppercased())
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppColors.textTertiary(colorScheme))
                                    .frame(width: 100, alignment: .leading)
                                Text(esrb)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(esrbBadgeColor(for: esrb))
                                    .cornerRadius(6)
                                Spacer()
                            }
                        }
                    }
                }
            }

            coreInfoSection

            cheatsEnabledSection

            MAMEDependencyStatusView(rom: currentROM, coreID: activeCoreID)

            if currentROM.systemID == "gb" || currentROM.systemID == "gbc" {
                gbColorizationSection
            }

            if let description = gameDescription {
                ModernSectionCard(showHeader: false) {
                    Text(description)
                        .font(.body)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var coreInfoSection: some View {
        ModernSectionCard(title: loc.localized("gameInfo.core"), icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu").foregroundColor(AppColors.textSecondary(colorScheme))
                    Text(loc.localized("gameInfo.emulationCore")).foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text(loc.localized("gameInfo.noCoresInstalled")).font(.caption).foregroundColor(AppColors.textMuted(colorScheme))
                    } else {
                        Picker("Core", selection: $infoCoreID) {
                            Text(loc.localized("gameInfo.selectCore")).tag(nil as String?)
                            ForEach(installedCores) { core in
                                Text(core.metadata.displayName).tag(core.id as String?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: infoCoreID) { _, _ in }
                    }
                }
                Divider().overlay(AppColors.divider(colorScheme))
                Toggle(isOn: $infoApplyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe").foregroundColor(AppColors.textSecondary(colorScheme))
                        Text(loc.localized("gameInfo.applyToSystemDefault")).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if infoApplyCoreToSystem {
                    Text(loc.localized("gameInfo.changeSystemCoreWarning").replacingOccurrences(of: "{0}", with: systemName))
                        .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                } else {
                    Text(loc.localized("gameInfo.onlyThisGameUsesSelectedCore"))
                        .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                }

                Divider().overlay(AppColors.divider(colorScheme))
                HStack {
                    Spacer()
                    Button { applyCoreConfigurationFromInfo() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: infoApplyCoreToSystem ? "globe" : "gamecontroller")
                            Text(infoApplyCoreToSystem ? loc.localized("gameInfo.setSystemDefault") : loc.localized("gameInfo.setForThisGame"))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.brandAccent.opacity(0.8))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(infoCoreID == nil || installedCores.isEmpty)
                }
                Divider().overlay(AppColors.divider(colorScheme))
                HStack {
                    Spacer()
                    Button {
                        showCoreOptionsView = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                            Text(loc.localized("gameInfo.coreOptions"))
                        }
                        .foregroundColor(AppColors.brandAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.brandAccent.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(activeCoreID == nil)
                }
            }
        }
    }

    func applyCoreConfigurationFromInfo() {
        guard let sysID = currentROM.systemID, let coreID = infoCoreID, !coreID.isEmpty else { return }
        if infoApplyCoreToSystem {
            sysPrefs.setPreferredCoreID(coreID, for: sysID)
            var updated = currentROM
            updated.useCustomCore = false
            updated.selectedCoreID = nil
            library.updateROM(updated)
            useCustomCore = false
            infoApplyCoreToSystem = true
        } else {
            var updated = currentROM
            updated.useCustomCore = true
            updated.selectedCoreID = coreID
            library.updateROM(updated)
            useCustomCore = true
            infoApplyCoreToSystem = false
        }
    }

    var cheatsEnabledSection: some View {
        ModernSectionCard(title: loc.localized("gameInfo.cheats"), icon: "gamecontroller") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { currentROM.settings.cheatsEnabled ?? false },
                    set: { newValue in
                        updateSettings { $0.cheatsEnabled = newValue }
                    }
                )) {
                    HStack {
                        Image(systemName: "gamecontroller.fill").foregroundColor(AppColors.brandAccent)
                        Text(loc.localized("gameInfo.enableCheats")).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

                if currentROM.settings.cheatsEnabled ?? false {
                    Text(loc.localized("gameInfo.cheatsEnabledInfo"))
                        .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var gbColorizationSection: some View {
        ModernSectionCard(title: loc.localized("gameInfo.gameBoyColorization"), icon: "paintpalette") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { gbColorizationEnabled },
                    set: { newValue in
                        gbColorizationEnabled = newValue
                        applyGBColorizationSettings()
                    }
                )) {
                    HStack {
                        Image(systemName: "paintpalette.fill").foregroundColor(.purple)
                        Text(loc.localized("gameInfo.enableColorization")).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                }
                .toggleStyle(SwitchToggleStyle())

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
                    Text(loc.localized("gameInfo.applyColorPalettes"))
                        .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                } else {
                    Divider().overlay(AppColors.divider(colorScheme))
                    Text(loc.localized("gameInfo.gamesDisplayMonochrome"))
                        .font(.caption).foregroundColor(AppColors.textTertiary(colorScheme)).lineSpacing(2)
                }
            }
        }
    }

    var gbPaletteModeRow: some View {
        HStack {
            Image(systemName: "eyedropper").foregroundColor(AppColors.textSecondary(colorScheme))
            Text(loc.localized("gameInfo.paletteMode")).foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
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
    }

    var gbInternalPaletteRow: some View {
        HStack {
            Image(systemName: "paintpalette").foregroundColor(AppColors.textSecondary(colorScheme))
            Text(loc.localized("gameInfo.internalPalette")).foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
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
    }

    var gbSGBBordersRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "rectangle.on.rectangle").foregroundColor(AppColors.textSecondary(colorScheme))
                Text(loc.localized("gameInfo.superGameBoyBorders")).foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
                Spacer()
                Text(loc.localized("gameInfo.mgbaCore")).foregroundColor(AppColors.textMuted(colorScheme)).font(.caption2)
            }
            Text(loc.localized("gameInfo.showSGBBorders"))
                .font(.caption2).foregroundColor(AppColors.textMuted(colorScheme)).padding(.leading, 24)
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
    }

    var gbColorCorrectionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "sun.max").foregroundColor(AppColors.textSecondary(colorScheme))
                Text(loc.localized("gameInfo.colorCorrection")).foregroundColor(AppColors.textSecondary(colorScheme)).font(.caption)
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
            Text(loc.localized("gameInfo.matchOutputColors"))
                .font(.caption2).foregroundColor(AppColors.textMuted(colorScheme)).padding(.leading, 24)
        }
    }

    func loadGBColorizationSettings() {
        guard let sysID = currentROM.systemID,
              (sysID == "gb" || sysID == "gbc"),
              let coreID = activeCoreID else { return }
        let gameFilename = currentROM.filenameWithoutExtension
        let overrides = CoreOptionsManager.shared.loadGameOverrides(for: coreID, systemID: sysID, gameFilename: gameFilename)
        if overrides.isEmpty { return }
        let coreBaseID = coreID.replacingOccurrences(of: "_libretro", with: "")
        if coreBaseID.contains("gambatte") {
            if let val = overrides["gambatte_gb_colorization"] {
                if val == "disabled" {
                    gbColorizationEnabled = false
                } else {
                    gbColorizationEnabled = true
                    gbColorizationMode = val
                }
            }
            if let val = overrides["gambatte_gb_internal_palette"] {
                gbInternalPalette = val
            }
            if let val = overrides["gambatte_gbc_color_correction"] {
                switch val {
                case "GBC only": gbColorCorrectionMode = "gbc_only"
                case "always": gbColorCorrectionMode = "always"
                default: gbColorCorrectionMode = "disabled"
                }
            }
        } else if coreBaseID.contains("mgba") {
            if let val = overrides["mgba_gb_model"] {
                switch val {
                case "Game Boy": gbColorizationEnabled = false
                case "Autodetect": gbColorizationEnabled = true; gbColorizationMode = "auto"
                case "Game Boy Color": gbColorizationEnabled = true; gbColorizationMode = "gbc"
                case "Super Game Boy": gbColorizationEnabled = true; gbColorizationMode = "sgb"
                default: break
                }
            }
            if let val = overrides["mgba_sgb_borders"] {
                gbSGBBordersEnabled = (val == "ON")
            }
        } else if coreBaseID.contains("sameboy") {
            if let val = overrides["sameboy_model"] {
                switch val {
                case "Game Boy": gbColorizationEnabled = false
                case "Auto": gbColorizationEnabled = true; gbColorizationMode = "auto"
                case "Game Boy Color": gbColorizationEnabled = true; gbColorizationMode = "gbc"
                default: break
                }
            }
            if let val = overrides["sameboy_color_correction_mode"] {
                switch val {
                case "off": gbColorCorrectionMode = "disabled"
                default: gbColorCorrectionMode = "gbc_only"
                }
            }
        } else if coreBaseID.contains("gearboy") {
            if let val = overrides["gearboy_colorization"] {
                gbColorizationEnabled = (val == "enabled")
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

    var identifyButton: some View {
        Button {
            Task {
                manualActionStatus = .working("Identifying from No-Intro database…")
                let result = await library.identifyROM(currentROM, preferNameMatch: false)
                switch result {
                case .identified(let info):
                    showManualResult("Found: \(currentROM.name) → \(info.name)", tone: .success)
                    var updated = currentROM
                    updated.customName = info.name
                    library.updateROM(updated)
                    if !currentROM.hasBoxArt {
                        if let _ = await BoxArtService.shared.fetchBoxArt(for: currentROM) {
                            var u = currentROM
                            u.hasBoxArt = true
                            library.updateROM(u)
                            loadBoxArt()
                        }
                    }
                    loadSlotInfo()
                case .identifiedFromName(let info):
                    showManualResult("Found: \(currentROM.name) → \(info.name) (matched by filename)", tone: .success)
                    var updated = currentROM
                    updated.customName = info.name
                    library.updateROM(updated)
                    if !currentROM.hasBoxArt {
                        if let _ = await BoxArtService.shared.fetchBoxArt(for: currentROM) {
                            var u = currentROM
                            u.hasBoxArt = true
                            library.updateROM(u)
                            loadBoxArt()
                        }
                    }
                    loadSlotInfo()
                case .crcNotInDatabase(let crc):
                    showManualResult("Couldn't identify this game. Try downloading metadata manually.", tone: .warning)
                    LoggerService.debug(category: "Identity", "For: \(currentROM.name) — Unknown game — CRC: \(crc)")
                case .identificationCleared:
                    showManualResult("Identification cleared — game will use ROM filename", tone: .success)
                case .databaseUnavailable:
                    showManualResult("Identification database unavailable. Check your internet connection.", tone: .error)
                case .romReadFailed(let reason):
                    showManualResult("Could not read this game: \(reason)", tone: .error)
                case .noSystem:
                    showManualResult("Cannot identify — system is not set for this file.", tone: .error)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if case .working = manualActionStatus { ProgressView().controlSize(.small) } else { Image(systemName: "qrcode.viewfinder") }
                Text(loc.localized("gameInfo.identifyGame"))
            }
            .foregroundColor(AppColors.textPrimary(colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppColors.cardBackground(colorScheme))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(isIdentifyWorking)
    }

    var fetchMetadataButton: some View {
        Group {
            switch fetchMetadataStatus {
            case .hidden:
                Button { Task { await fetchMetadata() } } label: {
                    Label(loc.localized("gameInfo.fetchMetadata"), systemImage: "network")
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.cardBackgroundSubtle(colorScheme))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
            case .working(_):
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(8)
            case .result(let msg, let tone):
                Button { clearFetchMetadataStatus() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(msg).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(tone.foregroundColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func fetchMetadata() async {
        await MainActor.run { fetchMetadataStatus = .working(loc.localized("gameInfo.searchingLaunchBox")) }
        let success = await LaunchBoxGamesDBService.shared.fetchAndApplyMetadata(for: currentROM, library: library)
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            if case .result = fetchMetadataStatus { fetchMetadataStatus = .hidden }
        }
        if success {
            await MainActor.run { fetchMetadataStatus = .result(loc.localized("gameInfo.metadataUpdated"), tone: .success) }
        } else {
            await MainActor.run { fetchMetadataStatus = .result(loc.localized("gameInfo.noMetadataFound"), tone: .warning) }
        }
    }

    func clearFetchMetadataStatus() {
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = nil
        fetchMetadataStatus = .hidden
    }

    var fetchBoxArtButton: some View {
        Group {
            switch fetchBoxArtStatus {
            case .hidden:
                Button { Task { await fetchBoxArt() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text(loc.localized("gameInfo.fetchArt"))
                    }
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColors.cardBackground(colorScheme))
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
            case .working(let msg):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(msg).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.cardBackground(colorScheme))
                .cornerRadius(20)
            case .result(let msg, let tone):
                Button { clearFetchBoxArtStatus() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(msg).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(tone.foregroundColor.opacity(0.1))
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func fetchBoxArt() async {
        await MainActor.run { fetchBoxArtStatus = .working(loc.localized("gameInfo.searching")) }
        if await BoxArtService.shared.fetchBoxArt(for: currentROM) != nil {
            var u = currentROM
            u.hasBoxArt = true
            library.updateROM(u)
            loadBoxArt()
            fetchBoxArtAutoDismiss?.cancel()
            fetchBoxArtAutoDismiss = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                if case .result = fetchBoxArtStatus { fetchBoxArtStatus = .hidden }
            }
            await MainActor.run { fetchBoxArtStatus = .result(loc.localized("gameInfo.artFound"), tone: .success) }
        } else {
            await MainActor.run { fetchBoxArtStatus = .result(loc.localized("gameInfo.noCoverArtFound"), tone: .warning) }
        }
    }

    func clearFetchBoxArtStatus() {
        fetchBoxArtAutoDismiss?.cancel()
        fetchBoxArtAutoDismiss = nil
        fetchBoxArtStatus = .hidden
    }

    var screenshotsRow: some View {
        ModernSectionCard(title: loc.localized("gameInfo.screenshots"), icon: "photo.on.rectangle", showHeader: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(screenshotImages.indices, id: \.self) { index in
                        Image(nsImage: screenshotImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 180, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                    }
                }
            }
        }
    }

    func esrbBadgeColor(for rating: String) -> Color {
        switch rating.lowercased() {
        case "ec", "e": return AppColors.success(colorScheme).opacity(0.3)
        case "e10+": return Color.blue.opacity(0.3)
        case "t": return Color.yellow.opacity(0.3)
        case "m", "ao": return AppColors.error(colorScheme).opacity(0.3)
        default: return AppColors.cardBackgroundSubtle(colorScheme)
        }
    }

    var playersRow: some View {
        Group {
            if let meta = currentROM.metadata, meta.players > 0 {
                let playersIdentifiedFromLibretro = meta.userPlayerOverride == nil && meta.players > 1
                    if playersIdentifiedFromLibretro {
                        Divider().overlay(AppColors.divider(colorScheme))
                        MetadataRow(label: loc.localized("gameInfo.players"), value: String(meta.players))
                    if meta.players > 1 {
                        Divider().overlay(AppColors.divider(colorScheme))
                        MetadataRow(label: loc.localized("gameInfo.coop"), value: meta.cooperative ? loc.localized("gameInfo.yes") : loc.localized("gameInfo.no"))
                    }
                } else {
                    Divider().overlay(AppColors.divider(colorScheme))
                    playersPickerView(meta: meta)
                }
            }
        }
    }

    private func playersPickerView(meta: ROMMetadata) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(loc.localized("gameInfo.players").uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .frame(width: 100, alignment: .leading)
            Spacer()
            Picker("", selection: Binding(
                get: { meta.userPlayerOverride ?? 1 },
                set: { newValue in
                    guard newValue > 0 else { return }
                    Task { @MainActor in
                        var updated = self.currentROM
                        if updated.metadata == nil { updated.metadata = ROMMetadata() }
                        updated.metadata?.userPlayerOverride = newValue
                        updated.metadata?.players = newValue
                        self.library.updateROM(updated)
                    }
                }
            )) {
                Text(loc.localized("gameInfo.single")).tag(1)
                Text(loc.localized("gameInfo.multi")).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
        }
    }
}
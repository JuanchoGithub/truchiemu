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
                    MetadataRow(label: "System", value: system?.name ?? currentROM.systemID ?? "Not identified")
                    Divider().overlay(dividerColor)
                    MetadataRow(label: "File Name", value: currentROM.path.lastPathComponent)
                    Divider().overlay(dividerColor)
                    MetadataRow(
                        label: "Path",
                        value: currentROM.path.deletingLastPathComponent().path,
                        copyAction: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(currentROM.path.path, forType: .string)
                        }
                    )
                    if let size = fileSize {
                        Divider().overlay(dividerColor)
                        MetadataRow(label: "File Size", value: size)
                    }
                    if let crc = crcHash {
                        Divider().overlay(dividerColor)
                        MetadataRow(
                            label: "CRC32",
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
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Original Name", value: original)
                        }
                        if let dev = meta.developer {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Developer", value: dev)
                        }
                        if let pub = meta.publisher {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Publisher", value: pub)
                        }
                        if let genre = meta.genre {
                            Divider().overlay(dividerColor)
                            MetadataRow(label: "Genre", value: genre)
                        }
                        Divider().overlay(dividerColor)
                        MetadataRow(label: "Players", value: String(meta.players))
                        Divider().overlay(dividerColor)
                        MetadataRow(label: "Co-op", value: meta.cooperative ? "Yes" : "No")
                        if let esrb = meta.esrbRating {
                            Divider().overlay(dividerColor)
                            HStack(alignment: .top, spacing: 16) {
                                Text("ESRB".uppercased())
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 100, alignment: .leading)
                                Text(esrb)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.85))
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
             
             if currentROM.systemID == "mame" || currentROM.systemID == "arcade" {
                MAMEDependencyStatusView(rom: currentROM, coreID: activeCoreID)
            }
            
            if currentROM.systemID == "gb" || currentROM.systemID == "gbc" {
                gbColorizationSection
            }

            if let description = gameDescription {
                ModernSectionCard(showHeader: false) {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    var coreInfoSection: some View {
        ModernSectionCard(title: "Core", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu").foregroundColor(.white.opacity(0.5))
                    Text("Emulation Core").foregroundColor(.white.opacity(0.5)).font(.caption)
                    Spacer()
                    if installedCores.isEmpty {
                        Text("No cores installed").font(.caption).foregroundColor(.white.opacity(0.3))
                    } else {
                        Picker("Core", selection: $infoCoreID) {
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
                Divider().overlay(dividerColor)
                Toggle(isOn: $infoApplyCoreToSystem) {
                    HStack {
                        Image(systemName: "globe").foregroundColor(.white.opacity(0.5))
                        Text("Apply to system default").foregroundColor(.white.opacity(0.85))
                    }
                }
                .toggleStyle(SwitchToggleStyle())
                
                if infoApplyCoreToSystem {
                    Text("This will change the default core for all \(systemName) games. The current game will no longer use a custom core override.")
                        .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                } else {
                    Text("Only this game will use the selected core.")
                        .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                }
                
                Divider().overlay(dividerColor)
                HStack {
                    Spacer()
                    Button { applyCoreConfigurationFromInfo() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: infoApplyCoreToSystem ? "globe" : "gamecontroller")
                            Text(infoApplyCoreToSystem ? "Set System Default" : "Set for This Game")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(infoCoreID == nil || installedCores.isEmpty)
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
         ModernSectionCard(title: "Cheats", icon: "gamecontroller") {
             VStack(alignment: .leading, spacing: 12) {
                 Toggle(isOn: Binding(
                     get: { currentROM.settings.cheatsEnabled ?? false },
                     set: { newValue in
                         updateSettings { $0.cheatsEnabled = newValue }
                     }
                 )) {
                     HStack {
                         Image(systemName: "gamecontroller.fill").foregroundColor(.blue)
                         Text("Enable Cheats").foregroundColor(.white.opacity(0.85))
                     }
                 }
                 .toggleStyle(SwitchToggleStyle())
                 
                 if currentROM.settings.cheatsEnabled ?? false {
                     Text("When enabled, the emulator will attempt to apply active cheats during launch.")
                         .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                 }
             }
         }
     }

     var gbColorizationSection: some View {
         ModernSectionCard(title: "Game Boy Colorization", icon: "paintpalette") {
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
                         Text("Enable Colorization").foregroundColor(.white.opacity(0.85))
                     }
                 }
                 .toggleStyle(SwitchToggleStyle())
                 
                 if gbColorizationEnabled {
                     Divider().overlay(dividerColor)
                     gbPaletteModeRow
                     if gbColorizationMode == "internal" {
                         Divider().overlay(dividerColor)
                         if isGambatteCore {
                             gbInternalPaletteRow
                         } else {
                             gbInternalPaletteRow.opacity(0.4).disabled(true)
                                 .help("Gambatte core only — switch to gambatte_libretro to use named palettes")
                         }
                     }
                     Divider().overlay(dividerColor)
                     gbSGBBordersRow
                     Divider().overlay(dividerColor)
                     if isGambatteCore {
                         gbColorCorrectionRow
                     } else {
                         gbColorCorrectionRow.opacity(0.4).disabled(true)
                             .help("Gambatte core only — switch to gambatte_libretro to use color correction")
                     }
                     Divider().overlay(dividerColor)
                     Text("Apply color palettes to original Game Boy (DMG) games. 'Auto' selects the best palette for each game. 'Internal' uses a classic Game Boy or Super Game Boy palette. Named palettes and color correction require the Gambatte core.")
                         .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                 } else {
                     Divider().overlay(dividerColor)
                     Text("Games will display in classic Game Boy monochrome (green-tinted).")
                         .font(.caption).foregroundColor(.white.opacity(0.4)).lineSpacing(2)
                 }
             }
         }
     }

    var gbPaletteModeRow: some View {
        HStack {
            Image(systemName: "eyedropper").foregroundColor(.white.opacity(0.5))
            Text("Palette Mode").foregroundColor(.white.opacity(0.5)).font(.caption)
            Spacer()
            Picker("Palette Mode", selection: Binding(
                get: { gbColorizationMode },
                set: { newValue in
                    gbColorizationMode = newValue
                    applyGBColorizationSettings()
                }
            )) {
                Text("Auto Select").tag("auto")
                Text("Game Boy Color").tag("gbc")
                Text("Super Game Boy").tag("sgb")
                Text("Internal Palette").tag("internal")
                Text("Custom Palettes").tag("custom")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
    }

    var gbInternalPaletteRow: some View {
        HStack {
            Image(systemName: "paintpalette").foregroundColor(.white.opacity(0.5))
            Text("Internal Palette").foregroundColor(.white.opacity(0.5)).font(.caption)
            Spacer()
            Picker("Internal Palette", selection: Binding(
                get: { gbInternalPalette },
                set: { newValue in
                    gbInternalPalette = newValue
                    applyGBColorizationSettings()
                }
            )) {
                Section(header: Text("Game Boy")) {
                    Text("GB - DMG (Green)").tag("GB - DMG")
                    Text("GB - Pocket").tag("GB - Pocket")
                    Text("GB - Light").tag("GB - Light")
                }
                Section(header: Text("Game Boy Color")) {
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
                Section(header: Text("Super Game Boy")) {
                    Text("SGB - 1A").tag("SGB - 1A")
                    Text("SGB - 1B").tag("SGB - 1B")
                    Text("SGB - 2A").tag("SGB - 2A")
                    Text("SGB - 2B").tag("SGB - 2B")
                    Text("SGB - 3A").tag("SGB - 3A")
                    Text("SGB - 3B").tag("SGB - 3B")
                    Text("SGB - 4A").tag("SGB - 4A")
                    Text("SGB - 4B").tag("SGB - 4B")
                }
                Section(header: Text("Special")) {
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
                Image(systemName: "rectangle.on.rectangle").foregroundColor(.white.opacity(0.5))
                Text("Super Game Boy Borders").foregroundColor(.white.opacity(0.5)).font(.caption)
                Spacer()
                Text("mGBA core").foregroundColor(.white.opacity(0.3)).font(.caption2)
            }
            Text("Show decorative borders on SGB-enhanced games.")
                .font(.caption2).foregroundColor(.white.opacity(0.3)).padding(.leading, 24)
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
                Image(systemName: "sun.max").foregroundColor(.white.opacity(0.5))
                Text("Color Correction").foregroundColor(.white.opacity(0.5)).font(.caption)
                Spacer()
                Picker("Color Correction", selection: Binding(
                    get: { gbColorCorrectionMode },
                    set: { newValue in
                        gbColorCorrectionMode = newValue
                        applyGBColorizationSettings()
                    }
                )) {
                    Text("GBC Games Only").tag("gbc_only")
                    Text("Always").tag("always")
                    Text("Disabled").tag("disabled")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }
            Text("Match output colors to original Game Boy Color LCD.")
                .font(.caption2).foregroundColor(.white.opacity(0.3)).padding(.leading, 24)
        }
    }

    func applyGBColorizationSettings() {
        guard currentROM.systemID == "gb" || currentROM.systemID == "gbc" else { return }
        var updated = currentROM
        updated.settings.gbColorizationEnabled = gbColorizationEnabled
        updated.settings.gbColorizationMode = gbColorizationMode
        updated.settings.gbInternalPalette = gbInternalPalette
        updated.settings.gbSGBBordersEnabled = gbSGBBordersEnabled
        updated.settings.gbColorCorrectionMode = gbColorCorrectionMode
        library.updateROM(updated)
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
                Text("Identify Game")
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(buttonBgColor)
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
                    Label("Fetch Metadata", systemImage: "network")
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(subtleButtonBgColor)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            case .working(_):
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(subtleButtonBgColor)
                    .cornerRadius(8)
            case .result(let msg, let tone):
                Button { clearFetchMetadataStatus() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(msg).font(.caption).foregroundColor(.white.opacity(0.7))
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
        await MainActor.run { fetchMetadataStatus = .working("Searching LaunchBox...") }
        let success = await LaunchBoxGamesDBService.shared.fetchAndApplyMetadata(for: currentROM, library: library)
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            if case .result = fetchMetadataStatus { fetchMetadataStatus = .hidden }
        }
        if success {
            await MainActor.run { fetchMetadataStatus = .result("Metadata updated", tone: .success) }
        } else {
            await MainActor.run { fetchMetadataStatus = .result("No metadata found in the database. Try identifying this game first.", tone: .warning) }
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
                        Text("Fetch Art")
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(buttonBgColor)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
            case .working(let msg):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(msg).font(.caption).foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(buttonBgColor)
                .cornerRadius(20)
            case .result(let msg, let tone):
                Button { clearFetchBoxArtStatus() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(msg).font(.caption).foregroundColor(.white.opacity(0.7))
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
        await MainActor.run { fetchBoxArtStatus = .working("Searching...") }
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
            await MainActor.run { fetchBoxArtStatus = .result("Art found", tone: .success) }
        } else {
            await MainActor.run { fetchBoxArtStatus = .result("No cover art found for this game. You can manually search using the Box Art picker.", tone: .warning) }
        }
    }

    func clearFetchBoxArtStatus() {
        fetchBoxArtAutoDismiss?.cancel()
        fetchBoxArtAutoDismiss = nil
        fetchBoxArtStatus = .hidden
    }

    var screenshotsRow: some View {
        ModernSectionCard(title: "Screenshots", icon: "photo.on.rectangle", showHeader: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(screenshotImages.indices, id: \.self) { index in
                        Image(nsImage: screenshotImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 180, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                }
            }
        }
    }

    func esrbBadgeColor(for rating: String) -> Color {
        switch rating.lowercased() {
        case "ec", "e": return Color.green.opacity(0.3)
        case "e10+": return Color.blue.opacity(0.3)
        case "t": return Color.yellow.opacity(0.3)
        case "m", "ao": return Color.red.opacity(0.3)
        default: return Color.white.opacity(0.1)
        }
    }
}
import SwiftUI
import AppKit
import GameController

struct SetupWizardView: View {
    @ObservedObject var wizard: SetupWizardState
    @ObservedObject private var themeManager = ThemeManager.shared
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var loc: LocalizationManager

    @Environment(\.colorScheme) private var colorScheme
    @State private var raLoginError: RAError?
    @State private var isRALoggingIn: Bool = false
    @State private var raLoginSuccess: Bool = false

    var body: some View {
        ZStack {
            AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                ScrollView {
                    ZStack {
                        switch wizard.currentStep {
                        case .getStarted: stepGetStarted
                        case .lookAndFeel: stepLookAndFeel
                        case .featureCatalog: stepFeatureCatalog
                        case .achievementsSetup: stepAchievementsSetup
                        case .streamingSetup: stepStreamingSetup
                        case .completion: stepCompletion
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                bottomNavigation
            }
            .padding()
            .frame(maxWidth: 720)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.15), radius: 20, y: 4)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack {
                Label("TruchiEmu", systemImage: "arcade.stick")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 0) {
                ForEach(Array(wizard.visibleSteps.enumerated()), id: \.element.id) { idx, step in
                    Circle()
                        .fill(idx <= wizard.currentStepIndex ? AppColors.brandAccent : AppColors.cardBackground(colorScheme))
                        .frame(width: 8, height: 8)
                    if idx < wizard.visibleSteps.count - 1 {
                        Rectangle()
                            .fill(idx < wizard.currentStepIndex ? AppColors.brandAccent : AppColors.cardBackground(colorScheme))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)

        Text(loc.localized(wizard.currentStep.localizationKey))
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        HStack {
            if wizard.currentStepIndex > 0 {
                Button(loc.localized("wizard.back")) {
                    wizard.previousStep()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.leftArrow, modifiers: [])
            } else {
                Spacer()
            }

            Spacer()

            if wizard.currentStep.canSkip {
Button(loc.localized("wizard.skip")) {
                wizard.nextStep()
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary(colorScheme))
            }

            if wizard.currentStep == .completion {
                Button(loc.localized("wizard.enterLibrary")) {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Button(loc.localized("wizard.continue")) {
                    wizard.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.top, 16)
    }

    private func finishSetup() {
        library.hasCompletedOnboarding = true
        AppSettings.setBool("has_completed_onboarding", value: true)

        AppSettings.set("display_default_shader_preset", value: wizard.selectedShaderPresetID)
        SystemPreferences.shared.systemLanguage = wizard.selectedRegion

        // Persist theme (only if different from current — no restart here, user is prompted at Settings if they want one)
        if wizard.selectedTheme != ThemeManager.shared.currentTheme {
            AppSettings.set("accentTheme", value: wizard.selectedTheme)
            ThemeManager.shared.applyTheme(wizard.selectedTheme)
        }

        for folder in wizard.libraryFolders {
            library.addLibraryFolder(url: folder)
        }

        // LaunchBox metadata
        if wizard.featureLaunchBox {
            AppSettings.setBool("launchbox_use_for_boxart", value: true)
            AppSettings.setBool("launchbox_download_after_scan", value: true)
        }

        // Holo masks (visual box art preference; always write so the wizard choice takes effect)
        AppSettings.setBool("auto_generate_holo_masks", value: wizard.generateHoloMasks)

        // Cheats master toggle (download handled separately)
        if wizard.featureCheats {
            AppSettings.setBool("cheats_enabled", value: true)
        }

        // Time Machine (always write, even if false, so the wizard's choice takes effect)
        AppSettings.setBool("timeMachine_enabled", value: wizard.featureTimeMachine)

        // Streaming
        if wizard.featureStreaming {
            AppSettings.setBool("streaming_enabled", value: wizard.streamingEnabled)
            AppSettings.setString("streaming_quality", value: wizard.streamingQuality.rawValue)

            // Persist the per-destination keys we have, even ones that aren't currently selected,
            // so the user doesn't lose their other destinations by tweaking one in the wizard.
            AppSettings.setString("streaming_twitch_key", value: wizard.streamingTwitchKey)
            AppSettings.setString("streaming_youtube_key", value: wizard.streamingYouTubeKey)
            AppSettings.setString("streaming_custom_key", value: wizard.streamingCustomKey)

            if wizard.streamingEnabled {
                AppSettings.setString("streaming_mode", value: wizard.streamingDestination.rawValue)
            }
        }

        let downloadBezels = wizard.downloadBezels
        let downloadCheats = wizard.featureCheatsDownload
        let achievementsUsername = wizard.achievementsUsername
        let achievementsPassword = wizard.achievementsPassword
        let achievementsWebApiKey = wizard.achievementsWebApiKey
        let achievementsEnabled = wizard.featureRetroAchievements
        let achievementsHardcore = wizard.achievementsHardcore

        Task.detached(priority: .utility) {
            if downloadBezels || downloadCheats {
                await withTaskGroup(of: Void.self) { group in
                    if downloadBezels {
                        group.addTask { _ = await BezelAPIService.shared.downloadAllSystems() }
                    }
                    if downloadCheats {
                        group.addTask { _ = await CheatDownloadService.shared.downloadAllCheats() }
                    }
                }
            }

            if achievementsEnabled && !achievementsUsername.isEmpty && !achievementsWebApiKey.isEmpty {
                do {
                    try await RetroAchievementsService.shared.loginWithWebApiKey(
                        username: achievementsUsername,
                        webApiKey: achievementsWebApiKey,
                        password: achievementsPassword
                    )
                    await RetroAchievementsService.shared.setEnabled(true)
                    if achievementsHardcore {
                        await RetroAchievementsService.shared.setHardcoreMode(true)
                    }
                } catch {
                    LoggerService.info(category: "Wizard", "Achievements login failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Step 1: Get Started (Welcome + Add Games)

extension SetupWizardView {
    private var stepGetStarted: some View {
            VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("wizard.welcomeTitle")
                    .font(.title)
                    .fontWeight(.bold)
                Text("wizard.welcomeDescription")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(loc.localized("wizard.selectLanguage"), systemImage: "globe")
                        .font(.headline)
                    Spacer()
                    Picker(loc.localized("settings.selectLanguage"), selection: Binding<String>(
                        get: { loc.currentLanguage },
                        set: { newLang in
                            loc.setLanguage(newLang)
                            autoSelectRegion(for: newLang)
                        })
                    ) {
                        ForEach(loc.availableLanguages, id: \.self) { lang in
                            Text("\(languageFlag(for: lang)) \(languageDisplayName(for: lang))")
                                .tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .id(loc.currentLanguage)
                    .frame(maxWidth: 220, alignment: .trailing)
                }

                Text("wizard.languageDescription")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(loc.localized("wizard.gameRegion"), systemImage: "map")
                        .font(.headline)
                    Spacer()
                    Picker(loc.localized("wizard.selectRegion"), selection: $wizard.selectedRegion) {
                        ForEach(EmulatorLanguage.allCases) { lang in
                            Text("\(lang.flagEmoji) \(lang.localizedName)")
                                .tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .id(loc.currentLanguage)
                    .frame(maxWidth: 220, alignment: .trailing)
                }

                Text("wizard.regionDescription")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)

                VStack(alignment: .leading, spacing: 6) {
                    Text("wizard.regionExamples")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))

                    HStack(spacing: 6) {
                        ForEach([EmulatorLanguage.northAmerica, .japan, .europe], id: \.self) { region in
                            Button {
                                wizard.selectedRegion = region
                            } label: {
                                VStack(spacing: 2) {
                                    if let img = boxArtSample(for: region) {
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(region.flagEmoji)
                                        .font(.caption2)
                                    Text("wizard.region.\(region.name.lowercased().replacingOccurrences(of: " ", with: ""))")
                                        .font(.system(size: 9))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(wizard.selectedRegion == region ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(wizard.selectedRegion == region ? AppColors.brandAccent : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 4)
            }

            if !wizard.libraryFolders.isEmpty {
                List {
                    ForEach(wizard.libraryFolders.indices, id: \.self) { idx in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(AppColors.brandAccent)
                            VStack(alignment: .leading) {
                                Text(wizard.libraryFolders[idx].lastPathComponent)
                                    .lineLimit(1)
Text(wizard.libraryFolders[idx].path)
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                wizard.removeLibraryFolder(at: idx)
                            } label: {
Image(systemName: "trash")
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Button {
                pickFolder()
            } label: {
                Label(loc.localized("wizard.addFolder"), systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if wizard.libraryFolders.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    Text("wizard.addFolderLater")
                        .font(.callout)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }
        }
    }

    private func autoSelectRegion(for language: String) {
        switch language.lowercased() {
        case "en": wizard.selectedRegion = .northAmerica
        case "es": wizard.selectedRegion = .spain
        case "pt": wizard.selectedRegion = .brazil
        default: wizard.selectedRegion = .northAmerica
        }
    }

    private func boxArtSample(for region: EmulatorLanguage) -> NSImage? {
        let name: String
        switch region {
        case .northAmerica, .world: name = "super_mario_64_usa"
        case .japan: name = "super_mario_64_japan"
        case .europe: name = "super_mario_64_europe"
        case .brazil: name = "super_mario_64_europe"
        case .spain: name = "super_mario_64_europe"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = loc.localized("library.selectFolders")
        panel.prompt = loc.localized("wizard.addFoldersPrompt")
        if panel.runModal() == .OK {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let internalPrefix = appSupport.appendingPathComponent("TruchiEmu").path
            for url in panel.urls {
                if url.path.hasPrefix(internalPrefix) { continue }
                wizard.addLibraryFolder(url)
            }
        }
    }
}

// MARK: - Step 2: Look & Feel (Theme + Bezels + Shaders)

extension SetupWizardView {
    private var stepLookAndFeel: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Theme
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.localized("wizard.theme"), systemImage: "paintpalette")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("wizard.themeDescription")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.callout)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AccentColorTheme.allCases, id: \.self) { theme in
                                themeButton(theme)
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            }

            Divider()

            // Bezels
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.localized("bezel.title"), systemImage: "rectangle.on.rectangle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("wizard.bezelsDescription")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.callout)

                    Toggle(loc.localized("wizard.downloadBezelsToggle"), isOn: $wizard.downloadBezels)
                        .toggleStyle(.switch)
                        .tint(AppColors.brandAccentSecondary)
                }
                .padding(.leading, 4)
            }

            Divider()

            // Shaders
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.localized("wizard.defaultShader"), systemImage: "tv")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("wizard.shaderDescription")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.callout)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ShaderPreset.allPresets, id: \.id) { preset in
                                shaderPill(preset: preset)
                            }
                        }
                    }
                }
                .padding(.leading, 4)
            }

            Divider()

            // Holo Masks
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.localized("wizard.holoMasks"), systemImage: "sparkles")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("wizard.holoMasksDescription")
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .font(.callout)

                    Toggle(loc.localized("wizard.holoMasksToggle"), isOn: $wizard.generateHoloMasks)
                        .toggleStyle(.switch)
                        .tint(AppColors.brandAccentSecondary)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                            .font(.callout)
                        Text("wizard.holoMasksWarning")
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(8)
                }
                .padding(.leading, 4)
            }
        }
    }

    private func themeButton(_ theme: AccentColorTheme) -> some View {
        let isSelected = wizard.selectedTheme == theme
        return Button {
            wizard.selectedTheme = theme
        } label: {
            VStack(spacing: 4) {
                Image(theme.iconAssetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                Text(theme.displayName)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? AppColors.brandAccent : .primary)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppColors.brandAccent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func shaderPill(preset: ShaderPreset) -> some View {
        let isSelected = wizard.selectedShaderPresetID == preset.id
        return Button {
            wizard.selectedShaderPresetID = preset.id
        } label: {
            Label(preset.name, systemImage: shaderIcon(for: preset.shaderType))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.brandAccent.opacity(0.15) : AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? AppColors.brandAccent : Color.clear, lineWidth: 1)
                )
                .foregroundColor(isSelected ? AppColors.brandAccent : .primary)
        }
        .buttonStyle(.plain)
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

// MARK: - Step 3: Feature Catalog (checklist of optional features)

extension SetupWizardView {
    private var stepFeatureCatalog: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("wizard.featureCatalog.title")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("wizard.featureCatalog.description")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    icon: "trophy",
                    title: loc.localized("wizard.feature.achievements"),
                    description: loc.localized("wizard.feature.achievementsDesc"),
                    isOn: $wizard.featureRetroAchievements
                )

                Divider()

                featureRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: loc.localized("wizard.feature.streaming"),
                    description: loc.localized("wizard.feature.streamingDesc"),
                    isOn: $wizard.featureStreaming
                )

                Divider()

                featureRow(
                    icon: "wand.and.stars",
                    title: loc.localized("wizard.feature.cheats"),
                    description: loc.localized("wizard.feature.cheatsDesc"),
                    isOn: $wizard.featureCheats
                )

                if wizard.featureCheats {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .frame(width: 24)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                        Toggle(isOn: $wizard.featureCheatsDownload) {
                            Text(loc.localized("wizard.cheatsDetail"))
                                .font(.caption)
                        }
                        .toggleStyle(.switch)
                        .tint(AppColors.brandAccentSecondary)
                        Spacer()
                    }
                    .padding(.leading, 8)
                }

                Divider()

                featureRow(
                    icon: "books.vertical",
                    title: loc.localized("wizard.feature.launchbox"),
                    description: loc.localized("wizard.feature.launchboxDesc"),
                    isOn: $wizard.featureLaunchBox
                )

                Divider()

                featureRow(
                    icon: "clock.arrow.circlepath",
                    title: loc.localized("wizard.feature.timeMachine"),
                    description: loc.localized("wizard.feature.timeMachineDesc"),
                    isOn: $wizard.featureTimeMachine
                )

                Divider()

                // Accessibility row with inline action button instead of a toggle
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc.localized("wizard.feature.accessibility"))
                            .fontWeight(.medium)
                        Text(loc.localized("wizard.feature.accessibilityDesc"))
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .font(.callout)
                    }
                    Spacer()
                    if wizard.hasAccessibilityPermissions {
                        Label(loc.localized("wizard.accessibility.granted"), systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.success(colorScheme))
                    } else {
                        Button(loc.localized("wizard.accessibility.prompt")) {
                            wizard.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Each feature row uses the same horizontal layout: fixed-width icon + (title, description) +
    /// spacer + trailing toggle. The toggle's `.labelsHidden()`-style placement on the right of an
    /// `HStack` keeps every toggle switch vertically aligned.
    private func featureRow(icon: String, title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppColors.brandAccentSecondary)
        }
        .padding(.leading, 8)
    }
}


// MARK: - Step 4: RetroAchievements Setup (conditional)

extension SetupWizardView {
    private var stepAchievementsSetup: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(loc.localized("retroAchievements.title"), systemImage: "trophy")
                    .font(.headline)

                Text("wizard.retroAchievementsDescription")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)
            }

            VStack(spacing: 8) {
                TextField(loc.localized("retroAchievements.username"), text: $wizard.achievementsUsername)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                SecureField(loc.localized("retroAchievements.password"), text: $wizard.achievementsPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField(loc.localized("retroAchievements.webApiKey"), text: $wizard.achievementsWebApiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(AppColors.cardBackgroundSubtle(colorScheme))
            .cornerRadius(8)

            HStack(spacing: 12) {
                Button(action: testRAConnection) {
                    if isRALoggingIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(loc.localized("wizard.ra.testConnection"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(wizard.achievementsUsername.isEmpty || wizard.achievementsWebApiKey.isEmpty || isRALoggingIn)

                Link(loc.localized("retroAchievements.findYourKeyAt"), destination: URL(string: "https://retroachievements.org/controlpanel.php")!)
                    .font(.callout)
                    .foregroundColor(AppColors.brandAccent)

                Spacer()

                if raLoginSuccess {
                    Label(loc.localized("wizard.ra.connected"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(AppColors.success(colorScheme))
                }
            }

            if let error = raLoginError {
                Label(raErrorMessage(error), systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(AppColors.error(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let url = error.helpURL {
                    Button(loc.localized("ra.error.openSettings")) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(loc.localized("retroAchievements.hardcoreMode"), systemImage: "shield.lefthalf.filled")
                    .font(.headline)

                Toggle(loc.localized("retroAchievements.hardcoreMode"), isOn: $wizard.achievementsHardcore)
                    .toggleStyle(.switch)
                    .tint(AppColors.brandAccentSecondary)

                Text(loc.localized("retroAchievements.hardcoreModeDescription"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)
            }
        }
    }

    private func testRAConnection() {
        Task {
            isRALoggingIn = true
            raLoginError = nil
            raLoginSuccess = false
            do {
                try await RetroAchievementsService.shared.loginWithWebApiKey(
                    username: wizard.achievementsUsername,
                    webApiKey: wizard.achievementsWebApiKey,
                    password: wizard.achievementsPassword
                )
                raLoginSuccess = true
            } catch {
                if let raError = error as? RAError {
                    raLoginError = raError
                } else {
                    raLoginError = .loginFailed(error.localizedDescription)
                }
            }
            isRALoggingIn = false
        }
    }

    private func raErrorMessage(_ error: RAError) -> String {
        let key: String
        switch error {
        case .apiKeyMissing: key = "ra.error.apiKeyMissing"
        case .networkUnreachable: key = "ra.error.networkUnreachable"
        case .networkTimeout: key = "ra.error.networkTimeout"
        case .serverError: key = "ra.error.serverError"
        case .unknownUser: key = "ra.error.unknownUser"
        case .invalidApiKey: key = "ra.error.invalidApiKey"
        case .wrongPassword: key = "ra.error.wrongPassword"
        case .accountLocked: key = "ra.error.accountLocked"
        case .loginFailed: key = "ra.error.loginFailed"
        case .gameNotFound: key = "ra.error.gameNotFound"
        case .invalidHash: key = "ra.error.invalidHash"
        }
        let translated = loc.localized(key)
        if translated == key, case .loginFailed(let msg) = error {
            return loc.localized("ra.error.loginFailedWithMessage", msg)
        }
        if translated == key, case .serverError(let code) = error {
            return String(format: loc.localized("ra.error.serverErrorWithCode"), code)
        }
        return translated
    }
}

// MARK: - Step 5: Streaming Setup (conditional)

extension SetupWizardView {
    private var stepStreamingSetup: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(loc.localized("wizard.stream.title"), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)

                Text("wizard.stream.description")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.callout)
            }

            Toggle(loc.localized("wizard.stream.enable"), isOn: $wizard.streamingEnabled)
                .toggleStyle(.switch)
                .tint(AppColors.brandAccentSecondary)

            if wizard.streamingEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    // Destination
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.localized("wizard.stream.destination"))
                            .font(.callout)
                            .fontWeight(.medium)
                        Picker(loc.localized("wizard.stream.destination"), selection: $wizard.streamingDestination) {
                            ForEach([StreamingMode.twitch, .youtube, .custom], id: \.self) { mode in
                                Text(streamingModeLabel(for: mode))
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Stream key
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.localized("wizard.stream.streamKey"))
                            .font(.callout)
                            .fontWeight(.medium)
                        SecureField(loc.localized("wizard.stream.streamKeyPlaceholder"),
                                    text: Binding<String>(
                                        get: { wizard.streamingStreamKey },
                                        set: { wizard.streamingStreamKey = $0 }
                                    ))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        HStack(spacing: 6) {
                            Text(streamKeyHint)
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                            if let url = streamKeyLinkURL {
                                Link(streamKeyLinkLabel, destination: url)
                                    .font(.caption)
                                    .foregroundColor(AppColors.brandAccent)
                            }
                        }
                    }

                    // Quality
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc.localized("wizard.stream.quality"))
                            .font(.callout)
                            .fontWeight(.medium)
                        Picker(loc.localized("wizard.stream.quality"), selection: $wizard.streamingQuality) {
                            ForEach([RecordingQuality.low, .medium, .high], id: \.self) { q in
                                Text(recordingQualityLabel(for: q))
                                    .tag(q)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(12)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(8)
            }
        }
    }

    private func streamingModeLabel(for mode: StreamingMode) -> String {
        switch mode {
        case .twitch: return "Twitch"
        case .youtube: return "YouTube"
        case .custom: return loc.localized("wizard.stream.custom")
        case .localFile: return loc.localized("settings.streaming.localFile")
        }
    }

    private var streamKeyHint: String {
        switch wizard.streamingDestination {
        case .twitch: return loc.localized("wizard.stream.keyHint.twitch")
        case .youtube: return loc.localized("wizard.stream.keyHint.youtube")
        case .custom: return loc.localized("wizard.stream.keyHint.custom")
        case .localFile: return ""
        }
    }

    private var streamKeyLinkURL: URL? {
        switch wizard.streamingDestination {
        case .twitch:  return URL(string: "https://dashboard.twitch.tv/u/__username__/settings/stream")
        case .youtube: return URL(string: "https://studio.youtube.com/channel/UC/live_streaming")
        case .custom:  return nil
        case .localFile: return nil
        }
    }

    private var streamKeyLinkLabel: String {
        switch wizard.streamingDestination {
        case .twitch:  return loc.localized("wizard.stream.openDashboard")
        case .youtube: return loc.localized("wizard.stream.openStudio")
        case .custom, .localFile: return ""
        }
    }

    private func recordingQualityLabel(for q: RecordingQuality) -> String {
        switch q {
        case .low: return loc.localized("wizard.stream.quality.low")
        case .medium: return loc.localized("wizard.stream.quality.medium")
        case .high: return loc.localized("wizard.stream.quality.high")
        case .lossless: return loc.localized("wizard.stream.quality.lossless")
        }
    }
}

// MARK: - Step 6: Completion

extension SetupWizardView {
    private var stepCompletion: some View {
        VStack(spacing: 24) {
Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 56))
            .foregroundColor(AppColors.success(colorScheme))

            Text("wizard.allSet")
                .font(.title)
                .fontWeight(.bold)

Text("wizard.completionDescription")
            .multilineTextAlignment(.center)
            .foregroundColor(AppColors.textSecondary(colorScheme))

            // Summary of configured features
            if !wizard.enabledFeaturesSummary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.localized("wizard.summary.title"))
                        .font(.callout)
                        .fontWeight(.semibold)
                    ForEach(wizard.enabledFeaturesSummary, id: \.self) { key in
                        Label(loc.localized(key), systemImage: "checkmark")
                            .font(.callout)
                            .foregroundColor(AppColors.brandAccent)
                    }
                }
                .padding(12)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(8)
            }

            if !wizard.allDetectedGames.isEmpty && library.roms.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
Text(String(format: loc.localized("wizard.scanningFolders"), wizard.libraryFolders.count))
                    .font(.callout)
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
            } else if library.roms.isEmpty && !wizard.libraryFolders.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text("wizard.scanningForGames")
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            } else if library.roms.isEmpty {
                VStack(spacing: 8) {
Image(systemName: "tray")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                Text("wizard.noGamesDetected")
                    .font(.callout)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                Text("wizard.addFolderLater")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Label(String(format: loc.localized("wizard.gamesDetected"), library.roms.count), systemImage: "gamecontroller")
                            .font(.callout)
                        Spacer()
                    }
                }
            }
        }
        .task {
            if !library.roms.isEmpty {
                wizard.updateDetectedGames(from: library.roms)
            }
        }
        .onChange(of: library.lastChangeDate) { _, _ in
            if !library.roms.isEmpty {
                Task { wizard.updateDetectedGames(from: library.roms) }
            }
        }
    }
}

// MARK: - Language Helpers

extension SetupWizardView {
    private func languageDisplayName(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "English"
        case "es": return "Español"
        case "pt": return "Português"
        default: return lang.uppercased()
        }
    }

    private func languageFlag(for lang: String) -> String {
        switch lang.lowercased() {
        case "en": return "🇺🇸"
        case "es": return "🇦🇷"
        case "pt": return "🇧🇷"
        default: return "🌐"
        }
    }
}

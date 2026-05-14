import SwiftUI
import AppKit
import GameController

struct SetupWizardView: View {
    @ObservedObject var wizard: SetupWizardState
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var categoryManager: CategoryManager
    @EnvironmentObject var loc: LocalizationManager
    
    @State private var raLoginError: String?
    @State private var isRALoggingIn: Bool = false
    
    var body: some View {
        ZStack {
            // Clean, minimal backdrop
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            // Centered wizard card — adaptive size
            VStack(spacing: 0) {
                // Simple header with step indicator
                headerBar
                
                // Content area
                ZStack {
                    switch wizard.currentStep {
                    case .getStarted: stepGetStarted
                    case .lookAndFeel: stepLookAndFeel
                    case .optionalFeatures: stepOptionalFeatures
                    case .completion: stepCompletion
                    }
                }
                .padding(32)
                
                // Navigation buttons
                bottomNavigation
            }
            .padding()
            .frame(maxWidth: 680)
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
            
            // Step progress
            HStack(spacing: 0) {
                ForEach(Array(SetupWizardState.WizardStep.allCases.enumerated()), id: \.element.id) { idx, step in
                    Circle()
                        .fill(idx <= wizard.currentStepIndex ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 8, height: 8)
                    if idx < SetupWizardState.WizardStep.allCases.count - 1 {
                        Rectangle()
                            .fill(idx < wizard.currentStepIndex ? Color.accentColor : Color.secondary.opacity(0.15))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Text(wizard.currentStep.title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Bottom Navigation
    
    private var bottomNavigation: some View {
        HStack {
            if wizard.currentStepIndex > 0 && wizard.currentStep != .completion {
                Button(loc.localized("wizard.back")) {
                    wizard.previousStep()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.leftArrow, modifiers: [])
            } else {
                Spacer()
            }

            Spacer()

            // Skip button for optional steps
            if wizard.currentStep.canSkip {
                Button(loc.localized("wizard.skip")) {
                    wizard.nextStep()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Next / Finish button
            if wizard.currentStep == .completion {
                Button(loc.localized("wizard.enterLibrary")) {
                    finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            } else if wizard.currentStep == .getStarted {
                Button(loc.localized("wizard.continue")) {
                    wizard.nextStep()
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
        wizard.hasCompletedWizard = true
        library.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        
        AppSettings.setBool("logging_enabled", value: wizard.loggingEnabled)
        AppSettings.set("display_default_shader_preset", value: wizard.selectedShaderPresetID)
        
        // Add library folders (each triggers its own scan via addPrimaryFolder)
        for folder in wizard.libraryFolders {
            library.addLibraryFolder(url: folder)
        }
        
        // Capture main actor-isolated values before entering detached task
        let downloadBezels = wizard.downloadBezels
        let downloadCheats = wizard.downloadCheats
        
        // Kick off background tasks without blocking the UI
        Task.detached(priority: .utility) {
            // Download bezels and cheats in parallel if requested
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
            
            // RetroAchievements login
            /*
            if achievementsEnabled && !achievementsUsername.isEmpty && !achievementsPassword.isEmpty {
                do {
                    let token = try await RetroAchievementsService.shared.loginWithWebApiKey(
                        username: achievementsUsername,
                        webApiKey: achievementsPassword
                    )
                    await RetroAchievementsService.shared.saveSettings(
                        username: achievementsUsername,
                        webApiKey: <#T##String#>: token
                    )
                    await RetroAchievementsService.shared.setEnabled(true)
                } catch {
                    LoggerService.info(category: "Wizard", "Achievements login failed: \(error.localizedDescription)")
                }
            }*/
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
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !wizard.libraryFolders.isEmpty {
                List {
                    ForEach(wizard.libraryFolders.indices, id: \.self) { idx in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(wizard.libraryFolders[idx].lastPathComponent)
                                    .lineLimit(1)
                                Text(wizard.libraryFolders[idx].path)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                wizard.removeLibraryFolder(at: idx)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)
                    Text("wizard.addFolderLater")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
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

// MARK: - Step 2: Look & Feel (Bezels + Shaders)

extension SetupWizardView {
    private var stepLookAndFeel: some View {
        VStack(spacing: 24) {
            // Bezels
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.localized("bezel.title"), systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                Text("wizard.bezelsDescription")
                    .foregroundColor(.secondary)
                    .font(.callout)

                Toggle(loc.localized("wizard.downloadBezelsToggle"), isOn: $wizard.downloadBezels)
                    .toggleStyle(.switch)
                    .tint(.accentColor)
            }

            Divider()

            // Shaders
            VStack(alignment: .leading, spacing: 12) {
                Label(loc.localized("wizard.defaultShader"), systemImage: "tv")
                    .font(.headline)
                Text("wizard.shaderDescription")
                    .foregroundColor(.secondary)
                    .font(.callout)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ShaderPreset.allPresets, id: \.id) { preset in
                            shaderPill(preset: preset)
                        }
                    }
                }
            }
        }
    }
    
    private func shaderPill(preset: ShaderPreset) -> some View {
        let isSelected = wizard.selectedShaderPresetID == preset.id
        return Button {
            wizard.selectedShaderPresetID = preset.id
        } label: {
            Label(preset.name, systemImage: shaderIcon(for: preset.shaderType))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .foregroundColor(isSelected ? .accentColor : .primary)
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

// MARK: - Step 3: Optional Features (Cheats + Achievements + Logging)

extension SetupWizardView {
    private var stepOptionalFeatures: some View {
        VStack(spacing: 20) {
            // Cheats
            featureToggle(
                title: loc.localized("wizard.cheatsTitle"),
                icon: "wand.and.stars",
                description: loc.localized("wizard.cheatsDescription"),
                isOn: $wizard.downloadCheats,
                detail: loc.localized("wizard.cheatsDetail")
            )

            // Achievements
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $wizard.achievementsEnabled) {
                    Label {
                        Text("retroAchievements.title")
                    } icon: {
                        Image(systemName: "trophy")
                    }
                }
                .toggleStyle(.switch)
                .tint(.accentColor)

                Text("wizard.retroAchievementsDescription")
                    .foregroundColor(.secondary)
                    .font(.callout)

                if wizard.achievementsEnabled {
                    VStack(spacing: 8) {
                        TextField(loc.localized("retroAchievements.username"), text: $wizard.achievementsUsername)
                            .textFieldStyle(.roundedBorder)
                        SecureField(loc.localized("retroAchievements.password"), text: $wizard.achievementsPassword)
                            .textFieldStyle(.roundedBorder)

                        if let error = raLoginError {
                            Label(error, systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        /*HStack(spacing: 8) {
                            Button {
                                Task {
                                    isRALoggingIn = true
                                    raLoginError = nil
                                    do {
                                        let token = try await RetroAchievementsService.shared.login(
                                            username: wizard.achievementsUsername, password: wizard.achievementsPassword)
                                        RetroAchievementsService.shared.saveSettings(username: wizard.achievementsUsername, token: token)
                                    } catch {
                                        raLoginError = error.localizedDescription
                                    }
                                    isRALoggingIn = false
                                }
                            } label: {
                                if isRALoggingIn { ProgressView().controlSize(.small) } else { Text("Test Connection") }
                            }
                            .disabled(wizard.achievementsUsername.isEmpty || wizard.achievementsPassword.isEmpty || isRALoggingIn)

                            Link("Create Account", destination: URL(string: "https://retroachievements.org")!)
                                .font(.callout)
                                .foregroundColor(.accentColor)
                        }*/
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }

            // Logging
            featureToggle(
                title: loc.localized("wizard.loggingTitle"),
                icon: "terminal",
                description: loc.localized("wizard.loggingDescription"),
                isOn: $wizard.loggingEnabled,
                detail: loc.localized("wizard.loggingDetail")
            )
        }
    }
    
    private func featureToggle(title: String, icon: String, description: String, isOn: Binding<Bool>, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                Label {
                    Text(title)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: icon)
                }
            }
            .toggleStyle(.switch)
            .tint(.accentColor)
            
            Text(description)
                .foregroundColor(.secondary)
                .font(.callout)
            
            if isOn.wrappedValue {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Step 4: Completion

extension SetupWizardView {
    private var stepCompletion: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("wizard.allSet")
                .font(.title)
                .fontWeight(.bold)

            Text("wizard.completionDescription")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if !wizard.allDetectedGames.isEmpty && library.roms.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(format: loc.localized("wizard.scanningFolders"), wizard.libraryFolders.count))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else if library.roms.isEmpty && !wizard.libraryFolders.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text("wizard.scanningForGames")
                    .foregroundColor(.secondary)
            } else if library.roms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("wizard.noGamesDetected")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("wizard.addFolderLater")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

import SwiftUI
import AppKit
import GameController

struct SetupWizardView: View {
    @ObservedObject var wizard: SetupWizardState
    @EnvironmentObject var library: ROMLibrary
    @EnvironmentObject var coreManager: CoreManager
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var categoryManager: CategoryManager
    
    @State private var isFinishing = false
    @State private var finishError: String?
    @State private var raLoginError: String?
    @State private var isRALoggingIn: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.65, saturation: 0.8, brightness: 0.15),
                         Color(hue: 0.70, saturation: 0.9, brightness: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerSection
                stepIndicator
                
                ZStack {
                    switch wizard.currentStep {
                    case .welcome: stepWelcome
                    case .gameFolders: stepGameFolders
                    case .bezels: stepBezels
                    case .cheats: stepCheats
                    case .achievements: stepAchievements
                    case .logging: stepLogging
                    case .shaders: stepShaders
                    case .controllers: stepControllers
                    case .completion: stepCompletion
                    }
                }
                .frame(minHeight: 300)
                .padding(40)
                
                bottomNavigation
            }
            .padding()
            
            if isFinishing {
                finishOverlay
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "arcade.stick")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(LinearGradient(
                    colors: [.purple, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("TruchieEmu")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.bottom, 20)
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(SetupWizardState.WizardStep.allCases.enumerated()), id: \.element.id) { idx, step in
                Circle()
                    .fill(idx <= wizard.currentStepIndex ? Color.purple : Color.white.opacity(0.15))
                    .frame(width: 8, height: 8)
                if idx < SetupWizardState.WizardStep.allCases.count - 1 {
                    Rectangle()
                        .fill(idx < wizard.currentStepIndex ? Color.purple : Color.white.opacity(0.1))
                        .frame(height: 2)
                }
            }
        }
        .frame(width: 280)
        .padding(.bottom, 24)
    }
    
    private var bottomNavigation: some View {
        HStack {
            if wizard.currentStepIndex > 0 && wizard.currentStep != .completion {
                Button("Back") {
                    wizard.previousStep()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.leftArrow, modifiers: [])
            } else {
                Spacer()
            }
            
            Spacer()
            
            if wizard.currentStep == .completion {
                Button("Enter TruchieEmu") {
                    finishSetup()
                }
                .buttonStyle(PrimaryButtonStyle(color: .purple))
                .keyboardShortcut(.return, modifiers: [])
            } else if wizard.currentStep == .gameFolders && wizard.libraryFolders.isEmpty {
                Button("Skip for now") {
                    wizard.nextStep()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.white.opacity(0.6))
            } else if wizard.currentStepIndex < wizard.totalSteps - 1 {
                Button("Continue") {
                    wizard.nextStep()
                }
                .buttonStyle(PrimaryButtonStyle(color: .purple))
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.top, 20)
    }
    
    private var finishOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.purple)
                Text("Setting up TruchieEmu...")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                if let error = finishError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
    
    private func finishSetup() {
        isFinishing = true
        finishError = nil
        
        Task {
            for folder in wizard.libraryFolders {
                if !library.libraryFolders.contains(folder) {
                    library.libraryFolders.append(folder)
                }
                await library.scanROMs(in: folder, runAutomationAfter: false)
            }
            
            library.hasCompletedOnboarding = true
            
            Task {
                await LibraryAutomationCoordinator.shared.runAfterLibraryUpdate(library: library)
                await wizard.updateDetectedGames(from: library.roms)
            }
            
            await withTaskGroup(of: Void.self) { group in
                if wizard.downloadBezels {
                    group.addTask { await wizard.downloadBezelsFromWizard() }
                }
                if wizard.downloadCheats {
                    group.addTask { await wizard.downloadCheatsFromWizard() }
                }
            }
            
            UserDefaults.standard.set(wizard.loggingEnabled, forKey: "logging_enabled")
            UserDefaults.standard.set(wizard.selectedShaderPresetID, forKey: "display_default_shader_preset")
            
            if wizard.achievementsEnabled && !wizard.achievementsUsername.isEmpty && !wizard.achievementsPassword.isEmpty {
                do {
                    let token = try await RetroAchievementsService.shared.login(
                        username: wizard.achievementsUsername,
                        password: wizard.achievementsPassword
                    )
                    RetroAchievementsService.shared.saveSettings(
                        username: wizard.achievementsUsername,
                        token: token
                    )
                    RetroAchievementsService.shared.setEnabled(true)
                } catch {
                    LoggerService.info(category: "Wizard", "Achievements login failed: \(error.localizedDescription)")
                }
            }
            
            wizard.hasCompletedWizard = true
        }
    }
}

// MARK: - Step Views

extension SetupWizardView {
    private var stepWelcome: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Label("Welcome to TruchieEmu", systemImage: "hand.wave")
                    .font(.title.weight(.bold)).foregroundColor(.white)
                Text("Your beautiful macOS emulation frontend. Let's get you set up in just a few steps.")
                    .font(.body).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 16) {
                welcomeFeature(icon: "gamecontroller", text: "Add your game libraries")
                welcomeFeature(icon: "rectangle.on.rectangle", text: "Download bezels for authentic console frames")
                welcomeFeature(icon: "wand.and.stars", text: "Grab cheats from the libretro database")
                welcomeFeature(icon: "trophy", text: "Connect RetroAchievements to track trophies")
                welcomeFeature(icon: "tv", text: "Choose your favourite CRT/display shaders")
                welcomeFeature(icon: "gamecontroller.fill", text: "Set up your controllers")
            }
            Button("Let's Get Started") { wizard.nextStep() }
                .buttonStyle(PrimaryButtonStyle(color: .purple)).padding(.top, 12)
        }
    }
    
    private func welcomeFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(.purple).frame(width: 28)
            Text(text).foregroundColor(.white.opacity(0.85))
            Spacer()
        }
    }
    
    private var stepGameFolders: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Add Your Games", systemImage: "folder.badge.gearshape")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("Select one or more folders containing your ROM files. TruchieEmu will scan them recursively and identify which console each game belongs to. Your files are only read \u{2014} nothing is moved or modified.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            if !wizard.libraryFolders.isEmpty {
                VStack(spacing: 8) {
                    ForEach(wizard.libraryFolders.indices, id: \.self) { idx in
                        HStack {
                            Image(systemName: "folder.fill").foregroundColor(.purple)
                            Text(wizard.libraryFolders[idx].lastPathComponent).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Text(wizard.libraryFolders[idx].path).font(.caption.monospaced()).foregroundColor(.white.opacity(0.4)).lineLimit(1)
                            Button { wizard.removeLibraryFolder(at: idx) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.7))
                            }.buttonStyle(.plain)
                        }.padding(10).background(Color.white.opacity(0.05)).cornerRadius(8)
                    }
                }
            }
            Button { pickFolder() } label: {
                Label("Add Folder\u{2026}", systemImage: "folder.badge.plus").frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle(color: .blue))
            if wizard.libraryFolders.isEmpty {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.white.opacity(0.5))
                    Text("You can skip this and add games later from the main window.")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }
    
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more folders containing your ROM files"
        if panel.runModal() == .OK {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let internalPrefix = appSupport.appendingPathComponent("TruchieEmu").path
            for url in panel.urls {
                guard !url.path.hasPrefix(internalPrefix) else { continue }
                wizard.addLibraryFolder(url)
            }
        }
    }
    
    private var stepBezels: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Bezels", systemImage: "rectangle.on.rectangle")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("Bezels are decorative frames that surround the game screen, giving it the look of a real television or arcade cabinet. TruchieEmu can download bezels from The Bezel Project \u{2014} a free community database.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $wizard.downloadBezels) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Bezels").font(.body.weight(.medium)).foregroundColor(.white)
                    Text("Download bezel overlays for all supported systems (~2-5 GB)").font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }.toggleStyle(.switch).tint(.purple).padding().background(Color.white.opacity(0.05)).cornerRadius(12)
            if wizard.downloadBezels {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.cyan)
                    Text("You can also download bezels for specific systems later from Settings \u{2192} Bezels.")
                        .font(.caption).foregroundColor(.white.opacity(0.6))
                }.padding(.top, 4)
            }
        }
    }
    
    private var stepCheats: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Cheats", systemImage: "wand.and.stars")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("TruchieEmu can download cheat codes from the libretro cheats database. You can enable/disable and apply individual cheats per-game while playing.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $wizard.downloadCheats) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Cheats").font(.body.weight(.medium)).foregroundColor(.white)
                    Text("Download all cheat files from the libretro database (~50 MB)").font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }.toggleStyle(.switch).tint(.purple).padding().background(Color.white.opacity(0.05)).cornerRadius(12)
            HStack(spacing: 16) {
                cheatFeature(icon: "gamecontroller", label: "Per-game cheats")
                cheatFeature(icon: "gearshape", label: "Toggle individually")
                cheatFeature(icon: "play.fill", label: "Auto-apply on launch")
            }
        }
    }
    
    private func cheatFeature(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(.purple)
                .frame(width: 32, height: 32).background(Color.purple.opacity(0.15)).cornerRadius(8)
            Text(label).font(.caption).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
    }
}

// MARK: - Steps 4-7

extension SetupWizardView {
    private var stepAchievements: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("RetroAchievements", systemImage: "trophy")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("RetroAchievements adds achievements and leaderboards to classic games. Earn trophies, compete with friends, and track your progress across thousands of retro games.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $wizard.achievementsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable RetroAchievements").font(.body.weight(.medium)).foregroundColor(.white)
                    Text("Requires a free account at retroachievements.org").font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }.toggleStyle(.switch).tint(.purple).padding().background(Color.white.opacity(0.05)).cornerRadius(12)
            if wizard.achievementsEnabled {
                VStack(spacing: 12) {
                    TextField("Username", text: $wizard.achievementsUsername).textFieldStyle(.roundedBorder).foregroundColor(.white)
                    SecureField("Password", text: $wizard.achievementsPassword).textFieldStyle(.roundedBorder).foregroundColor(.white)
                    if let error = raLoginError {
                        Label(error, systemImage: "xmark.circle.fill").font(.caption).foregroundColor(.red)
                    }
                    HStack(spacing: 12) {
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
                        }.buttonStyle(.bordered).disabled(wizard.achievementsUsername.isEmpty || wizard.achievementsPassword.isEmpty || isRALoggingIn)
                        Link("Create Account", destination: URL(string: "https://retroachievements.org")!).font(.caption).foregroundColor(.purple)
                    }
                }.padding().background(Color.white.opacity(0.05)).cornerRadius(12)
            }
        }
    }
    
    private var stepLogging: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Logging", systemImage: "terminal")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("Enable diagnostic logging to help troubleshoot issues. Logs appear in the macOS Console app (filter by 'TruchieEmu').")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $wizard.loggingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Logging").font(.body.weight(.medium)).foregroundColor(.white)
                    Text("Log core loading, game launches, shader changes, and more").font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }.toggleStyle(.switch).tint(.purple).padding().background(Color.white.opacity(0.05)).cornerRadius(12)
            if wizard.loggingEnabled {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.cyan)
                    Text("Logging has a small performance impact. Recommended only for debugging.")
                        .font(.caption).foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Shaders & Controllers

extension SetupWizardView {
    private var stepShaders: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Display & Shaders", systemImage: "tv")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("Choose a default shader preset for all games. You can change this per-game later. Shaders add visual effects like CRT scanlines, LCD grids, and smoothing.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            let presets = ShaderPreset.allPresets
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(presets, id: \.id) { preset in
                        shaderCard(preset: preset)
                    }
                }
            }.frame(maxHeight: 250)
        }
    }
    
    private func shaderCard(preset: ShaderPreset) -> some View {
        let isSelected = wizard.selectedShaderPresetID == preset.id
        return Button { wizard.selectedShaderPresetID = preset.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: shaderIcon(for: preset.shaderType)).foregroundColor(isSelected ? .white : .purple).frame(width: 24)
                    Text(preset.name).font(.subheadline.weight(.semibold)).foregroundColor(.white).lineLimit(1)
                    Spacer()
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundColor(.purple) }
                }
                Text(preset.description ?? "").font(.caption).foregroundColor(.white.opacity(0.5)).lineLimit(2)
                if !preset.recommendedSystems.isEmpty {
                    Text(preset.recommendedSystems.prefix(3).map{ $0.uppercased() }.joined(separator: ", "))
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.purple.opacity(0.8))
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.purple.opacity(0.25) : Color.white.opacity(0.03)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.purple.opacity(0.6) : Color.clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
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
    
    private var stepControllers: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Controllers", systemImage: "gamecontroller")
                    .font(.title2.weight(.semibold)).foregroundColor(.white)
                Text("Plug in your game controller now and TruchieEmu will detect it automatically. Your controller mappings are saved for each system.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 16) {
                if wizard.controllerDetected {
                    HStack(spacing: 16) {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 48)).foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Controller Detected!").font(.title3.weight(.semibold)).foregroundColor(.white)
                            Text(wizard.detectedControllerName).font(.body).foregroundColor(.white.opacity(0.6))
                            Text("\(GCController.controllers().count) controller(s) connected").font(.caption).foregroundColor(.white.opacity(0.4))
                        }
                    }.padding().background(Color.green.opacity(0.1)).cornerRadius(12)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller").font(.system(size: 48)).foregroundColor(.white.opacity(0.3))
                        Text("No Controller Detected").font(.title3.weight(.semibold)).foregroundColor(.white.opacity(0.6))
                        Text("Plug in your controller via USB or Bluetooth, then click Refresh.")
                            .font(.body).foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center)
                    }.padding().background(Color.white.opacity(0.05)).cornerRadius(12)
                }
                Button {
                    wizard.refreshControllerDetection()
                } label: {
                    Label("Refresh Controllers", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                HStack {
                    Image(systemName: "keyboard").foregroundColor(.white.opacity(0.5))
                    Text("Keyboard is always available as a fallback input device.")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }
        }.onAppear { wizard.refreshControllerDetection() }
    }
}

// MARK: - Completion Step

extension SetupWizardView {
    private var stepCompletion: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundColor(.green)
                Text("All Set!").font(.title.weight(.bold)).foregroundColor(.white)
                Text("TruchieEmu is ready. Your games are being scanned and box art is being fetched in the background.")
                    .font(.body).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            
            if !wizard.allDetectedGames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Detected Games", systemImage: "gamecontroller")
                            .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                        Text("(\(wizard.allDetectedGames.count))").font(.caption).foregroundColor(.white.opacity(0.5))
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(wizard.allDetectedGames.prefix(20)) { game in
                                WizardGameCard(gameInfo: game)
                            }
                        }.padding(.vertical, 4)
                    }
                }.padding().background(Color.white.opacity(0.05)).cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    if library.roms.isEmpty && wizard.libraryFolders.isEmpty {
                        Image(systemName: "tray").font(.system(size: 32)).foregroundColor(.white.opacity(0.3))
                        Text("No games detected yet").font(.subheadline).foregroundColor(.white.opacity(0.5))
                        Text("Add your ROM folders to get started").font(.caption).foregroundColor(.white.opacity(0.4))
                    } else if library.roms.isEmpty {
                        ProgressView().controlSize(.small)
                        Text("Scanning for games...").font(.subheadline).foregroundColor(.white.opacity(0.5))
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 32)).foregroundColor(.white.opacity(0.3))
                        Text("No box art found yet").font(.subheadline).foregroundColor(.white.opacity(0.5))
                        Text("Box art downloads automatically for known games").font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                }.padding().background(Color.white.opacity(0.03)).cornerRadius(12)
            }
        }
        .task {
            if !library.roms.isEmpty {
                await wizard.updateDetectedGames(from: library.roms)
            }
        }
        .onChange(of: library.lastChangeDate) { _ in
            if !library.roms.isEmpty {
                Task { await wizard.updateDetectedGames(from: library.roms) }
            }
        }
    }
}

// MARK: - Wizard Game Card

struct WizardGameCard: View {
    let gameInfo: SetupWizardGameInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let boxArt = gameInfo.boxArt {
                    Image(nsImage: boxArt).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 110).clipped().cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.2))
                        .frame(width: 80, height: 110).clipped()
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "gamecontroller").foregroundColor(.white.opacity(0.3)).font(.system(size: 20))
                                Text(gameInfo.systemName.prefix(3).uppercased()).font(.caption.bold()).foregroundColor(.white.opacity(0.4))
                            }
                        )
                }
            }
            Text(gameInfo.displayName).font(.caption).foregroundColor(.white.opacity(0.8))
                .lineLimit(2).frame(width: 80, alignment: .leading)
        }
    }
}

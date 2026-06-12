import Foundation
import AppKit
import SwiftUI
import SwiftData

// MARK: - LaunchPhase

enum LaunchPhase: Equatable {
    case idle
    case checkingDependencies
    case preparingConfig
    case discoveringCoreOptions
    case applyingSettings
    case loadingCore
    case startingGame
    case waitingForFrame

    var localizationKey: String {
        switch self {
        case .idle: return "game.loading"
        case .checkingDependencies: return "game.launch.checkingDependencies"
        case .preparingConfig: return "game.launch.preparingConfig"
        case .discoveringCoreOptions: return "game.launch.discoveringCoreOptions"
        case .applyingSettings: return "game.launch.applyingSettings"
        case .loadingCore: return "game.launch.loadingCore"
        case .startingGame: return "game.launch.startingGame"
        case .waitingForFrame: return "game.launch.waitingForFrame"
        }
    }
}

// MARK: - GameLauncher

// Unified game launcher that ensures ALL launch paths (double-click, launch button, save state click, CLI)
// apply the same settings consistently: shaders, core options, achievements, cheats, controls, etc.
@MainActor
class GameLauncher: ObservableObject {
    static let shared = GameLauncher()

    @Published var isLaunching = false
    @Published var currentLaunchROM: ROM?
    @Published var launchPhase: LaunchPhase = .idle
    
    // Track active game window controllers
    private var activeControllers: [UUID: StandaloneGameWindowController] = [:]
    
    private init() {}
    
    // MARK: - Launch Configuration
    
    // Complete launch configuration for a game
    @MainActor
    struct LaunchConfig {
        let rom: ROM
        let coreID: String
        let slotToLoad: Int?
        let shaderPresetID: String
        let shaderUniformOverrides: [String: Float]
        let achievementsEnabled: Bool
        let hardcoreMode: Bool
        let cheatsEnabled: Bool
        let coreOptions: [String: String]
        let autoLoad: Bool
        let autoSave: Bool
        let bezelFileName: String
        
        init(
            rom: ROM,
            coreID: String,
            slotToLoad: Int? = nil,
            shaderPresetID: String? = nil,
            shaderUniformOverrides: [String: Float] = [:],
            achievementsEnabled: Bool? = nil,
            hardcoreMode: Bool? = nil,
            cheatsEnabled: Bool? = nil,
            coreOptions: [String: String]? = nil,
            autoLoad: Bool? = nil,
            autoSave: Bool? = nil
        ) {
            LoggerService.debug(category: "GameLauncher", "Creating launch configuration for ROM: \(rom.displayName)")
            self.rom = rom
            self.coreID = coreID
            self.slotToLoad = slotToLoad
            self.shaderUniformOverrides = shaderUniformOverrides
            
             // Resolve shader preset
            let system = SystemDatabase.system(forID: rom.systemID ?? "")
            let defaultShader = system?.defaultShaderPresetID ?? ""
            let romShader = rom.settings.shaderPresetID.isEmpty ? defaultShader : rom.settings.shaderPresetID
            LoggerService.info(category: "GameLauncher", "Shader resolution: romShader=\(romShader.isEmpty ? "(empty)" : romShader), systemDefault=\(defaultShader.isEmpty ? "(empty)" : defaultShader), romSettingsShader=\(rom.settings.shaderPresetID)")
            
            self.shaderPresetID = shaderPresetID ?? romShader
            
            // Resolve achievements
            self.achievementsEnabled = achievementsEnabled ?? AppSettings.getBool("ra_enabled", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved achievements enabled: \(self.achievementsEnabled)")
            self.hardcoreMode = hardcoreMode ?? false
            LoggerService.extreme(category: "GameLauncher", "Resolved hardcore mode: \(self.hardcoreMode)")
            
            // Resolve cheats
            self.cheatsEnabled = cheatsEnabled ?? rom.settings.cheatsEnabled ?? AppSettings.getBool("cheats_enabled", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved cheats enabled: \(self.cheatsEnabled)")
            
        // Resolve core options (system-level + game-level overrides)
        let resolvedSystemID = rom.systemID ?? "default"
        self.coreOptions = coreOptions ?? {
            var result = CoreOptionsManager.shared.loadSystemOverrides(for: coreID, systemID: resolvedSystemID)
            let gameFilename = rom.filenameWithoutExtension
            if !gameFilename.isEmpty {
                let gameOverrides = CoreOptionsManager.shared.loadGameOverrides(for: coreID, systemID: resolvedSystemID, gameFilename: gameFilename)
                result.merge(gameOverrides) { _, new in new }
            }
            return result
        }()
            LoggerService.extreme(category: "GameLauncher", "Resolved core options: \(self.coreOptions)")
            
            // Resolve auto save/load
            self.autoLoad = autoLoad ?? AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved auto load: \(self.autoLoad)")
            self.autoSave = autoSave ?? AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved auto save: \(self.autoSave)")
            
            // Resolve bezel
            self.bezelFileName = rom.settings.bezelFileName
            LoggerService.extreme(category: "GameLauncher", "Resolved bezel file name: \(self.bezelFileName)")
        }
    }
    
    // MARK: - Public Launch Methods
    
    // Launch a game with all settings applied - the single unified launch point
    // - Parameters:
    //   - rom: The ROM to launch
    //   - coreID: The core to use
    //   - slotToLoad: Optional save slot to load on start
    //   - library: Reference to ROMLibrary for marking as played
    //   - completion: Called when launch is complete
    // - Returns: The window controller if launch was successful
func launchGame(
 rom inputROM: ROM,
        coreID: String,
        slotToLoad: Int? = nil,
        progressiveVersion: Int? = nil,
        library: ROMLibrary? = nil,
        shaderUniformOverrides: [String: Float] = [:],
        checkMAMEDeps: Bool = true,
        completion: ((StandaloneGameWindowController?) -> Void)? = nil
) async {
 var rom = inputROM
 // Check if already launching
        LoggerService.extreme(category: "GameLauncher", "Checking if already launching")
        guard !isLaunching else {
            LoggerService.extreme(category: "GameLauncher", "Already launching, ignoring duplicate request")
            return
        }

        // Check if another game is already running (only one CoreHost exists)
        if RunningGamesTracker.shared.isGameRunning,
           let runningName = RunningGamesTracker.shared.currentRunningGameName {
            LoggerService.info(category: "GameLauncher", "Game already running: \(runningName), requesting switch to \(rom.displayName)")
            let action = await showSwitchGameAlert(runningGameName: runningName)
            switch action {
            case .switchAndSave:
                closeAllGameWindows()
            case .switchWithoutSaving:
                for (_, controller) in activeControllers {
                    controller.skipAutoSaveOnClose = true
                }
                closeAllGameWindows()
            case .cancel:
                completion?(nil)
                return
            }
        }

        // Check if this ROM is already running
        LoggerService.extreme(category: "GameLauncher", "Checking if ROM is already running")
        if RunningGamesTracker.shared.isRunning(romPath: rom.runningKey) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            completion?(nil)
            LoggerService.extreme(category: "GameLauncher", "ROM is already running, ignoring duplicate request")
            return
        }

        // MAME dependency check
        LoggerService.extreme(category: "GameLauncher", "Checking MAME dependencies")
        if (checkMAMEDeps && MAMEDependencyService.isMAMECore(coreID)) || coreID.lowercased().contains("ppsspp") || coreID.lowercased().contains("flycast") {
            launchPhase = .checkingDependencies
        }
        if checkMAMEDeps && MAMEDependencyService.isMAMECore(coreID) {
            LoggerService.info(category: "GameLauncher", "Running MAME dependency check for \(rom.displayName) (\(coreID))")
            let checkResult = checkMAMEDependencies(rom: rom, coreID: coreID)
            switch checkResult {
            case .missingFiles(let gameName, let required, let missing, let romsDir):
                LoggerService.info(category: "GameLauncher", "MAME ROM missing files for \(gameName): \(missing.joined(separator: ", "))")
                showMAMEMissingFilesAlert(gameName: gameName, required: required, missing: missing, romsDirectory: romsDir)
                isLaunching = false
                currentLaunchROM = nil
                completion?(nil)
                return
            case .canLaunch:
                LoggerService.info(category: "GameLauncher", "MAME dependency check passed, launching \(rom.displayName)")
            }
        }

        // PPSSPP asset check
        if coreID.lowercased().contains("ppsspp") {
            if !PPSSPAssetService.shared.hasAssets {
                _ = PPSSPAssetService.shared.ensureAssetsCopied()
                if !PPSSPAssetService.shared.hasAssets {
                    let shouldDownload = await showPPSSPAssetMissingAlertAsync()
                    if shouldDownload {
                        _ = await PPSSPAssetService.shared.downloadAssets()
                    }
                }
            }
        }

        if coreID.lowercased().contains("flycast") {
            DreamcastBIOSService.shared.ensureExtracted()
        }

        if coreID.lowercased().contains("virtualjaguar") {
            JaguarBIOSService.shared.ensureExtracted()
        }

        isLaunching = true
        currentLaunchROM = rom
        launchPhase = .preparingConfig

        // Create launch configuration with all settings
        let config = LaunchConfig(
            rom: rom,
            coreID: coreID,
            slotToLoad: slotToLoad,
            shaderUniformOverrides: shaderUniformOverrides
        )
        
        let systemID = rom.systemID ?? "default"

        launchPhase = .discoveringCoreOptions
        CoreOptionsManager.shared.discoverOptionsIfNeeded(for: coreID, romPath: rom.path.path)

        LoggerService.info(category: "GameLauncher", "Launching game: \(rom.displayName)")
        LoggerService.debug(category: "GameLauncher", "ROM path: \(rom.path.path)")
        LoggerService.debug(category: "GameLauncher", "Core: \(coreID), System: \(systemID), Slot: \(slotToLoad.map { "\($0)" } ?? "none")")
        LoggerService.debug(category: "GameLauncher", "Shader: \(config.shaderPresetID), Uniform overrides: \(config.shaderUniformOverrides.count)")
        LoggerService.debug(category: "GameLauncher", "Bezel: \(config.bezelFileName.isEmpty ? "auto-match" : (config.bezelFileName == "none" ? "disabled" : config.bezelFileName))")
        LoggerService.debug(category: "GameLauncher", "Achievements: \(config.achievementsEnabled), Hardcore: \(config.hardcoreMode)")
        LoggerService.debug(category: "GameLauncher", "Cheats: \(config.cheatsEnabled), Core options: \(config.coreOptions.count) override(s)")
        LoggerService.debug(category: "GameLauncher", "Auto-load: \(config.autoLoad), Auto-save: \(config.autoSave)")
        
        // Apply all settings
        launchPhase = .applyingSettings
        applyLaunchConfiguration(config)
        
        // Mark as played
        library?.markPlayed(rom)
        
        // Create runner and window controller
        let runner = EmulatorRunner.forSystem(systemID)

 // Auto-detect RA game if achievements enabled but no match yet
 if config.achievementsEnabled, (rom.raGameId == nil || rom.raGameId ?? 0 == 0) {
     // Skip RA sync if system is not supported by RetroAchievements
     let raConsoleID = RetroAchievementsService.shared.mapSystemIDToRAConsoleID(systemID)
     if raConsoleID > 0 {
         let previousMatchStatus = rom.raMatchStatus

         await RetroAchievementsService.shared.syncROMWithRA(rom: rom)

         let context = SwiftDataContainer.shared.mainContext
         let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate<ROMEntry> { $0.id == rom.id })
         if let entry = try? context.fetch(descriptor).first {
             let updatedRAGameId = entry.raGameId
             let updatedRAMatchStatus = entry.raMatchStatus
             rom.raGameId = updatedRAGameId
             rom.raMatchStatus = updatedRAMatchStatus

             let loc = LocalizationManager.shared

             if let updatedId = updatedRAGameId, updatedId > 0 {
                 var updated = rom
                 library?.updateROM(updated)
                 LoggerService.info(category: "GameLauncher", "Auto-detected RA game: \(rom.displayName) → raGameId=\(updatedId)")

                 // Notify on first successful match (transition from failure)
                 if let prev = previousMatchStatus, prev != "matched" {
                     NotificationHistoryManager.shared.post(
                         icon: "trophy",
                         title: loc.localized("raHash.notificationMatchTitle"),
                         subtitle: loc.localized("raHash.notificationMatchBody")
                             .replacingOccurrences(of: "{title}", with: rom.displayName)
                             .replacingOccurrences(of: "{system}", with: systemID)
                     )
                     NotificationService.shared.sendNotification(
                         title: loc.localized("raHash.notificationMatchTitle"),
                         body: loc.localized("raHash.notificationMatchBody")
                             .replacingOccurrences(of: "{title}", with: rom.displayName)
                             .replacingOccurrences(of: "{system}", with: systemID)
                     )
                     LoggerService.info(category: "GameLauncher", "RA auto-detect: \(rom.displayName) matched successfully")
                 }
             } else if let matchStatus = updatedRAMatchStatus, matchStatus != previousMatchStatus {
                 // Only notify on status changes to avoid duplicate notifications
                 if matchStatus == "not_supported" {
                     NotificationHistoryManager.shared.post(
                         icon: "magnifyingglass",
                         title: loc.localized("raHash.notificationNoMatchTitle"),
                         subtitle: loc.localized("raHash.pillNotFoundSubtitle")
                             .replacingOccurrences(of: "{title}", with: rom.displayName)
                             .replacingOccurrences(of: "{system}", with: systemID),
                         actionLabel: loc.localized("raHash.requestOnRA"),
                         actionType: "openURL",
                         actionPayload: OpenURLActionPayload(url: "https://retroachievements.org/viewtopic.php?t=15027")
                     )
                     NotificationService.shared.sendNotification(
                         title: loc.localized("raHash.notificationNoMatchTitle"),
                         body: loc.localized("raHash.notificationNoMatchBody")
                             .replacingOccurrences(of: "{title}", with: rom.displayName)
                             .replacingOccurrences(of: "{system}", with: systemID)
                     )
                     LoggerService.info(category: "GameLauncher", "RA auto-detect: \(rom.displayName) not found in RA database")
                 } else if matchStatus.hasPrefix("mismatch") {
                     NotificationHistoryManager.shared.post(
                         icon: "exclamationmark.triangle",
                         title: loc.localized("raHash.notificationMismatchTitle"),
                         subtitle: loc.localized("raHash.pillMismatchSubtitle")
                             .replacingOccurrences(of: "{title}", with: rom.displayName)
                             .replacingOccurrences(of: "{system}", with: systemID),
                         actionLabel: loc.localized("raHash.viewOnRetroAchievements"),
                         actionType: "openURL",
                         actionPayload: OpenURLActionPayload(url: "https://retroachievements.org/game/\(updatedRAGameId ?? 0)")
                     )
                     NotificationService.shared.sendNotification(
                         title: loc.localized("raHash.notificationMismatchTitle"),
                         body: loc.localized("raHash.notificationMismatchBody")
                             .replacingOccurrences(of: "{title}", with: rom.displayName)
                             .replacingOccurrences(of: "{system}", with: systemID)
                     )
                     LoggerService.info(category: "GameLauncher", "RA auto-detect: \(rom.displayName) hash mismatch in RA database")
                 }
             }
         }
     } else {
         LoggerService.debug(category: "GameLauncher", "Skipping RA auto-detect: \(systemID) not supported by RA")
     }
 }

 // Pre-load cached achievements for rcheevos memory detection
 if config.achievementsEnabled {
 if let raGameId = rom.raGameId, raGameId > 0 {
 if let username = RetroAchievementsService.shared.username {
                if let patchTriggers = await RetroAchievementsService.shared.fetchPatchData(gameID: raGameId), !patchTriggers.isEmpty {
                    LoggerService.info(category: "GameLauncher", "Got \(patchTriggers.count) unhashed triggers from patch API for game \(raGameId)")
                } else {
                    LoggerService.info(category: "GameLauncher", "No patch data available for game \(raGameId), will use cached MemAddr triggers")
                }

                // Also fetch patch data for parent game (subset games need parent's
                // unhashed triggers — the cached JSON has hashed MemAddr values)
                if let parentID = RetroAchievementsService.shared.parentGameIDForCache(gameID: raGameId) {
                    if let parentPatchTriggers = await RetroAchievementsService.shared.fetchPatchData(gameID: parentID), !parentPatchTriggers.isEmpty {
                        LoggerService.info(category: "GameLauncher", "Got \(parentPatchTriggers.count) unhashed triggers from patch API for parent game \(parentID)")
                    } else {
                        LoggerService.info(category: "GameLauncher", "No patch data available for parent game \(parentID)")
                    }
                }

                if let achievements = RetroAchievementsService.shared.loadCachedAchievements(gameID: raGameId, username: username) {
                    runner.rcheevosAchievements = achievements
                    runner.rcheevosRichPresenceScript = RetroAchievementsService.shared.loadRichPresenceScript(gameID: raGameId) ?? RetroAchievementsService.shared.loadRichPresenceScript(gameID: RetroAchievementsService.shared.parentGameIDForCache(gameID: raGameId) ?? 0)
                    let withTriggers = achievements.filter { $0.trigger != nil && !$0.trigger!.isEmpty }
                    LoggerService.info(category: "GameLauncher", "Loaded \(achievements.count) cached achievements (\(withTriggers.count) with triggers)")

                    // Set currentGame with actual achievement data so unlock
                    // notifications show correct title/badge/points
                    RetroAchievementsService.shared.currentGame = RAGameInfo(
                        id: raGameId,
                        title: rom.displayName,
                        consoleName: "",
                        consoleID: 0,
                        achievements: achievements,
                        totalPoints: achievements.reduce(0) { $0 + $1.points },
                        parentGameID: RetroAchievementsService.shared.parentGameIDForCache(gameID: raGameId)
                    )
                } else {
                    LoggerService.info(category: "GameLauncher", "No cached achievements found for gameID=\(raGameId)")

                    RetroAchievementsService.shared.currentGame = RAGameInfo(
                        id: raGameId,
                        title: rom.displayName,
                        consoleName: "",
                        consoleID: 0,
                        achievements: [],
                        totalPoints: 0,
                        parentGameID: RetroAchievementsService.shared.parentGameIDForCache(gameID: raGameId)
                    )
                }
            } else {
                LoggerService.info(category: "GameLauncher", "RA enabled but no username - skipping rcheevos")
            }
        } else {
            LoggerService.info(category: "GameLauncher", "RA enabled but rom.raGameId=\(rom.raGameId as Any) - skipping rcheevos")
        }
    }

        let controller = StandaloneGameWindowController(runner: runner)
        controller.library = library
        controller.cheatsEnabled = config.cheatsEnabled
        
        // Track the controller
        activeControllers[rom.id] = controller

        // Launch the game (window will be shown by controller when ready)
        controller.launch(rom: rom, coreID: coreID, slotToLoad: slotToLoad, progressiveVersion: progressiveVersion, shaderUniformOverrides: config.shaderUniformOverrides)

        // Cleanup
        isLaunching = false
        currentLaunchROM = nil

        LoggerService.debug(category: "GameLauncher", "Launch complete: \(rom.displayName)")
        completion?(controller)
    }
    
    // MARK: - Settings Application
    
    // Apply all launch settings before the game starts
    private func applyLaunchConfiguration(_ config: LaunchConfig) {
        // 1. Apply shader preset - only if different from current to avoid resetting uniforms
        let currentPresetID = ShaderManager.shared.activePreset.id
        if !config.shaderPresetID.isEmpty {
            // Check built-in presets first
            if let preset = ShaderPreset.preset(id: config.shaderPresetID) {
                if config.shaderPresetID != currentPresetID {
                    ShaderManager.shared.activatePreset(preset)
                    LoggerService.debug(category: "GameLauncher", "Activated shader: \(preset.name)")
                } else {
                    LoggerService.debug(category: "GameLauncher", "Shader already active: \(preset.name)")
                }
            } else {
                // Check saved custom presets (by UUID string)
                if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == config.shaderPresetID }) {
                    ShaderManager.shared.activatePresetWithOverrides(presetID: savedPreset.basePresetID, overrides: savedPreset.uniformValues)
                    LoggerService.debug(category: "GameLauncher", "Activated custom shader: \(savedPreset.name)")
                } else {
                    // Preset not found, reset to default
                    ShaderManager.shared.resetToDefault()
                    LoggerService.debug(category: "GameLauncher", "Shader not found, reset to default")
                }
            }
        } else {
            // If no shader is specified, we must explicitly reset the manager to prevent "leaking" the last used shader
            ShaderManager.shared.resetToDefault()
            LoggerService.debug(category: "GameLauncher", "Reset shader to default (no preset specified)")
        }

        
        // 1.5. Apply shader uniform overrides (after preset activation to override defaults)
        if !config.shaderUniformOverrides.isEmpty {
            for (name, value) in config.shaderUniformOverrides {
                ShaderManager.shared.updateUniform(name, value: value)
            }
        }

        // 3. Apply auto-load/save preferences
        AppSettings.setBool("saveState_autoLoadOnStart", value: config.autoLoad)
        AppSettings.setBool("saveState_autoSaveOnExit", value: config.autoSave)
        
        // 4. Apply achievements setting
        AppSettings.setBool("ra_enabled", value: config.achievementsEnabled)
        
        // 5. Apply hardcore mode
        if config.hardcoreMode != HardcoreModeManager.shared.isHardcoreActive {
            HardcoreModeManager.shared.isHardcoreActive = config.hardcoreMode
        }
    }

    // MARK: - MAME Missing Files Alert
    
    // Show an alert when MAME ROM files are missing.
    private func showMAMEMissingFilesAlert(gameName: String, required: [String], missing: [String], romsDirectory: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Missing ROM Files"
        alert.informativeText = "\"\(gameName)\" requires additional ROM files to run.\n\nRequired: \(required.joined(separator: ", "))\n\nMissing: \(missing.joined(separator: ", "))"
        LoggerService.error(category: "GameLauncher", "Missing ROM files for \(gameName): \(missing.joined(separator: ", "))")
        
        // Add buttons
        alert.addButton(withTitle: "Copy Missing Files")
        alert.addButton(withTitle: "Open ROMs Folder")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Copy missing files to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(missing.joined(separator: "\n"), forType: .string)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(romsDirectory)
        }
    }
    
    // MARK: - PPSSPP Asset Alert
    
    // Show an alert when PPSSPP assets are missing.
    // Returns true to download, false to skip or cancel
    private func showPPSSPAssetMissingAlertAsync() async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PPSSPP Assets Missing"
        alert.informativeText = "PPSSPP requires asset files to run games.\n\nThese include UI textures, fonts, and language files.\n\nWould you like to download them now?"
        LoggerService.warning(category: "GameLauncher", "PPSSPP assets missing, prompting user")
        
        alert.addButton(withTitle: "Download Assets")
        alert.addButton(withTitle: "Continue Without Assets")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            LoggerService.info(category: "GameLauncher", "User requested PPSSPP asset download")
            return true
        } else if response == .alertSecondButtonReturn {
            LoggerService.warning(category: "GameLauncher", "User chose to continue without PPSSPP assets")
            return false
        } else {
            LoggerService.info(category: "GameLauncher", "User cancelled PPSSPP launch")
            return false
        }
    }

    // MARK: - Switch Game Alert

    enum SwitchGameAction {
        case switchAndSave
        case switchWithoutSaving
        case cancel
    }

    private func showSwitchGameAlert(runningGameName: String) async -> SwitchGameAction {
        let loc = LocalizationManager.shared
        let autoSaveEnabled = AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = loc.localized("game.alreadyRunning.title")
        alert.informativeText = String(
            format: loc.localized("game.alreadyRunning.message"),
            runningGameName
        )

        if autoSaveEnabled {
            alert.informativeText += "\n\n" + String(
                format: loc.localized("game.alreadyRunning.saveInfo"),
                runningGameName
            )
            alert.addButton(withTitle: loc.localized("game.alreadyRunning.switchAndSave"))
            alert.addButton(withTitle: loc.localized("game.alreadyRunning.switchWithoutSaving"))
            alert.addButton(withTitle: loc.localized("game.alreadyRunning.cancel"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return .switchAndSave
            } else if response == .alertSecondButtonReturn {
                return .switchWithoutSaving
            } else {
                return .cancel
            }
        } else {
            alert.informativeText += "\n\n" + String(
                format: loc.localized("game.alreadyRunning.noSaveInfo"),
                runningGameName
            )
            alert.addButton(withTitle: loc.localized("game.alreadyRunning.switch"))
            alert.addButton(withTitle: loc.localized("game.alreadyRunning.cancel"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return .switchAndSave
            } else {
                return .cancel
            }
        }
    }

    // MARK: - Cleanup
    
    // Remove a controller from tracking when its window closes
    func removeController(for romID: UUID) {
        activeControllers.removeValue(forKey: romID)
    }

    // Expose active controllers for crash recovery (XPC connection loss)
    func allActiveControllers() -> [StandaloneGameWindowController] {
        Array(activeControllers.values)
    }

    func closeAllGameWindows() {
        // Detach SwiftUI views first while all objects are still alive,
        // preventing use-after-free during view graph teardown
        for (_, controller) in activeControllers {
            controller.detachSwiftUI()
        }
        for (_, controller) in activeControllers {
            controller.close()
        }
        activeControllers.removeAll()
    }
    
    // Check if a game is currently being launched
    func isLaunchingGame(romID: UUID) -> Bool {
        return currentLaunchROM?.id == romID
    }
}

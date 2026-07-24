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
            #if LOG_DEBUG
            LoggerService.debug(category: "GameLauncher", "Creating launch configuration for ROM: \(rom.displayName)")
            #endif
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
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved achievements enabled: \(self.achievementsEnabled)")
            #endif
            self.hardcoreMode = hardcoreMode ?? HardcoreModeManager.shared.isHardcoreActive(for: rom)
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved hardcore mode: \(self.hardcoreMode)")
            #endif
            
            // Resolve cheats
            self.cheatsEnabled = cheatsEnabled ?? rom.settings.cheatsEnabled ?? AppSettings.getBool("cheats_enabled", defaultValue: false)
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved cheats enabled: \(self.cheatsEnabled)")
            #endif
            
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
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved core options: \(self.coreOptions)")
            #endif
            
            // Resolve auto save/load
            self.autoLoad = autoLoad ?? AppSettings.getBool("saveState_autoLoadOnStart", defaultValue: false)
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved auto load: \(self.autoLoad)")
            #endif
            self.autoSave = autoSave ?? AppSettings.getBool("saveState_autoSaveOnExit", defaultValue: false)
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved auto save: \(self.autoSave)")
            #endif
            
            // Resolve bezel
            self.bezelFileName = rom.settings.bezelFileName
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Resolved bezel file name: \(self.bezelFileName)")
            #endif
        }
    }
    
    // MARK: - Public Launch Methods
    
    // Launch a game with all settings applied - the single unified launch point
    // - Parameters:
    //   - rom: The ROM to launch
    //   - coreID: The core to use
    //   - slotToLoad: Optional save slot to load on start
    //   - disableAutoLoadOnStart: Per-launch override that forces the auto-load
    //     step off, even when the user's `saveState_autoLoadOnStart` preference
    //     is enabled. Used by TV-mode's "Play from start" affordance (Y) so a
    //     single press can bypass global auto-load without clobbering the
    //     user's setting. The runner's auto-load checks consult this flag
    //     before falling back to the AppSettings value.
    //   - library: Reference to ROMLibrary for marking as played
    //   - completion: Called when launch is complete
    // - Returns: The window controller if launch was successful
func launchGame(
 rom inputROM: ROM,
        coreID: String,
        slotToLoad: Int? = nil,
        progressiveVersion: Int? = nil,
        disableAutoLoadOnStart: Bool = false,
        library: ROMLibrary? = nil,
        shaderUniformOverrides: [String: Float] = [:],
        checkMAMEDeps: Bool = true,
        completion: ((StandaloneGameWindowController?) -> Void)? = nil
) async {
 var rom = inputROM
 // Check if already launching
        #if LOG_EXTREME
        LoggerService.extreme(category: "GameLauncher", "Checking if already launching")
        #endif
        guard !isLaunching else {
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "Already launching, ignoring duplicate request")
            #endif
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
        #if LOG_EXTREME
        LoggerService.extreme(category: "GameLauncher", "Checking if ROM is already running")
        #endif
        if RunningGamesTracker.shared.isRunning(romPath: rom.runningKey) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            completion?(nil)
            #if LOG_EXTREME
            LoggerService.extreme(category: "GameLauncher", "ROM is already running, ignoring duplicate request")
            #endif
            return
        }

        // MAME dependency check
        #if LOG_EXTREME
        LoggerService.extreme(category: "GameLauncher", "Checking MAME dependencies")
        #endif
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
                    if ProcessInfo.processInfo.arguments.contains("--headless") {
                        _ = await PPSSPAssetService.shared.downloadAssets()
                    } else {
                        switch await PPSSPAssetService.shared.requestAssetDownloadSheet() {
                        case .downloaded, .skipped:
                            break
                        case .cancelled:
                            isLaunching = false
                            currentLaunchROM = nil
                            completion?(nil)
                            return
                        }
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
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "ROM path: \(rom.path.path)")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Core: \(coreID), System: \(systemID), Slot: \(slotToLoad.map { "\($0)" } ?? "none")")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Shader: \(config.shaderPresetID), Uniform overrides: \(config.shaderUniformOverrides.count)")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Bezel: \(config.bezelFileName.isEmpty ? "auto-match" : (config.bezelFileName == "none" ? "disabled" : config.bezelFileName))")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Achievements: \(config.achievementsEnabled), Hardcore: \(config.hardcoreMode)")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Cheats: \(config.cheatsEnabled), Core options: \(config.coreOptions.count) override(s)")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Auto-load: \(config.autoLoad), Auto-save: \(config.autoSave)")
        #endif
        
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
                 let updated = rom
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
         #if LOG_DEBUG
         LoggerService.debug(category: "GameLauncher", "Skipping RA auto-detect: \(systemID) not supported by RA")
         #endif
     }
 }

 // Pre-load cached achievements for rcheevos memory detection
    if config.achievementsEnabled {
        if let raGameId = rom.raGameId, raGameId > 0, rom.raMatchStatus == "matched" {
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

                    // Achievements loaded successfully at runtime — upgrade match status to "matched"
                    // so the library UI reflects that the game is properly identified, even when
                    // the initial hash-based or name-based lookup was inconclusive (e.g. .cdi files).
                    if rom.raMatchStatus != "matched" {
                        rom.raMatchStatus = "matched"
                        let ctx = SwiftDataContainer.shared.mainContext
                        let desc = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.id == rom.id })
                        if let entry = try? ctx.fetch(desc).first {
                            entry.raMatchStatus = "matched"
                            try? ctx.save()
                        }
                    }
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

        // Hand the runner to the rolling-buffer service so chunk size decisions
        // can match a manual record (display vs. core resolution, DAR
        // letterboxing) and so the buffer can start capturing once the user
        // has enabled it (rather than burning 60s of black before any game
        // window opens).
        RollingVideoBufferService.shared.activeRunner = runner
        RollingVideoBufferService.shared.didAssignActiveRunner()

        // Launch the game (window will be shown by controller when ready)
        controller.launch(rom: rom, coreID: coreID, slotToLoad: slotToLoad, progressiveVersion: progressiveVersion, disableAutoLoadOnStart: disableAutoLoadOnStart, shaderUniformOverrides: config.shaderUniformOverrides)

        // Cleanup
        isLaunching = false
        currentLaunchROM = nil

        #if LOG_DEBUG
        LoggerService.debug(category: "GameLauncher", "Launch complete: \(rom.displayName)")
        #endif
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
                    #if LOG_DEBUG
                    LoggerService.debug(category: "GameLauncher", "Activated shader: \(preset.name)")
                    #endif
                } else {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "GameLauncher", "Shader already active: \(preset.name)")
                    #endif
                }
            } else {
                // Check saved custom presets (by UUID string)
                if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == config.shaderPresetID }) {
                    ShaderManager.shared.activateSavedPreset(savedPreset)
                    #if LOG_DEBUG
                    LoggerService.debug(category: "GameLauncher", "Activated custom shader: \(savedPreset.name)")
                    #endif
                } else if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == config.shaderPresetID }) {
                    ShaderManager.shared.activateSlangPreset(slangPreset, overrides: config.shaderUniformOverrides)
                    #if LOG_DEBUG
                    LoggerService.debug(category: "GameLauncher", "Activated slang shader: \(slangPreset.name)")
                    #endif
                } else {
                    // Preset not found, reset to default
                    ShaderManager.shared.resetToDefault()
                    #if LOG_DEBUG
                    LoggerService.debug(category: "GameLauncher", "Shader not found, reset to default")
                    #endif
                }
            }
        } else {
            // If no shader is specified, we must explicitly reset the manager to prevent "leaking" the last used shader
            ShaderManager.shared.resetToDefault()
            #if LOG_DEBUG
            LoggerService.debug(category: "GameLauncher", "Reset shader to default (no preset specified)")
            #endif
        }

        
        // 1.5. Apply shader uniform overrides after preset activation (override saved/defaults).
        // Slang chains route through the librashader filter chain; Metal presets use the
        // in-house ShaderParameterStore.
        if !config.shaderUniformOverrides.isEmpty {
            if ShaderManager.shared.activeSlangPreset != nil {
                for (name, value) in config.shaderUniformOverrides {
                    SlangCompilerService.shared.setParameter(name: name, value: value)
                }
            } else {
                for (name, value) in config.shaderUniformOverrides {
                    ShaderManager.shared.updateUniform(name, value: value)
                }
            }
        }

        // 3. Apply auto-load/save preferences
        AppSettings.setBool("saveState_autoLoadOnStart", value: config.autoLoad)
        AppSettings.setBool("saveState_autoSaveOnExit", value: config.autoSave)
        
        // 4. Apply achievements setting
        AppSettings.setBool("ra_enabled", value: config.achievementsEnabled)
        
        // 5. Apply hardcore mode (snapshot/restore handled by HardcoreModeManager)
        let systemID = config.rom.systemID ?? "default"
        HardcoreModeManager.shared.syncState(rom: config.rom, coreID: config.coreID, systemID: systemID)
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
        if let controller = activeControllers[romID],
           RollingVideoBufferService.shared.activeRunner === controller.runner {
            RollingVideoBufferService.shared.activeRunner = nil
            // If the buffer was rolling, stop now that the game window is
            // gone so we don't keep feeding it black frames.
            RollingVideoBufferService.shared.stopRollingForNoRunner()
        }
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

    /// Close the running game windows for the given ROM ids (e.g. when those
    /// ROMs are removed from the library). Detaches SwiftUI before closing to
    /// avoid use-after-free during teardown.
    @MainActor func closeGameWindows(for romIDs: Set<UUID>) {
        guard !romIDs.isEmpty else { return }
        for (romID, controller) in activeControllers where romIDs.contains(romID) {
            controller.detachSwiftUI()
            controller.close()
        }
    }
    
    // Check if a game is currently being launched
    func isLaunchingGame(romID: UUID) -> Bool {
        return currentLaunchROM?.id == romID
    }
}

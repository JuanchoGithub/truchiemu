import Foundation
import AppKit
import SwiftUI

// MARK: - GameLauncher

/// Unified game launcher that ensures ALL launch paths (double-click, launch button, save state click, CLI)
/// apply the same settings consistently: shaders, core options, achievements, cheats, controls, etc.
@MainActor
class GameLauncher: ObservableObject {
    static let shared = GameLauncher()
    
    @Published var isLaunching = false
    @Published var currentLaunchROM: ROM?
    
    // Track active game window controllers
    private var activeControllers: [UUID: StandaloneGameWindowController] = [:]
    
    private init() {}
    
    // MARK: - Launch Configuration
    
    /// Complete launch configuration for a game
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
            self.rom = rom
            self.coreID = coreID
            self.slotToLoad = slotToLoad
            self.shaderUniformOverrides = shaderUniformOverrides
            
            // Resolve shader preset
            let romShader = rom.settings.shaderPresetID.isEmpty ? "builtin-crt-classic" : rom.settings.shaderPresetID
            self.shaderPresetID = shaderPresetID ?? romShader
            
            // Resolve achievements
            self.achievementsEnabled = achievementsEnabled ?? UserDefaults.standard.bool(forKey: "achievements_enabled")
            self.hardcoreMode = hardcoreMode ?? false
            
            // Resolve cheats
            self.cheatsEnabled = cheatsEnabled ?? UserDefaults.standard.bool(forKey: "cheats_enabled")
            
            // Resolve core options
            self.coreOptions = coreOptions ?? CoreOptionsManager.shared.loadUserOverrides(for: coreID)
            
            // Resolve auto save/load
            self.autoLoad = autoLoad ?? UserDefaults.standard.bool(forKey: "auto_load_on_start")
            self.autoSave = autoSave ?? UserDefaults.standard.bool(forKey: "auto_save_on_exit")
            
            // Resolve bezel
            self.bezelFileName = rom.settings.bezelFileName
        }
    }
    
    // MARK: - Public Launch Methods
    
    /// Launch a game with all settings applied - the single unified launch point
    /// - Parameters:
    ///   - rom: The ROM to launch
    ///   - coreID: The core to use
    ///   - slotToLoad: Optional save slot to load on start
    ///   - library: Reference to ROMLibrary for marking as played
    ///   - completion: Called when launch is complete
    /// - Returns: The window controller if launch was successful
    @discardableResult
    func launchGame(
        rom: ROM,
        coreID: String,
        slotToLoad: Int? = nil,
        library: ROMLibrary? = nil,
        shaderUniformOverrides: [String: Float] = [:],
        completion: ((StandaloneGameWindowController?) -> Void)? = nil
    ) -> StandaloneGameWindowController? {
        // Check if already launching
        guard !isLaunching else {
            LoggerService.debug(category: "GameLauncher", "Already launching, ignoring duplicate request")
            return nil
        }
        
        // Check if this ROM is already running
        if RunningGamesTracker.shared.isRunning(romPath: rom.path.path) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            completion?(nil)
            return nil
        }
        
        isLaunching = true
        currentLaunchROM = rom
        
        // Create launch configuration with all settings
        let config = LaunchConfig(
            rom: rom,
            coreID: coreID,
            slotToLoad: slotToLoad,
            shaderUniformOverrides: shaderUniformOverrides
        )
        
        let systemID = rom.systemID ?? "default"
        
        LoggerService.info(category: "GameLauncher", "Launching game: \(rom.displayName)")
        LoggerService.info(category: "GameLauncher", "ROM path: \(rom.path.path)")
        LoggerService.info(category: "GameLauncher", "Core: \(coreID), System: \(systemID), Slot: \(slotToLoad.map { "\($0)" } ?? "none")")
        LoggerService.info(category: "GameLauncher", "Shader: \(config.shaderPresetID), Uniform overrides: \(config.shaderUniformOverrides.count)")
        LoggerService.info(category: "GameLauncher", "Bezel: \(config.bezelFileName.isEmpty ? "auto-match" : (config.bezelFileName == "none" ? "disabled" : config.bezelFileName))")
        LoggerService.info(category: "GameLauncher", "Achievements: \(config.achievementsEnabled), Hardcore: \(config.hardcoreMode)")
        LoggerService.info(category: "GameLauncher", "Cheats: \(config.cheatsEnabled), Core options: \(config.coreOptions.count) override(s)")
        LoggerService.info(category: "GameLauncher", "Auto-load: \(config.autoLoad), Auto-save: \(config.autoSave)")
        
        // Apply all settings
        applyLaunchConfiguration(config)
        
        // Mark as played
        library?.markPlayed(rom)
        
        // Create runner and window controller
        let runner = EmulatorRunner.forSystem(systemID)
        let controller = StandaloneGameWindowController(runner: runner)
        
        // Track the controller
        activeControllers[rom.id] = controller
        
        // Launch the game
        controller.launch(rom: rom, coreID: coreID, slotToLoad: slotToLoad)
        
        // Bring window to front
        if let window = controller.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        
        // Cleanup
        isLaunching = false
        currentLaunchROM = nil
        
        LoggerService.info(category: "GameLauncher", "Launch complete: \(rom.displayName)")
        completion?(controller)
        return controller
    }
    
    // MARK: - Settings Application
    
    /// Apply all launch settings before the game starts
    private func applyLaunchConfiguration(_ config: LaunchConfig) {
        // 1. Apply shader preset
        if let preset = ShaderPreset.preset(id: config.shaderPresetID) {
            ShaderManager.shared.activatePreset(preset)
            LoggerService.debug(category: "GameLauncher", "Activated shader: \(preset.name)")
        }
        
        // 1.5. Apply shader uniform overrides (after preset activation to override defaults)
        if !config.shaderUniformOverrides.isEmpty {
            for (name, value) in config.shaderUniformOverrides {
                ShaderManager.shared.updateUniform(name, value: value)
            }
            LoggerService.debug(category: "GameLauncher", "Applied \(config.shaderUniformOverrides.count) shader uniform override(s): \(config.shaderUniformOverrides)")
        }
        
        // 2. Apply core options (persisted overrides are loaded automatically by the bridge)
        if !config.coreOptions.isEmpty {
            CoreOptionsManager.shared.saveOverride(for: config.coreID, values: config.coreOptions)
            LoggerService.debug(category: "GameLauncher", "Applied \(config.coreOptions.count) core option(s)")
        }
        
        // 3. Apply auto-load/save preferences
        UserDefaults.standard.set(config.autoLoad, forKey: "auto_load_on_start")
        UserDefaults.standard.set(config.autoSave, forKey: "auto_save_on_exit")
        
        // 4. Apply achievements setting
        UserDefaults.standard.set(config.achievementsEnabled, forKey: "achievements_enabled")
        
        // 5. Apply hardcore mode
        if config.hardcoreMode != HardcoreModeManager.shared.isHardcoreActive {
            HardcoreModeManager.shared.isHardcoreActive = config.hardcoreMode
        }
        
        // 6. Apply cheats setting
        UserDefaults.standard.set(config.cheatsEnabled, forKey: "cheats_enabled")
    }
    
    // MARK: - Cleanup
    
    /// Remove a controller from tracking when its window closes
    func removeController(for romID: UUID) {
        activeControllers.removeValue(forKey: romID)
    }
    
    /// Check if a game is currently being launched
    func isLaunchingGame(romID: UUID) -> Bool {
        return currentLaunchROM?.id == romID
    }
}
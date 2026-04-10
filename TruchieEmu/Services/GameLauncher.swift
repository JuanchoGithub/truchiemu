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
            LoggerService.debug(category: "GameLauncher", "Creating launch configuration for ROM: \(rom.displayName)")
            self.rom = rom
            self.coreID = coreID
            self.slotToLoad = slotToLoad
            self.shaderUniformOverrides = shaderUniformOverrides
            
            // Resolve shader preset
            let romShader = rom.settings.shaderPresetID.isEmpty ? "builtin-crt-classic" : rom.settings.shaderPresetID
            LoggerService.extreme(category: "GameLauncher", "Resolved shader preset: \(romShader)")
            self.shaderPresetID = shaderPresetID ?? romShader
            
            // Resolve achievements
            self.achievementsEnabled = achievementsEnabled ?? AppSettings.getBool("achievements_enabled", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved achievements enabled: \(self.achievementsEnabled)")
            self.hardcoreMode = hardcoreMode ?? false
            LoggerService.extreme(category: "GameLauncher", "Resolved hardcore mode: \(self.hardcoreMode)")
            
            // Resolve cheats
            self.cheatsEnabled = cheatsEnabled ?? AppSettings.getBool("cheats_enabled", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved cheats enabled: \(self.cheatsEnabled)")
            
            // Resolve core options
            self.coreOptions = coreOptions ?? CoreOptionsManager.shared.loadUserOverrides(for: coreID)
            LoggerService.extreme(category: "GameLauncher", "Resolved core options: \(self.coreOptions)")
            
            // Resolve auto save/load
            self.autoLoad = autoLoad ?? AppSettings.getBool("auto_load_on_start", defaultValue: false)
            LoggerService.extreme(category: "GameLauncher", "Resolved auto load: \(self.autoLoad)")
            self.autoSave = autoSave ?? AppSettings.getBool("auto_save_on_exit", defaultValue: true)
            LoggerService.extreme(category: "GameLauncher", "Resolved auto save: \(self.autoSave)")
            
            // Resolve bezel
            self.bezelFileName = rom.settings.bezelFileName
            LoggerService.extreme(category: "GameLauncher", "Resolved bezel file name: \(self.bezelFileName)")
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
        checkMAMEDeps: Bool = true,
        completion: ((StandaloneGameWindowController?) -> Void)? = nil
    ) -> StandaloneGameWindowController? {
        // Check if already launching
        LoggerService.extreme(category: "GameLauncher", "Checking if already launching")
        guard !isLaunching else {
            LoggerService.extreme(category: "GameLauncher", "Already launching, ignoring duplicate request")
            return nil
        }
        
        // Check if this ROM is already running
        LoggerService.extreme(category: "GameLauncher", "Checking if ROM is already running")
        if RunningGamesTracker.shared.isRunning(romPath: rom.path.path) {
            RunningGamesTracker.shared.notifyDuplicateLaunch(romName: rom.displayName)
            completion?(nil)
            LoggerService.extreme(category: "GameLauncher", "ROM is already running, ignoring duplicate request")
            return nil
        }
        
        // MAME dependency check
        LoggerService.extreme(category: "GameLauncher", "Checking MAME dependencies")
        if checkMAMEDeps && MAMEDependencyService.isMAMECore(coreID) {
            let checkResult = checkMAMEDependencies(rom: rom, coreID: coreID)
            if case .missingFiles(let gameName, let missing, let romsDir) = checkResult {
                LoggerService.info(category: "GameLauncher", "MAME ROM missing files for \(gameName): \(missing.map(\.sourceZIP))")
                showMAMEMissingFilesAlert(gameName: gameName, missing: missing, romsDirectory: romsDir)
                isLaunching = false
                currentLaunchROM = nil
                completion?(nil)
                return nil
            }
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
        LoggerService.debug(category: "GameLauncher", "ROM path: \(rom.path.path)")
        LoggerService.debug(category: "GameLauncher", "Core: \(coreID), System: \(systemID), Slot: \(slotToLoad.map { "\($0)" } ?? "none")")
        LoggerService.debug(category: "GameLauncher", "Shader: \(config.shaderPresetID), Uniform overrides: \(config.shaderUniformOverrides.count)")
        LoggerService.debug(category: "GameLauncher", "Bezel: \(config.bezelFileName.isEmpty ? "auto-match" : (config.bezelFileName == "none" ? "disabled" : config.bezelFileName))")
        LoggerService.debug(category: "GameLauncher", "Achievements: \(config.achievementsEnabled), Hardcore: \(config.hardcoreMode)")
        LoggerService.debug(category: "GameLauncher", "Cheats: \(config.cheatsEnabled), Core options: \(config.coreOptions.count) override(s)")
        LoggerService.debug(category: "GameLauncher", "Auto-load: \(config.autoLoad), Auto-save: \(config.autoSave)")
        
        // Apply all settings
        applyLaunchConfiguration(config)
        
        // Mark as played
        library?.markPlayed(rom)
        
        // Create runner and window controller
        let runner = EmulatorRunner.forSystem(systemID)
        let controller = StandaloneGameWindowController(runner: runner)
        controller.library = library
        
        // Track the controller
        activeControllers[rom.id] = controller
        
        // Launch the game (window will be shown by controller when ready)
        controller.launch(rom: rom, coreID: coreID, slotToLoad: slotToLoad)
        
        // Cleanup
        isLaunching = false
        currentLaunchROM = nil
        
        LoggerService.debug(category: "GameLauncher", "Launch complete: \(rom.displayName)")
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
        
        // 2.3. Apply MAME-specific core options for frame limiting (always, regardless of existing overrides)
        let launchSystemID = config.rom.systemID ?? "default"
        applyMAMEFrameLimitOptions(for: launchSystemID, coreID: config.coreID)
        
        // 2.5. Apply Game Boy colorization settings for original GB games
        applyGBColorizationForROM(config.rom, coreID: config.coreID)
        
        // 3. Apply auto-load/save preferences
        AppSettings.setBool("auto_load_on_start", value: config.autoLoad)
        AppSettings.setBool("auto_save_on_exit", value: config.autoSave)
        
        // 4. Apply achievements setting
        AppSettings.setBool("achievements_enabled", value: config.achievementsEnabled)
        
        // 5. Apply hardcore mode
        if config.hardcoreMode != HardcoreModeManager.shared.isHardcoreActive {
            HardcoreModeManager.shared.isHardcoreActive = config.hardcoreMode
        }
        
        // 6. Apply cheats setting
        AppSettings.setBool("cheats_enabled", value: config.cheatsEnabled)
    }
    
    // MARK: - MAME Frame Limiting
    
    /// Apply MAME-specific core options that ensure games run at their native speed.
    /// MAME cores run unlocked by default and can far exceed real hardware speed.
    /// This sets critical options like auto-frame-delay, vsync hints, and frameskip controls.
    private func applyMAMEFrameLimitOptions(for systemID: String, coreID: String) {
        guard systemID == "mame" || systemID == "fba" else { return }
        
        let coreBaseID = coreID.replacingOccurrences(of: "_libretro", with: "")
        var overrides = CoreOptionsManager.shared.loadUserOverrides(for: coreID)
        
        if coreBaseID.hasPrefix("mame") {
            // ── MAME2003-Plus specific options ──
            if coreBaseID.contains("mame2003_plus") || coreBaseID == "mame2003" {
                // Auto frameskip: dynamically adjusts frameskip to maintain speed
                overrides["mame2003-plus-auto-max-frameskip"] = "1"
                overrides["mame2003-plus-frameskip"] = "0"
                // Throttle: must be ON to lock to real hardware speed
                overrides["mame2003-plus-throttle"] = "enabled"
                // Skip disclaimer/skip warnings to avoid timing issues during boot
                overrides["mame2003-plus-skip_disclaimer"] = "enabled"
                overrides["mame2003-plus-skip_warnings"] = "enabled"
            }
            // ── MAME2010 specific options ──
            else if coreBaseID == "mame2010" {
                overrides["mame2010-auto_frameskip"] = "1"
                overrides["mame2010-frames_to_run"] = "0"
                overrides["mame2010-throttle"] = "enabled"
                overrides["mame2010-skip_disclaimer"] = "enabled"
                overrides["mame2010-skip_warnings"] = "enabled"
            }
            // ── MAME (current) specific options ──
            else if coreBaseID == "mame" {
                // Current MAME may have different option names
                overrides["mame-auto_frameskip"] = "enabled"
                overrides["mame-throttle"] = "enabled"
                overrides["mame-skip_gameinfo"] = "enabled"
            }
            // ── Generic MAME fallback ──
            else {
                // Apply common MAME frame rate options conservatively
                overrides["mame2000-auto_frameskip"] = "enabled"
                overrides["mame2000-throttle"] = "enabled"
            }
            
            LoggerService.debug(category: "GameLauncher", "Applied MAME frame limit options for core: \(coreBaseID)")
        } else if coreBaseID == "fbneo" {
            // FinalBurn Neo: ensure it's throttled to real hardware speed
            overrides["fbneo-frameskip"] = "0"
            overrides["fbneo-neogeo-controls"] = "classic"
            LoggerService.debug(category: "GameLauncher", "Applied FBNeo frame limit options")
        }
        
        if !overrides.isEmpty {
            CoreOptionsManager.shared.saveOverride(for: coreID, values: overrides)
        }
    }
    
    // MARK: - Game Boy Colorization
    
    /// Apply GB colorization core options based on ROM settings.
    /// Supports both original Game Boy (gb) and Game Boy Color (gbc).
    private func applyGBColorizationForROM(_ rom: ROM, coreID: String) {
        guard rom.systemID == "gb" || rom.systemID == "gbc" else { return }
        
        let settings = rom.settings
        let mode = settings.gbColorizationMode
        let colorCorrection = settings.gbColorCorrectionMode
        let isGBCROM = rom.systemID == "gbc"
        
        var overrides = CoreOptionsManager.shared.loadUserOverrides(for: coreID)
        let coreBaseID = coreID.replacingOccurrences(of: "_libretro", with: "")
        
        if coreBaseID.contains("gambatte") {
            applyGambatteOverrides(&overrides, settings: settings, mode: mode, colorCorrection: colorCorrection)
        } else if coreBaseID.contains("mgba") {
            applyMGBAOverrides(&overrides, settings: settings, mode: mode)
        } else if coreBaseID.contains("sameboy") {
            applySameBoyOverrides(&overrides, settings: settings, mode: mode, colorCorrection: colorCorrection, isGBCROM: isGBCROM)
        } else if coreBaseID.contains("gearboy") {
            overrides["gearboy_colorization"] = settings.gbColorizationEnabled ? "enabled" : "disabled"
        }
        
        if !overrides.isEmpty {
            CoreOptionsManager.shared.saveOverride(for: coreID, values: overrides)
        }
    }
    
    private func applyGambatteOverrides(
        _ overrides: inout [String: String],
        settings: ROMSettings,
        mode: String,
        colorCorrection: String
    ) {
        let value = settings.gbColorizationEnabled ? mode : "disabled"
        overrides["gambatte_gb_colorization"] = value
        overrides["gambatte_gb_internal_palette"] = settings.gbInternalPalette
        
        switch colorCorrection {
        case "gbc_only":
            overrides["gambatte_gbc_color_correction"] = "GBC only"
        case "always":
            overrides["gambatte_gbc_color_correction"] = "always"
        default:
            overrides["gambatte_gbc_color_correction"] = "disabled"
        }
    }
    
    private func applyMGBAOverrides(
        _ overrides: inout [String: String],
        settings: ROMSettings,
        mode: String
    ) {
        if !settings.gbColorizationEnabled {
            overrides["mgba_gb_model"] = "Game Boy"
        } else {
            switch mode {
            case "auto":  overrides["mgba_gb_model"] = "Autodetect"
            case "gbc":   overrides["mgba_gb_model"] = "Game Boy Color"
            case "sgb":   overrides["mgba_gb_model"] = "Super Game Boy"
            default:      overrides["mgba_gb_model"] = "Game Boy Color"
            }
        }
        overrides["mgba_sgb_borders"] = settings.gbSGBBordersEnabled ? "ON" : "OFF"
    }
    
    private func applySameBoyOverrides(
        _ overrides: inout [String: String],
        settings: ROMSettings,
        mode: String,
        colorCorrection: String,
        isGBCROM: Bool
    ) {
        if !settings.gbColorizationEnabled {
            overrides["sameboy_model"] = "Game Boy"
        } else {
            switch mode {
            case "auto":                           overrides["sameboy_model"] = "Auto"
            case "gbc", "internal", "sgb", "custom": overrides["sameboy_model"] = "Game Boy Color"
            default:                               overrides["sameboy_model"] = "Auto"
            }
        }
        if isGBCROM {
            switch colorCorrection {
            case "disabled", "off": overrides["sameboy_color_correction_mode"] = "off"
            default:                overrides["sameboy_color_correction_mode"] = "correct curves"
            }
        }
    }
    
    // MARK: - MAME Missing Files Alert
    
    /// Show an alert when MAME ROM files are missing.
    private func showMAMEMissingFilesAlert(gameName: String, missing: [MissingROMItem], romsDirectory: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Missing ROM Files"
        alert.informativeText = "\"\(gameName)\" requires additional ROM files to run.\n\nMissing files:\n\(missing.map { $0.sourceZIP }.joined(separator: "\n"))"
        LoggerService.error(category: "GameLauncher", "Missing ROM files for \(gameName): \(missing.map { $0.sourceZIP }.joined(separator: ", "))")
        
        alert.addButton(withTitle: "Open ROMs Folder")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(romsDirectory)
        }
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

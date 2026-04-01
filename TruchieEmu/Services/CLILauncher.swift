import Foundation

// MARK: - CLI Launch Arguments

/// Command-line argument keys used for launching games
enum CLIArg: String {
    // Core launch options
    case launch = "--launch"
    case core = "--core"
    case slot = "--slot"
    case headless = "--headless"
    case timeout = "--timeout"
    
    // Shader options
    case shader = "--shader"
    
    // Achievement options
    case achievementsEnabled = "--achievements"
    case hardcoreMode = "--hardcore"
    
    // Cheat options
    case cheatsEnabled = "--cheats"
    
    // Core options
    case coreOption = "--core-option"
    
    // Auto save/load options
    case autoLoad = "--auto-load"
    case autoSave = "--auto-save"
    
    // Info commands
    case listCores = "--list-cores"
    case listSystems = "--list-systems"
    case help = "--help"
    case version = "--version"
}

// MARK: - CLI Launch Options

/// Parsed CLI launch options with all supported features
struct CLILaunchOptions {
    // Core launch options
    let romPath: String?
    let coreID: String?
    let slot: Int?
    let headless: Bool
    let timeout: TimeInterval?
    
    // Shader options
    let shaderPresetID: String?
    
    // Achievement options
    let achievementsEnabled: Bool
    let hardcoreMode: Bool
    
    // Cheat options
    let cheatsEnabled: Bool
    
    // Core options (key=value pairs)
    let coreOptions: [String: String]
    
    // Auto save/load options
    let autoLoad: Bool
    let autoSave: Bool
    
    // Info commands
    var shouldListCores: Bool { command == .listCores }
    var shouldListSystems: Bool { command == .listSystems }
    var shouldShowHelp: Bool { command == .help }
    var shouldShowVersion: Bool { command == .version }
    
    let command: CLICommand
    
    init(
        romPath: String? = nil,
        coreID: String? = nil,
        slot: Int? = nil,
        headless: Bool = false,
        timeout: TimeInterval? = nil,
        shaderPresetID: String? = nil,
        achievementsEnabled: Bool = false,
        hardcoreMode: Bool = false,
        cheatsEnabled: Bool = false,
        coreOptions: [String: String] = [:],
        autoLoad: Bool = false,
        autoSave: Bool = false,
        command: CLICommand = .none
    ) {
        self.romPath = romPath
        self.coreID = coreID
        self.slot = slot
        self.headless = headless
        self.timeout = timeout
        self.shaderPresetID = shaderPresetID
        self.achievementsEnabled = achievementsEnabled
        self.hardcoreMode = hardcoreMode
        self.cheatsEnabled = cheatsEnabled
        self.coreOptions = coreOptions
        self.autoLoad = autoLoad
        self.autoSave = autoSave
        self.command = command
    }
    
    var hasLaunchCommand: Bool {
        return romPath != nil
    }
    
    var isInfoCommand: Bool {
        return command != .none
    }
}

enum CLICommand {
    case none
    case listCores
    case listSystems
    case help
    case version
}

// MARK: - CLILauncher

/// Utility to launch games via CLI using `open -a`
class CLILauncher {
    static let shared = CLILauncher()
    
    private init() {}
    
    /// Launch a game by spawning the TruchieEmu app with CLI arguments
    /// - Parameters:
    ///   - romPath: Absolute path to the ROM file
    ///   - coreID: Core identifier (e.g., "fceumm", "snes9x")
    ///   - slot: Optional save slot to load on start
    ///   - shaderPresetID: Shader preset to use
    ///   - achievementsEnabled: Whether to enable RetroAchievements
    ///   - hardcoreMode: Whether to enable hardcore mode
    ///   - cheatsEnabled: Whether to load cheats
    ///   - coreOptions: Core option overrides
    ///   - autoLoad: Whether to auto-load save state
    ///   - autoSave: Whether to auto-save on exit
    ///   - headless: If true, run without UI
    ///   - timeout: Optional timeout in seconds (for headless mode)
    /// - Returns: Whether the launch was initiated successfully
    @discardableResult
    func launchGame(
        romPath: String,
        coreID: String? = nil,
        slot: Int? = nil,
        shaderPresetID: String? = nil,
        achievementsEnabled: Bool = false,
        hardcoreMode: Bool = false,
        cheatsEnabled: Bool = false,
        coreOptions: [String: String] = [:],
        autoLoad: Bool = false,
        autoSave: Bool = false,
        headless: Bool = false,
        timeout: TimeInterval? = nil,
        appBundleID: String = "com.truchiemu.app"
    ) -> Bool {
        var arguments = buildLaunchArguments(
            romPath: romPath,
            coreID: coreID,
            slot: slot,
            shaderPresetID: shaderPresetID,
            achievementsEnabled: achievementsEnabled,
            hardcoreMode: hardcoreMode,
            cheatsEnabled: cheatsEnabled,
            coreOptions: coreOptions,
            autoLoad: autoLoad,
            autoSave: autoSave,
            headless: headless,
            timeout: timeout
        )
        
        return spawnApp(bundleID: appBundleID, arguments: arguments)
    }
    
    /// Launch a game using the app's executable directly
    /// - Parameters:
    ///   - romPath: Absolute path to the ROM file
    ///   - coreID: Core identifier
    ///   - slot: Optional save slot to load on start
    ///   - shaderPresetID: Shader preset to use
    ///   - achievementsEnabled: Whether to enable RetroAchievements
    ///   - hardcoreMode: Whether to enable hardcore mode
    ///   - cheatsEnabled: Whether to load cheats
    ///   - coreOptions: Core option overrides
    ///   - autoLoad: Whether to auto-load save state
    ///   - autoSave: Whether to auto-save on exit
    ///   - headless: If true, run without UI
    /// - Returns: The process that was spawned
    func launchGameDirect(
        romPath: String,
        coreID: String? = nil,
        slot: Int? = nil,
        shaderPresetID: String? = nil,
        achievementsEnabled: Bool = false,
        hardcoreMode: Bool = false,
        cheatsEnabled: Bool = false,
        coreOptions: [String: String] = [:],
        autoLoad: Bool = false,
        autoSave: Bool = false,
        headless: Bool = false
    ) -> Process? {
        let arguments = buildLaunchArguments(
            romPath: romPath,
            coreID: coreID,
            slot: slot,
            shaderPresetID: shaderPresetID,
            achievementsEnabled: achievementsEnabled,
            hardcoreMode: hardcoreMode,
            cheatsEnabled: cheatsEnabled,
            coreOptions: coreOptions,
            autoLoad: autoLoad,
            autoSave: autoSave,
            headless: headless,
            timeout: nil
        )
        
        return spawnDirect(arguments: arguments)
    }
    
    /// Build CLI arguments array from launch parameters
    private func buildLaunchArguments(
        romPath: String,
        coreID: String?,
        slot: Int?,
        shaderPresetID: String?,
        achievementsEnabled: Bool,
        hardcoreMode: Bool,
        cheatsEnabled: Bool,
        coreOptions: [String: String],
        autoLoad: Bool,
        autoSave: Bool,
        headless: Bool,
        timeout: TimeInterval?
    ) -> [String] {
        var arguments = ["--launch", romPath]
        
        if let coreID = coreID {
            arguments.append(contentsOf: ["--core", coreID])
        }
        
        if let slot = slot {
            arguments.append(contentsOf: ["--slot", String(slot)])
        }
        
        if let shaderPresetID = shaderPresetID {
            arguments.append(contentsOf: ["--shader", shaderPresetID])
        }
        
        if achievementsEnabled {
            arguments.append("--achievements")
        }
        
        if hardcoreMode {
            arguments.append("--hardcore")
        }
        
        if cheatsEnabled {
            arguments.append("--cheats")
        }
        
        for (key, value) in coreOptions {
            arguments.append(contentsOf: ["--core-option", "\(key)=\(value)"])
        }
        
        if autoLoad {
            arguments.append("--auto-load")
        }
        
        if autoSave {
            arguments.append("--auto-save")
        }
        
        if headless {
            arguments.append("--headless")
        }
        
        if let timeout = timeout {
            arguments.append(contentsOf: ["--timeout", String(timeout)])
        }
        
        return arguments
    }
    
    // MARK: - Private
    
    private func spawnApp(bundleID: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", bundleID, "--args"] + arguments
        
        do {
            try process.run()
            print("[CLILauncher] Spawning app with: open -a \(bundleID) --args \(arguments.joined(separator: " "))")
            return true
        } catch {
            print("[CLILauncher] Failed to spawn app: \(error)")
            return false
        }
    }
    
    private func spawnDirect(arguments: [String]) -> Process? {
        guard let executablePath = Bundle.main.executablePath else {
            print("[CLILauncher] Cannot find app executable path")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        
        do {
            try process.run()
            print("[CLILauncher] Spawned directly: \(executablePath) \(arguments.joined(separator: " "))")
            return process
        } catch {
            print("[CLILauncher] Failed to spawn directly: \(error)")
            return nil
        }
    }
}
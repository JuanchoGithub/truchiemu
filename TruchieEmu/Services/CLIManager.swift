import Foundation
import AppKit
import Combine

// MARK: - CLIManager

// Manages CLI command routing at app startup
class CLIManager: ObservableObject {
    static let shared = CLIManager()
    
    // Reference to the ROM library for recording playtime in CLI launches (weak to avoid retain cycles)
    weak var library: ROMLibrary?
    
    @MainActor
    @Published var isHandlingCLI = false
    @MainActor
    @Published var currentCLICommand: String?
    
    private var headlessProcess: Process?
    private var headlessTimer: Timer?
    
    private init() {}
    
    // MARK: - Public
    
    // Parse command-line arguments and route to appropriate handler
    // - Returns: The parsed CLI options
    func parseArguments() -> CLILaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        return parse(arguments: arguments)
    }
    
    // Handle CLI commands - call this at app startup
    // - Returns: true if CLI handled the command (app should not show main window)
    @MainActor
    func handleStartupCommands() -> Bool {
        let options = parseArguments()
        
        // Show help
        if options.shouldShowHelp {
            printHelp()
            return true
        }
        
        // Show version
        if options.shouldShowVersion {
            printVersion()
            return true
        }
        
        // List cores
        if options.shouldListCores {
            listCores()
            return true
        }
        
        // List systems
        if options.shouldListSystems {
            listSystems()
            return true
        }
        
        // Launch game
        if options.hasLaunchCommand {
            return handleLaunch(options: options)
        }
        
        return false
    }
    
    // MARK: - Parsing
    
    private func parse(arguments: [String]) -> CLILaunchOptions {
        var romPath: String?
        var coreID: String?
        var slot: Int?
        var headless = false
        var timeout: TimeInterval?
        var shaderPresetID: String?
        var shaderUniformOverrides: [String: Float] = [:]
        var achievementsEnabled = false
        var hardcoreMode = false
        var cheatsEnabled = false
        var coreOptions: [String: String] = [:]
        var bezelFileName: String? = nil
        var autoLoad = false
        var autoSave = false
        var command: CLICommand = .none
        
        var i = 1 // Skip executable path
        while i < arguments.count {
            let arg = arguments[i]
            
            switch arg {
            case CLIArg.launch.rawValue:
                i += 1
                if i < arguments.count {
                    romPath = arguments[i]
                }
                
            case CLIArg.core.rawValue:
                i += 1
                if i < arguments.count {
                    coreID = arguments[i]
                }
                
            case CLIArg.slot.rawValue:
                i += 1
                if i < arguments.count {
                    slot = Int(arguments[i])
                }
                
            case CLIArg.headless.rawValue:
                headless = true
                
            case CLIArg.timeout.rawValue:
                i += 1
                if i < arguments.count {
                    timeout = Double(arguments[i])
                }
                
            case CLIArg.shader.rawValue:
                i += 1
                if i < arguments.count {
                    shaderPresetID = arguments[i]
                }

            case CLIArg.shaderUniform.rawValue:
                i += 1
                if i < arguments.count {
                    let uniformStr = arguments[i]
                    LoggerService.debug(category: "CLI", "Parsing shader uniform: '\(uniformStr)'")
                    // Remove surrounding quotes if present
                    let cleanStr = uniformStr.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if let eqIndex = cleanStr.firstIndex(of: "=") {
                        let key = String(cleanStr[..<eqIndex])
                        let valueStr = String(cleanStr[cleanStr.index(after: eqIndex)...])
                        if let value = Float(valueStr) {
                            LoggerService.debug(category: "CLI", "Shader uniform override: \(key) = \(value)")
                            shaderUniformOverrides[key] = value
                        } else {
                            LoggerService.info(category: "CLI", "Failed to parse shader uniform value: '\(valueStr)'")
                        }
                    } else {
                        LoggerService.debug(category: "CLI", "No '=' found in shader uniform: '\(cleanStr)'")
                    }
                }

            case CLIArg.achievementsEnabled.rawValue:
                achievementsEnabled = true
                
            case CLIArg.hardcoreMode.rawValue:
                hardcoreMode = true
                
            case CLIArg.cheatsEnabled.rawValue:
                cheatsEnabled = true
                
            case CLIArg.bezel.rawValue:
                i += 1
                if i < arguments.count {
                    bezelFileName = arguments[i]
                }
                
            case CLIArg.coreOption.rawValue:
                i += 1
                if i < arguments.count {
                    let optionStr = arguments[i]
                    if let eqIndex = optionStr.firstIndex(of: "=") {
                        let key = String(optionStr[..<eqIndex])
                        let value = String(optionStr[optionStr.index(after: eqIndex)...])
                        coreOptions[key] = value
                    }
                }
                
            case CLIArg.autoLoad.rawValue:
                autoLoad = true
                
            case CLIArg.autoSave.rawValue:
                autoSave = true
                
            case CLIArg.listCores.rawValue:
                command = .listCores
                
            case CLIArg.listSystems.rawValue:
                command = .listSystems
                
            case CLIArg.help.rawValue:
                command = .help
                
            case CLIArg.version.rawValue:
                command = .version
                
            default:
                // Check if it's an old-style argument (just a path)
                if romPath == nil && arguments[i].contains(".") {
                    let path = arguments[i]
                    if FileManager.default.fileExists(atPath: path) {
                        romPath = path
                    }
                }
            }
            
            i += 1
        }
        
        return CLILaunchOptions(
            romPath: romPath,
            coreID: coreID,
            slot: slot,
            headless: headless,
            timeout: timeout,
            shaderPresetID: shaderPresetID,
            shaderUniformOverrides: shaderUniformOverrides,
            achievementsEnabled: achievementsEnabled,
            hardcoreMode: hardcoreMode,
            cheatsEnabled: cheatsEnabled,
            bezelFileName: bezelFileName,
            coreOptions: coreOptions,
            autoLoad: autoLoad,
            autoSave: autoSave,
            command: command
        )
    }
    
    // MARK: - Command Handlers
    
    @MainActor
    private func handleLaunch(options: CLILaunchOptions) -> Bool {
        guard let romPath = options.romPath else {
            LoggerService.info(category: "CLI", "Error: No ROM path specified")
            return false
        }
        
        // Verify ROM file exists
        if !FileManager.default.fileExists(atPath: romPath) {
            LoggerService.info(category: "CLI", "Error: ROM file not found: \(romPath)")
            return false
        }
        
        isHandlingCLI = true
        currentCLICommand = "Launching: \(romPath)"
        
        LoggerService.info(category: "CLI", "Launching game: \(romPath)")
        if let coreID = options.coreID {
            LoggerService.debug(category: "CLI", "Core: \(coreID)")
        }
        if let slot = options.slot {
            LoggerService.debug(category: "CLI", "Slot: \(slot)")
        }
        if let shader = options.shaderPresetID {
            LoggerService.debug(category: "CLI", "Shader: \(shader)")
        }
        if options.achievementsEnabled {
            LoggerService.info(category: "CLI", "Achievements: Enabled" + (options.hardcoreMode ? " (Hardcore)" : ""))
        }
        if options.cheatsEnabled {
            LoggerService.debug(category: "CLI", "Cheats: Enabled")
        }
        if !options.coreOptions.isEmpty {
            LoggerService.debug(category: "CLI", "Core options: \(options.coreOptions)")
        }
        if options.headless {
            LoggerService.info(category: "CLI", "Mode: Headless")
        }
        if !options.shaderUniformOverrides.isEmpty {
            LoggerService.debug(category: "CLI", "Shader uniform overrides: \(options.shaderUniformOverrides)")
        }
        
        // Resolve system ID from ROM path
        let systemID = resolveSystemID(romPath: romPath)
        
        // Find or auto-select core
        let coreID = options.coreID ?? selectCore(systemID: systemID)
        
        guard let coreID = coreID else {
            LoggerService.info(category: "CLI", "Error: Could not determine core for ROM")
            isHandlingCLI = false
            currentCLICommand = nil
            return false
        }
        
        // Create ROM model with CLI options applied
        var rom = createROM(path: romPath, systemID: systemID)
        
        // Apply shader preset if specified
        if let shaderPresetID = options.shaderPresetID {
            rom.settings.shaderPresetID = shaderPresetID
            LoggerService.debug(category: "CLI", "Applied shader preset: \(shaderPresetID)")
        }
        
        // Apply bezel if specified
        if let bezelFileName = options.bezelFileName {
            rom.settings.bezelFileName = bezelFileName
            LoggerService.debug(category: "CLI", "Applied bezel: \(bezelFileName)")
        }
        
        // Apply core options if specified
        if !options.coreOptions.isEmpty {
            CoreOptionsManager.shared.saveOverride(for: coreID, values: options.coreOptions)
            LoggerService.debug(category: "CLI", "Applied \(options.coreOptions.count) core option(s)")
        }
        
        // Apply auto-load/save settings
        if options.autoLoad {
            AppSettings.setBool("saveState_autoLoadOnStart", value: false)
            LoggerService.debug(category: "CLI", "Auto-load enabled")
        }
        if options.autoSave {
            AppSettings.setBool("saveState_autoSaveOnExit", value: false)
            LoggerService.debug(category: "CLI", "Auto-save enabled")
        }
        
        // CRITICAL FIX: Apply achievements, hardcore, and cheats settings via AppSettings
        // GameLauncher.LaunchConfig reads these from AppSettings, so we MUST set them here
        if options.achievementsEnabled {
            AppSettings.setBool("achievements_enabled", value: false)
            LoggerService.debug(category: "CLI", "Achievements enabled")
        }
        if options.hardcoreMode {
            AppSettings.setBool("hardcore_mode", value: false)
            LoggerService.debug(category: "CLI", "Hardcore mode enabled")
        }
        if options.cheatsEnabled {
            AppSettings.setBool("cheats_enabled", value: false)
            LoggerService.debug(category: "CLI", "Cheats enabled")
        }
        
        // Handle headless mode
        if options.headless {
            return handleHeadlessLaunch(rom: rom, coreID: coreID, timeout: options.timeout ?? 10)
        }
        
        // Reset running games tracker for CLI launches (since app is fresh each time)
        // NOTE: The ROM is registered later by StandaloneGameWindowController.launch()
        // Do NOT register here - it would cause GameLauncher.launchGame() to detect a "duplicate"
        RunningGamesTracker.shared.resetAll()
        
        // Normal UI mode - use unified GameLauncher for consistent launch behavior
        LoggerService.info(category: "CLI", "Creating game window (system: \(systemID), core: \(coreID))")
        
        // Use unified GameLauncher for all launch paths
        let controller = GameLauncher.shared.launchGame(
            rom: rom,
            coreID: coreID,
            slotToLoad: options.slot,
            library: library,
            shaderUniformOverrides: options.shaderUniformOverrides
        )
        
        guard let controller = controller, let gameWindow = controller.window else {
            LoggerService.info(category: "CLI", "Error: Failed to create game window")
            isHandlingCLI = false
            currentCLICommand = nil
            return false
        }
        
        // Make sure the game window is visible
        gameWindow.orderFrontRegardless()
        gameWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        LoggerService.debug(category: "CLI", "Game window ordered front")
        
        // Close the CLI placeholder window immediately (on next run loop iteration after game window is shown)
        DispatchQueue.main.async {
            LoggerService.debug(category: "CLI", "Starting cleanup. Current windows: \(NSApp.windows.count)")
            
            for window in NSApp.windows {
                if window == gameWindow { 
                    LoggerService.debug(category: "CLI", "Keeping game window")
                    continue 
                }
                // Only close CLI placeholder windows, not other important windows
                if window.title.isEmpty || window.title == "TruchieEmu" {
                    LoggerService.debug(category: "CLI", "Closing window: '\(window.title)'")
                    window.close()
                }
            }
            LoggerService.debug(category: "CLI", "Cleanup complete")
        }
        
        LoggerService.info(category: "CLI", "Game window created successfully")
        return true
    }
    
    @MainActor
    private func handleHeadlessLaunch(rom: ROM, coreID: String, timeout: TimeInterval) -> Bool {
        LoggerService.info(category: "CLI", "Headless mode - launching without UI")
        
        let runner = EmulatorRunner.forSystem(rom.systemID ?? "default")
        
        // Track running state
        headlessProcess = Process()
        
        // Store reference for timeout check
        let localRunner = runner
        
        // Auto-stop after timeout - check frames with a slight delay to allow async texture update
        headlessTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            // Schedule a quick secondary check to allow any pending async texture update to complete
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await MainActor.run {
                    let hasFrames = localRunner.currentFrameTexture != nil
                    LoggerService.info(category: "CLI", "Timeout reached (timeout: \(timeout)s)")
                    if hasFrames {
                        LoggerService.info(category: "CLI", "SUCCESS: Game rendered frames")
                        exit(0)
                    } else {
                        LoggerService.info(category: "CLI", "FAILURE: No frames received within timeout")
                        exit(1)
                    }
                }
            }
        }
        
        // Use the runner's launch method which handles ScummVM ZIP extraction
        runner.launch(rom: rom, coreID: coreID)
        
        LoggerService.info(category: "CLI", "Headless emulation started (timeout: \(timeout)s)")
        return true
    }
    
    private var headlessCancellables = Set<AnyCancellable>()
    
    // MARK: - Info Commands
    
    @MainActor
    private func listCores() {
        print("\n=== TruchieEmu Available Cores ===\n")
        
        // Show installed cores
        let installed = CoreManager.shared.installedCores
        if !installed.isEmpty {
            print("INSTALLED CORES:")
            for core in installed.sorted(by: { $0.id < $1.id }) {
                let active = core.activeVersionTag ?? "none"
                print("  ✓ \(core.id) - \(core.displayName) (Active: \(active))")
            }
        }
        
        // Show available cores from buildbot
        let available = CoreManager.shared.availableCores
        if !available.isEmpty {
            print("\nAVAILABLE CORES (from buildbot):")
            for core in available.sorted(by: { $0.coreID < $1.coreID }) {
                let isInstalled = CoreManager.shared.isInstalled(coreID: core.coreID)
                let status = isInstalled ? "✓" : "○"
                let systems = core.systemIDs.joined(separator: ", ")
                print("  \(status) \(core.coreID) - \(core.displayName) (Systems: \(systems))")
            }
        }
        
        print("\nTotal installed: \(installed.count)")
        print("Total available: \(available.count)")
        print("\nUsage: open -a TruchieEmu --args --launch /path/to/rom --core <core_id>\n")
    }
    
    @MainActor
    private func listSystems() {
        print("\n=== TruchieEmu Supported Systems ===\n")
        
        let systems = SystemDatabase.systems
        for system in systems {
            print("  \(system.id) - \(system.name)")
            print("    Extensions: \(system.extensions.joined(separator: ", "))")
            if let defaultCore = system.defaultCoreID {
                print("    Default Core: \(defaultCore)")
            }
        }
        
        print("\nUsage: open -a TruchieEmu --args --launch /path/to/rom\n")
    }
    
    
    private func printHelp() {
        print("""
        
        ╔═══════════════════════════════════════════╗
        ║          TruchieEmu CLI Help             ║
        ╚═══════════════════════════════════════════╝
        
        Usage:
          open -a TruchieEmu --args [OPTIONS]
        
        Commands:
          --launch <path>        Launch a ROM file
          --list-cores           List available emulator cores
          --list-systems         List supported systems
          --help                 Show this help message
          --version              Show version
        
        Options for --launch:
          --core <core_id>       Specify which core to use
          --slot <number>        Load save state from slot (0-9)
          --shader <preset_id>   Set shader preset (e.g., builtin-none, builtin-crt-classic)
          --shader-uniform <k=v> Override a shader uniform value (e.g., barrelAmount=0.25, scanlineIntensity=0.5, colorBoost=1.2)
          --achievements         Enable RetroAchievements
          --hardcore             Enable hardcore mode (with --achievements)
          --cheats               Load cheat files for the game
          --bezel <filename>     Set bezel image file (or "none" to disable)
          --core-option <k=v>    Set core option (can be used multiple times)
          --auto-load            Auto-load last save state on start
          --auto-save            Auto-save on exit
          --headless             Run without UI (for testing)
          --timeout <seconds>    Timeout for headless mode (default: 10)
        
        Examples:
          # Launch a game with auto core detection
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes
        
          # Launch with specific core
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --core fceumm
        
          # Launch and load from slot 3
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --slot 3
        
          # Launch with shader and achievements
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --shader builtin-crt-classic --achievements

          # Launch with custom shader uniform overrides
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --shader builtin-crt-classic --shader-uniform "barrelAmount=0.25" --shader-uniform "scanlineIntensity=0.5" --shader-uniform "colorBoost=1.2"
        
          # Launch with hardcore mode and cheats
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --achievements --hardcore --cheats

          # Launch with custom bezel
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --bezel "crt-curved.png"

          # Launch with bezel disabled
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --bezel none
        
          # Launch with core options
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --core-option "mupen64plus-cpucore=dynamic"
        
          # Headless test (returns 0 if frames render, 1 if not)
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --headless --timeout 10
        
          # List all cores
          open -a TruchieEmu --args --list-cores
        
        """)
    }
    
    private func printVersion() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        print("TruchieEmu v\(version) (Build \(build))")
    }
    
    // MARK: - Helpers
    
    private func resolveSystemID(romPath: String) -> String {
        let url = URL(fileURLWithPath: romPath)
        let ext = url.pathExtension.lowercased()
        
        // Special handling for zip files - check if it's likely a ScummVM game
        if ext == "zip" {
            let fileName = url.lastPathComponent.lowercased()
            // Known ScummVM game indicators in filenames
            let scummvmIndicators = [
                "floppy", "cd ", "dos", "scumm", "tentacle", "monkey island",
                "samnmax", "loom", "indy", "maniac", "zak", "dig", 
                "fullthrottle", "tuche", "kings quest", "space quest",
                "leisure suit", "police quest", "quest for glory"
            ]
            let isScummVM = scummvmIndicators.contains { fileName.contains($0) }
            if isScummVM {
                return "scummvm"
            }
            return "dos"  // Default zip to dos if not scummvm
        }
        
        // Use SystemDatabase to find matching system
        if let system = SystemDatabase.system(forExtension: ext) {
            return system.id
        }
        
        // Fallback mapping for common extensions
        let extToSystem: [String: String] = [
            "nes": "nes",
            "smc": "snes", "sfc": "snes",
            "n64": "n64", "z64": "n64",
            "scummvm": "scummvm"
        ]
        
        return extToSystem[ext] ?? "default"
    }
    
    @MainActor
    private func selectCore(systemID: String) -> String? {
        // First try system's default core
        if let system = SystemDatabase.system(forID: systemID), let defaultCore = system.defaultCoreID {
            // Check if this core is installed
            if let installedCore = CoreManager.shared.installedCores.first(where: { $0.id == defaultCore }) {
                if installedCore.isInstalled {
                    return defaultCore
                }
            }
        }
        
        // Fallback: try to find any installed core for this system
        for core in CoreManager.shared.installedCores {
            if core.isInstalled && core.systemIDs.contains(systemID) {
                return core.id
            }
        }
        
        return nil
    }
    
    private func createROM(path: String, systemID: String) -> ROM {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        
        let rom = ROM(
            id: UUID(),
            name: name,
            path: url,
            systemID: systemID,
            isFavorite: false,
            lastPlayed: nil,
            selectedCoreID: nil,
            customName: nil,
            useCustomCore: false,
            metadata: ROMMetadata(title: url.deletingPathExtension().lastPathComponent),
            isBios: false,
            isHidden: false,
            category: "game",
            crc32: nil,
            thumbnailLookupSystemID: nil,
            screenshotPaths: [],
            settings: ROMSettings()
        )
        
        return rom
    }
}
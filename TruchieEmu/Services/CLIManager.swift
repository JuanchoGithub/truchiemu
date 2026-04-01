import Foundation
import AppKit
import Combine

// MARK: - CLIManager

/// Manages CLI command routing at app startup
class CLIManager: ObservableObject {
    static let shared = CLIManager()
    
    @MainActor
    @Published var isHandlingCLI = false
    @MainActor
    @Published var currentCLICommand: String?
    
    private var headlessProcess: Process?
    private var headlessTimer: Timer?
    
    private init() {}
    
    // MARK: - Public
    
    /// Parse command-line arguments and route to appropriate handler
    /// - Returns: The parsed CLI options
    func parseArguments() -> CLILaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        return parse(arguments: arguments)
    }
    
    /// Handle CLI commands - call this at app startup
    /// - Returns: true if CLI handled the command (app should not show main window)
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
        var achievementsEnabled = false
        var hardcoreMode = false
        var cheatsEnabled = false
        var coreOptions: [String: String] = [:]
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
                
            case CLIArg.achievementsEnabled.rawValue:
                achievementsEnabled = true
                
            case CLIArg.hardcoreMode.rawValue:
                hardcoreMode = true
                
            case CLIArg.cheatsEnabled.rawValue:
                cheatsEnabled = true
                
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
            achievementsEnabled: achievementsEnabled,
            hardcoreMode: hardcoreMode,
            cheatsEnabled: cheatsEnabled,
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
            print("[CLI] Error: No ROM path specified")
            return false
        }
        
        // Verify ROM file exists
        if !FileManager.default.fileExists(atPath: romPath) {
            print("[CLI] Error: ROM file not found: \(romPath)")
            return false
        }
        
        isHandlingCLI = true
        currentCLICommand = "Launching: \(romPath)"
        
        print("[CLI] Launching game: \(romPath)")
        if let coreID = options.coreID {
            print("[CLI] Core: \(coreID)")
        }
        if let slot = options.slot {
            print("[CLI] Slot: \(slot)")
        }
        if let shader = options.shaderPresetID {
            print("[CLI] Shader: \(shader)")
        }
        if options.achievementsEnabled {
            print("[CLI] Achievements: Enabled" + (options.hardcoreMode ? " (Hardcore)" : ""))
        }
        if options.cheatsEnabled {
            print("[CLI] Cheats: Enabled")
        }
        if !options.coreOptions.isEmpty {
            print("[CLI] Core options: \(options.coreOptions)")
        }
        if options.headless {
            print("[CLI] Mode: Headless")
        }
        
        // Resolve system ID from ROM path
        let systemID = resolveSystemID(romPath: romPath)
        
        // Find or auto-select core
        let coreID = options.coreID ?? selectCore(systemID: systemID)
        
        guard let coreID = coreID else {
            print("[CLI] Error: Could not determine core for ROM")
            isHandlingCLI = false
            currentCLICommand = nil
            return false
        }
        
        // Create ROM model with CLI options applied
        var rom = createROM(path: romPath, systemID: systemID)
        
        // Apply shader preset if specified
        if let shaderPresetID = options.shaderPresetID {
            rom.settings.shaderPresetID = shaderPresetID
            print("[CLI] Applied shader preset: \(shaderPresetID)")
        }
        
        // Apply core options if specified
        if !options.coreOptions.isEmpty {
            CoreOptionsManager.shared.saveOverride(for: coreID, values: options.coreOptions)
            print("[CLI] Applied \(options.coreOptions.count) core option(s)")
        }
        
        // Apply auto-load/save settings
        if options.autoLoad {
            UserDefaults.standard.set(true, forKey: "auto_load_on_start")
            print("[CLI] Auto-load enabled")
        }
        if options.autoSave {
            UserDefaults.standard.set(true, forKey: "auto_save_on_exit")
            print("[CLI] Auto-save enabled")
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
        print("[CLI] Creating game window...")
        print("[CLI] System ID: \(systemID), Core ID: \(coreID)")
        
        // Use unified GameLauncher for all launch paths
        let controller = GameLauncher.shared.launchGame(
            rom: rom,
            coreID: coreID,
            slotToLoad: options.slot
        )
        
        guard let controller = controller, let gameWindow = controller.window else {
            print("[CLI] Error: Failed to create game window")
            isHandlingCLI = false
            currentCLICommand = nil
            return false
        }
        
        // Make sure the game window is visible
        gameWindow.orderFrontRegardless()
        gameWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("[CLI] Game window ordered front. Windows: \(NSApp.windows.map { $0.title })")
        
        // Close the CLI placeholder window immediately (on next run loop iteration after game window is shown)
        DispatchQueue.main.async {
            print("[CLI] Starting cleanup. Current windows: \(NSApp.windows.map { "\($0.title)(\($0 == gameWindow ? "game" : "other"))" })")
            
            for window in NSApp.windows {
                if window == gameWindow { 
                    print("[CLI] Keeping game window")
                    continue 
                }
                // Only close CLI placeholder windows, not other important windows
                if window.title.isEmpty || window.title == "TruchieEmu" {
                    print("[CLI] Closing window: '\(window.title)'")
                    window.close()
                }
            }
            print("[CLI] Cleanup complete")
        }
        
        print("[CLI] Game window created")
        return true
    }
    
    @MainActor
    private func handleHeadlessLaunch(rom: ROM, coreID: String, timeout: TimeInterval) -> Bool {
        print("[CLI] Headless mode - launching without UI")
        
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
                    print("[CLI] Timeout reached (timeout: \(timeout)s)")
                    if hasFrames {
                        print("[CLI] SUCCESS: Game rendered frames")
                        exit(0)
                    } else {
                        print("[CLI] FAILURE: No frames received within timeout")
                        exit(1)
                    }
                }
            }
        }
        
        // Use the runner's launch method which handles ScummVM ZIP extraction
        runner.launch(rom: rom, coreID: coreID)
        
        print("[CLI] Headless emulation started (timeout: \(timeout)s)")
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
          --achievements         Enable RetroAchievements
          --hardcore             Enable hardcore mode (with --achievements)
          --cheats               Load cheat files for the game
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
        
          # Launch with hardcore mode and cheats
          open -a TruchieEmu --args --launch ~/Roms/Mario.nes --achievements --hardcore --cheats
        
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
            boxArtPath: nil,
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
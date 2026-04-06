import SwiftUI
import AppKit

@main
struct TruchieEmuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // SwiftData container manages all persistence.
    // The container handles one-time migration on first launch.
    init() {
        _ = SwiftDataContainer.shared
        _ = LoggerService.shared
        
        // Load MAME lookup dictionary into memory for fast lookups
        Task {
            await MAMEImportService.shared.loadLookupDictionary()
        }
    }
    
    @StateObject private var library = ROMLibrary()
    @StateObject private var categoryManager = CategoryManager()
    @StateObject private var coreManager = CoreManager()
    @StateObject private var controllerService = ControllerService.shared
    @StateObject private var mameVerification = MAMEVerificationService.shared
    
    // NOTE: NSApp is NOT NOT available in init() for @main App structs.
    // Activation policy is set in AppDelegate.applicationWillFinishLaunching instead.
    // This prevents crashes when NSApp is accessed during initialization.
    
    private var isCLILaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--launch")
    }
    
    // MARK: - MAME Verification
    
    private func startMAMEVerificationIfNeeded() {
        // Only start verification for MAME system ROMs
        // Check if there are pending verifications
        Task { @MainActor in
            MAMEVerificationService.shared.updatePendingCount()
            if MAMEVerificationService.shared.pendingCount > 0 {
                // Get the model context from SwiftDataContainer
                let modelContext = SwiftDataContainer.shared.container.mainContext
                MAMEVerificationService.shared.startVerification(modelContext: modelContext)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentWithPrepopulationView()
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
                .environmentObject(LibraryAutomationCoordinator.shared)
                .environmentObject(mameVerification)
                .onAppear {
                    // Start MAME verification when app becomes idle
                    startMAMEVerificationIfNeeded()
                }
                .onDisappear {
                    // Pause verification when leaving the app
                    MAMEVerificationService.shared.pause()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            if !isCLILaunch {
                CommandGroup(replacing: .newItem) {}
                CommandMenu("Library") {
                    Button("Rescan Library") {
                        Task { await library.fullRescan() }
                    }
                    .keyboardShortcut("R", modifiers: [.command, .shift])
                    .disabled(library.romFolderURL == nil || library.isScanning)
                }
            }
        }
        
        WindowGroup(id: "game-info", for: UUID.self) { $romID in
            GameInfoWindow(romID: romID ?? UUID())
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
        }
        
        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
        }
    }
}

/// Wrapper view that runs first-run DAT pre-population before showing content.
/// Checks the prepopulation flag synchronously to avoid showing the loading view
/// on subsequent launches.
struct ContentWithPrepopulationView: View {
    @State private var isPrepopulated: Bool
    @State private var isRunningPrepopulation = false
    
    @EnvironmentObject var library: ROMLibrary
    
    init() {
        // Check synchronously so we skip the loading view on subsequent launches
        _isPrepopulated = State(initialValue: AppSettings.getBool("dat_prepopulation_done_v1", defaultValue: false))
    }
    
    var body: some View {
        Group {
            if isPrepopulated {
                ContentView()
                    .environmentObject(library)
            } else {
                ProgressView("Initializing game database…")
                    .frame(width: 200)
                    .task {
                        await performPrepopulation()
                    }
            }
        }
    }
    
    private func performPrepopulation() async {
        guard !isPrepopulated else { return }
        isRunningPrepopulation = true
        
        // Attempt pre-population, but always proceed regardless of success.
        _ = await DATPrepopulationService.ensureDATsArePopulated()
        
        isRunningPrepopulation = false
        isPrepopulated = true
    }
}

struct TruchieEmuApp_WindowsOnly: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var library = ROMLibrary()
    @StateObject private var categoryManager = CategoryManager()
    @StateObject private var coreManager = CoreManager()
    @StateObject private var controllerService = ControllerService.shared
    
    private var isCLILaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--launch")
    }
    
    init() {
        _ = SwiftDataContainer.shared
        _ = LoggerService.shared
    }
    
    var body: some Scene {
        WindowGroup {
            if isCLILaunch {
                // Empty view for CLI launches - no window content shown
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        // Launch the game - CLIManager handles all window cleanup
                        Task { @MainActor in
                            LoggerService.info(category: "App", "CLI launch - starting game")
                            // Set library reference for playtime tracking in CLI launches
                            CLIManager.shared.library = library
                            _ = CLIManager.shared.handleStartupCommands()
                        }
                    }
            } else {
                ContentView()
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
                    .environmentObject(LibraryAutomationCoordinator.shared)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            if !isCLILaunch {
                CommandGroup(replacing: .newItem) {}
                CommandMenu("Library") {
                    Button("Rescan Library") {
                        Task { await library.fullRescan() }
                    }
                    .keyboardShortcut("R", modifiers: [.command, .shift])
                    .disabled(library.romFolderURL == nil || library.isScanning)
                }
            }
        }
        
        WindowGroup(id: "game-info", for: UUID.self) { $romID in
            GameInfoWindow(romID: romID ?? UUID())
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
        }
        
        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
        }
    }
}

/// Empty scene for CLI launches - prevents SwiftUI from creating any window
struct EmptyScene: Scene {
    var body: some Scene {
        Window("", id: "cli-hidden") {
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear {
                    // Hide this window immediately and trigger CLI launch
                    if let window = NSApp.keyWindow ?? NSApp.windows.first {
                        window.close()
                    }
                    // Start the game launch process
                    Task { @MainActor in
                        RunningGamesTracker.shared.resetAll()
                        _ = CLIManager.shared.handleStartupCommands()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Track if this instance was launched via CLI
    private var isCLILaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--launch")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // For CLI launches, terminate the app when the game window closes
        // This prevents the dock icon from staying visible after closing the game
        return isCLILaunch
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set activation policy BEFORE any windows are created
        if ProcessInfo.processInfo.arguments.contains("--launch") {
            NSApp.setActivationPolicy(.accessory)
        }
        
        // Prevent the game-info window from being restored on launch.
        // macOS saves window state in NSQuitAlwaysKeepsWindows UserDefaults key.
        // By removing the game-info window ID from the saved state, we prevent restoration.
        clearGameInfoWindowState()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--launch") {
            LoggerService.info(category: "App", "CLI launch detected - will terminate when last window closes")
            // Ensure we're still in accessory mode (no dock icon)
            NSApp.setActivationPolicy(.accessory)
        } else {
            LoggerService.info(category: "App", "Normal launch - app ready")
        }
        
        // Close any game-info windows that may have slipped through restoration.
        // This runs after windows are created to catch any that were already restored.
        DispatchQueue.main.async {
            self.closeRestoredGameInfoWindows()
        }
    }
    
    /// Remove any saved state for the game-info window to prevent restoration on launch.
    /// Called during applicationWillFinishLaunching to clear UserDefaults before macOS restores windows.
    private func clearGameInfoWindowState() {
        // macOS stores window frame info under keys like "NSWindow Frame game-info:UUID"
        let defaults = UserDefaults.standard
        let keysToRemove = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("NSWindow Frame ") && ($0.contains("game-info") || $0.contains("GameInfoWindow"))
        }
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        
        // NSQuitAlwaysKeepsWindows: boolean flags for each window to quit-and-restore behavior
        if let quitInfo = defaults.dictionary(forKey: "NSQuitAlwaysKeepsWindows") as? [String: Bool] {
            var mutableQuitInfo = quitInfo
            let keysToClear = mutableQuitInfo.keys.filter {
                $0.contains("game-info") || $0.contains("GameInfoWindow")
            }
            for key in keysToClear {
                mutableQuitInfo.removeValue(forKey: key)
            }
            defaults.set(mutableQuitInfo, forKey: "NSQuitAlwaysKeepsWindows")
        }
    }
    
    /// Close any game-info windows that were restored despite UserDefaults cleanup.
    private func closeRestoredGameInfoWindows() {
        let gameInfoWindows = NSApp.windows.filter { window in
            // Match by restoration class name or by checking if it's a game-info window
            let className = String(describing: type(of: window))
            return className.contains("game") || className.contains("GameInfo") ||
                   window.representedURL?.lastPathComponent == "game-info"
        }
        for window in gameInfoWindows {
            window.close()
        }
    }
}

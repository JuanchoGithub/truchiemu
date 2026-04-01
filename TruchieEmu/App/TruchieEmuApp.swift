import SwiftUI
import AppKit

@main
struct TruchieEmuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = ROMLibrary()
    @StateObject private var categoryManager = CategoryManager()
    @StateObject private var coreManager = CoreManager()
    @StateObject private var controllerService = ControllerService.shared
    
    // NOTE: NSApp is NOT NOT available in init() for @main App structs.
    // Activation policy is set in AppDelegate.applicationWillFinishLaunching instead.
    // This prevents crashes when NSApp is accessed during initialization.
    
    private var isCLILaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--launch")
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
                            print("[App] CLI launch - starting game")
                            CLIManager.shared.handleStartupCommands()
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
                        if let url = library.romFolderURL {
                            Task { await library.rescanLibrary(at: url) }
                        }
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
                        CLIManager.shared.handleStartupCommands()
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
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--launch") {
            print("[App] CLI launch detected - will terminate when last window closes")
            // Ensure we're still in accessory mode (no dock icon)
            NSApp.setActivationPolicy(.accessory)
        } else {
            print("[App] Normal launch")
        }
    }
}
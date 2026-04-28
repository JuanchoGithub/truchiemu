import SwiftUI
import AppKit
import UserNotifications

// MARK: - Notification Names for Menu Commands

extension Notification.Name {
    static let addROMFolder = Notification.Name("addROMFolder")
    static let viewModeChanged = Notification.Name("viewModeChanged")
    static let boxArtVisibilityChanged = Notification.Name("boxArtVisibilityChanged")
    static let boxArtStyleChanged = Notification.Name("boxArtStyleChanged")
    static let navigateToFilter = Notification.Name("navigateToFilter")
    static let sortChanged = Notification.Name("sortChanged")
    static let filterToggled = Notification.Name("filterToggled")
    static let languageChanged = Notification.Name("languageChanged")
    static let zoomChanged = Notification.Name("zoomChanged")
    static let openAppSettings = Notification.Name("openAppSettings")
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
}

@main
struct TruchiEmuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // SwiftData container manages all persistence.
    // The container handles one-time migration on first launch.
    init() {
        _ = SwiftDataContainer.shared
        _ = LoggerService.shared
        
        // MAME dictionary loading is deferred to background tasks in ContentWithPrepopulationView
        // 1. Connect the Bridge to your existing LoggerService
        LibretroBridgeSwift.registerCoreLogger { message, level in
            let category = "LibretroCore"
            switch level {
            case 0: // INFO
                LoggerService.info(category: category, message)
            case 1: // WARN
                LoggerService.info(category: category, message)
            case 2: // ERROR
                LoggerService.error(category: category, message)
            default:
                LoggerService.debug(category: category, message)
            }
        }
    }
    
    @StateObject private var library = ROMLibrary()
    @StateObject private var categoryManager = CategoryManager()
    @StateObject private var coreManager = CoreManager()
    @StateObject private var controllerService = ControllerService.shared
    @StateObject private var mameVerification = MAMEVerificationService.shared
    @State private var systemDatabase = SystemDatabaseWrapper.shared
    
    // NOTE: NSApp is NOT available in init() for @main App structs.
    // Activation policy is set in AppDelegate.applicationWillFinishLaunching instead.
    // This prevents crashes when NSApp is accessed during initialization.
    
    private var isCLILaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--launch")
    }
    
    // Systems that have games in the library
    private var systemsWithGames: [SystemInfo] {
        let ids = Set(library.roms.compactMap { $0.systemID })
        return systemDatabase.systemsForDisplay.filter { system in
            let internalIDs = systemDatabase.allInternalIDs(forDisplayID: system.id)
            return internalIDs.contains { ids.contains($0) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                .environment(systemDatabase)
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
            SidebarCommands()
            if !isCLILaunch {
                CommandGroup(replacing: .newItem) {}
                
// Add Settings menu item to app menu using .appSettings placement
                CommandGroup(after: .appTermination) {
                    Button("Settings…") {
                        UserDefaults.standard.set("general", forKey: "settings_selectedTab")
                        NotificationCenter.default.post(name: .openAppSettings, object: nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                
                // Add to the default View menu (macOS provides Zoom, Enter Full Screen)
                CommandGroup(after: .toolbar) {
                    Divider()
                    
                    // View Mode
                    Section("View Mode") {
                        Button("Grid") {
                            AppSettings.set("gridViewMode", value: "grid")
                            NotificationCenter.default.post(name: .viewModeChanged, object: "grid")
                        }
                        .keyboardShortcut("1", modifiers: .command)
                        
                        Button("List") {
                            AppSettings.set("gridViewMode", value: "list")
                            NotificationCenter.default.post(name: .viewModeChanged, object: "list")
                        }
                        .keyboardShortcut("2", modifiers: .command)
                    }
                    
                    Divider()
                    
                    // Box Art
                    Menu("Box Art") {
                        Button(AppSettings.getBool("showBoxArt", defaultValue: true) ? "Hide Box Art" : "Show Box Art") {
                            let current = AppSettings.getBool("showBoxArt", defaultValue: true)
                            AppSettings.setBool("showBoxArt", value: !current)
                            NotificationCenter.default.post(name: .boxArtVisibilityChanged, object: nil)
                        }
                        .keyboardShortcut("B", modifiers: .command)
                        
                        Divider()
                        
                        ForEach(BoxType.allCases) { type in
                            Button(type.rawValue) {
                                AppSettings.set("defaultBoxType", value: type.rawValue)
                                NotificationCenter.default.post(name: .boxArtStyleChanged, object: nil)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Sort
                    Menu("Sort By") {
                        Button("Last Played") {
                            let current = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
                            AppSettings.setBool("sortByLastPlayed", value: !current)
                            NotificationCenter.default.post(name: .sortChanged, object: nil)
                        }
                        .keyboardShortcut("P", modifiers: [.command, .shift])
                        
                        Button("Last Added") {
                            let current = AppSettings.getBool("sortByLastAdded", defaultValue: false)
                            AppSettings.setBool("sortByLastAdded", value: !current)
                            NotificationCenter.default.post(name: .sortChanged, object: nil)
                        }
                        .keyboardShortcut("A", modifiers: [.command, .shift])
                    }
                    
                    Divider()
                    
                    // Filters
                    Menu("Filters") {
                        ForEach(GameFilterOption.allCases) { option in
                            Button(option.label) {
                                NotificationCenter.default.post(name: .filterToggled, object: option.rawValue)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Language
                    Menu("Language") {
                        ForEach(EmulatorLanguage.allCases) { lang in
                            Button("\(lang.flagEmoji) \(lang.name)") {
                                AppSettings.set("systemLanguage", value: lang.rawValue)
                                NotificationCenter.default.post(name: .languageChanged, object: nil)
                            }
                        }
                    }
                }
                
                // Library Menu (rename to something unique to avoid conflict with macOS default)
                CommandMenu("Games") {
                    Button("Add ROM Folder…") {
                        NotificationCenter.default.post(name: .addROMFolder, object: nil)
                    }
                    .keyboardShortcut("O", modifiers: [.command, .shift])
                    
                    Button("Rescan Library") {
                        Task { await library.fullRescan() }
                    }
                    .keyboardShortcut("R", modifiers: [.command, .shift])
                    .disabled(library.romFolderURL == nil || library.isScanning)
                    
                    Divider()
                    
                    // Navigation section
                    Section("Library") {
                        Button("All Games") {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "all")
                        }
                        
                        Button("Favorites") {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "favorites")
                        }
                        
                        Button("Recent") {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "recent")
                        }
                        
                        Divider()
                        
                        Button("Play History") {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "playHistory")
                        }
                        .keyboardShortcut("H", modifiers: [.command, .shift])
                    }
                    
                    Divider()
                    
                    // Systems submenu - only show systems that have games
                    Menu("Systems") {
                        let ids = Set(library.roms.compactMap { $0.systemID })
                        let displaySystems = SystemDatabase.systemsForDisplay.filter { system in
                            let internalIDs = SystemDatabase.allInternalIDs(forDisplayID: system.id)
                            return internalIDs.contains { ids.contains($0) }
                        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        
                        ForEach(displaySystems) { system in
                            Button(system.name) {
                                NotificationCenter.default.post(name: .navigateToFilter, object: "system-\(system.id)")
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Settings submenu
                    Menu("Settings") {
                        Button("Controllers") {
                            UserDefaults.standard.set("controllers", forKey: "settings_selectedTab")
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                        
                        Button("Shaders / Display") {
                            UserDefaults.standard.set("display", forKey: "settings_selectedTab")
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                        
                        Button("Cheats") {
                            UserDefaults.standard.set("cheats", forKey: "settings_selectedTab")
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                        
                        Button("Bezels") {
                            UserDefaults.standard.set("bezels", forKey: "settings_selectedTab")
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                        
                        Divider()
                        
                        Button("Cores…") {
                            UserDefaults.standard.set("cores", forKey: "settings_selectedTab")
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                        
                        Button("Box Art") {
                            UserDefaults.standard.set("boxArt", forKey: "settings_selectedTab")
                            NotificationCenter.default.post(name: .openAppSettings, object: nil)
                        }
                    }
                }
            }
        }
        
        WindowGroup(id: "game-info", for: UUID.self) { $romID in
            GameInfoWindow(romID: romID ?? UUID())
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
                .environment(systemDatabase)
        }

        WindowGroup(id: "core-options", for: String.self) { $coreID in
            if let coreID = coreID {
                CoreOptionsView(coreID: coreID)
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
                    .environment(systemDatabase)
            }
        }

        WindowGroup(id: "system-settings", for: SystemSettingsRequest.self) { $request in
            if let request = request {
                let initialPage: SettingsView.Page? = {
                    switch request.page {
                    case .bezels: return .bezels
                    case .controllers: return .controllers
                    case .cheats: return .cheats
                    case .general, .library, .cores, .boxArt, .display, .retroAchievements, .genre, .logging, .about:
                        return request.page
                    }
                }()
                SettingsView(system: request.system, initialPage: initialPage)
                    .environmentObject(library)
                    .environmentObject(categoryManager)
                    .environmentObject(coreManager)
                    .environmentObject(controllerService)
                    .environment(systemDatabase)
            }
        }
        
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
                .environment(systemDatabase)
        }
        
        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(categoryManager)
                .environmentObject(coreManager)
                .environmentObject(controllerService)
                .environment(systemDatabase)
        }
    }
}

// Wrapper view that runs first-run DAT pre-population before showing content.
// MAME dictionary loading is deferred to lazy/on-demand loading.
// Checks the prepopulation flag synchronously to avoid showing the loading view
// on subsequent launches.
struct ContentWithPrepopulationView: View {
    @State private var isPrepopulated: Bool
    @State private var isRunningPrepopulation = false
    
    @EnvironmentObject var library: ROMLibrary
    
    init() {
        // Check synchronously so we skip the loading view on subsequent launches
        _isPrepopulated = State(initialValue: AppSettings.getBool("dat_prepopulation_done_v1", defaultValue: false))
    }
    
    // Whether we need to show the loading view
    private var needsLoading: Bool {
        !isPrepopulated
    }
    
    var body: some View {
        Group {
            if !needsLoading {
                ContentView()
                    .environmentObject(library)
            } else {
                ProgressView("Initializing game database…")
                    .frame(width: 200)
                    .task {
                        await performInitialization()
                    }
            }
        }
    }
    
    private func performInitialization() async {
        // Perform DAT pre-population if needed
        if !isPrepopulated {
            isRunningPrepopulation = true
            _ = await DATPrepopulationService.ensureDATsArePopulated()
            isRunningPrepopulation = false
            isPrepopulated = true
        }

        // Ensure core mappings are present and up-to-date
        if await LibretroInfoManager.shouldRefreshInfo() {
            LoggerService.info(category: "App", "Core info is missing or stale. Refreshing during initialization...")
            await LibretroInfoManager.shared.refreshCoreInfo()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    // Track if this instance was launched via CLI
    private var isCLILaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--launch")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the delegate for notification center to handle foreground notifications
        UNUserNotificationCenter.current().delegate = self
        
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
            self.removeEditMenu()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                willPresent notification: UNNotification, 
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Allow the notification to show as a banner even when the app is in the foreground
        completionHandler([.banner, .sound])
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
    
    // Remove any saved state for the game-info window to prevent restoration on launch.
    // Called during applicationWillFinishLaunching to clear UserDefaults before macOS restores windows.
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
    
    // Close any game-info windows that were restored despite UserDefaults cleanup.
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
    
    // Remove the unused Edit menu from the menu bar
    private func removeEditMenu() {
        if let editMenu = NSApp.mainMenu?.item(withTitle: "Edit") {
            NSApp.mainMenu?.removeItem(editMenu)
        }
    }
}
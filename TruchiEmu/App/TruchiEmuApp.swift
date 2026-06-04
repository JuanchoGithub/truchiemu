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
    static let gameLoaded = Notification.Name("gameLoaded")
    static let checkForUpdatesFromMenu = Notification.Name("checkForUpdatesFromMenu")
    static let showWhatsNewFromMenu = Notification.Name("showWhatsNewFromMenu")
static let showChangelogFromMenu = Notification.Name("showChangelogFromMenu")
    static let openHelpWindow = Notification.Name("openHelpWindow")
  }

@main
struct TruchiEmuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var loc = LocalizationManager.shared

    // SwiftData container manages all persistence.
    // The container handles one-time migration on first launch.
    init() {
        _ = SwiftDataContainer.shared
        _ = LoggerService.shared
        _ = ThemeManager.shared
        _ = SaveDirectoryManager.shared
        CoreOverrideService.shared.syncBundledOverridesToAppSupport()
        
        // MAME dictionary loading is deferred to background tasks in ContentWithPrepopulationView
        // 1. Connect the Bridge to your existing LoggerService
LibretroBridgeSwift.registerCoreLogger { message, level in
// Filter out PPSSPP's excessive frame-by-frame FBO logs
if message.contains("[Core-DGB]") { return }
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

  private func openHelpWindow() {
    NotificationCenter.default.post(name: .openHelpWindow, object: nil)
  }

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

    private func checkForAppUpdates() {
        Task { @MainActor in
            guard AppUpdateService.shared.shouldAutoCheck() else { return }
            if let release = await AppUpdateService.shared.checkForUpdates() {
                NotificationHistoryManager.shared.post(
                    icon: "arrow.down.circle.fill",
                    title: loc.localized("update.availableTitle"),
                    subtitle: loc.localized("update.availableSubtitle") + " \(release.version)",
                    autoDismissDelay: 15,
                    actionLabel: loc.localized("update.viewUpdate"),
                    actionType: "viewUpdate",
                    actionPayload: release.version
                )
            }
        }
    }

    private func registerNotificationActionHandlers() {
        let historyManager = NotificationHistoryManager.shared
        historyManager.library = library

        historyManager.registerActionHandler(type: "undoHide") { entry in
            guard let payload = entry.decodePayload(ROMActionPayload.self),
                  let lib = historyManager.library else { return false }
            if let index = lib.roms.firstIndex(where: { $0.id == payload.romID }) {
                lib.roms[index].isHidden = false
                lib.updateROM(lib.roms[index])
                return true
            }
            return false
        }

        historyManager.registerActionHandler(type: "undoTrash") { entry in
            guard let payload = entry.decodePayload(TrashActionPayload.self),
                  let lib = historyManager.library else { return false }
            let originalURL = URL(fileURLWithPath: payload.originalPath)
            var restored = false

            if let trashPath = AppSettings.getString("pendingTrashRestore_\(payload.romID.uuidString)") {
                let trashURL = URL(fileURLWithPath: trashPath)
                do {
                    let destination = originalURL
                    if !FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) {
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    }
                    if FileManager.default.fileExists(atPath: trashURL.path) {
                        try FileManager.default.moveItem(at: trashURL, to: destination)
                        restored = true
                        LoggerService.info(category: "NotificationHistory", "ROM restored from trash: \(originalURL.lastPathComponent)")
                    }
                } catch {
                    LoggerService.warning(category: "NotificationHistory", "Failed to restore ROM from trash: \(error.localizedDescription)")
                }
                AppSettings.remove("pendingTrashRestore_\(payload.romID.uuidString)")
            }

            if restored {
                if let romData = payload.romJSON.data(using: .utf8),
                   let rom = try? JSONDecoder().decode(ROM.self, from: romData) {
                    lib.roms.append(rom)
                    LibraryMetadataStore.shared.persist(rom: rom)
                    LibraryMetadataStore.shared.flushDirtyToSwiftData()
                    let repo = ROMRepository(context: SwiftDataContainer.shared.mainContext)
                    repo.saveROM(rom)
                    lib.updateCounts()
                    return true
                }
            }
            return false
        }

        historyManager.registerActionHandler(type: "undoSaveDelete") { entry in
            guard let payload = entry.decodePayload(SaveDeleteActionPayload.self) else { return false }
            var restored = false
            for pair in payload.filePairs where pair.count == 2 {
                let originalPath = pair[0]
                let undoPath = pair[1]
                let undoURL = URL(fileURLWithPath: undoPath)
                let originalURL = URL(fileURLWithPath: originalPath)
                if FileManager.default.fileExists(atPath: undoURL.path) {
                    try? FileManager.default.moveItem(at: undoURL, to: originalURL)
                    restored = true
                }
            }
            return restored
        }

        historyManager.registerActionHandler(type: "viewUpdate") { entry in
            AppSettings.set("settings_selectedTab", value: "about")
            NotificationCenter.default.post(name: .openAppSettings, object: nil)
            return true
        }
    }
    
var body: some Scene {
    WindowGroup {
      ContentWithPrepopulationView()
        .tint(AppColors.brandAccentSecondary)
        .environmentObject(library)
        .environmentObject(categoryManager)
        .environmentObject(coreManager)
        .environmentObject(controllerService)
        .environmentObject(LibraryAutomationCoordinator.shared)
        .environmentObject(mameVerification)
        .environment(systemDatabase)
        .onAppear {
          startMAMEVerificationIfNeeded()
          registerNotificationActionHandlers()
          checkForAppUpdates()
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

            CommandGroup(replacing: .appInfo) {
                Button(loc.localized("about.title")) {
                    AppSettings.set("settings_selectedTab", value: "about")
                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button(loc.localized("app.settings")) {
                    AppSettings.set("settings_selectedTab", value: "general")
                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(before: .appTermination) {
                Divider()

                Button(loc.localized("update.checkForUpdates")) {
                    AppSettings.set("settings_selectedTab", value: "about")
                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: .checkForUpdatesFromMenu, object: nil)
                    }
                }

                Button(loc.localized("update.whatsNew")) {
                    AppSettings.set("settings_selectedTab", value: "about")
                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: .showWhatsNewFromMenu, object: nil)
                    }
                }

                Button(loc.localized("update.changelog")) {
                    AppSettings.set("settings_selectedTab", value: "about")
                    NotificationCenter.default.post(name: .openAppSettings, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NotificationCenter.default.post(name: .showChangelogFromMenu, object: nil)
                    }
                }
            }
                
                // Add to the default View menu (macOS provides Zoom, Enter Full Screen)
                CommandGroup(after: .toolbar) {
                    Divider()
                    
                    // View Mode
                    Section(loc.localized("app.viewMode")) {
                        Button(loc.localized("app.grid")) {
                            AppSettings.set("gridViewMode", value: "grid")
                            NotificationCenter.default.post(name: .viewModeChanged, object: "grid")
                        }
                        .keyboardShortcut("1", modifiers: .command)

                        Button(loc.localized("app.list")) {
                            AppSettings.set("gridViewMode", value: "list")
                            NotificationCenter.default.post(name: .viewModeChanged, object: "list")
                        }
                        .keyboardShortcut("2", modifiers: .command)
                    }
                    
                    Divider()
                    
                    // Box Art
                    Menu(loc.localized("app.boxArt")) {
                        Button(AppSettings.getBool("showBoxArt", defaultValue: true) ? loc.localized("app.hideBoxArt") : loc.localized("app.showBoxArt")) {
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
                    Menu(loc.localized("app.sortBy")) {
                        Button(loc.localized("app.lastPlayed")) {
                            let current = AppSettings.getBool("sortByLastPlayed", defaultValue: false)
                            AppSettings.setBool("sortByLastPlayed", value: !current)
                            NotificationCenter.default.post(name: .sortChanged, object: nil)
                        }
                        .keyboardShortcut("P", modifiers: [.command, .shift])

                        Button(loc.localized("app.lastAdded")) {
                            let current = AppSettings.getBool("sortByLastAdded", defaultValue: false)
                            AppSettings.setBool("sortByLastAdded", value: !current)
                            NotificationCenter.default.post(name: .sortChanged, object: nil)
                        }
                        .keyboardShortcut("A", modifiers: [.command, .shift])
                    }
                    
                    Divider()
                    
                    // Filters
                    Menu(loc.localized("app.filters")) {
                        ForEach(GameFilterOption.allCases) { option in
                            Button(option.label) {
                                NotificationCenter.default.post(name: .filterToggled, object: option.rawValue)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Menu(loc.localized("app.language")) {
                        ForEach(loc.availableLanguages, id: \.self) { lang in
                            Button(languageDisplayName(for: lang)) {
                                loc.setLanguage(lang)
                                NotificationCenter.default.post(name: .languageChanged, object: nil)
                            }
                        }
                    }
                }
                
                CommandGroup(replacing: .help) {
        Button(loc.localized("help.menu.documentation")) {
          if let url = URL(string: HelpContent.docsBaseURL) { NSWorkspace.shared.open(url) }
        }
        Button(loc.localized("help.menu.gettingStarted")) {
          if let url = URL(string: "\(HelpContent.docsBaseURL)/getting-started.html") { NSWorkspace.shared.open(url) }
        }
        Button(loc.localized("help.menu.troubleshooting")) {
          if let url = URL(string: "\(HelpContent.docsBaseURL)/troubleshooting.html") { NSWorkspace.shared.open(url) }
        }
        Button(loc.localized("help.menu.supportedSystems")) {
          if let url = URL(string: "\(HelpContent.docsBaseURL)/systems.html") { NSWorkspace.shared.open(url) }
        }

        Divider()

        Button(loc.localized("help.menu.keyboardShortcuts")) {
          openHelpWindow()
        }
        .keyboardShortcut("/", modifiers: .command)

        Divider()

        Button(loc.localized("help.menu.github")) {
          if let url = URL(string: "https://github.com/JuanchoGithub/truchiemu") { NSWorkspace.shared.open(url) }
        }
      }

      // Library Menu (rename to something unique to avoid conflict with macOS default)
                CommandMenu(loc.localized("app.games")) {
                    Button(loc.localized("app.addROMFolder")) {
                        NotificationCenter.default.post(name: .addROMFolder, object: nil)
                    }
                    .keyboardShortcut("O", modifiers: [.command, .shift])

                    Button(loc.localized("app.rescanLibrary")) {
                        Task { await library.fullRescan() }
                    }
                    .keyboardShortcut("R", modifiers: [.command, .shift])
                    .disabled(library.romFolderURL == nil || library.isScanning)

                    Divider()

                    // Navigation section
                    Section(loc.localized("app.library")) {
                        Button(loc.localized("app.allGames")) {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "all")
                        }

                        Button(loc.localized("app.favorites")) {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "favorites")
                        }

                        Button(loc.localized("app.recent")) {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "recent")
                        }

                        Divider()

                        Button(loc.localized("app.playHistory")) {
                            NotificationCenter.default.post(name: .navigateToFilter, object: "playHistory")
                        }
                        .keyboardShortcut("H", modifiers: [.command, .shift])
                    }

                    Divider()

                    // Systems submenu - only show systems that have games
                    Menu(loc.localized("app.systems")) {
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
                    Menu(loc.localized("app.settings")) {
        Button(loc.localized("app.controllers")) {
                AppSettings.set("settings_selectedTab", value: "controllers")
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }

            Button(loc.localized("app.shadersDisplay")) {
                AppSettings.set("settings_selectedTab", value: "display")
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }

            Button(loc.localized("app.cheats")) {
                AppSettings.set("settings_selectedTab", value: "cheats")
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }

            Button(loc.localized("app.bezels")) {
                AppSettings.set("settings_selectedTab", value: "bezels")
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }

            Divider()

            Button(loc.localized("app.cores")) {
                AppSettings.set("settings_selectedTab", value: "cores")
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }

            Button(loc.localized("app.boxArtSettings")) {
                AppSettings.set("settings_selectedTab", value: "boxArt")
                NotificationCenter.default.post(name: .openAppSettings, object: nil)
            }
                    }
                }
            }
        }
        
    WindowGroup(id: "game-info", for: UUID.self) { $romID in
        GameInfoWindow(romID: romID ?? UUID())
            .tint(AppColors.brandAccentSecondary)
            .environmentObject(library)
            .environmentObject(categoryManager)
            .environmentObject(coreManager)
            .environmentObject(controllerService)
            .environment(systemDatabase)
    }

  WindowGroup(id: "core-options", for: String.self) { $coreID in
      if let coreID = coreID {
        CoreOptionsView(coreID: coreID)
          .tint(AppColors.brandAccentSecondary)
          .environmentObject(library)
          .environmentObject(categoryManager)
          .environmentObject(coreManager)
          .environmentObject(controllerService)
          .environment(systemDatabase)
      }
    }

  WindowGroup(id: "help") {
    HelpWindowView()
      .tint(AppColors.brandAccentSecondary)
  }

  Settings {
        SettingsView()
            .tint(AppColors.brandAccentSecondary)
            .environmentObject(library)
            .environmentObject(categoryManager)
            .environmentObject(coreManager)
            .environmentObject(controllerService)
            .environment(systemDatabase)
    }
    }
}

// MARK: - Language Display Name Helper
private func languageDisplayName(for lang: String) -> String {
    switch lang.lowercased() {
    case "en": return "English"
    case "es": return "Español"
    case "pt": return "Português"
    default: return lang.uppercased()
    }
}

// Wrapper view that runs first-run DAT pre-population before showing content.
// MAME dictionary loading is deferred to lazy/on-demand loading.
// Checks the prepopulation flag synchronously to avoid showing the loading view
// on subsequent launches.
struct ContentWithPrepopulationView: View {
  @State private var isPrepopulated: Bool
  @State private var isRunningPrepopulation = false
  @State private var showInstallDrag = false
  @ObservedObject private var loc = LocalizationManager.shared
  @EnvironmentObject var library: ROMLibrary
  @Environment(\.openWindow) private var openWindow
    
    init() {
        // Check synchronously so we skip the loading view on subsequent launches
        _isPrepopulated = State(initialValue: AppSettings.getBool("dat_prepopulation_done_v1", defaultValue: false))
        _showInstallDrag = State(initialValue: InstallDragView.shouldShow())
    }
    
    // Whether we need to show the loading view
    private var needsLoading: Bool {
        !isPrepopulated
    }
    
    var body: some View {
        Group {
            if showInstallDrag {
                InstallDragView()
                    .onReceive(NotificationCenter.default.publisher(for: .installDragCompleted)) { _ in
                        showInstallDrag = false
                    }
            } else if !needsLoading {
                ContentView()
                    .environmentObject(library)
            } else {
                ProgressView(loc.localized("app.initializingDatabase"))
                    .frame(width: 200)
                    .task {
                        await performInitialization()
                    }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .openHelpWindow)) { _ in
      openWindow(id: "help")
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

        // Set up RetroAchievementsService with SwiftData context
        RetroAchievementsService.shared.setModelContext(SwiftDataContainer.shared.container.mainContext)

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
    
    // Setup periodic log maintenance timer (every 12 hours)
    Timer.scheduledTimer(withTimeInterval: 12 * 60 * 60, repeats: true) { _ in
      LoggerService.debug(category: "App", "Running periodic log maintenance")
      LogManager.shared.cleanupOldRotatedLogs()
      LogManager.shared.quickTrimLog()
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
        return isCLILaunch
    }

    func applicationWillTerminate(_ notification: Notification) {
        XPCConnectionManager.shared.forceKillServiceForAppExit()
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Apply saved appearance mode before SwiftUI renders any views
        ThemeManager.shared.applySavedAppearance()

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
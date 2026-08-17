import Foundation
import Combine
import SwiftUI
import GameController

// Manages the state of the first-run setup wizard
@MainActor
final class SetupWizardState: ObservableObject {
    static let shared = SetupWizardState()
    
    enum WizardStep: Int, CaseIterable, Identifiable {
        var id: Int { rawValue }
        
        // Phase 1: Welcome + Add game folders (combined)
        case getStarted = 0
        // Phase 2: Theme + Bezels + Shaders (visual preferences)
        case lookAndFeel = 1
        // Phase 3: Feature catalog checklist (select what to enable)
        case featureCatalog = 2
        // Phase 4: RetroAchievements setup (conditional, only if selected)
        case achievementsSetup = 3
        // Phase 5: Streaming setup (conditional, only if selected)
        case streamingSetup = 4
        // Phase 6: Completion
        case completion = 5
        
        var title: String {
            switch self {
            case .getStarted: return "Get Started"
            case .lookAndFeel: return "Look & Feel"
            case .featureCatalog: return "Optional Features"
            case .achievementsSetup: return "Achievements"
            case .streamingSetup: return "Streaming"
            case .completion: return "You're All Set"
            }
        }
        
        var icon: String {
            switch self {
            case .getStarted: return "folder.badge.gearshape"
            case .lookAndFeel: return "tv"
            case .featureCatalog: return "gearshape"
            case .achievementsSetup: return "trophy"
            case .streamingSetup: return "antenna.radiowaves.left.and.right"
            case .completion: return "checkmark.circle.fill"
            }
        }

        var localizationKey: String {
            switch self {
            case .getStarted: return "wizard.step.getStarted"
            case .lookAndFeel: return "wizard.step.lookAndFeel"
            case .featureCatalog: return "wizard.step.featureCatalog"
            case .achievementsSetup: return "wizard.step.achievementsSetup"
            case .streamingSetup: return "wizard.step.streamingSetup"
            case .completion: return "wizard.step.completion"
            }
        }
        
        // Whether this step can be skipped
        var canSkip: Bool {
            switch self {
            case .getStarted: return true
            case .lookAndFeel: return true
            case .featureCatalog: return true
            case .achievementsSetup: return true
            case .streamingSetup: return true
            case .completion: return false
            }
        }
    }
    
    // MARK: - Published State
    
    @Published var currentStep: WizardStep = .getStarted
    @Published var libraryFolders: [URL] = []
    @Published var downloadBezels: Bool = false
    @Published var selectedShaderPresetID: String = ""
    @Published var selectedRegion: EmulatorLanguage = .northAmerica
    @Published var selectedTheme: AccentColorTheme = .megaMan {
        didSet {
            // Apply theme live for immediate preview in the wizard without restart.
            // Skips persistence here — saved in finishSetup(); if the user backs out / re-runs
            // the wizard without finishing, we revert below.
            if oldValue != selectedTheme {
                ThemeManager.shared.applyTheme(selectedTheme)
            }
        }
    }
    @Published var controllerDetected: Bool = false
    @Published var detectedControllerName: String = ""
    
    // Feature catalog selections
    @Published var featureCheats: Bool = false
    @Published var featureCheatsDownload: Bool = false
    @Published var featureRetroAchievements: Bool = false
    @Published var featureStreaming: Bool = false
    @Published var featureLaunchBox: Bool = false
    @Published var featureAccessibility: Bool = false
    @Published var featureTimeMachine: Bool = false
    
    // RetroAchievements setup
    @Published var achievementsUsername: String = ""
    @Published var achievementsPassword: String = ""
    @Published var achievementsWebApiKey: String = ""
    @Published var achievementsHardcore: Bool = false
    
    // Streaming setup (simplified). One keyed string per destination so the user can see
    // keys already saved for non-active destinations when switching between them.
    @Published var streamingEnabled: Bool = false
    @Published var streamingQuality: RecordingQuality = .high
    @Published var streamingDestination: StreamingMode = .twitch
    @Published var streamingTwitchKey: String = ""
    @Published var streamingYouTubeKey: String = ""
    @Published var streamingCustomKey: String = ""
    
    /// Returns the stream key for the currently-selected destination.
    var streamingStreamKey: String {
        get {
            switch streamingDestination {
            case .twitch:  return streamingTwitchKey
            case .youtube: return streamingYouTubeKey
            case .custom:  return streamingCustomKey
            case .localFile: return ""
            }
        }
        set {
            switch streamingDestination {
            case .twitch:  streamingTwitchKey = newValue
            case .youtube: streamingYouTubeKey = newValue
            case .custom:  streamingCustomKey = newValue
            case .localFile: break
            }
        }
    }
    
    // Scanning state (provided by ROMLibrary)
    @Published var detectedGamesWithBoxArt: [SetupWizardGameInfo] = []
    @Published var allDetectedGames: [SetupWizardGameInfo] = []
    
    // Bezel download state
    @Published var bezelDownloadProgress: Double = 0
    @Published var isDownloadingBezels: Bool = false
    
    // Cheat download state
    @Published var cheatDownloadProgress: Double = 0
    @Published var isDownloadingCheats: Bool = false
    
    // Completion state: the single source is `has_completed_onboarding`
    // (persisted via AppSettings), mirrored by `ROMLibrary.hasCompletedOnboarding`.
    // There is intentionally no second flag here — `has_completed_full_setup`
    // was removed to avoid two independently-written completions drifting.
    
    private var controllerCancellables = Set<AnyCancellable>()
    
    private init() {
        refreshControllerDetection()
        setupControllerNotifications()
        prefillFromExistingSettings()
    }
    
    /// Pre-fill the wizard state from existing persisted settings (for re-runs from Settings).
    /// On first run these defaults are all empty / off, which is the same as the static default values.
    func prefillFromExistingSettings() {
        // Theme
        if let raw = AppSettings.get("accentTheme", type: String.self),
           let theme = AccentColorTheme(rawValue: raw) {
            selectedTheme = theme
        } else {
            selectedTheme = ThemeManager.shared.currentTheme
        }
        
        // Region + shader
        let langRaw = Int(AppSettings.get("coreSystemLanguage", type: String.self) ?? "0") ?? 0
        if let lang = EmulatorLanguage(rawValue: langRaw) {
            selectedRegion = lang
        }
        if let shader = AppSettings.getString("display_default_shader_preset"), !shader.isEmpty {
            selectedShaderPresetID = shader
        }
        
        // Bezels download state — assume already downloaded if any bezel storage is set up
        let bezelSetupDone = AppSettings.getBool("BezelInitialSetupComplete", defaultValue: false)
        downloadBezels = bezelSetupDone ? false : false  // default to off; user can re-check
        
        // Cheats
        featureCheats = AppSettings.getBool("cheats_enabled", defaultValue: false)
        
        // RetroAchievements
        featureRetroAchievements = AppSettings.getBool("ra_enabled", defaultValue: false)
        achievementsUsername = AppSettings.get("ra_username", type: String.self) ?? ""
        achievementsWebApiKey = AppSettings.get("ra_web_api_key", type: String.self) ?? ""
        achievementsHardcore = AppSettings.getBool("ra_hardcore", defaultValue: false)
        
        // LaunchBox
        featureLaunchBox = AppSettings.getBool("launchbox_use_for_boxart", defaultValue: false)

        // Time Machine (defaults to on at runtime)
        featureTimeMachine = AppSettings.getBool("timeMachine_enabled", defaultValue: true)

        // Streaming
        let streamingOn = AppSettings.getBool("streaming_enabled", defaultValue: false)
        featureStreaming = streamingOn
        streamingEnabled = streamingOn
        if let qRaw = AppSettings.getString("streaming_quality"),
           let q = RecordingQuality(rawValue: qRaw) {
            streamingQuality = q
        }
        if let mRaw = AppSettings.getString("streaming_mode"),
           let m = StreamingMode(rawValue: mRaw) {
            streamingDestination = m
        }
        // Pre-fill all per-destination keys so swapping destinations in the wizard shows the saved values.
        streamingTwitchKey  = AppSettings.getString("streaming_twitch_key")  ?? ""
        streamingYouTubeKey = AppSettings.getString("streaming_youtube_key") ?? ""
        streamingCustomKey  = AppSettings.getString("streaming_custom_key")  ?? ""
        
        // Accessibility
        featureAccessibility = InputCaptureManager.shared.hasAccessibilityPermissions
    }
    
    /// Reset wizard state for a re-run from Settings. Resets step and re-prefills.
    func resetForReRun() {
        currentStep = .getStarted
        prefillFromExistingSettings()
    }

    
    private func setupControllerNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshControllerDetection() }
            .store(in: &controllerCancellables)
        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshControllerDetection() }
            .store(in: &controllerCancellables)
    }
    
    func refreshControllerDetection() {
        let controllers = GCController.controllers()
        if let first = controllers.first {
            controllerDetected = true
            detectedControllerName = first.vendorName ?? "Controller"
        } else {
            controllerDetected = false
            detectedControllerName = ""
        }
    }
    
    // MARK: - Dynamic Step Navigation
    
    /// Visible steps in the current run, computing conditional sub-steps.
    var visibleSteps: [WizardStep] {
        WizardStep.allCases.filter { step in
            switch step {
            case .achievementsSetup: return featureRetroAchievements
            case .streamingSetup: return featureStreaming
            default: return true
            }
        }
    }
    
    /// All-step index paths for the progress bar.
    private var allSteps: [WizardStep] {
        [.getStarted, .lookAndFeel, .featureCatalog, .achievementsSetup, .streamingSetup, .completion]
    }
    
    var totalSteps: Int { visibleSteps.count }
    var currentStepIndex: Int {
        visibleSteps.firstIndex(of: currentStep) ?? 0
    }
    var progress: Double {
        guard totalSteps > 1 else { return 1.0 }
        return Double(currentStepIndex) / Double(totalSteps - 1)
    }
    
    func nextStep() {
        guard let idx = visibleSteps.firstIndex(of: currentStep),
              idx + 1 < visibleSteps.count else { return }
        currentStep = visibleSteps[idx + 1]
    }
    
    func previousStep() {
        guard let idx = visibleSteps.firstIndex(of: currentStep),
              idx > 0 else { return }
        currentStep = visibleSteps[idx - 1]
    }
    
    // MARK: - Library Folder Management
    
    func addLibraryFolder(_ url: URL) {
        if !libraryFolders.contains(url) {
            libraryFolders.append(url)
        }
    }
    
    func removeLibraryFolder(at index: Int) {
        guard index < libraryFolders.count else { return }
        libraryFolders.remove(at: index)
    }
    
    // MARK: - Update detected games from library
    
    func updateDetectedGames(from roms: [ROM]) {
        var withBoxArt: [SetupWizardGameInfo] = []
        var allGames: [SetupWizardGameInfo] = []
        
        let limitedROMs = roms.prefix(50)
        for rom in limitedROMs {
            var boxArtImage: NSImage? = nil
            if rom.hasBoxArt {
                boxArtImage = NSImage(contentsOf: rom.boxArtLocalPath)
            }
            
            let systemName = SystemDatabase.system(forID: rom.systemID ?? "")?.name ?? rom.systemID ?? "Unknown"
            let info = SetupWizardGameInfo(
                rom: rom,
                displayName: rom.displayName,
                systemName: systemName,
                boxArt: boxArtImage,
                hasBoxArt: boxArtImage != nil
            )
            
            allGames.append(info)
            if boxArtImage != nil {
                withBoxArt.append(info)
            }
        }
        
        self.allDetectedGames = allGames
        self.detectedGamesWithBoxArt = withBoxArt
    }
    
    // MARK: - Downloads
    
    func downloadBezelsFromWizard() async {
        guard downloadBezels else { return }
        LoggerService.info(category: "Wizard", "Downloading bezels...")
        isDownloadingBezels = true
        bezelDownloadProgress = 0
        
        _ = await BezelAPIService.shared.downloadAllSystems()
        
        bezelDownloadProgress = 1.0
        isDownloadingBezels = false
        LoggerService.info(category: "Wizard", "Bezel download complete.")
    }
    
    func downloadCheatsFromWizard() async {
        guard featureCheatsDownload else { return }
        LoggerService.info(category: "Wizard", "Downloading cheats...")
        isDownloadingCheats = true
        cheatDownloadProgress = 0
        
        _ = await CheatDownloadService.shared.downloadAllCheats()
        
        cheatDownloadProgress = 1.0
        isDownloadingCheats = false
        LoggerService.info(category: "Wizard", "Cheat download complete.")
    }
    
    private func isInternalPath(_ url: URL) -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return url.path.hasPrefix(appSupport.appendingPathComponent("TruchiEmu").path)
    }
    
    // MARK: - Accessibility
    
    func requestAccessibilityPermission() {
        InputCaptureManager.shared.requestAccessibilityPermissions()
    }
    
    var hasAccessibilityPermissions: Bool {
        InputCaptureManager.shared.hasAccessibilityPermissions
    }
    
    // MARK: - List of summary items for completion step
    
    var enabledFeaturesSummary: [String] {
        var items: [String] = []
        if featureCheats {
            items.append("wizard.summary.cheats")
        }
        if featureRetroAchievements {
            items.append("wizard.summary.achievements")
        }
        if featureStreaming {
            items.append("wizard.summary.streaming")
        }
        if featureLaunchBox {
            items.append("wizard.summary.launchbox")
        }
        if featureTimeMachine {
            items.append("wizard.summary.timeMachine")
        }
        if featureAccessibility {
            items.append("wizard.summary.accessibility")
        }
        if downloadBezels {
            items.append("wizard.summary.bezels")
        }
        return items
    }
}

// MARK: - Game Info for Wizard

struct SetupWizardGameInfo: Identifiable {
    let id = UUID()
    let rom: ROM
    let displayName: String
    let systemName: String
    let boxArt: NSImage?
    let hasBoxArt: Bool
}

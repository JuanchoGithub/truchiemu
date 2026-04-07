import Foundation
import Combine
import SwiftUI
import GameController

/// Manages the state of the first-run setup wizard
@MainActor
final class SetupWizardState: ObservableObject {
    static let shared = SetupWizardState()
    
    enum WizardStep: Int, CaseIterable, Identifiable {
        var id: Int { rawValue }
        
        /// Phase 1: Welcome + Add game folders (combined)
        case getStarted = 0
        /// Phase 2: Bezels + Shaders (visual preferences)
        case lookAndFeel = 1
        /// Phase 3: Cheats + Achievements + Logging (optional features)
        case optionalFeatures = 2
        /// Phase 4: Completion
        case completion = 3
        
        var title: String {
            switch self {
            case .getStarted: return "Get Started"
            case .lookAndFeel: return "Look & Feel"
            case .optionalFeatures: return "Optional Features"
            case .completion: return "You're All Set"
            }
        }
        
        var icon: String {
            switch self {
            case .getStarted: return "folder.badge.gearshape"
            case .lookAndFeel: return "tv"
            case .optionalFeatures: return "gearshape"
            case .completion: return "checkmark.circle.fill"
            }
        }
        
        /// Whether this step can be skipped
        var canSkip: Bool {
            switch self {
            case .getStarted: return true
            case .lookAndFeel: return true
            case .optionalFeatures: return true
            case .completion: return false
            }
        }
    }
    
    // MARK: - Published State
    
    @Published var currentStep: WizardStep = .getStarted
    @Published var libraryFolders: [URL] = []
    @Published var downloadBezels: Bool = false
    @Published var downloadCheats: Bool = false
    @Published var achievementsEnabled: Bool = false
    @Published var achievementsUsername: String = ""
    @Published var achievementsPassword: String = ""
    @Published var loggingEnabled: Bool = false
    @Published var selectedShaderPresetID: String = "builtin-crt-classic"
    @Published var controllerDetected: Bool = false
    @Published var detectedControllerName: String = ""
    
    // Scanning state (provided by ROMLibrary)
    @Published var detectedGamesWithBoxArt: [SetupWizardGameInfo] = []
    @Published var allDetectedGames: [SetupWizardGameInfo] = []
    
    // Bezel download state
    @Published var bezelDownloadProgress: Double = 0
    @Published var isDownloadingBezels: Bool = false
    
    // Cheat download state
    @Published var cheatDownloadProgress: Double = 0
    @Published var isDownloadingCheats: Bool = false
    
    // Completion state
    var hasCompletedWizard: Bool {
        get { AppSettings.getBool("has_completed_full_setup", defaultValue: false) }
        set { AppSettings.setBool("has_completed_full_setup", value: newValue) }
    }
    
    private var controllerCancellables = Set<AnyCancellable>()
    
    private init() {
        refreshControllerDetection()
        setupControllerNotifications()
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
    
    var totalSteps: Int { WizardStep.allCases.count }
    var currentStepIndex: Int { currentStep.rawValue }
    var progress: Double {
        Double(currentStepIndex) / Double(totalSteps - 1)
    }
    
    func nextStep() {
        if let next = WizardStep(rawValue: currentStepIndex + 1) {
            currentStep = next
        }
    }
    
    func previousStep() {
        if let prev = WizardStep(rawValue: currentStepIndex - 1) {
            currentStep = prev
        }
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
        let fm = FileManager.default
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
        guard downloadCheats else { return }
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
        return url.path.hasPrefix(appSupport.appendingPathComponent("TruchieEmu").path)
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

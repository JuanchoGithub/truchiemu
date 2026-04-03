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
        
        case welcome = 0
        case gameFolders = 1
        case bezels = 2
        case cheats = 3
        case achievements = 4
        case logging = 5
        case shaders = 6
        case controllers = 7
        case completion = 8
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to TruchieEmu"
            case .gameFolders: return "Add Your Games"
            case .bezels: return "Bezels"
            case .cheats: return "Cheats"
            case .achievements: return "RetroAchievements"
            case .logging: return "Logging"
            case .shaders: return "Display & Shaders"
            case .controllers: return "Controllers"
            case .completion: return "All Set!"
            }
        }
        
        var icon: String {
            switch self {
            case .welcome: return "hand.wave"
            case .gameFolders: return "folder.badge.gearshape"
            case .bezels: return "rectangle.on.rectangle"
            case .cheats: return "wand.and.stars"
            case .achievements: return "trophy"
            case .logging: return "terminal"
            case .shaders: return "tv"
            case .controllers: return "gamecontroller"
            case .completion: return "checkmark.circle.fill"
            }
        }
    }
    
    // MARK: - Published State
    
    @Published var currentStep: WizardStep = .welcome
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
        get { UserDefaults.standard.bool(forKey: "has_completed_full_setup") }
        set { UserDefaults.standard.set(newValue, forKey: "has_completed_full_setup") }
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
            if let artPath = rom.boxArtPath, fm.fileExists(atPath: artPath.path) {
                boxArtImage = NSImage(contentsOf: artPath)
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
    
    // MARK: - Apply Settings & Complete
    
    func applySettings(to library: ROMLibrary) async {
        // Add all library folders
        for folder in libraryFolders {
            guard !isInternalPath(folder) else { continue }
            if !library.libraryFolders.contains(folder) {
                library.libraryFolders.append(folder)
            }
        }
        library.hasCompletedOnboarding = true
        
        // Apply logging
        UserDefaults.standard.set(loggingEnabled, forKey: "logging_enabled")
        
        // Apply shader preset
        UserDefaults.standard.set(selectedShaderPresetID, forKey: "display_default_shader_preset")
        
        // Apply achievements
        if achievementsEnabled && !achievementsUsername.isEmpty && !achievementsPassword.isEmpty {
            do {
                let token = try await RetroAchievementsService.shared.login(
                    username: achievementsUsername,
                    password: achievementsPassword
                )
                RetroAchievementsService.shared.saveSettings(
                    username: achievementsUsername,
                    token: token
                )
                RetroAchievementsService.shared.setEnabled(true)
            } catch {
                LoggerService.info(category: "Wizard", "Achievements login failed: \(error.localizedDescription)")
            }
        }
        
        // Mark as completed
        hasCompletedWizard = true
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

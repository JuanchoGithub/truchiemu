import Foundation
import Combine

/// Centralized manager for all save directory configurations
/// Provides default, user-customized, and active paths with migration support
public final class SaveDirectoryManager: ObservableObject {
  public static let shared = SaveDirectoryManager()
    
    // MARK: - Published State
    @Published private(set) var activeSaveDirectory: URL
    @Published private(set) var activeSystemDirectory: URL
    @Published private(set) var needsMigration: Bool = false
    
    // MARK: - Private State
    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default
    
    // MARK: - Constants
    private enum Constants {
        static let savesFolderName = "saves"
        static let statesFolderName = "states"
        static let savefilesFolderName = "savefiles"
        static let systemFolderName = "System"
    }
    
    // MARK: - Initialization
    private init() {
        let defaultSave = Self.defaultSaveDirectory
        let defaultSystem = Self.defaultSystemDirectory
        
        self.activeSaveDirectory = AppSettings.getCustomSaveDirectory() ?? defaultSave
        self.activeSystemDirectory = AppSettings.getCustomSystemDirectory() ?? defaultSystem
        
        setupDirectoryStructure()
        checkMigrationStatus()
        
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.refreshFromPreferences()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Default Paths
    static var defaultSaveDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("TruchieEmu")
            .appendingPathComponent(Constants.savesFolderName)
    }
    
    static var defaultSystemDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("TruchieEmu")
            .appendingPathComponent(Constants.systemFolderName)
    }
    
    // MARK: - Derived Paths
    var statesDirectory: URL {
        activeSaveDirectory.appendingPathComponent(Constants.statesFolderName)
    }
    
    var savefilesDirectory: URL {
        activeSaveDirectory.appendingPathComponent(Constants.savefilesFolderName)
    }
    
    var systemDirectory: URL {
        activeSystemDirectory
    }
    
    // MARK: - Public API
    
    /// Updates the user-preferred save directory
    /// - Parameter url: New save directory or nil to reset to default
    /// - Returns: Bool indicating if migration is needed
    @discardableResult
    func setSaveDirectory(_ url: URL?) -> Bool {
        if let url = url {
            guard ensureDirectoryIsWritable(url) else {
                LoggerService.error(category: "SaveDirectoryManager", "Cannot write to directory: \(url)")
                return false
            }
        }
        
        AppSettings.setCustomSaveDirectory(url)
        refreshFromPreferences()
        return needsMigration
    }
    
    /// Updates the user-preferred system directory
    func setSystemDirectory(_ url: URL?) {
        if let url = url {
            guard ensureDirectoryIsWritable(url) else {
                LoggerService.error(category: "SaveDirectoryManager", "Cannot write to directory: \(url)")
                return
            }
        }
        
        AppSettings.setCustomSystemDirectory(url)
        refreshFromPreferences()
    }
    
    /// Performs migration from old to new directories
    /// - Parameter completion: Called with result when complete
    func performMigration(completion: ((Result<Void, Error>) -> Void)? = nil) {
        let oldSaveDir = Self.defaultSaveDirectory
        let newSaveDir = activeSaveDirectory
        
        guard oldSaveDir.path != newSaveDir.path else {
            completion?(.success(()))
            return
        }
        
        guard needsMigration else {
            completion?(.success(()))
            return
        }
        
        let migrationService = SaveMigrationService()
        migrationService.migrate(
            from: oldSaveDir,
            to: newSaveDir,
            completion: { [weak self] result in
                switch result {
                case .success:
                    self?.markMigrationComplete()
                    completion?(.success(()))
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Private Helpers
    
    private func setupDirectoryStructure() {
        createDirectoryIfNeeded(at: statesDirectory)
        createDirectoryIfNeeded(at: savefilesDirectory)
        createDirectoryIfNeeded(at: systemDirectory)
    }
    
    private func createDirectoryIfNeeded(at url: URL) {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            LoggerService.error(category: "SaveDirectoryManager", "Failed to create directory \(url): \(error)")
        }
    }
    
    private func ensureDirectoryIsWritable(_ url: URL) -> Bool {
        return fileManager.isWritableFile(atPath: url.path)
    }
    
    private func refreshFromPreferences() {
        let newSave = AppSettings.getCustomSaveDirectory() ?? Self.defaultSaveDirectory
        let newSystem = AppSettings.getCustomSystemDirectory() ?? Self.defaultSystemDirectory
        
        if newSave.path != activeSaveDirectory.path {
            activeSaveDirectory = newSave
            setupDirectoryStructure()
        }
        
        if newSystem.path != activeSystemDirectory.path {
            activeSystemDirectory = newSystem
            setupDirectoryStructure()
        }
        
        checkMigrationStatus()
    }
    
    private func checkMigrationStatus() {
        let defaultDir = Self.defaultSaveDirectory
        let hasExistingContent = directoryHasContent(defaultDir)
        let userSetDifferent = AppSettings.getCustomSaveDirectory() != nil
        needsMigration = hasExistingContent && userSetDifferent
    }
    
    private func directoryHasContent(_ url: URL) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return false
        }
        return !contents.isEmpty
    }
    
    private func markMigrationComplete() {
        AppSettings.setDate(AppSettings.SaveDirectoryKey.lastMigrationDate, value: Date())
        needsMigration = false
    }
}

// MARK: - Notifications
extension SaveDirectoryManager {
    static let directoryChangedNotification = Notification.Name("SaveDirectoryChanged")
}

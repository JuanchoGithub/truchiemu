import Foundation
import SwiftData

private enum containerLog {
    static func notice(_ message: String) { LoggerService.info(category: "SwiftDataContainer", message) }
    static func fault(_ message: String) { LoggerService.error(category: "SwiftDataContainer", message) }
}

// MARK: - SwiftData Container

// Singleton that manages the SwiftData ModelContainer lifecycle.
@MainActor
final class SwiftDataContainer: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SwiftDataContainer()
    
    // MARK: - Properties
    
    private(set) var container: ModelContainer!
    private(set) var migrationFlag: PersistenceMigrationFlag?
    
    // Primary context for MainActor writes
    var mainContext: ModelContext {
        container.mainContext
    }
    
    // Whether migration has already been completed
    var hasMigrated: Bool {
        migrationFlag?.hasMigrated ?? false
    }
    
    // MARK: - Store Management
    
    // Delete all SwiftData store files to force a fresh schema creation.
    // Used as a fallback when schema migration fails.
    private static func deleteStoreFiles() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        
        // 1. The new organized path
        let truchieFolder = appSupport.appendingPathComponent("TruchieEmu")
        
        // 2. The old "root" path (to clean up the mess)
        let rootStore = appSupport.appendingPathComponent("default.store")
        let rootWal = appSupport.appendingPathComponent("default.store-wal")
        let rootShm = appSupport.appendingPathComponent("default.store-shm")
        
        let targets = [truchieFolder, rootStore, rootWal, rootShm]
        
        for url in targets {
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                    LoggerService.info(category: "SwiftDataContainer", "Deleted: \(url.lastPathComponent)")
                } catch {
                    LoggerService.warning(category: "SwiftDataContainer", "Failed to delete \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Initialization (private)
    private init() {
        LoggerService.info(category: "SwiftDataContainer", "Initializing SwiftData container…")
        
       let schema = Schema([
            ROMEntry.self,
            ROMMetadataEntry.self,
            GameDBEntry.self,
            LibraryFolder.self,
            InstalledCore.self,
            AvailableCore.self,
            ControllerMapping.self,
            AchievementConfig.self,
            CheatStore.self,
            GameCategoryEntry.self,
            BezelPreferences.self,
            BoxArtPreferences.self,
            CoreOptionEntry.self,
            ShaderPresetEntry.self,
            ResourceCacheEntryModel.self,
            DATIngestionEntry.self,
            BoxArtResolutionEntry.self,
            // MAME ROM database and verification tracking
            MAMERomEntry.self,
            MAMEDatabaseInfo.self,
            MAMEVerificationRecord.self
        ])

        // --- NEW LOGIC START ---
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupport.appendingPathComponent("TruchieEmu")
        
        // Create the directory if it doesn't exist
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        let storeURL = directoryURL.appendingPathComponent("TruchieEmu.sqlite")
        let config = ModelConfiguration(url: storeURL)
        // --- NEW LOGIC END ---
        
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            migrationFlag = PersistenceMigrationFlag()
            LoggerService.info(category: "SwiftDataContainer", "ModelContainer created successfully at: \(storeURL.path)")
        } catch {
            LoggerService.warning(category: "SwiftDataContainer", "Failed to create ModelContainer: \(error.localizedDescription). Attempting store reset…")
            
            Self.deleteStoreFiles()
            
            // Re-create directory after deletion just in case
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            
            let retryConfig = ModelConfiguration(url: storeURL)
            do {
                container = try ModelContainer(for: schema, configurations: [retryConfig])
                migrationFlag = PersistenceMigrationFlag()
            } catch {
                // If schema migration fails, delete the store file and try again
                LoggerService.warning(category: "SwiftDataContainer", "Failed to create ModelContainer: \(error.localizedDescription). Attempting store reset…")
                Self.deleteStoreFiles()
                let retryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                do {
                    container = try ModelContainer(for: schema, configurations: [retryConfig])
                    migrationFlag = PersistenceMigrationFlag()
                } catch {
                    // Last resort: in-memory only
                    LoggerService.warning(category: "SwiftDataContainer", "Persistent store still failed after reset, using in-memory fallback")
                    let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    do {
                        container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                        migrationFlag = PersistenceMigrationFlag()
                        LoggerService.info(category: "SwiftDataContainer", "ModelContainer created with in-memory fallback")
                    } catch {
                        LoggerService.error(category: "SwiftDataContainer", "Fatal: ModelContainer creation failed even with in-memory fallback: \(error.localizedDescription)")
                        fatalError("Unable to initialize SwiftData container: \(error)")
                    }
                }
            }
        }    
    }
}

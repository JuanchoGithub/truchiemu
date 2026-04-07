import Foundation
import SwiftData

private enum containerLog {
    static func notice(_ message: String) { LoggerService.info(category: "SwiftDataContainer", message) }
    static func fault(_ message: String) { LoggerService.error(category: "SwiftDataContainer", message) }
}

// MARK: - SwiftData Container

/// Singleton that manages the SwiftData ModelContainer lifecycle.
@MainActor
final class SwiftDataContainer: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SwiftDataContainer()
    
    // MARK: - Properties
    
    private(set) var container: ModelContainer!
    private(set) var migrationFlag: PersistenceMigrationFlag?
    
    /// Primary context for MainActor writes
    var mainContext: ModelContext {
        container.mainContext
    }
    
    /// Whether migration has already been completed
    var hasMigrated: Bool {
        migrationFlag?.hasMigrated ?? false
    }
    
    // MARK: - Store Management
    
    /// Delete all SwiftData store files to force a fresh schema creation.
    /// Used as a fallback when schema migration fails.
    private static func deleteStoreFiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        
        let fileManager = FileManager.default
        // SwiftData uses "default.store" as the default store name
        let storeURL = appSupport.appendingPathComponent("default.store", isDirectory: true)
        let walURL = appSupport.appendingPathComponent("default.store-wal")
        let shmURL = appSupport.appendingPathComponent("default.store-shm")
        
        for url in [storeURL, walURL, shmURL] {
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                    LoggerService.info(category: "SwiftDataContainer", "Deleted store file: \(url.lastPathComponent)")
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
        
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            migrationFlag = PersistenceMigrationFlag()
            LoggerService.info(category: "SwiftDataContainer", "ModelContainer created successfully")
        } catch {
            // If schema migration fails, delete the store file and try again
            LoggerService.warning(category: "SwiftDataContainer", "Failed to create ModelContainer: \(error.localizedDescription). Attempting store reset…")
            Self.deleteStoreFiles()
            let retryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                container = try ModelContainer(for: schema, configurations: [retryConfig])
                migrationFlag = PersistenceMigrationFlag()
                LoggerService.info(category: "SwiftDataContainer", "ModelContainer recreated after store reset")
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

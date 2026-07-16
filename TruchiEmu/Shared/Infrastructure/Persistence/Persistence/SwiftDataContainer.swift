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

    // Delete ONLY the SwiftData SQLite store files to force a fresh schema creation.
    // Used as a fallback when schema migration fails. NEVER touch the surrounding
    // `TruchiEmu/` user-data folder — that holds saves/BIOS/states/cheats/settings/logs
    // which must survive a failed migration. Only the three SQLite triples inside
    // the folder, plus the legacy `default.store*` files at the Application Support
    // root (leftover from a pre-folder-layout era), are touched.
    private static func deleteStoreFiles() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let truchieFolder = appSupport.appendingPathComponent("TruchiEmu")

        let storeFile = truchieFolder.appendingPathComponent("TruchiEmu.sqlite")
        let walFile = truchieFolder.appendingPathComponent("TruchiEmu.sqlite-wal")
        let shmFile = truchieFolder.appendingPathComponent("TruchiEmu.sqlite-shm")

        // Legacy "root" path (pre-folder-layout era, lives at the Application
        // Support root, NOT inside the TruchiEmu user-data folder).
        let rootStore = appSupport.appendingPathComponent("default.store")
        let rootWal = appSupport.appendingPathComponent("default.store-wal")
        let rootShm = appSupport.appendingPathComponent("default.store-shm")

        let targets = [storeFile, walFile, shmFile, rootStore, rootWal, rootShm]

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
        // Don't log during init - could cause circular dependency with AppSettings
        
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
            MAMEVerificationRecord.self,
        // Generic settings storage
        SettingsEntry.self,
        RAGameCacheEntry.self,
        // Notification history
        NotificationEntry.self,
        // Move list (favorites, overrides, custom moves, custom games)
        MoveListEntry.self,
        CustomGameDataEntry.self
        ])

        // --- NEW LOGIC START ---
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupport.appendingPathComponent("TruchiEmu")
        
        // Create the directory if it doesn't exist
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        let storeURL = directoryURL.appendingPathComponent("TruchiEmu.sqlite")
        let config = ModelConfiguration(url: storeURL)
        // --- NEW LOGIC END ---
        
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            migrationFlag = PersistenceMigrationFlag()
        } catch {
            // Try recovery without logging (to avoid circular deps)
            
            Self.deleteStoreFiles()
            
            // Re-create directory after deletion just in case
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            
            let retryConfig = ModelConfiguration(url: storeURL)
            do {
                container = try ModelContainer(for: schema, configurations: [retryConfig])
                migrationFlag = PersistenceMigrationFlag()
            } catch {
                // If schema migration fails, delete the store file and try again
                Self.deleteStoreFiles()
                let retryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                do {
                    container = try ModelContainer(for: schema, configurations: [retryConfig])
                    migrationFlag = PersistenceMigrationFlag()
                } catch {
                    // Last resort: in-memory only
                    let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    do {
                        container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                        migrationFlag = PersistenceMigrationFlag()
                    } catch {
                        fatalError("Unable to initialize SwiftData container: \(error)")
                    }
                }
            }
        }    
    }
}

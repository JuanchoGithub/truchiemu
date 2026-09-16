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

    // Populated when the SwiftData store could not be migrated/opened on this
    // launch. The app's root Scene inspects this to decide whether to surface
    // App Update Mode (recovery UI). Non-nil means the container currently in
    // use is the in-memory fallback and the user's on-disk store is intact, but
    // the user needs a fixing update to read their existing data.
    private(set) var launchSchemaError: Error?

    // True when a backup of the SwiftData SQLite triple was successfully created
    // at the start of this launch (so the recovery flow / App Update Mode knows
    // it can offer "restore from the just-taken backup").
    private(set) var createdPreMigrationBackup: Bool = false

    // True when the live store on disk had to be the in-memory fallback this
    // launch because the on-disk store could not be opened.
    private(set) var runningInMemoryFallback: Bool = false

    // Maximum number of pre-migration backups to retain under .migrationBackups/.
    private static let maxBackups = 3

    // UserDefaults key for the last fingerprint that opened the store OK.
    // Uses UserDefaults, not AppSettings. AppSettings needs SwiftData.
    // SwiftData needs this container. That order causes a circular dependency.
    private static let backupFingerprintKey = "swiftdata_backup_fingerprint"

    // Fingerprint of app version plus schema. Backup runs only when it changes.
    // This stops a backup on each launch. Normal launches skip the backup.
    private static func currentBackupFingerprint(modelNames: [String]) -> String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion)|\(build)|\(modelNames.joined(separator: ","))"
    }
    
    // Primary context for MainActor writes
    var mainContext: ModelContext {
        container.mainContext
    }
    
    // Whether migration has already been completed
    var hasMigrated: Bool {
        migrationFlag?.hasMigrated ?? false
    }
    
    // MARK: - Store Management

    // Copy the live SwiftData SQLite triple (store + wal + shm) into a timestamped
    // subdirectory of `~/Library/Application Support/TruchiEmu/.migrationBackups/<ISO>/`
    // BEFORE attempting ModelContainer init. This ensures a known-good copy of the
    // user's DB exists even if migration corrupts or deletes the live files. The
    // surrounding user-data folder (saves, BIOS, etc.) is intentionally not backed
    // up here — those aren't touched by the migration flow.
    private static func makePreMigrationBackup(storeURL: URL,
                                                walURL: URL,
                                                shmURL: URL) -> Bool {
        let fileManager = FileManager.default
        let backupRoot = storeURL.deletingLastPathComponent().appendingPathComponent(".migrationBackups")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = backupRoot.appendingPathComponent(timestamp)
        do {
            try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            LoggerService.warning(category: "SwiftDataContainer", "Could not create backup directory: \(error.localizedDescription)")
            return false
        }

        let pairs: [(URL, URL)] = [
            (storeURL, dest.appendingPathComponent("TruchiEmu.sqlite")),
            (walURL, dest.appendingPathComponent("TruchiEmu.sqlite-wal")),
            (shmURL, dest.appendingPathComponent("TruchiEmu.sqlite-shm"))
        ]
        var copiedAny = false
        for (src, dst) in pairs {
            guard fileManager.fileExists(atPath: src.path) else { continue }
            do {
                if fileManager.fileExists(atPath: dst.path) { try fileManager.removeItem(at: dst) }
                try fileManager.copyItem(at: src, to: dst)
                copiedAny = true
            } catch {
                LoggerService.warning(category: "SwiftDataContainer", "Backup copy failed for \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Prune older backups beyond maxBackups. Sort by name (ISO timestamps sort
        // chronologically) and remove the oldest.
        if let entries = try? fileManager.contentsOfDirectory(at: backupRoot,
                                                                includingPropertiesForKeys: nil) {
            let sorted = entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            if sorted.count > maxBackups {
                for old in sorted.prefix(sorted.count - maxBackups) {
                    try? fileManager.removeItem(at: old)
                }
            }
        }

        if copiedAny {
            LoggerService.info(category: "SwiftDataContainer", "Pre-migration backup written to \(dest.lastPathComponent)")
        }
        return copiedAny
    }

    // True when fingerprint differs from last OK launch, or no fingerprint
    // exists yet. False on normal launches with no version or schema change.
    // Also false when no store file exists. There is nothing to back up then.
    private static func shouldMakePreMigrationBackup(storeURL: URL,
                                                     fingerprint: String) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }
        let last = UserDefaults.standard.string(forKey: backupFingerprintKey)
        return last != fingerprint
    }

    // Restore the most recent pre-migration backup to the live store path. Called
    // on the failure path when ModelContainer(for:) threw: the catch block may have
    // touched the live SQLite files (delete+retry), so we put the known-good copy
    // back as the live store. The next fixing release can then open and migrate
    // that store, recovering the user's library metadata. Returns true on success.
    private static func restoreLatestBackup(storeURL: URL,
                                              walURL: URL,
                                              shmURL: URL) -> Bool {
        let fileManager = FileManager.default
        let backupRoot = storeURL.deletingLastPathComponent().appendingPathComponent(".migrationBackups")
        guard let entries = try? fileManager.contentsOfDirectory(at: backupRoot,
                                                                  includingPropertiesForKeys: nil),
              !entries.isEmpty else { return false }
        let latest = entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last!

        let pairs: [(URL, URL)] = [
            (latest.appendingPathComponent("TruchiEmu.sqlite"), storeURL),
            (latest.appendingPathComponent("TruchiEmu.sqlite-wal"), walURL),
            (latest.appendingPathComponent("TruchiEmu.sqlite-shm"), shmURL)
        ]
        var restoredAny = false
        for (src, dst) in pairs {
            guard fileManager.fileExists(atPath: src.path) else { continue }
            do {
                if fileManager.fileExists(atPath: dst.path) { try fileManager.removeItem(at: dst) }
                try fileManager.copyItem(at: src, to: dst)
                restoredAny = true
            } catch {
                LoggerService.warning(category: "SwiftDataContainer", "Restore failed for \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if restoredAny {
            LoggerService.info(category: "SwiftDataContainer", "Restored pre-migration backup to live store path from \(latest.lastPathComponent)")
        }
        return restoredAny
    }
    
    // MARK: - Initialization (private)
    private init() {
        // Don't log during init - could cause circular dependency with AppSettings
        
        let modelTypes: [any PersistentModel.Type] = [
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
        ]
        let schema = Schema(modelTypes)

        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupport.appendingPathComponent("TruchiEmu")
        
        // Create the directory if it doesn't exist
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        let storeURL = directoryURL.appendingPathComponent("TruchiEmu.sqlite")
        let walURL = directoryURL.appendingPathComponent("TruchiEmu.sqlite-wal")
        let shmURL = directoryURL.appendingPathComponent("TruchiEmu.sqlite-shm")

        // Backup only when version or schema changed since last OK launch.
        // Normal launches skip the backup. No backup log shows then.
        // (Returned Bool tracked for App Update Mode UI.)
        let modelNames = modelTypes.map { String(describing: $0) }
        let fingerprint = Self.currentBackupFingerprint(modelNames: modelNames)
        if Self.shouldMakePreMigrationBackup(storeURL: storeURL, fingerprint: fingerprint) {
            createdPreMigrationBackup = Self.makePreMigrationBackup(storeURL: storeURL,
                                                                     walURL: walURL,
                                                                     shmURL: shmURL)
        }

        let config = ModelConfiguration(url: storeURL)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
            migrationFlag = PersistenceMigrationFlag()
            UserDefaults.standard.set(fingerprint, forKey: Self.backupFingerprintKey)
        } catch {
            // Schema migration / store-open failed. Surface the error so App Update
            // Mode UI can present the recovery flow, restore the pre-migration backup
            // to the live store path (so a fixing release can pick up the user's
            // original DB rather than an empty one), and run the app in-memory so the
            // UI still works. Crucially, we do NOT delete anything from the user-data
            // folder here — the broken store on disk is replaced by the pre-migration
            // backup (which preserves the user's library metadata).
            launchSchemaError = error
            LoggerService.error(category: "SwiftDataContainer", "Schema migration failed: \(error.localizedDescription)")

            // Restore the user's last-known-good SQLite triple from the pre-migration
            // backup to the live store path. The next launch (with a fixing release)
            // will see the user's original DB and can migrate it forward.
            _ = Self.restoreLatestBackup(storeURL: storeURL,
                                         walURL: walURL,
                                         shmURL: shmURL)

            // In-memory fallback so the UI can render App Update Mode.
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                migrationFlag = PersistenceMigrationFlag()
                runningInMemoryFallback = true
                LoggerService.info(category: "SwiftDataContainer", "Running in-memory-only; live store restored from backup; awaiting fixing update via App Update Mode.")
            } catch {
                // Even the in-memory container couldn't be created — this is a
                // code/schema bug unconnected to user data. fatalError so the
                // dev sees it during their build.
                fatalError("Unable to initialize SwiftData container: \(error)")
            }
        }
    }
}

import Foundation
import SwiftData

// Handles first-run pre-population of the game database from the bundled seed database.
// On first launch, copies the pre-populated seed database to Application Support so
// ROM identification works immediately without needing to download DAT files.
@MainActor
enum DATPrepopulationService {

    // Key stored in Settings to track whether pre-population has been done.
    private static let popDoneKey = "dat_prepopulation_done_v1"

    // MARK: - Public API

    // Check if pre-population is needed and perform it if so.
    // Returns true if the database was populated (or already had data), false if the seed was unavailable.
    static func ensureDATsArePopulated() async -> Bool {
        // If already done, skip
        if AppSettings.getBool(popDoneKey, defaultValue: false) {
            LoggerService.info(category: "DATPrepopulation", "DAT pre-population already done — skipping")
            return true
        }

        LoggerService.info(category: "DATPrepopulation", "First run — attempting DAT pre-population from bundled seed database")

        let success = importSeedDatabaseIfNecessary()

        // Always mark as done — we only want to attempt seed import once.
        // If the seed is missing, we accept that and move on; we don't want
        // to retry on every startup.
        AppSettings.setBool(popDoneKey, value: true)

        if success {
            LoggerService.info(category: "DATPrepopulation", "DAT pre-population completed successfully")
        } else {
            LoggerService.info(category: "DATPrepopulation", "Seed database unavailable — skipping. DAT downloads will populate the database.")
        }

        return success
    }

    // Copy the bundled seed database to the Application Support location if the existing
    // database is empty (no game_entries).
    static func importSeedDatabaseIfNecessary() -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("TruchieEmu")
        let dbPath = dbDir.appendingPathComponent("game_database")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        // Check if database exists and has game_entries using SwiftData.
        // Use fetchCount instead of fetching all entities - this avoids materializing
        // thousands of GameDBEntry objects into memory just to check if data exists.
        let context = SwiftDataContainer.shared.mainContext
        let countDescriptor = FetchDescriptor<GameDBEntry>()
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0
        
        if totalCount > 0 {
            LoggerService.info(category: "DATPrepopulation", "Database already has \(totalCount) game entries — seed import not needed")
            return true
        }

        LoggerService.info(category: "DATPrepopulation", "No database entries found — importing seed")

        // Find the bundled seed database
        guard let seedURL = Bundle.main.url(forResource: "game_database_seed", withExtension: "store") else {
            LoggerService.error(category: "DATPrepopulation", "Bundled seed database (game_database_seed.store) not found")
            return false
        }

        LoggerService.info(category: "DATPrepopulation", "Found seed database at \(seedURL.path)")

        // Copy seed to target location
        do {
            // If existing empty DB, remove it first
            if FileManager.default.fileExists(atPath: dbPath.path) {
                try FileManager.default.removeItem(at: dbPath)
            }

            try FileManager.default.copyItem(at: seedURL, to: dbPath)

            // Verify by checking SwiftData store using fetchCount (no materialization).
            let verifyDescriptor = FetchDescriptor<GameDBEntry>()
            let count = try context.fetchCount(verifyDescriptor)
            LoggerService.info(category: "DATPrepopulation", "Seed database imported: \(count) game entries copied")
            return count > 0
        } catch {
            LoggerService.error(category: "DATPrepopulation", "Failed to import seed database: \(error.localizedDescription)")
            return false
        }
    }

    // Return a list of system IDs that have been populated in the game database.
    static func getPopulatedSystems() -> [String] {
        return getAllSystemIDsFromRepository()
    }

    // Get all system IDs from the repository.
    // Uses a fetch request with property selection to only retrieve the systemID column,
    // avoiding materialization of full GameDBEntry objects.
    private static func getAllSystemIDsFromRepository() -> [String] {
        let context = SwiftDataContainer.shared.mainContext
        var descriptor = FetchDescriptor<GameDBEntry>()
        descriptor.propertiesToFetch = [\.systemID]
        do {
            let entries = try context.fetch(descriptor)
            var systemIDs = Set<String>()
            for entry in entries {
                systemIDs.insert(entry.systemID)
            }
            return Array(systemIDs).sorted()
        } catch {
            LoggerService.error(category: "DATPrepopulation", "Failed to fetch system IDs: \(error.localizedDescription)")
            return []
        }
    }
}

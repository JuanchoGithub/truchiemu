import Foundation
import SwiftData

// MARK: - Game DB Repository

// Typed repository for ROM identification lookups.
// Replaces the old GameDatabase with typed SwiftData queries.
@MainActor
final class GameDBRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Lookup Methods

    // Look up a game by systemID + CRC (exact match).
    func lookupByCRC(systemID: String, crc: String) -> GameDBLookupResult? {
        let descriptor = FetchDescriptor<GameDBEntry>(
            predicate: #Predicate { $0.systemID == systemID && $0.crc == crc }
        )
        do {
            let result = try context.fetch(descriptor)
            guard let entry = result.first else { return nil }
            return lookupResult(from: entry)
        } catch {
            LoggerService.error(category: "GameDBRepository", "CRC lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    // Search for games by exact stripped title match within a system.
    func searchByStrippedTitle(systemID: String, strippedTitle: String, limit: Int = 10) -> [GameDBLookupResult] {
        let descriptor = FetchDescriptor<GameDBEntry>(
            predicate: #Predicate { $0.systemID == systemID && $0.strippedTitle == strippedTitle }
        )
        do {
            let results = try context.fetch(descriptor)
            return results.prefix(limit).map { lookupResult(from: $0) }
        } catch {
            LoggerService.error(category: "GameDBRepository", "Stripped title search failed: \(error.localizedDescription)")
            return []
        }
    }

    // Search for games by substring match within a system.
    func searchBySubstring(systemID: String, substring: String, limit: Int = 20) -> [GameDBLookupResult] {
        let descriptor = FetchDescriptor<GameDBEntry>(
            predicate: #Predicate { $0.systemID == systemID && $0.title.contains(substring) }
        )
        do {
            let results = try context.fetch(descriptor)
            return results.prefix(limit).map { lookupResult(from: $0) }
        } catch {
            LoggerService.error(category: "GameDBRepository", "Substring search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Write Methods

    // Bulk upsert game entries for a given system.
    func upsertEntries(systemID: String, entries: [(crc: String, title: String, strippedTitle: String, year: String?, developer: String?, publisher: String?, genre: String?, thumbnailSystemID: String?)]) {
        // First, clear existing entries for this system to avoid duplicates
        clearSystem(systemID: systemID)

        for entry in entries {
            let model = GameDBEntry(
                systemID: systemID,
                crc: entry.crc,
                title: entry.title,
                strippedTitle: entry.strippedTitle,
                year: entry.year,
                developer: entry.developer,
                publisher: entry.publisher,
                genre: entry.genre,
                thumbnailSystemID: entry.thumbnailSystemID
            )
            context.insert(model)
        }

        do {
            try context.save()
            LoggerService.info(category: "GameDBRepository", "Upserted \(entries.count) game entries for system \(systemID).")
        } catch {
            LoggerService.error(category: "GameDBRepository", "Failed to upsert game entries: \(error.localizedDescription)")
        }
    }

    // Delete all game entries for a given system.
    func clearSystem(systemID: String) {
        do {
            let descriptor = FetchDescriptor<GameDBEntry>(
                predicate: #Predicate { $0.systemID == systemID }
            )
            let entries = try context.fetch(descriptor)
            for entry in entries {
                context.delete(entry)
            }
            try context.save()
        } catch {
            LoggerService.error(category: "GameDBRepository", "Failed to clear system \(systemID): \(error.localizedDescription)")
        }
    }

    // Count game entries for a given system.
    func countForSystem(systemID: String) -> Int {
        let descriptor = FetchDescriptor<GameDBEntry>(
            predicate: #Predicate { $0.systemID == systemID }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // Check if any entries exist for a given system.
    func hasEntriesForSystem(systemID: String) -> Bool {
        return countForSystem(systemID: systemID) > 0
    }

    // MARK: - Mapping

    // Create a GameDBLookupResult from a GameDBEntry @Model.
    private func lookupResult(from entry: GameDBEntry) -> GameDBLookupResult {
        GameDBLookupResult(
            systemID: entry.systemID,
            crc: entry.crc,
            title: entry.title,
            year: entry.year,
            developer: entry.developer,
            publisher: entry.publisher,
            genre: entry.genre,
            thumbnailSystemID: entry.thumbnailSystemID
        )
    }
}
import Foundation
import SwiftData

/// A single MAME ROM lookup entry (lightweight, for in-memory dictionary).
struct MAMELookupEntry {
    let shortName: String
    let description: String
    let type: String        // "game", "bios", "device", "mechanical"
    let isRunnable: Bool
    let year: String?
    let manufacturer: String?
    let parentROM: String?
    let players: Int?
    
    var isPlayableGame: Bool {
        type == "game" && isRunnable
    }
}

/// Service that imports the MAME ROM database (mame_rom_data.json) into SwiftData.
/// Provides lookup services for identifying MAME ROMs by filename.
@MainActor
final class MAMEImportService: ObservableObject {
    static let shared = MAMEImportService()
    
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importStatus: String = ""
    @Published var totalEntries: Int = 0
    @Published var importedEntries: Int = 0
    
    // MARK: - SwiftData Import
    
    /// Find the bundled JSON file
    func findDatabaseFile() -> URL? {
        // First try app bundle (for production builds)
        if let bundledURL = Bundle.main.url(forResource: "mame_rom_data", withExtension: "json") {
            return bundledURL
        }
        
        // Try common development paths
        let searchPaths = [
            // Relative to project root
            "scripts/mame_lookup/mame_rom_data.json",
            // Relative to ~/Downloads or similar 
            "\(NSHomeDirectory())/Downloads/mame_rom_data.json"
        ]
        
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        return nil
    }
    
    /// Import the database into SwiftData
    @MainActor
    func importDatabase(from fileURL: URL, modelContext: ModelContext) async -> ImportResult {
        guard !isImporting else {
            return .failure("Import already in progress")
        }
        
        isImporting = true
        importProgress = 0
        importStatus = "Reading database file..."
        
        defer {
            isImporting = false
        }
        
        do {
            // Load JSON data
            let data = try Data(contentsOf: fileURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure("Invalid JSON format")
            }
            
            guard let roms = json["roms"] as? [String: Any],
                  let metadata = json["metadata"] as? [String: Any] else {
                return .failure("Missing 'roms' or 'metadata' in JSON")
            }
            
            self.totalEntries = roms.count
            let total = Double(self.totalEntries)
            
            LoggerService.mameImport("Starting MAME ROM import: \(self.totalEntries) entries from \(fileURL.lastPathComponent)")
            
            // Delete existing entries to avoid duplicates
            importStatus = "Clearing existing entries..."
            deleteExistingEntries(modelContext: modelContext)
            
            var imported = 0
            var skipped = 0
            let errors = 0
            
            importStatus = "Importing entries..."
            
            // Import in batches to avoid memory pressure
            let batchSize = 500
            var batchInserts: [MAMERomEntry] = []
            
            for (shortName, rawValue) in roms {
                guard let entry = rawValue as? [String: Any] else {
                    skipped += 1
                    continue
                }
                
                let romEntry = MAMERomEntry(
                    shortName: shortName,
                    gameDescription: entry["description"] as? String ?? shortName,
                    type: entry["type"] as? String ?? "game",
                    isRunnable: entry["isRunnable"] as? Bool ?? true,
                    year: entry["year"] as? String,
                    manufacturer: entry["manufacturer"] as? String,
                    parentROM: entry["parent"] as? String,
                    players: entry["players"] as? Int
                )
                
                batchInserts.append(romEntry)
                imported += 1
                
                // Flush batch
                if batchInserts.count >= batchSize {
                    for item in batchInserts {
                        modelContext.insert(item)
                    }
                    batchInserts.removeAll()
                    
                    // Save periodically
                    try? modelContext.save()
                    
                    importProgress = Double(imported) / total
                    importStatus = "Imported \(imported)/\(self.totalEntries)"
                }
            }
            
            // Flush remaining
            for item in batchInserts {
                modelContext.insert(item)
            }
            try? modelContext.save()
            
            // Record database info
            let dbInfo = MAMEDatabaseInfo(
                totalEntries: imported,
                source: metadata["source"] as? String ?? "Unknown",
                version: metadata["generatedAt"] as? String ?? "Unknown"
            )
            modelContext.insert(dbInfo)
            try? modelContext.save()
            
            importProgress = 1.0
            importStatus = "Complete"
            
            let result = ImportResult(
                success: true,
                imported: imported,
                skipped: skipped,
                errors: errors,
                total: self.totalEntries
            )
            
            LoggerService.mameImport("MAME ROM import complete: \(imported) imported, \(skipped) skipped, \(errors) errors")
            
            return result
            
        } catch {
            LoggerService.mameImportError("Import failed: \(error.localizedDescription)")
            importStatus = "Failed: \(error.localizedDescription)"
            return .failure(error.localizedDescription)
        }
    }
    
    /// Delete all existing MAME database entries
    @MainActor
    private func deleteExistingEntries(modelContext: ModelContext) {
        do {
            var descriptor = FetchDescriptor<MAMERomEntry>()
            descriptor.fetchLimit = 1000
            
            var deleted = 0
            while true {
                let entries = try modelContext.fetch(descriptor)
                if entries.isEmpty { break }
                
                for entry in entries {
                    modelContext.delete(entry)
                    deleted += 1
                }
                try? modelContext.save()
                
                if entries.count < 1000 { break }
            }
            
            // Delete database info
            let infoDescriptor = FetchDescriptor<MAMEDatabaseInfo>()
            let infos = try modelContext.fetch(infoDescriptor)
            for info in infos {
                modelContext.delete(info)
            }
            try? modelContext.save()
            
            LoggerService.mameImport("Deleted \(deleted) existing MAME ROM entries")
        } catch {
            LoggerService.mameImportError("Failed to delete existing entries: \(error.localizedDescription)")
        }
    }
    
    /// Get import status for display
    var isDatabaseImported: Bool {
        // Quick check - could be made more robust with a persistence check
        return totalEntries > 0
    }
}

// MARK: - Import Result

struct ImportResult {
    let success: Bool
    let imported: Int
    let skipped: Int
    let errors: Int
    let total: Int
    
    static func failure(_ error: String) -> ImportResult {
        ImportResult(success: false, imported: 0, skipped: 0, errors: 1, total: 0)
    }
}
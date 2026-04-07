import Foundation
import SwiftData
import SwiftUI

// MARK: - MAME 2003-Plus Unified Service

/// Service that loads MAME 2003-Plus game data from the bundled mame_2003_plus.json.
/// This replaces the old runtime XML download system with a pre-built database.
final class MAME2003PlusService: ObservableObject {
    static let shared = MAME2003PlusService()
    
    @Published var isLoaded = false
    @Published var database: MAME2003PlusDatabase?
    
    /// In-memory lookup: shortName -> entry
    private var lookupTable: [String: MAME2003PlusEntry] = [:]
    /// Set of all runnable short names (for quick playability check)
    private var runnableShortNames: Set<String> = []
    
    static let bundledResourceName = "mame_2003_plus"
    static let bundledResourceExtension = "json"
    
    init() {
        loadDatabase()
    }
    
    // MARK: - Loading
    
    /// Load the bundled database from the app resources.
    func loadDatabase() {
        // Try: 1) App bundle, 2) Swift Package resources, 3) Direct path
        var jsonURL: URL?
        
        // 1. Try main bundle (production)
        if let url = Bundle.main.url(
            forResource: Self.bundledResourceName,
            withExtension: Self.bundledResourceExtension
        ) {
            jsonURL = url
        }
        
        // 2. Try bundle for framework/module if available
        if jsonURL == nil,
           let frameworkBundle = Bundle(identifier: "com.truchie.TruchieEmu"),
           let url = frameworkBundle.url(
            forResource: Self.bundledResourceName,
            withExtension: Self.bundledResourceExtension
           ) {
            jsonURL = url
        }
        
        // 3. Try development paths
        if jsonURL == nil {
            let devPaths = [
                "scripts/mame_lookup/mame_2003_plus.json",
                "TruchieEmu/Resources/mame_2003_plus.json"
            ]
            
            for path in devPaths {
                // Use current working directory or home dir as base
                let cwdPath = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: cwdPath.path) {
                    jsonURL = cwdPath
                    break
                }
                
                let homePath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("gitrepos/truchiemu/\(path)")
                if FileManager.default.fileExists(atPath: homePath.path) {
                    jsonURL = homePath
                    break
                }
            }
        }
        
        // Also try project root relative
        if jsonURL == nil {
            let projectURL = URL(fileURLWithPath: "/Users/jayjay/gitrepos/truchiemu/TruchieEmu/Resources/mame_2003_plus.json")
            if FileManager.default.fileExists(atPath: projectURL.path) {
                jsonURL = projectURL
            }
        }
        
        guard let url = jsonURL else {
            LoggerService.mameImport("MAME2003PlusService: Could not find bundled mame_2003_plus.json in any location")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let db = try decoder.decode(MAME2003PlusDatabase.self, from: data)
            
            self.database = db
            self.lookupTable = db.games
            self.runnableShortNames = Set(db.games.values.filter { $0.runnable && !$0.isBIOS }.map { $0.shortName })
            self.isLoaded = true
            
            LoggerService.mameImport("MAME2003PlusService: Loaded \(db.metadata.totalEntries) entries (\(db.metadata.runnableGames) runnable) from bundled database")
        } catch {
            LoggerService.mameImportError("MAME2003PlusService: Failed to decode bundled JSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Query Methods
    
    /// Look up a game by its short name (ZIP filename without extension).
    func lookup(shortName: String) -> MAME2003PlusEntry? {
        lookupTable[shortName.lowercased()]
    }
    
    /// Check if a short name is a runnable game (not BIOS, not unplayable).
    func isRunnable(shortName: String) -> Bool {
        runnableShortNames.contains(shortName.lowercased())
    }
    
    /// Check if a short name is a BIOS entry.
    func isBIOS(shortName: String) -> Bool {
        lookupTable[shortName.lowercased()]?.isBIOS ?? false
    }
    
    /// Get all runnable game short names (for library filtering).
    var allRunnableShortNames: Set<String> {
        runnableShortNames
    }
    
    /// Get all BIOS short names.
    var allBIOSShortNames: Set<String> {
        Set(lookupTable.values.filter { $0.isBIOS }.map { $0.shortName })
    }
    
    /// Get all entries as an array (for display purposes).
    var allEntries: [MAME2003PlusEntry] {
        Array(lookupTable.values)
    }
    
    /// Get all runnable entries sorted by description.
    var runnableEntries: [MAME2003PlusEntry] {
        lookupTable.values
            .filter { $0.runnable && !$0.isBIOS }
            .sorted { $0.description < $1.description }
    }
    
    // MARK: - Core Compatibility
    
    /// Returns true if this game is playable with the mame2003_plus core.
    /// Since this database is specifically for mame2003_plus, any runnable entry
    /// in it is compatible with that core.
    func isCompatibleWithMAME2003Plus(shortName: String) -> Bool {
        guard let entry = lookupTable[shortName.lowercased()] else { return false }
        return entry.runnable && !entry.isBIOS
    }
    
    /// Generate compatibility tag for library display.
    /// Returns "core:mame2003_plus compatible" or "MAME Unplayable".
    func compatibilityTag(for shortName: String) -> String {
        guard let entry = lookupTable[shortName.lowercased()] else {
            return "MAME Unplayable"
        }
        
        if entry.isBIOS {
            return "mame2003_plus BIOS"
        }
        
        if entry.runnable {
            return "core:mame2003_plus compatible"
        }
        
        return "MAME Unplayable"
    }
    
    // MARK: - Dependency Resolution
    
    /// Get all required parent ZIPs for a game (cloneOf, romOf, merge targets).
    func requiredZIPs(for shortName: String) -> [String] {
        guard let entry = lookupTable[shortName.lowercased()] else { return [] }
        
        var required: Set<String> = []
        
        // The game's own ZIP
        required.insert(shortName)
        
        // Parent ZIP (cloneOf games need the parent)
        if let parent = entry.cloneOf {
            required.insert(parent)
        }
        
        // BIOS ZIP (romOf)
        if let bios = entry.romOf {
            required.insert(bios)
        }
        
        return Array(required).sorted()
    }
    
    /// Check if all required ZIPs exist in the ROMs directory.
    func checkZIPsAvailable(for shortName: String, romsDirectory: URL) -> (allAvailable: Bool, missing: [String]) {
        let required = requiredZIPs(for: shortName)
        let missing = required.filter { zipName in
            let zipURL = romsDirectory.appendingPathComponent("\(zipName).zip")
            return !FileManager.default.fileExists(atPath: zipURL.path)
        }
        return (missing.isEmpty, missing)
    }
}


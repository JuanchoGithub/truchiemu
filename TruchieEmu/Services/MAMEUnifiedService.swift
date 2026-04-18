import Foundation

// MARK: - MAME Unified Service

// Service that loads the unified MAME database (mame_unified.json) containing
// game data from ALL MAME cores (2000, 2003, 2003-Plus, 2010, 2015, 2016).
//
// This replaces the old per-core XML download system with a single pre-built database.
// Each game entry knows which cores it's compatible with and its per-core dependencies.
@MainActor
final class MAMEUnifiedService: ObservableObject {
    static let shared = MAMEUnifiedService()
    
    @Published var isLoaded = false
    @Published var database: MAMEUnifiedDatabase?
    
    // In-memory lookup: shortName -> entry
    private var lookupTable: [String: MAMEUnifiedEntry] = [:]
    // Set of all runnable short names across ALL cores
    private var allRunnableShortNames: Set<String> = []
    // Set of all BIOS short names
    private var allBIOSShortNames: Set<String> = []
    // Set of unplayable short names (not runnable in any core)
    private var unplayableShortNames: Set<String> = []
    
    private var loadingTask: Task<Void, Never>?
    
    static let bundledResourceName = "mame_unified"
    static let bundledResourceExtension = "json"
    
    init() {
        // The database is loaded asynchronously to avoid blocking startup.
    }
    
    // MARK: - Loading
    
    // Ensures the database is loaded. If it's already loading or loaded, it returns immediately.
    // If not, it waits for the loading task to complete.
    func ensureLoaded() async {
        if isLoaded { return }
        if let task = loadingTask {
            _ = await task.result
            return
        }
        
        let task = Task {
            await loadDatabase()
        }
        loadingTask = task
        _ = await task.result
    }

    // Load the bundled unified database from the app resources.
    func loadDatabase() async {
        var jsonURL: URL?
        
        // 1. Try main bundle (production)
        if let url = Bundle.main.url(
            forResource: Self.bundledResourceName,
            withExtension: Self.bundledResourceExtension
        ) {
            jsonURL = url
        }
        
        // 2. Try development paths
        if jsonURL == nil {
            let devPaths = [
                "scripts/mame_lookup/mame_unified.json",
                "TruchieEmu/Resources/mame_unified.json"
            ]
            
            for path in devPaths {
                let cwdPath = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: cwdPath.path) {
                    jsonURL = cwdPath
                    break
                }
                
                let homePath = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("gitrepos/truchiemu/\(path)")
                if FileManager.default.fileExists(atPath: homePath.path) {
                    jsonURL = homePath
                    break
                }
            }
        }
        
        // 3. Try absolute project path
        if jsonURL == nil {
            let projectURL = URL(
                fileURLWithPath: "/Users/jayjay/gitrepos/truchiemu/TruchieEmu/Resources/mame_unified.json"
            )
            if FileManager.default.fileExists(atPath: projectURL.path) {
                jsonURL = projectURL
            }
        }
        
        guard let url = jsonURL else {
            LoggerService.mameImport("MAMEUnifiedService: Could not find bundled mame_unified.json")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let db = try decoder.decode(MAMEUnifiedDatabase.self, from: data)
            
            self.database = db
            self.lookupTable = db.games
            
            // Build lookup sets
            for (shortName, entry) in db.games {
                if entry.isBIOS {
                    allBIOSShortNames.insert(shortName)
                } else if entry.isRunnableInAnyCore {
                    allRunnableShortNames.insert(shortName)
                } else if !entry.compatibleCores.isEmpty {
                    // In cores but not runnable
                    unplayableShortNames.insert(shortName)
                } else {
                    // Not in any core at all
                    unplayableShortNames.insert(shortName)
                }
            }
            
            self.isLoaded = true
            
            LoggerService.mameImport(
                "MAMEUnifiedService: Loaded \(db.metadata.totalEntries) entries " +
                "(\(db.metadata.entriesInAtLeastOneCore) in cores, " +
                "\(db.metadata.entriesNotInAnyCore) not in any core)"
            )
        } catch {
            LoggerService.mameImportError(
                "MAMEUnifiedService: Failed to decode unified JSON: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Query Methods
    
    // Look up a game by its short name (ZIP filename without extension).
    func lookup(shortName: String) -> MAMEUnifiedEntry? {
        lookupTable[shortName.lowercased()]
    }
    
    // Check if a short name is runnable in ANY core.
    func isRunnable(shortName: String) -> Bool {
        allRunnableShortNames.contains(shortName.lowercased())
    }
    
    // Check if a short name is runnable in a specific core.
    func isRunnable(shortName: String, in coreID: String) -> Bool {
        guard let entry = lookupTable[shortName.lowercased()] else { return false }
        return entry.isRunnable(in: coreID)
    }
    
    // Check if a short name is a BIOS entry.
    func isBIOS(shortName: String) -> Bool {
        allBIOSShortNames.contains(shortName.lowercased())
    }
    
    // Check if a short name is unplayable (not runnable in any core).
    func isUnplayable(shortName: String) -> Bool {
        unplayableShortNames.contains(shortName.lowercased())
    }
    
    // Get all runnable game short names (for library filtering).
    var runnableShortNames: Set<String> {
        allRunnableShortNames
    }
    
    // Get all BIOS short names.
    var biosShortNames: Set<String> {
        allBIOSShortNames
    }
    
    // Get all entries as an array.
    var allEntries: [MAMEUnifiedEntry] {
        Array(lookupTable.values)
    }
    
    // Get all runnable entries sorted by description.
    var runnableEntries: [MAMEUnifiedEntry] {
        lookupTable.values
            .filter { $0.isRunnableInAnyCore && !$0.isBIOS }
            .sorted { $0.description < $1.description }
    }
    
    // MARK: - Core Compatibility
    
    // Get all cores that can run this game.
    func compatibleCores(for shortName: String) -> [String] {
        lookupTable[shortName.lowercased()]?.compatibleCores ?? []
    }
    
    // Generate compatibility tag for library display.
    // Returns "core:{coreID} compatible", "MAME BIOS", or "MAME Unplayable".
    func compatibilityTag(for shortName: String) -> String {
        guard let entry = lookupTable[shortName.lowercased()] else {
            return "MAME Unplayable"
        }
        return entry.compatibilityTag
    }
    
    // Get the best core to use for a game (first runnable core).
    func bestCore(for shortName: String) -> String? {
        guard let entry = lookupTable[shortName.lowercased()] else { return nil }
        
        // Find first core where this game is runnable
        for coreID in entry.compatibleCores {
            if entry.isRunnable(in: coreID) {
                return coreID
            }
        }
        return nil
    }
    
    // MARK: - Dependency Resolution
    
    // Get all required ZIPs for a game in a specific core.
    func requiredZIPs(for shortName: String, coreID: String) -> [String] {
        guard let entry = lookupTable[shortName.lowercased()] else { return [shortName] }
        return entry.requiredZIPs(for: coreID)
    }
    
    // Check if all required ZIPs exist in the ROMs directory.
    func checkZIPsAvailable(
        for shortName: String,
        coreID: String,
        romsDirectory: URL
    ) -> (allAvailable: Bool, missing: [String]) {
        let required = requiredZIPs(for: shortName, coreID: coreID)
        let missing = required.filter { zipName in
            let zipURL = romsDirectory.appendingPathComponent("\(zipName).zip")
            return !FileManager.default.fileExists(atPath: zipURL.path)
        }
        return (missing.isEmpty, missing)
    }
    
    // MARK: - Statistics
    
    // Get count of runnable games per core.
    var runnableCountsPerCore: [String: Int] {
        guard let db = database else { return [:] }
        return db.metadata.coreRunnableCounts
    }
    
    // Get display names for all cores.
    var coreDisplayNames: [String: String] {
        guard let db = database else { return [:] }
        return db.metadata.cores
    }
}
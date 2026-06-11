import Foundation

// MARK: - MAME Unified Service

// Service that loads the unified MAME database (mame_unified.json) containing
// game data from ALL MAME cores (2000, 2003, 2003-Plus, 2010, 2015, 2016).
//
// This replaces the old per-core XML download system with a single pre-built database.
// Each game entry knows which cores it's compatible with and its per-core dependencies.
final class MAMEUnifiedService: ObservableObject {
    static let shared = MAMEUnifiedService()
    
    @MainActor @Published var isLoaded = false
    @MainActor @Published var database: MAMEUnifiedDatabase?


    // The master dictionary containing ALL files (needed for ZIP dependency checks)
    nonisolated(unsafe) private var masterLookupTable: [String: MAMEUnifiedEntry] = [:]
    // In-memory lookup strictly for RUNNABLE games (UI uses this)
    nonisolated(unsafe) private var lookupTable: [String: MAMEUnifiedEntry] = [:]
    // Set of all runnable short names across ALL cores
    nonisolated(unsafe) private var allRunnableShortNames: Set<String> = []
    // Set of all BIOS short names
    nonisolated(unsafe) private var allBIOSShortNames: Set<String> = []
    // Set of unplayable short names (not runnable in any core)
    nonisolated(unsafe) private var unplayableShortNames: Set<String> = []
    // Set of FBNeo romset names (valid ZIP filenames for FBNeo core)
    nonisolated(unsafe) private var fbneoRomsetNames: Set<String> = []
    // Set of MAME shortnames that are runnable (for arcade filename validation)
    nonisolated(unsafe) private var allMAMEShortNames: Set<String> = []
    
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
        let loaded = await MainActor.run { isLoaded }
        if loaded { return }
        
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
         // We check both the root and the 'Data/' subdirectory because of how the Xcode group is structured
         if let url = Bundle.main.url(
             forResource: Self.bundledResourceName,
             withExtension: Self.bundledResourceExtension
         ) ?? Bundle.main.url(
             forResource: "\(Self.bundledResourceName)/\(Self.bundledResourceExtension)",
             withExtension: nil
         ) {
             jsonURL = url
         } else if let url = Bundle.main.url(
             forResource: Self.bundledResourceName,
             withExtension: Self.bundledResourceExtension,
             subdirectory: "Data"
         ) {
             jsonURL = url
         }
         
         // 2. Try development paths
         if jsonURL == nil {
             let devPaths = [
                 "mame_unified.json",
                 "TruchiEmu/Resources/mame_unified.json",
                 "TruchiEmu/Resources/Data/mame_unified.json"
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
                fileURLWithPath: "mame_unified.json"
            )
            if FileManager.default.fileExists(atPath: projectURL.path) {
                LoggerService.debug(category: "MAMEUnifiedService", "Loading: \(projectURL) - mame_unified.json")
                jsonURL = projectURL
            }
        }
        
        guard let url = jsonURL else {
            LoggerService.debug(category: "mameImport", "MAMEUnifiedService: Could not find bundled mame_unified.json")
            return
        }
        
        // Perform heavy decoding on a background thread
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(MAMEUnifiedDatabase, [String: MAMEUnifiedEntry],[String: MAMEUnifiedEntry], Set<String>, Set<String>, Set<String>, Set<String>), Error> in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let db = try decoder.decode(MAMEUnifiedDatabase.self, from: data)
                
                var newMasterLookup: [String: MAMEUnifiedEntry] = [:]
                var newLookupTable:[String: MAMEUnifiedEntry] = [:]
                var allBIOSShortNames: Set<String> = []
                var allRunnableShortNames: Set<String> = []
                var unplayableShortNames: Set<String> = []
                var allMAMEShortNames: Set<String> = []

                for (shortName, entry) in db.games {
                    let lowerName = shortName.lowercased()
                    
                    // 1. Everything goes in the master table for background tasks
                    newMasterLookup[lowerName] = entry 
                    
                    // 2. Sort into our specific lists
                    if entry.isBIOS || KnownBIOS.mameFiles.contains(lowerName) {
                        allBIOSShortNames.insert(lowerName)
                    } else if entry.isRunnableInAnyCore {
                        allRunnableShortNames.insert(lowerName)
                        allMAMEShortNames.insert(lowerName)
                        // ONLY playable games are allowed in this dictionary!
                        newLookupTable[lowerName] = entry 
                        
                    } else {
                        unplayableShortNames.insert(lowerName)
                    }
                }
                return .success((db, newMasterLookup, newLookupTable, allBIOSShortNames, allRunnableShortNames, unplayableShortNames, allMAMEShortNames))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let (db, master, lookup, bios, runnable, unplayable, mameShortNames)):
            LoggerService.info(category: "MAMEUnifiedService",
                               "Opened file \(String(describing: jsonURL))")
            await MainActor.run {
                self.database = db
                self.isLoaded = true
            }
            // Update nonisolated properties
            self.masterLookupTable = master
            self.lookupTable = lookup
            self.allBIOSShortNames = bios
            self.allRunnableShortNames = runnable
            self.unplayableShortNames = unplayable
            self.allMAMEShortNames = mameShortNames
            
            LoggerService.debug(category: "MAMEUnifiedService",
                "Loaded \(db.metadata.totalEntries) entries " +
                "(\(db.metadata.entriesInAtLeastOneCore) in cores, " +
                "\(db.metadata.entriesNotInAnyCore) not in any core)"
            )
            
            // Best-effort: load FBNeo romset names
            await loadFBNeoRomsets()
            
        case .failure(let error):
            LoggerService.error(category: "MAMEUnifiedService", "Failed to decode unified JSON: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - FBNeo Romset Loading

    // Loads FBNeo romset names from the cached DAT file.
    // This is a best-effort load — if the DAT doesn't exist, we just have an empty set.
    nonisolated private func loadFBNeoRomsets() async {
        // Try to find the FBNeo DAT file in known locations
        var datURL: URL?
        
        // 1. App Support cache
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let appSup = appSupport {
            let cachedURL = appSup.appendingPathComponent("TruchiEmu/Dats/FBNeo - Arcade Games.dat")
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                datURL = cachedURL
            }
        }
        
        // 2. Bundle resources
        if datURL == nil {
            if let bundleURL = Bundle.main.url(forResource: "FBNeo - Arcade Games", withExtension: "dat") {
                datURL = bundleURL
            } else if let bundleURL = Bundle.main.url(forResource: "FBNeo - Arcade Games", withExtension: "dat", subdirectory: "Data/LibretroDats") {
                datURL = bundleURL
            }
        }
        
        // 3. Development paths
        if datURL == nil {
            let devPaths = [
                "TruchiEmu/Resources/Data/FBNeo - Arcade Games.dat",
                "FBNeo - Arcade Games.dat"
            ]
            for path in devPaths {
                let devURL = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: devURL.path) {
                    datURL = devURL
                    break
                }
                let homeURL = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("gitrepos/truchiemu/\(path)")
                if FileManager.default.fileExists(atPath: homeURL.path) {
                    datURL = homeURL
                    break
                }
            }
        }
        
        guard let url = datURL else {
            LoggerService.debug(category: "MAMEUnifiedService", "FBNeo DAT not found — romset names unavailable")
            return
        }
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            LoggerService.debug(category: "MAMEUnifiedService", "FBNeo DAT exists but unreadable: \(url.path)")
            return
        }
        
        var romsetNames = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        var inGameBlock = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("game (") || trimmed.hasPrefix("machine (") {
                inGameBlock = true
            } else if trimmed == ")" && inGameBlock {
                inGameBlock = false
            } else if inGameBlock && trimmed.hasPrefix("name ") {
                // Extract the name within quotes, e.g., name "sf2"
                if let start = trimmed.firstIndex(of: "\""), let end = trimmed[trimmed.index(after: start)...].firstIndex(of: "\"") {
                    let romsetName = String(trimmed[trimmed.index(after: start)..<end]).lowercased()
                    if !romsetName.isEmpty {
                        romsetNames.insert(romsetName)
                    }
                }
            }
        }
        
        self.fbneoRomsetNames = romsetNames
        LoggerService.debug(category: "MAMEUnifiedService", "Loaded \(romsetNames.count) FBNeo romset names from \(url.lastPathComponent)")
    }

    // MARK: - Arcade Romset Name Validation

    // Strip macOS duplicate suffix like " (1)", " (2)" from a filename stem.
    nonisolated static func stripDuplicateSuffix(_ name: String) -> String {
        // Matches " (1)", " (2)", etc. at the very end of the string
        if let range = name.range(of: "\\s*\\(\\d+\\)$", options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    // Checks if a short name (ZIP stem) matches any known arcade romset name (MAME or FBNeo).
    nonisolated func isValidArcadeRomsetName(_ shortName: String) -> Bool {
        let lower = shortName.lowercased()
        let stripped = Self.stripDuplicateSuffix(lower)
        // Check original and stripped
        return allMAMEShortNames.contains(lower) || allMAMEShortNames.contains(stripped) ||
               fbneoRomsetNames.contains(lower) || fbneoRomsetNames.contains(stripped)
    }

    // Checks if a short name is a MAME romset (runnable game, not BIOS).
    nonisolated func isMAMERomsetName(_ shortName: String) -> Bool {
        let lower = shortName.lowercased()
        let stripped = Self.stripDuplicateSuffix(lower)
        return allMAMEShortNames.contains(lower) || allMAMEShortNames.contains(stripped)
    }

    // Checks if a short name is a FBNeo-only romset (NOT in MAME runnable list).
    nonisolated func isFBNeoOnlyRomsetName(_ shortName: String) -> Bool {
        let lower = shortName.lowercased()
        let stripped = Self.stripDuplicateSuffix(lower)
        let inFBNeo = fbneoRomsetNames.contains(lower) || fbneoRomsetNames.contains(stripped)
        let inMAME = allMAMEShortNames.contains(lower) || allMAMEShortNames.contains(stripped)
        return inFBNeo && !inMAME
    }

    // Checks if a short name is in BOTH MAME and FBNeo romsets.
    nonisolated func isSharedArcadeRomsetName(_ shortName: String) -> Bool {
        let lower = shortName.lowercased()
        let stripped = Self.stripDuplicateSuffix(lower)
        let inFBNeo = fbneoRomsetNames.contains(lower) || fbneoRomsetNames.contains(stripped)
        let inMAME = allMAMEShortNames.contains(lower) || allMAMEShortNames.contains(stripped)
        return inFBNeo && inMAME
    }

    // Look up a game by its short name (ZIP filename without extension).
    nonisolated func lookup(shortName: String) -> MAMEUnifiedEntry? {
        masterLookupTable[shortName.lowercased()]
    }
    
    // Check if a short name is runnable in ANY core.
    nonisolated func isRunnable(shortName: String) -> Bool {
        lookupTable[shortName.lowercased()] != nil
    }
    
    // Check if a short name is runnable in a specific core.
    nonisolated func isRunnable(shortName: String, in coreID: String) -> Bool {
        guard let entry = lookupTable[shortName.lowercased()] else { return false }
        return entry.isRunnable(in: coreID)
    }
    
    // Check if a short name is a BIOS entry.
    nonisolated func isBIOS(shortName: String) -> Bool {
        allBIOSShortNames.contains(shortName.lowercased())
    }
    
    // Check if a short name is unplayable (not runnable in any core).
    nonisolated func isUnplayable(shortName: String) -> Bool {
        unplayableShortNames.contains(shortName.lowercased())
    }
    
    // Get all runnable game short names (for library filtering).
    nonisolated var runnableShortNames: Set<String> {
        allRunnableShortNames
    }
    
    // Get all BIOS short names.
    nonisolated var biosShortNames: Set<String> {
        allBIOSShortNames
    }
    
    // Get all entries as an array.
    nonisolated var allEntries: [MAMEUnifiedEntry] {
        Array(masterLookupTable.values)
    }
    
    // Get all runnable entries sorted by description.
    nonisolated var runnableEntries: [MAMEUnifiedEntry] {
        // FIX 4: Beautifully simple! No filtering needed because lookupTable ONLY has playable games.
        lookupTable.values.sorted { $0.description < $1.description }
    }
    
    // MARK: - Core Compatibility
    
    // Get all cores that can run this game.
    nonisolated func compatibleCores(for shortName: String) -> [String] {
        masterLookupTable[shortName.lowercased()]?.compatibleCores ?? []
    }
    
    // Generate compatibility tag for library display.
    // Returns "core:{coreID} compatible", "MAME BIOS", or "MAME Unplayable".
    nonisolated func compatibilityTag(for shortName: String) -> String {
        let lower = shortName.lowercased()
        
        // FIX 3: Check BIOS list first so BIOS files don't say "Unplayable"
        if allBIOSShortNames.contains(lower) {
            return "MAME BIOS"
        }
        
        guard let entry = lookupTable[lower] else {
            return "MAME Unplayable"
        }
        return entry.compatibilityTag
    }
    
    // Get the best core to use for a game (first runnable core).
    nonisolated func bestCore(for shortName: String) -> String? {
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
    nonisolated func requiredZIPs(for shortName: String, coreID: String) -> [String] {
        guard let entry = masterLookupTable[shortName.lowercased()] else { return [shortName] }
        return entry.requiredZIPs(for: coreID)
    }
    
    // Check if all required ZIPs exist in the ROMs directory.
    nonisolated func checkZIPsAvailable(
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
    @MainActor var runnableCountsPerCore: [String: Int] {
        guard let db = database else { return [:] }
        return db.metadata.coreRunnableCounts
    }
    
    // Get display names for all cores.
    @MainActor var coreDisplayNames: [String: String] {
        guard let db = database else { return [:] }
        return db.metadata.cores
    }
}

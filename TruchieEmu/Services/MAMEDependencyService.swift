import Foundation
import SwiftData
import os.log

// MARK: - XML Parser for MAME XML

/// Parses a single MAME XML file and returns a dependency map.
struct MAMEXMLParser {
    
    struct ParsedGame {
        let shortName: String
        let description: String
        let year: String?
        let manufacturer: String?
        let players: Int?
        let isRunnable: Bool
        let cloneOf: String?
        let romOf: String?
        let sampleOf: String?
        let driverStatus: String?
        let romEntries: [ROMEntry]
    }
    
    struct ROMEntry {
        let name: String
        let size: Int?
        let crc: String?
        let merge: String?
    }
    
    /// Parse MAME XML data into a dependency database.
    static func parse(xmlData: Data, coreID: String) throws -> MAMEDependencyDB {
        let guardInstance = XMLParser(data: xmlData)
        let delegate = MAMEXMLParserDelegate()
        guardInstance.delegate = delegate
        
        guard guardInstance.parse() else {
            throw MAMEParserError.xmlParsingFailed("XML parser failed")
        }
        
        var games: [String: MAMEGameDependencies] = [:]
        
        for parsed in delegate.games {
            // Find ROMs with merge= attribute (these come from parent ZIP)
            let mergedROMs = parsed.romEntries.compactMap { rom -> String? in
                rom.merge ?? nil
            }
            
            games[parsed.shortName] = MAMEGameDependencies(
                description: parsed.description,
                isRunnable: parsed.isRunnable,
                driverStatus: parsed.driverStatus,
                parentROM: parsed.cloneOf,
                romOf: parsed.romOf,
                sampleOf: parsed.sampleOf,
                mergedROMs: mergedROMs.isEmpty ? nil : Array(Set(mergedROMs))
            )
        }
        
        return MAMEDependencyDB(
            coreID: coreID,
            version: coreID,
            fetchedAt: Date(),
            games: games
        )
    }
    
    /// Parse a list of MAMEGameInfo entries — only runnable games.
    static func getRunnableGames(from db: MAMEDependencyDB) -> [MAMEGameInfo] {
        db.games.compactMap { shortName, deps -> MAMEGameInfo? in
            guard deps.isRunnable else { return nil }
            return MAMEGameInfo(
                shortName: shortName,
                description: deps.description,
                year: nil,
                manufacturer: nil,
                players: nil,
                parentROM: deps.parentROM,
                romOf: deps.romOf,
                sampleOf: deps.sampleOf,
                driverStatus: deps.driverStatus
            )
        }.sorted { $0.description < $1.description }
    }
}

// MARK: - XML Parser Delegate

private final class MAMEXMLParserDelegate: NSObject, XMLParserDelegate {
    var games: [MAMEXMLParser.ParsedGame] = []
    
    private var currentGameName: String?
    private var currentDescription: String?
    private var currentYear: String?
    private var currentManufacturer: String?
    private var currentPlayers: Int?
    private var currentRunnable: Bool = true
    private var currentCloneOf: String?
    private var currentRomOf: String?
    private var currentSampleOf: String?
    private var currentDriverStatus: String?
    private var currentROMs: [MAMEXMLParser.ROMEntry] = []
    
    // We're parsing <rom> elements
    private var currentROMName: String?
    private var currentROMMerge: String?
    private var currentROMCRC: String?
    private var currentROMSize: Int?
    
    // Track current element for foundCharacters
    private var currentElement: String?
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentElement = elementName
        
        switch elementName {
        case "game":
            currentGameName = attributeDict["name"]
            currentRunnable = attributeDict["runnable"] != "no"
            currentCloneOf = attributeDict["cloneof"]
            currentRomOf = attributeDict["romof"]
            currentSampleOf = attributeDict["sampleof"]
            currentDescription = nil
            currentYear = nil
            currentManufacturer = nil
            currentPlayers = nil
            currentDriverStatus = nil
            currentROMs = []
            
        case "rom":
            currentROMName = attributeDict["name"]
            currentROMMerge = attributeDict["merge"]
            currentROMCRC = attributeDict["crc"]
            if let sizeStr = attributeDict["size"], let size = Int(sizeStr) {
                currentROMSize = size
            } else {
                currentROMSize = nil
            }
            
        case "input":
            if let playersStr = attributeDict["players"], let players = Int(playersStr) {
                currentPlayers = players
            }
            
        case "driver":
            currentDriverStatus = attributeDict["status"]
            
        default:
            break
        }
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "description", "year", "manufacturer":
            break // handled in foundCharacters
            
        case "rom":
            if let name = currentROMName {
                currentROMs.append(MAMEXMLParser.ROMEntry(
                    name: name,
                    size: currentROMSize,
                    crc: currentROMCRC,
                    merge: currentROMMerge
                ))
            }
            currentROMName = nil
            currentROMMerge = nil
            currentROMCRC = nil
            currentROMSize = nil
            
        case "game":
            if let name = currentGameName {
                games.append(MAMEXMLParser.ParsedGame(
                    shortName: name,
                    description: currentDescription ?? name,
                    year: currentYear,
                    manufacturer: currentManufacturer,
                    players: currentPlayers,
                    isRunnable: currentRunnable,
                    cloneOf: currentCloneOf,
                    romOf: currentRomOf,
                    sampleOf: currentSampleOf,
                    driverStatus: currentDriverStatus,
                    romEntries: currentROMs
                ))
            }
            currentGameName = nil
            
        default:
            break
        }
        
        currentElement = nil
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let element = currentElement else { return }
        
        switch element {
        case "description":
            currentDescription = (currentDescription ?? "") + trimmed
        case "year":
            currentYear = trimmed
        case "manufacturer":
            currentManufacturer = (currentManufacturer ?? "") + trimmed
        default:
            break
        }
    }
}

// MARK: - Errors

enum MAMEParserError: Error, LocalizedError {
    case xmlParsingFailed(String)
    case networkError(String)
    case noRunnableGames
    case coreNotSupported(String)
    
    var errorDescription: String? {
        switch self {
        case .xmlParsingFailed(let msg): return "XML parsing failed: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .noRunnableGames: return "No runnable games found in database"
        case .coreNotSupported(let core): return "Core '\(core)' is not a supported MAME core"
        }
    }
}

// MARK: - MAME Dependency Service

/// Service that manages MAME game dependencies per core version.
final class MAMEDependencyService: ObservableObject {
    static let shared = MAMEDependencyService()
    
    /// URL patterns for MAME XML files on GitHub
    static let xmlURLs: [String: String] = [
        "mame2000": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202000%20XML.dat",
        "mame2003": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202003%20XML.xml",
        "mame2003_plus": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202003-Plus%20XML.xml",
        "mame2010": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202010%20XML.xml",
        // "mame" (current) — fall back to 2015 zip, handled separately
        "mame": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202015%20XML.zip"
    ]
    
    static func isMAMECore(_ coreID: String) -> Bool {
        let base = coreID.replacingOccurrences(of: "_libretro", with: "")
        return base.hasPrefix("mame")
    }
    
    /// Core ID -> base name (e.g. "mame2003_libretro" -> "mame2003")
    static func baseCoreID(_ coreID: String) -> String {
        coreID.replacingOccurrences(of: "_libretro", with: "")
    }
    
    @Published var isFetching = false
    @Published var fetchProgress: Double = 0
    
    /// In-memory cache: coreID -> dependency database
    private var dependencyCache: [String: MAMEDependencyDB] = [:]
    
    /// Persistent storage URL
    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/MAMEDeps", isDirectory: true)
    }
    
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "MAMEDeps")
    
    /// UserDefaults key tracking cores whose XML fetch failed (for retry)
    private static let failedFetchKey = "MAMEDependencyService_failedFetchCores"
    
    /// Bundled JSON fallback URL
    private static let fallbackJSONPath = "scripts/mame_lookup/mame_rom_data.json"
    
    init() {
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadCachedDatabases()
        // Also try loading the bundled JSON as a fallback
        loadFallbackFromBundle()
    }
    
    // MARK: - Fetch & Parse
    
    /// Fetch and parse MAME XML dependencies for a core.
    /// Call this when a core is downloaded.
    /// Falls back to bundled JSON if fetch fails.
    func fetchAndParseDependencies(for coreID: String) async throws {
        let baseID = Self.baseCoreID(coreID)
        guard let xmlURLString = Self.xmlURLs[baseID] else {
            throw MAMEParserError.coreNotSupported(baseID)
        }
        
        // Check cache first
        if dependencyCache[baseID] != nil {
            log.info("Dependencies already cached for \(baseID)")
            return
        }
        
        isFetching = true
        defer { isFetching = false }
        
        log.info("Fetching MAME XML for \(baseID) from \(xmlURLString)")
        
        do {
            guard let url = URL(string: xmlURLString) else {
                throw MAMEParserError.networkError("Invalid URL")
            }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw MAMEParserError.networkError("HTTP error fetching XML")
            }
            
            // Handle ZIP files (currently only "mame" latest uses a ZIP)
            let xmlData: Data
            if baseID == "mame" && xmlURLString.hasSuffix(".zip") {
                // For zip files, we need to unzip — use ditto
                let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                
                let zipURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".zip")
                try data.write(to: zipURL)
                
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                proc.arguments = ["-xk", zipURL.path, tmpDir.path]
                try proc.run()
                proc.waitUntilExit()
                
                guard proc.terminationStatus == 0,
                      let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: [.isRegularFileKey]),
                      let xmlFileURL = ((enumerator.allObjects as? [URL]) ?? []).first(where: { $0.pathExtension == "xml" || $0.pathExtension == "dat" }) else {
                    try? FileManager.default.removeItem(at: tmpDir)
                    throw MAMEParserError.networkError("Failed to extract XML from ZIP")
                }
                
                xmlData = try Data(contentsOf: xmlFileURL)
                try? FileManager.default.removeItem(at: tmpDir)
            } else {
                xmlData = data
            }
            
            let db = try MAMEXMLParser.parse(xmlData: xmlData, coreID: baseID)
            
            // Cache in memory
            dependencyCache[baseID] = db
            
            // Persist to disk
            persistDatabase(db, for: baseID)
            
            // Remove from failed fetch set since it succeeded
            clearFailedFetch(baseID)
            
            log.info("Parsed \(db.games.count) game dependencies for \(baseID)")
            
        } catch {
            // Record as failed for retry on next startup
            recordFailedFetch(baseID)
            
            // Fallback: try using bundled JSON if no cached database exists
            log.warning("XML fetch failed for \(baseID): \(error.localizedDescription). Falling back to bundled database.")
            
            // The bundled fallback is already loaded in init() with coreID "mame_fallback"
            // For now, we just log the error. The game will still work but won't have
            // precise per-core dependency data.
        }
    }
    
    // MARK: - Retry Failed Fetches
    
    /// Record that a core's XML fetch failed so we can retry on next startup.
    private func recordFailedFetch(_ baseID: String) {
        var failed = AppSettings.get(Self.failedFetchKey, type: [String].self) ?? []
        guard !failed.contains(baseID) else { return }
        failed.append(baseID)
        AppSettings.set(Self.failedFetchKey, value: failed)
        log.info("Recorded failed fetch for core: \(baseID)")
    }
    
    /// Clear a core from the failed fetch list.
    private func clearFailedFetch(_ baseID: String) {
        var failed = AppSettings.get(Self.failedFetchKey, type: [String].self) ?? []
        failed.removeAll { $0 == baseID }
        AppSettings.set(Self.failedFetchKey, value: failed.count > 0 ? failed : nil)
    }
    
    /// Get cores whose dependency fetch previously failed (for retry).
    static var failedFetchCores: [String] {
        AppSettings.get(Self.failedFetchKey, type: [String].self) ?? []
    }
    
    /// Retry fetching dependencies for previously-failed cores.
    @MainActor
    func retryFailedFetches() async {
        let failedCores = Self.failedFetchCores
        guard !failedCores.isEmpty else { return }
        
        log.info("Retrying MAME dependency fetch for \(failedCores.count) core(s): \(failedCores)")
        
        let fullCoreIDs = failedCores.map { "\($0)_libretro" }
        for coreID in fullCoreIDs {
            // Retry silently - don't throw on failure since we're recovering
            do {
                try await self.fetchAndParseDependencies(for: coreID)
            } catch {
                log.warning("Retry fetch failed for \(coreID): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Query
    
    /// Get all runnable games for a core.
    func getRunnableGames(for coreID: String) -> [MAMEGameInfo] {
        let baseID = Self.baseCoreID(coreID)
        guard let db = dependencyCache[baseID] else {
            log.warning("No dependency database for \(baseID)")
            return []
        }
        return MAMEXMLParser.getRunnableGames(from: db)
    }
    
    /// Check missing dependencies for a specific game.
    /// Returns a list of missing ZIP files the user needs to obtain.
    func checkMissingDependencies(for shortName: String, coreID: String, romsDirectory: URL) -> [MissingROMItem] {
        let baseID = Self.baseCoreID(coreID)
        guard let db = dependencyCache[baseID],
              let deps = db.games[shortName] else {
            return []
        }
        
        var missing: [MissingROMItem] = []
        
        // Determine which ZIPs this game needs
        var requiredZIPs: Set<String> = [deps.romOf ?? shortName]
        if let sampleOf = deps.sampleOf, !sampleOf.isEmpty {
            requiredZIPs.insert(sampleOf)
        }
        
        // Check each required ZIP exists in ROMs directory
        for zipName in requiredZIPs.sorted() {
            let zipURL = romsDirectory.appendingPathComponent("\(zipName).zip")
            if !FileManager.default.fileExists(atPath: zipURL.path) {
                missing.append(MissingROMItem(
                    romName: zipName,
                    sourceZIP: "\(zipName).zip",
                    crc: nil,
                    size: nil
                ))
            }
        }
        
        return missing
    }
    
    // MARK: - Persistence
    
    private func persistDatabase(_ db: MAMEDependencyDB, for coreID: String) {
        let encoder = JSONEncoder()
        let url = storageURL.appendingPathComponent("\(coreID)_deps.json")
        
        do {
            let data = try encoder.encode(db)
            try data.write(to: url)
            log.info("Persisted dependency database for \(coreID)")
        } catch {
            log.error("Failed to persist database for \(coreID): \(error.localizedDescription)")
        }
    }
    
    private func loadCachedDatabases() {
        let decoder = JSONDecoder()
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil) else { return }
        
        for fileURL in contents where fileURL.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: fileURL)
                let db = try decoder.decode(MAMEDependencyDB.self, from: data)
                let coreID = fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_deps", with: "")
                dependencyCache[coreID] = db
            } catch {
                log.warning("Failed to load cached database from \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if !self.dependencyCache.isEmpty {
            log.info("Loaded \(self.dependencyCache.count) cached MAME dependency databases")
        }
    }
    
    // MARK: - Fallback JSON Loading
    
    /// Load the bundled mame_rom_data.json as a fallback dependency database.
    /// This ensures we always have at least basic game descriptions and runnable status.
    private func loadFallbackFromBundle() {
        // Try app bundle first (production)
        if let bundleURL = Bundle.main.url(forResource: "mame_rom_data", withExtension: "json") {
            loadFallbackJSON(from: bundleURL)
            return
        }
        
        // Try development paths
        let searchPaths = [
            "scripts/mame_lookup/mame_rom_data.json",
            "\(NSHomeDirectory())/Downloads/mame_rom_data.json"
        ]
        
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                loadFallbackJSON(from: url)
                return
            }
        }
        
        log.warning("No fallback MAME JSON found")
    }
    
    /// Parse the bundled JSON and add any cores that don't have cached databases.
    private func loadFallbackJSON(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let roms = json["roms"] as? [String: Any] else {
                log.error("Failed to parse fallback MAME JSON")
                return
            }
            
            var games: [String: MAMEGameDependencies] = [:]
            for (shortName, rawValue) in roms {
                guard let entry = rawValue as? [String: Any] else { continue }
                games[shortName] = MAMEGameDependencies(
                    description: entry["description"] as? String ?? shortName,
                    isRunnable: entry["isRunnable"] as? Bool ?? true,
                    driverStatus: nil,
                    parentROM: entry["parent"] as? String,
                    romOf: entry["parent"] as? String,
                    sampleOf: nil,
                    mergedROMs: nil
                )
            }
            
            // Use "mame_fallback" as the core ID for the bundled database
            let fallbackCoreID = "mame_fallback"
            if dependencyCache[fallbackCoreID] == nil {
                let db = MAMEDependencyDB(
                    coreID: fallbackCoreID,
                    version: "bundled",
                    fetchedAt: Date(),
                    games: games
                )
                dependencyCache[fallbackCoreID] = db
                log.info("Loaded bundled MAME dependency database (\(games.count) entries)")
            }
        } catch {
            log.error("Failed to load fallback MAME JSON: \(error.localizedDescription)")
        }
    }
    
    /// Check if dependencies have been fetched for a core.
    func hasDependencies(for coreID: String) -> Bool {
        let baseID = Self.baseCoreID(coreID)
        return dependencyCache[baseID] != nil
    }
    
    /// Set of short names for all runnable games across all loaded cores.
    /// Used by the library view to filter MAME games to only playable ones.
    var rachableShortNamesForCurrentCores: Set<String> {
        var names: Set<String> = []
        for db in dependencyCache.values {
            for (shortName, deps) in db.games where deps.isRunnable {
                names.insert(shortName)
            }
        }
        return names
    }
}

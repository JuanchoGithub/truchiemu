import Foundation

// MARK: - MAME Game Info (lightweight for UI display)

// Lightweight representation of a MAME game for UI display purposes.
struct MAMEGameInfo: Identifiable, Equatable {
    var id: String { shortName }
    let shortName: String
    let description: String
    let year: String?
    let manufacturer: String?
    let players: Int?
    let parentROM: String?
    let romOf: String?
    let sampleOf: String?
    let driverStatus: String?
}

// MARK: - MAME Unified Database Models (multi-core)

// Root structure of the bundled mame_unified.json file.
struct MAMEUnifiedDatabase {
    let metadata: MAMEUnifiedMetadata
    let games: [String: MAMEUnifiedEntry]
}

extension MAMEUnifiedDatabase: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: _CodingKeys.self)
        self.metadata = try container.decode(MAMEUnifiedMetadata.self, forKey: .metadata)
        let rawGames = try container.decode([String: MAMEUnifiedGameData].self, forKey: .games)
        self.games = Dictionary(uniqueKeysWithValues:
            rawGames.map { shortName, gameData in
                (shortName, MAMEUnifiedEntry(shortName: shortName, gameData: gameData))
            }
        )
    }
}

private enum _CodingKeys: String, CodingKey {
    case metadata, games
}

// Metadata section of the unified database.
struct MAMEUnifiedMetadata: Codable {
    let generatedAt: String
    let totalEntries: Int
    let entriesInAtLeastOneCore: Int
    let entriesNotInAnyCore: Int
    let biosEntries: Int
    let coreRunnableCounts: [String: Int]
    let cores: [String: String]  // coreID -> displayName
    let sources: [String: String]
}

// A single game entry from the unified MAME database.
struct MAMEUnifiedEntry: Identifiable {
    var id: String { shortName }
    
    let shortName: String
    let description: String
    let year: String?
    let manufacturer: String?
    let isBIOS: Bool
    
    // All cores that have this game in their database
    let compatibleCores: [String]
    
    // Per-core dependency info (runnable status, parent ROMs, etc.)
    let coreDeps: [String: MAMECoreDependency]?
    
    // Display metadata (merged from best available source)
    let players: Int?
    let control: String?
    let orientation: String?
    let screenType: String?
    let width: Int?
    let height: Int?
    let aspectX: Int?
    let aspectY: Int?
    let refreshRate: Double?
    let cpu: String?
    let audio: [String]?
    let driverStatus: String?
    
    init(shortName: String, gameData: MAMEUnifiedGameData) {
        self.shortName = shortName
        self.description = gameData.description
        self.year = gameData.year
        self.manufacturer = gameData.manufacturer
        self.isBIOS = gameData.isBIOS
        self.compatibleCores = gameData.compatibleCores
        self.coreDeps = gameData.coreDeps
        self.players = gameData.players
        self.control = gameData.control
        self.orientation = gameData.orientation
        self.screenType = gameData.screenType
        self.width = gameData.width
        self.height = gameData.height
        self.aspectX = gameData.aspectX
        self.aspectY = gameData.aspectY
        self.refreshRate = gameData.refreshRate
        self.cpu = gameData.cpu
        self.audio = gameData.audio
        self.driverStatus = gameData.driverStatus
    }
    
    // Check if this game is runnable in a specific core.
    func isRunnable(in coreID: String) -> Bool {
        guard let deps = coreDeps?[coreID] else { return false }
        return deps.runnable
    }
    
    // Check if this game is runnable in ANY core.
    var isRunnableInAnyCore: Bool {
        compatibleCores.contains { isRunnable(in: $0) }
    }
    
    // Get the dependency info for a specific core.
    func deps(for coreID: String) -> MAMECoreDependency? {
        coreDeps?[coreID]
    }
    
    // Returns true if this game runs in vertical orientation.
    var isVertical: Bool {
        orientation?.lowercased() == "vertical"
    }
    
    // Returns the effective aspect ratio as a string (e.g. "4:3", "3:4").
    var aspectRatioString: String? {
        guard let x = aspectX, let y = aspectY else { return nil }
        return "\(x):\(y)"
    }
    
    // Generate a compatibility tag for display.
    var compatibilityTag: String {
        if isBIOS {
            return "MAME BIOS"
        }
        if compatibleCores.isEmpty {
            return "MAME Unplayable"
        }
        if isRunnableInAnyCore {
            let primaryCore = compatibleCores.first ?? "mame"
            return "core:\(primaryCore) compatible"
        }
        return "MAME Unplayable"
    }
    
    // Get all required ZIPs for a specific core.
    func requiredZIPs(for coreID: String) -> [String] {
        guard let deps = coreDeps?[coreID] else { return [shortName] }
        
        var required: Set<String> = [shortName]
        if let parent = deps.cloneOf { required.insert(parent) }
        if let bios = deps.romOf { required.insert(bios) }
        if let sample = deps.sampleOf { required.insert(sample) }
        for merge in deps.mergedROMs ?? [] { required.insert(merge) }
        
        return Array(required).sorted()
    }
}

// Codable representation of a game's data fields in the unified database.
struct MAMEUnifiedGameData: Codable {
    let description: String
    let year: String?
    let manufacturer: String?
    let isBIOS: Bool
    let compatibleCores: [String]
    let coreDeps: [String: MAMECoreDependency]?
    let players: Int?
    let control: String?
    let orientation: String?
    let screenType: String?
    let width: Int?
    let height: Int?
    let aspectX: Int?
    let aspectY: Int?
    let refreshRate: Double?
    let cpu: String?
    let audio: [String]?
    let driverStatus: String?
}

// Per-core dependency information.
struct MAMECoreDependency: Codable, Equatable {
    let runnable: Bool
    let cloneOf: String?
    let romOf: String?
    let sampleOf: String?
    let mergedROMs: [String]?
}


// MARK: - Missing ROM Item

// Represents a missing ROM file that the user needs to obtain.
struct MissingROMItem: Identifiable, Equatable {
    let id = UUID()
    let romName: String
    let sourceZIP: String
    let crc: String?
    let size: Int?
}

// MARK: - MAME Dependency Database

// A parsed dependency database for a specific MAME core version.
struct MAMEDependencyDB: Codable {
    let coreID: String
    let version: String
    let fetchedAt: Date
    let games: [String: MAMEGameDependencies]  // shortName -> dependencies
}

// MARK: - MAME Game Dependencies

// Dependency information for a single MAME game.
struct MAMEGameDependencies: Codable, Equatable {
    let description: String
    let isRunnable: Bool
    let driverStatus: String?
    let parentROM: String?      // cloneof attribute
    let romOf: String?          // romof attribute — parent ROM ZIP
    let sampleOf: String?       // sampleof attribute — samples ZIP
    let mergedROMs: [String]?   // ROMs with merge= attribute (come from parent ZIP)
}
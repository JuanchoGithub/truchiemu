import Foundation

// MARK: - MAME Game Info (lightweight for UI display)

/// Lightweight representation of a MAME game for UI display purposes.
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

// MARK: - Missing ROM Item

/// Represents a missing ROM file that the user needs to obtain.
struct MissingROMItem: Identifiable, Equatable {
    let id = UUID()
    let romName: String
    let sourceZIP: String
    let crc: String?
    let size: Int?
}

// MARK: - MAME Dependency Database

/// A parsed dependency database for a specific MAME core version.
struct MAMEDependencyDB: Codable {
    let coreID: String
    let version: String
    let fetchedAt: Date
    let games: [String: MAMEGameDependencies]  // shortName -> dependencies
}

// MARK: - MAME Game Dependencies

/// Dependency information for a single MAME game.
struct MAMEGameDependencies: Codable, Equatable {
    let description: String
    let isRunnable: Bool
    let driverStatus: String?
    let parentROM: String?      // cloneof attribute
    let romOf: String?          // romof attribute — parent ROM ZIP
    let sampleOf: String?       // sampleof attribute — samples ZIP
    let mergedROMs: [String]?   // ROMs with merge= attribute (come from parent ZIP)
}
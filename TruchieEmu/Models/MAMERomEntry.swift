import Foundation
import SwiftData

// MARK: - MAME ROM Database Entry

/// Stores MAME ROM metadata: shortname → description, type, year, manufacturer.
/// Populated from libretro-database MAME.dat for ROM identification.
@Model
final class MAMERomEntry {
    @Attribute(.unique) var shortName: String
    var gameDescription: String
    var type: String        // "game", "bios", "device", "mechanical"
    var isRunnable: Bool
    var year: String?
    var manufacturer: String?
    var parentROM: String?
    var players: Int?
    var lastUpdated: Date

    init(
        shortName: String,
        gameDescription: String,
        type: String = "game",
        isRunnable: Bool = true,
        year: String? = nil,
        manufacturer: String? = nil,
        parentROM: String? = nil,
        players: Int? = nil
    ) {
        self.shortName = shortName
        self.gameDescription = gameDescription
        self.type = type
        self.isRunnable = isRunnable
        self.year = year
        self.manufacturer = manufacturer
        self.parentROM = parentROM
        self.players = players
        self.lastUpdated = Date()
    }
}

// MARK: - MAME Database Import Log

/// Tracks when the MAME database was last imported into SwiftData.
@Model
final class MAMEDatabaseInfo {
    @Attribute(.unique) var id: Int
    var totalEntries: Int
    var source: String
    var version: String
    var importedAt: Date

    init(
        totalEntries: Int,
        source: String,
        version: String
    ) {
        self.id = 1
        self.totalEntries = totalEntries
        self.source = source
        self.version = version
        self.importedAt = Date()
    }
}
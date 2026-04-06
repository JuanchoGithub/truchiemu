import Foundation

/// Result of a CRC lookup in the game database.
struct GameDBLookupResult {
    let systemID: String
    let crc: String
    let title: String
    let year: String?
    let developer: String?
    let publisher: String?
    let genre: String?
    let thumbnailSystemID: String?
}

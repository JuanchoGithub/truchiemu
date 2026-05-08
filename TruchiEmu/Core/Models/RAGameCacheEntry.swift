import Foundation
import SwiftData

@Model
final class RAGameCacheEntry {
    @Attribute(.unique) var id: Int
    var title: String
    var consoleID: Int
    var consoleName: String
    var imageIcon: String?
    var numAchievements: Int
    var points: Int
    var hashes: [String]
    var cachedAt: Date

    init(id: Int, title: String, consoleID: Int, consoleName: String, imageIcon: String? = nil, numAchievements: Int = 0, points: Int = 0, hashes: [String] = [], cachedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.consoleID = consoleID
        self.consoleName = consoleName
        self.imageIcon = imageIcon
        self.numAchievements = numAchievements
        self.points = points
        self.hashes = hashes
        self.cachedAt = cachedAt
    }

    convenience init(from dto: RAGameCacheEntry.DTO) {
        self.init(
            id: dto.id,
            title: dto.title,
            consoleID: dto.consoleID,
            consoleName: dto.consoleName,
            imageIcon: dto.imageIcon,
            numAchievements: dto.numAchievements,
            points: dto.points,
            hashes: dto.hashes,
            cachedAt: dto.cachedAt
        )
    }
}

extension RAGameCacheEntry {
    struct DTO: Codable {
        let id: Int
        let title: String
        let consoleID: Int
        let consoleName: String
        let imageIcon: String?
        let numAchievements: Int
        let points: Int
        let hashes: [String]
        let cachedAt: Date

        init(from entry: RAGameCacheEntry) {
            self.id = entry.id
            self.title = entry.title
            self.consoleID = entry.consoleID
            self.consoleName = entry.consoleName
            self.imageIcon = entry.imageIcon
            self.numAchievements = entry.numAchievements
            self.points = entry.points
            self.hashes = entry.hashes
            self.cachedAt = entry.cachedAt
        }
    }
}

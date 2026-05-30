import Foundation
import SwiftData

@Model
final class RAAchievementCacheEntry {
    @Attribute(.unique) var achievementId: Int
    var gameId: Int
    var title: String
    var achDescription: String
    var points: Int
    var badgeName: String
    var category: String
    var dateAwarded: Date?
    var dateAwardedHardcore: Date?
    var username: String?
    var trigger: String?
    var cachedAt: Date

    init(achievementId: Int, gameId: Int, title: String, description: String, points: Int, badgeName: String, category: String = "core", cachedAt: Date = Date()) {
        self.achievementId = achievementId
        self.gameId = gameId
        self.title = title
        self.achDescription = description
        self.points = points
        self.badgeName = badgeName
        self.category = category
        self.dateAwarded = nil
        self.dateAwardedHardcore = nil
        self.username = nil
        self.cachedAt = cachedAt
    }
    
    init(achievementId: Int, gameId: Int, title: String, description: String, points: Int, badgeName: String, category: String = "core", dateAwarded: Date? = nil, dateAwardedHardcore: Date? = nil, username: String? = nil, trigger: String? = nil, cachedAt: Date = Date()) {
        self.achievementId = achievementId
        self.gameId = gameId
        self.title = title
        self.achDescription = description
        self.points = points
        self.badgeName = badgeName
        self.category = category
        self.dateAwarded = dateAwarded
        self.dateAwardedHardcore = dateAwardedHardcore
        self.username = username
        self.trigger = trigger
        self.cachedAt = cachedAt
    }
}

@Model
final class RAGameAchievementCache {
    @Attribute(.unique) var gameId: Int
    var achievementCount: Int
    var title: String
    var consoleName: String
    var consoleID: Int
    var totalPoints: Int
    var cachedAt: Date
    
    init(gameId: Int, achievementCount: Int, title: String = "", consoleName: String = "", consoleID: Int = 0, totalPoints: Int = 0, cachedAt: Date = Date()) {
        self.gameId = gameId
        self.achievementCount = achievementCount
        self.title = title
        self.consoleName = consoleName
        self.consoleID = consoleID
        self.totalPoints = totalPoints
        self.cachedAt = cachedAt
    }
}

@Model
final class RAUserCache {
    @Attribute(.unique) var username: String
    var totalPoints: Int
    var totalHardcorePoints: Int
    var totalTruePoints: Int
    var rank: Int
    var awards: Int
    var memberSince: String
    var cachedAt: Date
    
    init(username: String, totalPoints: Int, totalHardcorePoints: Int, totalTruePoints: Int, rank: Int, awards: Int, memberSince: String, cachedAt: Date = Date()) {
        self.username = username
        self.totalPoints = totalPoints
        self.totalHardcorePoints = totalHardcorePoints
        self.totalTruePoints = totalTruePoints
        self.rank = rank
        self.awards = awards
        self.memberSince = memberSince
        self.cachedAt = cachedAt
    }
}

@Model
final class RAHashCache {
    @Attribute(.unique) var hash: String
    var gameId: Int
    var cachedAt: Date
    
    init(hash: String, gameId: Int, cachedAt: Date = Date()) {
        self.hash = hash
        self.gameId = gameId
        self.cachedAt = cachedAt
    }
}

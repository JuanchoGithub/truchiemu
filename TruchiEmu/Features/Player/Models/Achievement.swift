import Foundation

// MARK: - Achievement Data Structures

// Represents a single RetroAchievement.
struct Achievement: Identifiable, Codable, Hashable {
    var id: Int              // RA achievement ID
    var title: String
    var description: String
    var points: Int
    var badgeName: String    // Badge identifier (e.g., "12345")
    var isUnlocked: Bool
    var unlockDate: Date?
    var isHardcore: Bool
    var category: AchievementCategory
    var trigger: String?     // rcheevos trigger definition (from MemAddr)
    
    var badgeURL: URL? {
        URL(string: "https://media.retroachievements.org/Badge/\(badgeName).png")
    }
    
    var localBadgeURL: URL? {
        RABadgeCacheService.shared.localURL(for: badgeName)
    }
    
    var displayTitle: String {
        title
    }
    
    var displayDescription: String {
        isUnlocked ? description : "Hidden until unlocked"
    }
}

// Achievement categories based on RetroAchievements.
enum AchievementCategory: String, Codable, CaseIterable {
    case core       // Core achievements (count towards score)
    case unofficial // Unofficial/test achievements
    case event      // Event achievements
    
    var displayName: String {
        switch self {
        case .core: return "Core"
        case .unofficial: return "Unofficial"
        case .event: return "Event"
        }
    }
}

// MARK: - Game Info

// Represents a RetroAchievements game.
struct RAGameInfo: Codable {
    var id: Int
    var title: String
    var consoleName: String
    var consoleID: Int
    var achievements: [Achievement]
    var totalPoints: Int
    var playerScore: Int?
    var playerHardcoreScore: Int?
    
    var achievementCount: Int {
        achievements.count
    }
}

// MARK: - Leaderboard

// Represents a RetroAchievements leaderboard.
struct Leaderboard: Identifiable, Codable {
    var id: Int
    var title: String
    var description: String
    var format: LeaderboardFormat
    var lowerIsBetter: Bool
    var entries: [LeaderboardEntry]?
    
    var formattedValue: (Int) -> String {
        switch format {
        case .value:
            return { "\($0)" }
        case .time:
            return { formatTime($0) }
        case .score:
            return { "\($0) pts" }
        case .frames:
            return { "\($0) frames" }
        case .minutes:
            return { "\($0) min" }
        case .seconds:
            return { "\($0) sec" }
        }
    }
    
    private func formatTime(_ frames: Int) -> String {
        // Assuming 60 FPS
        let totalSeconds = frames / 60
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let remainingFrames = frames % 60
        return String(format: "%d:%02d.%02d", minutes, seconds, remainingFrames)
    }
}

// Leaderboard value formats.
enum LeaderboardFormat: String, Codable {
    case value
    case time
    case score
    case frames
    case minutes
    case seconds
}

// A single entry in a leaderboard.
struct LeaderboardEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var rank: Int
    var username: String
    var score: Int
    var dateSubmitted: Date?
    
    var isCurrentUser: Bool = false
}

// MARK: - RA User Info

// Represents a RetroAchievements user.
struct RAUserInfo: Codable {
    var username: String
    var totalPoints: Int
    var totalHardcorePoints: Int
    var totalTruePoints: Int
    var rank: Int
    var awards: Int
    var memberSince: String
    var richPresenceMsg: String?
    var lastGameID: Int?
    var lastGameTitle: String?
}

// MARK: - RA API Response Types

// Response from the RA API for game info.
struct RAGameResponse: Codable {
    @SafeOptionalInt var ID: Int?
    var Title: String?
    @SafeOptionalInt var ConsoleID: Int?
    var ConsoleName: String?
    @SafeOptionalInt var NumAchievements: Int?
    @SafeOptionalInt var NumAwarded: Int?
    @SafeOptionalInt var NumAwardedToUser: Int?
    @SafeOptionalInt var NumAwardedToUserHardcore: Int?
    var Achievements: [String: RAAchievementResponse]?
    var Hashes: [String]?
}

struct RAAchievementResponse: Codable {
    @SafeInt var ID: Int
    var Title: String
    var Description: String
    @SafeInt var Points: Int
    var BadgeName: String
    var DateAwarded: String?
    var DateAwardedHardcore: String?
    var Category: String?
    var MemAddr: String?     // Trigger definition for rcheevos
}

// Response from the RA API for hash resolution.
struct RAHashResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case ID, GameID, Title, Hashes
    }
    
    var ID: Int?
    var Title: String?
    var Hashes: [String]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let idVal: Int?
        if let idInt = try? container.decode(Int.self, forKey: .ID) {
            idVal = idInt
        } else if let idStr = try? container.decode(String.self, forKey: .ID), let idInt = Int(idStr) {
            idVal = idInt
        } else if let gameIdInt = try? container.decode(Int.self, forKey: .GameID) {
            idVal = gameIdInt
        } else if let gameIdStr = try? container.decode(String.self, forKey: .GameID), let idInt = Int(gameIdStr) {
            idVal = idInt
        } else {
            idVal = nil
        }
        
        self.ID = idVal
        self.Title = try? container.decode(String.self, forKey: .Title)
        self.Hashes = try? container.decode([String].self, forKey: .Hashes)
    }
}
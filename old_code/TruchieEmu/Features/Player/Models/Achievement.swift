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
    
    var badgeURL: URL? {
        URL(string: "https://media.retroachievements.org/Badge/\(badgeName).png")
    }
    
    var badgeLockedURL: URL? {
        URL(string: "https://media.retroachievements.org/Badge/\(badgeName)_lock.png")
    }
    
    var displayTitle: String {
        isUnlocked ? title : "???"
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
    var ID: String
    var Title: String
    var ConsoleID: String
    var ConsoleName: String
    var NumAchievements: Int
    var NumAwarded: Int
    var NumAwardedToUser: Int
    var NumAwardedToUserHardcore: Int
    var Achievements: [String: RAAchievementResponse]?
}

struct RAAchievementResponse: Codable {
    var ID: String
    var Title: String
    var Description: String
    var Points: String
    var BadgeName: String
    var DateAwarded: String?
    var HardcoreAchieved: Int?
    var Category: String?
}

// Response from the RA API for hash resolution.
struct RAHashResponse: Codable {
    var ID: String
    var Hash: String
}
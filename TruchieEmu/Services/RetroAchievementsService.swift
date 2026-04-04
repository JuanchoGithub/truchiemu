import Foundation
import os.log

private let raLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "RetroAchievements")

// MARK: - RetroAchievements Service

/// Service for interacting with the RetroAchievements API.
/// Handles authentication, game identification, achievement tracking, and leaderboards.
@MainActor
class RetroAchievementsService: ObservableObject {
    static let shared = RetroAchievementsService()
    
    // MARK: - Published State
    
    @Published var isLoggedIn = false
    @Published var username: String?
    @Published var currentGame: RAGameInfo?
    @Published var userInfo: RAUserInfo?
    @Published var hardcoreMode = true
    @Published var isEnabled = false
    @Published var richPresence: String?
    
    // MARK: - Configuration
    
    private let apiBaseURL = "https://retroachievements.org/API"
    private let apiKey: String
    
    // MARK: - Initialization
    
    private init() {
        // Load API key from environment or hardcoded value
        // For production, this should be stored securely
        self.apiKey = ProcessInfo.processInfo.environment["RA_API_KEY"] ?? ""
        loadSettings()
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        username = AppSettings.get("ra_username")
        let token = AppSettings.get("ra_token")
        hardcoreMode = AppSettings.getBool("ra_hardcore", defaultValue: false)
        isEnabled = AppSettings.getBool("ra_enabled", defaultValue: false)
        
        if let token = token, let username = username, !token.isEmpty {
            Task { await validateToken(token: token, username: username) }
        }
    }
    
    func saveSettings(username: String, token: String) {
        AppSettings.set("ra_username", value: username)
        AppSettings.set("ra_token", value: token)
        self.username = username
    }
    
    func setHardcoreMode(_ enabled: Bool) {
        hardcoreMode = enabled
        AppSettings.setBool("ra_hardcore", value: enabled)
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        AppSettings.setBool("ra_enabled", value: enabled)
        if !enabled {
            currentGame = nil
        }
    }
    
    // MARK: - Authentication
    
    /// Validate stored token on app launch.
    func validateToken(token: String, username: String) async {
        guard isEnabled, !apiKey.isEmpty else { return }
        
        do {
            let response = try await requestUserSummary(username: username, token: token)
            await MainActor.run {
                self.isLoggedIn = true
                self.userInfo = response
                raLog.info("RetroAchievements token validated for \(username)")
            }
        } catch {
            raLog.error("Token validation failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoggedIn = false
            }
        }
    }
    
    /// Login with username and password to get API token.
    func login(username: String, password: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw RAError.apiKeyMissing
        }
        
        let url = URL(string: "\(apiBaseURL)/APILogin.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "u": username,
            "p": password,
            "y": apiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RAError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let success = json?["Success"] as? Bool, success {
            let token = json?["Token"] as? String ?? ""
            await MainActor.run {
                self.isLoggedIn = true
                self.username = username
                saveSettings(username: username, token: token)
            }
            raLog.info("Login successful for \(username)")
            return token
        } else {
            let error = json?["Error"] as? String ?? "Unknown error"
            throw RAError.loginFailed(error)
        }
    }
    
    // MARK: - Game Identification
    
    /// Identify a game by its hash and fetch achievement data.
    func identifyGame(hash: String) async throws -> RAGameInfo? {
        guard isEnabled, isLoggedIn, !apiKey.isEmpty else { return nil }
        guard let username = username else { return nil }
        
        // First, get game ID from hash
        let gameID = try await resolveHash(hash: hash)
        guard let gameID = gameID else {
            raLog.info("Game not recognized by RetroAchievements")
            return nil
        }
        
        // Fetch game info with achievements
        return try await fetchGameInfo(gameID: gameID, username: username)
    }
    
    /// Resolve a ROM hash to a RetroAchievements game ID.
    private func resolveHash(hash: String) async throws -> Int? {
        guard username != nil else { return nil }
        
        return nil // Requires separate hash resolution endpoint
    }
    
    /// Fetch detailed game info including achievements.
    private func fetchGameInfo(gameID: Int, username: String) async throws -> RAGameInfo {
        let response = try await requestGameInfo(gameID: String(gameID), username: username)
        guard let response = response else {
            throw RAError.gameNotFound
        }
        
        var achievements: [Achievement] = []
        if let achDict = response.Achievements {
            for (_, achResponse) in achDict {
                let achievement = Achievement(
                    id: Int(achResponse.ID) ?? 0,
                    title: achResponse.Title,
                    description: achResponse.Description,
                    points: Int(achResponse.Points) ?? 0,
                    badgeName: achResponse.BadgeName,
                    isUnlocked: achResponse.DateAwarded != nil,
                    unlockDate: achResponse.DateAwarded.flatMap { date in
                        DateFormatter.raDateFormatter.date(from: date)
                    },
                    isHardcore: achResponse.HardcoreAchieved == 1,
                    category: AchievementCategory(rawValue: achResponse.Category ?? "core") ?? .core
                )
                achievements.append(achievement)
            }
        }
        
        return RAGameInfo(
            id: Int(response.ID) ?? 0,
            title: response.Title,
            consoleName: response.ConsoleName,
            consoleID: Int(response.ConsoleID) ?? 0,
            achievements: achievements,
            totalPoints: response.Achievements?.values.reduce(0) { $0 + (Int($1.Points) ?? 0) } ?? 0
        )
    }
    
    // MARK: - Achievement Unlocking
    
    /// Submit an achievement unlock.
    func unlockAchievement(id: Int, hardcore: Bool) async throws {
        guard isLoggedIn, let username = username else { return }
        
        let url = URL(string: "\(apiBaseURL)/AwardAchievement.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "u": username,
            "a": String(id),
            "h": hardcore ? "1" : "0",
            "y": apiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RAError.networkError
        }
        
        raLog.info("Achievement \(id) unlocked (hardcore: \(hardcore))")
        
        // Update local state
        await MainActor.run {
            if let index = currentGame?.achievements.firstIndex(where: { $0.id == id }) {
                currentGame?.achievements[index].isUnlocked = true
                currentGame?.achievements[index].isHardcore = hardcore
                currentGame?.achievements[index].unlockDate = Date()
            }
        }
    }
    
    // MARK: - Leaderboards
    
    /// Fetch leaderboards for a game.
    func fetchLeaderboards(gameID: Int) async throws -> [Leaderboard] {
        guard isLoggedIn, let username = username else { return [] }
        
        let url = URL(string: "\(apiBaseURL)/API_GetGameRankAndScore.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "g", value: String(gameID)),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: apiKey)
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        var leaderboards: [Leaderboard] = []
        if let jsonArray = json {
            for item in jsonArray {
                if let id = item["LBID"] as? Int,
                   let title = item["Title"] as? String,
                   let description = item["Description"] as? String,
                   let format = item["Format"] as? String {
                    let lb = Leaderboard(
                        id: id,
                        title: title,
                        description: description,
                        format: LeaderboardFormat(rawValue: format.lowercased()) ?? .value,
                        lowerIsBetter: item["LowerIsBetter"] as? Bool ?? false,
                        entries: nil
                    )
                    leaderboards.append(lb)
                }
            }
        }
        
        return leaderboards
    }
    
    /// Submit a leaderboard entry.
    func submitLeaderboardScore(leaderboardID: Int, score: Int) async throws {
        guard isLoggedIn, let username = username else { return }
        
        let url = URL(string: "\(apiBaseURL)/API_SubmitLeaderboardEntry.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let body: [String: String] = [
            "u": username,
            "i": String(leaderboardID),
            "s": String(score),
            "y": apiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RAError.networkError
        }
        
        raLog.info("Leaderboard \(leaderboardID) score submitted: \(score)")
    }
    
    // MARK: - Rich Presence
    
    /// Update rich presence message.
    func updateRichPresence(gameID: Int, message: String) async {
        guard isLoggedIn, let username = username else { return }
        
        let url = URL(string: "\(apiBaseURL)/API_Ping.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let body: [String: String] = [
            "u": username,
            "g": String(gameID),
            "m": message,
            "y": apiKey
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.richPresence = message
            }
        } catch {
            raLog.error("Failed to update rich presence: \(error.localizedDescription)")
        }
    }
    
    // MARK: - API Request Helpers
    
    private func requestUserSummary(username: String, token: String) async throws -> RAUserInfo? {
        let url = URL(string: "\(apiBaseURL)/API_GetUserSummary.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "y", value: apiKey),
            URLQueryItem(name: "a", value: "1")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let responseData = json?["User"] as? [String: Any] else { return nil }
        
        return RAUserInfo(
            username: responseData["User"] as? String ?? username,
            totalPoints: (responseData["TotalPoints"] as? String).flatMap { Int($0) } ?? 0,
            totalHardcorePoints: (responseData["TotalHardcorePoints"] as? String).flatMap { Int($0) } ?? 0,
            totalTruePoints: (responseData["TotalTruePoints"] as? String).flatMap { Int($0) } ?? 0,
            rank: (responseData["Rank"] as? String).flatMap { Int($0) } ?? 0,
            awards: (responseData["Awards"] as? String).flatMap { Int($0) } ?? 0,
            memberSince: responseData["MemberSince"] as? String ?? "",
            richPresenceMsg: responseData["RichPresenceMsg"] as? String,
            lastGameID: responseData["LastGameID"] as? Int,
            lastGameTitle: responseData["LastGameTitle"] as? String
        )
    }
    
    private func requestGameInfo(gameID: String, username: String) async throws -> RAGameResponse? {
        let url = URL(string: "\(apiBaseURL)/API_GetGame.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "i", value: gameID),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: apiKey)
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(RAGameResponse.self, from: data)
    }
}

// MARK: - RA Error Types

enum RAError: LocalizedError {
    case apiKeyMissing
    case networkError
    case loginFailed(String)
    case gameNotFound
    case invalidHash
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "RetroAchievements API key is not configured"
        case .networkError:
            return "Network error occurred"
        case .loginFailed(let msg):
            return "Login failed: \(msg)"
        case .gameNotFound:
            return "Game not found in RetroAchievements database"
        case .invalidHash:
            return "Invalid ROM hash for this system"
        }
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let raDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
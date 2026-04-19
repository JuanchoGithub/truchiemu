import Foundation

// MARK: - RetroAchievements Service

// Service for interacting with the RetroAchievements API.
// Handles authentication, game identification, achievement tracking, and leaderboards.
import SwiftData

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
    
    // The user's personal Web API Key used to authenticate all REST requests
    private var webApiKey: String = ""

    private var modelContext: ModelContext?

    /// Injected by the Coordinator/App to allow SwiftData access
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Initialization
    
    private init() {
        loadSettings()
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        username = AppSettings.get("ra_username", type: String.self)
        let key = AppSettings.get("ra_web_api_key", type: String.self)
        hardcoreMode = AppSettings.getBool("ra_hardcore", defaultValue: false)
        isEnabled = AppSettings.getBool("ra_enabled", defaultValue: false)
        
        if let key = key, let username = username, !key.isEmpty {
            self.webApiKey = key
            Task { await validateCredentials(username: username, webApiKey: key) }
        }
    }
    
    func saveSettings(username: String, webApiKey: String) {
        AppSettings.set("ra_username", value: username)
        AppSettings.set("ra_web_api_key", value: webApiKey)
        
        self.username = username
        self.webApiKey = webApiKey
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
    
    /// Validates the user's Web API Key by attempting to fetch their user summary.
    func loginWithWebApiKey(username: String, webApiKey: String) async throws {
        // Temporarily set the key so the request wrapper can use it
        self.webApiKey = webApiKey
        
        do {
            guard let response = try await requestUserSummary(username: username) else {
                throw RAError.loginFailed("Invalid Web API Key or Username.")
            }
            
            await MainActor.run {
                self.isLoggedIn = true
                self.username = username
                self.userInfo = response
                self.saveSettings(username: username, webApiKey: webApiKey)
            }
            
            LoggerService.info(category: "RetroAchievements", "Logged in successfully as \(username)")
            
        } catch {
            await MainActor.run {
                self.webApiKey = "" // Reset on failure
                self.isLoggedIn = false
            }
            LoggerService.error(category: "RetroAchievements", "Login failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Validate stored credentials on app launch.
    private func validateCredentials(username: String, webApiKey: String) async {
        guard isEnabled, !webApiKey.isEmpty else { return }
        
        do {
            try await loginWithWebApiKey(username: username, webApiKey: webApiKey)
        } catch {
            LoggerService.error(category: "RetroAchievements", "Token validation failed on launch.")
        }
    }
    
    // MARK: - Game List Caching (New)

    /// Fetches the entire game list from RA and stores it locally.
    /// Should be called on first login or when requested via UI.
    func fetchAndCacheGameList() async throws {
        guard isEnabled, isLoggedIn, let context = modelContext else {
            throw RAError.networkError 
        }
        guard let username = username else { return }

        LoggerService.info(category: "RetroAchievements", "Fetching full game list from RA...")

        // API endpoint: https://api-docs.retroachievements.org/v1/get-game-list.html
        let url = URL(string: "\(apiBaseURL)/API_GetGameList.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        
        // Decode the response (Expected format: Array of objects)
        let raGames = try JSONDecoder().decode([RARAGameListResponse].self, from: data)

        // Transactional update to the local cache
        try await context.transaction {
            // Clear old cache to ensure a clean, up-to-date list
            try context.delete(model: RAGameCacheEntry.self)

            for raGame in raGames {
                let entry = RAGameCacheEntry(
                    id: Int(raGame.ID) ?? 0,
                    title: raGame.Title,
                    consoleID: Int(raGame.ConsoleID) ?? 0,
                    consoleName: raGame.ConsoleName
                )
                context.insert(entry)
            }
        }
        
        LoggerService.info(category: "RetroAchievements", "Successfully cached \(raGames.count) games from RA.")
    }

    /// Performs a local search in the RAGameCacheEntry database for a name match.
    func identifyGameByName(title: String, consoleID: Int) async -> Int? {
        guard let context = modelContext else { return nil }
        
        // Use localizedStandardContains for resilient name matching
        let predicate = #Predicate<RAGameCacheEntry> {
            $0.title.localizedStandardContains(title) && $0.consoleID == consoleID
        }
        
        let descriptor = FetchDescriptor<RAGameCacheEntry>(predicate: predicate)
        
        do {
            let results = try context.fetch(descriptor)
            // Return the first match found in the local cache
            return results.first?.id
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to search local RA cache: \(error)")
            return nil
        }
    }

    // MARK: - Game Identification
    
    /// Coordinates the identification of a local ROM with RetroAchievements.
    /// Performs name-based lookup via local cache, followed by hash verification via API.
    func syncROMWithRA(rom: ROM) async {
        guard isLoggedIn, let systemID = rom.systemID, let context = modelContext else { return }

        LoggerService.info(category: "RetroAchievements", "Syncing \(rom.name) with RA...")

        // 0. Find the corresponding ROMEntry in SwiftData
        let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.id == rom.id })
        guard let romEntry = try? context.fetch(descriptor).first else {
            LoggerService.error(category: "RetroAchievements", "Syncing \(rom.name) failed: ROMEntry not found in SwiftData.")
            return
        }

        // 1. Attempt Name-based identification using the local RA cache
        let raConsoleID = mapSystemIDToRAConsoleID(systemID)
        
        if let raGameID = await identifyGameByName(title: rom.name, consoleID: raConsoleID) {
            romEntry.raGameId = raGameID
            
            // 2. Verify the exact version using the ROM's hash (if available)
            if let romHash = rom.crc32 {
                do {
                    // Check if the provided hash matches the RA database for this specific Game ID
                    let raGameIDFromHash = try await resolveHash(hash: romHash)
                    
                    if raGameIDFromHash == raGameID {
                        romEntry.raMatchStatus = "matched"
                    } else {
                        // The game is found by name, but the hash points to a different RA Game ID (version mismatch)
                        romEntry.raMatchStatus = "mismatch:\(romHash)"
                    }
                } catch {
                    LoggerService.error(category: "RetroAchievements", "Hash verification failed for \(rom.name): \(error)")
                }
            }
        } else {
            // 3. Fallback: If name match fails, try identifying by hash only
            if let romHash = rom.crc32 {
                if let raGameID = try? await resolveHash(hash: romHash) {
                    romEntry.raGameId = raGameID
                    romEntry.raMatchStatus = "matched"
                } else {
                    romEntry.raMatchStatus = "not_supported"
                }
            }
        }
        
        // Persist changes to SwiftData
        try? context.save()
    }

    /// Helper to map Libretro/SystemDatabase IDs to RetroAchievements Console IDs
    private func mapSystemIDToRAConsoleID(_ systemID: String) -> Int {
        // Implementation will include a mapping dictionary (e.g., "nes" -> 1, "snes" -> 2, etc.)
        // based on the RA API documentation.
        let mapping: [String: Int] = [
            "nes": 1,
            "snes": 2,
            "genesis": 3,
            "megadrive": 3,
            "sms": 4,
            "gamegear": 5,
            "gba": 6,
            "gb": 7,
            "gbc": 8,
            "nds": 9,
            "psx": 10,
            "ps2": 11,
            "psp": 12,
            "n64": 13,
            "dreamcast": 14,
            "saturn": 15,
            "mame": 16,
            "arcade": 16
        ]
        return mapping[systemID.lowercased()] ?? 0
    }

    // Identify a game by its hash and fetch achievement data.
    func identifyGame(hash: String) async throws -> RAGameInfo? {
        guard isEnabled, isLoggedIn, !webApiKey.isEmpty else { return nil }
        guard let username = username else { return nil }
        
        // First, get game ID from hash
        let gameID = try await resolveHash(hash: hash)
        guard let gameID = gameID else {
            LoggerService.info(category: "RetroAchievements", "Game not recognized by RetroAchievements")
            return nil
        }
        
        // Fetch game info with achievements
        return try await fetchGameInfo(gameID: gameID, username: username)
    }
    
    // Resolve a ROM hash to a RetroAchievements game ID.
    private func resolveHash(hash: String) async throws -> Int? {
        guard let username = username else { return nil }
        LoggerService.debug(category: "RetroAchievements", "Resolving hash for user \(username)")
        
        do {
            if let response = try await requestGameByHash(hash: hash, username: username) {
                return Int(response.ID)
            }
        } catch {
            LoggerService.error(category: "RetroAchievements", "Hash resolution failed: \(error.localizedDescription)")
        }
        
        return nil
    }

    // Fetch game ID from a ROM hash.
    private func requestGameByHash(hash: String, username: String) async throws -> RAHashResponse? {
        let url = URL(string: "\(apiBaseURL)/API_GetGameByHash.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        LoggerService.debug(category: "RetroAchievements", "Requesting Game, hash \(hash), user: \(username)")

        components.queryItems = [
            URLQueryItem(name: "h", value: hash),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        LoggerService.debug(category: "RetroAchievements", "Requesting Game, url: \(components.url)")
        // Check for error in JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errorMsg = json?["Error"] as? String {
            LoggerService.debug(category: "RetroAchievements", "Hash resolution error: \(errorMsg)")
            return nil
        }
        
        return try JSONDecoder().decode(RAHashResponse.self, from: data)
    }
    
    // Fetch detailed game info including achievements.
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
    
    // Submit an achievement unlock.
    func unlockAchievement(id: Int, hardcore: Bool) async throws {
        guard isLoggedIn, let username = username, !webApiKey.isEmpty else { return }
        
        let url = URL(string: "\(apiBaseURL)/AwardAchievement.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body:[String: String] = [
            "u": username,
            "a": String(id),
            "h": hardcore ? "1" : "0",
            "y": webApiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RAError.networkError
        }
        
        LoggerService.info(category: "RetroAchievements", "Achievement \(id) unlocked (hardcore: \(hardcore))")
        
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
    
    // Fetch leaderboards for a game.
    func fetchLeaderboards(gameID: Int) async throws -> [Leaderboard] {
        guard isLoggedIn, let username = username, !webApiKey.isEmpty else { return[] }
        
        let url = URL(string: "\(apiBaseURL)/API_GetGameRankAndScore.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "g", value: String(gameID)),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
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
    
    // Submit a leaderboard entry.
    func submitLeaderboardScore(leaderboardID: Int, score: Int) async throws {
        guard isLoggedIn, let username = username, !webApiKey.isEmpty else { return }
        
        let url = URL(string: "\(apiBaseURL)/API_SubmitLeaderboardEntry.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let body: [String: String] = [
            "u": username,
            "i": String(leaderboardID),
            "s": String(score),
            "y": webApiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RAError.networkError
        }
        
        LoggerService.info(category: "RetroAchievements", "Leaderboard \(leaderboardID) score submitted: \(score)")
    }
    
    // MARK: - Rich Presence
    
    // Update rich presence message.
    func updateRichPresence(gameID: Int, message: String) async {
        guard isLoggedIn, let username = username, !webApiKey.isEmpty else { return }
        
        let url = URL(string: "\(apiBaseURL)/API_Ping.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let body:[String: String] = [
            "u": username,
            "g": String(gameID),
            "m": message,
            "y": webApiKey
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.richPresence = message
            }
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to update rich presence: \(error.localizedDescription)")
        }
    }
    
    // MARK: - API Request Helpers
    
    private struct RARAGameListResponse: Decodable {
        let ID: String
        let Title: String
        let ConsoleID: String
        let ConsoleName: String
    }

    private func requestUserSummary(username: String) async throws -> RAUserInfo? {
        let url = URL(string: "\(apiBaseURL)/API_GetUserSummary.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey), // Auth happens here
            URLQueryItem(name: "a", value: "1")
        ]
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RAError.networkError
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Throw proper error if RetroAchievements rejects the Web API Key
        if let errorMsg = json?["Error"] as? String {
            throw RAError.loginFailed(errorMsg)
        }
        
        guard let responseData = json else { return nil }
        
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
            URLQueryItem(name: "y", value: webApiKey)
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
            return "RetroAchievements Web API key is not configured"
        case .networkError:
            return "Network error occurred"
        case .loginFailed(let msg):
            return "Connection failed: \(msg)"
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

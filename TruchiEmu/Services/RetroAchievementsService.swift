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
        try context.transaction {
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
    
    // Find game by hash - tries local cache first, then falls back to API
    func findGameByHashLocally(consoleID: Int, hash: String) async -> (id: Int, title: String, hashes: [String])? {
        // First try local cache
        if let context = modelContext {
            let lowerHash = hash.lowercased()
            let predicate = #Predicate<RAGameCacheEntry> {
                $0.consoleID == consoleID
            }
            let descriptor = FetchDescriptor<RAGameCacheEntry>(predicate: predicate)
            
            if let results = try? context.fetch(descriptor) {
                for entry in results {
                    if entry.hashes.contains(where: { $0.lowercased() == lowerHash }) {
                        return (entry.id, entry.title, entry.hashes)
                    }
                }
            }
        }
        
        // If not in cache, try to resolve via API directly
        return await resolveHashViaAPI(hash: hash, consoleID: consoleID)
    }
    
    // Find all games by name - tries local cache first, then falls back to API  
    func findAllRAGamesByName(title: String, consoleID: Int) async -> [(id: Int, title: String, hashes: [String])] {
        // First try local cache
        if let context = modelContext {
            let predicate = #Predicate<RAGameCacheEntry> {
                $0.title.localizedStandardContains(title) && $0.consoleID == consoleID
            }
            let descriptor = FetchDescriptor<RAGameCacheEntry>(predicate: predicate)
            
            if let results = try? context.fetch(descriptor) {
                return results.map { ($0.id, $0.title, $0.hashes) }
            }
        }
        
        // If not in cache, search via API
        return await searchGamesByNameViaAPI(title: title, consoleID: consoleID)
    }
    
    // Search games by name via RA API
    private func searchGamesByNameViaAPI(title: String, consoleID: Int) async -> [(id: Int, title: String, hashes: [String])] {
        guard let username = username, !webApiKey.isEmpty else { return [] }
        
        // Use the generic game list endpoint filtered by console and search term
        let url = URL(string: "\(apiBaseURL)/API_GetGameList.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey),
            URLQueryItem(name: "i", value: String(consoleID)),
            URLQueryItem(name: "f", value: "1")
        ]
        
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!) else { return [] }
        
        // Parse the list and filter by title
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let lowerTitle = title.lowercased()
            return json.compactMap { game in
                guard let gameTitle = game["Title"] as? String,
                      gameTitle.lowercased().contains(lowerTitle),
                      let idStr = game["ID"] as? String,
                      let id = Int(idStr) else { return nil }
                let hashes = game["Hashes"] as? [String] ?? []
                return (id, gameTitle, hashes)
            }
        }
        
        return []
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
        
        if let raGameId = await identifyGameByName(title: rom.name, consoleID: raConsoleID) {
            romEntry.raGameId = raGameId
            
            // 2. Verify the exact version using the ROM's hash (if available)
            if let romHash = rom.crc32 {
                do {
                    // Check if the provided hash matches the RA database for this specific Game ID
                    let raGameIDFromHash = try await resolveHash(hash: romHash)
                    
                    if raGameIDFromHash == raGameId {
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
                if let raGameId = try? await resolveHash(hash: romHash) {
                    romEntry.raGameId = raGameId
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
    func mapSystemIDToRAConsoleID(_ systemID: String) -> Int {
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
    
    // Resolve hash directly via RA API - returns game info
    private func resolveHashViaAPI(hash: String, consoleID: Int) async -> (id: Int, title: String, hashes: [String])? {
        guard let username = username, !webApiKey.isEmpty else { return nil }
        
        // This calls the API to resolve hash to game ID
        let url = URL(string: "\(apiBaseURL)/API_GetGameByHash.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "h", value: hash),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
        ]
        
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!) else { return nil }
        
        // Response format: {"ID":"10","Title":"Sonic the Hedgehog 2","Hashes":["abc123",...]}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let idStr = json["ID"] as? String,
                  let title = json["Title"] as? String else {
                // Check for error
                if let error = json["Error"] as? String {
                    LoggerService.info(category: "RetroAchievements", "Hash resolution error: \(error)")
                }
                return nil
            }
            
            let gameId = Int(idStr) ?? 0
            let hashes = json["Hashes"] as? [String] ?? []
            
            LoggerService.info(category: "RetroAchievements", "Resolved hash to game: \(title) (ID: \(gameId))")
            return (gameId, title, hashes)
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
        LoggerService.debug(category: "RetroAchievements", "Requesting Game, url: \(components.url?.absoluteString ?? "unknown")")
        // Check for error in JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errorMsg = json?["Error"] as? String {
            LoggerService.debug(category: "RetroAchievements", "Hash resolution error: \(errorMsg)")
            return nil
        }
        
        return try JSONDecoder().decode(RAHashResponse.self, from: data)
    }
    
    // Fetch detailed game info including achievements.
    func fetchGameInfo(gameID: Int, username: String) async throws -> RAGameInfo {
        // 1. Try to load from cache first
        if let cached = await loadGameInfoFromCache(gameID: gameID, username: username) {
            // Check freshness (6 months)
            let sixMonths: TimeInterval = 180 * 24 * 3600
            if Date().timeIntervalSince(cached.cachedAt) < sixMonths {
                LoggerService.info(category: "RetroAchievements", "Using cached achievement info for game \(gameID) (cached at \(cached.cachedAt))")
                
                // Still trigger badge prefetch just in case
                RABadgeCacheService.shared.prefetchBadges(for: cached.gameInfo.achievements)
                
                return cached.gameInfo
            }
            LoggerService.info(category: "RetroAchievements", "Cached achievement info for game \(gameID) is stale, re-fetching...")
        }

        let response = try await requestGameInfo(gameID: String(gameID), username: username)
        guard let response = response else {
            throw RAError.gameNotFound
        }
        
        var achievements: [Achievement] = []
        if let achDict = response.Achievements {
            for (_, achResponse) in achDict {
                let achievement = Achievement(
                    id: achResponse.ID,
                    title: achResponse.Title,
                    description: achResponse.Description,
                    points: achResponse.Points,
                    badgeName: achResponse.BadgeName,
                    isUnlocked: achResponse.DateAwarded != nil,
                    unlockDate: achResponse.DateAwarded.flatMap { date in
                        DateFormatter.raDateFormatter.date(from: date)
                    },
                    isHardcore: achResponse.DateAwardedHardcore != nil,
                    category: AchievementCategory(rawValue: achResponse.Category ?? "core") ?? .core
                )
                achievements.append(achievement)
            }
            RABadgeCacheService.shared.prefetchBadges(for: achievements)
        }
        
        let gameInfo = RAGameInfo(
            id: response.ID ?? 0,
            title: response.Title ?? "",
            consoleName: response.ConsoleName ?? "",
            consoleID: response.ConsoleID ?? 0,
            achievements: achievements,
            totalPoints: response.Achievements?.values.reduce(0) { $0 + $1.Points } ?? 0
        )
        
        // Save to cache
        await saveGameInfoToCache(gameInfo: gameInfo, username: username)
        
        return gameInfo
    }
    
    @MainActor
    private func loadGameInfoFromCache(gameID: Int, username: String) async -> (gameInfo: RAGameInfo, cachedAt: Date)? {
        guard let context = modelContext else { return nil }
        
        let gamePredicate = #Predicate<RAGameAchievementCache> { $0.gameId == gameID }
        let gameDescriptor = FetchDescriptor<RAGameAchievementCache>(predicate: gamePredicate)
        
        guard let gameCache = try? context.fetch(gameDescriptor).first else { return nil }
        
        let achPredicate = #Predicate<RAAchievementCacheEntry> { $0.gameId == gameID && $0.username == username }
        let achDescriptor = FetchDescriptor<RAAchievementCacheEntry>(predicate: achPredicate)
        
        guard let achEntries = try? context.fetch(achDescriptor) else { return nil }
        // If we found the game cache but no achievements for this user, we might need a re-fetch
        if achEntries.isEmpty && gameCache.achievementCount > 0 { return nil }

        let achievements = achEntries.map { entry in
            Achievement(
                id: entry.achievementId,
                title: entry.title,
                description: entry.achDescription,
                points: entry.points,
                badgeName: entry.badgeName,
                isUnlocked: entry.dateAwarded != nil,
                unlockDate: entry.dateAwarded,
                isHardcore: entry.dateAwardedHardcore != nil,
                category: AchievementCategory(rawValue: entry.category) ?? .core
            )
        }
        
        let gameInfo = RAGameInfo(
            id: gameCache.gameId,
            title: gameCache.title,
            consoleName: gameCache.consoleName,
            consoleID: gameCache.consoleID,
            achievements: achievements,
            totalPoints: gameCache.totalPoints
        )
        
        return (gameInfo, gameCache.cachedAt)
    }
    
    @MainActor
    private func saveGameInfoToCache(gameInfo: RAGameInfo, username: String) async {
        guard let context = modelContext else { return }
        
        // 1. Update/Create Game Cache
        let gameID = gameInfo.id
        let gamePredicate = #Predicate<RAGameAchievementCache> { $0.gameId == gameID }
        let gameDescriptor = FetchDescriptor<RAGameAchievementCache>(predicate: gamePredicate)
        
        if let existingGame = try? context.fetch(gameDescriptor).first {
            existingGame.achievementCount = gameInfo.achievements.count
            existingGame.title = gameInfo.title
            existingGame.consoleName = gameInfo.consoleName
            existingGame.consoleID = gameInfo.consoleID
            existingGame.totalPoints = gameInfo.totalPoints
            existingGame.cachedAt = Date()
        } else {
            let newGame = RAGameAchievementCache(
                gameId: gameInfo.id,
                achievementCount: gameInfo.achievements.count,
                title: gameInfo.title,
                consoleName: gameInfo.consoleName,
                consoleID: gameInfo.consoleID,
                totalPoints: gameInfo.totalPoints,
                cachedAt: Date()
            )
            context.insert(newGame)
        }
        
        // 2. Update/Create Achievement Entries
        for ach in gameInfo.achievements {
            let achID = ach.id
            let achPredicate = #Predicate<RAAchievementCacheEntry> { $0.achievementId == achID && $0.username == username }
            let achDescriptor = FetchDescriptor<RAAchievementCacheEntry>(predicate: achPredicate)
            
            if let existingAch = try? context.fetch(achDescriptor).first {
                existingAch.title = ach.title
                existingAch.achDescription = ach.description
                existingAch.points = ach.points
                existingAch.badgeName = ach.badgeName
                existingAch.category = ach.category.rawValue
                existingAch.dateAwarded = ach.unlockDate
                existingAch.dateAwardedHardcore = ach.isHardcore ? ach.unlockDate : nil // Approximation
                existingAch.cachedAt = Date()
            } else {
                let newAch = RAAchievementCacheEntry(
                    achievementId: ach.id,
                    gameId: gameInfo.id,
                    title: ach.title,
                    description: ach.description,
                    points: ach.points,
                    badgeName: ach.badgeName,
                    category: ach.category.rawValue,
                    dateAwarded: ach.unlockDate,
                    dateAwardedHardcore: ach.isHardcore ? ach.unlockDate : nil,
                    username: username,
                    cachedAt: Date()
                )
                context.insert(newAch)
            }
        }
        
        try? context.save()
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
        let url = URL(string: "\(apiBaseURL)/API_GetGameExtended.php")!
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

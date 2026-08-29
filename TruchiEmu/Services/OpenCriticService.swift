import Foundation
import Combine

@MainActor
class OpenCriticService: ObservableObject {
    static let shared = OpenCriticService()
    
    @Published var isFetching: Bool = false
    @Published var lastError: String?
    @Published var fetchedGameIDs: Set<UUID> = Set()

    // Connection-test UI state
    @Published var isTestingConnection: Bool = false
    @Published var connectionTestMessage: String?
    @Published var connectionTestSuccess: Bool?
    
    private let apiBaseURL = "https://opencritic-api.p.rapidapi.com"
    private let apiKeyKey = "opencritic_api_key"
    private let apiHostKey = "opencritic_api_host"
    
    // MARK: - Configuration
    
    var apiKey: String? {
        get { AppSettings.getString(apiKeyKey, defaultValue: nil) }
        set { AppSettings.setString(apiKeyKey, value: newValue ?? "") }
    }
    
    var apiHost: String {
        get { AppSettings.getString(apiHostKey, defaultValue: "opencritic-api.p.rapidapi.com") ?? "opencritic-api.p.rapidapi.com" }
        set { AppSettings.setString(apiHostKey, value: newValue) }
    }
    
    // MARK: - Search
    
    // OpenCritic RapidAPI search returns a top-level JSON array of game summaries
    // (not a wrapped object). Query parameter is `criteria`.
    func searchGames(query: String) async throws -> [OpenCriticGameSummary] {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenCriticError.missingAPIKey
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(apiBaseURL)/game/search?criteria=\(encodedQuery)")!
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "x-rapidapi-key")
        request.addValue(apiHost, forHTTPHeaderField: "x-rapidapi-host")
        
        LoggerService.info(category: "OpenCritic", "GET /game/search?criteria=<\(query)>")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            LoggerService.info(category: "OpenCritic", "GET /game/search -> HTTP \(http.statusCode)")
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)?.prefix(800) ?? "<non-utf8>"
                LoggerService.error(category: "OpenCritic", "Search request failed (HTTP \(http.statusCode)): \(body)")
                throw OpenCriticError.httpStatus(http.statusCode)
            }
        }
        
        let games = try JSONDecoder().decode([OpenCriticGameSummary].self, from: data)
        LoggerService.info(category: "OpenCritic", "Search returned \(games.count) results")
        return games
    }
    
    // MARK: - Game Details
    
    // Detail endpoint returns the game object directly (no wrapper).
    func getGameDetails(id: Int) async throws -> OpenCriticGameDetail {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenCriticError.missingAPIKey
        }
        
        let url = URL(string: "\(apiBaseURL)/game/\(id)")!
        var request = URLRequest(url: url)
        request.addValue(key, forHTTPHeaderField: "x-rapidapi-key")
        request.addValue(apiHost, forHTTPHeaderField: "x-rapidapi-host")
        
        LoggerService.info(category: "OpenCritic", "GET /game/\(id)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            LoggerService.info(category: "OpenCritic", "GET /game/\(id) -> HTTP \(http.statusCode)")
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)?.prefix(800) ?? "<non-utf8>"
                LoggerService.error(category: "OpenCritic", "Game details request failed (HTTP \(http.statusCode)): \(body)")
                throw OpenCriticError.httpStatus(http.statusCode)
            }
        }
        
        return try JSONDecoder().decode(OpenCriticGameDetail.self, from: data)
    }
    
    // MARK: - Fetch for ROM
    
    func fetchOpenCriticData(for rom: ROM) async {
        guard apiKey != nil else {
            lastError = "OpenCritic API key not configured. Add it in Settings."
            isFetching = false
            return
        }
        
        isFetching = true
        lastError = nil
        
        do {
            // If we already resolved this ROM to an OpenCritic game ID on a
            // previous fetch, skip the search call entirely (saves 1 of 2 hits).
            let gameID: Int
            if let cachedID = rom.metadata?.openCriticID, cachedID > 0 {
                gameID = cachedID
                LoggerService.info(category: "OpenCritic", "Using cached game ID \(gameID) for '\(rom.displayName)' (skipping search)")
            } else {
                let summaries = try await searchGames(query: rom.displayName)
                guard let summary = summaries.first(where: { $0.name.lowercased() == rom.displayName.lowercased() }) else {
                    lastError = "No OpenCritic match found for '\(rom.displayName)'"
                    isFetching = false
                    return
                }
                gameID = summary.id
            }

            let details = try await getGameDetails(id: gameID)

            // Review count is already provided by the detail payload
            // (numTopCriticReviews), so we do not spend a separate API call on it.
            let reviewCount = details.numTopCriticReviews ?? 0

            NotificationCenter.default.post(
                name: NSNotification.Name("OpenCriticDataFetched"),
                object: nil,
                userInfo: [
                    "romID": rom.id,
                    "gameID": gameID,
                    "score": details.topCriticScore ?? 0,
                    "percentRecommended": details.percentRecommended ?? 0,
                    "tier": details.tier ?? "Unrated",
                    "numReviews": details.numTopCriticReviews ?? reviewCount
                ]
            )
        } catch {
            lastError = error.localizedDescription
        }
        
        isFetching = false
    }
    
    // MARK: - Test Connection
    
    // Performs a lightweight search to validate the API key and connectivity.
    func testAPIConnection() async {
        isTestingConnection = true
        connectionTestMessage = nil
        connectionTestSuccess = nil
        defer { isTestingConnection = false }
        
        guard let key = apiKey, !key.isEmpty else {
            connectionTestSuccess = false
            connectionTestMessage = "OpenCritic API key not configured. Add it in Settings."
            LoggerService.warning(category: "OpenCritic", "Test connection skipped: no API key set")
            return
        }
        
        LoggerService.info(category: "OpenCritic", "Testing API connection…")
        do {
            let results = try await searchGames(query: "zelda")
            connectionTestSuccess = true
            connectionTestMessage = "Connection successful — \(results.count) games found for \"zelda\"."
            LoggerService.info(category: "OpenCritic", "Test connection succeeded (\(results.count) results)")
        } catch {
            connectionTestSuccess = false
            connectionTestMessage = "Connection failed: \(error.localizedDescription)"
            LoggerService.error(category: "OpenCritic", "Test connection failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Error Types
    
    enum OpenCriticError: Error, LocalizedError {
        case missingAPIKey
        case networkFailed
        case noMatchFound
        case decodingFailed
        case httpStatus(Int)
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenCritic API key not configured. Add it in Settings."
            case .networkFailed:
                return "Network error while fetching OpenCritic data."
            case .noMatchFound:
                return "No OpenCritic match found for this game."
            case .decodingFailed:
                return "Failed to parse OpenCritic response."
            case .httpStatus(let code):
                return "OpenCritic API returned HTTP \(code). Check your API key and RapidAPI subscription."
            }
        }
    }
}

// MARK: - Data Models

struct OpenCriticGameSummary: Codable, Identifiable {
    let id: Int
    let name: String
    let topCriticScore: Double?
    let percentRecommended: Double?
    let tier: String?
    let firstReleaseDate: String?
    let url: String?
    let platforms: [OpenCriticPlatformSummary]?
}

struct OpenCriticGameDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let topCriticScore: Double?
    let percentRecommended: Double?
    let tier: String?
    let numTopCriticReviews: Int?
    let firstReleaseDate: String?
    let url: String?
    let description: String?
    let platforms: [OpenCriticPlatform]?
    let genres: [OpenCriticGenre]?
    let companies: [OpenCriticCompany]?
    let images: OpenCriticImages?
}

struct OpenCriticPlatform: Codable, Identifiable {
    let id: Int
    let name: String
    let shortName: String?
    let imageSrcV2: String?
}

struct OpenCriticPlatformSummary: Codable {
    let platform: String?
    let image: String?
}

struct OpenCriticGenre: Codable {
    let name: String
    let slug: String?
}

struct OpenCriticCompany: Codable {
    let name: String
    let type: String?
}

struct OpenCriticImages: Codable {
    let banner: OpenCriticImageRef?
    let box: OpenCriticImageRef?
    let screenshot: OpenCriticImageRef?
}

struct OpenCriticImageRef: Codable {
    let og: String?
    let sm: String?
    let md: String?
    let lg: String?
}

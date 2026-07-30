import Foundation
import AppKit

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
    
    private func shouldFetch(cachedAt: Date?, isUserInitiated: Bool) -> Bool {
        guard let cachedAt = cachedAt else { return true }

        let twentyFourHours: TimeInterval = 24 * 3600
        let oneHour: TimeInterval = 3600

        // 24h for background fetches, 1h for user-initiated refreshes, always fetch when forced.
        let threshold = isUserInitiated ? oneHour : twentyFourHours
        return Date().timeIntervalSince(cachedAt) >= threshold
    }
    @Published var currentGame: RAGameInfo?
    @Published var userInfo: RAUserInfo?
    @Published var hardcoreMode = true
    @Published var isEnabled = false
    @Published var richPresence: String?
    
    // MARK: - "Match All Games" progress (observed by Library + Settings views)
    @Published var isMatchingAll = false
    @Published var matchedAllCount = 0
    @Published var matchedAllTotal = 0
    // True during the cache-import phase of "Match All Games". When true the
    // views show "Importing game cache (step/total files)"; when false they
    // show the matched-count progress line.
    @Published var isImportingRACache = false
    @Published var importRACacheStep = 0
    @Published var importRACacheTotal = 0
    
    // MARK: - Configuration
    
    private let apiBaseURL = "https://retroachievements.org/API"
    
    private static let baseFolder: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("TruchiEmu/RetroAchievements", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    
    private static let gameDataFolder: URL = {
        let folder = baseFolder.appendingPathComponent("Games", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static let listDataFolder: URL = {
        let folder = baseFolder.appendingPathComponent("Lists", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    
    private var baseFolder: URL { Self.baseFolder }
    private var gameDataFolder: URL { Self.gameDataFolder }
    private var listDataFolder: URL { Self.listDataFolder }
    
    // The user's personal Web API Key used to authenticate all REST requests
    private var webApiKey: String = ""

    // Token from dorequest.php?r=login2 — required for patch fetch and other dorequest calls.
    // Different from the Web API key (which uses y= param on REST endpoints).
    private var loginToken: String?

    // The last known login token, kept around even after `loginToken` is cleared on
    // an expired_token response. Used by `fetchLoginToken()` to attempt a token refresh
    // via dorequest.php?r=login2&t=<token> — RA's login2 endpoint reissues a fresh token
    // if the provided one is still valid.
    private var lastKnownLoginToken: String?
    private var isRefreshingToken = false

    // Set to true when the server definitively rejects our token (invalid_credentials
    // or expired_token that can't be refreshed). While true, all RA write operations
    // (unlock, ping, start session, patch fetch) bail early. Cleared on a successful
    // re-login via loginWithWebApiKey.
    private var isLoggedOutByTokenFailure = false
    // Guards the "re-login needed" notification so it fires at most once per session.
    private var hasSurfacedTokenReloginNeeded = false

    private var pendingUnlocks: [(id: Int, hardcore: Bool)] = []
    private var isProcessingUnlocks = false
    private var lastUnlockTime: Date = .distantPast

    // Resolved live from the current SwiftData container rather than cached, so it
    // always reflects the active store even if the container is recreated (migration,
    // reset, reload). Caching it at launch caused matching to read a stale context
    // that no longer held the full library.
    private var modelContext: ModelContext? {
        SwiftDataContainer.shared.mainContext
    }

    /// Kept for compatibility with the app's launch wiring; the context is now
    /// resolved live from SwiftDataContainer.shared.mainContext.
    func setModelContext(_ context: ModelContext) {}
    
    // MARK: - Initialization
    
    private init() {
        loadSettings()
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        username = AppSettings.get("ra_username", type: String.self)
        let key = AppSettings.get("ra_web_api_key", type: String.self)
        loginToken = AppSettings.get("ra_login_token", type: String.self)
        lastKnownLoginToken = loginToken
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

    /// Validates the user's Web API Key by attempting to fetch their user summary,
    /// then exchanges the password for a login token via login2 (if not already cached).
    func loginWithWebApiKey(username: String, webApiKey: String, password: String) async throws {
        self.webApiKey = webApiKey

        do {
            let response = try await requestUserSummary(username: username)

            await MainActor.run {
                self.isLoggedIn = true
                self.username = username
                self.userInfo = response
                self.isLoggedOutByTokenFailure = false
                self.hasSurfacedTokenReloginNeeded = false
                self.saveSettings(username: username, webApiKey: webApiKey)
            }

            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "User summary: pts=\(response.totalPoints) hc=\(response.totalHardcorePoints) true=\(response.totalTruePoints) rank=\(response.rank)")
            #endif

            LoggerService.info(category: "RetroAchievements", "Logged in successfully as \(username)")

            if loginToken == nil && !password.isEmpty {
                do {
                    let token = try await fetchLoginTokenWithPassword(username: username, password: password)
                    await MainActor.run {
                        self.loginToken = token
                        self.lastKnownLoginToken = token
                        AppSettings.set("ra_login_token", value: token)
                    }
                    LoggerService.info(category: "RetroAchievements", "Login token obtained and saved")
                } catch {
                    // Password is wrong — surface this as a credential error so the user knows
                    // exactly what failed. The web API key already validated (user summary succeeded).
                    LoggerService.error(category: "RetroAchievements", "Password login failed: \(error.localizedDescription)")
                    throw error
                }
            }

            Task {
                try? await fetchAndCacheGameList()
                if needsHashDownload() {
                    LoggerService.info(category: "RetroAchievements", "Hash data missing, auto-triggering game list download with hashes...")
                    try? await fetchAndCacheAllGames()
                }
            }

        } catch {
            await MainActor.run {
                self.webApiKey = ""
                self.loginToken = nil
                self.isLoggedIn = false
            }
            LoggerService.error(category: "RetroAchievements", "Login failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func fetchLoginTokenWithPassword(username: String, password: String) async throws -> String {
        var cUrl: UnsafeMutablePointer<CChar>?
        var cPostData: UnsafeMutablePointer<CChar>?
        var cContentType: UnsafeMutablePointer<CChar>?

        let initResult = username.withCString { usernamePtr in
            password.withCString { passwordPtr in
                rcheevos_api_init_login(usernamePtr, passwordPtr, &cUrl, &cPostData, &cContentType)
            }
        }

        guard initResult == 0, let urlStr = cUrl else {
            LoggerService.error(category: "RetroAchievements", "rcheevos failed to build login request: \(initResult)")
            rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
            throw RAError.loginFailed("Internal error building login request.")
        }

        let requestURL = String(cString: urlStr)
        let postDataStr = cPostData.map { String(cString: $0) }
        let contentTypeStr = cContentType.map { String(cString: $0) }
        rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)

        #if LOG_DEBUG
        LoggerService.debug(category: "RetroAchievements", "Login2 request URL: \(requestURL)")
        #endif
        #if LOG_DEBUG
        LoggerService.debug(category: "RetroAchievements", "Login2 POST data: \(postDataStr ?? "nil")")
        #endif

        guard let url = URL(string: requestURL) else {
            throw RAError.loginFailed("Internal error building login URL.")
        }

        var request = URLRequest(url: url)
        request.setValue("rcheevos/12.3.0 TruchiEmu/1.0.0", forHTTPHeaderField: "User-Agent")
        if let postData = postDataStr, !postData.isEmpty {
            request.httpMethod = "POST"
            request.httpBody = postData.data(using: .utf8)
            if let ct = contentTypeStr {
                request.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw RAError.from(urlError: urlError)
        } catch {
            throw RAError.networkUnreachable
        }

        var cToken: UnsafeMutablePointer<CChar>?
        let jsonBody = String(data: data, encoding: .utf8) ?? ""
        let result = jsonBody.withCString { bodyPtr in
            rcheevos_api_process_login_response(bodyPtr, data.count, &cToken)
        }

        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard result == 0, let tokenPtr = cToken else {
            LoggerService.error(category: "RetroAchievements", "Login2 response error code=\(result) http=\(httpStatus)")
            free(cToken)
            throw RAError.from(httpStatus: httpStatus == 0 ? 200 : httpStatus, json: json ?? nil)
        }

        let token = String(cString: tokenPtr)
        free(cToken)
        return token
    }

    private func validateCredentials(username: String, webApiKey: String) async {
        guard isEnabled, !webApiKey.isEmpty else { return }

        do {
            try await loginWithWebApiKey(username: username, webApiKey: webApiKey, password: "")
        } catch {
            LoggerService.error(category: "RetroAchievements", "Token validation failed on launch.")
        }
    }

    // MARK: - Game List Caching (New)

    /// Fetches the list of all supported consoles from RA and caches them.
    @discardableResult
    func fetchAndCacheConsoleList(forceRefresh: Bool = false) async throws -> [RAConsole] {
        guard let context = modelContext else { return [] }
        
        // 0. Check freshness
        let fileURL = baseFolder.appendingPathComponent("consoles.json")
        if !forceRefresh, FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modDate = attributes?[.modificationDate] as? Date, !shouldFetch(cachedAt: modDate, isUserInitiated: false) {
                LoggerService.info(category: "RetroAchievements", "Console list is still fresh, skipping fetch.")
                
                let dbConsoles = (try? context.fetch(FetchDescriptor<RAConsole>())) ?? []
                if !dbConsoles.isEmpty {
                    return dbConsoles
                }
                
                // DB is empty but file exists - load from file
                LoggerService.info(category: "RetroAchievements", "Consoles DB empty but fresh file exists, importing...")
                if let data = try? Data(contentsOf: fileURL),
                   let consoles = try? JSONDecoder().decode([RAConsoleResponse].self, from: data) {
                    return await importConsolesFromList(consoles, context: context)
                }
            }
        }

    LoggerService.info(category: "RetroAchievements", "Fetching console list from RA...")
        let coordinator = RAGameCacheCoordinator.shared
        coordinator.startFetchingConsoles()

        let url = URL(string: "\(apiBaseURL)/API_GetConsoleIDs.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
        ]
        
        guard let finalURL = components.url else { throw RAError.networkUnreachable }
        let (data, _) = try await URLSession.shared.data(from: finalURL)
        
        let consoles = try JSONDecoder().decode([RAConsoleResponse].self, from: data)
        let results = await importConsolesFromList(consoles, context: context)
        
        // Save to file for offline reference
        try? data.write(to: fileURL)
        
        LoggerService.info(category: "RetroAchievements", "Successfully cached \(consoles.count) consoles.")
        coordinator.finish()

        return results
    }

    @discardableResult
    private func importConsolesFromList(_ consoles: [RAConsoleResponse], context: ModelContext) async -> [RAConsole] {
        // 1. Get all existing consoles first to avoid per-item fetches
        let existingConsoles = try? context.fetch(FetchDescriptor<RAConsole>())
        let existingMap = Dictionary(uniqueKeysWithValues: (existingConsoles ?? []).map { ($0.id, $0) })
        
        var results: [RAConsole] = []
        
        // 2. Update or insert
        for console in consoles {
            let id = console.ID
            let name = console.Name
            
            if let existing = existingMap[id] {
                existing.name = name
                results.append(existing)
            } else {
                let newConsole = RAConsole(id: id, name: name)
                context.insert(newConsole)
                results.append(newConsole)
            }
        }
        
        do {
            try context.save()
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to save consoles to database: \(error.localizedDescription)")
        }
        
        return results
    }

    /// Fetches game lists for ALL consoles and stores them as local JSON files.
    func fetchAndCacheAllGames(forceRefresh: Bool = false) async throws {
        guard let context = modelContext else { return }
        
        // 1. Get consoles from DB
        var consoles = (try? context.fetch(FetchDescriptor<RAConsole>())) ?? []
        
        if consoles.isEmpty {
            LoggerService.warning(category: "RetroAchievements", "No consoles found in cache. Fetching consoles first...")
            consoles = try await fetchAndCacheConsoleList(forceRefresh: forceRefresh)
            
            if consoles.isEmpty {
                LoggerService.error(category: "RetroAchievements", "Consoles list still empty after fetch. Aborting.")
                return
            }
        }
        
        // 2. Filter consoles to only those present in the user's library
        let romDescriptor = FetchDescriptor<ROMEntry>()
        let userRoms = (try? context.fetch(romDescriptor)) ?? []
        let userSystemIDs = Set(userRoms.compactMap { $0.systemID })
        let userRAConsoleIDs = Set(userSystemIDs.map { mapSystemIDToRAConsoleID($0) })
        
    let filteredConsoles = consoles.filter { userRAConsoleIDs.contains($0.id) }
        LoggerService.info(category: "RetroAchievements", "Refreshing game lists for \(filteredConsoles.count) systems present in library (out of \(consoles.count) total RA consoles).")

        let coordinator = RAGameCacheCoordinator.shared
        let totalConsoles = filteredConsoles.count

        // Uses listDataFolder for console-specific lists
        for (index, console) in filteredConsoles.enumerated() {
            let step = index + 1
            coordinator.startFetchingGames(consoleID: console.id, consoleName: console.name, step: step, total: totalConsoles)

            let safeName = console.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
            let fileName = "\(console.id)_\(safeName).json"
            let fileURL = listDataFolder.appendingPathComponent(fileName)
            
            // Freshness check for individual console list
            if !forceRefresh, FileManager.default.fileExists(atPath: fileURL.path) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let modDate = attributes?[.modificationDate] as? Date, !shouldFetch(cachedAt: modDate, isUserInitiated: false) {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "RetroAchievements", "Skipping fetch for \(console.name), local list is fresh.")
                    #endif
                    continue
                }
            }

            LoggerService.info(category: "RetroAchievements", "Fetching games for console: \(console.name) (ID: \(console.id))...")
            
            let url = URL(string: "\(apiBaseURL)/API_GetGameList.php")!
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "u", value: username),
                URLQueryItem(name: "y", value: webApiKey),
                URLQueryItem(name: "i", value: String(console.id)),
                URLQueryItem(name: "h", value: "1") // Include hashes
            ]
            
            guard let finalURL = components.url else { continue }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: finalURL)
                
                // Save to JSON file with standardized naming
                let safeName = console.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
                let fileName = "\(console.id)_\(safeName).json"
                let fileURL = listDataFolder.appendingPathComponent(fileName)
                try? data.write(to: fileURL)
                
                // Import this specific file into the database
                await importLocalJSONFile(fileURL)
                
                LoggerService.info(category: "RetroAchievements", "Successfully cached games for \(console.name)")
                } catch {
                    LoggerService.error(category: "RetroAchievements", "Failed to fetch games for \(console.name): \(error.localizedDescription)")
                }
                coordinator.updateProgress(Double(step) / Double(totalConsoles), status: coordinator.statusLine)
            }
        
        LoggerService.info(category: "RetroAchievements", "Finished fetching games for all consoles.")
        coordinator.finish()
    }

    /// Fetches the entire game list from RA and stores it locally.
    /// Should be called on first login or when requested via UI.
    /// All heavy work (JSON parsing, SwiftData upserts) runs on a background context.
    func fetchAndCacheGameList(isUserInitiated: Bool = false) async throws {
        guard isEnabled, isLoggedIn else {
            throw RAError.loginFailed("Not logged in to RetroAchievements.")
        }

        guard let container = SwiftDataContainer.shared.container else { return }

        let mainContext = container.mainContext
        let descriptor = FetchDescriptor<RAGameCacheEntry>()
        if let firstEntry = try? mainContext.fetch(descriptor).first {
            if !shouldFetch(cachedAt: firstEntry.cachedAt, isUserInitiated: isUserInitiated) {
                LoggerService.info(category: "RetroAchievements", "RA game cache is still fresh (cached at \(firstEntry.cachedAt)), skipping fetch.")
                return
            }
        }

        LoggerService.info(category: "RetroAchievements", "Fetching entire game list from RA (isUserInitiated=\(isUserInitiated))...")

        // 1. Fetch from API (network I/O — already async)
        let url = URL(string: "\(apiBaseURL)/API_GetGameList.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let raGames = try JSONDecoder().decode([RARAGameListResponse].self, from: data)

        // 2. Determine user's console IDs on main context, then read hash files off-thread
        let romDescriptor = FetchDescriptor<ROMEntry>()
        let userRoms = (try? mainContext.fetch(romDescriptor)) ?? []
        let userSystemIDs = Set(userRoms.compactMap { $0.systemID })
        let userRAConsoleIDs = Set(userSystemIDs.map { String(Self.systemIDToRAConsoleID($0)) })
        let localHashes = await readLocalHashFiles(userRAConsoleIDs: userRAConsoleIDs)

        // 3. Write everything to SwiftData on a background context
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let bgContext = ModelContext(container)
                do {
                    try bgContext.transaction {
                        try bgContext.delete(model: RAGameCacheEntry.self)

                        for raGame in raGames {
                            let entry = RAGameCacheEntry(
                                id: raGame.ID,
                                title: raGame.Title,
                                consoleID: raGame.ConsoleID,
                                consoleName: raGame.ConsoleName,
                                hashes: localHashes[raGame.ID] ?? []
                            )
                            bgContext.insert(entry)
                        }
                    }
                } catch {
                    LoggerService.error(category: "RetroAchievements", "Background SwiftData transaction failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }

        // 4. Sync main context with background changes
        mainContext.processPendingChanges()

        LoggerService.info(category: "RetroAchievements", "Successfully cached \(raGames.count) games from RA (\(localHashes.count) with hashes).")
    }

    /// Reads local JSON cache files and returns a dictionary mapping gameID -> [hashes].
    /// Runs entirely off the main thread — no SwiftData, just file I/O + JSON decoding.
    private nonisolated func readLocalHashFiles(userRAConsoleIDs: Set<String>) async -> [Int: [String]] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let listFolder = appSupport.appendingPathComponent("TruchiEmu/RetroAchievements/Lists", isDirectory: true)

        guard FileManager.default.fileExists(atPath: listFolder.path) else { return [:] }

        let jsonFiles: [URL]
        do {
            jsonFiles = try FileManager.default.contentsOfDirectory(at: listFolder, includingPropertiesForKeys: nil)
                .filter { url in
                    guard url.pathExtension == "json" else { return false }
                    let id = url.lastPathComponent.components(separatedBy: "_").first ?? ""
                    return userRAConsoleIDs.contains(id)
                }
        } catch {
            return [:]
        }

        LoggerService.info(category: "RetroAchievements", "Found \(jsonFiles.count) relevant JSON cache files for your library.")

        var result: [Int: [String]] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let games = try? decoder.decode([GameJSON].self, from: data) else { continue }
            var count = 0
            for game in games {
                if !game.hashes.isEmpty {
                    result[game.id] = game.hashes
                    count += 1
                }
            }
            LoggerService.info(category: "RetroAchievements", "Read \(count) games with hashes from \(fileURL.lastPathComponent)")
        }

        return result
    }

    /// Checks whether local hash JSON files exist for the user's library consoles.
    /// Returns `true` if any relevant hash file is missing.
    @MainActor
    func needsHashDownload() -> Bool {
        guard let context = modelContext else { return true }
        let romDescriptor = FetchDescriptor<ROMEntry>()
        guard let userRoms = try? context.fetch(romDescriptor) else { return true }
        let userSystemIDs = Set(userRoms.compactMap { $0.systemID })
        let userRAConsoleIDs = userSystemIDs.map { Self.systemIDToRAConsoleID($0) }
        guard !userRAConsoleIDs.isEmpty else { return false }

        let listFolder = listDataFolder
        guard FileManager.default.fileExists(atPath: listFolder.path) else { return true }

        guard let jsonFiles = try? FileManager.default.contentsOfDirectory(at: listFolder, includingPropertiesForKeys: nil) else { return true }

        for consoleID in userRAConsoleIDs where consoleID > 0 {
            let hasFile = jsonFiles.contains { url in
                let prefix = url.lastPathComponent.components(separatedBy: "_").first
                return prefix == String(consoleID)
            }
            if !hasFile { return true }
        }
        return false
    }

    /// Pure mapping from system ID to RA console ID — no MainActor required.
    /// Delegates to `RomHasher`, which is the single source of truth for
    /// RetroAchievements console IDs (kept in sync with rcheevos' rc_consoles.h).
    /// Previously this had its own copy with several wrong values (e.g.
    /// pcecd -> 50 instead of 76) which made disc games fail to match.
    private nonisolated static func systemIDToRAConsoleID(_ systemID: String) -> Int {
        RomHasher.raConsoleID(for: systemID)
    }

    /// Imports local JSON cache files using a background ModelContext.
    /// Called by user-initiated flows (fetchAndCacheAllGames, matchAllCachedGames).
    func importLocalRAGameCache(onProgress: ((Int, Int) -> Void)? = nil) async {
        guard let container = SwiftDataContainer.shared.container else { return }
        let listFolder = listDataFolder

        guard FileManager.default.fileExists(atPath: listFolder.path) else {
            LoggerService.info(category: "RetroAchievements", "No local RA cache directory found.")
            return
        }

        // Determine user's console IDs on main context (lightweight read)
        let mainContext = container.mainContext
        let romDescriptor = FetchDescriptor<ROMEntry>()
        let userRoms = (try? mainContext.fetch(romDescriptor)) ?? []
        let userSystemIDs = Set(userRoms.compactMap { $0.systemID })
        let userRAConsoleIDs = Set(userSystemIDs.map { String(Self.systemIDToRAConsoleID($0)) })

        let jsonFiles: [URL]
        do {
            jsonFiles = try FileManager.default.contentsOfDirectory(at: listFolder, includingPropertiesForKeys: nil)
                .filter { url in
                    guard url.pathExtension == "json" else { return false }
                    let id = url.lastPathComponent.components(separatedBy: "_").first ?? ""
                    return userRAConsoleIDs.contains(id)
                }
        } catch {
            LoggerService.error(category: "RetroAchievements", "Error listing local cache: \(error.localizedDescription)")
            return
        }

        LoggerService.info(category: "RetroAchievements", "Found \(jsonFiles.count) relevant JSON cache files for your library.")

        let totalCount = jsonFiles.count
        for (index, fileURL) in jsonFiles.enumerated() {
            await importLocalJSONFile(fileURL)
            onProgress?(index + 1, totalCount)
        }
    }

    /// Imports a single console JSON file using a background ModelContext.
    func importLocalJSONFile(_ fileURL: URL) async {
        guard let container = SwiftDataContainer.shared.container else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let games = try? decoder.decode([GameJSON].self, from: data) else { return }

            // Run upserts on a background context
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let bgContext = ModelContext(container)
                    for game in games {
                        let gameID = game.id
                        let fetchDescriptor = FetchDescriptor<RAGameCacheEntry>(
                            predicate: #Predicate<RAGameCacheEntry> { $0.id == gameID }
                        )

                        if let existing = try? bgContext.fetch(fetchDescriptor).first {
                            existing.hashes = game.hashes
                            existing.title = game.title
                            existing.consoleID = game.consoleID
                            existing.consoleName = game.consoleName
                        } else {
                            let entry = RAGameCacheEntry(
                                id: game.id,
                                title: game.title,
                                consoleID: game.consoleID,
                                consoleName: game.consoleName,
                                hashes: game.hashes
                            )
                            bgContext.insert(entry)
                        }
                    }
                    try? bgContext.save()
                    continuation.resume()
                }
            }

            container.mainContext.processPendingChanges()
            LoggerService.info(category: "RetroAchievements", "Imported \(games.count) games from \(fileURL.lastPathComponent)")
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to import \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Performs a local search in the RAGameCacheEntry database for a name match.
    func identifyGameByName(title: String, consoleID: Int) async -> Int? {
        guard let context = modelContext else { return nil }
        
        // 1. Clean the title: remove extension, replace underscores, remove common tags
        var cleanedTitle = title
        if let lastDotIndex = cleanedTitle.lastIndex(of: ".") {
            cleanedTitle = String(cleanedTitle[..<lastDotIndex])
        }
        cleanedTitle = cleanedTitle.replacingOccurrences(of: "_", with: " ")
        
        // Remove common tags like (World), [!], etc.
        let tagRegex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: .caseInsensitive)
        if let regex = tagRegex {
            cleanedTitle = regex.stringByReplacingMatches(in: cleanedTitle, options: [], range: NSRange(location: 0, length: cleanedTitle.utf16.count), withTemplate: "")
        }
        
        cleanedTitle = cleanedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        LoggerService.info(category: "RetroAchievements", "Searching RA cache for cleaned title: '\(cleanedTitle)' (original: '\(title)')")
        
        // 2. Use localizedStandardContains for resilient name matching
        let predicate = #Predicate<RAGameCacheEntry> {
            $0.title.localizedStandardContains(cleanedTitle) && $0.consoleID == consoleID
        }
        
        let descriptor = FetchDescriptor<RAGameCacheEntry>(predicate: predicate)
        
        do {
            let results = try context.fetch(descriptor)
            // Return the first match found in the local cache, ensuring it's a valid ID
            if let firstId = results.first?.id, firstId > 0 {
                return firstId
            }
            return nil
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to search local RA cache: \(error)")
            return nil
        }
    }
    
    /// Finds a game ID by hash searching across ALL consoles in the local cache.
    private func findGameIdByHashLocally(hash: String) async -> Int? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<RAGameCacheEntry>()
        let entries = (try? context.fetch(descriptor)) ?? []
        for entry in entries {
            if entry.hashes.contains(where: { $0.caseInsensitiveCompare(hash) == .orderedSame }) {
                return entry.id
            }
        }
        return nil
    }

    // Find game by hash - tries local cache first
    func findGameByHashLocally(consoleID: Int, hash: String, isUserInitiated: Bool = false) async -> (id: Int, title: String, hashes: [String])? {
        let lowerHash = hash.lowercased()
        LoggerService.info(category: "RetroAchievements", "Searching RA cache for hash: \(lowerHash) (ConsoleID: \(consoleID))")
        
        // First try local cache (full game list search)
        if let context = modelContext {
            // Fetch games for this console first. 
            // Filtering hashes in the predicate can crash with _NSCoreDataStringSearch 
            // when applied to array attributes in some SwiftData versions.
            let predicate = #Predicate<RAGameCacheEntry> {
                $0.consoleID == consoleID
            }
            let descriptor = FetchDescriptor<RAGameCacheEntry>(predicate: predicate)
            
            do {
                let gamesForConsole = try context.fetch(descriptor)
                if let result = gamesForConsole.first(where: { entry in
                    entry.hashes.contains(where: { $0.caseInsensitiveCompare(lowerHash) == .orderedSame })
                }) {
                    LoggerService.info(category: "RetroAchievements", "Local cache HIT for hash \(lowerHash): \(result.title) (ID: \(result.id))")
                    return (result.id, result.title, result.hashes)
                }
            } catch {
                LoggerService.error(category: "RetroAchievements", "Failed to fetch from local cache: \(error.localizedDescription)")
            }
        }
        
        LoggerService.info(category: "RetroAchievements", "Local cache MISS for hash \(lowerHash).")
        
        LoggerService.info(category: "RetroAchievements", "Hash \(lowerHash) not found in any local cache, will need API resolution.")
        return nil
    }
    
    // Find all games by name - tries local cache first, then falls back to API.
    // Uses ROMIdentifierService-style normalization (article variants, tag stripping,
    // roman/arabic variants) so "Addams Family, The" matches "The Addams Family".
    func findAllRAGamesByName(title: String, consoleID: Int) async -> [(id: Int, title: String, hashes: [String])] {
        let queryKeys = Self.buildTitleSearchKeys(for: title)
        guard !queryKeys.isEmpty else { return [] }

        // First try local cache
        if let context = modelContext {
            let predicate = #Predicate<RAGameCacheEntry> {
                $0.consoleID == consoleID
            }
            let descriptor = FetchDescriptor<RAGameCacheEntry>(predicate: predicate)

            if let results = try? context.fetch(descriptor) {
                let matches = results.compactMap { entry -> (Int, String, [String])? in
                    Self.matchesTitleSearchKeys(queryKeys: queryKeys, candidate: entry.title) ?
                    (entry.id, entry.title, entry.hashes) : nil
                }
                if !matches.isEmpty { return matches }
            }
        }

        // Fall back to API
        return await searchGamesByNameViaAPI(title: title, consoleID: consoleID, queryKeys: queryKeys)
    }

    // Build a set of normalized search keys from a ROM title.
    // Uses ROMIdentifierService's normalization helpers for robust matching.
    static func buildTitleSearchKeys(for title: String) -> Set<String> {
        var keys = Set<String>()

        // Strip filename tags and parens (e.g. "Addams Family, The (USA).nes" -> "Addams Family, The")
        let stem = LibretroThumbnailResolver.stripRomFilenameTags(title)
        let stripped = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(stem)

        // 1. Standard normalized form (lowercase, paren-stripped, whitespace-collapsed)
        keys.insert(ROMIdentifierService.normalizedComparableTitle(stripped))

        // 2. Aggressive normalized form (strips all punctuation, lowercased)
        let aggressive = ROMIdentifierService.aggressivelyNormalizedTitle(stem)
        if !aggressive.isEmpty { keys.insert(aggressive) }

        // 3. Article variants ("The Addams Family" <-> "Addams Family, The")
        for variant in ROMIdentifierService.articleVariants(of: stripped) {
            keys.insert(ROMIdentifierService.normalizedComparableTitle(variant))
            let aggr = ROMIdentifierService.aggressivelyNormalizedTitle(variant)
            if !aggr.isEmpty { keys.insert(aggr) }
        }

        // 4. Roman/Arabic number variants ("Final Fantasy III" <-> "Final Fantasy 3")
        for base in Array(keys) {
            for variant in ROMIdentifierService.romanNumeralVariants(of: base) {
                keys.insert(variant)
            }
        }

        // Drop any blanks or overly-broad keys
        return keys.filter { $0.count >= 2 }
    }

    // Returns true if the candidate RA title matches any of the search keys.
    static func matchesTitleSearchKeys(queryKeys: Set<String>, candidate: String) -> Bool {
        let stripped = LibretroThumbnailResolver.stripParenthesesForFuzzyMatch(candidate)
        let normalized = ROMIdentifierService.normalizedComparableTitle(stripped)
        if queryKeys.contains(normalized) { return true }

        let aggressive = ROMIdentifierService.aggressivelyNormalizedTitle(candidate)
        if !aggressive.isEmpty && queryKeys.contains(aggressive) { return true }

        // Article variants of the candidate
        for variant in ROMIdentifierService.articleVariants(of: stripped) {
            if queryKeys.contains(ROMIdentifierService.normalizedComparableTitle(variant)) { return true }
            let aggr = ROMIdentifierService.aggressivelyNormalizedTitle(variant)
            if !aggr.isEmpty && queryKeys.contains(aggr) { return true }
        }

        return false
    }

    // Search games by name via RA API
    private func searchGamesByNameViaAPI(title: String, consoleID: Int, queryKeys: Set<String>) async -> [(id: Int, title: String, hashes: [String])] {
        guard let username = username, !webApiKey.isEmpty else { return [] }

        // Use the generic game list endpoint filtered by console
        let url = URL(string: "\(apiBaseURL)/API_GetGameList.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey),
            URLQueryItem(name: "i", value: String(consoleID)),
            URLQueryItem(name: "f", value: "1")
        ]

        guard let (data, _) = try? await URLSession.shared.data(from: components.url!) else { return [] }

        // Parse the list and filter by title using robust normalization
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return json.compactMap { game in
                guard let gameTitle = game["Title"] as? String,
                      let idStr = game["ID"] as? String,
                      let id = Int(idStr),
                      Self.matchesTitleSearchKeys(queryKeys: queryKeys, candidate: gameTitle) else { return nil }
                let hashes = game["Hashes"] as? [String] ?? []
                return (id, gameTitle, hashes)
            }
        }

        return []
    }

    /// Matches all games in the library using the local RA cache.
    /// - Parameter roms: The authoritative set of games to match (the in-memory library the user sees).
    /// - Parameter onProgress: Optional closure invoked after each ROM with the running matched count and total.
    func matchAllCachedGames(
        roms: [ROM],
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> (matched: Int, total: Int) {
        var matchedCount = 0
        let coordinator = RAGameCacheCoordinator.shared

        // Publish state BEFORE the long import/matching work so SwiftUI gets to
        // render the progress bar with the correct total immediately. Without
        // this reordering the bar either didn't appear or showed frozen,
        // because importLocalRAGameCache() then the matching loop hogged the
        // MainActor for seconds with no SwiftUI render frame in between.
        isMatchingAll = true
        matchedAllCount = 0
        matchedAllTotal = roms.count
        await Task.yield()

        // Cache-import phase. Drive the dedicated published state so the bar
        // shows "Importing game cache (step/total)" instead of being stuck on
        // "Matched 0 of N" for ~50s while JSON files are parsed.
        isImportingRACache = true
        importRACacheStep = 0
        importRACacheTotal = 0
        await Task.yield()
        await importLocalRAGameCache { step, total in
            self.importRACacheStep = step
            self.importRACacheTotal = total
        }
        isImportingRACache = false
        await Task.yield()

        let totalRoms = roms.count

        for (index, rom) in roms.enumerated() {
            let step = index + 1
            coordinator.startHashing(romName: rom.name, step: step, total: totalRoms)

            await syncROMWithRA(rom: rom)

            // Check if it was matched
            if let context = modelContext {
                let descriptor = FetchDescriptor<ROMEntry>(predicate: #Predicate { $0.id == rom.id })
                if let entry = try? context.fetch(descriptor).first, entry.raMatchStatus == "matched" {
                    matchedCount += 1
                }
            }
            matchedAllCount = matchedCount
            onProgress?(matchedCount, totalRoms)
            coordinator.updateHashingProgress(Double(step) / Double(totalRoms), romName: rom.name, step: step, total: totalRoms)
            // Let SwiftUI repaint the running counter. The hashing happens off
            // MainActor, but the SwiftData lookup + the progress closure above
            // are synchronous; yielding here guarantees a render frame per ROM
            // so the bar never freezes between iterations.
            await Task.yield()
        }

        isMatchingAll = false
        coordinator.finish()
        return (matchedCount, totalRoms)
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

        // If already matched and valid, we can skip unless it's a placeholder 0
        if let currentId = romEntry.raGameId, currentId > 0, romEntry.raMatchStatus == "matched" {
            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "\(rom.name) is already identified as ID \(currentId), skipping sync.")
            #endif
            return
        }

        // 1. Attempt identification via HASH FIRST (most reliable)
        let raConsoleID = mapSystemIDToRAConsoleID(systemID)
        let isGBFamily = systemID == "gb" || systemID == "gbc"
        let altConsoleID: Int? = isGBFamily ? (raConsoleID == 4 ? 6 : 4) : nil
        var matchedOnAltConsole = false

        // hashing reads file bytes + calls rcheevos C; for disc images this can
        // take seconds. Run off MainActor so the UI stays responsive and the
        // "Matched X of Y" line keeps updating per ROM.
        let romHash: String?
        if let precomputed = rom.md5 {
            romHash = precomputed
        } else {
            let path = rom.path.path
            romHash = await Task.detached(priority: .userInitiated) {
                RomHasher.hashRom(at: path, systemID: systemID)
            }.value
        }
        
        LoggerService.info(category: "RetroAchievements", "Syncing '\(rom.name)' - Generated Hash: \(romHash ?? "NONE") (RA ConsoleID: \(raConsoleID))")
        
        if let romHash = romHash {
            // Check local cache (including the newly imported JSON data)
            if let result = await findGameByHashLocally(consoleID: raConsoleID, hash: romHash) {
                LoggerService.info(category: "RetroAchievements", "Hash MATCH found for \(rom.name): \(result.title) (ID: \(result.id))")
                romEntry.raGameId = result.id
                romEntry.raMatchStatus = "matched"
                
                // If we also identified it as ID 0 previously, clear it
                if romEntry.raGameId == 0 { romEntry.raGameId = result.id }
                
                try? context.save()
                return
            }
            // Try alternate console for GB/GBC duality
            if let altID = altConsoleID {
                if let result = await findGameByHashLocally(consoleID: altID, hash: romHash) {
                    LoggerService.info(category: "RetroAchievements", "Hash MATCH found on alternate console for \(rom.name): \(result.title) (ID: \(result.id))")
                    romEntry.raGameId = result.id
                    romEntry.raMatchStatus = "matched"
                    matchedOnAltConsole = true
                    try? context.save()
                    postGBGBCCrossMatchNotification(rom: rom, systemID: systemID, altConsoleID: altID)
                    return
                }
            }
        }

        // 2. Fallback to NAME-based identification
        // NOTE: raGameId is deliberately NOT set here. When the hash doesn't match,
        // setting raGameId to a name-match game causes wrong RA data to display
        // in views that check raGameId > 0. The status alone ("mismatch") is set
        // so the RA comparison sheet can still use name matching.
        if let raGameId = await identifyGameByName(title: rom.name, consoleID: raConsoleID) {
            romEntry.raMatchStatus = "mismatch"
            
            // 3. Verify the exact version using the ROM's hash via local cache
            if let romHash = romHash {
                if let result = await findGameByHashLocally(consoleID: raConsoleID, hash: romHash) {
                    if result.id == raGameId {
                        romEntry.raMatchStatus = "matched"
                    } else {
                        romEntry.raMatchStatus = "mismatch:\(romHash)"
                        romEntry.raGameId = result.id // Update to the correct ID if local hash points elsewhere
                    }
                } else if let altID = altConsoleID {
                    // Try alternate console for GB/GBC duality
                    if let result = await findGameByHashLocally(consoleID: altID, hash: romHash) {
                        if result.id == raGameId {
                            romEntry.raMatchStatus = "matched"
                            matchedOnAltConsole = true
                        } else {
                            romEntry.raMatchStatus = "mismatch:\(romHash)"
                            romEntry.raGameId = result.id
                            matchedOnAltConsole = true
                        }
                    }
                } else {
                    /*
                     IMPORTANT: Individual hash lookups via API_GetGameByHash.php are BANNED by RetroAchievements 
                     for library scanning. All identification MUST be done via the local JSON cache lists 
                     (API_GetGameList.php?h=1) to avoid server strain.
                     
                     if let raGameIDFromHash = try? await resolveHash(hash: romHash) {
                         if raGameIDFromHash == raGameId {
                             romEntry.raMatchStatus = "matched"
                         } else {
                             romEntry.raMatchStatus = "mismatch:\(romHash)"
                             romEntry.raGameId = raGameIDFromHash
                         }
                     }
                    */
                }
            }
        } else {
            // 4. Final attempt: Identify by hash only via local cache if not found earlier
            if let romHash = romHash {
                if let result = await findGameByHashLocally(consoleID: raConsoleID, hash: romHash) {
                    romEntry.raGameId = result.id
                    romEntry.raMatchStatus = "matched"
                } else if let altID = altConsoleID {
                    if let result = await findGameByHashLocally(consoleID: altID, hash: romHash) {
                        romEntry.raGameId = result.id
                        romEntry.raMatchStatus = "matched"
                        matchedOnAltConsole = true
                    } else {
                        romEntry.raMatchStatus = "not_supported"
                    }
                } else {
                    romEntry.raMatchStatus = "not_supported"
                }
            }
        }
        
        if matchedOnAltConsole {
            postGBGBCCrossMatchNotification(rom: rom, systemID: systemID, altConsoleID: altConsoleID ?? 0)
        }
        
        // Persist computed MD5 if we have it
        if let md5 = romHash, md5.count > 8 {
            romEntry.md5 = md5
        }
        
        // Persist changes to SwiftData
        try? context.save()
    }

    /// Helper to map Libretro/SystemDatabase IDs to RetroAchievements Console IDs
    func mapSystemIDToRAConsoleID(_ systemID: String) -> Int {
        Self.systemIDToRAConsoleID(systemID)
    }

    private func postGBGBCCrossMatchNotification(rom: ROM, systemID: String, altConsoleID: Int) {
        let sysName = systemID == "gb" ? "Game Boy" : "Game Boy Color"
        let altName = altConsoleID == 6 ? "Game Boy Color" : "Game Boy"
        NotificationHistoryManager.shared.post(
            icon: "trophy.fill",
            title: "\(rom.name) matched to \(altName)",
            subtitle: "Set as \(sysName) but matched to RA's \(altName)",
            autoDismissDelay: 8
        )
    }

    // Identify a game by its hash and fetch achievement data.
    func identifyGame(hash: String) async throws -> RAGameInfo? {
        guard isEnabled, isLoggedIn, !webApiKey.isEmpty else { return nil }
        guard let username = username else { return nil }
        
        // First, get game ID from hash using local cache (Remote resolveHash is BANNED)
        let gameID = await findGameIdByHashLocally(hash: hash)
        guard let gameID = gameID else {
            LoggerService.info(category: "RetroAchievements", "Game not recognized locally by RetroAchievements")
            return nil
        }
        
        // Fetch game info with achievements
        return try await fetchGameInfo(gameID: gameID, username: username)
    }
    
    // Resolve a ROM hash to a RetroAchievements game ID.
    /*
    /// BANNED: Individual hash lookups via API are prohibited by RetroAchievements for library scanning.
    /// Use findGameByHashLocally instead to query the local JSON cache.
    func resolveHash(hash: String, isUserInitiated: Bool = false) async throws -> Int? {
        guard let username = username else { return nil }
        let lowerHash = hash.lowercased()
        
        // 1. Try local cache first
        if let cached = await loadHashFromCache(hash: lowerHash) {
            if !shouldFetch(cachedAt: cached.cachedAt, isUserInitiated: isUserInitiated) {
                LoggerService.info(category: "RetroAchievements", "Using cached hash resolution for \(lowerHash): ID \(cached.gameId)")
                return cached.gameId
            }
        }
        
        LoggerService.info(category: "RetroAchievements", "Resolving hash \(lowerHash) via RA API...")
        
        do {
            if let response = try await requestGameByHash(hash: lowerHash, username: username),
               let gameId = response.ID, gameId > 0 {
                LoggerService.info(category: "RetroAchievements", "API Resolved hash \(lowerHash) -> ID \(gameId) ('\(response.Title ?? "Unknown")')")
                await saveHashToCache(hash: lowerHash, gameId: gameId)
                return gameId
            } else {
                LoggerService.info(category: "RetroAchievements", "API could not resolve hash \(lowerHash) (Game not found or error).")
            }
        } catch {
            LoggerService.error(category: "RetroAchievements", "API Request failed for hash \(lowerHash): \(error.localizedDescription)")
        }
        
        return nil
    }
    */
    
    @MainActor
    private func loadHashFromCache(hash: String) async -> (gameId: Int, cachedAt: Date)? {
        guard let context = modelContext else { return nil }
        let predicate = #Predicate<RAHashCache> { $0.hash == hash }
        let descriptor = FetchDescriptor<RAHashCache>(predicate: predicate)
        guard let cache = try? context.fetch(descriptor).first else { return nil }
        return (cache.gameId, cache.cachedAt)
    }
    
    @MainActor
    private func saveHashToCache(hash: String, gameId: Int) async {
        guard let context = modelContext else { return }
        let predicate = #Predicate<RAHashCache> { $0.hash == hash }
        let descriptor = FetchDescriptor<RAHashCache>(predicate: predicate)
        
        if let existing = try? context.fetch(descriptor).first {
            existing.gameId = gameId
            existing.cachedAt = Date()
        } else {
            let newCache = RAHashCache(hash: hash, gameId: gameId)
            context.insert(newCache)
        }
        try? context.save()
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
            let idVal = json["ID"] ?? json["GameID"]
            guard let title = json["Title"] as? String else {
                // Check for error
                if let error = json["Error"] as? String {
                    LoggerService.info(category: "RetroAchievements", "Hash resolution error: \(error)")
                }
                return nil
            }
            
            let gameId: Int
            if let i = idVal as? Int { gameId = i }
            else if let s = idVal as? String, let i = Int(s) { gameId = i }
            else { return nil }
            
            let hashes = json["Hashes"] as? [String] ?? []
            
            LoggerService.info(category: "RetroAchievements", "Resolved hash to game: \(title) (ID: \(gameId))")
            return (id: gameId, title: title, hashes: hashes)
        }
        
        return nil
    }

    // Fetch game ID from a ROM hash.
    private func requestGameByHash(hash: String, username: String) async throws -> RAHashResponse? {
        let url = URL(string: "\(apiBaseURL)/API_GetGameByHash.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #if LOG_DEBUG
        LoggerService.debug(category: "RetroAchievements", "Requesting Game, hash \(hash), user: \(username)")
        #endif

        components.queryItems = [
            URLQueryItem(name: "h", value: hash),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey)
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        #if LOG_DEBUG
        LoggerService.debug(category: "RetroAchievements", "Requesting Game, url: \(components.url?.absoluteString ?? "unknown")")
        #endif
        // Check for error in JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errorMsg = json?["Error"] as? String {
            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "Hash resolution error: \(errorMsg)")
            #endif
            return nil
        }
        
        return try JSONDecoder().decode(RAHashResponse.self, from: data)
    }
    
    // Fetch detailed game info including achievements.
    // - isUserInitiated: loosens the cache TTL (1h instead of 24h).
    // - force: skips the cache entirely and always hits the network.
    func fetchGameInfo(gameID: Int, username: String, isUserInitiated: Bool = false, force: Bool = false) async throws -> RAGameInfo {
        // 1. Try to load from cache first (skip if forced)
        if !force, let cached = await loadGameInfoFromCache(gameID: gameID, username: username) {
            if !shouldFetch(cachedAt: cached.cachedAt, isUserInitiated: isUserInitiated) {
 LoggerService.info(category: "RetroAchievements", "Using cached achievement info for game \(gameID) (cached at \(cached.cachedAt))")

                var result = cached.gameInfo
                if let parentID = result.parentGameID {
                    let parentInfo = try? await fetchGameInfo(gameID: parentID, username: username, isUserInitiated: false)
                    if let parentInfo = parentInfo {
                        let parentAchs = parentInfo.achievements.filter { $0.category == .core }
                        let existingIDs = Set(result.achievements.map(\.id))
                        let newAchs = parentAchs.filter { !existingIDs.contains($0.id) }
                        result.achievements.append(contentsOf: newAchs)
                    }
                }

                return result
            }
            LoggerService.info(category: "RetroAchievements", "Cached achievement info for game \(gameID) is stale or refresh requested, re-fetching...")
        }

        // 2. Try network fetch, fall back to cache on failure
        do {
            let (response, rawData) = try await requestGameInfo(gameID: String(gameID), username: username)
        guard let response = response else {
            throw RAError.gameNotFound
        }

        if let data = rawData {
            let fileURL = gameDataFolder.appendingPathComponent("\(gameID).json")
            try? data.write(to: fileURL)
            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "Archived raw game info to \(fileURL.path)")
            #endif
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
                    isUnlocked: achResponse.unlockedDate != nil,
                    unlockDate: achResponse.unlockedDate.flatMap { date in
                        DateFormatter.raDateFormatter.date(from: date)
                    },
                    isHardcore: achResponse.unlockedDateHardcore != nil,
                    category: achResponse.resolvedCategory,
                    trigger: achResponse.MemAddr
                )
                achievements.append(achievement)
 }
 }

        let parentGameID = response.ParentGameID

        var gameInfo = RAGameInfo(
            id: response.ID ?? 0,
            title: response.Title ?? "",
            consoleName: response.ConsoleName ?? "",
            consoleID: response.ConsoleID ?? 0,
            achievements: achievements,
            totalPoints: response.Achievements?.values.reduce(0) { $0 + $1.Points } ?? 0,
            parentGameID: parentGameID
        )

        if let parentID = parentGameID, parentID > 0 {
            let parentInfo = try? await fetchGameInfo(gameID: parentID, username: username, isUserInitiated: false)
            if let parentInfo = parentInfo {
                let parentAchs = parentInfo.achievements.filter { $0.category == .core }
                let existingIDs = Set(gameInfo.achievements.map(\.id))
                let newAchs = parentAchs.filter { !existingIDs.contains($0.id) }
                gameInfo.achievements.append(contentsOf: newAchs)
                LoggerService.info(category: "RetroAchievements", "Merged \(newAchs.count) core achievements from parent game \(parentID) into subset \(gameID)")
            }
        }

            await saveGameInfoToCache(gameInfo: gameInfo, username: username)

            return gameInfo
        } catch {
            LoggerService.info(category: "RetroAchievements", "Network fetch failed for game \(gameID): \(error). Trying cache fallback...")
            if let cached = await loadGameInfoFromCache(gameID: gameID, username: username) {
 LoggerService.info(category: "RetroAchievements", "Using stale cache for game \(gameID) after network failure")
 return cached.gameInfo
            }
            if let diskAchievements = loadCachedAchievements(gameID: gameID, username: username) {
 LoggerService.info(category: "RetroAchievements", "Using disk cache for game \(gameID) after network failure")
                let parentID = parentGameIDForCache(gameID: gameID)
                return RAGameInfo(
                    id: gameID,
                    title: "",
                    consoleName: "",
                    consoleID: 0,
                    achievements: diskAchievements,
                    totalPoints: diskAchievements.reduce(0) { $0 + $1.points },
                    parentGameID: parentID
                )
            }
            throw error
        }
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
                category: AchievementCategory(rawValue: entry.category) ?? .core,
                trigger: entry.trigger
            )
        }
        
        let gameInfo = RAGameInfo(
            id: gameCache.gameId,
            title: gameCache.title,
            consoleName: gameCache.consoleName,
            consoleID: gameCache.consoleID,
            achievements: achievements,
            totalPoints: gameCache.totalPoints,
            parentGameID: gameCache.parentGameID
        )

        return (gameInfo, gameCache.cachedAt)
    }
    
func parentGameIDForCache(gameID: Int) -> Int? {
    let fileURL = gameDataFolder.appendingPathComponent("\(gameID).json")
    guard let data = try? Data(contentsOf: fileURL),
          let response = try? JSONDecoder().decode(RAGameResponse.self, from: data),
          let parentID = response.ParentGameID, parentID > 0 else { return nil }
    return parentID
}

nonisolated static func cachedAchievementProgress(for raGameId: Int) -> (earned: Int, total: Int)? {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let fileURL = appSupport
        .appendingPathComponent("TruchiEmu/RetroAchievements/Games", isDirectory: true)
        .appendingPathComponent("\(raGameId).json")
    guard let data = try? Data(contentsOf: fileURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let total = json["NumAchievements"] as? Int ?? 0
    let earned = json["NumAwardedToUser"] as? Int ?? 0
    guard total > 0 else { return nil }
    return (earned, total)
}

@MainActor
func loadCachedAchievements(gameID: Int, username: String) -> [Achievement]? {
        let fileURL = gameDataFolder.appendingPathComponent("\(gameID).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let response = try? JSONDecoder().decode(RAGameResponse.self, from: data)
        guard let achDict = response?.Achievements, !achDict.isEmpty else { return nil }

        let patchTriggers = loadPatchDataFromDisk(gameID: gameID)
        var achievements = achDict.values.map { ach -> Achievement in
            let patchDef = patchTriggers?.achievements.first(where: { $0.id == ach.ID })?.definition
            let hasPatch = (patchDef?.isEmpty == false)
            let trigger: String? = hasPatch ? patchDef : ach.MemAddr
            let source = hasPatch ? "patch" : "memaddr"
            let unlocked = (ach.unlockedDate != nil)

            let trigPreview = (trigger ?? "<nil>").prefix(80)
            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "RA ach id=\(ach.ID) source=\(source) unlocked=\(unlocked) trigger=\(trigPreview)")
            #endif

            return Achievement(
                id: ach.ID,
                title: ach.Title,
                description: ach.Description,
                points: ach.Points,
                badgeName: ach.BadgeName,
                isUnlocked: unlocked,
                unlockDate: ach.unlockedDate.flatMap { DateFormatter.raDateFormatter.date(from: $0) },
                isHardcore: ach.unlockedDateHardcore != nil,
                category: ach.resolvedCategory,
                trigger: trigger
            )
        }

    if let parentID = response?.ParentGameID, parentID > 0,
        var parentAchs = loadCachedAchievements(gameID: parentID, username: username) {
        let parentPatchTriggers = loadPatchDataFromDisk(gameID: parentID)
        if let parentPatch = parentPatchTriggers {
            for i in parentAchs.indices {
                if let patchDef = parentPatch.achievements.first(where: { $0.id == parentAchs[i].id })?.definition,
                   !patchDef.isEmpty {
                    parentAchs[i].trigger = patchDef
                }
            }
        }
        let parentCoreAchs = parentAchs.filter { $0.category == .core }
        let existingIDs = Set(achievements.map(\.id))
        let newAchs = parentCoreAchs.filter { !existingIDs.contains($0.id) }
        achievements.append(contentsOf: newAchs)
    }

        return achievements
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
        existingGame.parentGameID = gameInfo.parentGameID
        existingGame.cachedAt = Date()
    } else {
        let newGame = RAGameAchievementCache(
            gameId: gameInfo.id,
            achievementCount: gameInfo.achievements.count,
            title: gameInfo.title,
            consoleName: gameInfo.consoleName,
            consoleID: gameInfo.consoleID,
            totalPoints: gameInfo.totalPoints,
            parentGameID: gameInfo.parentGameID,
            cachedAt: Date()
        )
            context.insert(newGame)
        }
        
        // 2. Update/Create Achievement Entries
        for ach in gameInfo.achievements {
            let achID = ach.id
            let achPredicate = #Predicate<RAAchievementCacheEntry> { $0.achievementId == achID }
            let achDescriptor = FetchDescriptor<RAAchievementCacheEntry>(predicate: achPredicate)

            if let existingAch = try? context.fetch(achDescriptor).first {
                existingAch.title = ach.title
                existingAch.achDescription = ach.description
                existingAch.points = ach.points
                existingAch.badgeName = ach.badgeName
                existingAch.category = ach.category.rawValue
                if ach.unlockDate != nil {
                    existingAch.dateAwarded = ach.unlockDate
                    existingAch.dateAwardedHardcore = ach.isHardcore ? ach.unlockDate : nil
                }
                existingAch.username = username
                existingAch.trigger = ach.trigger
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
                    trigger: ach.trigger,
                    cachedAt: Date()
                )
            context.insert(newAch)
            }
        }

        do {
            try context.save()
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to save achievement cache: \(error)")
        }
    }
    
    // MARK: - Achievement Unlocking

    func unlockAchievement(id: Int, hardcore: Bool) async {
        guard isLoggedIn, let username = username, let token = loginToken else {
            LoggerService.error(category: "RetroAchievements", "Unlock skipped — not logged in or missing login token")
            return
        }

        let wasAlreadyUnlocked: Bool
        if let idx = currentGame?.achievements.firstIndex(where: { $0.id == id }) {
            wasAlreadyUnlocked = currentGame!.achievements[idx].isUnlocked
        } else {
            wasAlreadyUnlocked = false
        }

        pendingUnlocks.append((id: id, hardcore: hardcore))

        guard !isProcessingUnlocks else { return }
        isProcessingUnlocks = true

        while !pendingUnlocks.isEmpty {
            let batch = pendingUnlocks
            pendingUnlocks.removeAll()

            for unlock in batch {
                let minInterval: TimeInterval = 1.5
                let elapsed = Date().timeIntervalSince(lastUnlockTime)
                if elapsed < minInterval {
                    try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000))
                }
                lastUnlockTime = Date()

                await performAwardRequest(id: unlock.id, hardcore: unlock.hardcore, username: username, token: token, wasLocallyUnlocked: !wasAlreadyUnlocked)
            }
        }

        isProcessingUnlocks = false
    }

    private func performAwardRequest(id: Int, hardcore: Bool, username: String, token: String, wasLocallyUnlocked: Bool) async {
        var cUrl: UnsafeMutablePointer<CChar>?
        var cPostData: UnsafeMutablePointer<CChar>?
        var cContentType: UnsafeMutablePointer<CChar>?

        let initResult = username.withCString { usernamePtr in
            token.withCString { tokenPtr in
                rcheevos_api_init_award_achievement(usernamePtr, tokenPtr, UInt32(id), hardcore ? 1 : 0, &cUrl, &cPostData, &cContentType)
            }
        }

        guard initResult == 0, let urlStr = cUrl else {
            LoggerService.error(category: "RetroAchievements", "Failed to build award request for achievement \(id): \(initResult)")
            rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
            return
        }

        let requestURL = String(cString: urlStr)
        let postDataStr = cPostData.map { String(cString: $0) }
        let contentTypeStr = cContentType.map { String(cString: $0) }
        rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)

        guard let url = URL(string: requestURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("rcheevos/12.3.0 TruchiEmu/1.0.0", forHTTPHeaderField: "User-Agent")
        if let postData = postDataStr, !postData.isEmpty {
            var modifiedPost = postData
            if !modifiedPost.contains("l=") {
                modifiedPost += "&l=TruchiEmu/1.0.0"
            }
            request.httpMethod = "POST"
            request.httpBody = modifiedPost.data(using: .utf8)
            if let ct = contentTypeStr {
                request.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            LoggerService.error(category: "RetroAchievements", "Award achievement \(id) network error: \(error.localizedDescription)")
            return
        }

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? -1
        let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"

        var awardResponse = rcheevos_api_process_award_response(responseBody, data.count, Int32(statusCode))
        defer { rcheevos_api_destroy_award_response(&awardResponse) }

        if awardResponse.succeeded != 0 {
            if wasLocallyUnlocked {
                LoggerService.info(category: "RetroAchievements", "Achievement \(id) unlocked! Score: \(awardResponse.new_player_score), Remaining: \(awardResponse.achievements_remaining)")
            } else {
                LoggerService.info(category: "RetroAchievements", "Achievement \(id) already unlocked on server (re-award)")
            }
		await MainActor.run {
			if let index = self.currentGame?.achievements.firstIndex(where: { $0.id == id }) {
				self.currentGame?.achievements[index].isUnlocked = true
				self.currentGame?.achievements[index].isHardcore = hardcore
				self.currentGame?.achievements[index].unlockDate = Date()
			} else if var game = self.currentGame {
				let ach = Achievement(
					id: id, title: "Achievement \(id)", description: "",
					points: 0, badgeName: "", isUnlocked: true,
					unlockDate: Date(), isHardcore: hardcore,
					category: .core, trigger: nil
				)
				game.achievements.append(ach)
				self.currentGame = game
			}
			if wasLocallyUnlocked {
				let achievement = self.currentGame?.achievements.first(where: { $0.id == id })
				if let achievement = achievement {
					AchievementToastManager.shared.showAchievement(achievement)

					let gameTitle = self.currentGame?.title ?? ""
NotificationHistoryManager.shared.post(
						icon: "trophy.fill",
						title: achievement.title,
						subtitle: "\(achievement.points) points — \(gameTitle)",
						autoDismissDelay: 5
					)
				}
			}
		}

		if wasLocallyUnlocked {
			let badgeName = await MainActor.run { self.currentGame?.achievements.first(where: { $0.id == id })?.badgeName ?? "" }
			let gameID = await MainActor.run { self.currentGame?.id ?? 0 }
			let gameTitle = await MainActor.run { self.currentGame?.title ?? "" }
			let systemName = await MainActor.run { self.currentGame?.consoleName ?? "" }
			let achievementTitle = await MainActor.run { self.currentGame?.achievements.first(where: { $0.id == id })?.title ?? "" }
			let achievementPoints = await MainActor.run { self.currentGame?.achievements.first(where: { $0.id == id })?.points ?? 0 }

			if !badgeName.isEmpty && RABadgeCacheService.shared.localURL(for: badgeName) == nil {
				await RABadgeCacheService.shared.ensureBadgeDownloaded(badgeName: badgeName)
			}

			let unlockedLabel = LocalizationManager.shared.localized("achievement.unlockedLabel")
			let pointsLabel = LocalizationManager.shared.localized("achievement.pointsLabel")
			let body: String
			if !systemName.isEmpty {
				body = "\(achievementTitle) — \(achievementPoints) \(pointsLabel)\n\(gameTitle) (\(systemName))"
			} else {
				body = "\(achievementTitle) — \(achievementPoints) \(pointsLabel)\n\(gameTitle)"
			}

			let userInfo: [String: Any] = ["raGameId": gameID]

			await MainActor.run {
				if let localURL = RABadgeCacheService.shared.localURL(for: badgeName),
				   let image = NSImage(contentsOf: localURL) {
					NotificationService.shared.sendNotification(
						title: unlockedLabel,
						body: body,
						image: image,
						userInfo: userInfo
					)
				} else {
					NotificationService.shared.sendNotification(
						title: unlockedLabel,
						body: body,
						userInfo: userInfo
					)
				}
			}
		}
            persistUnlockToCache(achievementId: id, hardcore: hardcore)
        } else {
            let errMsg = awardResponse.error_message.map { String(cString: $0) } ?? "unknown"
            LoggerService.error(category: "RetroAchievements", "Award achievement \(id) failed: HTTP \(statusCode), body: \(responseBody), error: \(errMsg)")

            if errMsg.contains("expired_token") || errMsg.contains("invalid_credentials") {
                let reason = errMsg.contains("expired_token") ? "expired_token" : "invalid_credentials"
                loginToken = nil
                AppSettings.remove("ra_login_token")
                LoggerService.error(category: "RetroAchievements", "Login token expired, cleared. Re-login required.")
                surfaceReloginNeeded(reason: reason)
            }
        }
    }

    private func persistUnlockToCache(achievementId: Int, hardcore: Bool) {
        guard let game = currentGame else { return }

        let candidateIDs: [Int] = {
            if let parentID = game.parentGameID, parentID > 0 {
                return [game.id, parentID]
            }
            return [game.id]
        }()

        let now = DateFormatter.raDateFormatter.string(from: Date())

        for gameID in candidateIDs {
            let fileURL = gameDataFolder.appendingPathComponent("\(gameID).json")
            guard let data = try? Data(contentsOf: fileURL),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var achievements = json["Achievements"] as? [String: Any] else { continue }

            for (key, value) in achievements {
                guard var ach = value as? [String: Any], ach["ID"] as? Int == achievementId else { continue }
                ach["DateAwarded"] = now
                ach["DateEarned"] = now
                if hardcore {
                    ach["DateAwardedHardcore"] = now
                    ach["DateEarnedHardcore"] = now
                }
                achievements[key] = ach
                break
            }

            json["Achievements"] = achievements
            guard let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { continue }
            try? updatedData.write(to: fileURL)
            break
        }

        updateSwiftDataCache(achievementId: achievementId, hardcore: hardcore)
    }

    private func updateSwiftDataCache(achievementId: Int, hardcore: Bool) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<RAAchievementCacheEntry> { $0.achievementId == achievementId }
        let descriptor = FetchDescriptor<RAAchievementCacheEntry>(predicate: predicate)
        guard let entry = try? context.fetch(descriptor).first else { return }
        entry.dateAwarded = Date()
        if hardcore { entry.dateAwardedHardcore = Date() }
        try? context.save()
    }

@MainActor
func refreshGameCacheAfterGameStop() {
    guard let game = currentGame,
          let username = username,
          !webApiKey.isEmpty else { return }
    let gameID = game.id
    Task {
 do {
 let refreshedInfo = try await fetchGameInfo(gameID: gameID, username: username, isUserInitiated: true)
 LoggerService.info(category: "RetroAchievements", "Post-game cache refresh completed for game \(gameID)")
 if !refreshedInfo.achievements.isEmpty {
 RABadgeCacheService.shared.prefetchBadges(for: refreshedInfo.achievements)
 }
 if let parentID = game.parentGameID, parentID > 0 {
 let parentInfo = try await fetchGameInfo(gameID: parentID, username: username, isUserInitiated: true)
 LoggerService.info(category: "RetroAchievements", "Post-game cache refresh completed for parent game \(parentID)")
 if !parentInfo.achievements.isEmpty {
 RABadgeCacheService.shared.prefetchBadges(for: parentInfo.achievements)
 }
 }
        } catch {
            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "Post-game cache refresh failed: \(error.localizedDescription)")
            #endif
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
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard httpStatus == 200 else {
            throw RAError.serverError(httpStatus)
        }
        
        LoggerService.info(category: "RetroAchievements", "Leaderboard \(leaderboardID) score submitted: \(score)")
    }
    
    // MARK: - Rich Presence
    
    // Update rich presence message.
    func updateRichPresence(gameID: Int, message: String, rom: ROM? = nil) async {
        guard isLoggedIn, let username = username else { return }
        guard let token = await fetchLoginToken() else {
            LoggerService.error(category: "RetroAchievements", "Rich presence ping skipped — no login token")
            return
        }

        var cUrl: UnsafeMutablePointer<CChar>?
        var cPostData: UnsafeMutablePointer<CChar>?
        var cContentType: UnsafeMutablePointer<CChar>?

        let initResult = username.withCString { userPtr in
            token.withCString { tokenPtr in
                rcheevos_api_init_ping(
                    userPtr,
                    tokenPtr,
                    UInt32(gameID),
                    message,
                    rom?.md5,
                    HardcoreModeManager.shared.isHardcoreActive(for: rom) ? 1 : 0,
                    &cUrl, &cPostData, &cContentType
                )
            }
        }

        guard initResult == 0, let urlStr = cUrl else {
            rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
            LoggerService.error(category: "RetroAchievements", "rcheevos failed to build ping request: \(initResult)")
            return
        }

        let requestURL = String(cString: urlStr)
        let postDataStr = cPostData.map { String(cString: $0) }
        let contentTypeStr = cContentType.map { String(cString: $0) }
        rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
        cUrl = nil; cPostData = nil; cContentType = nil

        guard let url = URL(string: requestURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("rcheevos/12.3.0 TruchiEmu/1.0.0", forHTTPHeaderField: "User-Agent")
        if let postData = postDataStr, !postData.isEmpty {
            request.httpMethod = "POST"
            request.httpBody = postData.data(using: .utf8)
            if let ct = contentTypeStr {
                request.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            var pingResp = body.withCString { bodyPtr in
                rcheevos_api_process_ping_response(bodyPtr, data.count, Int32(status))
            }
            rcheevos_api_destroy_ping_response(&pingResp)
            if pingResp.succeeded != 1 {
                let err = pingResp.error_message.map { String(cString: $0) } ?? "(unknown)"
                LoggerService.error(category: "RetroAchievements", "Ping failed (HTTP \(status)): \(err)")
                return
            }
            await MainActor.run {
                self.richPresence = message
            }
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to update rich presence: \(error.localizedDescription)")
        }
    }

    func startSession(gameID: Int, rom: ROM? = nil) async {
        guard let result = await performStartSession(gameID: gameID, rom: rom) else { return }

        // Trust the server's Unlocks/HardcoreUnlocks arrays as the authoritative answer.
        // Reset local isUnlocked/isHardcore for ALL achievements, then mark only the ones
        // the server says are unlocked. This is critical when the user has reset their
        // achievements on the RA website — the local cache may still show old unlocks,
        // and the rcheevos runtime would otherwise filter out those triggers as "already
        // unlocked" and never activate them.
        await MainActor.run {
            guard let existing = self.currentGame else { return }
            var updated = existing
            for i in updated.achievements.indices {
                applyServerUnlocks(result: result, to: &updated.achievements[i])
            }
            self.currentGame = updated
        }
    }

    // Pre-launch reconciliation: asks the server for the user's true unlocks and applies
    // them to the supplied achievements array. This MUST run before rcheevos triggers are
    // activated — otherwise the runtime filters out "already unlocked" triggers (from
    // stale disk cache) and never re-activates them after a server-side reset.
    func reconcileAchievementsWithServer(gameID: Int, rom: ROM?, achievements: [Achievement]) async -> [Achievement] {
        guard let result = await performStartSession(gameID: gameID, rom: rom) else { return achievements }
        return achievements.map { ach in
            var copy = ach
            applyServerUnlocks(result: result, to: &copy)
            return copy
        }
    }

    // Apply server's unlocks to a single achievement in place. The server is authoritative:
    // if the server says an achievement IS unlocked, mark it unlocked. If the server says
    // it is NOT unlocked, clear any stale local unlock state so the runtime will activate it.
    private func applyServerUnlocks(result: StartSessionResult, to ach: inout Achievement) {
        let id = ach.id
        if result.serverHardcore.contains(id) {
            ach.isUnlocked = true
            ach.isHardcore = true
            ach.unlockDate = ach.unlockDate ?? Date()
        } else if result.serverUnlocked.contains(id) {
            ach.isUnlocked = true
            ach.isHardcore = false
            ach.unlockDate = ach.unlockDate ?? Date()
        } else {
            ach.isUnlocked = false
            ach.isHardcore = false
            ach.unlockDate = nil
        }
    }

    private struct StartSessionResult {
        let serverUnlocked: Set<Int>
        let serverHardcore: Set<Int>
        let succeeded: Bool
    }

    // Builds, sends, and parses a dorequest.php?r=startsession request. Returns the
    // server's authoritative unlocks + hardcore unlocks, or nil if the call failed entirely
    // (no token, network error, etc.).
    private func performStartSession(gameID: Int, rom: ROM?) async -> StartSessionResult? {
        guard isLoggedIn, let username = username else { return nil }
        guard let token = await fetchLoginToken() else {
            LoggerService.error(category: "RetroAchievements", "Start session skipped — no login token")
            return nil
        }

        var cUrl: UnsafeMutablePointer<CChar>?
        var cPostData: UnsafeMutablePointer<CChar>?
        var cContentType: UnsafeMutablePointer<CChar>?

        let initResult = username.withCString { userPtr in
            token.withCString { tokenPtr in
                rcheevos_api_init_start_session(
                    userPtr,
                    tokenPtr,
                    UInt32(gameID),
                    rom?.md5,
                    HardcoreModeManager.shared.isHardcoreActive(for: rom) ? 1 : 0,
                    &cUrl, &cPostData, &cContentType
                )
            }
        }

        guard initResult == 0, let urlStr = cUrl else {
            rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
            LoggerService.error(category: "RetroAchievements", "rcheevos failed to build start session request: \(initResult)")
            return nil
        }

        let requestURL = String(cString: urlStr)
        let postDataStr = cPostData.map { String(cString: $0) }
        let contentTypeStr = cContentType.map { String(cString: $0) }
        rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
        cUrl = nil; cPostData = nil; cContentType = nil

        guard let url = URL(string: requestURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("rcheevos/12.3.0 TruchiEmu/1.0.0", forHTTPHeaderField: "User-Agent")
        if let postData = postDataStr, !postData.isEmpty {
            request.httpMethod = "POST"
            request.httpBody = postData.data(using: .utf8)
            if let ct = contentTypeStr {
                request.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            var ssResp = body.withCString { bodyPtr in
                rcheevos_api_process_start_session_response(bodyPtr, data.count, Int32(status))
            }
            defer { rcheevos_api_destroy_start_session_response(&ssResp) }

            if ssResp.succeeded != 1 {
                let err = ssResp.error_message.map { String(cString: $0) } ?? "(unknown)"
                LoggerService.error(category: "RetroAchievements", "Start session failed (HTTP \(status)): \(err)")
                if err.contains("expired_token") || err.contains("invalid_credentials") {
                    let reason = err.contains("expired_token") ? "expired_token" : "invalid_credentials"
                    await MainActor.run {
                        self.lastKnownLoginToken = self.lastKnownLoginToken ?? token
                        self.loginToken = nil
                        AppSettings.remove("ra_login_token")
                    }
                    surfaceReloginNeeded(reason: reason)
                }
                return nil
            }
            LoggerService.info(category: "RetroAchievements", "Started session for game \(gameID) (\(ssResp.num_unlocks) prior unlocks, \(ssResp.num_hardcore_unlocks) hardcore)")

            let serverUnlocked = Set((0..<Int(ssResp.num_unlocks)).map { Int(ssResp.unlocks[$0]) })
            let serverHardcore = Set((0..<Int(ssResp.num_hardcore_unlocks)).map { Int(ssResp.hardcore_unlocks[$0]) })
            return StartSessionResult(serverUnlocked: serverUnlocked, serverHardcore: serverHardcore, succeeded: true)
        } catch {
            LoggerService.error(category: "RetroAchievements", "Failed to start session: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Patch Data (Unhashed Triggers)

    private static let patchDataFolder: URL = {
        let folder = baseFolder.appendingPathComponent("Patches", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private var patchDataFolder: URL { Self.patchDataFolder }

    struct PatchAchievement: Codable {
        let id: Int
        let definition: String
        let points: Int
        let category: Int
    }

    struct PatchData: Codable {
        let gameId: Int
        let achievements: [PatchAchievement]
        let richPresenceScript: String?
        let fetchedAt: Date
    }

    private func fetchLoginToken() async -> String? {
        if let existing = loginToken { return existing }

        // The login token was cleared (e.g. by an expired_token server response).
        // Attempt to refresh it via dorequest.php?r=login2 using the last known
        // token — RA's login2 endpoint reissues a fresh token if the provided one
        // is still server-side valid. Without this, the user would have to re-enter
        // their password every time the token expires.
        if isRefreshingToken { return nil }
        if isLoggedOutByTokenFailure { return nil }
        guard let cached = lastKnownLoginToken, let username, !username.isEmpty else {
            surfaceReloginNeeded(reason: "missing")
            return nil
        }
        return await refreshLoginToken(username: username, existingToken: cached)
    }

    // Called when we know the token cannot be refreshed (server returned
    // invalid_credentials or expired_token, or there is no stored token to try).
    // Marks the service as effectively logged out for dorequest calls and posts a
    // user-visible notification at most once per session.
    private func surfaceReloginNeeded(reason: String) {
        let prevLoggedOut = isLoggedOutByTokenFailure
        isLoggedOutByTokenFailure = true
        if hasSurfacedTokenReloginNeeded { return }
        hasSurfacedTokenReloginNeeded = true
        LoggerService.error(category: "RetroAchievements", "Re-login required (reason: \(reason)). Most Recently Played and achievement awards will not work until the user logs in again under Settings → RetroAchievements.")
        let loc = LocalizationManager.shared
        NotificationService.shared.sendNotification(
            title: loc.localized("retroAchievements.reloginNeededTitle"),
            body: loc.localized("retroAchievements.reloginNeededBody"),
            userInfo: ["raReloginNeeded": true]
        )
        _ = prevLoggedOut // suppress unused-warning noise if any
    }

    private func refreshLoginToken(username: String, existingToken: String) async -> String? {
        isRefreshingToken = true
        defer { isRefreshingToken = false }

        var cUrl: UnsafeMutablePointer<CChar>?
        var cPostData: UnsafeMutablePointer<CChar>?
        var cContentType: UnsafeMutablePointer<CChar>?

        let initResult = username.withCString { userPtr in
            existingToken.withCString { tokenPtr in
                rcheevos_api_init_login_with_token(userPtr, tokenPtr, &cUrl, &cPostData, &cContentType)
            }
        }

        guard initResult == 0, let urlStr = cUrl else {
            rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
            LoggerService.error(category: "RetroAchievements", "Token refresh: rcheevos failed to build login2 request: \(initResult)")
            return nil
        }

        let requestURL = String(cString: urlStr)
        let postDataStr = cPostData.map { String(cString: $0) }
        let contentTypeStr = cContentType.map { String(cString: $0) }
        rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
        cUrl = nil; cPostData = nil; cContentType = nil

        guard let url = URL(string: requestURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("rcheevos/12.3.0 TruchiEmu/1.0.0", forHTTPHeaderField: "User-Agent")
        if let postData = postDataStr, !postData.isEmpty {
            request.httpMethod = "POST"
            request.httpBody = postData.data(using: .utf8)
            if let ct = contentTypeStr {
                request.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            LoggerService.error(category: "RetroAchievements", "Token refresh network error: \(error.localizedDescription)")
            return nil
        }

        var cToken: UnsafeMutablePointer<CChar>?
        let jsonBody = String(data: data, encoding: .utf8) ?? ""
        let result = jsonBody.withCString { bodyPtr in
            rcheevos_api_process_login_response(bodyPtr, data.count, &cToken)
        }

        guard result == 0, let tokenPtr = cToken else {
            // rcheevos error codes (see rc_error.h):
            //   -34 RC_INVALID_CREDENTIALS — token was rejected as not-a-valid token
            //   -35 RC_EXPIRED_TOKEN       — token was rejected as expired, server refuses to refresh
            //   -32 RC_NO_RESPONSE         — network or empty body (retryable next call)
            //   -27 RC_API_FAILURE         — generic server error (retryable next call)
            let reason: String
            switch result {
            case -34: reason = "invalid_credentials"
            case -35: reason = "expired_token"
            case -32: reason = "no_response"
            case -27: reason = "api_failure"
            default:  reason = "rc=\(result)"
            }
            LoggerService.error(category: "RetroAchievements", "Token refresh failed (rc=\(result), reason=\(reason)) — re-login with password required")
            free(cToken)
            // Only surface the user notification on definitive failures. Transient
            // network/API issues will be retried on the next call automatically.
            if result == -34 || result == -35 {
                surfaceReloginNeeded(reason: reason)
            }
            return nil
        }

        let newToken = String(cString: tokenPtr)
        free(cToken)

        LoggerService.info(category: "RetroAchievements", "Login token refreshed successfully")
        await MainActor.run {
            self.loginToken = newToken
            self.lastKnownLoginToken = newToken
            AppSettings.set("ra_login_token", value: newToken)
        }
        return newToken
    }

    func fetchPatchData(gameID: Int) async -> [Int: String]? {
        guard isLoggedIn, let username = username else {
            LoggerService.info(category: "RetroAchievements", "Cannot fetch patch data: not logged in")
            return nil
        }

        guard let token = await fetchLoginToken() else {
            LoggerService.error(category: "RetroAchievements", "Cannot fetch patch data: no login token")
            return nil
        }

        if let existing = loadPatchDataFromDisk(gameID: gameID) {
            if let fetchedAt = existing.fetchedAt as Date?,
               Date().timeIntervalSince(fetchedAt) < 24 * 3600 {
                LoggerService.info(category: "RetroAchievements", "Using cached patch data for game \(gameID)")
                var result = [Int: String]()
                for ach in existing.achievements {
                    result[ach.id] = ach.definition
                }
                return result
            }
        }

        var cUrl: UnsafeMutablePointer<CChar>?
        var cPostData: UnsafeMutablePointer<CChar>?
        var cContentType: UnsafeMutablePointer<CChar>?

        let initResult = username.withCString { usernamePtr in
            token.withCString { tokenPtr in
                rcheevos_api_init_fetch_game_data(usernamePtr, tokenPtr, UInt32(gameID), &cUrl, &cPostData, &cContentType)
            }
        }

        guard initResult == 0, let urlStr = cUrl else {
            LoggerService.error(category: "RetroAchievements", "rcheevos failed to build patch request: \(initResult)")
            rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
            return nil
        }

        let requestURL = String(cString: urlStr)
        let postDataStr = cPostData.map { String(cString: $0) }
        let contentTypeStr = cContentType.map { String(cString: $0) }
        rcheevos_api_destroy_request_strings(cUrl, cPostData, cContentType)
        cUrl = nil; cPostData = nil; cContentType = nil

        guard let url = URL(string: requestURL) else {
            LoggerService.error(category: "RetroAchievements", "Invalid patch URL: \(requestURL)")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("rcheevos/12.3.0 TruchiEmu/1.0.0", forHTTPHeaderField: "User-Agent")
        if var postData = postDataStr, !postData.isEmpty {
            postData += "&l=TruchiEmu/1.0.0"
            request.httpMethod = "POST"
            request.httpBody = postData.data(using: .utf8)
            if let ct = contentTypeStr {
                request.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response): (Data, URLResponse?)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            LoggerService.error(category: "RetroAchievements", "Patch fetch network error: \(error.localizedDescription)")
            return nil
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            LoggerService.error(category: "RetroAchievements", "Patch fetch HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            return nil
        }

        let jsonBody = String(data: data, encoding: .utf8) ?? ""
        var patchResponse = jsonBody.withCString { bodyPtr in
            rcheevos_api_process_patch_response(bodyPtr, data.count)
        }

        guard patchResponse.succeeded != 0 else {
            let errMsg = patchResponse.error_message.map { String(cString: $0) } ?? "unknown"
            rcheevos_api_destroy_patch_response(&patchResponse)
            if errMsg.contains("expired_token") || errMsg.contains("invalid_credentials") {
                let reason = errMsg.contains("expired_token") ? "expired_token" : "invalid_credentials"
                loginToken = nil
                AppSettings.remove("ra_login_token")
                LoggerService.error(category: "RetroAchievements", "Login token expired or invalid, cleared. Re-login required.")
                surfaceReloginNeeded(reason: reason)
            }
            LoggerService.error(category: "RetroAchievements", "Patch response error: \(errMsg)")
            return nil
        }

        var triggers = [Int: String]()
        var patchAchievements = [PatchAchievement]()
        for i in 0..<patchResponse.num_achievements {
            let ach = patchResponse.achievements![Int(i)]
            if ach.id >= 101000000 { continue }
            let def = ach.definition.map { String(cString: $0) } ?? ""
            triggers[Int(ach.id)] = def
            patchAchievements.append(PatchAchievement(
                id: Int(ach.id),
                definition: def,
                points: Int(ach.points),
                category: Int(ach.category)
            ))
        }

        let richPresence = patchResponse.rich_presence_script.map { String(cString: $0) }
        rcheevos_api_destroy_patch_response(&patchResponse)

        let patchData = PatchData(
            gameId: gameID,
            achievements: patchAchievements,
            richPresenceScript: richPresence,
            fetchedAt: Date()
        )
        savePatchDataToDisk(patchData, gameID: gameID)

        LoggerService.info(category: "RetroAchievements", "Fetched patch data for game \(gameID): \(triggers.count) achievement triggers")
        return triggers
    }

    private func loadPatchDataFromDisk(gameID: Int) -> PatchData? {
        let fileURL = patchDataFolder.appendingPathComponent("\(gameID).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PatchData.self, from: data)
    }

    func loadRichPresenceScript(gameID: Int) -> String? {
        return loadPatchDataFromDisk(gameID: gameID)?.richPresenceScript
    }

    private func savePatchDataToDisk(_ patchData: PatchData, gameID: Int) {
        let fileURL = patchDataFolder.appendingPathComponent("\(gameID).json")
        guard let data = try? JSONEncoder().encode(patchData) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - API Request Helpers
    
    private struct RARAGameListResponse: Decodable, Sendable {
        @SafeInt var ID: Int
        let Title: String
        @SafeInt var ConsoleID: Int
        let ConsoleName: String
    }

    private struct RAConsoleResponse: Decodable {
        @SafeInt var ID: Int
        var Name: String
    }

    private struct GameJSON: Decodable {
        let id: Int
        let title: String
        let consoleID: Int
        let consoleName: String
        let hashes: [String]
        
        enum CodingKeys: String, CodingKey {
            case ID, Title, ConsoleID, ConsoleName, Hashes
            case id, title, consoleID, consoleName, hashes
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Decode ID (handles string/int and case variants)
            if let val = try? container.decode(Int.self, forKey: .ID) { id = val }
            else if let val = try? container.decode(Int.self, forKey: .id) { id = val }
            else if let s = try? container.decode(String.self, forKey: .ID) { id = Int(s) ?? 0 }
            else if let s = try? container.decode(String.self, forKey: .id) { id = Int(s) ?? 0 }
            else { id = 0 }
            
            // Decode Title
            title = (try? container.decode(String.self, forKey: .Title)) ?? (try? container.decode(String.self, forKey: .title)) ?? "Unknown"
            
            // Decode ConsoleID
            if let val = try? container.decode(Int.self, forKey: .ConsoleID) { consoleID = val }
            else if let val = try? container.decode(Int.self, forKey: .consoleID) { consoleID = val }
            else if let s = try? container.decode(String.self, forKey: .ConsoleID) { consoleID = Int(s) ?? 0 }
            else if let s = try? container.decode(String.self, forKey: .consoleID) { consoleID = Int(s) ?? 0 }
            else { consoleID = 0 }
            
            // Decode ConsoleName
            consoleName = (try? container.decode(String.self, forKey: .ConsoleName)) ?? (try? container.decode(String.self, forKey: .consoleName)) ?? ""
            
            // Decode Hashes
            hashes = (try? container.decode([String].self, forKey: .Hashes)) ?? (try? container.decode([String].self, forKey: .hashes)) ?? []
        }
    }

    private func requestUserSummary(username: String) async throws -> RAUserInfo {
        let url = URL(string: "\(apiBaseURL)/API_GetUserSummary.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey), // Auth happens here
            URLQueryItem(name: "a", value: "1")
        ]

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: components.url!)
        } catch let urlError as URLError {
            throw RAError.from(urlError: urlError)
        } catch {
            throw RAError.networkUnreachable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RAError.serverError(0)
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        if httpResponse.statusCode != 200 {
            throw RAError.from(httpStatus: httpResponse.statusCode, json: json ?? nil)
        }

        // RA returns 200 with {Success:false, Status:"..."} for some auth failures
        if let json = json, let success = json["Success"] as? Bool, success == false {
            throw RAError.from(httpStatus: 200, json: json)
        }

        guard let responseData = json else {
            throw RAError.serverError(httpResponse.statusCode)
        }

        // Always log the full response so the JSON shape can be diagnosed from the log file
        // without requiring the user to enable Debug logging. This is a diagnostic aid for
        // parsing bugs (RA occasionally renames fields). Verbose but bounded.
        if let pretty = try? JSONSerialization.data(withJSONObject: responseData, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: pretty, encoding: .utf8) {
            LoggerService.info(category: "RetroAchievements", "API_GetUserSummary FULL RESPONSE:\n\(prettyStr)")
        } else {
            let keys = responseData.keys.sorted().joined(separator: ", ")
            LoggerService.info(category: "RetroAchievements", "API_GetUserSummary keys: \(keys)")
        }

        let safeInt = { (key: String) -> Int in
            if let val = responseData[key] as? Int { return val }
            if let s = responseData[key] as? String, let val = Int(s) { return val }
            return 0
        }

        return RAUserInfo(
            username: responseData["User"] as? String ?? username,
            totalPoints: safeInt("TotalSoftcorePoints"),
            totalHardcorePoints: safeInt("TotalHardcorePoints"),
            totalTruePoints: safeInt("TotalTruePoints"),
            rank: safeInt("TotalRanked"),
            awards: safeInt("Awards"),
            memberSince: responseData["MemberSince"] as? String ?? "",
            richPresenceMsg: responseData["RichPresenceMsg"] as? String,
            lastGameID: responseData["LastGameID"] as? Int ?? (responseData["LastGameID"] as? String).flatMap { Int($0) },
            lastGameTitle: responseData["LastGameTitle"] as? String
        )
    }

    // Manually refresh the user summary (points/rank/member-since) without requiring
    // a full re-login. Useful when the displayed stats appear stale or after a server-side
    // change (e.g. points awarded retroactively for an event).
    @MainActor
    func refreshUserSummary() async {
        guard isLoggedIn, let username = username, !webApiKey.isEmpty else { return }
        do {
            let response = try await requestUserSummary(username: username)
            self.userInfo = response
            #if LOG_DEBUG
            LoggerService.debug(category: "RetroAchievements", "Refreshed user summary: pts=\(response.totalPoints) hc=\(response.totalHardcorePoints) true=\(response.totalTruePoints) rank=\(response.rank)")
            #endif
        } catch {
            LoggerService.error(category: "RetroAchievements", "refreshUserSummary failed: \(error.localizedDescription)")
        }
    }
    
    private func requestGameInfo(gameID: String, username: String) async throws -> (response: RAGameResponse?, rawData: Data?) {
        let url = URL(string: "\(apiBaseURL)/API_GetGameInfoAndUserProgress.php")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "g", value: gameID),
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "y", value: webApiKey),
            URLQueryItem(name: "a", value: "1")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(RAGameResponse.self, from: data)
        return (response, data)
    }
}

// MARK: - RA Error Types

enum RAError: LocalizedError {
    case apiKeyMissing
    case networkUnreachable
    case networkTimeout
    case serverError(Int)
    case unknownUser
    case invalidApiKey
    case wrongPassword
    case accountLocked
    case loginFailed(String)
    case gameNotFound
    case invalidHash

    /// User-facing category for grouping messages in the UI (e.g. to color the error label).
    enum Severity {
        case info, warning, error
    }

    var severity: Severity {
        switch self {
        case .apiKeyMissing, .networkUnreachable, .networkTimeout:
            return .info
        case .serverError, .loginFailed, .gameNotFound, .invalidHash:
            return .warning
        case .unknownUser, .invalidApiKey, .wrongPassword, .accountLocked:
            return .error
        }
    }

    /// Optional URL the user can click for self-service resolution (e.g. RA settings page).
    var helpURL: URL? {
        switch self {
        case .unknownUser, .accountLocked:
            return URL(string: "https://retroachievements.org/")
        case .invalidApiKey, .wrongPassword:
            return URL(string: "https://retroachievements.org/settings")
        default:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "RetroAchievements Web API key is not configured."
        case .networkUnreachable:
            return "Can't reach retroachievements.org. Check your internet connection."
        case .networkTimeout:
            return "The connection to RetroAchievements timed out. Try again."
        case .serverError(let code):
            return "RetroAchievements server returned HTTP \(code). Try again in a moment."
        case .unknownUser:
            return "This RetroAchievements username doesn't exist. Check the spelling."
        case .invalidApiKey:
            return "The Web API Key is invalid. Generate a new one at retroachievements.org/settings."
        case .wrongPassword:
            return "The password is incorrect."
        case .accountLocked:
            return "Your RetroAchievements account is locked or suspended."
        case .loginFailed(let msg):
            return "RetroAchievements login failed: \(msg)"
        case .gameNotFound:
            return "Game not found in RetroAchievements database."
        case .invalidHash:
            return "Invalid ROM hash for this system."
        }
    }
}

/// Translate an RA API response field or status code into a structured RAError.
/// Used by both the Web API Key path (`API_GetUserSummary.php`) and the login2 path.
extension RAError {
    /// Map an HTTP status code + JSON body to a structured error.
    /// `json` may be nil if the response wasn't JSON.
    static func from(httpStatus: Int, json: [String: Any]?) -> RAError {
        if httpStatus == 200 { return .loginFailed("Unexpected response") }

        // Inspect server-provided fields
        if let json = json {
            if let errorStr = (json["Error"] as? String) ?? (json["Status"] as? String) {
                let lower = errorStr.lowercased()
                if lower.contains("unknown user") || lower.contains("user not found") || lower.contains("no such user") {
                    return .unknownUser
                }
                if lower.contains("invalid api key") || lower.contains("invalid web api key") || lower.contains("api key") {
                    return .invalidApiKey
                }
                if lower.contains("credentials invalid") || lower.contains("invalid credentials") || lower.contains("incorrect password") || lower.contains("wrong password") {
                    return .wrongPassword
                }
                if lower.contains("locked") || lower.contains("suspended") || lower.contains("banned") {
                    return .accountLocked
                }
                return .loginFailed(errorStr)
            }
            if let success = json["Success"] as? Bool, success == false {
                return .loginFailed("RetroAchievements rejected the request.")
            }
        }

        if (500..<600).contains(httpStatus) {
            return .serverError(httpStatus)
        }
        return .serverError(httpStatus)
    }

    /// Map a `URLError` (raised by URLSession on transport failures) to a structured RAError.
    static func from(urlError: URLError) -> RAError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return .networkUnreachable
        case .timedOut:
            return .networkTimeout
        default:
            return .networkUnreachable
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

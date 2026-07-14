import Foundation
import AppKit

struct LaunchBoxGame: Codable, Hashable {
    let databaseID: Int
    let name: String
    let platform: String
    let releaseDate: String?
    let releaseYear: String?
    let overview: String?
    let developer: String?
    let publisher: String?
    let genres: String?
    let communityRating: Double?
    let esrb: String?
    let maxPlayers: Int?
    let cooperative: Bool?
    let videoURL: String?
    let wikipediaURL: String?
    let alternateNames: [String]
    let images: [LaunchBoxImageRef]
}

struct LaunchBoxImageRef: Codable, Hashable {
    let fileName: String
    let type: String
    let region: String?
    let crc32: String?
}

private struct GamePartial {
    var databaseID: Int = 0
    var name: String = ""
    var platform: String = ""
    var releaseDate: String?
    var releaseYear: String?
    var overview: String?
    var developer: String?
    var publisher: String?
    var genres: String?
    var communityRating: Double?
    var esrb: String?
    var maxPlayers: Int?
    var cooperative: Bool?
    var videoURL: String?
    var wikipediaURL: String?
}

private struct TempImageRef: Hashable {
    let databaseID: Int
    let fileName: String
    let type: String
    let region: String?
    let crc32: String?
}

private struct TempAlternateName: Hashable {
    let databaseID: Int
    let alternateName: String
}

@MainActor
final class LaunchBoxMetadataService: ObservableObject {
    static let shared = LaunchBoxMetadataService()

    enum Phase: Equatable {
        case idle
        case downloading
        case extracting
        case parsing
        case indexing
        case ready
    }

    @Published private(set) var currentPhase: Phase = .idle
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadStatus: String = ""
    @Published private(set) var totalItems: Int = 0
    @Published private(set) var completedItems: Int = 0

    private let keyLastUpdate = "launchbox_metadata_last_update"
    private let keySystemOverride = "launchbox_system_platform_map"

    private let zipURL = URL(
        string: "https://gamesdb.launchbox-app.com/Metadata.zip"
    )!

    private init() {}

    private var storageDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/LaunchBox", isDirectory: true)
    }

    private var platformsDir: URL {
        storageDir.appendingPathComponent("Platforms", isDirectory: true)
    }

    private var zipLocalURL: URL {
        storageDir.appendingPathComponent("Metadata.zip")
    }

    private var crossRefFile: URL {
        platformsDir.appendingPathComponent("_crossref.json")
    }

    var lastUpdateDate: Date? {
        let interval = AppSettings.getDouble(keyLastUpdate, defaultValue: 0)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private var isStale: Bool {
        guard let last = lastUpdateDate else { return true }
        return Date().timeIntervalSince(last) > 86400
    }

    private var zipExists: Bool {
        FileManager.default.fileExists(atPath: zipLocalURL.path)
    }

    // MARK: - Platform Name Resolution

    private var platformNameCache: [String: String] = [:]

    func platformName(forSystemID systemID: String) -> String? {
        if let cached = platformNameCache[systemID] { return cached }
        guard let map = loadCrossRef() else { return nil }
        let result = map[systemID]
        platformNameCache[systemID] = result
        return result
    }

    private func loadCrossRef() -> [String: String]? {
        guard FileManager.default.fileExists(atPath: crossRefFile.path),
              let data = try? Data(contentsOf: crossRefFile),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return map
    }

    // MARK: - Staleness Check

    func needsUpdate() -> Bool {
        isStale || !zipExists || !hasPlatformFiles
    }

    private var hasPlatformFiles: Bool {
        let files = try? FileManager.default.contentsOfDirectory(at: platformsDir, includingPropertiesForKeys: nil)
        return files?.contains(where: { $0.pathExtension == "json" }) ?? false
    }

    // MARK: - Download

    func downloadIfNeeded(force: Bool = false, progress: @escaping (Double) -> Void = { _ in }) async -> Bool {
        if !force, !isStale, zipExists { return true }

        try? FileManager.default.createDirectory(at: platformsDir, withIntermediateDirectories: true)
        return await downloadZip(progress: progress)
    }

    private func downloadZip(progress: @escaping (Double) -> Void) async -> Bool {
        currentPhase = .downloading
        downloadProgress = 0

        do {
            let delegate = DownloadProgressDelegate()
            delegate.progressHandler = { p in
                progress(p)
                Task { @MainActor in self.downloadProgress = p }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let request = URLRequest(url: zipURL)

            let (location, response) = try await session.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                currentPhase = .idle
                return false
            }

            try? FileManager.default.removeItem(at: zipLocalURL)
            try FileManager.default.moveItem(at: location, to: zipLocalURL)
            session.invalidateAndCancel()

            return true
        } catch {
            currentPhase = .idle
            return false
        }
    }

    // MARK: - Parse & Index

    func parseAndIndexIfNeeded(force: Bool = false, status: @escaping (String) -> Void = { _ in }) async -> Bool {
        if !force, !needsUpdate() { return true }

        status("Extracting Metadata.xml (501 MB)...")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchbox_\(UUID().uuidString)")

        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let extractProcess = Process()
            extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            extractProcess.arguments = ["-o", zipLocalURL.path, "-d", tempDir.path]
            try extractProcess.run()
            extractProcess.waitUntilExit()

            guard extractProcess.terminationStatus == 0 else {
                currentPhase = .idle
                return false
            }
        } catch {
            currentPhase = .idle
            return false
        }

        let xmlURL = tempDir.appendingPathComponent("Metadata.xml")
        guard FileManager.default.fileExists(atPath: xmlURL.path) else {
            currentPhase = .idle
            return false
        }

        currentPhase = .parsing
        status("Parsing 183,999 games, 68,263 alternate names, 1.3M images...")

        let parser = LaunchBoxXMLParser(url: xmlURL)

        await Task.detached(priority: .utility) {
            parser.parse()
        }.value

        if parser.parseError != nil {
            currentPhase = .idle
            return false
        }

        currentPhase = .indexing
        status("Grouping games by platform...")

        let gamesByPlatform = groupByPlatform(games: parser.games, images: parser.images, alternateNames: parser.alternateNames)
        let crossRef = buildCrossRef(gamesByPlatform: gamesByPlatform)

        let totalPlatforms = gamesByPlatform.count
        var completed = 0

        for (platformName, platformGames) in gamesByPlatform {
            let safeName = platformName.sanitizedForFilename
            let url = platformsDir.appendingPathComponent("\(safeName).json")
            if let data = try? JSONEncoder().encode(platformGames) {
                try? data.write(to: url, options: .atomic)
            }
            completed += 1
            status("Indexed \(platformName) (\(completed)/\(totalPlatforms) platforms, \(platformGames.count) games)")
        }

        if let crossData = try? JSONEncoder().encode(crossRef) {
            try? crossData.write(to: crossRefFile, options: .atomic)
        }

        platformNameCache = crossRef
        AppSettings.setDouble(keyLastUpdate, value: Date().timeIntervalSince1970)
        LaunchBoxGamesDBService.shared.recordSyncDate()

        currentPhase = .ready
        let totalGames = gamesByPlatform.values.reduce(0) { $0 + $1.count }
        status("LaunchBox database ready — \(totalGames) games across \(totalPlatforms) platforms")
        return true
    }

    // MARK: - Full Pipeline (simple call)

    func downloadAndParseIfNeeded(force: Bool = false) async -> Bool {
        guard await downloadIfNeeded(force: force) else { return false }
        return await parseAndIndexIfNeeded(force: force)
    }

    private func groupByPlatform(
        games: [Int: GamePartial],
        images: [Int: [LaunchBoxImageRef]],
        alternateNames: [Int: [String]]
    ) -> [String: [LaunchBoxGame]] {
        var groups: [String: [Int: LaunchBoxGame]] = [:]

        for (dbID, partial) in games {
            let game = LaunchBoxGame(
                databaseID: dbID,
                name: partial.name,
                platform: partial.platform,
                releaseDate: partial.releaseDate,
                releaseYear: partial.releaseYear,
                overview: partial.overview,
                developer: partial.developer,
                publisher: partial.publisher,
                genres: partial.genres,
                communityRating: partial.communityRating,
                esrb: partial.esrb,
                maxPlayers: partial.maxPlayers,
                cooperative: partial.cooperative,
                videoURL: partial.videoURL,
                wikipediaURL: partial.wikipediaURL,
                alternateNames: alternateNames[dbID] ?? [],
                images: images[dbID] ?? []
            )
            groups[partial.platform, default: [:]][dbID] = game
        }

        var result: [String: [LaunchBoxGame]] = [:]
        for (platform, platformGames) in groups {
            result[platform] = platformGames.values.sorted { $0.name < $1.name }
        }
        return result
    }

    private func buildCrossRef(gamesByPlatform: [String: [LaunchBoxGame]]) -> [String: String] {
        var map: [String: String] = [:]
        let allSystems = SystemDatabase.systems

        for platformName in gamesByPlatform.keys {
            let lower = platformName.lowercased()
            for system in allSystems {
                let sysName = system.name.lowercased()
                if lower.contains(sysName) || sysName.contains(lower) {
                    map[system.id] = platformName
                }
            }
        }

        for system in allSystems {
            if map[system.id] == nil {
                let mfr = system.manufacturer.lowercased()
                let sysName = system.name.lowercased()
                for platformName in gamesByPlatform.keys {
                    let lower = platformName.lowercased()
                    if lower.contains(mfr) && lower.contains(sysName) {
                        map[system.id] = platformName
                        break
                    }
                }
            }
        }

        return map
    }

    // MARK: - Query API

    private var gameCache: [String: [LaunchBoxGame]] = [:]
    private var cacheAccessCount: [String: Int] = [:]
    private let cacheMaxEntries = 50

    func games(forPlatform platformName: String) -> [LaunchBoxGame] {
        if let cached = gameCache[platformName] { return cached }

        let fileName = "\(platformName.sanitizedForFilename).json"
        let url = platformsDir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([LaunchBoxGame].self, from: data)
        else { return [] }

        if gameCache.count >= cacheMaxEntries,
           let oldest = cacheAccessCount.min(by: { $0.value < $1.value })?.key {
            gameCache.removeValue(forKey: oldest)
            cacheAccessCount.removeValue(forKey: oldest)
        }

        gameCache[platformName] = games
        cacheAccessCount[platformName] = 0
        return games
    }

    func bestMatch(for gameName: String, systemID: String) -> LaunchBoxGame? {
        guard let platformName = platformName(forSystemID: systemID) else { return nil }
        return bestMatch(for: gameName, platformName: platformName)
    }

    func bestMatch(for gameName: String, platformName: String) -> LaunchBoxGame? {
        let games = games(forPlatform: platformName)
        let query = gameName.lowercased().trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else { return nil }

        let exact = games.first { $0.name.lowercased() == query }
        if let exact { return exact }

        var scored: [(game: LaunchBoxGame, score: Int)] = []

        for game in games {
            if game.name.lowercased().fuzzyMatch(query) {
                scored.append((game, fuzzyScore(query, target: game.name.lowercased())))
            }
            for alt in game.alternateNames {
                if alt.lowercased().fuzzyMatch(query) {
                    scored.append((game, fuzzyScore(query, target: alt.lowercased())))
                    break
                }
            }
        }

        return scored.max(by: { $0.score < $1.score })?.game
    }

    private func fuzzyScore(_ query: String, target: String) -> Int {
        if target == query { return 1000 }
        if target.hasPrefix(query) { return 500 }
        if target.contains(query) { return 300 }

        var score = 0
        var tIdx = target.startIndex
        var consecutive = 0

        for qc in query {
            while tIdx < target.endIndex && target[tIdx] != qc {
                tIdx = target.index(after: tIdx)
                consecutive = 0
            }
            if tIdx < target.endIndex {
                consecutive += 1
                score += consecutive * 10
                tIdx = target.index(after: tIdx)
            }
        }
        return score
    }

    func boxArtRef(for game: LaunchBoxGame) -> LaunchBoxImageRef? {
        let boxFronts = game.images.filter { $0.type == "Box - Front" }
        guard !boxFronts.isEmpty else { return nil }

        let regionPref = SystemPreferences.shared.systemLanguage.noIntroRegionPreference

        for preferred in regionPref {
            let stripped = preferred
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .lowercased()
            if let match = boxFronts.first(where: {
                $0.region?.lowercased().contains(stripped) ?? false
            }) {
                return match
            }
        }

        return boxFronts.first
    }

    static func cdnURL(for imageRef: LaunchBoxImageRef) -> URL {
        URL(string: "https://images.launchbox-app.com/\(imageRef.fileName)")!
    }

    func fetchAndApplyMetadata(for rom: ROM, library: ROMLibrary) async -> Bool {
        let gameName = rom.metadata?.title ?? rom.displayName
        guard let systemID = rom.systemID,
              let match = bestMatch(for: gameName, systemID: systemID)
        else { return false }

        var updated = rom
        var meta = updated.metadata ?? ROMMetadata()

        if meta.description?.isEmpty ?? true { meta.description = match.overview }
        if meta.developer?.isEmpty ?? true { meta.developer = match.developer }
        if meta.publisher?.isEmpty ?? true { meta.publisher = match.publisher }
        if meta.genre?.isEmpty ?? true { meta.genre = match.genres }
        if meta.releaseDate?.isEmpty ?? true { meta.releaseDate = match.releaseDate }
        if meta.year?.isEmpty ?? true { meta.year = match.releaseYear }
        if meta.esrbRating?.isEmpty ?? true { meta.esrbRating = match.esrb }
        if !meta.cooperative { meta.cooperative = match.cooperative ?? false }

        updated.metadata = meta

        var downloadedBoxArt = false
        if !updated.hasBoxArt, let imageRef = boxArtRef(for: match) {
            let cdn = Self.cdnURL(for: imageRef)
            let localURL = updated.boxArtLocalPath
            let folder = localURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            if let (tmpURL, _) = try? await URLSession.shared.download(from: cdn) {
                if NSImage(contentsOf: tmpURL) != nil {
                    try? FileManager.default.removeItem(at: localURL)
                    try? FileManager.default.moveItem(at: tmpURL, to: localURL)
                    BoxArtThumbnailService.deleteThumbnails(for: localURL)
                    await ImageCache.shared.removeImage(for: localURL)
                    await ImageCache.shared.removeThumbnail(for: localURL)
                    BoxArtThumbnailService.generateThumbnailsSynchronously(forOriginal: localURL)
                    updated.hasBoxArt = true
                    downloadedBoxArt = true
                } else {
                    try? FileManager.default.removeItem(at: tmpURL)
                }
            }
        }

        library.updateROM(updated, persist: true)
        LoggerService.info(category: "LaunchBoxMD", "Enriched '\(rom.name)' — found \(match.name) (DBID: \(match.databaseID))" + (downloadedBoxArt ? " + box art" : ""))
        return true
    }
}

// MARK: - XMLParser Delegate

private class LaunchBoxXMLParser: NSObject, XMLParserDelegate {
    let url: URL
    var games: [Int: GamePartial] = [:]
    var images: [Int: [LaunchBoxImageRef]] = [:]
    var alternateNames: [Int: [String]] = [:]
    var parseError: Error?

    private enum Container {
        case none
        case game
        case alternateName
        case gameImage
    }

    private var container: Container = .none
    private var currentGame: GamePartial?
    private var currentAltDBID: Int = 0
    private var currentAltName: String = ""
    private var currentImageDBID: Int = 0
    private var currentImageFileName: String = ""
    private var currentImageType: String = ""
    private var currentImageRegion: String?
    private var currentImageCRC: String?
    private var currentElement: String = ""
    private var currentValue: String = ""

    init(url: URL) {
        self.url = url
    }

    func parse() {
        let data = try? Data(contentsOf: url)
        guard let data else {
            parseError = NSError(domain: "LaunchBoxXML", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot read Metadata.xml"])
            return
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""

        switch elementName {
        case "Game":
            container = .game
            currentGame = GamePartial()
        case "GameAlternateName":
            container = .alternateName
            currentAltDBID = 0
            currentAltName = ""
        case "GameImage":
            container = .gameImage
            currentImageDBID = 0
            currentImageFileName = ""
            currentImageType = ""
            currentImageRegion = nil
            currentImageCRC = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch container {
        case .game:
            guard var game = currentGame else { return }
            switch elementName {
            case "DatabaseID": game.databaseID = Int(value) ?? 0
            case "Name": game.name = value
            case "Platform": game.platform = value
            case "ReleaseDate": game.releaseDate = value
            case "ReleaseYear": game.releaseYear = value
            case "Overview": game.overview = value
            case "Developer": game.developer = value
            case "Publisher": game.publisher = value
            case "Genres": game.genres = value
            case "CommunityRating": game.communityRating = Double(value)
            case "ESRB": game.esrb = value
            case "MaxPlayers": game.maxPlayers = Int(value)
            case "Cooperative": game.cooperative = value.lowercased() == "true"
            case "VideoURL": game.videoURL = value
            case "WikipediaURL": game.wikipediaURL = value
            case "Game":
                if game.databaseID > 0, !game.name.isEmpty {
                    games[game.databaseID] = game
                }
                currentGame = nil
                container = .none
            default: break
            }
            currentGame = game

        case .alternateName:
            switch elementName {
            case "DatabaseID": currentAltDBID = Int(value) ?? 0
            case "AlternateName": currentAltName = value
            case "GameAlternateName":
                if currentAltDBID > 0, !currentAltName.isEmpty {
                    alternateNames[currentAltDBID, default: []].append(currentAltName)
                }
                container = .none
            default: break
            }

        case .gameImage:
            switch elementName {
            case "DatabaseID": currentImageDBID = Int(value) ?? 0
            case "FileName": currentImageFileName = value
            case "Type": currentImageType = value
            case "Region": currentImageRegion = value
            case "CRC32": currentImageCRC = value
            case "GameImage":
                if currentImageDBID > 0, !currentImageFileName.isEmpty, !currentImageType.isEmpty {
                    let ref = LaunchBoxImageRef(
                        fileName: currentImageFileName,
                        type: currentImageType,
                        region: currentImageRegion,
                        crc32: currentImageCRC
                    )
                    images[currentImageDBID, default: []].append(ref)
                }
                container = .none
            default: break
            }

        case .none:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - URLSession Download Delegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    var progressHandler: ((Double) -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(max(totalBytesExpectedToWrite, 1))
        progressHandler?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        progressHandler?(1.0)
    }
}

// MARK: - Filename Sanitization

private extension String {
    var sanitizedForFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        return components(separatedBy: allowed.inverted).joined()
    }
}

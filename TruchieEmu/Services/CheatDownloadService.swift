import Foundation
import os.log

private let cheatDownloadLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "CheatDownloadService")

// MARK: - Download Log Entry

/// Represents a single download log entry
struct CheatDownloadLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let systemName: String
    let fileName: String
    let status: DownloadStatus
    let message: String
    
    enum DownloadStatus: Equatable {
        case inProgress
        case success
        case failed(String)
        
        static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
            switch (lhs, rhs) {
            case (.inProgress, .inProgress):
                return true
            case (.success, .success):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }
}

// MARK: - Cheat Download Service

/// Downloads cheat files from the libretro-database cheats repository.
/// URL: https://github.com/libretro/libretro-database/tree/master/cht
class CheatDownloadService: ObservableObject {
    static let shared = CheatDownloadService()
    
    // MARK: - Published State
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var lastDownloadDate: Date? {
        didSet {
            UserDefaults.standard.set(lastDownloadDate, forKey: "cheatLastDownloadDate")
        }
    }
    
    // MARK: - Download Progress State
    
    /// Total number of items to download
    @Published var totalItemsToDownload: Int = 0
    /// Number of items currently downloaded
    @Published var currentDownloadedCount: Int = 0
    /// Number of items currently being downloaded (in progress)
    @Published var currentlyDownloadingCount: Int = 0
    /// Log of all download attempts with their status
    @Published var downloadLog: [CheatDownloadLogEntry] = []
    
    // MARK: - Constants
    
    /// Base URL for libretro cheat database
    private let baseURL = "https://github.com/libretro/libretro-database/raw/master/cht"
    
    /// Raw API URL for listing files
    private let apiBaseURL = "https://api.github.com/repos/libretro/libretro-database/contents/cht"
    
    /// Local directory for downloaded cheats
    private var localCheatsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/cheats_downloaded")
    }
    
    /// Directory for a specific system's cheats
    func systemCheatDirectory(for systemID: String) -> URL {
        localCheatsDirectory.appendingPathComponent(systemID)
    }
    
    // MARK: - Initialization
    
    init() {
        loadLastDownloadDate()
    }
    
    private func loadLastDownloadDate() {
        lastDownloadDate = UserDefaults.standard.object(forKey: "cheatLastDownloadDate") as? Date
    }
    
    // MARK: - Public Methods
    
    /// Download all cheat files from libretro database
    @MainActor
    func downloadAllCheats() async -> CheatDownloadResult {
        guard !isDownloading else {
            return .alreadyDownloading
        }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Starting download..."
        downloadLog = []
        currentDownloadedCount = 0
        currentlyDownloadingCount = 0
        totalItemsToDownload = 0
        
        defer {
            isDownloading = false
            currentlyDownloadingCount = 0
        }
        
        // Ensure local directory exists
        do {
            try FileManager.default.createDirectory(at: localCheatsDirectory, withIntermediateDirectories: true)
        } catch {
            cheatDownloadLog.error("Failed to create cheats directory: \(error.localizedDescription)")
            return .failed("Could not create local cheats directory")
        }
        
        // Fetch the list of cheat folders/files from GitHub
        downloadStatus = "Fetching cheat index..."
        let gitHubContents: [GitHubContent]
        do {
            gitHubContents = try await fetchGitHubContents(apiBaseURL)
        } catch {
            cheatDownloadLog.error("Failed to fetch GitHub contents: \(error.localizedDescription)")
            return .failed("Could not fetch cheat index from GitHub")
        }
        
        // Filter for directories (each directory is a system)
        let systemFolders = gitHubContents.filter { $0.type == .directory }
        downloadStatus = "Found \(systemFolders.count) systems with cheats"
        
        // Count total cheat files to download
        totalItemsToDownload = await countTotalCheatFiles(in: systemFolders)
        downloadStatus = "Found \(totalItemsToDownload) cheat files in \(systemFolders.count) systems"
        
        var totalDownloaded = 0
        var totalFailed = 0
        
        // Download cheats for each system folder
        for (index, folder) in systemFolders.enumerated() {
            let progress = Double(index) / Double(systemFolders.count)
            downloadProgress = progress
            downloadStatus = "Downloading \(folder.name) (\(index + 1)/\(systemFolders.count))"
            
            do {
                let downloaded = try await downloadSystemCheats(folder, systemName: folder.name)
                totalDownloaded += downloaded
            } catch {
                cheatDownloadLog.error("Failed to download cheats for \(folder.name): \(error.localizedDescription)")
                
                // Log the system-level failure
                let logEntry = CheatDownloadLogEntry(
                    timestamp: Date(),
                    systemName: folder.name,
                    fileName: "System",
                    status: .failed(error.localizedDescription),
                    message: "Failed to download cheats for \(folder.name)"
                )
                await MainActor.run {
                    downloadLog.append(logEntry)
                }
                totalFailed += 1
            }
        }
        
        downloadProgress = 1.0
        downloadStatus = "Download complete!"
        lastDownloadDate = Date()
        
        let message = "Downloaded \(totalDownloaded) cheat files (\(totalFailed) systems failed)"
        cheatDownloadLog.info("\(message)")
        return .success(downloaded: totalDownloaded, failed: totalFailed, message: message)
    }
    
    /// Download cheats for a specific system
    @MainActor
    func downloadCheatsForSystem(_ systemID: String) async -> CheatDownloadResult {
        guard !isDownloading else {
            return .alreadyDownloading
        }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Downloading cheats for \(systemID)..."
        downloadLog = []
        currentDownloadedCount = 0
        currentlyDownloadingCount = 0
        totalItemsToDownload = 0
        
        defer {
            isDownloading = false
            currentlyDownloadingCount = 0
        }
        
        do {
            let systemFolderName = mapSystemIDToFolderName(systemID)
            let encodedFolderName = systemFolderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? systemFolderName
            let folderURL = apiBaseURL + "/" + encodedFolderName
            
            guard let url = URL(string: folderURL) else {
                return .failed("Invalid system ID")
            }
            
            // Count total files first
            totalItemsToDownload = await countCheatFilesInFolder(url, maxDepth: 1)
            downloadStatus = "Found \(totalItemsToDownload) cheat files for \(systemID)"
            
            let downloaded = try await downloadCheatsFromFolder(url, to: systemCheatDirectory(for: systemID), systemName: systemID)
            
            // Check for subdirectories and download them too
            let contents = try await fetchGitHubContents(url.absoluteString)
            for item in contents where item.type == .directory {
                let encodedItemName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.name
                let subFolderURL = "\(url.absoluteString)/\(encodedItemName)"
                if let subURL = URL(string: subFolderURL) {
                    _ = try await downloadCheatsFromFolder(subURL, to: systemCheatDirectory(for: systemID), systemName: systemID)
                }
            }
            
            lastDownloadDate = Date()
            return .success(downloaded: downloaded, failed: 0, message: "Downloaded \(downloaded) cheat files for \(systemID)")
        } catch {
            cheatDownloadLog.error("Failed to download cheats for \(systemID): \(error.localizedDescription)")
            return .failed("Failed to download cheats: \(error.localizedDescription)")
        }
    }
    
    // MARK: - ROM Cheat Lookup
    
    /// Find cheats for a specific ROM by searching downloaded cheat files
    func findCheatsForROM(_ rom: ROM) -> [CheatFile] {
        let romFilename = rom.path.deletingPathExtension().lastPathComponent
        let systemID = rom.systemID ?? "unknown"
        var foundFiles: [CheatFile] = []
        
        // Search in downloaded cheats directory
        let romCheatsDirName = romFilename
        
        // Look for matching .cht files
        if let enumerator = FileManager.default.enumerator(
            at: localCheatsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let filename = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                let romFilenameLower = romFilename.lowercased()
                
                if filename == romFilenameLower || romCheatsDirName.contains(filename) {
                    if let cheats = CheatParser.parseChtFile(url: fileURL) {
                        let cheatFile = CheatFile(
                            romPath: rom.path.path,
                            romName: rom.displayName,
                            cheats: cheats,
                            source: .libretroDatabase
                        )
                        foundFiles.append(cheatFile)
                    }
                }
            }
        }
        
        // Merge cheats from all found files
        if !foundFiles.isEmpty {
            let allCheats = foundFiles.flatMap { $0.cheats }
            let mergedFile = CheatFile(
                romPath: rom.path.path,
                romName: rom.displayName,
                cheats: mergeCheats(allCheats),
                source: .libretroDatabase
            )
            return [mergedFile]
        }
        
        return []
    }
    
    // MARK: - Private Methods
    
    /// Fetch directory contents from GitHub API
    private func fetchGitHubContents(_ urlString: String) async throws -> [GitHubContent] {
        guard let url = URL(string: urlString) else {
            throw CheatDownloadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        // GitHub API requires User-Agent
        request.setValue("TruchieEmu/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CheatDownloadError.invalidResponse
        }
        
        // Check HTTP status code first
        if httpResponse.statusCode == 403 {
            // Rate limited - return empty array instead of throwing
            cheatDownloadLog.warning("GitHub API rate limit reached for: \(urlString)")
            return []
        }
        
        if httpResponse.statusCode == 404 {
            // Not found - return empty array (folder might not exist yet in repo)
            cheatDownloadLog.warning("GitHub API path not found: \(urlString)")
            return []
        }
        
        if httpResponse.statusCode != 200 {
            throw CheatDownloadError.httpError(httpResponse.statusCode)
        }
        
        // Verify we got JSON content before trying to decode
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.contains("json") || !contentType.isEmpty else {
            cheatDownloadLog.error("Non-JSON response received (Content-Type: \(contentType)), data preview: \(String(data: data.prefix(200), encoding: .utf8) ?? "empty")")
            throw CheatDownloadError.invalidResponse
        }
        
        // Check if data is empty
        guard !data.isEmpty else {
            cheatDownloadLog.error("Empty response from GitHub API for: \(urlString)")
            throw CheatDownloadError.networkError
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            return try decoder.decode([GitHubContent].self, from: data)
        } catch let decodeError {
            // Log the actual response for debugging
            let responsePreview = String(data: data.prefix(500), encoding: .utf8) ?? "(unable to decode response)"
            cheatDownloadLog.error("JSON decode error: \(decodeError.localizedDescription). Response preview: \(responsePreview)")
            throw CheatDownloadError.invalidResponse
        }
    }
    
    /// Count total cheat files across all system folders
    private func countTotalCheatFiles(in systemFolders: [GitHubContent]) async -> Int {
        var totalCount = 0
        for folder in systemFolders {
            guard !folder.safeUrl.isEmpty else { continue }
            totalCount += await countCheatFilesInFolder(URL(string: folder.safeUrl)!, maxDepth: 2)
        }
        return totalCount
    }
    
    /// Count cheat files in a folder (with depth limit to prevent excessive recursion)
    private func countCheatFilesInFolder(_ url: URL, maxDepth: Int) async -> Int {
        guard maxDepth > 0 else { return 0 }
        
        do {
            let contents = try await fetchGitHubContents(url.absoluteString)
            var count = 0
            
            for item in contents {
                if item.type == .file && item.name.hasSuffix(".cht") {
                    count += 1
                } else if item.type == .directory {
                    if let nestedURLString = item.url, let nestedURL = URL(string: nestedURLString) {
                        count += await countCheatFilesInFolder(nestedURL, maxDepth: maxDepth - 1)
                    }
                }
            }
            return count
        } catch {
            return 0
        }
    }
    
    /// Download cheat files from a system folder
    private func downloadSystemCheats(_ folder: GitHubContent, systemName: String) async throws -> Int {
        let destDir = localCheatsDirectory.appendingPathComponent(folder.name)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Fetch contents of the folder using safe url accessor
        let folderURL = folder.safeUrl
        guard !folderURL.isEmpty else {
            cheatDownloadLog.warning("Folder \(folder.name) has no URL, skipping")
            return 0
        }
        let folderContents = try await fetchGitHubContents(folderURL)
        
        var downloaded = 0
        
        // Download .cht files directly in this folder
        for item in folderContents where item.type == .file && item.name.hasSuffix(".cht") {
            try await downloadFile(item, to: destDir, systemName: systemName)
            await MainActor.run {
                currentDownloadedCount += 1
            }
            downloaded += 1
        }
        
        // Check for nested directories (MAME vs other naming)
        for item in folderContents where item.type == .directory {
            if let nestedURLString = item.url, let nestedURL = URL(string: nestedURLString) {
                _ = try await downloadCheatsFromFolder(nestedURL, to: destDir, systemName: systemName)
            }
        }
        
        return downloaded
    }
    
    /// Download cheat files from a specific folder URL
    private func downloadCheatsFromFolder(_ url: URL, to destination: URL, systemName: String = "Unknown") async throws -> Int {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        
        let contents = try await fetchGitHubContents(url.absoluteString)
        var downloaded = 0
        
        for item in contents where item.type == .file && item.name.hasSuffix(".cht") {
            try await downloadFile(item, to: destination, systemName: systemName)
            await MainActor.run {
                currentDownloadedCount += 1
            }
            downloaded += 1
        }
        
        return downloaded
    }
    
    /// Download a single file
    private func downloadFile(_ content: GitHubContent, to destination: URL, systemName: String) async throws {
        // Log start of download
        await MainActor.run {
            currentlyDownloadingCount += 1
            let logEntry = CheatDownloadLogEntry(
                timestamp: Date(),
                systemName: systemName,
                fileName: content.name,
                status: .inProgress,
                message: "Downloading \(content.name)..."
            )
            downloadLog.append(logEntry)
        }
        
        // Construct raw file URL using known pattern
        let rawBaseURL = "https://raw.githubusercontent.com/libretro/libretro-database/master/cht/"
        
        // The path from GitHub API includes the "cht/" prefix (e.g., "cht/Nintendo - NES/file.cht")
        // but rawBaseURL already ends with "cht/", so we need to strip it to avoid double "cht/cht/"
        let rawPath = content.safePath
        let relativePath: String
        if rawPath.hasPrefix("cht/") {
            relativePath = String(rawPath.dropFirst(4))
        } else {
            relativePath = rawPath
        }
        
        // Use a restrictive character set that encodes special characters like (), +, ', etc.
        // GitHub's raw server requires these to be URL-encoded
        let allowedCharacters = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~/"))
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? relativePath
        let rawURL = rawBaseURL + encodedPath
        
        // Always use the manually constructed URL since GitHub API's download_url
        // may contain unencoded special characters that cause issues with URLSession
        guard let url = URL(string: rawURL) else {
            cheatDownloadLog.info("Raw download URL construction failed for \(content.name): \(rawURL)")
            await MainActor.run {
                currentlyDownloadingCount -= 1
                // Update the in-progress entry to failed
                if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                    downloadLog[lastIndex] = CheatDownloadLogEntry(
                        timestamp: Date(),
                        systemName: systemName,
                        fileName: content.name,
                        status: .failed("Invalid URL"),
                        message: "Failed: Invalid URL for \(content.name)"
                    )
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("TruchieEmu/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResp = response as? HTTPURLResponse else {
                cheatDownloadLog.info("Failed to download \(content.name): invalid response")
                await MainActor.run {
                    currentlyDownloadingCount -= 1
                    if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                        downloadLog[lastIndex] = CheatDownloadLogEntry(
                            timestamp: Date(),
                            systemName: systemName,
                            fileName: content.name,
                            status: .failed("Invalid response"),
                            message: "Failed: Invalid response for \(content.name)"
                        )
                    }
                }
                return
            }
            
            guard httpResp.statusCode == 200 else {
                cheatDownloadLog.info("Failed to download \(content.name): HTTP \(httpResp.statusCode)")
                await MainActor.run {
                    currentlyDownloadingCount -= 1
                    if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                        downloadLog[lastIndex] = CheatDownloadLogEntry(
                            timestamp: Date(),
                            systemName: systemName,
                            fileName: content.name,
                            status: .failed("HTTP \(httpResp.statusCode)"),
                            message: "Failed: HTTP \(httpResp.statusCode) for \(content.name)"
                        )
                    }
                }
                return
            }
            
            // Verify we got actual data and it's not empty
            guard !data.isEmpty else {
                cheatDownloadLog.info("Failed to download \(content.name): empty data received")
                await MainActor.run {
                    currentlyDownloadingCount -= 1
                    if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                        downloadLog[lastIndex] = CheatDownloadLogEntry(
                            timestamp: Date(),
                            systemName: systemName,
                            fileName: content.name,
                            status: .failed("Empty data"),
                            message: "Failed: Empty data for \(content.name)"
                        )
                    }
                }
                return
            }
            
            // Check if we accidentally got HTML (like a 404 page) instead of a cheat file
            let preview = String(data: data.prefix(50), encoding: .utf8) ?? ""
            if preview.hasPrefix("<!DOCTYPE") || preview.hasPrefix("<html") {
                cheatDownloadLog.info("Failed to download \(content.name): received HTML instead of cheat file")
                await MainActor.run {
                    currentlyDownloadingCount -= 1
                    if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                        downloadLog[lastIndex] = CheatDownloadLogEntry(
                            timestamp: Date(),
                            systemName: systemName,
                            fileName: content.name,
                            status: .failed("HTML response"),
                            message: "Failed: HTML response for \(content.name)"
                        )
                    }
                }
                return
            }
            
            // Use a safe filename by URL-decoding the name and sanitizing
            let safeName = content.name.replacingOccurrences(of: "/", with: "_")
            let destURL = destination.appendingPathComponent(safeName)
            try data.write(to: destURL, options: .atomic)
            
            // Log success
            await MainActor.run {
                currentlyDownloadingCount -= 1
                if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                    downloadLog[lastIndex] = CheatDownloadLogEntry(
                        timestamp: Date(),
                        systemName: systemName,
                        fileName: content.name,
                        status: .success,
                        message: "Successfully downloaded \(content.name)"
                    )
                }
            }
        } catch {
            cheatDownloadLog.error("Failed to download \(content.name): \(error.localizedDescription)")
            await MainActor.run {
                currentlyDownloadingCount -= 1
                if let lastIndex = downloadLog.indices.last, downloadLog[lastIndex].status == .inProgress {
                    downloadLog[lastIndex] = CheatDownloadLogEntry(
                        timestamp: Date(),
                        systemName: systemName,
                        fileName: content.name,
                        status: .failed(error.localizedDescription),
                        message: "Failed: \(error.localizedDescription) for \(content.name)"
                    )
                }
            }
            throw error
        }
    }
    
    // MARK: - Utility Methods
    
    /// Get the total number of downloaded cheat files
    func getDownloadedCheatCount() -> Int {
        var count = 0
        if let enumerator = FileManager.default.enumerator(
            at: localCheatsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "cht" {
                    count += 1
                }
            }
        }
        return count
    }
    
    /// Get the total size of downloaded cheats
    func getDownloadedCheatSize() -> Int64 {
        var totalSize: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: localCheatsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "cht",
                   let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attrs[.size] as? Int64 {
                    totalSize += fileSize
                }
            }
        }
        return totalSize
    }
    
    /// Clear all downloaded cheats
    func clearDownloadedCheats() throws {
        if FileManager.default.fileExists(atPath: localCheatsDirectory.path) {
            try FileManager.default.removeItem(at: localCheatsDirectory)
            lastDownloadDate = nil
            UserDefaults.standard.removeObject(forKey: "cheatLastDownloadDate")
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapSystemIDToFolderName(_ systemID: String) -> String {
        // Map system IDs to libretro cht folder names
        let mapping: [String: String] = [
            "nes": "Nintendo - Nintendo Entertainment System",
            "fds": "Nintendo - Family Computer Disk System",
            "snes": "Nintendo - Super Nintendo Entertainment System",
            "satellaview": "Nintendo - Satellaview",
            "n64": "Nintendo - Nintendo 64",
            "nds": "Nintendo - Nintendo DS",
            "gb": "Nintendo - Game Boy",
            "gba": "Nintendo - Game Boy Advance",
            "gbc": "Nintendo - Game Boy Color",
            "genesis": "Sega - Mega Drive - Genesis",
            "32x": "Sega - 32X",
            "megadrive": "Sega - Mega Drive - Genesis",
            "sms": "Sega - Master System - Mark III",
            "gg": "Sega - Game Gear",
            "saturn": "Sega - Saturn",
            "segacd": "Sega - Mega-CD - Sega CD",
            "dreamcast": "Sega - Dreamcast",
            "psx": "Sony - PlayStation",
            "psone": "Sony - PlayStation",
            "psp": "Sony - PlayStation Portable",
            "fbneo": "FBNeo - Arcade Games",
            "arcade": "FBNeo - Arcade Games",
            "mame": "MAME",
            "prboom": "PrBoom",
            "dos": "DOS",
            "amstrad": "Amstrad - GX4000",
            "gx4000": "Amstrad - GX4000",
            "atari2600": "Atari - 2600",
            "atari5200": "Atari - 5200",
            "atari7800": "Atari - 7800",
            "atari800": "Atari - 8-bit Family",
            "jaguar": "Atari - Jaguar",
            "atarilynx": "Atari - Lynx",
            "chailove": "ChaiLove",
            "colecovision": "Coleco - ColecoVision",
            "intellivision": "Mattel - Intellivision",
            "msx": "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R",
            "msx2": "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R",
            "turbografx16": "NEC - PC Engine - TurboGrafx 16",
            "pce": "NEC - PC Engine - TurboGrafx 16",
            "tg16": "NEC - PC Engine - TurboGrafx 16",
            "turbografxcd": "NEC - PC Engine CD - TurboGrafx-CD",
            "pcecd": "NEC - PC Engine CD - TurboGrafx-CD",
            "supergrafx": "NEC - PC Engine SuperGrafx",
            "sgfx": "NEC - PC Engine SuperGrafx",
            "puzzlescript": "PuzzleScript",
            "spectrum": "Sinclair - ZX Spectrum +3",
            "zxspectrum": "Sinclair - ZX Spectrum +3",
            "tic80": "TIC-80",
            "thomson": "Thomson - MOTO"
        ]
        
        return mapping[systemID.lowercased()] ?? systemID
    }
    
    private func mergeCheats(_ cheats: [Cheat]) -> [Cheat] {
        var cheatByIndex: [Int: Cheat] = [:]
        for cheat in cheats {
            if let existing = cheatByIndex[cheat.index] {
                // Keep the one with a description
                let shouldReplace = !cheat.description.isEmpty && existing.description.isEmpty
                if shouldReplace {
                    cheatByIndex[cheat.index] = cheat
                }
            } else {
                cheatByIndex[cheat.index] = cheat
            }
        }
        return cheatByIndex.values.sorted { $0.index < $1.index }
    }
}

// MARK: - Data Types

/// GitHub API content response
private struct GitHubContent: Decodable {
    let name: String
    let path: String?
    let url: String?
    let htmlUrl: String?
    let downloadUrl: String?
    let sha: String?
    let size: Int?
    let type: ContentType
    
    enum ContentType: String, Decodable {
        case file = "file"
        case directory = "dir"
    }
    
    enum CodingKeys: String, CodingKey {
        case name, path, url, sha, size
        case htmlUrl = "html_url"
        case downloadUrl = "download_url"
        case type
    }
    
    // Custom decoder to handle missing or invalid fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // name is the only truly required field
        self.name = try container.decode(String.self, forKey: .name)
        
        // Make other fields optional with sensible defaults
        self.path = try container.decodeIfPresent(String.self, forKey: .path)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        self.downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
        self.sha = try container.decodeIfPresent(String.self, forKey: .sha)
        self.size = try container.decodeIfPresent(Int.self, forKey: .size)
        
        // Handle missing or invalid type field - infer from name
        if let typeString = try container.decodeIfPresent(String.self, forKey: .type),
           let contentType = ContentType(rawValue: typeString) {
            self.type = contentType
        } else {
            // If type is missing/invalid, try to infer from name
            let parts = self.name.split(separator: ".")
            if parts.count > 1 {
                self.type = .file
            } else {
                self.type = .directory
            }
        }
    }
    
    /// Helper to get url with a fallback default
    var safeUrl: String {
        url ?? ""
    }
    
    /// Helper to get path with a fallback default
    var safePath: String {
        path ?? name
    }
}

/// Result of cheat download operation
enum CheatDownloadResult: Equatable {
    case success(downloaded: Int, failed: Int, message: String)
    case failed(String)
    case alreadyDownloading
}

/// Cheat download errors
enum CheatDownloadError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case fileWriteError
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .fileWriteError:
            return "Failed to write file"
        case .networkError:
            return "Network error"
        }
    }
}
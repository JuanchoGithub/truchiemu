import Foundation

// MARK: - Download Log Entry

// Represents a single download log entry
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

// Downloads cheat files from the libretro-database cheats repository.
// URL: https://github.com/libretro/libretro-database/tree/master/cht
class CheatDownloadService: ObservableObject {
    static let shared = CheatDownloadService()
    
    // MARK: - Published State
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var lastDownloadDate: Date? {
        didSet {
            AppSettings.setDate("cheatLastDownloadDate", value: lastDownloadDate ?? Date())
        }
    }
    
    // MARK: - Download Progress State
    
    // Total number of items to download
    @Published var totalItemsToDownload: Int = 0
    // Number of items currently downloaded
    @Published var currentDownloadedCount: Int = 0
    // Number of items currently being downloaded (in progress)
    @Published var currentlyDownloadingCount: Int = 0
    // Log of all download attempts with their status
    @Published var downloadLog: [CheatDownloadLogEntry] = []
    
    // MARK: - Constants
    
    // Base URL for libretro cheat database
    private let baseURL = "https://github.com/libretro/libretro-database/raw/master/cht"
    
    // Raw API URL for listing files (Contents API)
    private let apiBaseURL = "https://api.github.com/repos/libretro/libretro-database/contents/cht"
    
    // Git Trees API base URL for getting all files in a tree (recursive)
    private let gitTreesBaseURL = "https://api.github.com/repos/libretro/libretro-database/git/trees/master?recursive=1"
    
    // Local directory for downloaded cheats
    private var localCheatsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/cheats_downloaded")
    }
    
    // Directory for a specific system's cheats
    func systemCheatDirectory(for systemID: String) -> URL {
        localCheatsDirectory.appendingPathComponent(systemID)
    }
    
    // MARK: - Initialization
    
    init() {
        loadLastDownloadDate()
    }
    
    private func loadLastDownloadDate() {
        lastDownloadDate = AppSettings.getDate("cheatLastDownloadDate")
    }
    
    // MARK: - Public Methods
    
    // Download all cheat files from libretro database
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
            LoggerService.error(category: "CheatDownloadService", "Failed to create cheats directory: \(error.localizedDescription)")
            return .failed("Could not create local cheats directory")
        }
        
        // Fetch the list of cheat folders/files from GitHub
        downloadStatus = "Fetching cheat index..."
        let gitHubContents: [GitHubContent]
        do {
            gitHubContents = try await fetchGitHubContents(apiBaseURL)
        } catch {
            LoggerService.error(category: "CheatDownloadService", "Failed to fetch GitHub contents: \(error.localizedDescription)")
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
                LoggerService.error(category: "CheatDownloadService", "Failed to download cheats for \(folder.name): \(error.localizedDescription)")
                
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
        LoggerService.info(category: "CheatDownloadService", message)
        return .success(downloaded: totalDownloaded, failed: totalFailed, message: message)
    }
    
    // Download a cheat file for a specific ROM by finding the matching cheat in the libretro-database.
    // Tries the .dat name (metadata.title) first, then falls back to the ROM filename.
    @MainActor
    func downloadCheatForROM(_ rom: ROM, systemID: String) async throws -> Bool {
        LoggerService.info(category: "CheatDownloadService", "=== Starting cheat download for ROM: \(rom.displayName) ===")
        
        guard !isDownloading else {
            LoggerService.warning(category: "CheatDownloadService", "Download already in progress, rejecting request")
            throw CheatDownloadError.alreadyDownloading
        }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Searching for cheat for \(rom.displayName)..."
        downloadLog = []
        currentDownloadedCount = 0
        currentlyDownloadingCount = 0
        totalItemsToDownload = 0
        
        defer {
            isDownloading = false
            currentlyDownloadingCount = 0
            LoggerService.info(category: "CheatDownloadService", "=== Download session ended (isDownloading=false) ===")
        }
        
        // Map system ID to folder name
        let systemFolderName = mapSystemIDToFolderName(systemID)
        let encodedFolderName = systemFolderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? systemFolderName
        let folderURL = apiBaseURL + "/" + encodedFolderName
        
        guard let url = URL(string: folderURL) else {
            LoggerService.error(category: "CheatDownloadService", "Invalid URL constructed: \(folderURL)")
            throw CheatDownloadError.invalidURL
        }
        
        // Fetch contents of the system folder
        downloadStatus = "Searching in \(systemFolderName)..."
        let contents = try await fetchGitHubContents(url.absoluteString)
        
        // Create destination directory
        let destDir = systemCheatDirectory(for: systemID)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Try searching using the .dat name (metadata.title) first, then fall back to ROM filename
        var targetFile: GitHubContent?
        
        // Priority 1: Try the .dat name (from No-Intro identification)
        if let datName = rom.metadata?.title {
            LoggerService.info(category: "CheatDownloadService", "Trying .dat name first: \(datName)")
            downloadStatus = "Looking for cheat file matching: \(datName)"
            targetFile = findMatchingCheatFile(in: contents, romFilename: datName)
            if targetFile != nil {
                LoggerService.info(category: "CheatDownloadService", "Found match using .dat name: \(datName)")
            }
        }
        
        // Priority 2: Fall back to the ROM file name if .dat name didn't match
        if targetFile == nil {
            let romFilename = rom.path.deletingPathExtension().lastPathComponent
            LoggerService.info(category: "CheatDownloadService", "Falling back to ROM filename: \(romFilename)")
            downloadStatus = "Looking for cheat file matching: \(romFilename)"
            targetFile = findMatchingCheatFile(in: contents, romFilename: romFilename)
        }
        
        guard let matchingFile = targetFile else {
            LoggerService.info(category: "CheatDownloadService", "No matching cheat file found for ROM: \(rom.displayName)")
            downloadStatus = "No cheat file found for \(rom.displayName)"
            return false
        }
        
        // Download the matching file
        LoggerService.info(category: "CheatDownloadService", "Downloading cheat file: \(matchingFile.name)")
        downloadStatus = "Downloading \(matchingFile.name)..."
        self.totalItemsToDownload = 1
        self.currentDownloadedCount = 0
        
        try await downloadFile(matchingFile, to: destDir, systemName: systemID)
        self.currentDownloadedCount = 1
        
        downloadProgress = 1.0
        downloadStatus = "Successfully downloaded cheat for \(rom.displayName)"
        lastDownloadDate = Date()
        
        LoggerService.info(category: "CheatDownloadService", "=== Cheat download complete for: \(rom.displayName) ===")
        return true
    }
    
    // Download cheats for a specific system (throws on error, returns count on success)
    @MainActor
    func downloadCheatsForSystem(_ systemID: String) async throws -> Int {
        LoggerService.info(category: "CheatDownloadService", "=== Starting download for system: \(systemID) ===")
        
        guard !isDownloading else {
            LoggerService.warning(category: "CheatDownloadService", "Download already in progress, rejecting request")
            throw CheatDownloadError.alreadyDownloading
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
            LoggerService.info(category: "CheatDownloadService", "=== Download session ended (isDownloading=false) ===")
        }
        
        let systemFolderName = mapSystemIDToFolderName(systemID)
        LoggerService.info(category: "CheatDownloadService", "Mapped system ID '\(systemID)' to folder name: '\(systemFolderName)'")
        
        let encodedFolderName = systemFolderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? systemFolderName
        let folderURL = apiBaseURL + "/" + encodedFolderName
        LoggerService.info(category: "CheatDownloadService", "GitHub API URL: \(folderURL)")
        
        guard let url = URL(string: folderURL) else {
            LoggerService.error(category: "CheatDownloadService", "Invalid URL constructed: \(folderURL)")
            throw CheatDownloadError.invalidURL
        }
        
        // Count total files first
        LoggerService.info(category: "CheatDownloadService", "Counting cheat files in folder...")
        self.totalItemsToDownload = await countCheatFilesInFolder(url, maxDepth: 1)
        LoggerService.info(category: "CheatDownloadService", "Found \(self.totalItemsToDownload) cheat files for \(systemID)")
        downloadStatus = "Found \(self.totalItemsToDownload) cheat files for \(systemID)"
        
        // Download from main folder
        LoggerService.info(category: "CheatDownloadService", "Downloading cheats from main folder...")
        var totalDownloaded = try await downloadCheatsFromFolder(url, to: systemCheatDirectory(for: systemID), systemName: systemID)
        LoggerService.info(category: "CheatDownloadService", "Downloaded \(totalDownloaded) files from main folder")
        
        // Check for subdirectories and download them too
        LoggerService.info(category: "CheatDownloadService", "Checking for subdirectories...")
        let contents = try await fetchGitHubContents(url.absoluteString)
        let subDirs = contents.filter { $0.type == .directory }
        LoggerService.info(category: "CheatDownloadService", "Found \(subDirs.count) subdirectories")
        
        for item in subDirs {
            LoggerService.info(category: "CheatDownloadService", "Processing subdirectory: \(item.name)")
            let encodedItemName = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.name
            let subFolderURL = "\(url.absoluteString)/\(encodedItemName)"
            if let subURL = URL(string: subFolderURL) {
                let subCount = try await downloadCheatsFromFolder(subURL, to: systemCheatDirectory(for: systemID), systemName: systemID)
                LoggerService.info(category: "CheatDownloadService", "Downloaded \(subCount) files from subdirectory: \(item.name)")
                totalDownloaded += subCount
            }
        }
        
        LoggerService.info(category: "CheatDownloadService", "=== Download complete: \(totalDownloaded) total files ===")
        lastDownloadDate = Date()
        return totalDownloaded
    }
    
    // MARK: - ROM Cheat Lookup
    
    // Find cheats for a specific ROM by searching downloaded cheat files
    func findCheatsForROM(_ rom: ROM) -> [CheatFile] {
        let romFilename = rom.path.deletingPathExtension().lastPathComponent
        var foundFiles: [CheatFile] = []
        let romNormalizedKey = GameNameFormatter.normalizedComparisonKey(romFilename)
        
        // Search in downloaded cheats directory
        let romCheatsDirName = romFilename
        
        // Look for matching .cht files
        if let enumerator = FileManager.default.enumerator(
            at: localCheatsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                let filenameLower = filename.lowercased()
                let fileNormalizedKey = GameNameFormatter.normalizedComparisonKey(filename)
                let romFilenameLower = romFilename.lowercased()
                
                // Match by exact, contains, or space-removed comparison
                let isMatch = filenameLower == romFilenameLower ||
                              romCheatsDirName.lowercased().contains(filenameLower) ||
                              filenameLower.contains(romFilenameLower) ||
                              fileNormalizedKey == romNormalizedKey
                
                if isMatch {
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
    
    // Fetch directory contents from GitHub API.
    // Uses the Git Trees API for directories that may have >1000 files (like NES cheats),
    // since the Contents API is limited to 1000 results.
    private func fetchGitHubContents(_ urlString: String) async throws -> [GitHubContent] {
        // Check if this is the cheats base directory or a system subdirectory
        // These directories have >1000 files, so we use the Git Trees API
        if urlString.contains("/contents/cht") || urlString.hasPrefix(apiBaseURL) {
            return try await fetchUsingGitTreesAPI(urlString)
        }
        
        // For other directories, use the standard Contents API
        return try await fetchUsingContentsAPI(urlString)
    }
    
    // Fetch using the Git Trees API (returns all files, no pagination limit)
    // Integrates with ResourceCacheInterceptor for cache-first fetching with ETag/304 support.
    private func fetchUsingGitTreesAPI(_ urlString: String) async throws -> [GitHubContent] {
        LoggerService.info(category: "CheatDownloadService", "Using Git Trees API for: \(urlString)")
        
        // Extract the system folder name from the URL
        // URL format: https://api.github.com/repos/libretro/libretro-database/contents/cht/[SystemName]
        // or: https://api.github.com/repos/libretro/libretro-database/contents/cht
        let systemFolderName: String
        if urlString.hasSuffix("/cht") || urlString.hasSuffix("%2Fcht") {
            // This is the root cht directory - return system folders
            systemFolderName = ""
        } else {
            // Extract system folder name
            let components = urlString.components(separatedBy: "/")
            if let lastComponent = components.last, !lastComponent.isEmpty {
                systemFolderName = lastComponent.removingPercentEncoding ?? lastComponent
            } else if let secondToLast = components.dropLast().last {
                systemFolderName = secondToLast.removingPercentEncoding ?? secondToLast
            } else {
                systemFolderName = ""
            }
        }
        
        let cacheKey = ResourceCacheEntry.makeCheatManifestKey(systemFolder: systemFolderName)
        
        // Use ResourceCacheInterceptor for cache-first fetch
        let data: Data
        do {
            let result = try await ResourceCacheInterceptor.shared.fetchWithCache(
                url: URL(string: gitTreesBaseURL)!,
                type: .cheatManifest,
                cacheKey: cacheKey,
                expiry: .short  // 1 hour — directory listings change rarely
            )
            data = result.data
        } catch {
            LoggerService.warning(category: "CheatDownloadService", "Git Trees API fetch failed via cache interceptor: \(error.localizedDescription)")
            throw CheatDownloadError.networkError
        }
        
        let decoder = JSONDecoder()
        
        do {
            let treesResponse = try decoder.decode(GitTreesResponse.self, from: data)
            var result: [GitHubContent] = []
            
            guard treesResponse.sha != nil else {
                throw CheatDownloadError.invalidResponse
            }
            
            if systemFolderName.isEmpty {
                // Root cht directory - return system folders
                let pathPrefix = "cht/"
                var seenFolders: Set<String> = []
                
                for treeItem in treesResponse.tree where treeItem.path.hasPrefix(pathPrefix) {
                    let remainingPath = String(treeItem.path.dropFirst(pathPrefix.count))
                    if let firstSlash = remainingPath.firstIndex(of: "/") {
                        let folderName = String(remainingPath[..<firstSlash])
                        if seenFolders.insert(folderName).inserted {
                            // Extract URL for this folder
                            let folderPath = "cht/\(folderName)"
                            let folderURL = "https://api.github.com/repos/libretro/libretro-database/contents/\(folderPath)?ref=master"
                            let content = GitHubContent(name: folderName, path: folderPath, url: folderURL, htmlUrl: nil, downloadUrl: nil, sha: nil, size: nil, type: GitHubContent.ContentType.directory)
                            result.append(content)
                        }
                    }
                }
            } else {
                // System subdirectory - return files in that system
                let pathPrefix = "cht/\(systemFolderName)/"
                
                for treeItem in treesResponse.tree where treeItem.path.hasPrefix(pathPrefix) {
                    let remainingPath = String(treeItem.path.dropFirst(pathPrefix.count))
                    // Only include direct children (no subdirectories for now, unless needed)
                    if !remainingPath.contains("/") && treeItem.path.hasSuffix(".cht") {
                        let filePath = treeItem.path
                        let downloadURL = "https://raw.githubusercontent.com/libretro/libretro-database/master/\(filePath)"
                        let content = GitHubContent(
                            name: remainingPath,
                            path: filePath,
                            url: "https://api.github.com/repos/libretro/libretro-database/contents/\(filePath)?ref=master",
                            htmlUrl: nil,
                            downloadUrl: downloadURL,
                            sha: treeItem.sha,
                            size: nil,
                            type: .file
                        )
                        result.append(content)
                    }
                }
            }
            
            LoggerService.info(category: "CheatDownloadService", "Git Trees API returned \(result.count) items for: \(systemFolderName)")
            return result
            
        } catch let decodeError as DecodingError {
            LoggerService.error(category: "CheatDownloadService", "JSON decode error: \(decodeError)")
            throw CheatDownloadError.invalidResponse
        }
    }
    
    // Standard Contents API fetch (for directories with <1000 files)
    private func fetchUsingContentsAPI(_ urlString: String) async throws -> [GitHubContent] {
        guard let url = URL(string: urlString) else {
            throw CheatDownloadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("TruchieEmu/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CheatDownloadError.invalidResponse
        }
        
        if httpResponse.statusCode == 403 {
            LoggerService.warning(category: "CheatDownloadService", "GitHub API rate limit reached for: \(urlString)")
            return []
        }
        
        if httpResponse.statusCode == 404 {
            return []
        }
        
        if httpResponse.statusCode != 200 {
            throw CheatDownloadError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode([GitHubContent].self, from: data)
    }
    
    // Count total cheat files across all system folders
    private func countTotalCheatFiles(in systemFolders: [GitHubContent]) async -> Int {
        var totalCount = 0
        for folder in systemFolders {
            guard !folder.safeUrl.isEmpty else { continue }
            totalCount += await countCheatFilesInFolder(URL(string: folder.safeUrl)!, maxDepth: 2)
        }
        return totalCount
    }
    
    // Count cheat files in a folder (with depth limit to prevent excessive recursion)
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
    
    // Download cheat files from a system folder
    private func downloadSystemCheats(_ folder: GitHubContent, systemName: String) async throws -> Int {
        let destDir = localCheatsDirectory.appendingPathComponent(folder.name)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Fetch contents of the folder using safe url accessor
        let folderURL = folder.safeUrl
        guard !folderURL.isEmpty else {
            LoggerService.warning(category: "CheatDownloadService", "Folder \(folder.name) has no URL, skipping")
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
    
    // Download cheat files from a specific folder URL
    private func downloadCheatsFromFolder(_ url: URL, to destination: URL, systemName: String = "Unknown") async throws -> Int {
        LoggerService.info(category: "CheatDownloadService", "Downloading from folder: \(url.absoluteString)")
        LoggerService.info(category: "CheatDownloadService", "Destination: \(destination.path)")
        
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        
        let contents = try await fetchGitHubContents(url.absoluteString)
        let chtFiles = contents.filter { $0.type == .file && $0.name.hasSuffix(".cht") }
        LoggerService.info(category: "CheatDownloadService", "Found \(chtFiles.count) .cht files in folder")
        
        var downloaded = 0
        for item in chtFiles {
            LoggerService.info(category: "CheatDownloadService", "Downloading file: \(item.name)")
            try await downloadFile(item, to: destination, systemName: systemName)
            await MainActor.run {
                currentDownloadedCount += 1
            }
            downloaded += 1
        }
        
        LoggerService.info(category: "CheatDownloadService", "Downloaded \(downloaded) files from folder")
        return downloaded
    }
    
    // Download a single file
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
            LoggerService.info(category: "CheatDownloadService", "Raw download URL construction failed for \(content.name): \(rawURL)")
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
                LoggerService.info(category: "CheatDownloadService", "Failed to download \(content.name): invalid response")
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
                LoggerService.info(category: "CheatDownloadService", "Failed to download \(content.name): HTTP \(httpResp.statusCode)")
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
                LoggerService.info(category: "CheatDownloadService", "Failed to download \(content.name): empty data received")
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
                LoggerService.info(category: "CheatDownloadService", "Failed to download \(content.name): received HTML instead of cheat file")
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
            LoggerService.error(category: "CheatDownloadService", "Failed to download \(content.name): \(error.localizedDescription)")
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
    
    // Get the total number of downloaded cheat files
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
    
    // Get the total size of downloaded cheats
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
    
    // Clear all downloaded cheats
    func clearDownloadedCheats() throws {
        if FileManager.default.fileExists(atPath: localCheatsDirectory.path) {
            try FileManager.default.removeItem(at: localCheatsDirectory)
            lastDownloadDate = nil
            AppSettings.removeObject("cheatLastDownloadDate")
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
    
    // Find a matching cheat file for a given ROM filename.
    // Looks for exact match first, then partial matches, then space-removed matches.
    private func findMatchingCheatFile(in contents: [GitHubContent], romFilename: String) -> GitHubContent? {
        let chtFiles = contents.filter { $0.type == .file && $0.name.hasSuffix(".cht") }
        
        // Normalize the ROM filename for comparison
        let romFilenameLower = romFilename.lowercased()
        let romFilenameNoBracket = removeBracketsAndParentheses(romFilenameLower)
        
        // 1. Check for exact match (ignoring .cht extension)
        for file in chtFiles {
            let fileBaseName = String(file.name.dropLast(4)).lowercased() // Remove ".cht"
            if fileBaseName == romFilenameLower {
                LoggerService.info(category: "CheatDownloadService", "Found exact match: \(file.name)")
                return file
            }
        }
        
        // 2. Check for exact match ignoring brackets and special characters
        for file in chtFiles {
            let fileBaseName = String(file.name.dropLast(4)).lowercased() // Remove ".cht"
            let fileNoBracket = removeBracketsAndParentheses(fileBaseName)
            if fileNoBracket == romFilenameNoBracket {
                LoggerService.info(category: "CheatDownloadService", "Found match (ignoring brackets): \(file.name)")
                return file
            }
        }
        
        // 3. Check for partial match - file name contains ROM name or vice versa
        for file in chtFiles {
            let fileBaseName = String(file.name.dropLast(4)).lowercased() // Remove ".cht"
            let fileNoBracket = removeBracketsAndParentheses(fileBaseName)
            if fileNoBracket.contains(romFilenameNoBracket) || romFilenameNoBracket.contains(fileNoBracket) {
                // Only accept if the shorter name is at least 4 characters to avoid false matches
                let shorterLength = min(fileNoBracket.count, romFilenameNoBracket.count)
                if shorterLength >= 4 {
                    LoggerService.info(category: "CheatDownloadService", "Found partial match: \(file.name) for \(romFilename)")
                    return file
                }
            }
        }
        
        // 4. Check for match with spaces removed (e.g., "ShadowRun" vs "Shadow Run")
        let romNoSpaces = GameNameFormatter.normalizedComparisonKey(romFilenameNoBracket)
        for file in chtFiles {
            let fileBaseName = String(file.name.dropLast(4)).lowercased() // Remove ".cht"
            let fileNoBracket = removeBracketsAndParentheses(fileBaseName)
            let fileNoSpaces = GameNameFormatter.normalizedComparisonKey(fileNoBracket)
            if fileNoSpaces == romNoSpaces {
                LoggerService.info(category: "CheatDownloadService", "Found match (spaces removed): \(file.name) for \(romFilename)")
                return file
            }
        }
        
        LoggerService.info(category: "CheatDownloadService", "No matching cheat file found for: \(romFilename)")
        return nil
    }
    
    // Remove brackets, parentheses and their contents from a string
    private func removeBracketsAndParentheses(_ str: String) -> String {
        var result = str
        // Remove content in parentheses: (USA), (Europe), etc.
        var inParens = false
        var temp = ""
        for char in result {
            if char == "(" {
                inParens = true
            } else if char == ")" {
                inParens = false
            } else if !inParens {
                temp.append(char)
            }
        }
        result = temp
        
        // Remove content in brackets: [!], [b1], etc.
        var inBrackets = false
        temp = ""
        for char in result {
            if char == "[" {
                inBrackets = true
            } else if char == "]" {
                inBrackets = false
            } else if !inBrackets {
                temp.append(char)
            }
        }
        result = temp.trimmingCharacters(in: .whitespaces)
        
        return result
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

// GitHub API content response
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
    
    // Public initializer for creating GitHubContent from Git Trees API
    init(name: String, path: String?, url: String?, htmlUrl: String?, downloadUrl: String?, sha: String?, size: Int?, type: ContentType) {
        self.name = name
        self.path = path
        self.url = url
        self.htmlUrl = htmlUrl
        self.downloadUrl = downloadUrl
        self.sha = sha
        self.size = size
        self.type = type
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
    
    // Safer accessors for optional fields used in logic
    var safeUrl: String { url ?? "" }
    var safePath: String { path ?? name }
}

// Result of cheat download operation
enum CheatDownloadResult: Equatable {
    case success(downloaded: Int, failed: Int, message: String)
    case failed(String)
    case alreadyDownloading
}

// Cheat download errors
enum CheatDownloadError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case fileWriteError
    case networkError
    case alreadyDownloading
    
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
        case .alreadyDownloading:
            return "A download is already in progress"
        }
    }
}

// MARK: - Timeout Support

// Error thrown when an operation exceeds the specified time limit
struct TimeoutError: Error, LocalizedError {
    let seconds: TimeInterval
    
    var errorDescription: String? {
        return "Operation timed out after \(Int(seconds)) seconds"
    }
}

// Executes an async operation with a timeout. Throws TimeoutError if the operation doesn't complete in time.
func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Start the actual operation
        group.addTask {
            return try await operation()
        }
        
        // Start the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError(seconds: seconds)
        }
        
        // Return the first result (either operation completes or timeout fires)
        let result = try await group.next()!
        
        // Cancel the remaining task
        group.cancelAll()
        
        return result
    }
}
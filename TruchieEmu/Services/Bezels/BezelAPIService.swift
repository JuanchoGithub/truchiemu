import Foundation
import AppKit

// MARK: - Download Log Entry

struct BezelDownloadLogEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let fileName: String
    let systemID: String
    let timestamp: Date
    let duration: TimeInterval?
    let status: DownloadStatus
    
    enum DownloadStatus: Equatable, Codable {
        case inProgress
        case success
        case failed(String)
        
        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
        
        var errorMessage: String? {
            if case .failed(let msg) = self { return msg }
            return nil
        }
    }
    
    init(
        id: UUID = UUID(),
        fileName: String,
        systemID: String = "",
        timestamp: Date = Date(),
        duration: TimeInterval? = nil,
        status: DownloadStatus
    ) {
        self.id = id
        self.fileName = fileName
        self.systemID = systemID
        self.timestamp = timestamp
        self.duration = duration
        self.status = status
    }
    
    var displayDuration: String {
        guard let duration else { return "" }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        return String(format: "%.1fs", duration)
    }
}

// MARK: - UserDefaults Keys for Download Log

enum BezelDownloadUserDefaultsKeys {
    static let downloadLog = "BezelDownloadLog"
}

// MARK: - Bezel Download Service (Progress Tracking)

@MainActor
class BezelDownloadProgress: ObservableObject {
    @Published var isRunning = false
    @Published var currentDownloadedCount = 0
    @Published var totalItemsToDownload = 0
    @Published var downloadStatus = ""
    @Published var downloadLog: [BezelDownloadLogEntry] = []
    @Published var currentlyDownloadingCount = 0
    
    /// The system currently being downloaded (for display purposes)
    @Published var currentSystemID: String = ""
    /// Total bezels downloaded across all sessions
    var totalDownloadedCount: Int {
        downloadLog.filter { $0.status.isSuccess }.count
    }
    
    var progress: Double {
        guard totalItemsToDownload > 0 else { return 0 }
        return Double(currentDownloadedCount) / Double(totalItemsToDownload)
    }
    
    var lastDownloadDate: Date? {
        downloadLog.last { $0.status.isSuccess }?.timestamp
    }
    
    init() {
        loadPersistentLog()
    }
    
    func reset() {
        currentDownloadedCount = 0
        totalItemsToDownload = 0
        downloadStatus = ""
        currentlyDownloadingCount = 0
        currentSystemID = ""
        isRunning = false
        // Don't clear downloadLog - it persists
    }
    
    func resetLog() {
        downloadLog = []
        saveLog()
    }
    
    func addLogEntry(_ entry: BezelDownloadLogEntry) {
        downloadLog.append(entry)
        // Keep log manageable
        if downloadLog.count > 500 {
            downloadLog = Array(downloadLog.suffix(200))
        }
        saveLog()
    }
    
    /// Save download log to UserDefaults for persistence
    private func saveLog() {
        if let encoded = try? JSONEncoder().encode(downloadLog) {
            UserDefaults.standard.set(encoded, forKey: BezelDownloadUserDefaultsKeys.downloadLog)
        }
    }
    
    /// Load download log from UserDefaults
    private func loadPersistentLog() {
        if let data = UserDefaults.standard.data(forKey: BezelDownloadUserDefaultsKeys.downloadLog),
           let entries = try? JSONDecoder().decode([BezelDownloadLogEntry].self, from: data) {
            // Only keep last 200 entries
            downloadLog = Array(entries.suffix(200))
        }
    }
    
    /// Cancel the current download
    func cancelDownload() {
        isRunning = false
        downloadStatus = "Download cancelled"
        addLogEntry(BezelDownloadLogEntry(
            fileName: "Download cancelled",
            systemID: currentSystemID,
            status: .failed("User cancelled download")
        ))
    }
}

// MARK: - Bezel API Service

/// Handles communication with The Bezel Project's GitHub repositories.
/// Fetches manifests (directory listings) and downloads bezel files.
@MainActor
class BezelAPIService: ObservableObject {
    static let shared = BezelAPIService()
    
    @Published var progressTracker = BezelDownloadProgress()
    
    /// URLSession for downloads (with reasonable timeout)
    private var urlSession: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Manifest Fetching
    
    /// Fetch the manifest (list of available bezels) from GitHub API for a system.
    /// Uses the Git Trees API to get ALL files without pagination limits.
    func fetchManifest(systemID: String) async throws -> [BezelEntry] {
        guard let config = BezelSystemMapping.config(for: systemID) else {
            throw BezelError.systemNotSupported(systemID)
        }
        
        let url = config.treesAPIURL
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("TruchieEmu/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200:
                    break // OK
                case 403:
                    throw BezelError.apiRateLimited
                case 404:
                    throw BezelError.systemNotFound(systemID)
                default:
                    throw BezelError.apiError(httpResponse.statusCode)
                }
            }
            
            // Parse Git Trees API response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tree = json["tree"] as? [[String: Any]] else {
                throw BezelError.parseError
            }
            
            var entries: [BezelEntry] = []
            let bezelPath = config.bezelDirectoryPath
            
            for item in tree {
                guard let path = item["path"] as? String,
                      item["type"] as? String == "blob",
                      path.lowercased().hasPrefix(bezelPath.lowercased()),
                      path.lowercased().hasSuffix(".png") else {
                    continue
                }
                
                // Extract just the filename from the path
                let filename = (path as NSString).lastPathComponent
                let id = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                
                // Construct the raw download URL
                let rawURL = config.githubRawURL.appendingPathComponent(filename)
                
                let entry = BezelEntry(
                    id: id,
                    filename: filename,
                    rawURL: rawURL,
                    localURL: nil
                )
                entries.append(entry)
            }
            
            // Sort entries alphabetically by display name
            entries.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            
            // Update local URLs for already-downloaded files
            let storageManager = BezelStorageManager.shared
            try? storageManager.ensureDirectoriesExist()
            
            for i in entries.indices {
                let localPath = storageManager.bezelFilePath(
                    systemID: systemID,
                    gameName: entries[i].id
                )
                if FileManager.default.fileExists(atPath: localPath.path) {
                    entries[i].localURL = localPath
                }
            }
            
            // Cache the manifest
            try cacheManifest(entries, for: systemID)
            
            return entries
            
        } catch let bezelError as BezelError {
            throw bezelError
        } catch {
            throw BezelError.networkError(error)
        }
    }
    
    /// Get cached manifest for a system.
    func cachedManifest(systemID: String) -> BezelManifest? {
        let storageManager = BezelStorageManager.shared
        let cachePath = storageManager.manifestCachePath(for: systemID)
        
        guard let data = try? Data(contentsOf: cachePath) else { return nil }
        return try? JSONDecoder().decode(BezelManifest.self, from: data)
    }
    
    /// Fetch manifest, using cache if available and not stale.
    func getManifest(systemID: String) async throws -> [BezelEntry] {
        // Try cache first
        if let manifest = cachedManifest(systemID: systemID), !manifest.isStale {
            // Update local URLs
            return updateLocalURLs(manifest.entries, systemID: systemID)
        }
        
        // Fetch from API
        return try await fetchManifest(systemID: systemID)
    }
    
    /// Cache a manifest to disk.
    private func cacheManifest(_ entries: [BezelEntry], for systemID: String) throws {
        let storageManager = BezelStorageManager.shared
        let cachePath = storageManager.manifestCachePath(for: systemID)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: cachePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let manifest = BezelManifest(
            systemID: systemID,
            lastFetched: Date(),
            entries: entries
        )
        
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: cachePath, options: .atomic)
    }
    
    /// Update local URLs for entries that are already downloaded.
    private func updateLocalURLs(_ entries: [BezelEntry], systemID: String) -> [BezelEntry] {
        let storageManager = BezelStorageManager.shared
        
        return entries.map { entry in
            var updated = entry
            let localPath = storageManager.bezelFilePath(
                systemID: systemID,
                gameName: entry.id
            )
            if FileManager.default.fileExists(atPath: localPath.path) {
                updated = BezelEntry(
                    id: entry.id,
                    filename: entry.filename,
                    rawURL: entry.rawURL,
                    localURL: localPath
                )
            }
            return updated
        }
    }
    
    // MARK: - Single Bezel Download
    
    /// Download a single bezel file.
    func downloadBezel(systemID: String, entry: BezelEntry) async throws -> URL {
        let storageManager = BezelStorageManager.shared
        try storageManager.ensureDirectoriesExist()
        
        let destinationURL = storageManager.bezelFilePath(
            systemID: systemID,
            gameName: entry.id
        )
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        // Download to temp file first
        let (tempURL, response) = try await urlSession.download(from: entry.rawURL)
        
        // Verify response
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                throw BezelError.downloadFailed(entry.filename, httpResponse.statusCode)
            }
        }
        
        // Verify it's an image (check content type or file extension)
        let tempData = try Data(contentsOf: tempURL)
        guard isValidPNG(data: tempData) else {
            throw BezelError.invalidFileFormat(entry.filename)
        }
        
        // Move to final location
        try? FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        return destinationURL
    }
    
    /// Check if data is a valid PNG file.
    private func isValidPNG(data: Data) -> Bool {
        // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
        return data.count >= 8 &&
               data[0] == 0x89 &&
               data[1] == 0x50 &&
               data[2] == 0x4E &&
               data[3] == 0x47 &&
               data[4] == 0x0D &&
               data[5] == 0x0A &&
               data[6] == 0x1A &&
               data[7] == 0x0A
    }
    
    // MARK: - Batch Download
    
    /// Download all bezels for a system.
    /// - Returns: Number of successfully downloaded bezels.
    func downloadAllBezels(systemID: String) async -> (success: Int, failed: Int, message: String) {
        // Check if already running
        guard !progressTracker.isRunning else {
            return (0, 0, "Download already in progress")
        }
        
        progressTracker.reset()
        progressTracker.isRunning = true
        progressTracker.currentSystemID = systemID
        progressTracker.downloadStatus = "Fetching manifest for \(systemID)..."
        
        // Log the start of download
        progressTracker.addLogEntry(BezelDownloadLogEntry(
            fileName: "Started downloading \(systemID) bezels",
            systemID: systemID,
            status: .inProgress
        ))
        
        var successCount = 0
        var failedCount = 0
        
        defer {
            progressTracker.isRunning = false
        }
        
        // Fetch manifest
        let entries: [BezelEntry]
        do {
            entries = try await fetchManifest(systemID: systemID)
        } catch {
            progressTracker.downloadStatus = "Failed to fetch manifest: \(error.localizedDescription)"
            progressTracker.addLogEntry(BezelDownloadLogEntry(
                fileName: "Failed to fetch manifest",
                systemID: systemID,
                status: .failed(error.localizedDescription)
            ))
            return (0, 0, "Failed to fetch manifest: \(error.localizedDescription)")
        }
        
        let total = entries.count
        progressTracker.totalItemsToDownload = total
        progressTracker.downloadStatus = "Downloading \(total) bezel(s) for \(systemID)..."
        
        // Download bezels in batches to avoid overwhelming the network
        let batchSize = 3
        let entryGroups = entries.chunked(into: batchSize)
        
        for group in entryGroups {
            guard progressTracker.isRunning else { break }
            
            await withTaskGroup(of: (Bool, String, TimeInterval?).self) { groupTask in
                for entry in group {
                    progressTracker.currentlyDownloadingCount += 1
                    
                    groupTask.addTask {
                        let entryName = entry.filename
                        let startTime = Date()
                        do {
                            _ = try await self.downloadBezel(
                                systemID: systemID,
                                entry: entry
                            )
                            let duration = Date().timeIntervalSince(startTime)
                            await MainActor.run {
                                self.progressTracker.addLogEntry(BezelDownloadLogEntry(
                                    fileName: entryName,
                                    systemID: systemID,
                                    duration: duration,
                                    status: .success
                                ))
                            }
                            return (true, entryName, duration)
                        } catch {
                            let duration = Date().timeIntervalSince(startTime)
                            await MainActor.run {
                                self.progressTracker.addLogEntry(BezelDownloadLogEntry(
                                    fileName: entryName,
                                    systemID: systemID,
                                    duration: duration,
                                    status: .failed(error.localizedDescription)
                                ))
                            }
                            return (false, entryName, duration)
                        }
                    }
                }
                
                for await (success, _, _) in groupTask {
                    await MainActor.run {
                        progressTracker.currentlyDownloadingCount -= 1
                        if success {
                            successCount += 1
                        } else {
                            failedCount += 1
                        }
                        progressTracker.currentDownloadedCount = successCount + failedCount
                        progressTracker.downloadStatus = "Downloaded \(progressTracker.currentDownloadedCount)/\(total)..."
                    }
                }
            }
        }
        
        let message = "Downloaded \(successCount) bezel(s) for \(systemID)" + (failedCount > 0 ? ", \(failedCount) failed" : "")
        progressTracker.downloadStatus = message
        
        // Log completion
        progressTracker.addLogEntry(BezelDownloadLogEntry(
            fileName: "Completed \(systemID): \(successCount) success, \(failedCount) failed",
            systemID: systemID,
            status: .success
        ))
        
        return (successCount, failedCount, message)
    }
    
    /// Download bezels for all supported systems.
    func downloadAllSystems() async -> (success: Int, failed: Int, message: String) {
        var totalSuccess = 0
        var totalFailed = 0
        var systemFailures: [String] = []
        
        progressTracker.reset()
        progressTracker.isRunning = true
        
        let supportedSystems = BezelSystemMapping.configurations.keys.sorted()
        progressTracker.totalItemsToDownload = supportedSystems.count
        
        for systemID in supportedSystems {
            guard progressTracker.isRunning else { break }
            
            progressTracker.downloadStatus = "Processing \(systemID)..."
            
            let (_, systemFailed, _) = await downloadAllBezels(systemID: systemID)
            
            if systemFailed > 0 {
                systemFailures.append(systemID)
            }
            totalFailed += systemFailed
            totalSuccess += progressTracker.currentDownloadedCount - totalFailed + totalSuccess
            
            progressTracker.currentDownloadedCount += 1
        }
        
        progressTracker.isRunning = false
        
        let message = "Complete: \(totalSuccess) bezels from \(supportedSystems.count) systems" +
                     (systemFailures.isEmpty ? "" : ", \(systemFailures.count) systems had failures")
        
        return (totalSuccess, totalFailed, message)
    }
    
    /// Get the count of downloaded bezel PNG files.
    func getDownloadedBezelCount(for systemID: String) -> Int {
        let storageManager = BezelStorageManager.shared
        let systemDir = storageManager.systemBezelsDirectory(for: systemID)
        
        guard FileManager.default.fileExists(atPath: systemDir.path) else { return 0 }
        
        var count = 0
        if let enumerator = FileManager.default.enumerator(at: systemDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "png" {
                    count += 1
                }
            }
        }
        
        return count
    }
}

// MARK: - Bezel Errors

enum BezelError: LocalizedError {
    case systemNotSupported(String)
    case systemNotFound(String)
    case apiRateLimited
    case apiError(Int)
    case parseError
    case downloadFailed(String, Int)
    case invalidFileFormat(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .systemNotSupported(let id):
            return "System '\(id)' is not supported by The Bezel Project"
        case .systemNotFound(let id):
            return "Bezel repository for '\(id)' not found"
        case .apiRateLimited:
            return "GitHub API rate limit reached. Try again later."
        case .apiError(let code):
            return "GitHub API error: \(code)"
        case .parseError:
            return "Failed to parse manifest data"
        case .downloadFailed(let name, let code):
            return "Failed to download '\(name)' (HTTP \(code))"
        case .invalidFileFormat(let name):
            return "'\(name)' is not a valid PNG file"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Array.chunked

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var currentIndex = 0
        
        while currentIndex < count {
            let endIndex = Swift.min(currentIndex + size, count)
            chunks.append(Array(self[currentIndex..<endIndex]))
            currentIndex = endIndex
        }
        
        return chunks
    }
}
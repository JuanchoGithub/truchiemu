import Foundation
import Combine
import Darwin
import AppKit
import SwiftData

enum CoreDownloadPhase: Equatable {
    case idle
    case findingURL
    case fetchingFromURL
    case downloading(progress: Double)
    case installing
}


class BiosDownloader {
    
    // The path inside the ZIP: dolphin-master/Data/Sys/

    //create a distributor function that will call the appropriate download function based on the coreID
    func downloadAndExtractBios(for coreID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if coreID == "dolphin_libretro" {
            downloadAndExtractDolphinBios(completion: completion)
        }
    }

    func deleteCore(coreID: String) {
        if coreID == "dolphin_libretro" {
            deleteDolphinBios(coreID: coreID)
        }
    }

    func deleteDolphinBios(coreID: String) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipFileLocation = tempDir.appendingPathComponent("repo.zip")
        let destinationFolder = getAppSupportDirectory().appendingPathComponent("System/dolphin-emu/Sys")
        //delete the destination folder
        try? fileManager.removeItem(at: destinationFolder)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Deleted support Sys folder for: \(coreID) at \(destinationFolder)")
        #endif
        //delete the zip file
        try? fileManager.removeItem(at: zipFileLocation)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Deleted zip file for: \(coreID) at \(zipFileLocation)")
        #endif
    }
    
    func downloadAndExtractDolphinBios(completion: @escaping (Result<Void, Error>) -> Void) {
        let repoZipURL = URL(string: "https://github.com/dolphin-emu/dolphin/archive/refs/heads/master.zip")!
        let targetSubPath = "dolphin-master/Data/Sys"
        let fileManager = FileManager.default
        
        // 1. Setup Paths
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let zipFileLocation = tempDir.appendingPathComponent("repo.zip")
        let destinationFolder = getAppSupportDirectory().appendingPathComponent("System/dolphin-emu/Sys")
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // 2. Download the Zip file
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Downloading repository...")
            #endif
            let semaphore = DispatchSemaphore(value: 0)
            var downloadError: Error?
            
            let task = URLSession.shared.downloadTask(with: repoZipURL) { localURL, _, error in
                if let error = error {
                    downloadError = error
                } else if let localURL = localURL {
                    do {
                        // Move downloaded file to our controlled temp location
                        if fileManager.fileExists(atPath: zipFileLocation.path) {
                            try fileManager.removeItem(at: zipFileLocation)
                        }
                        try fileManager.moveItem(at: localURL, to: zipFileLocation)
                    } catch {
                        downloadError = error
                    }
                }
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()
            
            if let error = downloadError {
                completion(.failure(error))
                return
            }
            
            // 3. Use the system 'unzip' utility
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Running system unzip...")
            #endif
            try runUnzip(zipPath: zipFileLocation.path, destination: tempDir.path)
            
            // 4. Move files from the specific subfolder to the destination
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Moving files to application support...")
            #endif
            try moveSysFiles(from: tempDir.appendingPathComponent(targetSubPath), to: destinationFolder)
            
            // 5. Cleanup
            try? fileManager.removeItem(at: tempDir)
            
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Finished successfully.")
            #endif
            completion(.success(()))
            
        } catch {
            LoggerService.error(category: "CoreManager", "Failed to download and extract BIOS: \(error)")
            completion(.failure(error))
        }
    }
    
    // Executes the shell command: unzip <path> -d <destination>
    private func runUnzip(zipPath: String, destination: String) throws {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = [zipPath, "-d", destination]
        process.standardError = pipe // Capture errors
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown unzip error"
            LoggerService.error(category: "CoreManager", "Unzip error: \(errorMsg)")
            throw NSError(domain: "UnzipError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    private func moveSysFiles(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure destination exists
        if !fileManager.fileExists(atPath: destination.path) {
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Creating destination directory: \(destination)")
            #endif
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        
        // Check if the extracted subfolder actually exists
        guard fileManager.fileExists(atPath: source.path) else {
            LoggerService.error(category: "CoreManager", "Subfolder \(source.lastPathComponent) not found in ZIP")
            throw NSError(domain: "FileSystemError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Subfolder \(source.lastPathComponent) not found in ZIP"])
        }
        
        let files = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        
        for fileURL in files {
            let targetURL = destination.appendingPathComponent(fileURL.lastPathComponent)
            
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: fileURL, to: targetURL)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Moved file: \(fileURL.lastPathComponent)")
            #endif
        }
    }
    
    private func getAppSupportDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Application support directory: \(paths[0])")
        #endif
        return paths[0].appendingPathComponent("TruchiEmu")
    }
}

@MainActor
class CoreManager: ObservableObject {
    static let shared = CoreManager()
    
    @Published var installedCores: [LibretroCore] = []
    @Published var availableCores: [RemoteCoreInfo] = []
    @Published var isFetchingCoreList: Bool = false
    @Published var pendingDownload: PendingCoreDownload? = nil
    @Published var downloadPhase: CoreDownloadPhase = .idle
    @Published var downloadCoreName: String = ""
    var isDownloadingCore: Bool { downloadPhase != .idle }
    private let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/Cores", isDirectory: true)
    }()
    private let coresKey = "installed_cores_v2"
    private let availableCoresKey = "available_cores_v1"
    private let coresInitialFetchDoneKey = "cores_initial_fetch_done_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    // Whether to trigger an automatic core list fetch from the buildbot. Returns true only on first launch with no cached data.
    var shouldAutoFetchCores: Bool {
        let hasCache = !availableCores.isEmpty
        let hasBeenFetched = AppSettings.getBool(coresInitialFetchDoneKey, defaultValue: false)
        return !hasCache && !hasBeenFetched
    }

    var buildbotBase: URL {
        URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/")!
    }

    init() {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        
        // ✅ MUST LOAD FIRST so the cores know which systems they belong to!
        LibretroInfoManager.loadMappings() 
        
        loadInstalledCores()
        loadAvailableCores()
    }   

    // MARK: - Core List

    func fetchAvailableCores() async {
        isFetchingCoreList = true
        defer { isFetchingCoreList = false }

        LoggerService.info(category: "CoreManager", "Fetching available cores from \(buildbotBase)")
        
        var request = URLRequest(url: buildbotBase)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Request: \(request)")
        #endif

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            LoggerService.error(category: "CoreManager", "Failed to fetch core list: Network error")
            return
        }
        
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            LoggerService.error(category: "CoreManager", "Failed to fetch core list: HTTP \(http.statusCode)")
            return
        }

        guard let html = String(data: data, encoding: .utf8) else { 
            LoggerService.error(category: "CoreManager", "Failed to parse core list: Encoding error")
            return 
        }

        // Parse the HTML index page for .dylib.zip entries with build dates
        // Format: fileName-yyyy-mm-dd hh:mm:sssize
        let pattern = #"href=['"]([^'"]+_libretro\.dylib\.zip)['"]"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Found \(matches.count) core links in HTML")
        #endif

        // Group results by coreID to extract build date
        var cores: [RemoteCoreInfo] = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let fileNameFull = String(html[range])
            let fileName = (fileNameFull as NSString).lastPathComponent

            // Extract build date from the surrounding context
            var buildDate = (fileNameFull as NSString).deletingPathExtension
                .replacingOccurrences(of: "_libretro", with: "")
            
            // Try to extract date pattern from the HTML line
            let lineStart = html.range(of: fileNameFull)?.lowerBound ?? html.startIndex
            let lineEndIndex = html.index(lineStart, offsetBy: min(200, html.distance(from: lineStart, to: html.endIndex)))
            let lineRange = lineStart..<lineEndIndex
            let lineSnippet = String(html[lineRange])
            
            // Extract date like "2026-04-28 04:05" from line
            let datePattern = #"(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})"#
            if let dateRegex = try? NSRegularExpression(pattern: datePattern),
               let dateMatch = dateRegex.firstMatch(in: lineSnippet, range: NSRange(lineSnippet.startIndex..., in: lineSnippet)) {
                let dateStr = String(lineSnippet[Range(dateMatch.range(at: 1), in: lineSnippet)!])
                let timeStr = String(lineSnippet[Range(dateMatch.range(at: 2), in: lineSnippet)!])
                buildDate = "\(dateStr) \(timeStr)"
            } else {
                buildDate = ISO8601DateFormatter().string(from: Date()).prefix(16).description
            }

            let downloadURL = fileNameFull.contains("://") ? URL(string: fileNameFull)! : buildbotBase.appendingPathComponent(fileName)
            let coreID = fileName
            .replacingOccurrences(of: ".dylib.zip", with: "")
            .replacingOccurrences(of: ".dll.zip", with: "")

            let displayName = coreID
            .replacingOccurrences(of: "_libretro", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")

            var systemIDs = CoreManager.supportedSystems(for: coreID)
            systemIDs = Array(Set(systemIDs)) // deduplicate

            // Fetch version from .info file asynchronously but don't block here
            // Store build date for now, version will be resolved later or on download
            cores.append(RemoteCoreInfo(
            coreID: coreID,
            fileName: fileName,
            downloadURL: downloadURL,
            systemIDs: systemIDs,
            displayName: displayName,
            version: buildDate // Temporary: use build date until full version fetch
            ))
        }

        // Now fetch .info files in parallel for version info
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Fetching version info for \(cores.count) cores...")
        #endif
        await withTaskGroup(of: Void.self) { group in
            for (index, core) in cores.enumerated() {
                group.addTask {
                    let version = await self.determineVersion(for: core.coreID, buildDate: core.version ?? "")
                    await MainActor.run {
                        cores[index].version = version
                    }
                }
            }
        }

        availableCores = cores.sorted { $0.displayName < $1.displayName }
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Available cores: \(availableCores)")
        #endif
        saveAvailableCores()
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Available cores saved")
        #endif
        AppSettings.setBool(coresInitialFetchDoneKey, value: true)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Available cores initial fetch done")
        #endif
    }

    // MARK: - Info File Processing

    private let infoBaseURL = URL(string: "https://buildbot.libretro.com/assets/frontend/info/")!
    private let infoCacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/Info", isDirectory: true)
    }()

    func parseInfoFile(_ data: Data) -> [String: String] {
        guard let content = String(data: data, encoding: .utf8) else { return [:] }
        var properties: [String: String] = [:]

        // Parse INI-style key="value" format
        let pattern = #"(\w+)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [:] }

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: content),
                  let valueRange = Range(match.range(at: 2), in: content) else { continue }
            let key = String(content[keyRange])
            let value = String(content[valueRange])
            properties[key] = value
        }

        return properties
    }

    func determineVersion(for coreID: String, buildDate: String) async -> String {
        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: infoCacheURL, withIntermediateDirectories: true)

        let infoFileName = "\(coreID).info"
        let infoURL = infoBaseURL.appendingPathComponent(infoFileName)
        let cachedInfoPath = infoCacheURL.appendingPathComponent(infoFileName)

        var versionString = ""
        var infoProperties: [String: String] = [:]

        // Try to fetch and parse the .info file
        do {
            let (data, _) = try await URLSession.shared.data(from: infoURL)
            infoProperties = parseInfoFile(data)

            if let displayVersion = infoProperties["display_version"] {
                versionString = displayVersion
            } else if let version = infoProperties["version"] {
                versionString = version
            }

            // Cache the .info file locally for offline use
            try data.write(to: cachedInfoPath)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Cached .info file for \(coreID): \(cachedInfoPath.path)")
            #endif
        } catch {
            LoggerService.warning(category: "CoreManager", "Failed to fetch .info for \(coreID): \(error.localizedDescription)")
            // Try to load from cache if available
            if let cachedData = try? Data(contentsOf: cachedInfoPath) {
                infoProperties = parseInfoFile(cachedData)
                versionString = infoProperties["display_version"] ?? infoProperties["version"] ?? ""
                #if LOG_DEBUG
                LoggerService.debug(category: "CoreManager", "Using cached .info for \(coreID)")
                #endif
            }
        }

        // Fallback to "unknown" if version is empty
        if versionString.isEmpty {
            versionString = "unknown"
        }

        // Concatenate with build date (Option A + 5)
        return "\(versionString)-\(buildDate)"
    }

    // MARK: - Download (user must authorize via pendingDownload)

    struct PendingCoreDownload: Identifiable, Equatable {
        static func == (lhs: PendingCoreDownload, rhs: PendingCoreDownload) -> Bool {
            lhs.coreInfo.coreID == rhs.coreInfo.coreID && lhs.romID == rhs.romID
        }

        var id: String { coreInfo.coreID }
        let coreInfo: RemoteCoreInfo

        // Launch context — when set, the game should be auto-launched after download
        let romID: UUID?
        let systemID: String?
        let slotToLoad: Int?

        init(coreInfo: RemoteCoreInfo, romID: UUID? = nil, systemID: String? = nil, slotToLoad: Int? = nil) {
            self.coreInfo = coreInfo
            self.romID = romID
            self.systemID = systemID
            self.slotToLoad = slotToLoad
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "PendingCoreDownload initialized")
            #endif
        }

        // Convenience: true when launch context is provided
        var hasLaunchContext: Bool { romID != nil && systemID != nil }
    }

    func requestCoreDownload(
        for coreID: String,
        systemID: String? = nil,
        romID: UUID? = nil,
        slotToLoad: Int? = nil
    ) {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "[REQUEST] RequestCoreDownload called with coreID=\\(coreID), systemID=\\(sysStr), availableCores.count=\\(availableCores.count)")
        #endif
    
    // Find in available list
    if let remote = availableCores.first(where: { $0.coreID == coreID }) {
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Found remote core: \(remote)")
            #endif
            pendingDownload = PendingCoreDownload(
                coreInfo: remote,
                romID: romID,
                systemID: systemID,
                slotToLoad: slotToLoad
            )
    } else {
      #if LOG_DEBUG
      LoggerService.debug(category: "CoreManager", "Core not found in available list, building synthetic RemoteCoreInfo")
      #endif
      // Build a synthetic RemoteCoreInfo - marks version as "synthetic" to identify in UI
      let fileName = "\(coreID).dylib.zip"
      let url = buildbotBase.appendingPathComponent(fileName)
      let displayName = coreID
      .replacingOccurrences(of: "_libretro", with: "")
      .replacingOccurrences(of: "_", with: " ")
      .split(separator: " ").map { $0.capitalized }.joined(separator: " ")
      let buildDate = Date().ISO8601Format().prefix(16).description
            let info = RemoteCoreInfo(coreID: coreID, fileName: fileName, downloadURL: url,
                systemIDs: systemID.map { [$0] } ?? [], displayName: displayName, version: "synthetic-\(buildDate)")
            pendingDownload = PendingCoreDownload(
                coreInfo: info,
                romID: romID,
                systemID: systemID,
                slotToLoad: slotToLoad
            )
            let coreIdStr = pendingDownload?.coreInfo.coreID ?? "nil"
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "[SYNTHETIC] pendingDownload SET: \(coreIdStr)")
            #endif
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "[STATE] pendingDownload should now trigger sheet via @Published")
            #endif
        }
    }
    
    // MARK: - Core Resolution Helper
    
    /// Resolves and returns the appropriate core ID for a ROM,
    /// with synthetic fallback to ensure download sheet can appear for fresh installs.
    /// This centralizes the core resolution logic and eliminates triplication across views.
    func resolveCoreID(for rom: ROM, system: SystemInfo) -> String {
        let sysPrefs = SystemPreferences.shared
        let coreID = rom.useCustomCore ?
            (rom.selectedCoreID ?? sysPrefs.preferredCoreID(for: system.id) ?? system.defaultCoreID) :
            (sysPrefs.preferredCoreID(for: system.id) ?? system.defaultCoreID)
        
        // Synthetic fallback when no core is configured/defaulted
        return coreID ?? "\(system.id)_libretro"
    }
    
    // MARK: - Download (user must authorize via pendingDownload)
    
    func downloadCore(_ info: RemoteCoreInfo, romPath: String? = nil) async {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Starting download: \(info.coreID) from \(info.downloadURL)")
        #endif

        downloadCoreName = info.displayName
        downloadPhase = .findingURL

        let BiosDownloaderService = BiosDownloader()
        BiosDownloaderService.downloadAndExtractBios(for: info.coreID) { result in
            switch result {
            case .success(_):
                #if LOG_DEBUG
                LoggerService.debug(category: "CoreManager", "BIOS for \(info.coreID) downloaded successfully")
                #endif
            case .failure(let error):
                LoggerService.error(category: "CoreManager", "BIOS for \(info.coreID) download failed: \(error)")
            }
        }

        // Mark existing installed core as downloading (for re-downloads/updates)
        if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
            installedCores[idx].isDownloading = true
        }

        do {
            downloadPhase = .fetchingFromURL
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Downloading core: \(info.coreID)")
            #endif
            var request = URLRequest(url: info.downloadURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

            downloadPhase = .downloading(progress: 0)
            let (tmpURL, response) = try await URLSession.shared.download(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                LoggerService.error(category: "CoreManager", "Server returned HTTP \(http.statusCode)")
                throw NSError(domain: "CoreManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"])
            }

            downloadPhase = .installing

            // Use version from RemoteCoreInfo instead of timestamp
            // Extract version from info.version (format: "raw-version-buildDate")
            let versionParts = (info.version ?? "unknown").split(separator: "-", maxSplits: 1)
            let versionString = String(versionParts.first ?? "unknown")
            let buildDate = versionParts.count > 1 ? String(versionParts[1]) : Date().ISO8601Format()

            // Create folder structure: coreID/version/
            let coreFolder = appSupportURL.appendingPathComponent(info.coreID, isDirectory: true)
            let versionFolder = coreFolder.appendingPathComponent("\(versionString)-\(buildDate)", isDirectory: true)
            try FileManager.default.createDirectory(at: versionFolder, withIntermediateDirectories: true)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Core version folder created: \(versionFolder.path)")
            #endif

            // Unzip to version folder
            let dylibName = info.fileName.replacingOccurrences(of: ".zip", with: "")
            let dylibDest = versionFolder.appendingPathComponent(dylibName)

            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Unzipping to: \(dylibDest.path)")
            #endif
            try await unzip(zipURL: tmpURL, extracting: dylibName, to: dylibDest)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Unzipped successfully")
            #endif

            // Create CoreVersion object
            let coreVersion = CoreVersion(
                version: versionString,
                buildDate: buildDate,
                dylibPath: dylibDest,
                downloadedAt: Date(),
                remoteURL: info.downloadURL,
                isActive: true // Mark as active immediately after download
            )
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Core version created: \(coreVersion)")
            #endif

            // Create latest symlink pointing to the version we just downloaded
            let symlinkPath = coreFolder.appendingPathComponent(info.coreID + ".dylib")
            let relativePath = "\(versionString)-\(buildDate)/\(dylibName)"

            do {
                // Remove old symlink if it exists
                if FileManager.default.fileExists(atPath: symlinkPath.path) {
                    try FileManager.default.removeItem(at: symlinkPath)
                }

                // Create new symlink to version folder
                try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: dylibDest)
                #if LOG_DEBUG
                LoggerService.debug(category: "CoreManager", "Created latest symlink: \(symlinkPath.path) -> \(relativePath)")
                #endif
            } catch {
                LoggerService.error(category: "CoreManager", "Failed to create latest symlink: \(error)")
            }

            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                // Ensure no duplicate path entries exist
                installedCores[idx].installedVersions.removeAll { $0.dylibPath.path == dylibDest.path }
                installedCores[idx].installedVersions.append(coreVersion)
                installedCores[idx].activeVersionTag = coreVersion.tag
                installedCores[idx].isDownloading = false
                installedCores[idx].downloadProgress = 0
            } else {
                // New core installation
                let newCore = LibretroCore(
                    id: info.coreID,
                    displayName: info.displayName,
                    systemIDs: info.systemIDs,
                    installedVersions: [coreVersion],
                    activeVersionTag: coreVersion.tag,
                    isDownloading: false,
                    downloadProgress: 0
                )
                installedCores.append(newCore)
            }

            // Discover core options and input descriptors in one shot (both captured during core init)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Discovering core options and input descriptors for: \(info.coreID)")
            #endif
            await CoreOptionsManager.shared.discoverOptions(for: info.coreID, dylibPath: dylibDest.path, romPath: romPath)

            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Installed cores: \(installedCores)")
            #endif
            saveInstalledCores()
            LoggerService.info(category: "CoreManager", "Successfully installed \(info.coreID) version \(versionString)")
        } catch {
            LoggerService.error(category: "CoreManager", "Download failed for \(info.coreID): \(error.localizedDescription)")
            // Remove placeholder core if it was added (no installed versions = not truly installed)
            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID && $0.installedVersions.isEmpty }) {
                installedCores.remove(at: idx)
            } else if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                installedCores[idx].isDownloading = false
            }
        }

        downloadPhase = .idle
        downloadCoreName = ""
    }

    // MARK: - Core lookup

    func defaultCore(for systemID: String) -> LibretroCore? {
        guard let system = SystemDatabase.system(forID: systemID),
              let coreID = system.defaultCoreID else { return nil }
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Default core \(coreID) for system \(systemID)")
        #endif
        return installedCores.first { $0.id == coreID }
    }

    func isInstalled(coreID: String) -> Bool {
        let result = installedCores.first(where: { $0.id == coreID })?.isInstalled ?? false
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Is installed: \(coreID) -> \(result)")
        #endif
        return result
    }

    func setActiveVersion(coreID: String, tag: String) {
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Set active version: \(coreID) -> \(tag)")
        #endif
        if let idx = installedCores.firstIndex(where: { $0.id == coreID }) {
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Found installed core: \(coreID)")
            #endif
            installedCores[idx].activeVersionTag = tag
            saveInstalledCores()
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Installed cores: \(installedCores)")
            #endif
            CoreOptionsManager.shared.discoverOptionsIfNeeded(for: coreID)
        }
    }

    func deleteCore(_ core: LibretroCore) {
        // Remove from disk
        let folder = appSupportURL.appendingPathComponent(core.id)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Deleting core: \(core.id)")
        #endif
        try? FileManager.default.removeItem(at: folder)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Core deleted: \(core.id)")
        #endif
        // Remove from list
        installedCores.removeAll { $0.id == core.id }
        saveInstalledCores()
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Core removed from list: \(core.id)")
        #endif
        // Instantly fallback any systems that were relying on this deleted core
        repairPreferredCores()
        let biosDownloaderService = BiosDownloader()
        biosDownloaderService.deleteCore(coreID: core.id)
    }

    // MARK: - Persistence

    private func saveInstalledCores() {
        if let data = try? encoder.encode(installedCores) {
            AppSettings.setData(coresKey, value: data)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Installed cores saved: \(installedCores)")
            #endif
            objectWillChange.send() 
        }
    }

    private func repairPreferredCores() {
        for system in SystemDatabase.systems {
            // Find all currently installed cores that support this system
            let validCoresForSystem = installedCores.filter { 
                $0.systemIDs.contains(system.id) || $0.id == system.defaultCoreID 
            }
            
            // Get current preference (handle potential empty string from AppSettings)
            var currentPref = SystemPreferences.shared.preferredCoreID(for: system.id)
            if currentPref?.isEmpty == true { currentPref = nil }
            
            // 1. If NO cores are installed for this system, wipe any dangling preference.
            if validCoresForSystem.isEmpty {
                if currentPref != nil {
                    SystemPreferences.shared.setPreferredCoreID(nil, for: system.id)
                }
                continue
            }
            
            let isPrefInstalled = validCoresForSystem.contains { $0.id == currentPref }
            let isDefaultInstalled = validCoresForSystem.contains { $0.id == system.defaultCoreID }
            
            // 2. If the user's preferred core is still installed, we are good. Do nothing.
            if let _ = currentPref, isPrefInstalled { continue }
            
            // 3. If there's no custom preference and the factory default is installed, we are good.
            if currentPref == nil && isDefaultInstalled { continue }
            
            // 4. We need to auto-assign a new core!
            if isDefaultInstalled {
                // The custom preferred core was deleted, but the factory default is still here. 
                // Clear the preference so it naturally falls back to default.
                SystemPreferences.shared.setPreferredCoreID(nil, for: system.id)
                LoggerService.warning(category: "CoreManager", "Preferred core for \(system.name) was missing. Reset to factory default: \(system.defaultCoreID ?? "None")")
            } else {
                // Neither the preferred nor the factory default are installed. 
                // Auto-assign the first available core alphabetically.
                if let fallback = validCoresForSystem.sorted(by: { $0.displayName < $1.displayName }).first {
                    SystemPreferences.shared.setPreferredCoreID(fallback.id, for: system.id)
                    LoggerService.error(category: "CoreManager", "Default core for \(system.name) missing. Auto-assigned to fallback: \(fallback.id).")
                }
            }
        }
    }

    private func loadInstalledCores() {
        // First try to load from persisted data (backward compatibility)
        var persistedCores: [LibretroCore] = []
        if let data = AppSettings.getData(coresKey),
           let saved = try? decoder.decode([LibretroCore].self, from: data) {
            persistedCores = saved
        }

        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Loading installed cores from filesystem and cache")
        #endif

        var validCores: [LibretroCore] = []
        var cacheNeedsRepair = false

        // Scan filesystem for cores
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            do {
                let coreFolders = try FileManager.default.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil)

                for coreFolder in coreFolders {
                    guard coreFolder.hasDirectoryPath else { continue }
                    let coreID = coreFolder.lastPathComponent

                    // Scan version folders
                    let versionFolders = try FileManager.default.contentsOfDirectory(at: coreFolder, includingPropertiesForKeys: nil)
                    var installedVersions: [CoreVersion] = []
                    var activeVersionTag: String?

                    // Look for latest symlink
                    let symlinkPath = coreFolder.appendingPathComponent("\(coreID).dylib")
                    let latestDylibURL = symlinkPath

                    for versionFolder in versionFolders {
                        guard versionFolder.hasDirectoryPath else { continue }

                        // Parse version from folder name (format: version-buildDate)
                        let folderName = versionFolder.lastPathComponent
                        let components = folderName.split(separator: "-", maxSplits: 1)
                        let version = components.first.map(String.init) ?? "unknown"
                        let buildDate = components.count > 1 ? String(components[1]) : Date().ISO8601Format()

                        // Find dylib in version folder
                        let files = try FileManager.default.contentsOfDirectory(at: versionFolder, includingPropertiesForKeys: nil)
                        for file in files {
                            let fileName = file.lastPathComponent
                            if fileName.hasSuffix(".dylib") {
                            // Check if this is the active version (matches symlink target)
                            let isActive = latestDylibURL.path == file.path

                            // Try to get persisted info for this version first
                            let persistedVersion = persistedCores.first(where: { $0.id == coreID })?
                                .installedVersions.first(where: { $0.dylibPath.path == file.path })

                            var coreVersion = persistedVersion ?? CoreVersion(
                                version: version,
                                buildDate: buildDate,
                                dylibPath: file,
                                downloadedAt: Date(), // Will default to now if first time scanned
                                remoteURL: nil
                            )

                            coreVersion.isActive = isActive
                            installedVersions.append(coreVersion)

                                if isActive {
                                    activeVersionTag = coreVersion.tag
                                }

                                #if LOG_DEBUG
                                LoggerService.debug(category: "CoreManager", "Found version: \(version) for \(coreID)")
                                #endif
                            }
                        }
                    }

                    // Merge with persisted data if any
                    let persistedCore = persistedCores.first { $0.id == coreID }
                    let combinedVersions = installedVersions + (persistedCore?.installedVersions.filter { p in
                        // Add any versions from persisted that we didn't find on disk
                        !installedVersions.contains { $0.dylibPath.path == p.dylibPath.path }
                    } ?? [])

                    if !installedVersions.isEmpty {
                        let core = LibretroCore(
                            id: coreID,
                            displayName: persistedCore?.displayName ?? coreID,
                            systemIDs: CoreManager.supportedSystems(for: coreID),
                            installedVersions: combinedVersions,
                            activeVersionTag: activeVersionTag,
                            isDownloading: false,
                            downloadProgress: 0
                        )
                        validCores.append(core)
                    }
                }
            } catch {
                LoggerService.error(category: "CoreManager", "Error scanning core folder: \(error)")
            }
        }

        // Add any persisted cores that weren't found on disk
        for persisted in persistedCores {
            if !validCores.contains(where: { $0.id == persisted.id }) {
                // Check if any versions still have valid files
                let validVersions = persisted.installedVersions.filter { v in
                    if FileManager.default.fileExists(atPath: v.dylibPath.path) {
                        return true
                    } else {
                        #if LOG_DEBUG
                        LoggerService.debug(category: "CoreManager", "Removing missing version: \(v.dylibPath.path)")
                        #endif
                        cacheNeedsRepair = true
                        return false
                    }
                }

                if !validVersions.isEmpty {
                    var fixedCore = persisted
                    fixedCore.installedVersions = validVersions
                    validCores.append(fixedCore)
                } else {
                    cacheNeedsRepair = true
                }
            }
        }

        // Migrate any timestamp-based folders to version-based
        for core in validCores {
            migrateTimestampToVersionFolders(for: core)
        }

        installedCores = validCores

        if cacheNeedsRepair {
            LoggerService.error(category: "CoreManager", "Core cache repaired due to migration or missing files.")
            saveInstalledCores()
        }

        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Loaded \(installedCores.count) installed cores with versioned folders")
        #endif

        repairPreferredCores()
        validateCoreVersions()
    }

    private func validateCoreVersions() {
        var needsSave = false
        for i in installedCores.indices {
            let core = installedCores[i]
            guard let tag = core.activeVersionTag else { continue }
            if !core.installedVersions.contains(where: { $0.tag == tag }) {
                LoggerService.warning(category: "CoreManager", "Repairing core state: \(core.id) activeTag '\(tag)' not found in versions, resetting")
                installedCores[i].activeVersionTag = nil
                needsSave = true
            }
        }
        if needsSave { saveInstalledCores() }
    }

    private func migrateTimestampToVersionFolders(for core: LibretroCore) {
        // Migration logic for old timestamp-based structure → new version-based
        let coreFolder = appSupportURL.appendingPathComponent(core.id)
        guard FileManager.default.fileExists(atPath: coreFolder.path) else { return }

        do {
            let folders = try FileManager.default.contentsOfDirectory(at: coreFolder, includingPropertiesForKeys: nil)
            for folder in folders {
                // Old format: "2024-01-01 12-00-00" (timestamp folder)
                // New format: "version-buildDate"
                let folderName = folder.lastPathComponent
                if folderName.contains(" ") && folderName.count >= 16 {
                    // This looks like an old timestamp folder
                    #if LOG_DEBUG
                    LoggerService.debug(category: "CoreManager", "Found old timestamp folder: \(folderName)")
                    #endif

                    // Find dylib in it
                    let dylibFiles = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                        .filter { $0.path.hasSuffix(".dylib") }

                    for dylibFile in dylibFiles {
                        // Move to new structure: version-unknown-timestamp
                        let newVersion = "unknown-\(folderName.replacingOccurrences(of: " ", with: "-"))"
                        let newVersionFolder = coreFolder.appendingPathComponent(newVersion, isDirectory: true)
                        try FileManager.default.createDirectory(at: newVersionFolder, withIntermediateDirectories: true)

                        let newDylibPath = newVersionFolder.appendingPathComponent(dylibFile.lastPathComponent)
                        try FileManager.default.moveItem(at: dylibFile, to: newDylibPath)

                        // Remove old timestamp folder if empty
                        let remaining = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                        if remaining.isEmpty {
                            try FileManager.default.removeItem(at: folder)
                        }

                        #if LOG_DEBUG
                        LoggerService.debug(category: "CoreManager", "Migrated \(core.id) from timestamp to version folder")
                        #endif
                    }
                }
            }
        } catch {
            LoggerService.error(category: "CoreManager", "Migration error for \(core.id): \(error)")
        }
    }

    private func loadAvailableCores() {
        guard let data = AppSettings.getData(availableCoresKey),
              var saved = try? decoder.decode([RemoteCoreInfo].self, from: data) else { return }
        // Refresh systemIDs so updates to supportedSystems mappings are applied to cached data
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Loading available cores")
        #endif
        for i in 0..<saved.count {
            #if LOG_EXTREME
            LoggerService.extreme(category: "CoreManager", "Loading available core: \(saved[i].coreID) for system: \(saved[i].systemIDs)")
            #endif
            saved[i].systemIDs = CoreManager.supportedSystems(for: saved[i].coreID)
        }
        availableCores = saved
    }

    private func saveAvailableCores() {
        if let data = try? encoder.encode(availableCores) {
            AppSettings.setData(availableCoresKey, value: data)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Available cores saved: \(availableCores)")
            #endif
        }
    }

    static func supportedSystems(for coreID: String) -> [String] {
        // 1. Get systems that explicitly list this core as their 'defaultCoreID'
        var ids = Set(SystemDatabase.systems.filter { $0.defaultCoreID == coreID }.map { $0.id })

        // 2. Dynamic map lookup
        let strippedID = coreID.replacingOccurrences(of: "_libretro", with: "")
        let dynamicIDs = LibretroInfoManager.coreToSystemMap[coreID] ?? 
                        LibretroInfoManager.coreToSystemMap[strippedID] ?? []
                        
        ids.formUnion(dynamicIDs)

        // 3. Expand to all compatible aliases
        var finalIDs = Set<String>()
        for id in ids {
            finalIDs.formUnion(SystemDatabase.compatibleIDs(for: id))
        }
        
        // 4. Handle Dolphin case: if it only has gamecube, also include wii
        if coreID == "dolphin_libretro" && finalIDs.contains("gamecube") && !finalIDs.contains("wii") {
            finalIDs.insert("wii")
            finalIDs.formUnion(SystemDatabase.compatibleIDs(for: "wii"))
        }
        
        return Array(finalIDs)
    }

    // MARK: - Minimal ZIP extraction

    private func unzip(zipURL: URL, extracting targetName: String, to destination: URL) async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Unzipping core: \(zipURL.path) to \(tmpDir.path)")
        #endif

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-xk", zipURL.path, tmpDir.path]

        try proc.run()
        proc.waitUntilExit()
        
        if proc.terminationStatus != 0 {
            LoggerService.error(category: "CoreManager", "ditto failed with exit code \(proc.terminationStatus)")
            throw NSError(domain: "CoreManager", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ditto failed with exit code \(proc.terminationStatus)"])
        }

        // Recursive search for the dylib
        let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: nil)
        var foundURL: URL?
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Searching for file: \(targetName)")
        #endif
        while let fileURL = enumerator?.nextObject() as? URL {
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Found file: \(fileURL.path)")
            #endif
            if fileURL.lastPathComponent == targetName {
                foundURL = fileURL
                break
            }
        }

        if let dylib = foundURL {
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Found dylib: \(dylib.path)")
            #endif
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: dylib, to: destination)
            await prepareCore(at: destination.path)
            #if LOG_DEBUG
            LoggerService.debug(category: "CoreManager", "Core prepared: \(destination.path)")
            #endif
        } else {
            LoggerService.error(category: "CoreManager", "Failed to find \(targetName) in unzipped archive.")
            throw NSError(domain: "CoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to find \(targetName) in unzipped archive."])
        }
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func prepareCore(at path: String) async {
        // Remove quarantine attribute using C API
        removexattr(path, "com.apple.quarantine", 0)
        
        // On ARM64/Apple Silicon, dylibs MUST be at least ad-hoc signed to be loaded.
        // Even if already signed, re-signing ensures it's valid for this machine.
        #if arch(arm64)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-s", "-", "--force", path]
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Codesigning core: \(path)")
        #endif
        try? proc.run()
        proc.waitUntilExit()
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Core codesigned: \(path)")
        #endif
        #endif
    }
    @MainActor
    func performFullSystemUpdate() async {
        isFetchingCoreList = true
        // Use the LibretroInfoManager singleton to piggyback its status updates
        let infoManager = LibretroInfoManager.shared
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Starting full system update")
        #endif
        
        // Step 1: Update System/File Extension Database
        await infoManager.refreshCoreInfo()
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "System/File Extension Database updated")
        #endif
    
        // Step 2: Fetch the actual Core binaries from Libretro buildbot
        await fetchAvailableCores()
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Core binaries fetched")
        #endif
    
        // Step 3: Cleanup/Post-process
        isFetchingCoreList = false
        infoManager.refreshStatus = "Full System Update Complete!"
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Full System Update Complete!")
        #endif
    
        // Trigger a UI refresh if your views are observing SystemPreferences
        self.loadAvailableCores()
        self.loadInstalledCores()
        SystemPreferences.shared.updateTrigger += 1
    }

}

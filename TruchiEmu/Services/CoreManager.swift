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
    @Published var isCheckingCoreUpdates: Bool = false
    @Published var isUpdatingAllCores: Bool = false
    @Published var hasCheckedForUpdates: Bool = false
    @Published var coresNeedingUpdate: [LibretroCore] = []
    /// The upstream version of each installed core. The value is the version of the
    /// core at the build date of the installed version.
    @Published var installedVersions: [String: String] = [:]
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
    private let coreUpdateCheckKey = "cores_last_core_update_check_v1"
    private let coreUpdateCheckMigrationKey = "cores_core_update_check_migrated_v1"
    private let installedVersionsKey = "core_installed_versions_v1"
    /// The upstream version of an installed build. The key is the core ID and the
    /// build date of the build.
    private var installedVersionCache: [String: String] = [:]
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

    /// Whether enough time has passed since the last core update check to run another one.
    var shouldCheckCoreUpdates: Bool {
        let interval: TimeInterval = 86400 // 24 hours
        guard let lastCheck = AppSettings.getDate(coreUpdateCheckKey) else { return true }
        return Date().timeIntervalSince(lastCheck) > interval
    }

    var buildbotBase: URL {
        URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/")!
    }

    init() {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        
        // One-time migration: clear any stale core update check date that may have
        // been recorded by a previous version (the old code set the date even when
        // the check failed). Ensures the first check with the new logic runs.
        if AppSettings.getBool(coreUpdateCheckMigrationKey, defaultValue: false) == false {
            AppSettings.remove(coreUpdateCheckKey)
            AppSettings.setBool(coreUpdateCheckMigrationKey, value: true)
        }
        
        // ✅ MUST LOAD FIRST so the cores know which systems they belong to!
        LibretroInfoManager.loadMappings() 
        
        loadInstalledCores()
        loadAvailableCores()
        loadInstalledVersions()
    }   

    // MARK: - Core List

    func fetchAvailableCores() async {
        isFetchingCoreList = true
        defer { isFetchingCoreList = false }

        // The upstream version of each core comes from the core info data.
        if LibretroInfoManager.coreVersions.isEmpty {
            await LibretroInfoManager.shared.refreshCoreInfo()
        }

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

            // The buildbot does not give a version in the file name. The version
            // comes from the core info data of the core.
            let upstreamVersion = LibretroInfoManager.coreVersions[coreID] ?? "unknown"

            cores.append(RemoteCoreInfo(
            coreID: coreID,
            fileName: fileName,
            downloadURL: downloadURL,
            systemIDs: systemIDs,
            displayName: displayName,
            version: "\(upstreamVersion)-\(buildDate)"
            ))
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

    // MARK: - Core Update Check

    /// Checks whether any installed core has a newer version available on the buildbot.
    /// Fetches the available core list first (if needed), then compares each installed
    /// core's version against the latest version.
    ///
    /// The installed version is the version of libretro-core-info at the build date of
    /// the installed build. The available version is the current version of
    /// libretro-core-info. A nightly rebuild does not change the version, so a nightly
    /// rebuild does not show as an update.
    func checkForCoreUpdates() async {
        guard !isCheckingCoreUpdates else { return }
        isCheckingCoreUpdates = true
        defer { isCheckingCoreUpdates = false }

        LoggerService.info(category: "CoreManager", "Checking for core updates...")

        // Get the list of available cores. This also loads the upstream versions.
        await fetchAvailableCores()

        guard !availableCores.isEmpty else {
            LoggerService.warning(category: "CoreManager", "Core update check skipped: no available cores fetched")
            hasCheckedForUpdates = true
            return
        }

        // The installed version is the upstream version at the build date of the
        // installed build. The available version is the current upstream version.
        var candidates: [(core: LibretroCore, buildDate: Date, availableVersion: String)] = []
        for installed in installedCores {
            guard installed.source == .buildbot else { continue }
            guard let active = installed.activeVersion,
                  let buildDate = CoreManager.parseBuildDate(active.buildDate) else { continue }
            guard let remote = availableCores.first(where: { $0.coreID == installed.id }) else { continue }
            guard let availableVersion = LibretroInfoManager.coreVersions[remote.coreID], !availableVersion.isEmpty else { continue }
            candidates.append((installed, buildDate, availableVersion))
        }

        // Resolve the installed version of each core. The result is cached.
        let resolved = await withTaskGroup(of: (String, String?).self, returning: [(String, String?)].self) { group in
            for candidate in candidates {
                let key = installedVersionCacheKey(coreID: candidate.core.id, buildDate: candidate.buildDate)
                if let cached = installedVersionCache[key] {
                    group.addTask { (candidate.core.id, cached.isEmpty ? nil : cached) }
                } else {
                    group.addTask {
                        let version = await CoreVersionHistoryService.shared.version(for: candidate.core.id, at: candidate.buildDate)
                        return (candidate.core.id, version)
                    }
                }
            }
            var results: [(String, String?)] = []
            for await result in group { results.append(result) }
            return results
        }

        var outdated: [LibretroCore] = []
        for (coreID, version) in resolved {
            installedVersions[coreID] = version ?? ""
            guard let candidate = candidates.first(where: { $0.core.id == coreID }) else { continue }
            // Keep the result. The version of a build does not change.
            let key = installedVersionCacheKey(coreID: coreID, buildDate: candidate.buildDate)
            installedVersionCache[key] = version ?? ""
            guard let version, !version.isEmpty else { continue }
            if version != candidate.availableVersion {
                outdated.append(candidate.core)
                LoggerService.info(category: "CoreManager", "Update available for \(candidate.core.displayName): installed \(version), available \(candidate.availableVersion)")
            }
        }

        // Keep the order of the installed cores.
        outdated.sort { lhs, rhs in
            guard let left = installedCores.firstIndex(where: { $0.id == lhs.id }),
                  let right = installedCores.firstIndex(where: { $0.id == rhs.id }) else { return false }
            return left < right
        }

        coresNeedingUpdate = outdated
        hasCheckedForUpdates = true
        saveInstalledVersions()
        AppSettings.setDate(coreUpdateCheckKey, value: Date())
        LoggerService.info(category: "CoreManager", "Core update check complete: \(outdated.count) core(s) need updating")
    }

    /// Updates all cores that have a newer version.
    /// The cores update one by one, because the download flow uses shared state.
    func updateAllCores() async {
        guard !isUpdatingAllCores, !isDownloadingCore, !isCheckingCoreUpdates else { return }
        isUpdatingAllCores = true
        defer { isUpdatingAllCores = false }

        // Make sure the list of cores that need an update is correct.
        if !hasCheckedForUpdates {
            await checkForCoreUpdates()
        }

        let cores = coresNeedingUpdate
        guard !cores.isEmpty else { return }

        LoggerService.info(category: "CoreManager", "Updating \(cores.count) core(s)")
        for core in cores {
            guard let remote = availableCores.first(where: { $0.coreID == core.id }) else { continue }
            await downloadCore(remote)
        }
        LoggerService.info(category: "CoreManager", "Update of all cores complete")
    }

    /// Stores the version of a downloaded build.
    /// The UI then shows the new version at once, without a new update check.
    private func recordInstalledVersion(coreID: String, version: String, buildDate: String) {
        // The upstream version is the version of the core. Other strings, such as
        // "synthetic", are not versions.
        let upstream = LibretroInfoManager.coreVersions[coreID] ?? ""
        let resolved = upstream.isEmpty ? version : upstream
        guard !resolved.isEmpty, resolved != "unknown", resolved != "synthetic" else { return }

        installedVersions[coreID] = resolved
        if let date = CoreManager.parseBuildDate(buildDate) {
            let key = installedVersionCacheKey(coreID: coreID, buildDate: date)
            installedVersionCache[key] = resolved
        }
        saveInstalledVersions()

        // The core no longer needs an update. Remove it from the list.
        refreshOutdatedCores()
    }

    /// The upstream version of an installed core at the build date of the install.
    func installedVersion(for core: LibretroCore) -> String? {
        if let version = installedVersions[core.id], !version.isEmpty { return version }
        guard let active = core.activeVersion,
              let buildDate = CoreManager.parseBuildDate(active.buildDate) else { return nil }
        let key = installedVersionCacheKey(coreID: core.id, buildDate: buildDate)
        guard let cached = installedVersionCache[key], !cached.isEmpty else { return nil }
        return cached
    }

    /// The latest upstream version of a core.
    func availableVersion(for coreID: String) -> String? {
        guard let version = LibretroInfoManager.coreVersions[coreID], !version.isEmpty else { return nil }
        return version
    }

    /// The key of the cache of the installed versions. The build date is part of the
    /// key because a new build of the same core has a different version.
    private func installedVersionCacheKey(coreID: String, buildDate: Date) -> String {
        "\(coreID)|\(Int(buildDate.timeIntervalSince1970))"
    }

    private func loadInstalledVersions() {
        guard let data = AppSettings.getData(installedVersionsKey),
              let saved = try? decoder.decode([String: String].self, from: data) else { return }
        installedVersionCache = saved
    }

    private func saveInstalledVersions() {
        if let data = try? encoder.encode(installedVersionCache) {
            AppSettings.setData(installedVersionsKey, value: data)
        }
    }

    /// Returns true if the given core has a newer version available.
    func hasUpdate(for coreID: String) -> Bool {
        coresNeedingUpdate.contains { $0.id == coreID }
    }

    // MARK: - Version and Build Date

    /// Splits a version folder name into the version and the build date.
    /// The name of a version folder has the format "<version>-<build date>".
    static func parseVersionFolderName(_ name: String) -> (version: String, buildDate: String) {
        // The build date is at the end of the name.
        let datePattern = #"\d{4}-\d{2}-\d{2}(?:[ T-]\d{2}[:-]\d{2}(?:[:-]\d{2})?)?$"#
        if let range = name.range(of: datePattern, options: .regularExpression) {
            let buildDate = normalizeBuildDate(String(name[range]))
            var version = String(name[..<range.lowerBound])
            if version.hasSuffix("-") { version.removeLast() }
            // Old installs use an "unknown-" prefix before the real version.
            if version.hasPrefix("unknown-") { version.removeFirst("unknown-".count) }
            return (version.isEmpty ? "unknown" : version, buildDate)
        }

        // The old format: "<version>-<build date>".
        let parts = name.split(separator: "-", maxSplits: 1)
        let version = parts.first.map(String.init) ?? "unknown"
        let buildDate = parts.count > 1 ? String(parts[1]) : ""
        return (version, buildDate)
    }

    /// Puts a build date in the format "YYYY-MM-DD HH:MM".
    static func normalizeBuildDate(_ value: String) -> String {
        let pattern = #"^(\d{4}-\d{2}-\d{2})[ T-](\d{2})[:-](\d{2})(?::(\d{2}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return value
        }
        func part(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range])
        }
        let date = part(1)
        let hour = part(2)
        let minute = part(3)
        let second = part(4)
        if second.isEmpty {
            return "\(date) \(hour):\(minute)"
        }
        return "\(date) \(hour):\(minute):\(second)"
    }

    /// Reads the build date of a version string. The buildbot uses UTC.
    static func parseBuildDate(_ value: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd-HH-mm",
            "yyyy-MM-dd",
            "yyyyMMdd-HHmmss",
            "yyyyMMdd-HHmm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
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

            // Use the version from RemoteCoreInfo instead of timestamp
            // The version string has the format "<version>-<build date>".
            let parsedVersion = CoreManager.parseVersionFolderName(info.version ?? "unknown")
            let versionString = parsedVersion.version
            let buildDate = parsedVersion.buildDate

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

            // Store the version of the new build. The UI then shows the new
            // version at once, without a new update check.
            recordInstalledVersion(coreID: info.coreID, version: versionString, buildDate: buildDate)

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

                    // Migrate old timestamp folders before the scan.
                    migrateTimestampToVersionFolders(in: coreFolder, coreID: coreID)

                    // Scan version folders
                    let versionFolders = try FileManager.default.contentsOfDirectory(at: coreFolder, includingPropertiesForKeys: nil)
                    var installedVersions: [CoreVersion] = []
                    var activeVersionTag: String?

                    // The "latest" symlink points at the active version. Repair it
                    // first. A symlink can point to a folder that does not exist.
                    let activeDylibURL = repairLatestSymlink(coreFolder: coreFolder, coreID: coreID, versionFolders: versionFolders)

                    for versionFolder in versionFolders {
                        guard versionFolder.hasDirectoryPath else { continue }

                        // Parse version from folder name (format: version-buildDate)
                        let folderName = versionFolder.lastPathComponent
                        let parsed = CoreManager.parseVersionFolderName(folderName)
                        let version = parsed.version
                        let buildDate = parsed.buildDate

                        // Find dylib in version folder
                        let files = try FileManager.default.contentsOfDirectory(at: versionFolder, includingPropertiesForKeys: nil)
                        for file in files {
                            let fileName = file.lastPathComponent
                            if fileName.hasSuffix(".dylib") {
                            // Check if this is the active version (matches symlink target)
                            let isActive = activeDylibURL?.path == file.path

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

                            // The name of the folder has the correct version and build date.
                            coreVersion.version = version
                            coreVersion.buildDate = buildDate
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
                        // Custom cores keep their persisted mapping. Buildbot cores recompute.
                        let systemIDs: [String]
                        if persistedCore?.source == .custom, let kept = persistedCore?.systemIDs, !kept.isEmpty {
                            systemIDs = kept
                        } else {
                            systemIDs = CoreManager.supportedSystems(for: coreID)
                        }
                        let core = LibretroCore(
                            id: coreID,
                            displayName: persistedCore?.displayName ?? coreID,
                            systemIDs: systemIDs,
                            installedVersions: combinedVersions,
                            activeVersionTag: activeVersionTag,
                            isDownloading: false,
                            downloadProgress: 0,
                            source: persistedCore?.source ?? .buildbot,
                            originURL: persistedCore?.originURL
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

    /// Makes sure that the "latest" symlink of a core points at an existing version.
    /// The symlink can point at a folder that does not exist. This happens when a
    /// version folder is renamed. The function returns the active dylib.
    private func repairLatestSymlink(coreFolder: URL, coreID: String, versionFolders: [URL]) -> URL? {
        let fileManager = FileManager.default
        let symlinkPath = coreFolder.appendingPathComponent("\(coreID).dylib")

        // The symlink is correct when it points at an existing dylib.
        let currentTarget = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path)
        if let currentTarget {
            let target = URL(fileURLWithPath: currentTarget, relativeTo: coreFolder).standardizedFileURL
            if fileManager.fileExists(atPath: target.path) {
                return target
            }
        }

        // The symlink is missing or points at a file that is not there. Use the
        // build date of the old target to find the version folder.
        var target: URL?
        if let currentTarget {
            let oldFolderName = URL(fileURLWithPath: currentTarget).deletingLastPathComponent().lastPathComponent
            if let oldDate = CoreManager.parseBuildDate(oldFolderName) {
                target = versionFolders.first { folder in
                    guard let date = CoreManager.parseBuildDate(CoreManager.parseVersionFolderName(folder.lastPathComponent).buildDate) else { return false }
                    return abs(date.timeIntervalSince(oldDate)) < 60
                }
            }
        }

        // Use the newest version folder when the old target does not exist.
        if target == nil {
            target = versionFolders
                .filter { $0.hasDirectoryPath }
                .compactMap { folder -> (Date, URL)? in
                    let buildDate = CoreManager.parseVersionFolderName(folder.lastPathComponent).buildDate
                    guard let date = CoreManager.parseBuildDate(buildDate) else { return nil }
                    return (date, folder)
                }
                .max { $0.0 < $1.0 }?.1
        }

        guard let target,
              let dylib = try? fileManager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent.hasSuffix(".dylib") }) else { return nil }

        // Point the symlink at the version folder again.
        try? fileManager.removeItem(at: symlinkPath)
        try? fileManager.createSymbolicLink(at: symlinkPath, withDestinationURL: dylib)
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Repaired the active version symlink of \(coreID) -> \(dylib.lastPathComponent)")
        #endif
        return dylib
    }

    private func migrateTimestampToVersionFolders(in coreFolder: URL, coreID: String) {
        // Migration logic for old timestamp-based structure → new version-based
        guard FileManager.default.fileExists(atPath: coreFolder.path) else { return }

        do {
            let folders = try FileManager.default.contentsOfDirectory(at: coreFolder, includingPropertiesForKeys: nil)
            for folder in folders {
                // Old format: "2024-01-01 12-00-00" (timestamp folder)
                // New format: "version-buildDate"
                let folderName = folder.lastPathComponent
                let isOldTimestampFolder = folderName.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                if isOldTimestampFolder {
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
                        LoggerService.debug(category: "CoreManager", "Migrated \(coreID) from timestamp to version folder")
                        #endif
                    }
                }
            }
        } catch {
            LoggerService.error(category: "CoreManager", "Migration error for \(coreID): \(error)")
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
        // 0. Builtin map for custom cores with no buildbot or info entry
        if coreID == "suyu_libretro" {
            var switchIDs = Set(["switch"])
            switchIDs.formUnion(SystemDatabase.compatibleIDs(for: "switch"))
            return Array(switchIDs)
        }        // 1. Get systems that explicitly list this core as their 'defaultCoreID'
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

    /// Core IDs installable only via custom import (no buildbot entry).
    static let knownCustomCoreIDs: Set<String> = ["suyu_libretro"]

    /// True when a system can be enabled via custom import even with no buildbot core.
    static func customCoreAvailable(for systemID: String) -> Bool {
        guard let sys = SystemDatabase.system(forID: systemID), let def = sys.defaultCoreID else { return false }
        return knownCustomCoreIDs.contains(def)
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

    // MARK: - Custom core import (non-buildbot, e.g. suyu)

    /// Installs a custom core from a local .zip or .dylib file.
    /// Keeps companion files (e.g. suyu_libretro_libs) beside the dylib.
    func installCustomCore(from pickedURL: URL, systemIDs: [String], originURL: URL? = nil) async throws -> LibretroCore {
        let fm = FileManager.default
        let needsStop = pickedURL.startAccessingSecurityScopedResource()
        defer { if needsStop { pickedURL.stopAccessingSecurityScopedResource() } }

        let stagingDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stagingDir) }

        // Copy picked file into staging so sandbox reads stay valid.
        let stagedInput = stagingDir.appendingPathComponent(pickedURL.lastPathComponent)
        try fm.copyItem(at: pickedURL, to: stagedInput)

        // Resolve payload dir: unzip zips, use dylib dir directly.
        let payloadDir = stagingDir.appendingPathComponent("payload", isDirectory: true)
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        if stagedInput.pathExtension.lowercased() == "zip" {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-xk", stagedInput.path, payloadDir.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw NSError(domain: "CoreManager", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Unzip failed."])
            }
        } else {
            try fm.copyItem(at: stagedInput, to: payloadDir.appendingPathComponent(stagedInput.lastPathComponent))
        }

        // Find the core dylib. Prefer *_libretro.dylib, else first .dylib.
        guard let dylibURL = findCoreDylib(in: payloadDir) else {
            throw NSError(domain: "CoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No .dylib found in the picked file."])
        }
        let coreID = dylibURL.deletingPathExtension().lastPathComponent
        let dylibName = dylibURL.lastPathComponent

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd-HHmm"
        let buildDate = dateFmt.string(from: Date())
        let coreFolder = appSupportURL.appendingPathComponent(coreID, isDirectory: true)
        let versionFolder = coreFolder.appendingPathComponent("custom-\(buildDate)", isDirectory: true)
        try fm.createDirectory(at: versionFolder, withIntermediateDirectories: true)

        // Move full payload contents so companion libs stay beside the dylib.
        // If the dylib sits in a subfolder, move its siblings. Else move top level.
        let sourceDir = dylibURL.deletingLastPathComponent()
        let payloadItems = try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        for item in payloadItems {
            let dest = versionFolder.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: item, to: dest)
        }

        let installedDylib = versionFolder.appendingPathComponent(dylibName)
        await prepareBinaries(in: versionFolder)
        guard fm.fileExists(atPath: installedDylib.path) else {
            throw NSError(domain: "CoreManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Core dylib missing after install."])
        }

        let displayName = coreID
            .replacingOccurrences(of: "_libretro", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        let resolvedSystems = Array(Set(systemIDs + CoreManager.supportedSystems(for: coreID)))
        let coreVersion = CoreVersion(
            version: "custom",
            buildDate: buildDate,
            dylibPath: installedDylib,
            downloadedAt: Date(),
            remoteURL: originURL,
            isActive: true
        )

        // Symlink Cores/<id>/<id>.dylib points at the installed dylib.
        let symlinkPath = coreFolder.appendingPathComponent(coreID + ".dylib")
        if fm.fileExists(atPath: symlinkPath.path) { try? fm.removeItem(at: symlinkPath) }
        try fm.createSymbolicLink(at: symlinkPath, withDestinationURL: installedDylib)

        if let idx = installedCores.firstIndex(where: { $0.id == coreID }) {
            installedCores[idx].installedVersions.removeAll { $0.dylibPath.path == installedDylib.path }
            installedCores[idx].installedVersions.append(coreVersion)
            installedCores[idx].activeVersionTag = coreVersion.tag
            installedCores[idx].displayName = installedCores[idx].displayName.isEmpty ? displayName : installedCores[idx].displayName
            installedCores[idx].source = .custom
            if originURL != nil { installedCores[idx].originURL = originURL }
            if !resolvedSystems.isEmpty { installedCores[idx].systemIDs = resolvedSystems }
        } else {
            installedCores.append(LibretroCore(
                id: coreID,
                displayName: displayName,
                systemIDs: resolvedSystems,
                installedVersions: [coreVersion],
                activeVersionTag: coreVersion.tag,
                source: .custom,
                originURL: originURL
            ))
        }

        await CoreOptionsManager.shared.discoverOptions(for: coreID, dylibPath: installedDylib.path, romPath: nil)
        saveInstalledCores()
        LoggerService.info(category: "CoreManager", "Installed custom core \(coreID)")
        return installedCores.first(where: { $0.id == coreID })!
    }

    /// Downloads a custom core zip from a URL (e.g. GitHub release) then installs it.
    func installCustomCore(fromURL url: URL, systemIDs: [String]) async throws -> LibretroCore {
        downloadPhase = .fetchingFromURL
        downloadCoreName = url.lastPathComponent
        defer { downloadPhase = .idle; downloadCoreName = "" }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        let (tmpURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "CoreManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        downloadPhase = .installing
        // Move to a stable temp path with the remote filename so extension checks work.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: staged)
        try FileManager.default.moveItem(at: tmpURL, to: staged)
        return try await installCustomCore(from: staged, systemIDs: systemIDs, originURL: url)
    }

    private func findCoreDylib(in dir: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        var fallback: URL?
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension.lowercased() == "dylib" else { continue }
            if file.lastPathComponent.contains("_libretro") { return file }
            fallback = fallback ?? file
        }
        return fallback
    }

    /// Clears quarantine and ad-hoc signs every binary in a custom core folder.
    private func prepareBinaries(in folder: URL) async {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            let ext = file.pathExtension.lowercased()
            guard ext == "dylib" || ext == "so" else { continue }
            await prepareCore(at: file.path)
        }
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

        // Refresh the outdated-cores list after a full system update
        await refreshOutdatedCores()
    }

    /// Updates `coresNeedingUpdate` with the cores whose version differs from the
    /// latest version. The installed versions must already be resolved.
    private func refreshOutdatedCores() {
        var outdated: [LibretroCore] = []
        for installed in installedCores {
            guard let availableVersion = availableVersion(for: installed.id),
                  let installedVersion = installedVersion(for: installed),
                  !installedVersion.isEmpty else { continue }
            if installedVersion != availableVersion {
                outdated.append(installed)
            }
        }
        coresNeedingUpdate = outdated
        #if LOG_DEBUG
        LoggerService.debug(category: "CoreManager", "Refreshed outdated cores: \(outdated.count) need updating")
        #endif
    }
}


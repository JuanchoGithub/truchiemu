import Foundation
import Combine
import Darwin
import AppKit
import SwiftData

@MainActor
class CoreManager: ObservableObject {
    static let shared = CoreManager()
    
    @Published var installedCores: [LibretroCore] = []
    @Published var availableCores: [RemoteCoreInfo] = []
    @Published var isFetchingCoreList: Bool = false
    @Published var pendingDownload: PendingCoreDownload? = nil
    private let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchieEmu/Cores", isDirectory: true)
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

    /// Whether to trigger an automatic core list fetch from the buildbot. Returns true only on first launch with no cached data.
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
        loadInstalledCores()
        loadAvailableCores()
        LibretroInfoManager.loadMappings()
    }

    // MARK: - Core List

    func fetchAvailableCores() async {
        isFetchingCoreList = true
        defer { isFetchingCoreList = false }

        LoggerService.info(category: "CoreManager", "Fetching available cores from \(buildbotBase)")
        
        var request = URLRequest(url: buildbotBase)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        LoggerService.debug(category: "CoreManager", "Request: \(request)")

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

        // Parse the HTML index page for .dylib.zip links - handle both " and ' and relative/absolute paths
        let pattern = #"href=['"]([^'"]+_libretro\.dylib\.zip)['"]"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        LoggerService.debug(category: "CoreManager", "Found \(matches.count) core links in HTML")

        var cores: [RemoteCoreInfo] = []
        for match in matches {
            LoggerService.debug(category: "CoreManager", "Match: \(match)")
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let fileNameFull = String(html[range])
            // Extract just the filename if it's a full URL or path
            let fileName = (fileNameFull as NSString).lastPathComponent
            
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

            cores.append(RemoteCoreInfo(
                coreID: coreID,
                fileName: fileName,
                downloadURL: downloadURL,
                systemIDs: systemIDs,
                displayName: displayName
            ))
        }
        availableCores = cores.sorted { $0.displayName < $1.displayName }
        LoggerService.debug(category: "CoreManager", "Available cores: \(availableCores)")
        saveAvailableCores()
        LoggerService.debug(category: "CoreManager", "Available cores saved")
        AppSettings.setBool(coresInitialFetchDoneKey, value: true)
        LoggerService.debug(category: "CoreManager", "Available cores initial fetch done")
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
            LoggerService.debug(category: "CoreManager", "PendingCoreDownload initialized")
        }

        /// Convenience: true when launch context is provided
        var hasLaunchContext: Bool { romID != nil && systemID != nil }
    }

    func requestCoreDownload(
        for coreID: String,
        systemID: String? = nil,
        romID: UUID? = nil,
        slotToLoad: Int? = nil
    ) {
        LoggerService.debug(category: "CoreManager", "Requesting core download for: \(coreID)")
        // Find in available list
        if let remote = availableCores.first(where: { $0.coreID == coreID }) {
            LoggerService.debug(category: "CoreManager", "Found remote core: \(remote)")
            pendingDownload = PendingCoreDownload(
                coreInfo: remote,
                romID: romID,
                systemID: systemID,
                slotToLoad: slotToLoad
            )
        } else {
            LoggerService.debug(category: "CoreManager", "Core not found in available list, building synthetic RemoteCoreInfo")
            // Build a synthetic RemoteCoreInfo
            let fileName = "\(coreID).dylib.zip"
            let url = buildbotBase.appendingPathComponent(fileName)
            let displayName = coreID
                .replacingOccurrences(of: "_libretro", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            let info = RemoteCoreInfo(coreID: coreID, fileName: fileName, downloadURL: url,
                                      systemIDs: systemID.map { [$0] } ?? [], displayName: displayName)
            pendingDownload = PendingCoreDownload(
                coreInfo: info,
                romID: romID,
                systemID: systemID,
                slotToLoad: slotToLoad
            )
            LoggerService.debug(category: "CoreManager", "Pending core download set: \(pendingDownload)")
        }
    }

    func downloadCore(_ info: RemoteCoreInfo) async {
        LoggerService.debug(category: "CoreManager", "Starting download: \(info.coreID) from \(info.downloadURL)")
        
        // Mark as downloading
        if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
            LoggerService.debug(category: "CoreManager", "Found installed core: \(info.coreID)")
            installedCores[idx].isDownloading = true
        } else {
            LoggerService.debug(category: "CoreManager", "Core not found in installed cores, adding new core")
            installedCores.append(LibretroCore(id: info.coreID, displayName: info.displayName,
                                               systemIDs: info.systemIDs, installedVersions: [],
                                               isDownloading: true))
        }

        do {
            LoggerService.debug(category: "CoreManager", "Downloading core: \(info.coreID)")
            var request = URLRequest(url: info.downloadURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            LoggerService.debug(category: "CoreManager", "Request: \(request)")
            let (tmpURL, response) = try await URLSession.shared.download(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                LoggerService.error(category: "CoreManager", "Server returned HTTP \(http.statusCode)")
                throw NSError(domain: "CoreManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"])
            }
            
            // Use date and time for tag to ensure uniqueness if downloaded on same day
            let tag = ISO8601DateFormatter().string(from: Date()).prefix(19).description
                .replacingOccurrences(of: "T", with: " ")
                .replacingOccurrences(of: ":", with: "-")

            // Destination folder
            let coreFolder = appSupportURL.appendingPathComponent("\(info.coreID)/\(tag)", isDirectory: true)
            try FileManager.default.createDirectory(at: coreFolder, withIntermediateDirectories: true)
            LoggerService.debug(category: "CoreManager", "Core folder created: \(coreFolder.path)")

            // Unzip
            let dylibName = info.fileName.replacingOccurrences(of: ".zip", with: "")
            let dylibDest = coreFolder.appendingPathComponent(dylibName)
            
            LoggerService.debug(category: "CoreManager", "Unzipping to: \(dylibDest.path)")
            try await unzip(zipURL: tmpURL, extracting: dylibName, to: dylibDest)
            LoggerService.debug(category: "CoreManager", "Unzipped successfully")

            let version = CoreVersion(tag: tag, dylibPath: dylibDest, downloadedAt: Date(), remoteURL: info.downloadURL)
            LoggerService.debug(category: "CoreManager", "Core version created: \(version)")

            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                // Ensure no duplicate path entries exist
                installedCores[idx].installedVersions.removeAll { $0.dylibPath.path == dylibDest.path }
                installedCores[idx].installedVersions.append(version)
                installedCores[idx].activeVersionTag = tag
                installedCores[idx].isDownloading = false
                installedCores[idx].downloadProgress = 0
            }
            LoggerService.debug(category: "CoreManager", "Installed cores: \(installedCores)")
            saveInstalledCores()
            LoggerService.info(category: "CoreManager", "Successfully installed \(info.coreID)")
        } catch {
            LoggerService.error(category: "CoreManager", "Download failed for \(info.coreID): \(error.localizedDescription)")
            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                LoggerService.debug(category: "CoreManager", "Found installed core: \(info.coreID)")
                installedCores[idx].isDownloading = false
            }
            LoggerService.error(category: "CoreManager", "Download failed for \(info.coreID): \(error.localizedDescription)")
        }
    }

    // MARK: - Core lookup

    func defaultCore(for systemID: String) -> LibretroCore? {
        guard let system = SystemDatabase.system(forID: systemID),
              let coreID = system.defaultCoreID else { return nil }
        LoggerService.debug(category: "CoreManager", "Default core \(coreID) for system \(systemID)")
        return installedCores.first { $0.id == coreID }
    }

    func isInstalled(coreID: String) -> Bool {
        let result = installedCores.first(where: { $0.id == coreID })?.isInstalled ?? false
        LoggerService.debug(category: "CoreManager", "Is installed: \(coreID) -> \(result)")
        return result
    }

    func setActiveVersion(coreID: String, tag: String) {
        LoggerService.debug(category: "CoreManager", "Set active version: \(coreID) -> \(tag)")
        if let idx = installedCores.firstIndex(where: { $0.id == coreID }) {
            LoggerService.debug(category: "CoreManager", "Found installed core: \(coreID)")
            installedCores[idx].activeVersionTag = tag
            saveInstalledCores()
            LoggerService.debug(category: "CoreManager", "Installed cores: \(installedCores)")
        }
    }

    func deleteCore(_ core: LibretroCore) {
        // Remove from disk
        let folder = appSupportURL.appendingPathComponent(core.id)
        LoggerService.debug(category: "CoreManager", "Deleting core: \(core.id)")
        try? FileManager.default.removeItem(at: folder)
        LoggerService.debug(category: "CoreManager", "Core deleted: \(core.id)")
        // Remove from list
        installedCores.removeAll { $0.id == core.id }
        saveInstalledCores()
        LoggerService.debug(category: "CoreManager", "Core removed from list: \(core.id)")
    }

    // MARK: - Persistence

    private func saveInstalledCores() {
        if let data = try? encoder.encode(installedCores) {
            AppSettings.setData(coresKey, value: data)
            LoggerService.debug(category: "CoreManager", "Installed cores saved: \(installedCores)")
        }
    }

    private func loadInstalledCores() {
        guard let data = AppSettings.getData(coresKey),
              var saved = try? decoder.decode([LibretroCore].self, from: data) else { return }
        
        // Migrate/Refresh systemIDs for installed cores and deduplicate versions
        LoggerService.debug(category: "CoreManager", "Loading installed cores")
        for i in 0..<saved.count {
            saved[i].systemIDs = CoreManager.supportedSystems(for: saved[i].id)
            
            // Fix existing data corruption: ensure each version has a unique path
            var seenPaths = Set<String>()
            saved[i].installedVersions = saved[i].installedVersions.filter { v in
                let path = v.dylibPath.path
                if seenPaths.contains(path) { return false }
                seenPaths.insert(path)
                LoggerService.debug(category: "CoreManager", "Loading installed core \(saved[i].id) version: \(v.tag)")
                return true
            }
        }
        
        installedCores = saved
    }

    private func loadAvailableCores() {
        guard let data = AppSettings.getData(availableCoresKey),
              var saved = try? decoder.decode([RemoteCoreInfo].self, from: data) else { return }
        // Refresh systemIDs so updates to supportedSystems mappings are applied to cached data
        LoggerService.debug(category: "CoreManager", "Loading available cores")
        for i in 0..<saved.count {
            LoggerService.debug(category: "CoreManager", "Loading available core: \(saved[i].coreID)")
            saved[i].systemIDs = CoreManager.supportedSystems(for: saved[i].coreID)
        }
        availableCores = saved
    }

    private func saveAvailableCores() {
        if let data = try? encoder.encode(availableCores) {
            AppSettings.setData(availableCoresKey, value: data)
            LoggerService.debug(category: "CoreManager", "Available cores saved: \(availableCores)")
        }
    }

    static func supportedSystems(for coreID: String) -> [String] {
        // 1. Get systems that explicitly list this core as their 'defaultCoreID'
        var ids = SystemDatabase.systems.filter { $0.defaultCoreID == coreID }.map { $0.id }
        
        // 2. Check our dynamic map (built from the Libretro .info files)
        let coreIDNormalized = coreID.replacingOccurrences(of: "_libretro", with: "")
        if let dynamicIDs = LibretroInfoManager.coreToSystemMap[coreIDNormalized] {
            ids.append(contentsOf: dynamicIDs)
        }
        
        // 3. Fallback/Safety: Hardcoded MAME alias if still needed
        if coreID.contains("mame") { ids.append("mame") }
        
        // Return unique results
        return Array(Set(ids))
    }

    // MARK: - Minimal ZIP extraction

    private func unzip(zipURL: URL, extracting targetName: String, to destination: URL) async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        LoggerService.debug(category: "CoreManager", "Unzipping core: \(zipURL.path) to \(tmpDir.path)")

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
        LoggerService.debug(category: "CoreManager", "Searching for file: \(targetName)")
        while let fileURL = enumerator?.nextObject() as? URL {
            LoggerService.debug(category: "CoreManager", "Found file: \(fileURL.path)")
            if fileURL.lastPathComponent == targetName {
                foundURL = fileURL
                break
            }
        }

        if let dylib = foundURL {
            LoggerService.debug(category: "CoreManager", "Found dylib: \(dylib.path)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: dylib, to: destination)
            await prepareCore(at: destination.path)
            LoggerService.debug(category: "CoreManager", "Core prepared: \(destination.path)")
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
        LoggerService.debug(category: "CoreManager", "Codesigning core: \(path)")
        try? proc.run()
        proc.waitUntilExit()
        LoggerService.debug(category: "CoreManager", "Core codesigned: \(path)")
        #endif
    }
    @MainActor
    func performFullSystemUpdate() async {
        isFetchingCoreList = true
        // Use the LibretroInfoManager singleton to piggyback its status updates
        let infoManager = LibretroInfoManager.shared
        LoggerService.debug(category: "CoreManager", "Starting full system update")
        
        // Step 1: Update System/File Extension Database
        await infoManager.refreshCoreInfo()
        LoggerService.debug(category: "CoreManager", "System/File Extension Database updated")
    
        // Step 2: Fetch the actual Core binaries from Libretro buildbot
        await fetchAvailableCores()
        LoggerService.debug(category: "CoreManager", "Core binaries fetched")
    
        // Step 3: Cleanup/Post-process
        isFetchingCoreList = false
        infoManager.refreshStatus = "Full System Update Complete!"
        LoggerService.debug(category: "CoreManager", "Full System Update Complete!")
    
        // Trigger a UI refresh if your views are observing SystemPreferences
        SystemPreferences.shared.updateTrigger += 1
    }
}

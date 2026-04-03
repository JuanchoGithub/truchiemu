import Foundation
import Combine
import Darwin

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

    private let defaults = UserDefaults.standard
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
        let hasBeenFetched = defaults.bool(forKey: coresInitialFetchDoneKey)
        return !hasCache && !hasBeenFetched
    }

    var buildbotBase: URL {
        URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/")!
    }

    init() {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
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

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            LoggerService.info(category: "CoreManager", "Failed to fetch core list: Network error")
            return
        }
        
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            LoggerService.info(category: "CoreManager", "Failed to fetch core list: HTTP \(http.statusCode)")
            return
        }

        guard let html = String(data: data, encoding: .utf8) else { 
            LoggerService.info(category: "CoreManager", "Failed to parse core list: Encoding error")
            return 
        }

        // Parse the HTML index page for .dylib.zip links - handle both " and ' and relative/absolute paths
        let pattern = #"href=['"]([^'"]+_libretro\.dylib\.zip)['"]"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        LoggerService.debug(category: "CoreManager", "Found \(matches.count) core links in HTML")

        var cores: [RemoteCoreInfo] = []
        for match in matches {
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
        saveAvailableCores()
        defaults.set(true, forKey: coresInitialFetchDoneKey)
    }

    // MARK: - Download (user must authorize via pendingDownload)

    struct PendingCoreDownload: Identifiable {
        var id: String { coreInfo.coreID }
        let coreInfo: RemoteCoreInfo
    }

    func requestCoreDownload(for coreID: String, systemID: String? = nil) {
        // Find in available list
        if let remote = availableCores.first(where: { $0.coreID == coreID }) {
            pendingDownload = PendingCoreDownload(coreInfo: remote)
        } else {
            // Build a synthetic RemoteCoreInfo
            let fileName = "\(coreID).dylib.zip"
            let url = buildbotBase.appendingPathComponent(fileName)
            let displayName = coreID
                .replacingOccurrences(of: "_libretro", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            let info = RemoteCoreInfo(coreID: coreID, fileName: fileName, downloadURL: url,
                                      systemIDs: systemID.map { [$0] } ?? [], displayName: displayName)
            pendingDownload = PendingCoreDownload(coreInfo: info)
        }
    }

    func downloadCore(_ info: RemoteCoreInfo) async {
        LoggerService.info(category: "CoreManager", "Starting download: \(info.coreID) from \(info.downloadURL)")
        
        // Mark as downloading
        if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
            installedCores[idx].isDownloading = true
        } else {
            installedCores.append(LibretroCore(id: info.coreID, displayName: info.displayName,
                                               systemIDs: info.systemIDs, installedVersions: [],
                                               isDownloading: true))
        }

        do {
            var request = URLRequest(url: info.downloadURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            
            let (tmpURL, response) = try await URLSession.shared.download(for: request)
            
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "CoreManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"])
            }
            
            // Use date and time for tag to ensure uniqueness if downloaded on same day
            let tag = ISO8601DateFormatter().string(from: Date()).prefix(19).description
                .replacingOccurrences(of: "T", with: " ")
                .replacingOccurrences(of: ":", with: "-")

            // Destination folder
            let coreFolder = appSupportURL.appendingPathComponent("\(info.coreID)/\(tag)", isDirectory: true)
            try FileManager.default.createDirectory(at: coreFolder, withIntermediateDirectories: true)

            // Unzip
            let dylibName = info.fileName.replacingOccurrences(of: ".zip", with: "")
            let dylibDest = coreFolder.appendingPathComponent(dylibName)
            
            LoggerService.debug(category: "CoreManager", "Unzipping to \(dylibDest.path)")
            try await unzip(zipURL: tmpURL, extracting: dylibName, to: dylibDest)

            let version = CoreVersion(tag: tag, dylibPath: dylibDest, downloadedAt: Date(), remoteURL: info.downloadURL)

            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                // Ensure no duplicate path entries exist
                installedCores[idx].installedVersions.removeAll { $0.dylibPath.path == dylibDest.path }
                installedCores[idx].installedVersions.append(version)
                installedCores[idx].activeVersionTag = tag
                installedCores[idx].isDownloading = false
                installedCores[idx].downloadProgress = 0
            }

            saveInstalledCores()
            LoggerService.info(category: "CoreManager", "Successfully installed \(info.coreID)")
        } catch {
            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                installedCores[idx].isDownloading = false
            }
            LoggerService.info(category: "CoreManager", "Download failed for \(info.coreID): \(error.localizedDescription)")
        }
    }

    // MARK: - Core lookup

    func defaultCore(for systemID: String) -> LibretroCore? {
        guard let system = SystemDatabase.system(forID: systemID),
              let coreID = system.defaultCoreID else { return nil }
        return installedCores.first { $0.id == coreID }
    }

    func isInstalled(coreID: String) -> Bool {
        installedCores.first(where: { $0.id == coreID })?.isInstalled ?? false
    }

    func setActiveVersion(coreID: String, tag: String) {
        if let idx = installedCores.firstIndex(where: { $0.id == coreID }) {
            installedCores[idx].activeVersionTag = tag
            saveInstalledCores()
        }
    }

    func deleteCore(_ core: LibretroCore) {
        // Remove from disk
        let folder = appSupportURL.appendingPathComponent(core.id)
        try? FileManager.default.removeItem(at: folder)
        
        // Remove from list
        installedCores.removeAll { $0.id == core.id }
        saveInstalledCores()
    }

    // MARK: - Persistence

    private func saveInstalledCores() {
        if let data = try? encoder.encode(installedCores) {
            defaults.set(data, forKey: coresKey)
        }
    }

    private func loadInstalledCores() {
        guard let data = defaults.data(forKey: coresKey),
              var saved = try? decoder.decode([LibretroCore].self, from: data) else { return }
        
        // Migrate/Refresh systemIDs for installed cores and deduplicate versions
        for i in 0..<saved.count {
            saved[i].systemIDs = CoreManager.supportedSystems(for: saved[i].id)
            
            // Fix existing data corruption: ensure each version has a unique path
            var seenPaths = Set<String>()
            saved[i].installedVersions = saved[i].installedVersions.filter { v in
                let path = v.dylibPath.path
                if seenPaths.contains(path) { return false }
                seenPaths.insert(path)
                return true
            }
        }
        
        installedCores = saved
    }

    private func loadAvailableCores() {
        guard let data = defaults.data(forKey: availableCoresKey),
              let saved = try? decoder.decode([RemoteCoreInfo].self, from: data) else { return }
        availableCores = saved
    }

    private func saveAvailableCores() {
        if let data = try? encoder.encode(availableCores) {
            defaults.set(data, forKey: availableCoresKey)
        }
    }

    static func supportedSystems(for coreID: String) -> [String] {
        var ids = SystemDatabase.systems.filter { $0.defaultCoreID == coreID }.map { $0.id }
        
        // Hardcoded capabilities for common multi-system cores
        if coreID.contains("mgba") { ids += ["gba", "gb", "gbc"] }
        if coreID.contains("mesen") { ids += ["nes", "snes", "gb"] }
        if coreID.contains("genesis_plus_gx") { ids += ["genesis", "sms", "gamegear"] }
        if coreID.contains("snes9x") { ids += ["snes"] }
        if coreID.contains("mupen64plus") || coreID.contains("parallel_n64") { ids += ["n64"] }
        if coreID.contains("picodrive") { ids += ["genesis", "sms", "gamegear", "32x"] }
        if coreID.contains("mednafen_psx") { ids += ["psx"] }
        if coreID.contains("dosbox_pure") { ids += ["dos"] }
        
        return Array(Set(ids))
    }

    // MARK: - Minimal ZIP extraction

    private func unzip(zipURL: URL, extracting targetName: String, to destination: URL) async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-xk", zipURL.path, tmpDir.path]
        
        try proc.run()
        proc.waitUntilExit()
        
        if proc.terminationStatus != 0 {
            throw NSError(domain: "CoreManager", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ditto failed with exit code \(proc.terminationStatus)"])
        }

        // Recursive search for the dylib
        let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: nil)
        var foundURL: URL?
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == targetName {
                foundURL = fileURL
                break
            }
        }

        if let dylib = foundURL {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: dylib, to: destination)
            await prepareCore(at: destination.path)
        } else {
            LoggerService.info(category: "CoreManager", "Failed to find \(targetName) in unzipped archive.")
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
        try? proc.run()
        proc.waitUntilExit()
        #endif
    }
}

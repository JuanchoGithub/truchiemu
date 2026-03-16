import Foundation
import Combine
import Darwin

@MainActor
class CoreManager: ObservableObject {
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    var buildbotBase: URL {
        URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(arch)/latest/")!
    }

    init() {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        loadInstalledCores()
    }

    // MARK: - Core List

    func fetchAvailableCores() async {
        isFetchingCoreList = true
        defer { isFetchingCoreList = false }

        guard let (data, _) = try? await URLSession.shared.data(from: buildbotBase),
              let html = String(data: data, encoding: .utf8) else { return }

        // Parse the HTML index page for .dylib.zip links
        let pattern = #"href="([^"]+_libretro\.dylib\.zip)""#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        var cores: [RemoteCoreInfo] = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let fileName = String(html[range])
            let downloadURL = buildbotBase.appendingPathComponent(fileName)
            let coreID = fileName
                .replacingOccurrences(of: ".dylib.zip", with: "")
                .replacingOccurrences(of: ".dll.zip", with: "")

            let displayName = coreID
                .replacingOccurrences(of: "_libretro", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")

            let systemIDs = SystemDatabase.systems
                .filter { $0.defaultCoreID == coreID }
                .map { $0.id }

            cores.append(RemoteCoreInfo(
                coreID: coreID,
                fileName: fileName,
                downloadURL: downloadURL,
                systemIDs: systemIDs,
                displayName: displayName
            ))
        }
        availableCores = cores.sorted { $0.displayName < $1.displayName }
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
        // Mark as downloading
        if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
            installedCores[idx].isDownloading = true
        } else {
            installedCores.append(LibretroCore(id: info.coreID, displayName: info.displayName,
                                               systemIDs: info.systemIDs, installedVersions: [],
                                               isDownloading: true))
        }

        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: info.downloadURL)
            let tag = ISO8601DateFormatter().string(from: Date()).prefix(10).description

            // Destination folder
            let coreFolder = appSupportURL.appendingPathComponent("\(info.coreID)/\(tag)", isDirectory: true)
            try FileManager.default.createDirectory(at: coreFolder, withIntermediateDirectories: true)

            // Unzip
            let dylibName = info.fileName.replacingOccurrences(of: ".zip", with: "")
            let dylibDest = coreFolder.appendingPathComponent(dylibName)
            try await unzip(zipURL: tmpURL, extracting: dylibName, to: dylibDest)

            let version = CoreVersion(tag: tag, dylibPath: dylibDest, downloadedAt: Date(), remoteURL: info.downloadURL)

            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                installedCores[idx].installedVersions.append(version)
                installedCores[idx].activeVersionTag = tag
                installedCores[idx].isDownloading = false
                installedCores[idx].downloadProgress = 0
            }

            saveInstalledCores()
        } catch {
            if let idx = installedCores.firstIndex(where: { $0.id == info.coreID }) {
                installedCores[idx].isDownloading = false
            }
            print("[CoreManager] Download failed: \(error)")
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
              let saved = try? decoder.decode([LibretroCore].self, from: data) else { return }
        installedCores = saved
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
            print("[CoreManager] Failed to find \(targetName) in unzipped archive.")
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

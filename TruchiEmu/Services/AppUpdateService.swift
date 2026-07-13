import Foundation

private enum updateLog {
    static func info(_ message: String) { LoggerService.info(category: "AppUpdate", message) }
    static func warning(_ message: String) { LoggerService.warning(category: "AppUpdate", message) }
}

enum AppVersion {
    static let current: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }()

    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }()

    static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return .orderedDescending }
            if p1 < p2 { return .orderedAscending }
        }
        return .orderedSame
    }
}

struct AppRelease: Identifiable {
    var id: String { tagName }
    let tagName: String
    let name: String
    let body: String
    let htmlURL: String
    let publishedAt: Date?
    let assetDownloadURL: String?
    let assetName: String?

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var isCurrent: Bool {
        version == AppVersion.current
    }

    var isNewer: Bool {
        AppVersion.compare(version, AppVersion.current) == .orderedDescending
    }
}

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    private let owner = "JuanchoGithub"
    private let repo = "truchiemu"
    private let releasesURL = "https://api.github.com/repos/JuanchoGithub/truchiemu/releases"
    private let changelogURL = "https://github.com/JuanchoGithub/truchiemu/releases"

    @Published var latestRelease: AppRelease?
    @Published var pendingStartupUpdate: AppRelease?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var isInstalling = false
    @Published var downloadProgress: Double = 0
    @Published var totalBytesWritten: Int64 = 0
    @Published var totalBytesExpected: Int64 = 0
    @Published var allReleases: [AppRelease] = []

    var updateAvailable: Bool {
        guard latestRelease != nil else { return false }
        #if LOG_DEBUG
        return true
        #else
        return latestRelease!.isNewer
        #endif
    }

    var newerReleases: [AppRelease] {
        allReleases.filter { AppVersion.compare($0.version, AppVersion.current) == .orderedDescending }
    }

    private init() {}

    var autoCheckEnabled: Bool {
        get { AppSettings.getBool("autoCheckUpdates", defaultValue: true) }
        set { AppSettings.setBool("autoCheckUpdates", value: newValue) }
    }

    var lastCheckDate: Date? {
        AppSettings.getDate("lastUpdateCheckDate")
    }

    var skippedVersion: String? {
        AppSettings.getString("skippedUpdateVersion")
    }

    func skipVersion(_ version: String) {
        AppSettings.setString("skippedUpdateVersion", value: version)
    }

    func checkForUpdates() async -> AppRelease? {
        guard !isChecking else { return nil }
        isChecking = true
        defer { isChecking = false }

        updateLog.info("Checking for updates...")

        guard let url = URL(string: releasesURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TruchiEmu/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                updateLog.warning("GitHub API returned non-200 status")
                return nil
            }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            let appReleases = releases.map { $0.toAppRelease() }
            allReleases = appReleases

            AppSettings.setDate("lastUpdateCheckDate", value: Date())

            #if LOG_DEBUG
            if let latest = appReleases.first {
                latestRelease = latest
                updateLog.info("[LOG_DEBUG] Presenting latest release for testing: \(latest.version)")
                return latest
            }
            return nil
            #else
            if let latest = appReleases.first, latest.isNewer {
                if let skipped = skippedVersion, skipped == latest.version {
                    updateLog.info("Skipping version \(latest.version) (user dismissed)")
                    latestRelease = nil
                    return nil
                }
                latestRelease = latest
                updateLog.info("Update available: \(latest.version)")
                return latest
            } else {
                latestRelease = nil
                updateLog.info("App is up to date")
                return nil
            }
            #endif
        } catch {
            updateLog.warning("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    func downloadAndInstall(release: AppRelease) async {
        let installURL = await downloadUpdateOnly(release: release)
        guard installURL != nil else { return }
        relaunchAfterUpdate(at: installURL!)
    }

    func downloadUpdateOnly(release: AppRelease) async -> URL? {
        guard let assetURL = release.assetDownloadURL, let url = URL(string: assetURL) else {
            updateLog.warning("No download URL for release \(release.tagName)")
            return nil
        }

        isDownloading = true
        downloadProgress = 0
        totalBytesWritten = 0
        totalBytesExpected = 0
        defer { isDownloading = false; downloadTask = nil; downloadContinuation = nil }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = release.assetName ?? "TruchiEmu.zip"
        let localURL = tempDir.appendingPathComponent(fileName)

        do {
            updateLog.info("Downloading update from \(url.absoluteString)")
            var request = URLRequest(url: url)
            request.setValue("TruchiEmu/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 300

            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: sessionConfig, delegate: DownloadDelegate(service: self), delegateQueue: nil)

            let downloadURL = try await withCheckedThrowingContinuation { continuation in
                downloadContinuation = continuation
                downloadTask = session.downloadTask(with: request)
                downloadTask?.resume()
            }

            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: downloadURL, to: localURL)
            updateLog.info("Downloaded to \(localURL.path)")

            isDownloading = false
            isInstalling = true
            defer { isInstalling = false }

            if fileName.hasSuffix(".zip") {
                return try installFromZip(at: localURL)
            } else if fileName.hasSuffix(".dmg") {
                return try installFromDMG(at: localURL)
            }
        } catch {
            updateLog.warning("Download failed: \(error.localizedDescription)")
        }
        return nil
    }

    fileprivate func reportProgress(progress: Double, bytesWritten: Int64, bytesExpected: Int64) {
        downloadProgress = progress
        totalBytesWritten = bytesWritten
        totalBytesExpected = bytesExpected
    }

    fileprivate func downloadFinished(at location: URL) {
        downloadContinuation?.resume(returning: location)
    }

    fileprivate func downloadFailed(_ error: Error) {
        downloadContinuation?.resume(throwing: error)
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }

    private func installFromZip(at zipURL: URL) throws -> URL? {
        try runProcess(executable: "/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, zipURL.deletingLastPathComponent().path])

        let extractedDir = zipURL.deletingLastPathComponent()
        guard let appURL = try FileManager.default.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            NSWorkspace.shared.open(extractedDir)
            return nil
        }
        return try installApp(at: appURL)
    }

    private func installFromDMG(at dmgURL: URL) throws -> URL? {
        let mountTask = Process()
        mountTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountTask.arguments = ["attach", "-nobrowse", "-plist", dmgURL.path]
        let pipe = Pipe()
        mountTask.standardOutput = pipe
        try mountTask.run()
        mountTask.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            return nil
        }
        guard let mountPoint = propertyList.compactMap({ $0["mount-point"] as? String }).first else {
            return nil
        }

        defer {
            try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", "-quiet", mountPoint])
        }

        let mountURL = URL(fileURLWithPath: mountPoint)
        guard let appURL = try FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { return nil }
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagingApp = stagingDir.appendingPathComponent(appURL.lastPathComponent)
        try runProcess(executable: "/usr/bin/ditto", arguments: [appURL.path, stagingApp.path])
        return try installApp(at: stagingApp)
    }

    private func installApp(at sourceAppURL: URL) throws -> URL {
        let dest = URL(fileURLWithPath: "/Applications/\(sourceAppURL.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try runProcess(executable: "/usr/bin/ditto", arguments: [sourceAppURL.path, dest.path])
        try? runProcess(executable: "/usr/bin/xattr", arguments: ["-cr", dest.path])
        updateLog.info("Installed to \(dest.path)")
        return dest
    }

    private func relaunchAfterUpdate(at appURL: URL) {
        updateLog.info("Relaunching from \(appURL.path)")
        AppSettings.flush()
        let bundleURL = appURL
        let executableName = bundleURL.deletingPathExtension().lastPathComponent
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        let process = Process()
        process.executableURL = executableURL
        process.arguments = []
        try? process.run()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    func openReleasesPage() {
        guard let url = URL(string: changelogURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func shouldAutoCheck() -> Bool {
        guard autoCheckEnabled else { return false }
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) > 86400
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String?
    let publishedAt: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    func toAppRelease() -> AppRelease {
        let macAsset = assets.first { asset in
            asset.name.hasSuffix(".zip") || asset.name.hasSuffix(".dmg")
        }
        return AppRelease(
            tagName: tagName,
            name: name ?? tagName,
            body: body ?? "",
            htmlURL: htmlURL ?? "",
            publishedAt: parseDate(publishedAt),
            assetDownloadURL: macAsset?.browserDownloadURL,
            assetName: macAsset?.name
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private let service: AppUpdateService

    init(service: AppUpdateService) {
        self.service = service
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        updateLog.info("Download redirect to \(request.url?.absoluteString ?? "unknown")")
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        updateLog.info("Download finished at \(location.path)")
        let safeLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try FileManager.default.moveItem(at: location, to: safeLocation)
        } catch {
            Task { @MainActor in
                service.downloadFailed(error)
            }
            return
        }
        Task { @MainActor in
            service.downloadFinished(at: safeLocation)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = -1
        }
        let written = totalBytesWritten
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            service.reportProgress(progress: progress, bytesWritten: written, bytesExpected: expected)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            updateLog.warning("Download task failed: \(error.localizedDescription)")
            Task { @MainActor in
                service.downloadFailed(error)
            }
        } else {
            updateLog.info("Download task completed successfully")
        }
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

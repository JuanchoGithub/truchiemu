import AppKit
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
    let isPrerelease: Bool

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var isCurrent: Bool {
        version == AppVersion.current
    }

    var isNewer: Bool {
        AppVersion.compare(version, AppVersion.current) == .orderedDescending
    }

    var isSkippedByUser: Bool {
        AppSettings.getString("skippedUpdateVersion", defaultValue: "") == version
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
        guard let latestRelease else { return false }
        return latestRelease.isNewer
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

            let stableReleases = appReleases.filter { !$0.isPrerelease }
            let latest = stableReleases.max(by: { AppVersion.compare($0.version, $1.version) == .orderedAscending })

            if let latest, latest.isNewer {
                latestRelease = latest
                if latest.isSkippedByUser {
                    updateLog.info("Update available but skipped by user: \(latest.version)")
                    return nil
                }
                updateLog.info("Update available: \(latest.version)")
                return latest
            } else {
                latestRelease = nil
                updateLog.info("App is up to date")
                return nil
            }
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
        if AppSettings.getString("skippedUpdateVersion", defaultValue: "") == release.version {
            AppSettings.remove("skippedUpdateVersion")
        }
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

    private func runProcess(executable: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func updateError(_ message: String) -> Error {
        NSError(domain: "AppUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func installFromZip(at zipURL: URL) throws -> URL? {
        // Extract into our own staging folder. Never scan the shared temp
        // root: it holds WebKit data folders that end with ".app".
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TruchiEmu-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let dittoStatus = try runProcess(executable: "/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, stagingDir.path])
        guard dittoStatus == 0 else {
            throw updateError("Unzip failed with exit code \(dittoStatus)")
        }

        guard let appURL = findAppBundle(in: stagingDir) else {
            updateLog.warning("No valid TruchiEmu.app found in update archive")
            return nil
        }
        return try installApp(at: appURL)
    }

    /// Finds `TruchiEmu.app` under `directory` and checks it is a real bundle.
    /// Ignores decoy folders such as `com.TruchiEmu.app` (WebKit data).
    private func findAppBundle(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "TruchiEmu.app" else { continue }
            enumerator.skipDescendants()
            if validatedAppBundle(at: url) {
                return url
            }
            updateLog.warning("Skipping invalid bundle at \(url.path)")
        }
        return nil
    }

    nonisolated private func validatedAppBundle(at url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              (plist["CFBundleIdentifier"] as? String) == "com.TruchiEmu.app" else {
            return false
        }
        let executableName = (plist["CFBundleExecutable"] as? String) ?? url.deletingPathExtension().lastPathComponent
        var isExecutableDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.appendingPathComponent("Contents/MacOS/\(executableName)").path,
            isDirectory: &isExecutableDirectory
        ), !isExecutableDirectory.boolValue else {
            return false
        }
        return true
    }

    private func installFromDMG(at dmgURL: URL) throws -> URL? {
        let mountTask = Process()
        mountTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountTask.arguments = ["attach", "-nobrowse", "-plist", dmgURL.path]
        let pipe = Pipe()
        mountTask.standardOutput = pipe
        try mountTask.run()
        mountTask.waitUntilExit()
        guard mountTask.terminationStatus == 0 else {
            throw updateError("hdiutil attach failed with exit code \(mountTask.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            return nil
        }
        guard let mountPoint = propertyList.compactMap({ $0["mount-point"] as? String }).first else {
            return nil
        }

        defer {
            let detachStatus = try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", "-quiet", mountPoint])
            if detachStatus != 0 {
                updateLog.warning("hdiutil detach failed with exit code \(detachStatus ?? -1)")
            }
        }

        let mountURL = URL(fileURLWithPath: mountPoint)
        guard let appURL = findAppBundle(in: mountURL) else { return nil }
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }
        let stagingApp = stagingDir.appendingPathComponent(appURL.lastPathComponent)
        let dittoStatus = try runProcess(executable: "/usr/bin/ditto", arguments: [appURL.path, stagingApp.path])
        guard dittoStatus == 0 else {
            throw updateError("Staging copy failed with exit code \(dittoStatus)")
        }
        return try installApp(at: stagingApp)
    }

    private func installApp(at sourceAppURL: URL) throws -> URL {
        // Update where the app runs from. A fixed /Applications path leaves
        // a stale copy behind when the app runs from Downloads or Desktop.
        let bundlePath = Bundle.main.bundlePath
        let isDevBuild = bundlePath.contains("DerivedData") || bundlePath.contains("Xcode.app")
        let dest: URL
        if isDevBuild {
            dest = URL(fileURLWithPath: "/Applications/\(sourceAppURL.lastPathComponent)")
        } else {
            dest = Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent(sourceAppURL.lastPathComponent)
            if !dest.path.hasPrefix("/Applications/") {
                updateLog.warning("App runs outside /Applications (\(bundlePath)); updating in place at \(dest.path)")
            }
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        let dittoStatus = try runProcess(executable: "/usr/bin/ditto", arguments: [sourceAppURL.path, dest.path])
        guard dittoStatus == 0 else {
            throw updateError("Install copy failed with exit code \(dittoStatus)")
        }
        let xattrStatus = try runProcess(executable: "/usr/bin/xattr", arguments: ["-cr", dest.path])
        if xattrStatus != 0 {
            updateLog.warning("xattr -cr failed with exit code \(xattrStatus)")
        }
        updateLog.info("Installed to \(dest.path)")
        return dest
    }

    private func relaunchAfterUpdate(at appURL: URL) {
        updateLog.info("Relaunching from \(appURL.path)")
        AppSettings.flush()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                updateLog.warning("Relaunch failed: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    func openReleasesPage() {
        guard let url = URL(string: changelogURL) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Update Health (issue #40 recovery)

    /// Result of the broken-update scan. Only `/Applications` is scanned.
    /// Never auto-deletes; the UI only offers Show in Finder.
    struct UpdateHealthReport {
        var strayPaths: [String] = []
        var brokenMainCopyPath: String?
        var splitRunningPath: String?
        var splitInstalledPath: String?
        var splitRunningVersion: String?
        var splitInstalledVersion: String?

        var needsAttention: Bool {
            !strayPaths.isEmpty || brokenMainCopyPath != nil || splitInstalledPath != nil
        }

        /// Stable signature so Dismiss persists per finding, not globally.
        var signature: String {
            (strayPaths.sorted() + [brokenMainCopyPath, splitInstalledPath, splitRunningVersion, splitInstalledVersion].compactMap { $0 }).joined(separator: "|")
        }
    }

    nonisolated func detectUpdateHealth() -> UpdateHealthReport {
        var report = UpdateHealthReport()
        let fileManager = FileManager.default
        let applicationsDir = URL(fileURLWithPath: "/Applications")
        guard let entries = try? fileManager.contentsOfDirectory(at: applicationsDir, includingPropertiesForKeys: nil) else {
            return report
        }
        for entry in entries {
            let name = entry.lastPathComponent
            let isStrayName = name == "com.TruchiEmu.app"
                || (name.hasPrefix("com.apple.WebKit.") && name.hasSuffix("+com.TruchiEmu.app"))
            if isStrayName, !validatedAppBundle(at: entry) {
                report.strayPaths.append(entry.path)
                updateLog.warning("Stray update leftover in /Applications: \(entry.path)")
            }
        }
        let mainCopy = applicationsDir.appendingPathComponent("TruchiEmu.app")
        if fileManager.fileExists(atPath: mainCopy.path), !validatedAppBundle(at: mainCopy) {
            report.brokenMainCopyPath = mainCopy.path
            updateLog.warning("Broken TruchiEmu.app in /Applications: \(mainCopy.path)")
        }
        let bundlePath = Bundle.main.bundlePath
        let isDevBuild = bundlePath.contains("DerivedData") || bundlePath.contains("Xcode.app")
        if !isDevBuild, !bundlePath.hasPrefix("/Applications/"), validatedAppBundle(at: mainCopy) {
            let installedVersion = bundleVersion(at: mainCopy) ?? "?"
            if installedVersion != AppVersion.current {
                report.splitRunningPath = bundlePath
                report.splitInstalledPath = mainCopy.path
                report.splitRunningVersion = AppVersion.current
                report.splitInstalledVersion = installedVersion
                updateLog.warning("Split install: running \(AppVersion.current) from \(bundlePath), /Applications has \(installedVersion)")
            }
        }
        return report
    }

    nonisolated private func bundleVersion(at appURL: URL) -> String? {
        guard let data = try? Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleShortVersionString"] as? String
    }

    func shouldShowRecovery(for report: UpdateHealthReport) -> Bool {
        guard report.needsAttention, !report.signature.isEmpty else { return false }
        return AppSettings.getString("recoveryDismissedSignature", defaultValue: "") != report.signature
    }

    func dismissRecovery(for report: UpdateHealthReport) {
        AppSettings.setString("recoveryDismissedSignature", value: report.signature)
    }

    /// Copies the running bundle to `/Applications/TruchiEmu.app`.
    /// Used by the recovery prompt for the broken-copy and split-install cases.
    func reinstallFromRunningCopy() async throws -> URL {
        let source = Bundle.main.bundleURL
        guard validatedAppBundle(at: source) else {
            throw updateError("Running copy is not a valid bundle")
        }
        let dest = URL(fileURLWithPath: "/Applications/TruchiEmu.app")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        updateLog.info("Reinstalling running copy to \(dest.path)")
        let dittoStatus = try runProcess(executable: "/usr/bin/ditto", arguments: [source.path, dest.path])
        guard dittoStatus == 0 else {
            throw updateError("Reinstall copy failed with exit code \(dittoStatus)")
        }
        guard validatedAppBundle(at: dest) else {
            throw updateError("Reinstalled copy failed validation")
        }
        let xattrStatus = try runProcess(executable: "/usr/bin/xattr", arguments: ["-cr", dest.path])
        if xattrStatus != 0 {
            updateLog.warning("xattr -cr failed with exit code \(xattrStatus)")
        }
        updateLog.info("Reinstalled to \(dest.path)")
        return dest
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
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
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
            assetName: macAsset?.name,
            isPrerelease: prerelease
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

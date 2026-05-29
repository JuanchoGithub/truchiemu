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
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var allReleases: [AppRelease] = []

    var updateAvailable: Bool {
        guard let release = latestRelease else { return false }
        return release.isNewer
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
        } catch {
            updateLog.warning("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    func downloadAndInstall(release: AppRelease) async {
        guard let assetURL = release.assetDownloadURL, let url = URL(string: assetURL) else {
            updateLog.warning("No download URL for release \(release.tagName)")
            return
        }

        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = release.assetName ?? "TruchiEmu.zip"
        let localURL = tempDir.appendingPathComponent(fileName)

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 300

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                updateLog.warning("Download returned non-200 status")
                return
            }

            let expectedLength = httpResponse.expectedContentLength
            var buffer = Data()
            buffer.reserveCapacity(Int(expectedLength))

            for try await chunk in asyncBytes {
                buffer.append(chunk)
                if expectedLength > 0 {
                    downloadProgress = Double(buffer.count) / Double(expectedLength)
                }
            }

            try buffer.write(to: localURL)
            updateLog.info("Downloaded to \(localURL.path)")

            if fileName.hasSuffix(".zip") {
                try extractAndMoveZip(at: localURL)
            } else if fileName.hasSuffix(".dmg") {
                NSWorkspace.shared.open(localURL)
            }
        } catch {
            updateLog.warning("Download failed: \(error.localizedDescription)")
        }
    }

    private func extractAndMoveZip(at zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, zipURL.deletingLastPathComponent().path]
        try process.run()
        process.waitUntilExit()

        let extractedDir = zipURL.deletingLastPathComponent()
        if let appURL = try FileManager.default.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) {
            let dest = URL(fileURLWithPath: "/Applications/\(appURL.lastPathComponent)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: appURL, to: dest)
            updateLog.info("Installed to \(dest.path)")
            NSWorkspace.shared.open(dest)
            NSApplication.shared.terminate(nil)
        } else {
            NSWorkspace.shared.open(extractedDir)
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

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

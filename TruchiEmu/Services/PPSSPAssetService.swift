import Foundation

class PPSSPAssetService: ObservableObject {
    static let shared = PPSSPAssetService()
    
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    @Published var downloadError: String? = nil
    @Published var lastCheckDate: Date?
    @Published var isPresentingAssetSheet = false
    
    private let systemDirectoryName = "PPSSPP"
    
    private var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/System/\(systemDirectoryName)")
    }
    
    private var bundledURL: URL? {
        Bundle.main.url(forResource: systemDirectoryName, withExtension: nil, subdirectory: "System")
    }
    
    enum AssetStatus {
        case ok
        case missingFiles
        case notChecked
    }
    
    enum AssetSheetResult {
        case downloaded
        case skipped
        case cancelled
    }

    private var pendingSheetContinuation: CheckedContinuation<AssetSheetResult, Never>?

    // Presents the locking asset-download sheet and suspends the caller
    // (GameLauncher.launch) until the user resolves it.
    @MainActor
    func requestAssetDownloadSheet() async -> AssetSheetResult {
        await withCheckedContinuation { continuation in
            pendingSheetContinuation = continuation
            isPresentingAssetSheet = true
        }
    }

    // Resolves the pending sheet, dismissing it and resuming the caller.
    @MainActor
    func resolveAssetSheet(_ result: AssetSheetResult) {
        isPresentingAssetSheet = false
        pendingSheetContinuation?.resume(returning: result)
        pendingSheetContinuation = nil
    }

    private init() {
        lastCheckDate = AppSettings.getDate("ppsspAssetCheckDate")
    }
    
    var hasAssets: Bool {
        let requiredFiles = [
            "ppge_atlas.zim",
            "font_atlas.zim",
            "asciifont_atlas.zim",
            "compat.ini",
            "langregion.ini"
        ]
        for file in requiredFiles {
            let fileURL = appSupportURL.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                return false
            }
        }
        let fontDir = appSupportURL.appendingPathComponent("flash0/font")
        if !FileManager.default.fileExists(atPath: fontDir.path) {
            return false
        }
        let langDir = appSupportURL.appendingPathComponent("lang")
        if !FileManager.default.fileExists(atPath: langDir.path) {
            return false
        }
        let langFile = langDir.appendingPathComponent("en_US.ini")
        if !FileManager.default.fileExists(atPath: langFile.path) {
            return false
        }
        return true
    }
    
@MainActor
func ensureAssetsCopied() -> Bool {
do {
try FileManager.default.createDirectory(at: appSupportURL.deletingLastPathComponent().deletingLastPathComponent(), withIntermediateDirectories: true)
} catch {
LoggerService.error(category: "PPSSPAssetService", "Failed to create System directory: \(error.localizedDescription)")
return false
}

let zipFileName = "PPSSPP_assets.zip"
guard let zipURL = Bundle.main.url(forResource: zipFileName, withExtension: nil, subdirectory: "System") else {
LoggerService.warning(category: "PPSSPAssetService", "No bundled PPSSPP assets zip found")
return false
}

#if LOG_DEBUG
LoggerService.debug(category: "PPSSPAssetService", "Found bundled PPSSPP zip at: \(zipURL.path)")
#endif

let extractionSucceeded = extractZip(at: zipURL, to: appSupportURL.deletingLastPathComponent())
if extractionSucceeded {
LoggerService.info(category: "PPSSPAssetService", "Successfully extracted bundled PPSSPP assets from zip")
return true
} else {
LoggerService.warning(category: "PPSSPAssetService", "Failed to extract bundled PPSSPP assets from zip")
return false
}
}

private func extractZip(at zipURL: URL, to destinationDir: URL) -> Bool {
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
process.arguments = ["-o", zipURL.path, "-d", destinationDir.path]
let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe
do {
try process.run()
process.waitUntilExit()
if process.terminationStatus == 0 {
#if LOG_DEBUG
if let outputData = try? pipe.fileHandleForReading.readToEnd(),
let output = String(data: outputData, encoding: .utf8) {
LoggerService.debug(category: "PPSSPAssetService", "Unzip output: \(output.prefix(500))")
}
#endif
return true
} else {
let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
if let errorOutput = String(data: errorData, encoding: .utf8) {
LoggerService.error(category: "PPSSPAssetService", "Unzip failed: \(errorOutput)")
}
return false
}
} catch {
LoggerService.error(category: "PPSSPAssetService", "Failed to run unzip: \(error.localizedDescription)")
return false
}
}

@MainActor
func downloadAssets() async -> Bool {
        guard !isDownloading else { return false }
        
        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Fetching latest release..."
        
        defer { isDownloading = false }
        
        do {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: releasesURL))
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                downloadStatus = "Failed to fetch release info"
                return false
            }
            
            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)
            
            guard let asset = release.assets.first(where: { $0.name.contains("PPSSPPSDL-macOS") && $0.name.hasSuffix(".zip") }) else {
                downloadStatus = "macOS SDL assets not found"
                return false
            }
            
            downloadStatus = "Downloading PPSSPP assets..."
            downloadProgress = 0.2
            
            let (zipData, zipResponse) = try await URLSession.shared.data(for: URLRequest(url: URL(string: asset.downloadUrl)!))
            
            guard let httpZipResponse = zipResponse as? HTTPURLResponse, httpZipResponse.statusCode == 200 else {
                downloadStatus = "Download failed"
                return false
            }
            
downloadProgress = 0.6
    downloadStatus = "Extracting assets..."

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ppsspp_assets_\(UUID().uuidString)")

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let zipFileURL = tempDir.appendingPathComponent("ppsspp.zip")
    try zipData.write(to: zipFileURL)

#if LOG_DEBUG
    LoggerService.debug(category: "PPSSPAssetService", "Downloaded \(zipData.count) bytes, written to \(zipFileURL.path)")
#endif

    let fileManager = FileManager.default

    let unzipProcess = Process()
    unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzipProcess.arguments = ["-l", zipFileURL.path]
    let listPipe = Pipe()
    unzipProcess.standardOutput = listPipe
    try unzipProcess.run()
    unzipProcess.waitUntilExit()

#if LOG_DEBUG
    let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
    if let listOutput = String(data: listData, encoding: .utf8) {
        LoggerService.debug(category: "PPSSPAssetService", "ZIP contents (first 20 lines): \(String(listOutput.prefix(2000)))")
    }
#endif

    let extractProcess = Process()
    extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    extractProcess.arguments = ["-o", zipFileURL.path, "-d", tempDir.path]
    let extractPipe = Pipe()
    extractProcess.standardOutput = extractPipe
    extractProcess.standardError = extractPipe
    try extractProcess.run()
    extractProcess.waitUntilExit()

    if extractProcess.terminationStatus != 0 {
        let errorData = extractPipe.fileHandleForReading.readDataToEndOfFile()
        if let errorOutput = String(data: errorData, encoding: .utf8) {
            LoggerService.error(category: "PPSSPAssetService", "Unzip failed: \(errorOutput)")
        }
        downloadStatus = "Extraction failed (code \(extractProcess.terminationStatus))"
        return false
    }

#if LOG_DEBUG
    LoggerService.debug(category: "PPSSPAssetService", "Unzip succeeded, searching for assets directory")
#endif

    let possiblePaths = [
        tempDir.appendingPathComponent("PPSSPPSDL.app/Contents/Resources/assets"),
        tempDir.appendingPathComponent("PPSSPPSDL/assets"),
        tempDir.appendingPathComponent("assets"),
        tempDir.appendingPathComponent("MacOS/assets"),
    ]

    var extractedAppDir: URL?
    for path in possiblePaths {
        if fileManager.fileExists(atPath: path.path) {
            extractedAppDir = path
            #if LOG_DEBUG
            LoggerService.debug(category: "PPSSPAssetService", "Found assets at: \(path.path)")
            #endif
            break
        }
    }

#if LOG_DEBUG
    if let contents = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
        LoggerService.debug(category: "PPSSPAssetService", "Temp dir contents: \(contents.map { $0.lastPathComponent })")
    }
#endif

    guard let assetsDir = extractedAppDir else {
        downloadStatus = "Assets directory not found in package"
        return false
    }

    downloadProgress = 0.8
    downloadStatus = "Copying assets..."

    if fileManager.fileExists(atPath: appSupportURL.path) {
        try fileManager.removeItem(at: appSupportURL)
    }
    try fileManager.copyItem(at: assetsDir, to: appSupportURL)
            
            downloadProgress = 1.0
            downloadStatus = "Download complete"
            
            let now = Date()
            lastCheckDate = now
            AppSettings.setDate("ppsspAssetCheckDate", value: now)
            
            LoggerService.info(category: "PPSSPAssetService", "Successfully downloaded and installed PPSSPP assets")
            return true
            
        } catch {
            LoggerService.error(category: "PPSSPAssetService", "Failed to download PPSSPP assets: \(error.localizedDescription)")
            downloadStatus = "Error: \(error.localizedDescription)"
            return false
        }
    }
    
@MainActor
func checkAssets() async -> AssetStatus {
isChecking = true
defer { isChecking = false }

if hasAssets {
let now = Date()
lastCheckDate = now
AppSettings.setDate("ppsspAssetCheckDate", value: now)
return .ok
}

_ = ensureAssetsCopied()
if hasAssets {
let now = Date()
lastCheckDate = now
AppSettings.setDate("ppsspAssetCheckDate", value: now)
LoggerService.info(category: "PPSSPAssetService", "PPSSPP assets ready from bundled zip")
return .ok
}

LoggerService.info(category: "PPSSPAssetService", "Bundled extraction failed/missing, trying GitHub download...")
let downloadSuccess = await downloadAssets()
if downloadSuccess && hasAssets {
let now = Date()
lastCheckDate = now
AppSettings.setDate("ppsspAssetCheckDate", value: now)
return .ok
}

return .missingFiles
}
    
    private let releasesURL = URL(string: "https://api.github.com/repos/hrydgard/ppsspp/releases/latest")!
    
    private struct GitHubRelease: Decodable {
        let assets: [GitHubReleaseAsset]
    }
    
    private struct GitHubReleaseAsset: Decodable {
        let name: String
        let downloadUrl: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case downloadUrl = "browser_download_url"
        }
    }
    
    }

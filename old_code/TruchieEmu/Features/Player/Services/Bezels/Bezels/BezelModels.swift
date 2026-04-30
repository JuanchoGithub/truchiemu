import Foundation

// MARK: - Bezel Entry Model

// Represents a single bezel entry from The Bezel Project repository.
struct BezelEntry: Identifiable, Codable, Equatable, Hashable {
    // Unique identifier (filename without .png extension)
    let id: String
    // Full filename including extension
    let filename: String
    // GitHub raw download URL
    let rawURL: URL
    // Local file URL (nil until downloaded)
    var localURL: URL?
    
    // Human-readable display name (filename without extension, cleaned up)
    var displayName: String {
        let stripped = GameNameFormatter.stripTags(id)
        return stripped.replacingOccurrences(of: "_", with: " ")
    }
    
    // URL for thumbnail preview (uses GitHub's raw URL)
    var thumbnailURL: URL { rawURL }
    
    // Check if this bezel is downloaded locally
    var isDownloaded: Bool {
        guard let url = localURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    init(id: String, filename: String, rawURL: URL, localURL: URL? = nil) {
        self.id = id
        self.filename = filename
        self.rawURL = rawURL
        self.localURL = localURL
    }
    
    // Create from a GitHub API response item
    init?(fromGitHubItem item: [String: Any], baseURL: URL) {
        guard let name = item["name"] as? String,
              let downloadURL = item["download_url"] as? String,
              let url = URL(string: downloadURL) else {
            return nil
        }
        self.id = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        self.filename = name
        self.rawURL = url
        self.localURL = nil
    }
}

// MARK: - Bezel System Config

// Configuration for mapping internal system IDs to Bezel Project repository names.
struct BezelSystemConfig: Codable {
    // Internal system ID (e.g., "snes")
    let systemID: String
    // Bezel Project repository name (e.g., "SNES")
    let bezelProjectName: String
    // GitHub API base URL for this system's bezel directory
    let githubAPIURL: URL
    // GitHub raw content base URL for this system's bezels
    let githubRawURL: URL
    
    // Git Trees API URL to get the full directory structure (no pagination)
    let treesAPIURL: URL
    
    // The subdirectory path within the repo where bezels are stored
    var bezelDirectoryPath: String {
        "retroarch/overlay/GameBezels/\(bezelProjectName)/"
    }
    
    // Generate a direct URL to a bezel PNG file (for download)
    func bezelRawURL(for filename: String) -> URL {
        githubRawURL.appendingPathComponent(filename)
    }
    
    // Default aspect ratio for this system's bezels (most are 4:3)
    var defaultAspectRatio: CGFloat { 4.0 / 3.0 }
    
    init(systemID: String, bezelProjectName: String) {
        self.systemID = systemID
        self.bezelProjectName = bezelProjectName
        // Trees API returns all files recursively - use this for full manifest
        self.treesAPIURL = URL(
            string: "https://api.github.com/repos/thebezelproject/bezelproject-\(bezelProjectName)/git/trees/master?recursive=1"
        )!
        // Contents API for fallback (single file fetch)
        self.githubAPIURL = URL(
            string: "https://api.github.com/repos/thebezelproject/bezelproject-\(bezelProjectName)/contents/retroarch/overlay/GameBezels/\(bezelProjectName)"
        )!
        self.githubRawURL = URL(
            string: "https://raw.githubusercontent.com/thebezelproject/bezelproject-\(bezelProjectName)/master/retroarch/overlay/GameBezels/\(bezelProjectName)/"
        )!
    }
}

// MARK: - Bezel Manifest Cache

// Cached manifest for a system's available bezels.
struct BezelManifest: Codable {
    // System ID this manifest belongs to
    let systemID: String
    // Date when this manifest was last fetched
    let lastFetched: Date
    // List of available bezel entries
    let entries: [BezelEntry]
    
    // Check if manifest is stale (older than 7 days)
    var isStale: Bool {
        Date().timeIntervalSince(lastFetched) > 7 * 24 * 60 * 60
    }
}

// MARK: - Bezel Storage Mode

// Defines where bezel files are stored.
enum BezelStorageMode: String, Codable, CaseIterable {
    // Bezels stored relative to the first library folder (default)
    case libraryRelative
    // User-selected custom folder
    case customFolder
    // Internal app-managed folder in Application Support
    case internalManaged
    
    var displayName: String {
        switch self {
        case .libraryRelative:
            return "Library Folder"
        case .customFolder:
            return "Custom Folder"
        case .internalManaged:
            return "Internal (App Data)"
        }
    }
    
    var icon: String {
        switch self {
        case .libraryRelative:
            return "folder"
        case .customFolder:
            return "folder.badge.person.crop"
        case .internalManaged:
            return "internaldrive"
        }
    }
}

// MARK: - Bezel Resolution Result

// Result of resolving a bezel for a specific game.
struct BezelResolutionResult {
    // The bezel entry (may be nil if not found)
    let entry: BezelEntry?
    // How this bezel was resolved
    let resolutionMethod: ResolutionMethod
    // The aspect ratio to use for the playable area
    let aspectRatio: CGFloat
    
    enum ResolutionMethod {
        case exactMatch        // Exact filename match found locally
        case userSelection     // User manually selected this bezel
        case systemDefault     // Using system default bezel (if available)
        case none              // No bezel available
    }
    
    static var noBezel: BezelResolutionResult {
        BezelResolutionResult(entry: nil, resolutionMethod: .none, aspectRatio: 4.0 / 3.0)
    }
}
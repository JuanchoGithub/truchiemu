import Foundation

/// Git Trees API response model for recursive tree listing
struct GitTreesResponse: Codable, Sendable {
    let sha: String?
    let tree: [GitTreeItem]
    let truncated: Bool
    let url: String?
}

/// Individual item in a Git tree response
struct GitTreeItem: Codable, Sendable {
    let path: String
    let mode: String?
    let type: String
    let sha: String?
    let size: Int?
    let url: String?
}

/// Individual item in a GitHub Contents API response
struct GitHubFileContent: Codable, Sendable {
    let name: String
    let path: String?
    let url: String?
    let htmlUrl: String?
    let downloadUrl: String?
    let sha: String?
    let size: Int?
    let type: ContentType?
    
    enum ContentType: String, Codable, Sendable {
        case file
        case directory
        case submodule
        case symlink
    }
    
    // Safer accessors for optional fields used in logic
    var safeUrl: String { url ?? "" }
    var safePath: String { path ?? "" }
}

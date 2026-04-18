import Foundation

// MARK: - Internal Cache Data Types (used by ResourceCacheRepository)

// Internal cache data used by ResourceCacheRepository.
public struct RCCacheData {
    public let cacheKey: String
    public let resourceType: String
    public let sourceURL: String
    public let responseStatus: Int?
    public let contentType: String?
    public let fileSize: Int?
    public let localPath: String?
    public let etag: String?
    public let lastModified: String?
    public let checksum: String?
    public let expiresAt: Int?
    public let createdAt: Date
    public let updatedAt: Date
    public let accessCount: Int
    public let lastAccessed: Date?

    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date.now.timeIntervalSince1970 > Double(expiresAt)
    }

    public var isHit: Bool {
        responseStatus == 200 || responseStatus == 304
    }
}

// Internal box art resolution data used by ResourceCacheRepository.
public struct RCBoxArtData {
    public let romPathKey: String
    public let systemID: String
    public let gameTitle: String?
    public let resolvedURL: String
    public let source: String
    public let httpStatus: Int
    public let isValid: Bool
    public let resolvedAt: Date
}

// MARK: - Resource Type

// Represents the type of external resource being cached.
enum ResourceType: String, Codable, Sendable {
    case dat              // No-Intro .dat files
    case rdb              // Libretro .rdb files
    case boxart           // Box art images from Libretro CDN
    case bezel            // Bezel PNGs from Bezel Project
    case bezelManifest    // Bezel directory listing (Git tree)
    case cheat            // .cht cheat files from libretro-database
    case cheatManifest    // Cheat directory listing (Git tree)
    case gitTree          // Generic GitHub API git tree responses
    case apiResponse      // Generic API JSON responses (ScreenScraper, LaunchBox, etc.)
    case libretroDatFile  // Downloaded libretro-database .dat files for system identification
    case headCheck        // HEAD request results (cached 200/404)
    case thumbnailManifest // libretro-thumbnails directory listing (Git tree)
}

// MARK: - Cache Expiry Policy

// Defines how long a cached entry should be considered valid.
enum CacheExpiryPolicy: Sendable {
    case never            // Permanent (DAT files — change detection via checksum)
    case short            // 1 hour (Git tree listings, directory indexes)
    case medium           // 24 hours (search results, API responses)
    case long             // 7 days (box art, bezels, cheat files)
    case conditional       // Use ETag/Last-Modified for 304 revalidation

    var ttlSeconds: Int? {
        switch self {
        case .never: return nil
        case .short: return 3600          // 1 hour
        case .medium: return 86400        // 24 hours
        case .long: return 604800         // 7 days
        case .conditional: return nil     // TTL determined by ETag/Last-Modified
        }
    }
}

// MARK: - Resource Cache Entry

// Represents a single cached HTTP resource in the resource_cache table.
struct ResourceCacheEntry: Equatable, Sendable {
    let id: Int
    let cacheKey: String            // e.g. "dat_genesis_no_intro"
    let resourceType: ResourceType  // enum: .dat, .rdb, .boxart, .bezel, .cheat
    let sourceURL: String           // Full URL that was fetched
    let responseStatus: Int?        // 200, 404, 304, etc.
    let contentType: String?        // Content-Type header
    let fileSize: Int?
    let localPath: String?          // Where downloaded file is stored
    let etag: String?               // HTTP ETag header for conditional requests
    let lastModified: String?       // HTTP Last-Modified header
    let checksum: String?           // SHA256 of content to detect changes
    let expiresAt: Int?             // Unix timestamp for cache refresh
    let createdAt: Int              // Unix timestamp
    let updatedAt: Int              // Unix timestamp
    let accessCount: Int            // How many times this entry was used
    let lastAccessed: Int?          // Unix timestamp of last use

    var isExpired: Bool {
        guard let expiresAt = expiresAt else {
            // For conditional policy, never expire if we have ETag or Last-Modified
            return false
        }
        return Int(Date().timeIntervalSince1970) > expiresAt
    }

    var isHit: Bool {
        guard let status = responseStatus else { return false }
        return status == 200 || status == 304
    }

    // Compute a cache key for a DAT file by system and source.
    static func makeDatKey(systemID: String, source: String) -> String {
        return "dat_\(systemID)_\(source)"
    }

    // Compute a cache key for an RDB file by system and source.
    static func makeRdbKey(systemID: String, source: String) -> String {
        return "rdb_\(systemID)_\(source)"
    }

    // Compute a cache key for a box art lookup.
    static func makeBoxArtKey(systemID: String, gameTitle: String, source: String) -> String {
        let sanitizedTitle = gameTitle.replacingOccurrences(of: " ", with: "_")
        return "boxart_\(systemID)_\(sanitizedTitle)_\(source)"
    }

    // Compute a cache key for a bezel manifest by system.
    static func makeBezelManifestKey(systemID: String) -> String {
        return "bezel_manifest_\(systemID)"
    }

    // Compute a cache key for a cheat manifest by system folder.
    static func makeCheatManifestKey(systemFolder: String) -> String {
        return "cheat_manifest_\(systemFolder)"
    }

    // Compute a cache key for a thumbnail manifest by system repository.
    static func makeThumbnailManifestKey(repoName: String) -> String {
        return "thumbnail_manifest_\(repoName)"
    }

    // Compute a cache key for LaunchBox search results.
    static func makeLaunchBoxSearchKey(platform: String, query: String) -> String {
        let sanitizedQuery = query.replacingOccurrences(of: " ", with: "_")
        return "launchbox_search_\(platform)_\(sanitizedQuery)"
    }
}

// MARK: - Resource Cache Stats

// Aggregate statistics for the resource cache.
struct ResourceCacheStats: Sendable {
    let totalEntries: Int
    let totalBytes: Int
    let hitRate: Double           // 0.0 - 1.0
    let expiredEntries: Int
    let entriesByType: [ResourceType: Int]
}

// MARK: - DAT Ingestion Record

// Tracks each DAT/RDB file ingestion event in the dat_ingestion table.
struct DATIngestionRecord: Equatable, Sendable {
    let id: Int
    let resourceCacheID: Int           // FK to resource_cache
    let systemID: String
    let sourceName: String             // "no-intro", "redump", "mame", etc.
    let entriesFound: Int              // How many entries in the DAT/RDB
    let entriesIngested: Int           // How many were written to game_entries
    let ingestionStatus: String        // "pending", "success", "partial", "failed"
    let errorMessage: String?
    let durationMs: Int
    let ingestedAt: Int                // Unix timestamp
}

// MARK: - Box Art Resolution

// Caches the result of "this ROM → this box art URL" lookup in box_art_resolutions table.
struct BoxArtResolution: Equatable, Sendable {
    let id: Int
    let romPathKey: String             // Hash or normalized ROM path
    let systemID: String
    let gameTitle: String?
    let resolvedURL: String            // The actual CDN URL that was tried
    let source: String                 // "libretro", "screenscraper", "launchbox", "google"
    let httpStatus: Int                // 200, 404, etc.
    let isValid: Bool                  // Whether the download succeeded and was a valid image
    let resolvedAt: Int

    static func makeKey(romPathKey: String, source: String) -> String {
        return "boxart_\(romPathKey)_\(source)"
    }
}

// MARK: - Bezel Manifest Cache

// Caches Git tree responses per bezel system.
struct BezelManifestCache: Equatable, Sendable {
    let id: Int
    let resourceCacheID: Int
    let systemID: String
    let sha: String                    // Git tree SHA for change detection
    let fileCount: Int
    let fetchedAt: Int

    var isStale: Bool {
        let age = Int(Date().timeIntervalSince1970) - fetchedAt
        return age > 3600 // 1 hour
    }
}
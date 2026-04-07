import XCTest
import CryptoKit
@testable import TruchieEmu

final class ResourceCacheManagerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    // MARK: - Model Tests

    func testResourceCacheEntryExpired() {
        let now = Int(Date().timeIntervalSince1970)
        let future = now + 7200 // 2 hours from now
        let past = now - 3600   // 1 hour ago

        let nonExpired = ResourceCacheEntry(
            id: 1, cacheKey: "test", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: 200, contentType: "text/xml", fileSize: 1000, localPath: nil,
            etag: nil, lastModified: nil, checksum: "abc", expiresAt: future,
            createdAt: now, updatedAt: now, accessCount: 1, lastAccessed: nil
        )
        XCTAssertFalse(nonExpired.isExpired)

        let expired = ResourceCacheEntry(
            id: 2, cacheKey: "test2", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: 200, contentType: "text/xml", fileSize: 1000, localPath: nil,
            etag: nil, lastModified: nil, checksum: "abc", expiresAt: past,
            createdAt: now, updatedAt: now, accessCount: 1, lastAccessed: nil
        )
        XCTAssertTrue(expired.isExpired)

        let noExpiry = ResourceCacheEntry(
            id: 3, cacheKey: "test3", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: 200, contentType: "text/xml", fileSize: 1000, localPath: nil,
            etag: "etag123", lastModified: nil, checksum: "abc", expiresAt: nil,
            createdAt: now, updatedAt: now, accessCount: 1, lastAccessed: nil
        )
        XCTAssertFalse(noExpiry.isExpired)
    }

    func testResourceCacheEntryIsHit() {
        let hit200 = ResourceCacheEntry(
            id: 1, cacheKey: "test", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: 200, contentType: nil, fileSize: nil, localPath: nil,
            etag: nil, lastModified: nil, checksum: nil, expiresAt: nil,
            createdAt: 0, updatedAt: 0, accessCount: 0, lastAccessed: nil
        )
        XCTAssertTrue(hit200.isHit)

        let hit304 = ResourceCacheEntry(
            id: 2, cacheKey: "test2", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: 304, contentType: nil, fileSize: nil, localPath: nil,
            etag: nil, lastModified: nil, checksum: nil, expiresAt: nil,
            createdAt: 0, updatedAt: 0, accessCount: 0, lastAccessed: nil
        )
        XCTAssertTrue(hit304.isHit)

        let miss404 = ResourceCacheEntry(
            id: 3, cacheKey: "test3", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: 404, contentType: nil, fileSize: nil, localPath: nil,
            etag: nil, lastModified: nil, checksum: nil, expiresAt: nil,
            createdAt: 0, updatedAt: 0, accessCount: 0, lastAccessed: nil
        )
        XCTAssertFalse(miss404.isHit)

        let noStatus = ResourceCacheEntry(
            id: 4, cacheKey: "test4", resourceType: .dat, sourceURL: "http://example.com",
            responseStatus: nil, contentType: nil, fileSize: nil, localPath: nil,
            etag: nil, lastModified: nil, checksum: nil, expiresAt: nil,
            createdAt: 0, updatedAt: 0, accessCount: 0, lastAccessed: nil
        )
        XCTAssertFalse(noStatus.isHit)
    }

    func testCacheExpiryPolicyTTL() {
        XCTAssertNil(CacheExpiryPolicy.never.ttlSeconds)
        XCTAssertEqual(CacheExpiryPolicy.short.ttlSeconds, 3600)
        XCTAssertEqual(CacheExpiryPolicy.medium.ttlSeconds, 86400)
        XCTAssertEqual(CacheExpiryPolicy.long.ttlSeconds, 604800)
        XCTAssertNil(CacheExpiryPolicy.conditional.ttlSeconds)
    }

    func testCacheKeyGeneration() {
        XCTAssertEqual(
            ResourceCacheEntry.makeDatKey(systemID: "genesis", source: "no-intro"),
            "dat_genesis_no-intro"
        )
        XCTAssertEqual(
            ResourceCacheEntry.makeRdbKey(systemID: "snes", source: "libretro"),
            "rdb_snes_libretro"
        )
        XCTAssertEqual(
            ResourceCacheEntry.makeBoxArtKey(systemID: "nes", gameTitle: "Mario Bros", source: "libretro"),
            "boxart_nes_Mario_Bros_libretro"
        )
        XCTAssertEqual(
            ResourceCacheEntry.makeBezelManifestKey(systemID: "genesis"),
            "bezel_manifest_genesis"
        )
        XCTAssertEqual(
            ResourceCacheEntry.makeCheatManifestKey(systemFolder: "Nintendo - NES"),
            "cheat_manifest_Nintendo - NES"
        )
        XCTAssertEqual(
            ResourceCacheEntry.makeLaunchBoxSearchKey(platform: "NES", query: "Mario"),
            "launchbox_search_NES_Mario"
        )
    }

    func testResourceTypeRawValues() {
        XCTAssertEqual(ResourceType.dat.rawValue, "dat")
        XCTAssertEqual(ResourceType.rdb.rawValue, "rdb")
        XCTAssertEqual(ResourceType.boxart.rawValue, "boxart")
        XCTAssertEqual(ResourceType.bezel.rawValue, "bezel")
        XCTAssertEqual(ResourceType.bezelManifest.rawValue, "bezelManifest")
        XCTAssertEqual(ResourceType.cheat.rawValue, "cheat")
        XCTAssertEqual(ResourceType.cheatManifest.rawValue, "cheatManifest")
        XCTAssertEqual(ResourceType.gitTree.rawValue, "gitTree")
        XCTAssertEqual(ResourceType.apiResponse.rawValue, "apiResponse")
        XCTAssertEqual(ResourceType.libretroDatFile.rawValue, "libretroDatFile")
        XCTAssertEqual(ResourceType.headCheck.rawValue, "headCheck")
    }

    func testSHA256Checksum() {
        let data = "Hello, World!".data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        let hexString = hash.compactMap { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hexString.count, 64) // SHA256 produces 64 hex chars
    }

    func testBoxArtResolutionKey() {
        XCTAssertEqual(
            BoxArtResolution.makeKey(romPathKey: "mario_rom", source: "libretro"),
            "boxart_mario_rom_libretro"
        )
    }

    func testBezelManifestCacheStaleness() {
        let now = Int(Date().timeIntervalSince1970)
        let fresh = BezelManifestCache(
            id: 1, resourceCacheID: 1, systemID: "genesis",
            sha: "abc123", fileCount: 50, fetchedAt: now
        )
        XCTAssertFalse(fresh.isStale)

        let stale = BezelManifestCache(
            id: 2, resourceCacheID: 2, systemID: "genesis",
            sha: "def456", fileCount: 50, fetchedAt: now - 7200 // 2 hours ago
        )
        XCTAssertTrue(stale.isStale)
    }

    func testResourceCacheStats() {
        let stats = ResourceCacheStats(
            totalEntries: 100,
            totalBytes: 5_000_000,
            hitRate: 0.85,
            expiredEntries: 10,
            entriesByType: [.dat: 50, .boxart: 30, .bezelManifest: 20]
        )
        XCTAssertEqual(stats.totalEntries, 100)
        XCTAssertEqual(stats.totalBytes, 5_000_000)
        XCTAssertEqual(stats.hitRate, 0.85, accuracy: 0.01)
        XCTAssertEqual(stats.expiredEntries, 10)
        XCTAssertEqual(stats.entriesByType[.dat], 50)
    }
}


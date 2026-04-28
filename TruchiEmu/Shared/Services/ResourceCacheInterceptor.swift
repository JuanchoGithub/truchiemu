import Foundation
import SwiftData

// A cache-first HTTP fetcher that checks the local cache before hitting the network.
// Supports ETag/Last-Modified conditional requests for efficient revalidation.
@MainActor
class ResourceCacheInterceptor: ObservableObject {
    static let shared = ResourceCacheInterceptor()

    private let urlSession: URLSession

    private var cacheRepo: ResourceCacheRepository {
        ResourceCacheRepository(context: SwiftDataContainer.shared.mainContext)
    }

    init() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "TruchiEmu/\(version) (macOS)"
        ]
        config.requestCachePolicy = .useProtocolCachePolicy
        urlSession = URLSession(configuration: config)
    }

    // MARK: - Cache-First Fetch

    func fetchWithCache(
        url: URL,
        type: ResourceType,
        cacheKey: String,
        expiry: CacheExpiryPolicy
    ) async throws -> (data: Data, response: URLResponse) {
        if let entry = cacheRepo.getEntry(cacheKey: cacheKey) {
            if entry.responseStatus == 404 {
                LoggerService.info(category: "ResourceCache", "Cache hit (404 cached): \(cacheKey) — skipping network call")
                throw ResourceCacheInterceptorError.cachedMiss(httpStatus: 404, url: url.absoluteString)
            }

            if !entry.isExpired, let localPath = entry.localPath {
                let localURL = URL(fileURLWithPath: localPath)
                if let cachedData = try? Data(contentsOf: localURL) {
                    LoggerService.info(category: "ResourceCache", "Cache hit (local file): \(cacheKey) — returning cached data")
                    cacheRepo.recordHit(cacheKey: cacheKey)
                    return (cachedData, URLResponse(
                        url: url,
                        mimeType: entry.contentType ?? "application/octet-stream",
                        expectedContentLength: entry.fileSize ?? Int(cachedData.count),
                        textEncodingName: nil
                    ))
                }
            }

            if entry.etag != nil || entry.lastModified != nil || entry.isExpired {
                return try await conditionalFetch(
                    url: url,
                    cacheKey: cacheKey,
                    type: type,
                    existingEntry: entry,
                    expiry: expiry
                )
            }
        }

        return try await fullFetch(
            url: url,
            cacheKey: cacheKey,
            type: type,
            expiry: expiry
        )
    }

    // MARK: - Conditional Fetch

    private func conditionalFetch(
        url: URL,
        cacheKey: String,
        type: ResourceType,
        existingEntry: RCCacheData,
        expiry: CacheExpiryPolicy
    ) async throws -> (data: Data, response: URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let etag = existingEntry.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = existingEntry.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        LoggerService.info(category: "ResourceCache", "Conditional request: \(cacheKey)")

        do {
            let (data, response) = try await urlSession.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 304 {
                    LoggerService.info(category: "ResourceCache", "Cache revalidated (304): \(cacheKey)")
                    let newExpires = expiry.ttlSeconds.map { Int(Date().timeIntervalSince1970) + $0 }
                    cacheRepo.updateEntry(
                        cacheKey: cacheKey,
                        expiresAt: newExpires
                    )

                    if let localPath = existingEntry.localPath,
                       let cachedData = try? Data(contentsOf: URL(fileURLWithPath: localPath)) {
                        return (cachedData, response)
                    }
                    return (data, response)
                }

                if httpResponse.statusCode == 200 {
                    LoggerService.info(category: "ResourceCache", "Cache refreshed (200): \(cacheKey)")
                    return try await storeAndReturn(
                        data: data,
                        response: response,
                        cacheKey: cacheKey,
                        type: type,
                        expiry: expiry
                    )
                }

                LoggerService.warning(category: "ResourceCache", "Cache fetch returned status \(httpResponse.statusCode): \(cacheKey)")
                throw ResourceCacheInterceptorError.httpError(statusCode: httpResponse.statusCode, url: url.absoluteString)
            }

            throw ResourceCacheInterceptorError.invalidResponse
        } catch let error as ResourceCacheInterceptorError {
            throw error
        } catch {
            LoggerService.error(category: "ResourceCache", "Network error for \(cacheKey): \(error.localizedDescription)")

            if let localPath = existingEntry.localPath,
               let cachedData = try? Data(contentsOf: URL(fileURLWithPath: localPath)) {
                LoggerService.info(category: "ResourceCache", "Using stale cached data for \(cacheKey) (network error)")
                return (cachedData, URLResponse(
                    url: url,
                    mimeType: existingEntry.contentType ?? "application/octet-stream",
                    expectedContentLength: existingEntry.fileSize ?? Int(cachedData.count),
                    textEncodingName: nil
                ))
            }

            throw error
        }
    }

    // MARK: - Full Fetch

    private func fullFetch(
        url: URL,
        cacheKey: String,
        type: ResourceType,
        expiry: CacheExpiryPolicy
    ) async throws -> (data: Data, response: URLResponse) {
        LoggerService.info(category: "ResourceCache", "Full fetch: \(cacheKey) → \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await urlSession.data(for: request)
            return try await storeAndReturn(
                data: data,
                response: response,
                cacheKey: cacheKey,
                type: type,
                expiry: expiry
            )
        } catch let error as ResourceCacheInterceptorError {
            throw error
        } catch {
            LoggerService.error(category: "ResourceCache", "Network error for \(cacheKey): \(error.localizedDescription)")
            throw ResourceCacheInterceptorError.networkError(underlying: error)
        }
    }

    // MARK: - Store and Return

    private func storeAndReturn(
        data: Data,
        response: URLResponse,
        cacheKey: String,
        type: ResourceType,
        expiry: CacheExpiryPolicy
    ) async throws -> (data: Data, response: URLResponse) {
        let httpResponse = response as? HTTPURLResponse
        let status = httpResponse?.statusCode
        let contentType = httpResponse?.mimeType
        let etag = httpResponse?.allHeaderFields["Etag"] as? String
            ?? httpResponse?.allHeaderFields["etag"] as? String
            ?? httpResponse?.allHeaderFields["ETag"] as? String
        let lastModified = httpResponse?.allHeaderFields["Last-Modified"] as? String
            ?? httpResponse?.allHeaderFields["last-modified"] as? String

        let checksum = ResourceCacheRepository.computeSHA256(data)
        let fileSize = data.count
        let expiresAt: Int? = expiry.ttlSeconds.map { Int(Date().timeIntervalSince1970) + $0 }

        let localPath = try storeDataLocally(data: data, url: response.url)

        if cacheRepo.getEntry(cacheKey: cacheKey) != nil {
            cacheRepo.updateEntry(
                cacheKey: cacheKey,
                responseStatus: status,
                contentType: contentType,
                fileSize: fileSize,
                localPath: localPath,
                etag: etag,
                lastModified: lastModified,
                checksum: checksum,
                expiresAt: expiresAt
            )
        } else {
            _ = cacheRepo.createEntry(
                cacheKey: cacheKey,
                resourceType: type.rawValue,
                sourceURL: response.url?.absoluteString ?? "",
                responseStatus: status,
                contentType: contentType,
                fileSize: fileSize,
                localPath: localPath,
                etag: etag,
                lastModified: lastModified,
                checksum: checksum,
                expiresAt: expiresAt
            )
        }

        LoggerService.info(category: "ResourceCache", "Cached: \(cacheKey) (\(fileSize) bytes, checksum: \(checksum.prefix(12)))")

        return (data, response)
    }

    // MARK: - Local Storage

    private func storeDataLocally(data: Data, url: URL?) throws -> String {
        let cacheDir = ResourceCacheInterceptor.localCacheDirectory
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let filename: String
        if let url = url {
            let urlHash = ResourceCacheRepository.computeSHA256(Data(url.absoluteString.utf8))
            filename = "cache_\(urlHash.prefix(16)).\(url.pathExtension)"
        } else {
            filename = "cache_\(UUID().uuidString).dat"
        }

        let fileURL = cacheDir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)

        return fileURL.path
    }

    private static var localCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/ResourceCache")
    }

    // MARK: - Check Cache Only (No Network)

    func checkCacheOnly(cacheKey: String) -> Data? {
        guard let entry = cacheRepo.getEntry(cacheKey: cacheKey) else {
            return nil
        }

        if entry.isExpired && entry.etag == nil && entry.lastModified == nil {
            return nil
        }

        if entry.responseStatus == 404 {
            return nil
        }

        guard let localPath = entry.localPath else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: localPath))
    }

    // MARK: - Record Miss (For Known 404s)

    func recordCacheMiss(cacheKey: String, httpStatus: Int, resourceType: ResourceType, sourceURL: String) {
        if cacheRepo.getEntry(cacheKey: cacheKey) == nil {
            _ = cacheRepo.createEntry(
                cacheKey: cacheKey,
                resourceType: resourceType.rawValue,
                sourceURL: sourceURL,
                responseStatus: httpStatus,
                expiresAt: Int(Date().timeIntervalSince1970) + 86400
            )
        }
    }
}

// MARK: - Errors

enum ResourceCacheInterceptorError: LocalizedError {
    case cachedMiss(httpStatus: Int, url: String)
    case httpError(statusCode: Int, url: String)
    case networkError(underlying: Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cachedMiss(let status, let url):
            return "Cached miss: \(url) returned HTTP \(status)"
        case .httpError(let status, let url):
            return "HTTP error from \(url): \(status)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
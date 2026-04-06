import Foundation
import SwiftData
import os.log
import CryptoKit

private let cacheLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu",
    category: "ResourceCacheRepository"
)

// MARK: - Resource Cache Repository

@MainActor
final class ResourceCacheRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func getEntry(cacheKey: String) -> RCCacheData? {
        let pd: Predicate<ResourceCacheEntryModel> = #Predicate { (entry: ResourceCacheEntryModel) in
            entry.cacheKey == cacheKey
        }
        let descriptor = FetchDescriptor<ResourceCacheEntryModel>(predicate: pd)
        guard let model = try? context.fetch(descriptor).first else { return nil }
        model.accessCount += 1
        model.lastAccessed = Date()
        try? context.save()
        return toCacheData(from: model)
    }

    func getExpiredEntries() -> [RCCacheData] {
        guard let models = try? context.fetch(FetchDescriptor<ResourceCacheEntryModel>()) else { return [] }
        return models.filter { $0.isExpired }.map { toCacheData(from: $0) }
    }

    func clearExpired() -> Int {
        guard let models = try? context.fetch(FetchDescriptor<ResourceCacheEntryModel>()) else { return 0 }
        let expired = models.filter { $0.isExpired }
        expired.forEach { context.delete($0) }
        try? context.save()
        return expired.count
    }

    func clearByType(_ type: String) -> Int {
        let pd: Predicate<ResourceCacheEntryModel> = #Predicate { (entry: ResourceCacheEntryModel) in
            entry.resourceType == type
        }
        let descriptor = FetchDescriptor<ResourceCacheEntryModel>(predicate: pd)
        guard let models = try? context.fetch(descriptor) else { return 0 }
        models.forEach { context.delete($0) }
        try? context.save()
        return models.count
    }

    func getBoxArtResolution(romPathKey: String, source: String) -> RCBoxArtData? {
        let ck = "\(romPathKey)::\(source)"
        let pd: Predicate<BoxArtResolutionEntry> = #Predicate { (e: BoxArtResolutionEntry) in
            e.compositeKey == ck
        }
        let descriptor = FetchDescriptor<BoxArtResolutionEntry>(predicate: pd)
        guard let model = try? context.fetch(descriptor).first else { return nil }
        return toBoxArtData(from: model)
    }

    func createEntry(cacheKey: String, resourceType: String, sourceURL: String,
                     responseStatus: Int? = nil, contentType: String? = nil,
                     fileSize: Int? = nil, localPath: String? = nil, etag: String? = nil,
                     lastModified: String? = nil, checksum: String? = nil,
                     expiresAt: Int? = nil) -> RCCacheData {
        let model = ResourceCacheEntryModel(
            cacheKey: cacheKey, resourceType: resourceType, sourceURL: sourceURL,
            responseStatus: responseStatus, contentType: contentType, fileSize: fileSize,
            localPath: localPath, etag: etag, lastModified: lastModified,
            checksum: checksum, expiresAt: expiresAt)
        context.insert(model)
        try? context.save()
        return toCacheData(from: model)
    }

    func updateEntry(cacheKey: String, responseStatus: Int? = nil, contentType: String? = nil,
                     fileSize: Int? = nil, localPath: String? = nil, etag: String? = nil,
                     lastModified: String? = nil, checksum: String? = nil, expiresAt: Int? = nil) {
        let pd: Predicate<ResourceCacheEntryModel> = #Predicate { (entry: ResourceCacheEntryModel) in
            entry.cacheKey == cacheKey
        }
        let descriptor = FetchDescriptor<ResourceCacheEntryModel>(predicate: pd)
        guard let model = try? context.fetch(descriptor).first else { return }
        if let v = responseStatus { model.responseStatus = v }
        if let v = contentType { model.contentType = v }
        if let v = fileSize { model.fileSize = v }
        if let v = localPath { model.localPath = v }
        if let v = etag { model.etag = v }
        if let v = lastModified { model.lastModified = v }
        if let v = checksum { model.checksum = v }
        if let v = expiresAt { model.expiresAt = v }
        model.updatedAt = Date()
        try? context.save()
    }

    func updateEntry(_ entry: RCCacheData) {
        let key = entry.cacheKey
        let pd: Predicate<ResourceCacheEntryModel> = #Predicate { (e: ResourceCacheEntryModel) in
            e.cacheKey == key
        }
        let descriptor = FetchDescriptor<ResourceCacheEntryModel>(predicate: pd)
        guard let model = try? context.fetch(descriptor).first else { return }
        model.resourceType = entry.resourceType
        model.sourceURL = entry.sourceURL
        model.responseStatus = entry.responseStatus
        model.contentType = entry.contentType
        model.fileSize = entry.fileSize
        model.localPath = entry.localPath
        model.etag = entry.etag
        model.lastModified = entry.lastModified
        model.checksum = entry.checksum
        model.expiresAt = entry.expiresAt
        model.updatedAt = Date()
        try? context.save()
    }

    func recordHit(cacheKey: String, localPath: String? = nil, fileSize: Int? = nil,
                   etag: String? = nil, lastModified: String? = nil) {
        let pd: Predicate<ResourceCacheEntryModel> = #Predicate { (e: ResourceCacheEntryModel) in
            e.cacheKey == cacheKey
        }
        let descriptor = FetchDescriptor<ResourceCacheEntryModel>(predicate: pd)
        guard let model = try? context.fetch(descriptor).first else { return }
        model.responseStatus = 200
        if let v = localPath { model.localPath = v }
        if let v = fileSize { model.fileSize = v }
        if let v = etag { model.etag = v }
        if let v = lastModified { model.lastModified = v }
        model.accessCount += 1
        model.lastAccessed = Date()
        model.updatedAt = Date()
        try? context.save()
    }

    func recordMiss(cacheKey: String, httpStatus: Int) {
        let pd: Predicate<ResourceCacheEntryModel> = #Predicate { (e: ResourceCacheEntryModel) in
            e.cacheKey == cacheKey
        }
        let descriptor = FetchDescriptor<ResourceCacheEntryModel>(predicate: pd)
        if let model = try? context.fetch(descriptor).first {
            model.responseStatus = httpStatus
            model.accessCount += 1
            model.lastAccessed = Date()
            model.updatedAt = Date()
            try? context.save()
        } else {
            _ = createEntry(cacheKey: cacheKey, resourceType: "unknown", sourceURL: "", responseStatus: httpStatus)
        }
    }

    func storeBoxArtResolution(romPathKey: String, systemID: String, gameTitle: String?,
                               resolvedURL: String, source: String, httpStatus: Int, isValid: Bool) {
        let ck = "\(romPathKey)::\(source)"
        let pd: Predicate<BoxArtResolutionEntry> = #Predicate { (e: BoxArtResolutionEntry) in
            e.compositeKey == ck
        }
        let descriptor = FetchDescriptor<BoxArtResolutionEntry>(predicate: pd)
        if let existing = try? context.fetch(descriptor).first {
            existing.gameTitle = gameTitle
            existing.resolvedURL = resolvedURL
            existing.httpStatus = httpStatus
            existing.isValid = isValid
            existing.resolvedAt = Date()
        } else {
            context.insert(BoxArtResolutionEntry(
                romPathKey: romPathKey, systemID: systemID, gameTitle: gameTitle,
                resolvedURL: resolvedURL, source: source, httpStatus: httpStatus,
                isValid: isValid, resolvedAt: Date()))
        }
        try? context.save()
    }

    func clearBoxArtResolutions() {
        if let entries = try? context.fetch(FetchDescriptor<BoxArtResolutionEntry>()) {
            entries.forEach { context.delete($0) }
            try? context.save()
        }
    }

    static func computeSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func toCacheData(from m: ResourceCacheEntryModel) -> RCCacheData {
        RCCacheData(cacheKey: m.cacheKey, resourceType: m.resourceType,
                    sourceURL: m.sourceURL, responseStatus: m.responseStatus,
                    contentType: m.contentType, fileSize: m.fileSize,
                    localPath: m.localPath, etag: m.etag,
                    lastModified: m.lastModified, checksum: m.checksum,
                    expiresAt: m.expiresAt, createdAt: m.createdAt,
                    updatedAt: m.updatedAt, accessCount: m.accessCount,
                    lastAccessed: m.lastAccessed)
    }

    private func toBoxArtData(from m: BoxArtResolutionEntry) -> RCBoxArtData {
        RCBoxArtData(romPathKey: m.romPathKey, systemID: m.systemID,
                     gameTitle: m.gameTitle, resolvedURL: m.resolvedURL,
                     source: m.source, httpStatus: m.httpStatus,
                     isValid: m.isValid, resolvedAt: m.resolvedAt)
    }
}
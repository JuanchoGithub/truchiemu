import Foundation
import SwiftData

// MARK: - ROM Entry

@Model
final class ROMEntry {
    @Attribute(.unique) var id: UUID
    var name: String
    var path: String
    var systemID: String?
    var hasBoxArt: Bool
    var isFavorite: Bool
    var lastPlayed: Date?
    var totalPlaytimeSeconds: Double
    var timesPlayed: Int
    var selectedCoreID: String?
    var customName: String?
    var useCustomCore: Bool
    var metadataJSON: String?
    var isBios: Bool
    var isHidden: Bool
    var dateAdded: Date
    var category: String
    var crc32: String?
    var thumbnailLookupSystemID: String?
    var screenshotPathsJSON: String?
    var settingsJSON: String?
    var isIdentified: Bool
    var raGameI: Int?
    var raMatchStatus: String? // Values: "matched", "mismatch:<expected_hash>", "not_supported"

    // Relationships
    // Note: inverse relationships with @Relationship can cause circular reference issues
    // Using forward-only relationships to avoid Swift macro expansion bugs
    @Relationship(deleteRule: .cascade) var metadata: ROMMetadataEntry?
    // var identificationResults: [GameDBEntry] = []  // Temporarily disabled due to circular ref

    // Computed properties
    var displayName: String {
        customName ?? metadata?.title ?? name
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        systemID: String? = nil,
        hasBoxArt: Bool = false,
        isFavorite: Bool = false,
        lastPlayed: Date? = nil,
        totalPlaytimeSeconds: Double = 0.0,
        timesPlayed: Int = 0,
        selectedCoreID: String? = nil,
        customName: String? = nil,
        useCustomCore: Bool = false,
        metadataJSON: String? = nil,
        isBios: Bool = false,
        isHidden: Bool = false,
        dateAdded: Date = Date(),
        category: String = "game",
        crc32: String? = nil,
        thumbnailLookupSystemID: String? = nil,
        screenshotPathsJSON: String? = nil,
        settingsJSON: String? = nil,
        isIdentified: Bool = false,
        raGameId: Int? = nil,
        raMatchStatus: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path.path
        self.systemID = systemID
        self.hasBoxArt = hasBoxArt
        self.isFavorite = isFavorite
        self.lastPlayed = lastPlayed
        self.totalPlaytimeSeconds = totalPlaytimeSeconds
        self.timesPlayed = timesPlayed
        self.selectedCoreID = selectedCoreID
        self.customName = customName
        self.useCustomCore = useCustomCore
        self.metadataJSON = metadataJSON
        self.isBios = isBios
        self.isHidden = isHidden
        self.dateAdded = dateAdded
        self.category = category
        self.crc32 = crc32
        self.thumbnailLookupSystemID = thumbnailLookupSystemID
        self.screenshotPathsJSON = screenshotPathsJSON
        self.settingsJSON = settingsJSON
        self.isIdentified = isIdentified
        self.raGameId = raGameId
        self.raMatchStatus = raMatchStatus
    }
}

// MARK: - ROM Metadata Entry

@Model
final class ROMMetadataEntry {
    @Attribute(.unique) var pathKey: String
    var crc32: String?
    var title: String?
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var players: Int?
    var gameDescription: String?
    var rating: Double?
    var cooperative: Bool?
    var esrbRating: String?
    var thumbnailSystemID: String?
    var hasBoxArt: Bool
    var titleScreenPath: String?
    var screenshotPathsJSON: String?
    var customCoreID: String?
    var customName: String?

    // Note: inverse relationship disabled to avoid circular reference
    var romID: UUID?

    init(
        pathKey: String,
        crc32: String? = nil,
        title: String? = nil,
        year: String? = nil,
        developer: String? = nil,
        publisher: String? = nil,
        genre: String? = nil,
        players: Int? = nil,
        gameDescription: String? = nil,
        rating: Double? = nil,
        cooperative: Bool? = nil,
        esrbRating: String? = nil,
        thumbnailSystemID: String? = nil,
        hasBoxArt: Bool = false,
        titleScreenPath: String? = nil,
        screenshotPathsJSON: String? = nil,
        customCoreID: String? = nil,
        customName: String? = nil
    ) {
        self.pathKey = pathKey
        self.crc32 = crc32
        self.title = title
        self.year = year
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.players = players
        self.gameDescription = gameDescription
        self.rating = rating
        self.cooperative = cooperative
        self.esrbRating = esrbRating
        self.thumbnailSystemID = thumbnailSystemID
        self.hasBoxArt = hasBoxArt
        self.titleScreenPath = titleScreenPath
        self.screenshotPathsJSON = screenshotPathsJSON
        self.customCoreID = customCoreID
        self.customName = customName
    }
}

// MARK: - Game DB Entry

@Model
final class GameDBEntry {
    var systemID: String
    var crc: String
    var title: String
    var strippedTitle: String
    var year: String?
    var developer: String?
    var publisher: String?
    var genre: String?
    var thumbnailSystemID: String?

    // Note: inverse relationship disabled to avoid circular reference
    var romID: UUID?

    init(
        systemID: String,
        crc: String,
        title: String,
        strippedTitle: String,
        year: String? = nil,
        developer: String? = nil,
        publisher: String? = nil,
        genre: String? = nil,
        thumbnailSystemID: String? = nil
    ) {
        self.systemID = systemID
        self.crc = crc
        self.title = title
        self.strippedTitle = strippedTitle
        self.year = year
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.thumbnailSystemID = thumbnailSystemID
    }
}

// MARK: - Library Folder

@Model
final class LibraryFolder {
    @Attribute(.unique) var urlPath: String
    var bookmarkData: Data
    var parentPath: String?
    var isPrimary: Bool

    // Computed property
    var url: URL {
        URL(fileURLWithPath: urlPath)
    }

    init(
        urlPath: String,
        bookmarkData: Data,
        parentPath: String? = nil,
        isPrimary: Bool = false
    ) {
        self.urlPath = urlPath
        self.bookmarkData = bookmarkData
        self.parentPath = parentPath
        self.isPrimary = isPrimary
    }
}

// MARK: - Installed Core

@Model
final class InstalledCore {
    @Attribute(.unique) var coreID: String
    var displayName: String
    var versionTag: String?
    var installDate: Date
    var systemIDsJSON: String?
    var dylibPath: String?
    var isActive: Bool

    init(
        coreID: String,
        displayName: String,
        versionTag: String? = nil,
        installDate: Date = Date(),
        systemIDsJSON: String? = nil,
        dylibPath: String? = nil,
        isActive: Bool = true
    ) {
        self.coreID = coreID
        self.displayName = displayName
        self.versionTag = versionTag
        self.installDate = installDate
        self.systemIDsJSON = systemIDsJSON
        self.dylibPath = dylibPath
        self.isActive = isActive
    }
}

// MARK: - Available Core

@Model
final class AvailableCore {
    @Attribute(.unique) var coreID: String
    var displayName: String
    var systemIDsJSON: String?
    var downloadURL: String?
    var lastChecked: Date?

    init(
        coreID: String,
        displayName: String,
        systemIDsJSON: String? = nil,
        downloadURL: String? = nil,
        lastChecked: Date? = nil
    ) {
        self.coreID = coreID
        self.displayName = displayName
        self.systemIDsJSON = systemIDsJSON
        self.downloadURL = downloadURL
        self.lastChecked = lastChecked
    }
}

// MARK: - Controller Mapping

@Model
final class ControllerMapping {
    @Attribute(.unique) var mappingID: String
    var deviceType: String
    var configJSON: String

    init(
        mappingID: String,
        deviceType: String,
        configJSON: String
    ) {
        self.mappingID = mappingID
        self.deviceType = deviceType
        self.configJSON = configJSON
    }
}

// MARK: - Achievements Config

@Model
final class AchievementConfig {
    var username: String?
    var token: String?
    var isHardcore: Bool
    var isEnabled: Bool

    static let singletonID = 1

    init(
        username: String? = nil,
        token: String? = nil,
        isHardcore: Bool = false,
        isEnabled: Bool = true
    ) {
        self.username = username
        self.token = token
        self.isHardcore = isHardcore
        self.isEnabled = isEnabled
    }
}

// MARK: - Cheat Store

@Model
final class CheatStore {
    @Attribute(.unique) var romKey: String
    var cheatsJSON: String

    init(
        romKey: String,
        cheatsJSON: String
    ) {
        self.romKey = romKey
        self.cheatsJSON = cheatsJSON
    }
}

// MARK: - Game Category Entry

@Model
final class GameCategoryEntry {
    @Attribute(.unique) var categoryID: String
    var name: String
    var iconName: String
    var colorHex: String
    var gameIDsJSON: String
    var sortOrder: Int

    init(
        categoryID: String,
        name: String,
        iconName: String,
        colorHex: String,
        gameIDsJSON: String,
        sortOrder: Int = 0
    ) {
        self.categoryID = categoryID
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.gameIDsJSON = gameIDsJSON
        self.sortOrder = sortOrder
    }
}

// MARK: - Bezel Preferences

@Model
final class BezelPreferences {
    var storageMode: String
    var customFolderPath: String?
    var libraryFolderPath: String?
    var initialSetupComplete: Bool
    var lastPromptedLibraryCount: Int
    var downloadLogJSON: String?

    init(
        storageMode: String = "local",
        customFolderPath: String? = nil,
        libraryFolderPath: String? = nil,
        initialSetupComplete: Bool = false,
        lastPromptedLibraryCount: Int = 0,
        downloadLogJSON: String? = nil
    ) {
        self.storageMode = storageMode
        self.customFolderPath = customFolderPath
        self.libraryFolderPath = libraryFolderPath
        self.initialSetupComplete = initialSetupComplete
        self.lastPromptedLibraryCount = lastPromptedLibraryCount
        self.downloadLogJSON = downloadLogJSON
    }
}

// MARK: - Box Art Preferences

@Model
final class BoxArtPreferences {
    var credentialsJSON: String?
    var useLibretro: Bool
    var useHeadCheck: Bool
    var fallbackFilename: String?

    init(
        credentialsJSON: String? = nil,
        useLibretro: Bool = false,
        useHeadCheck: Bool = false,
        fallbackFilename: String? = nil
    ) {
        self.credentialsJSON = credentialsJSON
        self.useLibretro = useLibretro
        self.useHeadCheck = useHeadCheck
        self.fallbackFilename = fallbackFilename
    }
}

// MARK: - Core Option Entry

@Model
final class CoreOptionEntry {
    var coreID: String
    var optionKey: String
    var optionValue: String?
    var isOverride: Bool

    @Attribute(.unique) var compositeKey: String

    init(
        coreID: String,
        optionKey: String,
        optionValue: String? = nil,
        isOverride: Bool = false
    ) {
        self.coreID = coreID
        self.optionKey = optionKey
        self.optionValue = optionValue
        self.isOverride = isOverride
        self.compositeKey = "\(coreID)::\(optionKey)"
    }
}

// MARK: - Shader Preset Entry

@Model
final class ShaderPresetEntry {
    @Attribute(.unique) var id: String
    var name: String
    var presetJSON: String
    var windowPositionJSON: String?

    init(
        id: String,
        name: String,
        presetJSON: String,
        windowPositionJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.presetJSON = presetJSON
        self.windowPositionJSON = windowPositionJSON
    }
}

// MARK: - Resource Cache Entry Model

@Model
final class ResourceCacheEntryModel {
    @Attribute(.unique) var cacheKey: String
    var resourceType: String
    var sourceURL: String
    var responseStatus: Int?
    var contentType: String?
    var fileSize: Int?
    var localPath: String?
    var etag: String?
    var lastModified: String?
    var checksum: String?
    var expiresAt: Int?
    var createdAt: Date
    var updatedAt: Date
    var accessCount: Int
    var lastAccessed: Date?

    // Note: inverse relationship disabled to avoid circular reference
    // var datIngestionRecords: [DATIngestionEntry] = []

    // Computed properties
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date.now.timeIntervalSince1970 > Double(expiresAt)
    }

    var isHit: Bool {
        responseStatus == 200 || responseStatus == 304
    }

    init(
        cacheKey: String,
        resourceType: String,
        sourceURL: String,
        responseStatus: Int? = nil,
        contentType: String? = nil,
        fileSize: Int? = nil,
        localPath: String? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        checksum: String? = nil,
        expiresAt: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        accessCount: Int = 0,
        lastAccessed: Date? = nil
    ) {
        self.cacheKey = cacheKey
        self.resourceType = resourceType
        self.sourceURL = sourceURL
        self.responseStatus = responseStatus
        self.contentType = contentType
        self.fileSize = fileSize
        self.localPath = localPath
        self.etag = etag
        self.lastModified = lastModified
        self.checksum = checksum
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accessCount = accessCount
        self.lastAccessed = lastAccessed
    }
}

// MARK: - DAT Ingestion Entry

@Model
final class DATIngestionEntry {
    var systemID: String
    var sourceName: String
    var entriesFound: Int
    var entriesIngested: Int
    var ingestionStatus: String
    var errorMessage: String?
    var durationMs: Int
    var ingestedAt: Date

    // Reference to resource cache (no inverse relationship to avoid circular ref)
    var resourceCacheID: Int?

    init(
        resourceCacheID: Int? = nil,
        systemID: String,
        sourceName: String,
        entriesFound: Int,
        entriesIngested: Int,
        ingestionStatus: String,
        errorMessage: String? = nil,
        durationMs: Int,
        ingestedAt: Date = Date()
    ) {
        self.resourceCacheID = resourceCacheID
        self.systemID = systemID
        self.sourceName = sourceName
        self.entriesFound = entriesFound
        self.entriesIngested = entriesIngested
        self.ingestionStatus = ingestionStatus
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.ingestedAt = ingestedAt
    }
}

// MARK: - Box Art Resolution Entry

@Model
final class BoxArtResolutionEntry {
    var romPathKey: String
    var systemID: String
    var gameTitle: String?
    var resolvedURL: String
    var source: String
    var httpStatus: Int
    var isValid: Bool
    var resolvedAt: Date

    @Attribute(.unique) var compositeKey: String

    init(
        romPathKey: String,
        systemID: String,
        gameTitle: String? = nil,
        resolvedURL: String,
        source: String,
        httpStatus: Int,
        isValid: Bool,
        resolvedAt: Date = Date()
    ) {
        self.romPathKey = romPathKey
        self.systemID = systemID
        self.gameTitle = gameTitle
        self.resolvedURL = resolvedURL
        self.source = source
        self.httpStatus = httpStatus
        self.isValid = isValid
        self.resolvedAt = resolvedAt
        self.compositeKey = "\(romPathKey)::\(source)"
    }
}


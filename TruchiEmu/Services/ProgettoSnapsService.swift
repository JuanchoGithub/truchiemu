import Foundation
import SwiftUI

// MARK: - Progetto-SNAPS Metadata Service
//
// Downloads and parses catver.ini/genre.ini from Progetto-SNAPS for MAME genre metadata.
// Uses 30-day caching following existing metadata patterns.
//
@MainActor
final class ProgettoSnapsService: ObservableObject {
    static let shared = ProgettoSnapsService()

    // MARK: - URLs

    // Progetto-SNAPS catver.ini URL - in metadata/ folder
    private let catverURL = URL(string: "https://raw.githubusercontent.com/libretro/mame2003-plus-libretro/master/metadata/catver.ini")!
    // Genre INI file
    private let genreURL = URL(string: "https://raw.githubusercontent.com/libretro/mame2003-plus-libretro/master/metadata/genre.ini")!

    // MARK: - Cache Settings

    private let cacheFreshnessDays: Int = 30
    private let keyAutoUpdate = "mame_genres_auto_update"
    private let keyLastUpdated = "mame_metadata_last_updated"

    // MARK: - Published State

    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var downloadError: String?

    // MARK: - Runtime Data

    private var _catverDictionary: [String: String]?
    private var _genreDictionary: [String: String]?

    // MARK: - Cache Paths

    private var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/MAME", isDirectory: true)
    }

    private var catverCachePath: URL {
        cacheDirectory.appendingPathComponent(".cache_catver.ini")
    }

    private var genreCachePath: URL {
        cacheDirectory.appendingPathComponent(".cache_genre.ini")
    }

    private var versionPath: URL {
        cacheDirectory.appendingPathComponent(".version.json")
    }

    // MARK: - Public API

    var autoUpdateEnabled: Bool {
        get { AppSettings.getBool(keyAutoUpdate, defaultValue: true) }
        set { AppSettings.setBool(keyAutoUpdate, value: newValue) }
    }

    /// Returns true if MAME genre metadata is available.
    var isMetadataAvailable: Bool {
        _catverDictionary != nil || loadCachedDictionary() != nil
    }

    /// Download fresh metadata if needed (based on 30-day cache).
    func downloadMetadataIfNeeded() async {
        // Check settings
        guard autoUpdateEnabled else { return }

        // Check if cache is valid
        guard !isCacheValid() else { return }

        // Check if we have MAME ROMs (skip if no MAME games in library)
        // For now, we proceed - lightweight check

        await downloadMetadata()
    }

    /// Force download fresh metadata from Progetto-SNAPS.
    func downloadMetadata() async {
        guard !isDownloading else { return }

        isDownloading = true
        downloadError = nil

        do {
            // Ensure cache directory exists
            try ensureCacheDirectory()

            // Download catver.ini (contains categories)
            LoggerService.info(category: "ProgettoSnaps", "Downloading catver.ini from GitHub...")
            let catverData = try await downloadFile(from: catverURL, to: catverCachePath)
            _catverDictionary = parseCatverINI(data: catverData)
            LoggerService.info(category: "ProgettoSnaps", "Parsed \(_catverDictionary?.count ?? 0) catver entries")

            // Download genre.ini (optional - may be 404)
            do {
                LoggerService.info(category: "ProgettoSnaps", "Downloading genre.ini from GitHub...")
                let genreData = try await downloadFile(from: genreURL, to: genreCachePath)
                _genreDictionary = parseGenreINI(data: genreData)
            } catch {
                // genre.ini is optional - ignore 404
                LoggerService.info(category: "ProgettoSnaps", "genre.ini not available (optional)")
            }

            // Save version info
            saveVersionInfo()

            lastUpdated = Date()
            if let timestamp = lastUpdated {
                AppSettings.set(keyLastUpdated, value: timestamp.timeIntervalSince1970)
            }

            LoggerService.info(category: "ProgettoSnaps", "Downloaded MAME metadata: \(_catverDictionary?.count ?? 0) entries")
        } catch {
            downloadError = error.localizedDescription
            LoggerService.error(category: "ProgettoSnaps", "Download failed: \(error)")
        }

        isDownloading = false
    }

    /// Get genre/category for a MAME ROM.
    func getGenre(for romShortName: String) -> String? {
        // Try in-memory cache first
        if let cached = _catverDictionary?[romShortName] {
            return extractMainCategory(from: cached)
        }

        // Try disk cache
        let diskCache = loadCachedDictionary()
        if let fromDisk = diskCache?[romShortName] {
            // Cache in memory for future access
            _catverDictionary = diskCache
            return extractMainCategory(from: fromDisk)
        }

        return nil
    }

    /// Get all available genres from metadata.
    func getAllGenres() -> [String] {
        let source = _catverDictionary ?? loadCachedDictionary() ?? [:]
        let categories = Set(source.values.map { extractMainCategory(from: $0) })
        return Array(categories).sorted()
    }

    // MARK: - Cache Management

    private func isCacheValid() -> Bool {
        guard FileManager.default.fileExists(atPath: catverCachePath.path) else {
            return false
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: catverCachePath.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return false
        }

        let freshnessInterval = TimeInterval(cacheFreshnessDays * 24 * 60 * 60)
        return Date().timeIntervalSince(modificationDate) < freshnessInterval
    }

    func loadCachedDictionary() -> [String: String]? {
        guard FileManager.default.fileExists(atPath: catverCachePath.path),
              let data = try? Data(contentsOf: catverCachePath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Cache in memory for faster subsequent access
        if _catverDictionary == nil {
            _catverDictionary = parseCatverINI(data: data)
        }

        return _catverDictionary
    }

    private func ensureCacheDirectory() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    private func saveVersionInfo() {
        let info: [String: Any] = [
            "lastUpdated": Date().timeIntervalSince1970,
            "entries": _catverDictionary?.count ?? 0
        ]

        if let data = try? JSONSerialization.data(withJSONObject: info),
           let json = String(data: data, encoding: .utf8) {
            try? json.write(to: versionPath, atomically: true, encoding: .utf8)
        }
    }

    private func loadVersionInfo() {
        guard let data = try? Data(contentsOf: versionPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = json["lastUpdated"] as? TimeInterval else {
            // Try loading from AppSettings
            let timestamp = AppSettings.getDouble(keyLastUpdated, defaultValue: 0)
            if timestamp > 0 {
                lastUpdated = Date(timeIntervalSince1970: timestamp)
            }
            return
        }

        lastUpdated = Date(timeIntervalSince1970: timestamp)
    }

    // MARK: - Network

    private func downloadFile(from url: URL, to destination: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.setValue("TruchiEmu/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProgettoSnapsError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ProgettoSnapsError.httpError(httpResponse.statusCode)
        }

        // Save to cache
        try data.write(to: destination)

        return data
    }

    // MARK: - INI Parsing

    /// Parse catver.ini format: romname=Category/Subcategory
    private func parseCatverINI(data: Data) -> [String: String]? {
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var result: [String: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            // Parse key=value
            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

                if !key.isEmpty && !value.isEmpty {
                    result[key] = value
                }
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Parse genre.ini format: romname=Genre
    private func parseGenreINI(data: Data) -> [String: String]? {
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var result: [String: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

                if !key.isEmpty && !value.isEmpty {
                    result[key] = value
                }
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Extract main category from "Fighting / Versus" -> "Fighting"
    private func extractMainCategory(from fullCategory: String) -> String {
        if let slashIndex = fullCategory.firstIndex(of: "/") {
            let main = String(fullCategory[..<slashIndex])
            return main.trimmingCharacters(in: .whitespaces)
        }
        return fullCategory.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Initialization

    private init() {
        loadVersionInfo()
    }
}

// MARK: - Errors

enum ProgettoSnapsError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .parseError:
            return "Failed to parse metadata"
        }
    }
}
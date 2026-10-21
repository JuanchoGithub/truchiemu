import Foundation
import AppKit

// Bundled game-icons.net library (4180 single-fill vector icons) used for
// category iconography. The PDFs ship inside game-icons.zip and are unpacked
// to Application Support on first launch (versioned via AppSettings so bundle
// updates re-unpack). Icons load on demand as template NSImages so the
// surrounding foreground style tints them like SF Symbols.
@MainActor
final class GamingIconService: ObservableObject {
    static let shared = GamingIconService()

    /// Prefix stored in GameCategory.iconName / SystemInfo.iconName for icons
    /// from this library, e.g. "gi:lorc/castle".
    nonisolated static let iconPrefix = "gi:"

    enum LoadState: Equatable {
        case idle
        case unpacking
        case ready
        case failed(String)
    }

    struct Manifest: Codable {
        let version: Int
        let source: String
        let license: String
        let licenseUrl: String
        let credits: String
        let tags: [String: String]
        let themes: [Theme]
        let icons: [Icon]
    }

    struct Theme: Codable, Identifiable {
        let key: String
        let title: String
        let tags: [String]
        var id: String { key }
    }

    struct Icon: Codable, Identifiable, Hashable {
        let id: String // "author/name"
        let name: String
        let author: String
        let tags: [String]
    }

    @Published private(set) var state: LoadState = .idle

    private(set) var manifest: Manifest?
    private var themeIndex: [String: [Icon]] = [:]
    private let imageCache = NSCache<NSString, NSImage>()
    private var unpackTask: Task<Void, Never>?

    private nonisolated static let unpackedVersionKey = "gaming_icons_unpacked_version"
    private static let logCategory = "GamingIcons"

    private nonisolated static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/GamingIcons")
    }

    private init() {
        imageCache.countLimit = 500
        loadManifest()
        ensureUnpacked()
    }

    // MARK: - Manifest

    private func loadManifest() {
        guard let url = Bundle.main.url(forResource: "game-icons-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data) else {
            LoggerService.error(category: Self.logCategory, "Failed to load game-icons manifest from bundle")
            return
        }
        manifest = decoded
    }

    var creditsText: String? { manifest?.credits }
    var licenseURL: URL? { manifest.flatMap { URL(string: $0.licenseUrl) } }

    // MARK: - Unpack

    func ensureUnpacked() {
        guard unpackTask == nil else { return }
        guard let manifest else {
            state = .failed("missing manifest")
            return
        }
        let dirExists = FileManager.default.fileExists(atPath: Self.storageDirectory.path)
        if AppSettings.getInt(Self.unpackedVersionKey, defaultValue: 0) == manifest.version, dirExists {
            state = .ready
            return
        }

        state = .unpacking
        let version = manifest.version
        #if LOG_DEBUG
        LoggerService.debug(category: Self.logCategory, "Unpacking gaming icons v\(version)...")
        #endif
        unpackTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try Self.unpackBundle()
                await self?.finishUnpack(version: version)
            } catch {
                await self?.failUnpack(error.localizedDescription)
            }
        }
    }

    private nonisolated static func unpackBundle() throws {
        guard let zipURL = Bundle.main.url(forResource: "game-icons", withExtension: "zip") else {
            throw NSError(domain: "GamingIcons", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "game-icons.zip missing from bundle"])
        }

        let fileManager = FileManager.default
        let destination = storageDirectory
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("GamingIcons-tmp")

        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        try runUnzip(zipURL: zipURL, destination: staging)
        // Sanity check: the archive must actually contain icon PDFs.
        let entries = try fileManager.contentsOfDirectory(atPath: staging.path)
        guard !entries.isEmpty else {
            throw NSError(domain: "GamingIcons", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "game-icons.zip unpacked empty"])
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: staging, to: destination)
    }

    private nonisolated static func runUnzip(zipURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipURL.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GamingIcons", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "unzip exited with status \(process.terminationStatus)"])
        }
    }

    private func finishUnpack(version: Int) {
        AppSettings.setInt(Self.unpackedVersionKey, value: version)
        state = .ready
        unpackTask = nil
        #if LOG_DEBUG
        LoggerService.debug(category: Self.logCategory, "Gaming icons v\(version) ready at \(Self.storageDirectory.path)")
        #endif
    }

    private func failUnpack(_ message: String) {
        LoggerService.error(category: Self.logCategory, "Failed to unpack gaming icons: \(message)")
        state = .failed(message)
        unpackTask = nil
    }

    // MARK: - Icon access

    /// True when the stored icon name refers to this library (prefix "gi:").
    nonisolated static func isGamingIconName(_ iconName: String) -> Bool {
        iconName.hasPrefix(iconPrefix)
    }

    /// Template image for a stored icon name ("gi:author/name"), or nil when
    /// the name is not a gaming icon, is malformed, or is not yet unpacked.
    func image(for iconName: String) -> NSImage? {
        guard let id = iconID(from: iconName) else { return nil }
        if let cached = imageCache.object(forKey: id as NSString) { return cached }
        guard state == .ready else { return nil }
        let url = Self.storageDirectory.appendingPathComponent(id).appendingPathExtension("pdf")
        guard let image = NSImage(contentsOfFile: url.path) else { return nil }
        image.isTemplate = true
        imageCache.setObject(image, forKey: id as NSString)
        return image
    }

    /// Validates "gi:author/name" and returns "author/name", or nil.
    /// The character whitelist blocks path traversal from hand-edited data.
    func iconID(from iconName: String) -> String? {
        guard iconName.hasPrefix(Self.iconPrefix) else { return nil }
        let id = String(iconName.dropFirst(Self.iconPrefix.count))
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty }),
              id == id.lowercased(),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "/") })
        else { return nil }
        return id
    }

    func search(_ query: String) -> [Icon] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let manifest else { return [] }
        return manifest.icons.filter { icon in
            icon.name.localizedCaseInsensitiveContains(trimmed)
            || icon.id.localizedCaseInsensitiveContains(trimmed)
            || icon.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    func icons(for theme: Theme) -> [Icon] {
        if let cached = themeIndex[theme.key] { return cached }
        let result = manifest?.icons.filter { icon in
            !Set(icon.tags).isDisjoint(with: theme.tags)
        } ?? []
        themeIndex[theme.key] = result
        return result
    }
}

import AppKit
import Foundation
import ImageIO

enum BoxArtThumbnailSize: String, CaseIterable {
    case tiny
    case small
    case medium
    case large

    var maxPixelSize: CGFloat {
        switch self {
        case .tiny: return 150
        case .small: return 400
        case .medium: return 540
        case .large: return 800
        }
    }

    var maxPixelHeight: CGFloat {
        switch self {
        case .tiny: return 200
        case .small: return 400
        case .medium: return 540
        case .large: return 800
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .tiny: return 0.75
        case .small: return 0.80
        case .medium: return 0.82
        case .large: return 0.85
        }
    }

    var suffix: String {
        switch self {
        case .tiny: return "_tiny"
        case .small: return "_small"
        case .medium: return "_medium"
        case .large: return "_large"
        }
    }

    static func forGridZoom(_ continuousZoom: Double) -> BoxArtThumbnailSize {
        if continuousZoom <= 0.4 {
            return .small
        } else if continuousZoom <= 0.6 {
            return .medium
        } else {
            return .large
        }
    }
}

@MainActor
class BoxArtThumbnailService: ObservableObject {
    static let shared = BoxArtThumbnailService()

    private var fileWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var debounceTimers: [URL: Timer] = [:]

    private let generationQueue = DispatchQueue(label: "com.truchiemu.thumbnail-gen", qos: .utility, attributes: .concurrent)
    private var pendingGeneration: Set<String> = []
    private var activeGenerationCount = 0
    private let maxConcurrentGeneration = 4

    private init() {}

    // MARK: - Thumbnail Path Resolution

    nonisolated
    static func thumbnailURL(for originalURL: URL, size: BoxArtThumbnailSize) -> URL {
        let thumbsDir = originalURL.deletingLastPathComponent().appendingPathComponent("te_thumbs")
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        return thumbsDir.appendingPathComponent("\(baseName)\(size.suffix).jpg")
    }

    nonisolated
    static func thumbsDirectoryURL(for originalURL: URL) -> URL {
        return originalURL.deletingLastPathComponent().appendingPathComponent("te_thumbs")
    }

    // MARK: - On-Demand Background Generation

    nonisolated
    static func scheduleGeneration(forOriginal originalURL: URL) {
        Task { @MainActor in
            shared.enqueueGeneration(for: originalURL)
        }
    }

    private func enqueueGeneration(for originalURL: URL) {
        let path = originalURL.path
        guard !pendingGeneration.contains(path) else { return }
        pendingGeneration.insert(path)

        tryDrainGenerationQueue()
    }

    private func tryDrainGenerationQueue() {
        guard activeGenerationCount < maxConcurrentGeneration,
              let nextPath = pendingGeneration.popFirst() else { return }

        let url = URL(fileURLWithPath: nextPath)
        activeGenerationCount += 1

        generationQueue.async { [weak self] in
            Self.generateThumbnailsSynchronously(forOriginal: url)

            Task { @MainActor [weak self] in
                self?.activeGenerationCount -= 1
                self?.tryDrainGenerationQueue()
            }
        }
    }

    // MARK: - Direct Generation (used by BoxArtService after download)

    func generateThumbnails(forOriginal originalURL: URL) {
        guard FileManager.default.fileExists(atPath: originalURL.path) else { return }
        Self.generateThumbnailsSynchronously(forOriginal: originalURL)
    }

    nonisolated
    static func generateThumbnailsSynchronously(forOriginal originalURL: URL) {
        let thumbsDir = originalURL.deletingLastPathComponent().appendingPathComponent("te_thumbs")

        do {
            try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        } catch {
            LoggerService.error(category: "BoxArtThumbnails", "Failed to create te_thumbs dir at \(thumbsDir.path): \(error.localizedDescription)")
            return
        }

        guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil) else {
            LoggerService.error(category: "BoxArtThumbnails", "CGImageSourceCreateWithURL failed for \(originalURL.lastPathComponent)")
            return
        }

        for size in BoxArtThumbnailSize.allCases {
            let thumbURL = Self.thumbnailURL(for: originalURL, size: size)

            if FileManager.default.fileExists(atPath: thumbURL.path) {
                if let thumbMod = try? FileManager.default.attributesOfItem(atPath: thumbURL.path)[.modificationDate] as? Date,
                   let origMod = try? FileManager.default.attributesOfItem(atPath: originalURL.path)[.modificationDate] as? Date,
                   thumbMod >= origMod {
                    continue
                }
            }

            let maxPx = max(size.maxPixelSize, size.maxPixelHeight)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPx)
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                LoggerService.error(category: "BoxArtThumbnails", "Failed to create thumbnail for \(originalURL.lastPathComponent) size \(size.rawValue)")
                continue
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let tiffRep = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffRep),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: size.jpegQuality]) else {
                LoggerService.error(category: "BoxArtThumbnails", "JPEG encoding failed for \(originalURL.lastPathComponent) size \(size.rawValue)")
                continue
            }

            do {
                try jpegData.write(to: thumbURL, options: .atomic)
            } catch {
                LoggerService.error(category: "BoxArtThumbnails", "Failed to write \(thumbURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Existence & Validation

    nonisolated
    static func thumbnailExists(for originalURL: URL, size: BoxArtThumbnailSize) -> Bool {
        let url = thumbnailURL(for: originalURL, size: size)
        return FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated
    static func needsRegeneration(for originalURL: URL, size: BoxArtThumbnailSize) -> Bool {
        let thumbURL = thumbnailURL(for: originalURL, size: size)
        guard FileManager.default.fileExists(atPath: thumbURL.path),
              FileManager.default.fileExists(atPath: originalURL.path) else {
            return true
        }
        guard let thumbMod = try? FileManager.default.attributesOfItem(atPath: thumbURL.path)[.modificationDate] as? Date,
              let origMod = try? FileManager.default.attributesOfItem(atPath: originalURL.path)[.modificationDate] as? Date else {
            return true
        }
        return thumbMod < origMod
    }

    // MARK: - Deletion & Invalidation

    nonisolated
    static func deleteThumbnails(for originalURL: URL) {
        for size in BoxArtThumbnailSize.allCases {
            let url = thumbnailURL(for: originalURL, size: size)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func invalidateAndRegenerate(for rom: ROM) {
        let originalURL = rom.boxArtLocalPath
        Self.deleteThumbnails(for: originalURL)
        Task {
            await ImageCache.shared.removeImage(for: originalURL)
            await ImageCache.shared.removeThumbnail(for: originalURL)
        }
        Self.generateThumbnailsSynchronously(forOriginal: originalURL)
    }

    func invalidateAndRegenerate(for originalURL: URL) {
        Self.deleteThumbnails(for: originalURL)
        Task {
            await ImageCache.shared.removeImage(for: originalURL)
            await ImageCache.shared.removeThumbnail(for: originalURL)
        }
        Self.generateThumbnailsSynchronously(forOriginal: originalURL)
    }

    // MARK: - File Watching

    func startWatching(directory: URL) {
        guard !fileWatchers.keys.contains(directory) else { return }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        let watchedDir = directory
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleDirectoryChange(at: watchedDir)
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
        fileWatchers[directory] = source
    }

    func stopWatching(directory: URL) {
        if let source = fileWatchers[directory] {
            source.cancel()
            fileWatchers.removeValue(forKey: directory)
        }
    }

    func stopAllWatching() {
        for (_, source) in fileWatchers {
            source.cancel()
        }
        fileWatchers.removeAll()
    }

    private func handleDirectoryChange(at directory: URL) {
        debounceTimers[directory]?.invalidate()
        debounceTimers[directory] = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.processDirectoryChanges(at: directory)
        }
    }

    private func processDirectoryChanges(at directory: URL) {
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ["png", "jpg", "jpeg", "gif", "webp", "bmp"].contains(ext)
                }
        } catch {
            return
        }

        for fileURL in fileURLs {
            if Self.needsRegeneration(for: fileURL, size: .tiny) {
                Self.scheduleGeneration(forOriginal: fileURL)
                Task {
                    await ImageCache.shared.removeImage(for: fileURL)
                    await ImageCache.shared.removeThumbnail(for: fileURL)
                }
                BoxArtService.shared.boxArtUpdated = UUID()
            }
        }
    }

    // MARK: - Migration

    func migrateOldThumbnailCache() {
        guard !AppSettings.getBool("boxArtThumbnailServiceMigrated", defaultValue: false) else { return }

        let oldCacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TruchiEmu/ThumbnailCache", isDirectory: true)

        if FileManager.default.fileExists(atPath: oldCacheDir.path) {
            try? FileManager.default.removeItem(at: oldCacheDir)
            LoggerService.info(category: "BoxArtThumbnails", "Deleted old ThumbnailCache directory")
        }

        AppSettings.setBool("boxArtThumbnailServiceMigrated", value: true)
    }
}

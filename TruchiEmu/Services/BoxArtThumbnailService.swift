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
    // Higher concurrency so a large library's thumbnails finish warming
    // (generated to disk) well before the user has scrolled through it —
    // until then scrolling falls back to decoding the full original, which
    // is what caused the cold-scroll lag.
    private let maxConcurrentGeneration = 12

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

    private func enqueueGeneration(for originalURL: URL, sizes: [BoxArtThumbnailSize]? = nil) {
        let path = originalURL.path
        guard !pendingGeneration.contains(path) else { return }
        pendingGeneration.insert(path)

        tryDrainGenerationQueue(sizes: sizes)
    }

    private func tryDrainGenerationQueue(sizes: [BoxArtThumbnailSize]? = nil) {
        guard activeGenerationCount < maxConcurrentGeneration,
              let nextPath = pendingGeneration.popFirst() else { return }

        let url = URL(fileURLWithPath: nextPath)
        activeGenerationCount += 1

        generationQueue.async { [weak self] in
            Self.generateThumbnailsSynchronously(forOriginal: url, sizes: sizes)

            Task { @MainActor [weak self] in
                self?.activeGenerationCount -= 1
                self?.tryDrainGenerationQueue(sizes: sizes)
            }
        }
    }

    // MARK: - Direct Generation (used by BoxArtService after download)

    func generateThumbnails(forOriginal originalURL: URL) {
        guard FileManager.default.fileExists(atPath: originalURL.path) else { return }
        Self.generateThumbnailsSynchronously(forOriginal: originalURL)
    }

    /// Sizes actually painted by the grid/list cards. `.tiny` is only used as a
    /// transient first-paint and is generated on demand, so warming skips it.
    private static let displaySizes: [BoxArtThumbnailSize] = [.small, .medium, .large]

    /// Eagerly generate on-disk `te_thumbs` for a batch of ROMs (e.g. right
    /// after a library scan or boxart download) so scrolling never falls back
    /// to the full-original decode path. ROMs whose thumbnails already exist
    /// and are newer than the original are skipped, so re-warming is cheap.
    /// Generation runs on the shared utility queue (concurrency-bounded).
    func warmThumbnails(for roms: [ROM]) {
        let urls = roms.compactMap { rom -> URL? in
            let path = rom.boxArtLocalPath
            guard rom.hasBoxArt, FileManager.default.fileExists(atPath: path.path) else { return nil }
            return path
        }
        for url in urls {
            enqueueGeneration(for: url, sizes: Self.displaySizes)
        }
    }

    nonisolated
    static func generateThumbnailsSynchronously(forOriginal originalURL: URL, sizes: [BoxArtThumbnailSize]? = nil) {
        let sizesToGenerate = sizes ?? BoxArtThumbnailSize.allCases
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

        // Single decode at the largest bucket (.large = 800px). Smaller buckets
        // are downsampled in memory from this one decode via NSBitmapImageRep
        // instead of re-decoding the source file 4x. Halves CPU and peak RSS
        // during the burst of generation that fires when boxart completes
        // downloading for many ROMs in succession.
        let largestMaxPx = max(BoxArtThumbnailSize.large.maxPixelSize,
                               BoxArtThumbnailSize.large.maxPixelHeight)
        let primaryOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(largestMaxPx)
        ]

        guard let primaryCG = CGImageSourceCreateThumbnailAtIndex(source, 0, primaryOptions as CFDictionary) else {
            LoggerService.error(category: "BoxArtThumbnails", "Failed to create primary thumbnail for \(originalURL.lastPathComponent)")
            return
        }

        let primaryNSImage = NSImage(cgImage: primaryCG, size: NSSize(width: primaryCG.width, height: primaryCG.height))
        guard let primaryTiff = primaryNSImage.tiffRepresentation,
              let primaryRep = NSBitmapImageRep(data: primaryTiff) else {
            LoggerService.error(category: "BoxArtThumbnails", "Primary rep construction failed for \(originalURL.lastPathComponent)")
            return
        }

        for size in sizesToGenerate {
            let thumbURL = Self.thumbnailURL(for: originalURL, size: size)

            if FileManager.default.fileExists(atPath: thumbURL.path) {
                if let thumbMod = try? FileManager.default.attributesOfItem(atPath: thumbURL.path)[.modificationDate] as? Date,
                   let origMod = try? FileManager.default.attributesOfItem(atPath: originalURL.path)[.modificationDate] as? Date,
                   thumbMod >= origMod {
                    continue
                }
            }

            let targetMaxPx = max(size.maxPixelSize, size.maxPixelHeight)

            // Reuse the single primary decode for all sizes. For .large we ship
            // it as-is; for smaller buckets we downsample via a proportionally
            // scaled NSBitmapImageRep — one Operation per bucket is cheap
            // compared to a fresh CGImageSourceThumbnailAtIndex call.
            guard let rep = repForSize(primaryRep, targetMaxPx: targetMaxPx) else {
                LoggerService.error(category: "BoxArtThumbnails", "Downsample rep failed for \(originalURL.lastPathComponent) size \(size.rawValue)")
                continue
            }
            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: size.jpegQuality]) else {
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

    /// Downsamples an existing NSBitmapImageRep to fit within targetMaxPx on
    /// its longest side. Returns nil if the source is already smaller than the
    /// target (caller should reuse the source rep directly in that case).
    private nonisolated static func repForSize(_ source: NSBitmapImageRep, targetMaxPx: CGFloat) -> NSBitmapImageRep? {
        let srcW = source.pixelsWide
        let srcH = source.pixelsHigh
        let longestSide = CGFloat(max(srcW, srcH))
        if longestSide <= targetMaxPx {
            // Already small enough — reuse source directly.
            return source
        }
        let scale = targetMaxPx / longestSide
        let destW = max(1, Int((CGFloat(srcW) * scale).rounded()))
        let destH = max(1, Int((CGFloat(srcH) * scale).rounded()))
        guard let cgImage = source.cgImage else { return nil }
        let targetRect = CGRect(x: 0, y: 0, width: destW, height: destH)
        guard let destRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: destW,
            pixelsHigh: destH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        guard let context = NSGraphicsContext(bitmapImageRep: destRep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The cgImage is anchored bottom-left by default; flip vertically.
        context.cgContext.translateBy(x: 0, y: CGFloat(destH))
        context.cgContext.scaleBy(x: 1, y: -1)
        context.cgContext.draw(cgImage, in: targetRect)
        NSGraphicsContext.restoreGraphicsState()
        return destRep
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
            if let self = self {
                Task { @MainActor in
                    self.processDirectoryChanges(at: directory)
                }
            }
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

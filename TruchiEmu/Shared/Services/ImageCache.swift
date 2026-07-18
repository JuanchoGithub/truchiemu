import AppKit
import Foundation
import ImageIO

// MARK: - Image Cache

// Image cache with cost-based eviction so memory stays bounded.
// Uses NSCache with proper cost values for automatic eviction under pressure.
// Separate caches for thumbnails (small, many) and full images (large, few).
// Supports pre-generated on-disk thumbnails in .te_thumbs/ directories for fast loading.
actor ImageCache {
    static let shared = ImageCache()

    // Thumbnails: grid/list views — small images, many entries.
    // NSCache is thread-safe, so this can be accessed from both the actor
    // isolation domain and the nonisolated thumbnailSync(...) fast path.
    nonisolated(unsafe) private var thumbnailCache = NSCache<NSString, NSImage>()

    // Full images: detail views, zoom — larger images, fewer entries
    private var imageCache = NSCache<NSString, NSImage>()

    // Tracks in-flight loading tasks to prevent duplicate loads for the same key.
    private var inFlight = [String: Task<NSImage?, Never>]()

    // Limits concurrent image decoding to prevent task explosion and memory pressure crashes.
    private var activeLoadCount = 0
    private let maxConcurrentLoads = 12

    // MARK: - Cost Calculation

    nonisolated private func cost(of image: NSImage) -> Int {
        let rep = image.representations.first
        let width = CGFloat(rep?.pixelsWide ?? Int(image.size.width))
        let height = CGFloat(rep?.pixelsHigh ?? Int(image.size.height))
        return Int(width * height * 4)
    }

    // MARK: - Thumbnail API (grid/list views)

    func thumbnail(for url: URL, maxWidth: CGFloat = 400, maxHeight: CGFloat = 600) async -> NSImage? {
        let key = thumbKey(url)

        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let maxPx = max(maxWidth, maxHeight)
            let img = await self.loadAndDecode(at: url, maxPixelSize: maxPx)
            if let img = img {
                let c = cost(of: img)
                self.thumbnailCache.setObject(img, forKey: key as NSString, cost: c)
            }
            self.inFlight.removeValue(forKey: key)
            return img
        }

        inFlight[key] = task
        return await task.value
    }

    // Size-aware thumbnail loading: checks for pre-generated thumbnail on disk first.
    // If no disk thumbnail exists, loads the full boxart immediately for display,
    // then kicks off background thumbnail generation so the next load is fast.
    func thumbnail(for url: URL, preferredSize: BoxArtThumbnailSize) async -> NSImage? {
        let sizeKey = thumbKey(url, size: preferredSize)

        if let cached = thumbnailCache.object(forKey: sizeKey as NSString) {
            return cached
        }

        if let existing = inFlight[sizeKey] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let thumbURL = BoxArtThumbnailService.thumbnailURL(for: url, size: preferredSize)
            var img: NSImage?

            if FileManager.default.fileExists(atPath: thumbURL.path) {
                img = await self.loadFromFile(at: thumbURL)
            }

            if img == nil {
                img = await self.loadAndDecode(at: url, maxPixelSize: preferredSize.maxPixelSize)

                if img != nil {
                    BoxArtThumbnailService.scheduleGeneration(forOriginal: url)
                }
            }

            if let img = img {
                let c = cost(of: img)
                self.thumbnailCache.setObject(img, forKey: sizeKey as NSString, cost: c)
            }
            self.inFlight.removeValue(forKey: sizeKey)
            return img
        }

        inFlight[sizeKey] = task
        return await task.value
    }

    func cacheThumbnail(_ image: NSImage, for url: URL) {
        let key = thumbKey(url)
        let c = cost(of: image)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: c)
    }

    /// Synchronous fast path used by recycled NSCollectionViewItems to pre-paint
    /// before the SwiftUI .task fires, eliminating placeholder flicker on scroll.
    /// Order: in-memory NSCache first (instant), then a guarded disk read of the
    /// pre-generated `te_thumbs` JPEG (sub-millisecond when the file is already
    /// in the OS page cache, which it is once warmed). The `fileExists` guard
    /// keeps the cold/uncached case cheap — only ROMs with a real thumb file pay
    /// the decode, and that decode runs on the main thread but is tiny (400–800px
    /// JPEG). This is what lets warmed libraries paint boxart with zero flash
    /// and zero async round-trip, independent of NSCache residency.
    nonisolated func thumbnailSync(for url: URL, preferredSize: BoxArtThumbnailSize) -> NSImage? {
        let sizeKey = "thumb:\(preferredSize.rawValue):\(url.path)" as NSString
        if let cached = thumbnailCache.object(forKey: sizeKey) {
            return cached
        }
        // Fall back to any cached size — a slightly wrong size is better than nil.
        for size in BoxArtThumbnailSize.allCases where size != preferredSize {
            let altKey = "thumb:\(size.rawValue):\(url.path)" as NSString
            if let cached = thumbnailCache.object(forKey: altKey) {
                return cached
            }
        }
        // Cache miss: read the pre-generated thumb from disk. Guarded by
        // fileExists so we only touch disk for ROMs that actually have a thumb.
        let thumbURL = BoxArtThumbnailService.thumbnailURL(for: url, size: preferredSize)
        if FileManager.default.fileExists(atPath: thumbURL.path),
           let source = CGImageSourceCreateWithURL(thumbURL as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            let img = NSImage(cgImage: cgImage, size: .zero)
            thumbnailCache.setObject(img, forKey: sizeKey, cost: cost(of: img))
            return img
        }
        // Last-resort fallback: decode the original boxart synchronously so a
        // recycled cell never paints the placeholder/stock gradient while the
        // async path catches up. This only fires when te_thumbs hasn't been
        // generated yet (cold miss); once decoded it's cached. A single full
        // decode on the main thread is cheap and far better than the flash.
        guard FileManager.default.fileExists(atPath: url.path),
              let origSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let origCG = CGImageSourceCreateThumbnailAtIndex(origSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(preferredSize.maxPixelSize)
              ] as CFDictionary) else {
            return nil
        }
        let origImg = NSImage(cgImage: origCG, size: .zero)
        thumbnailCache.setObject(origImg, forKey: sizeKey, cost: cost(of: origImg))
        return origImg
    }

    func removeThumbnail(for url: URL) {
        let key = thumbKey(url)
        thumbnailCache.removeObject(forKey: key as NSString)
        inFlight.removeValue(forKey: key)
        for size in BoxArtThumbnailSize.allCases {
            let sizeKey = thumbKey(url, size: size)
            thumbnailCache.removeObject(forKey: sizeKey as NSString)
            inFlight.removeValue(forKey: sizeKey)
        }
    }

    // MARK: - Full Image API (detail views)

    // Get an image from cache, or load it from disk asynchronously.
    // Capped at 1024px max dimension for detail view display.
    func image(for url: URL) async -> NSImage? {
        let key = imageKey(url)

        if let cached = imageCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let img = await self.loadAndDecode(at: url, maxPixelSize: 1024)
            if let img = img {
                let c = self.cost(of: img)
                self.imageCache.setObject(img, forKey: key as NSString, cost: c)
            }
            self.inFlight.removeValue(forKey: key)
            return img
        }

        inFlight[key] = task
        return await task.value
    }

    func cacheImage(_ image: NSImage, for url: URL) {
        let key = imageKey(url)
        let c = cost(of: image)
        imageCache.setObject(image, forKey: key as NSString, cost: c)
    }

    func removeImage(for url: URL) {
        let key = imageKey(url)
        let fullKey = fullResKey(url)
        imageCache.removeObject(forKey: key as NSString)
        imageCache.removeObject(forKey: fullKey as NSString)
        inFlight.removeValue(forKey: key)
        inFlight.removeValue(forKey: fullKey)
    }

    // MARK: - Full Resolution API (zoom/fullscreen)

    // Load the original image at full resolution with no downscaling.
    // Stored in the imageCache alongside capped images; high cost means
    // NSCache evicts these first under memory pressure.
    func fullResolutionImage(for url: URL) async -> NSImage? {
        let key = fullResKey(url)

        if let cached = imageCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let img = await self.loadAndDecode(at: url, maxPixelSize: nil)
            if let img = img {
                let c = self.cost(of: img)
                self.imageCache.setObject(img, forKey: key as NSString, cost: c)
            }
            self.inFlight.removeValue(forKey: key)
            return img
        }

        inFlight[key] = task
        return await task.value
    }

    // MARK: - Decode and Cache (used by preloader)

    // Decodes an image at the given max size and stores it as a thumbnail.
    func decodedImage(for url: URL, maxWidth: CGFloat = 0, maxHeight: CGFloat = 0) async -> NSImage? {
        let maxPx: CGFloat?
        if maxWidth > 0 || maxHeight > 0 {
            maxPx = max(maxWidth, maxHeight)
        } else {
            maxPx = nil
        }
        let img = await loadAndDecode(at: url, maxPixelSize: maxPx)
        if let img = img {
            cacheThumbnail(img, for: url)
        }
        return img
    }

    // MARK: - Internal Loading Logic

    // Fast path: load a pre-generated JPEG from disk (no downscaling needed).
    // Uses CGImageSource with ShouldCacheImmediately so the JPEG decode happens
    // off the main thread, avoiding main-thread stalls when SwiftUI renders the image.
    private func loadFromFile(at url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }

    // Loads and decodes an image using CGImageSource for stability and efficiency.
    // maxPixelSize controls the maximum dimension; nil means full resolution.
    private func loadAndDecode(at url: URL, maxPixelSize: CGFloat?) async -> NSImage? {
        while activeLoadCount >= maxConcurrentLoads {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        activeLoadCount += 1
        defer { activeLoadCount -= 1 }

        if Task.isCancelled { return nil }

        let requestedMaxPx = maxPixelSize

        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }

            var thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]

            if let maxPx = requestedMaxPx {
                thumbOptions[kCGImageSourceThumbnailMaxPixelSize] = Int(maxPx)
            } else {
                thumbOptions[kCGImageSourceThumbnailMaxPixelSize] = 100_000
            }

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                return nil
            }

            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }

    // MARK: - Cache Management

    func clear() {
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        inFlight.removeAll()
    }

    // MARK: - Key helpers

    private func thumbKey(_ url: URL) -> String {
        "thumb:\(url.path)"
    }

    private func thumbKey(_ url: URL, size: BoxArtThumbnailSize) -> String {
        "thumb:\(size.rawValue):\(url.path)"
    }

    private func imageKey(_ url: URL) -> String {
        "img:\(url.path)"
    }

    private func fullResKey(_ url: URL) -> String {
        "full:\(url.path)"
    }

    init() {
        // Thumbnail cache: bounded by both count (2500) and total bytes (384MB).
        // Decoded thumbnails range ~120KB (.tiny) to ~2.5MB (.large). Without a
        // cost limit, 2500 large thumbs could hold ~6GB; the 384MB cap lets NSCache
        // evict the largest entries under pressure before system OOM intervenes.
        // Thumbnail cache: 700MB / 5000 entries. Bounded so NSCache still evicts
        // under memory pressure. Cache misses during scroll are covered by the
        // disk-reading thumbnailSync fast path (reads the warmed te_thumbs JPEG,
        // sub-ms from page cache), so we don't need to keep the whole library
        // resident to avoid flashes.
        thumbnailCache.countLimit = 5000
        thumbnailCache.totalCostLimit = 700 * 1024 * 1024

        // Full image cache: 500 items / 256MB — detail/zoom images, bounded so
        // the large entries evict before they compete with the working set.
        imageCache.countLimit = 500
        imageCache.totalCostLimit = 256 * 1024 * 1024
    }
}

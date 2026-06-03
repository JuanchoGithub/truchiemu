import AppKit
import Foundation
import ImageIO

// MARK: - Image Cache

// Image cache with cost-based eviction so memory stays bounded.
// Uses NSCache with proper cost values for automatic eviction under pressure.
// Separate caches for thumbnails (small, many) and full images (large, few).
actor ImageCache {
    static let shared = ImageCache()

    // Thumbnails: grid/list views — small images, many entries
    private var thumbnailCache = NSCache<NSString, NSImage>()

    // Full images: detail views, zoom — larger images, fewer entries
    private var imageCache = NSCache<NSString, NSImage>()

    // Tracks in-flight loading tasks to prevent duplicate loads for the same key.
    private var inFlight = [String: Task<NSImage?, Never>]()

    // Limits concurrent image decoding to prevent task explosion and memory pressure crashes.
    private var activeLoadCount = 0
    private let maxConcurrentLoads = 12

    // MARK: - Cost Calculation

    private func cost(of image: NSImage) -> Int {
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

    func cacheThumbnail(_ image: NSImage, for url: URL) {
        let key = thumbKey(url)
        let c = cost(of: image)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: c)
    }

    func removeThumbnail(for url: URL) {
        let key = thumbKey(url)
        thumbnailCache.removeObject(forKey: key as NSString)
        inFlight.removeValue(forKey: key)
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
                // Full resolution: set a very large max pixel size so
                // CGImageSourceCreateThumbnailAtIndex returns the full image
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

    private func imageKey(_ url: URL) -> String {
        "img:\(url.path)"
    }

    private func fullResKey(_ url: URL) -> String {
        "full:\(url.path)"
    }

    init() {
        // Thumbnail cache: 100MB, 500 items (small images for grid views)
        thumbnailCache.totalCostLimit = 100 * 1024 * 1024
        thumbnailCache.countLimit = 500

        // Full image cache: 400MB, 300 items (larger images for detail/zoom)
        imageCache.totalCostLimit = 400 * 1024 * 1024
        imageCache.countLimit = 300
    }
}

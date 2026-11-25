import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
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
    // isolation domain and the nonisolated cache-only fast paths.
    nonisolated(unsafe) private var thumbnailCache = NSCache<NSString, NSImage>()

    // Full images: detail views, zoom — larger images, fewer entries
    private var imageCache = NSCache<NSString, NSImage>()

    // Tracks in-flight loading tasks to prevent duplicate loads for the same key.
    // The token lets an old task remove only its own dictionary entry.
    private struct InFlightEntry {
        let task: Task<NSImage?, Never>
        let token: UUID
    }
    private var inFlight = [String: InFlightEntry]()

    // Invalidates async work for one cache key without affecting other keys.
    private var keyVersions = [String: UInt64]()

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
            return await existing.task.value
        }

        let version = currentVersion(for: key)
        let token = UUID()
        let task = Task<NSImage?, Never> {
            let maxPx = max(maxWidth, maxHeight)
            let img = await self.loadAndDecode(at: url, maxPixelSize: maxPx)
            guard self.isCurrentVersion(key, version: version), !Task.isCancelled else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }
            if let img = img {
                let c = cost(of: img)
                self.thumbnailCache.setObject(img, forKey: key as NSString, cost: c)
            }
            self.removeInFlightIfCurrent(key, token: token)
            return img
        }

        inFlight[key] = InFlightEntry(task: task, token: token)
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
            return await existing.task.value
        }

        let version = currentVersion(for: sizeKey)
        let token = UUID()
        let task = Task<NSImage?, Never> {
            let thumbURL = BoxArtThumbnailService.thumbnailURL(for: url, size: preferredSize)
            var img: NSImage?
            var loadedFromOriginal = false

            if FileManager.default.fileExists(atPath: thumbURL.path) {
                img = await self.loadFromFile(at: thumbURL)
            }

            if img == nil {
                img = await self.loadAndDecode(at: url, maxPixelSize: preferredSize.maxPixelSize)
                loadedFromOriginal = img != nil
            }

            guard self.isCurrentVersion(sizeKey, version: version), !Task.isCancelled else {
                self.removeInFlightIfCurrent(sizeKey, token: token)
                return nil
            }

            if loadedFromOriginal {
                BoxArtThumbnailService.scheduleGeneration(forOriginal: url)
            }

            if let img = img {
                let c = cost(of: img)
                self.thumbnailCache.setObject(img, forKey: sizeKey as NSString, cost: c)
            }
            self.removeInFlightIfCurrent(sizeKey, token: token)
            return img
        }

        inFlight[sizeKey] = InFlightEntry(task: task, token: token)
        return await task.value
    }

    func cacheThumbnail(_ image: NSImage, for url: URL) {
        let key = thumbKey(url)
        let c = cost(of: image)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: c)
    }

    /// Compatibility wrapper for callers that need a synchronous thumbnail.
    /// It only reads the in-memory cache. It never reads the disk and never
    /// decodes the original image on the main thread.
    nonisolated func thumbnailSync(for url: URL, preferredSize: BoxArtThumbnailSize) -> NSImage? {
        let auditOnMain = Thread.isMainThread
        let auditStart = auditOnMain ? DispatchTime.now().uptimeNanoseconds : 0
        defer {
            if auditOnMain {
                ScrollPerfCounters.thumbnailSyncCalls += 1
                ScrollPerfCounters.thumbnailSyncMainThreadNs &+= Int64(DispatchTime.now().uptimeNanoseconds &- auditStart)
            }
        }
        return thumbnailCachedOrPregen(for: url, preferredSize: preferredSize)
    }

    /// Synchronous fast path for recycled cells, used to pre-paint boxart on
    /// scroll without flickering the placeholder. This consults ONLY the
    /// in-memory NSCache — it performs ZERO disk I/O and ZERO decode on the
    /// main thread, so it can never stall scrolling. The prefetcher warms
    /// NSCache for cells near the viewport, so during normal scrolling the
    /// thumb is already resident and the card paints instantly (no grey).
    /// Cells whose thumb is not yet cached fall back to nil and are filled by
    /// the async `.task`, which is the same behaviour the standard grid relies
    /// on for cold cells. Doing a synchronous disk read here (even the cheap
    /// pre-generated `te_thumbs` JPEG) was measured to pile seconds of
    /// main-thread blocking into a single scroll burst once you scroll into
    /// colder regions, so it is deliberately avoided.
    nonisolated func thumbnailCachedOrPregen(for url: URL, preferredSize: BoxArtThumbnailSize) -> NSImage? {
        let sizeKey = "thumb:\(preferredSize.rawValue):\(url.path)" as NSString
        if let cached = thumbnailCache.object(forKey: sizeKey) {
            return cached
        }
        for size in BoxArtThumbnailSize.allCases where size != preferredSize {
            let altKey = "thumb:\(size.rawValue):\(url.path)" as NSString
            if let cached = thumbnailCache.object(forKey: altKey) {
                return cached
            }
        }
        return nil
    }

    /// Synchronous "cache or pre-generated thumb" load for callers that must
    /// paint art on the very first frame (the TV-mode hero cover). It uses the
    /// in-memory thumbnail cache and the pre-generated `te_thumbs` JPEG, so the
    /// cost is one `fileExists` probe plus a small JPEG decode (measured 1–3 ms
    /// for `.large` once ImageIO is warm). It never decodes the original image.
    /// A missing pre-gen returns `nil` cheaply and the caller stays on the
    /// async path.
    ///
    /// Order: exact-size memory hit, then the pre-gen file at the requested
    /// size (so a large hero never shows a 400 px grid thumb stretched), then
    /// any other cached size, which is still better than a placeholder.
    nonisolated func thumbnailSyncPregen(for url: URL, preferredSize: BoxArtThumbnailSize) -> NSImage? {
        let sizeKey = "thumb:\(preferredSize.rawValue):\(url.path)" as NSString
        if let cached = thumbnailCache.object(forKey: sizeKey) {
            return cached
        }
        let thumbURL = BoxArtThumbnailService.thumbnailURL(for: url, size: preferredSize)
        let sourceModificationDate = Self.fileModificationDate(at: url)
        let thumbnailModificationDate = Self.fileModificationDate(at: thumbURL)
        if FileManager.default.fileExists(atPath: thumbURL.path),
           let source = CGImageSourceCreateWithURL(thumbURL as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            let image = NSImage(cgImage: cgImage, size: .zero)
            if Self.fileUnchanged(at: url, since: sourceModificationDate),
               Self.fileUnchanged(at: thumbURL, since: thumbnailModificationDate) {
                thumbnailCache.setObject(image, forKey: sizeKey, cost: cost(of: image))
            }
            return image
        }
        return thumbnailCachedOrPregen(for: url, preferredSize: preferredSize)
    }

    func removeThumbnail(for url: URL) {
        var keys = [thumbKey(url)]
        for size in BoxArtThumbnailSize.allCases {
            keys.append(thumbKey(url, size: size))
            keys.append(blurredFillKey(url, size: size))
        }
        keys.append(blurredBackdropKey(url))

        for key in keys {
            thumbnailCache.removeObject(forKey: key as NSString)
            invalidate(key)
        }
    }

    // MARK: - Blurred Fill (BoxArtDisplayMode.fillBlurred)

    // Pre-rasterized blurred background for the fill-blurred display mode.
    // SwiftUI's `.blur` is recomputed every frame for every visible cell, which
    // stutters during fast scroll. Here we apply a Gaussian blur with CoreImage
    // once per cover, off the main thread, and cache the resulting bitmap. The
    // grid cell then displays an already-blurred NSImage with no per-frame GPU
    // filter cost.
    //
    // The blurred bitmap is sized to a fixed render target (256×320 square-ish)
    // rather than the live cell size, because the blur radius is a single fixed
    // value and the cell already re-stretches the bitmap with .scaledToFill. A
    // small fixed render target keeps memory cost predictable (~310 KB per entry
    // and bounded by the thumbnail NSCache cost limit).
    func blurredFillImage(for url: URL, size: BoxArtThumbnailSize) async -> NSImage? {
        let key = blurredFillKey(url, size: size)

        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.task.value
        }

        let version = currentVersion(for: key)
        let token = UUID()
        let task = Task<NSImage?, Never> {
            // Reuse the already-decoded thumbnail as the blur source — no second
            // disk read. If the base thumbnail isn't cached yet, fall back to the
            // standard thumbnail() load so we don't bypass the inFlight/decode
            // path; the next call will hit the cache.
            let base: NSImage?
            if let cached = thumbnailCache.object(forKey: thumbKey(url, size: size) as NSString) {
                base = cached
            } else {
                base = await self.thumbnail(for: url, preferredSize: size)
            }
            guard let source = base, let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }

            let blurred = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let ciSource = CIImage(cgImage: cg)
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = ciSource
                // Radius tuned to match the look of the previous on-the-fly
                // SwiftUI blur (which used ~0.08 * 280 ~= 22). Lower it slightly
                // (18) because CoreImage's blur is perceptually denser than
                // SwiftUI's CALayer blur at the same numeric radius.
                filter.radius = 18

                // Background fills get composited over black by the SwiftUI cell
                // (Color.black at the bottom of the ZStack). Compositing the blur
                // over black here too avoids the white edge fringing that CIFilter
                // produces when the source has alpha.
                guard let output = filter.outputImage else { return nil }
                let blackBackground = CIImage(color: CIColor.black).cropped(to: output.extent)
                let composited = output.composited(over: blackBackground)

                let context = CIContext(options: [.useSoftwareRenderer: false])
                guard let cgOut = context.createCGImage(composited, from: ciSource.extent) else { return nil }
                return NSImage(cgImage: cgOut, size: .zero)
            }.value

            guard self.isCurrentVersion(key, version: version), !Task.isCancelled else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }
            if let blurred {
                let c = self.cost(of: blurred)
                self.thumbnailCache.setObject(blurred, forKey: key as NSString, cost: c)
            }
            self.removeInFlightIfCurrent(key, token: token)
            return blurred
        }

        inFlight[key] = InFlightEntry(task: task, token: token)
        return await task.value
    }

    /// Synchronous fast path for the blurred-fill bitmap. Used by recycled
    /// collection-view cells to avoid flashing the unblurred thumbnail during
    /// scroll before the async `blurredFillImage` task completes. Returns nil
    /// on a cache miss rather than touching disk — the SwiftUI cell falls back
    /// to the on-the-fly `.blur` for that one frame and the async task fills
    /// the cache for next time.
    nonisolated func blurredFillImageSync(for url: URL, size: BoxArtThumbnailSize) -> NSImage? {
        let key = blurredFillKey(url, size: size) as NSString
        return thumbnailCache.object(forKey: key)
    }

    // MARK: - TV Backdrop Blur

    // Pre-rasterized full-window backdrop for TV mode's `.boxart` theme. Same
    // rationale as `blurredFillImage`: a live `.blur` on a full-screen image
    // is re-evaluated by the window server every time the image swaps, and
    // under load the first frame(s) composite the RAW image before the
    // filtered result is ready — a full-strength boxart flash over the UI.
    // Here the gaussian blur and saturation boost are baked in once per cover
    // and cached, so the view displays a plain bitmap with zero live filters.
    //
    // Radius sizing: the bitmap is stretched to fill the window, and the old
    // live blur was `58 × TVModeMetrics.scale` screen-points with
    // `scale = screenHeight / 982`, which works out to ~0.059 × the bitmap's
    // fill dimension. Nudged down to 0.05 because CoreImage's blur is
    // perceptually denser than the CALayer blur at the same numeric radius
    // (same correction as `blurredFillImage`'s 18-vs-22 note).
    func blurredBackdropImage(for url: URL) async -> NSImage? {
        let key = blurredBackdropKey(url)

        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.task.value
        }

        let version = currentVersion(for: key)
        let token = UUID()
        let task = Task<NSImage?, Never> {
            // Reuse the already-decoded .large thumbnail as the blur source —
            // no second disk read. Same fallback as `blurredFillImage`.
            let base: NSImage?
            if let cached = thumbnailCache.object(forKey: thumbKey(url, size: .large) as NSString) {
                base = cached
            } else {
                base = await self.thumbnail(for: url, preferredSize: .large)
            }
            guard let source = base, let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }

            let blurred = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let ciSource = CIImage(cgImage: cg)
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = ciSource
                let maxDim = max(ciSource.extent.width, ciSource.extent.height)
                filter.radius = Float(maxDim * 0.05)

                guard let output = filter.outputImage else { return nil }
                // Bake in the saturation boost the backdrop used to apply as a
                // live `.saturation(1.4)` filter.
                let saturate = CIFilter.colorControls()
                saturate.inputImage = output
                saturate.saturation = 1.4
                guard let saturated = saturate.outputImage else { return nil }

                // Composite over black to avoid the white edge fringing
                // CIFilter produces when the source has alpha; the TV backdrop
                // sits over a dark scrim, so this matches the on-screen
                // treatment too.
                let blackBackground = CIImage(color: CIColor.black).cropped(to: ciSource.extent)
                let composited = saturated.composited(over: blackBackground)

                let context = CIContext(options: [.useSoftwareRenderer: false])
                guard let cgOut = context.createCGImage(composited, from: ciSource.extent) else { return nil }
                return NSImage(cgImage: cgOut, size: .zero)
            }.value

            guard self.isCurrentVersion(key, version: version), !Task.isCancelled else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }
            if let blurred {
                let c = self.cost(of: blurred)
                self.thumbnailCache.setObject(blurred, forKey: key as NSString, cost: c)
            }
            self.removeInFlightIfCurrent(key, token: token)
            return blurred
        }

        inFlight[key] = InFlightEntry(task: task, token: token)
        return await task.value
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
            return await existing.task.value
        }

        let version = currentVersion(for: key)
        let token = UUID()
        let task = Task<NSImage?, Never> {
            let img = await self.loadAndDecode(at: url, maxPixelSize: 1024)
            guard self.isCurrentVersion(key, version: version), !Task.isCancelled else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }
            if let img = img {
                let c = self.cost(of: img)
                self.imageCache.setObject(img, forKey: key as NSString, cost: c)
            }
            self.removeInFlightIfCurrent(key, token: token)
            return img
        }

        inFlight[key] = InFlightEntry(task: task, token: token)
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
        invalidate(key)
        invalidate(fullKey)
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
            return await existing.task.value
        }

        let version = currentVersion(for: key)
        let token = UUID()
        let task = Task<NSImage?, Never> {
            let img = await self.loadAndDecode(at: url, maxPixelSize: nil)
            guard self.isCurrentVersion(key, version: version), !Task.isCancelled else {
                self.removeInFlightIfCurrent(key, token: token)
                return nil
            }
            if let img = img {
                let c = self.cost(of: img)
                self.imageCache.setObject(img, forKey: key as NSString, cost: c)
            }
            self.removeInFlightIfCurrent(key, token: token)
            return img
        }

        inFlight[key] = InFlightEntry(task: task, token: token)
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
        let key = thumbKey(url)
        let version = currentVersion(for: key)
        let img = await loadAndDecode(at: url, maxPixelSize: maxPx)
        guard isCurrentVersion(key, version: version), !Task.isCancelled else {
            return nil
        }
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

    private func currentVersion(for key: String) -> UInt64 {
        keyVersions[key] ?? 0
    }

    private func isCurrentVersion(_ key: String, version: UInt64) -> Bool {
        currentVersion(for: key) == version
    }

    private func invalidate(_ key: String) {
        let nextVersion = (keyVersions[key] ?? 0) &+ 1
        keyVersions[key] = nextVersion
        if let entry = inFlight.removeValue(forKey: key) {
            entry.task.cancel()
        }
    }

    private func removeInFlightIfCurrent(_ key: String, token: UUID) {
        guard inFlight[key]?.token == token else { return }
        inFlight.removeValue(forKey: key)
    }

    nonisolated private static func fileModificationDate(at url: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else {
            return nil
        }
        return date
    }

    nonisolated private static func fileUnchanged(at url: URL, since date: Date?) -> Bool {
        guard let date,
              let currentDate = fileModificationDate(at: url) else {
            return false
        }
        return currentDate == date
    }

    func clear() {
        imageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        for key in Array(inFlight.keys) {
            invalidate(key)
        }
    }

    // MARK: - Key helpers

    private func thumbKey(_ url: URL) -> String {
        "thumb:\(url.path)"
    }

    private func thumbKey(_ url: URL, size: BoxArtThumbnailSize) -> String {
        "thumb:\(size.rawValue):\(url.path)"
    }

    nonisolated private func blurredFillKey(_ url: URL, size: BoxArtThumbnailSize) -> String {
        "blurfill:\(size.rawValue):\(url.path)"
    }

    private func blurredBackdropKey(_ url: URL) -> String {
        "blurbg:\(url.path)"
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
        // under memory pressure. Cache misses are filled by the async image
        // loader, so the whole library does not need to remain resident.
        thumbnailCache.countLimit = 5000
        thumbnailCache.totalCostLimit = 700 * 1024 * 1024

        // Full image cache: 500 items / 256MB — detail/zoom images, bounded so
        // the large entries evict before they compete with the working set.
        imageCache.countLimit = 500
        imageCache.totalCostLimit = 256 * 1024 * 1024
    }
}

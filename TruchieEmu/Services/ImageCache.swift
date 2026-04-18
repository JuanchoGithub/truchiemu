import AppKit
import Foundation
import ImageIO

// MARK: - Image Cache

// Simple, robust image cache for box art.
// Uses NSCache for automatic memory management and limits concurrency to prevent memory pressure crashes.
actor ImageCache {
    static let shared = ImageCache()
    
    private var cache = NSCache<NSURL, NSImage>()
    
    // Tracks in-flight loading tasks to prevent duplicate loads for the same URL.
    private var inFlight = [URL: Task<NSImage?, Never>]()
    
    // Limits concurrent image decoding to prevent task explosion and memory pressure crashes.
    private var activeLoadCount = 0
    private let maxConcurrentLoads = 12
    
    // MARK: - Public API
    
    // Get an image from cache, or load it from disk asynchronously.
    func image(for url: URL) async -> NSImage? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Return existing in-flight task if available
        if let existing = inFlight[url] {
            return await existing.value
        }
        
        let task = Task {
            let img = await self.loadAndDecode(at: url)
            if let img = img {
                self.cache.setObject(img, forKey: url as NSURL)
            }
            // Clear from in-flight on completion
            self.inFlight.removeValue(forKey: url)
            return img
        }
        
        inFlight[url] = task
        return await task.value
    }
    
    // Get a downscaled thumbnail for grid/list views.
    func thumbnail(for url: URL, maxWidth: CGFloat = 400, maxHeight: CGFloat = 600) async -> NSImage? {
        return await image(for: url)
    }
    
    // Decode and cache an image (used by preloader).
    func decodedImage(for url: URL, maxWidth: CGFloat = 0, maxHeight: CGFloat = 0) async -> NSImage? {
        return await image(for: url)
    }
    
    // MARK: - Internal Loading Logic
    
    // Loads and decodes an image using CGImageSource for stability and efficiency.
    private func loadAndDecode(at url: URL) async -> NSImage? {
        // Wait if too many loads are active (primitive semaphore)
        while activeLoadCount >= maxConcurrentLoads {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        activeLoadCount += 1
        defer { activeLoadCount -= 1 }
        
        if Task.isCancelled { return nil }
        
        // Use ImageIO for more robust loading than NSImage(contentsOf:)
        // This is much harder to crash with corrupted files.
        return await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldAllowFloat: true
            ]
            
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            
            // For box art, we often want a reasonable thumbnail size immediately
            // to save memory if the original is huge.
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024, // Safety limit
                kCGImageSourceShouldCacheImmediately: true
            ]
            
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                return nil
            }
            
            return NSImage(cgImage: cgImage, size: .zero) // size zero matches CGImage dimensions
        }.value
    }
    
    // MARK: - Cache Management
    
    func cacheImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
    
    func clear() {
        cache.removeAllObjects()
        inFlight.removeAll()
    }
    
    func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
        inFlight.removeValue(forKey: url)
    }
    
    func cacheThumbnail(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
    
    func removeThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
    
    init() {
        // 500MB limit for box art images
        cache.totalCostLimit = 500 * 1024 * 1024
        cache.countLimit = 5000
    }
}
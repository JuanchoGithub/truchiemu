import AppKit
import Foundation

// MARK: - Image Cache

/// Simple, fast image cache for box art.
/// Uses NSCache for automatic memory management with count limits.
actor ImageCache {
    static let shared = ImageCache()
    
    private var cache = NSCache<NSURL, NSImage>()
    
    // MARK: - Public API
    
    /// Get an image from cache, or load it from disk synchronously.
    /// This is a drop-in replacement for `NSImage(contentsOf:)` with caching.
    func image(for url: URL) async -> NSImage? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Load from disk on background thread
        let result = try? await Task.detached {
            NSImage(contentsOf: url)
        }.value
        
        if let image = result {
            cache.setObject(image, forKey: url as NSURL)
        }
        
        return result
    }
    
    /// Get a downscaled thumbnail for grid/list views.
    /// If no thumbnail exists, loads from cache or disk.
    func thumbnail(for url: URL, maxWidth: CGFloat = 400, maxHeight: CGFloat = 600) async -> NSImage? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Load from disk on background thread
        let result = try? await Task.detached {
            NSImage(contentsOf: url)
        }.value
        
        if let image = result {
            cache.setObject(image, forKey: url as NSURL)
        }
        
        return result
    }
    
    /// Decode and cache an image (used by preloader).
    func decodedImage(for url: URL, maxWidth: CGFloat = 0, maxHeight: CGFloat = 0) async -> NSImage? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Load from disk on background thread
        let result = try? await Task.detached {
            NSImage(contentsOf: url)
        }.value
        
        if let image = result {
            cache.setObject(image, forKey: url as NSURL)
        }
        
        return result
    }
    
    /// Directly cache a pre-loaded NSImage.
    func cacheImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
    
    /// Clear all cached images.
    func clear() {
        cache.removeAllObjects()
    }
    
    /// Remove a specific image from cache.
    func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
    
    /// Cache a thumbnail (alias for cacheImage).
    func cacheThumbnail(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
    
    /// Remove thumbnail from cache (alias for removeImage).
    func removeThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
    
    init() {
        // ~500MB limit for box art images
        cache.totalCostLimit = 500 * 1024 * 1024
        cache.countLimit = 5000
    }
}
import Foundation
import Combine
import AppKit

// Background service that preloads and decodes box art images for efficient grid display.
// Handles pre-warming the image cache, LRU disk cache management, and scoped invalidation.
//
// ## Persistent Thumbnail Cache
// Downscaled thumbnails are serialized to disk in `TruchiEmu/ThumbnailCache`. On each launch,
// these pre-decoded thumbnails are loaded directly into the NSCache so images appear instantly
// without re-reading and rescaling the original box art files.
@MainActor
class BoxArtPreloaderService: ObservableObject {
    static let shared = BoxArtPreloaderService()
    
    // Configuration for the preloader
    struct Config {
        // Maximum persistent thumbnail cache size in bytes (default: 300MB)
        var maxThumbnailCacheBytes: Int
        // Maximum disk cache size in bytes for box art originals (default: 500MB)
        var maxDiskCacheBytes: Int
        // Number of images to preload in background batch
        var preloadBatchSize: Int
        // Delay between preload batches to keep UI responsive
        var preloadBatchDelay: UInt64
        // Target width for downscaled thumbnails (0 = full resolution)
        var thumbnailMaxWidth: CGFloat
        // Target height for downscaled thumbnails (0 = full resolution)
        var thumbnailMaxHeight: CGFloat
        
        static let `default` = Config(
            maxThumbnailCacheBytes: 500 * 1024 * 1024,  // 500MB (increased from 300MB)
            maxDiskCacheBytes: 1000 * 1024 * 1024,  // 1GB (increased from 500MB)
            preloadBatchSize: 50, // increased from 20
            preloadBatchDelay: 10_000_000,  // 10ms (decreased from 50ms)
            thumbnailMaxWidth: 400,
            thumbnailMaxHeight: 600
        )
    }
    
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0
    @Published var preloadCount = 0
    @Published var totalPending = 0
    
    var config: Config = .default
    
    // Cache directory for serialized NSImage thumbnails (persists across launches)
    nonisolated
    static var thumbnailCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TruchiEmu/ThumbnailCache", isDirectory: true)
    }
    
    // MARK: - Thumbnail Persistence
    
    // Save a thumbnail to the persistent disk cache.
    nonisolated
    static func storeThumbnail(_ image: NSImage, for url: URL) {
        let key = url.path
        let cacheDir = Self.thumbnailCacheURL
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let safeKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let fileURL = cacheDir.appendingPathComponent("\(safeKey).tiff")
        guard let tiff = image.tiffRepresentation else { return }
        try? tiff.write(to: fileURL, options: .atomic)
    }
    
    // Load a thumbnail from the persistent disk cache. Returns nil if not cached.
    nonisolated
    static func loadThumbnail(at url: URL) -> NSImage? {
        let key = url.path
        let safeKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let fileURL = Self.thumbnailCacheURL.appendingPathComponent("\(safeKey).tiff")
        guard let data = try? Data(contentsOf: fileURL),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        
        // Ensure pixels are pre-decoded from TIFF to avoid lazy draw jank
        guard let cgImage = rep.cgImage else {
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            return image
        }
        
        return NSImage(cgImage: cgImage, size: rep.size)
    }
    
    // Check if a thumbnail exists for the given URL.
    nonisolated
    static func hasThumbnail(at url: URL) -> Bool {
        let key = url.path
        let safeKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let fileURL = Self.thumbnailCacheURL.appendingPathComponent("\(safeKey).tiff")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Preload ROMs into Image Cache
    
    // Preload box art for a set of ROMs into the decoded image cache.
    // Runs in background batches to avoid blocking the main thread.
    // If a pre-decoded thumbnail exists on disk, it is loaded instantly; otherwise
    // the original image is decoded and downscaled, then saved to the persistent cache.
    func preloadBoxArt(for roms: [ROM]) async {
        guard !roms.isEmpty else { return }
        
        await MainActor.run {
            isPreloading = true
            preloadProgress = 0
            preloadCount = 0
            totalPending = roms.count
        }
        
        let total = roms.count
        var completed = 0
        
        // Process in batches
        let batchSize = config.preloadBatchSize
        var start = 0
        
        while start < total {
            let end = min(start + batchSize, total)
            let batch = Array(roms[start..<end])
            
            // Decode images for this batch in parallel on background threads
            await withTaskGroup(of: (URL, NSImage?).self) { group in
                for rom in batch {
                    guard rom.hasBoxArt else { continue }
                    let artPath = rom.boxArtLocalPath
                    
                    // Check if we have a pre-decoded thumbnail on disk first
                    if let thumb = Self.loadThumbnail(at: artPath) {
                        await ImageCache.shared.cacheThumbnail(thumb, for: artPath)
                        continue
                    }
                    
                    group.addTask {
                        let image = await ImageCache.shared.decodedImage(for: artPath, maxWidth: self.config.thumbnailMaxWidth, maxHeight: self.config.thumbnailMaxHeight)
                        // Save to persistent thumbnail cache for next launch
                        if let img = image {
                            Self.storeThumbnail(img, for: artPath)
                        }
                        return (artPath, image)
                    }
                }
                
                for await (_, image) in group {
                    if image != nil {
                        await MainActor.run { preloadCount += 1 }
                    }
                }
            }
            
            completed = end
            let progress = Double(completed) / Double(total)
            await MainActor.run { preloadProgress = progress }
            
            // Brief delay to yield to main thread
            try? await Task.sleep(nanoseconds: config.preloadBatchDelay)
            
            // Check for cancellation
            if Task.isCancelled { break }
            
            start = end
        }
        
        await MainActor.run {
            isPreloading = false
            LoggerService.info(category: "BoxArtPreloader", "Preload complete: \(preloadCount)/\(total) images cached")
        }
    }
    
    // Invalidate a single image from the cache (scoped invalidation).
    // Call this instead of clear() when a single ROM's box art changes.
    func invalidateImage(for rom: ROM) {
        // Remove full-res from cache
        let url = rom.boxArtLocalPath
        Task {
            await ImageCache.shared.removeImage(for: url)
            await ImageCache.shared.removeThumbnail(for: url)
        }
    }
    
    // Invalidate multiple images from the cache
    func invalidateImages(for roms: [ROM]) {
        for rom in roms {
            invalidateImage(for: rom)
        }
    }
    
    // MARK: - LRU Disk Cache Management
    
    // Check disk cache size and evict least-recently-used files if over limit.
    // Returns number of files evicted.
    func enforceDiskCacheLimit() async -> Int {
        let boxArtCacheURL = Self.diskCacheURL
        guard FileManager.default.fileExists(atPath: boxArtCacheURL.path) else { return 0 }
        
        let totalSize = calculateDirectorySize(at: boxArtCacheURL)
        
        if totalSize <= config.maxDiskCacheBytes {
            return 0
        }
        
        LoggerService.info(category: "BoxArtPreloader", "Disk cache size: \(totalSize / 1024 / 1024)MB exceeds limit of \(config.maxDiskCacheBytes / 1024 / 1024)MB, enforcing LRU eviction")
        
        // Get all files with their modification dates
        let files = getFilesWithDates(in: boxArtCacheURL)
        let sortedByDate = files.sorted { $0.date < $1.date }  // oldest first
        
        var evicted = 0
        var currentSize = totalSize
        
        for file in sortedByDate {
            if currentSize <= config.maxDiskCacheBytes * 8 / 10 {
                // Evict until we're at 80% of the limit
                break
            }
            
            try? FileManager.default.removeItem(at: file.url)
            currentSize -= file.size
            evicted += 1
        }
        
        LoggerService.info(category: "BoxArtPreloader", "Evicted \(evicted) files, freed \(totalSize - currentSize) bytes")
        return evicted
    }
    
    // Touch a file to update its modification date (extends its LRU lifetime).
    func touchFile(at url: URL) {
        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
    
    // MARK: - Disk Cache Info
    
    // Get current disk cache size in bytes
    func diskCacheSizeBytes() -> Int {
        calculateDirectorySize(at: Self.diskCacheURL)
    }
    
    // Get human-readable disk cache size
    var diskCacheSizeFormatted: String {
        let bytes = diskCacheSizeBytes()
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        if bytes < 1024 * 1024 * 1024 { return "\(bytes / 1024 / 1024) MB" }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
    
    // Get file count in disk cache
    func diskCacheFileCount() -> Int {
        let url = Self.diskCacheURL
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return 0 }
        return enumerator.allObjects.count
    }
    
    // MARK: - Clear All Cached Data
    
    // Clear all cached box art from disk and memory.
    func clearAllCache() async {
        // Clear memory cache
        await ImageCache.shared.clear()
        
        // Clear disk cache
        let url = Self.diskCacheURL
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        
        LoggerService.info(category: "BoxArtPreloader", "All box art caches cleared")
    }
    
    // MARK: - Private Helpers
    
    static var diskCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("TruchiEmu/BoxArtCache", isDirectory: true)
    }
    
    nonisolated
    private func calculateDirectorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        
        var totalSize = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
               resourceValues.isDirectory == false {
                totalSize += resourceValues.fileSize ?? 0
            }
        }
        return totalSize
    }
    
    nonisolated
    private struct FileInfo {
        let url: URL
        let date: Date
        let size: Int
    }
    
    nonisolated
    private func getFilesWithDates(in url: URL) -> [FileInfo] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else { return [] }
        
        var files: [FileInfo] = []
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]),
               resourceValues.isDirectory == false {
                let fileSize = resourceValues.fileSize ?? 0
                let modDate = resourceValues.contentModificationDate ?? Date.distantPast
                files.append(FileInfo(url: fileURL, date: modDate, size: fileSize))
            }
        }
        return files
    }
}
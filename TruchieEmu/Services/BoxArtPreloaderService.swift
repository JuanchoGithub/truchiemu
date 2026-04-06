import Foundation
import Combine
import AppKit

/// Background service that preloads and decodes box art images for efficient grid display.
/// Handles pre-warming the image cache, LRU disk cache management, and scoped invalidation.
@MainActor
class BoxArtPreloaderService: ObservableObject {
    static let shared = BoxArtPreloaderService()
    
    /// Configuration for the preloader
    struct Config {
        /// Maximum disk cache size in bytes (default: 500MB)
        var maxDiskCacheBytes: Int
        /// Number of images to preload in background batch
        var preloadBatchSize: Int
        /// Delay between preload batches to keep UI responsive
        var preloadBatchDelay: UInt64
        /// Target width for downscaled thumbnails (0 = full resolution)
        var thumbnailMaxWidth: CGFloat
        /// Target height for downscaled thumbnails (0 = full resolution)
        var thumbnailMaxHeight: CGFloat
        
        static let `default` = Config(
            maxDiskCacheBytes: 500 * 1024 * 1024,  // 500MB
            preloadBatchSize: 20,
            preloadBatchDelay: 50_000_000,  // 50ms
            thumbnailMaxWidth: 400,
            thumbnailMaxHeight: 600
        )
    }
    
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0
    @Published var preloadCount = 0
    @Published var totalPending = 0
    
    var config: Config = .default
    
    // MARK: - Preload ROMs into Image Cache
    
    /// Preload box art for a set of ROMs into the decoded image cache.
    /// Runs in background batches to avoid blocking the main thread.
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
                    guard let artPath = rom.boxArtPath else { continue }
                    group.addTask {
                        let image = await ImageCache.shared.decodedImage(for: artPath, maxWidth: self.config.thumbnailMaxWidth, maxHeight: self.config.thumbnailMaxHeight)
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
    
    /// Invalidate a single image from the cache (scoped invalidation).
    /// Call this instead of clear() when a single ROM's box art changes.
    func invalidateImage(for rom: ROM) {
        // Remove full-res from cache
        if let url = rom.boxArtPath {
            Task {
                await ImageCache.shared.removeImage(for: url)
                await ImageCache.shared.removeThumbnail(for: url)
            }
        }
    }
    
    /// Invalidate multiple images from the cache
    func invalidateImages(for roms: [ROM]) {
        for rom in roms {
            invalidateImage(for: rom)
        }
    }
    
    // MARK: - LRU Disk Cache Management
    
    /// Check disk cache size and evict least-recently-used files if over limit.
    /// Returns number of files evicted.
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
    
    /// Touch a file to update its modification date (extends its LRU lifetime).
    func touchFile(at url: URL) {
        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
    
    // MARK: - Disk Cache Info
    
    /// Get current disk cache size in bytes
    func diskCacheSizeBytes() -> Int {
        calculateDirectorySize(at: Self.diskCacheURL)
    }
    
    /// Get human-readable disk cache size
    var diskCacheSizeFormatted: String {
        let bytes = diskCacheSizeBytes()
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        if bytes < 1024 * 1024 * 1024 { return "\(bytes / 1024 / 1024) MB" }
        return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
    
    /// Get file count in disk cache
    func diskCacheFileCount() -> Int {
        let url = Self.diskCacheURL
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return 0 }
        return enumerator.allObjects.count
    }
    
    // MARK: - Clear All Cached Data
    
    /// Clear all cached box art from disk and memory.
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
        return caches.appendingPathComponent("TruchieEmu/BoxArtCache", isDirectory: true)
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
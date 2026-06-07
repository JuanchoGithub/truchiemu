import Foundation
import SwiftUI

@MainActor
class RABadgeCacheService: ObservableObject {
    static let shared = RABadgeCacheService()
    
    @Published var badgeUpdateToken = UUID()
    
    private let fileManager = FileManager.default
    
    private static let badgeFolder: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("TruchiEmu/RetroAchievements/Badges", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    
    private var badgeFolder: URL { Self.badgeFolder }
    
    private init() {}
    
    /// Returns the local URL for a badge if it exists, otherwise nil.
    nonisolated func localURL(for badgeName: String) -> URL? {
        let fileURL = Self.badgeFolder.appendingPathComponent("\(badgeName).png")
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        if exists {
            return fileURL
        }
        return nil
    }
    
    /// Downloads a badge if it doesn't already exist locally. Returns true if successful.
    @discardableResult
    func ensureBadgeDownloaded(badgeName: String) async -> Bool {
        let fileURL = Self.badgeFolder.appendingPathComponent("\(badgeName).png")
        
        // Skip if already exists
        if fileManager.fileExists(atPath: fileURL.path) {
            return true
        }
        
        let urlString = "https://media.retroachievements.org/Badge/\(badgeName).png"
        guard let url = URL(string: urlString) else { return false }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            
            if httpResponse.statusCode != 200 {
                LoggerService.error(category: "RABadgeCache", "Failed to download badge \(badgeName): HTTP \(httpResponse.statusCode) from \(urlString)")
                return false
            }
            
            try data.write(to: fileURL)
            await MainActor.run {
                badgeUpdateToken = UUID()
            }
            LoggerService.debug(category: "RABadgeCache", "Downloaded and cached badge: \(badgeName)")
            return true
        } catch {
            LoggerService.error(category: "RABadgeCache", "Failed to download badge \(badgeName): \(error)")
            return false
        }
    }
    
    /// Downloads all missing badges for a list of achievements with rate limiting (2 hits/sec).
 func prefetchBadges(for achievements: [Achievement]) {
 LoggerService.info(category: "RABadgeCache", "Prefetching badges for \(achievements.count) achievements...")
        Task {
            var downloadCount = 0
            for achievement in achievements {
                // Check local existence first to avoid unnecessary hits
                let fileURL = Self.badgeFolder.appendingPathComponent("\(achievement.badgeName).png")
                let exists = FileManager.default.fileExists(atPath: fileURL.path)
                
                if !exists {
                    LoggerService.debug(category: "RABadgeCache", "Badge \(achievement.badgeName) missing, queuing download...")
                    if await ensureBadgeDownloaded(badgeName: achievement.badgeName) {
                        downloadCount += 1
                    }
                    // Throttle to 2 hits per second (500ms delay)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                } else {
                    LoggerService.debug(category: "RABadgeCache", "Badge \(achievement.badgeName) already exists at \(fileURL.path)")
                }
            }
            if downloadCount > 0 {
                LoggerService.info(category: "RABadgeCache", "Finished prefetching. Downloaded \(downloadCount) new badges.")
            } else {
                LoggerService.debug(category: "RABadgeCache", "All badges already cached.")
            }
        }
    }
}

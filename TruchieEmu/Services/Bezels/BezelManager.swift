import Foundation
import AppKit

/// Main manager for bezel resolution, caching, and loading.
/// This is the primary interface for other parts of the app to interact with bezels.
@MainActor
class BezelManager: ObservableObject {
    static let shared = BezelManager()
    
    /// Cached bezel images (LRU cache)
    private var imageCache: NSCache<NSString, NSImage>
    
    /// Currently loading bezels (prevent duplicate downloads)
    private var loadingBezels: Set<String> = []
    
    private let apiService: BezelAPIService
    private let storageManager: BezelStorageManager
    
    private init() {
        self.apiService = BezelAPIService.shared
        self.storageManager = BezelStorageManager.shared
        
        // Set up image cache (100MB limit)
        self.imageCache = NSCache<NSString, NSImage>()
        imageCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
        imageCache.countLimit = 50
    }
    
    // MARK: - Bezel Resolution
    
    /// Resolve a bezel for a game.
    /// - Parameters:
    ///   - systemID: The system ID (e.g., "snes")
    ///   - rom: The ROM to resolve a bezel for
    ///   - preferAutoMatch: If true, skip user-selected bezel and use auto-match (for when user explicitly triggers auto-match)
    /// - Returns: A bezel resolution result with the image URL and aspect ratio
    func resolveBezel(systemID: String, rom: ROM, preferAutoMatch: Bool = false) -> BezelResolutionResult {
        // Check if bezels are enabled for this ROM
        let bezelFileName = rom.settings.bezelFileName
        let isBezelDisabled = bezelFileName == "none"
        
        if isBezelDisabled {
            return .noBezel
        }
        
        // 1. Check for user-selected bezel (only if not preferring auto-match)
        if !preferAutoMatch, !bezelFileName.isEmpty {
            if let result = resolveSpecificBezel(systemID: systemID, filename: bezelFileName) {
                return result
            }
        }
        
        // 2. Try auto-match (exact filename match locally)
        if let autoMatchResult = autoMatchBezel(systemID: systemID, gameName: rom.displayName) {
            return autoMatchResult
        }
        
        // 3. Try auto-match with cleaned name
        let cleanName = cleanGameName(rom.displayName)
        if let cleanMatchResult = autoMatchBezel(systemID: systemID, gameName: cleanName) {
            return cleanMatchResult
        }
        
        // 4. Try fuzzy match against cached manifest entries
        if let manifestMatch = fuzzyMatchBezel(systemID: systemID, gameName: rom.displayName) {
            return manifestMatch
        }
        
        // 5. Fall back to user-selected bezel only if auto-match wasn't preferred and nothing was found
        if !preferAutoMatch, !bezelFileName.isEmpty {
            if let result = resolveSpecificBezel(systemID: systemID, filename: bezelFileName) {
                return result
            }
        }
        
        // 6. No bezel found
        return .noBezel
    }
    
    /// Fuzzy match a bezel against manifest entries using cleaned/normalized names.
    private func fuzzyMatchBezel(systemID: String, gameName: String) -> BezelResolutionResult? {
        guard let cachedManifest = apiService.cachedManifest(systemID: systemID) else {
            return nil
        }
        
        let normalizedInput = normalizeGameNameForMatch(gameName)
        
        // Try to find a bezel entry whose normalized name matches or contains the input
        for entry in cachedManifest.entries {
            let normalizedEntry = normalizeGameNameForMatch(entry.id)
            
            // Check exact match after normalization
            if normalizedInput == normalizedEntry {
                LoggerService.debug(category: "Bezel", "Found bezel for \(gameName) via manifest match: \(entry.displayName)")
                return createResultFor(entry: entry, systemID: systemID)
            }
            
            // Check if entry contains the game name (handles region variants)
            if normalizedInput.count > 3 && normalizedEntry.contains(normalizedInput) {
                LoggerService.debug(category: "Bezel", "Found bezel for \(gameName) via partial match: \(entry.displayName)")
                return createResultFor(entry: entry, systemID: systemID)
            }
            
            // Check if input contains the entry
            if normalizedEntry.count > 3 && normalizedInput.contains(normalizedEntry) {
                LoggerService.debug(category: "Bezel", "Found bezel for \(gameName) via reverse match: \(entry.displayName)")
                return createResultFor(entry: entry, systemID: systemID)
            }
        }
        
        return nil
    }
    
    /// Create a BezelResolutionResult for a manifest-matched entry.
    private func createResultFor(entry: BezelEntry, systemID: String) -> BezelResolutionResult {
        // Download if not local
        let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: entry.id)
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            let aspectRatio = getAspectRatio(for: localURL)
            return BezelResolutionResult(
                entry: BezelEntry(
                    id: entry.id,
                    filename: entry.filename,
                    rawURL: entry.rawURL,
                    localURL: localURL
                ),
                resolutionMethod: .exactMatch,
                aspectRatio: aspectRatio
            )
        }
        
        // Return entry with remote URL for download
        return BezelResolutionResult(
            entry: entry,
            resolutionMethod: .exactMatch,
            aspectRatio: 4.0 / 3.0 // Default until loaded
        )
    }
    
    /// Resolve a specific bezel by filename.
    private func resolveSpecificBezel(systemID: String, filename: String) -> BezelResolutionResult? {
        let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: filename)
        
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }
        
        let aspectRatio = getAspectRatio(for: localURL)
        let entry = BezelEntry(
            id: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
            filename: filename,
            rawURL: URL(filePath: ""), // Not used for local files
            localURL: localURL
        )
        
        return BezelResolutionResult(
            entry: entry,
            resolutionMethod: .userSelection,
            aspectRatio: aspectRatio
        )
    }
    
    /// Try to auto-match a game name to a bezel.
    private func autoMatchBezel(systemID: String, gameName: String) -> BezelResolutionResult? {
        let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: gameName)
        
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }
        
        let aspectRatio = getAspectRatio(for: localURL)
        let entry = BezelEntry(
            id: URL(fileURLWithPath: gameName).deletingPathExtension().lastPathComponent,
            filename: "\(gameName).png",
            rawURL: URL(filePath: ""),
            localURL: localURL
        )
        
        return BezelResolutionResult(
            entry: entry,
            resolutionMethod: .exactMatch,
            aspectRatio: aspectRatio
        )
    }
    
    // MARK: - Image Loading
    
    /// Load a bezel image from a local URL (with caching).
    func loadBezelImage(at url: URL) -> NSImage? {
        let cacheKey = url.path as NSString
        
        // Check cache first
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Load from disk
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        
        // Cache it (cost is approximate image size)
        let cost = Int(image.size.width * image.size.height * 4)
        imageCache.setObject(image, forKey: cacheKey, cost: cost)
        
        return image
    }
    
    /// Get the aspect ratio of a bezel image.
    func getAspectRatio(for url: URL) -> CGFloat {
        guard let image = NSImage(contentsOf: url) else {
            return 4.0 / 3.0 // Default fallback
        }
        
        let width = image.size.width
        let height = image.size.height
        
        guard width > 0 && height > 0 else {
            return 4.0 / 3.0
        }
        
        // Detect orientation
        if width > height {
            // Horizontal bezel (most common) - assume 4:3 playable area
            return 4.0 / 3.0
        } else {
            // Vertical bezel (rotated arcade games) - assume 3:4 playable area
            return 3.0 / 4.0
        }
    }
    
    // MARK: - Download Management
    
    /// Download a bezel for a game. This is called before gameplay to ensure bezels are ready.
    func downloadBezelIfNeeded(systemID: String, gameName: String) async throws -> URL? {
        // Check local first (use full gameName for storage)
        let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: gameName)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        // Prevent duplicate downloads
        let loadingKey = "\(systemID):\(gameName)"
        guard !loadingBezels.contains(loadingKey) else {
            return nil
        }
        loadingBezels.insert(loadingKey)
        defer { loadingBezels.remove(loadingKey) }
        
        // Get manifest to find the bezel
        let entries = try await apiService.getManifest(systemID: systemID)
        
        // Try multiple matching strategies
        let searchTerms = [gameName, cleanGameName(gameName), gameName.lowercased()]
        
        for searchTerm in searchTerms {
            let sanitized = storageManager.sanitizeFilename(searchTerm)
            
            if let entry = entries.first(where: {
                $0.id == searchTerm ||
                $0.id == sanitized ||
                $0.displayName.caseInsensitiveCompare(searchTerm) == .orderedSame
            }) {
                return try await apiService.downloadBezel(systemID: systemID, entry: entry)
            }
        }
        
        // Try fuzzy match against manifest using cleaned names
        let normalizedInput = normalizeGameNameForMatch(gameName)
        for entry in entries {
            let normalizedEntry = normalizeGameNameForMatch(entry.id)
            if normalizedEntry.count > 3 && normalizedInput.count > 3 {
                if normalizedEntry.contains(normalizedInput) {
                    return try await apiService.downloadBezel(systemID: systemID, entry: entry)
                }
            }
        }
        
        return nil // Not found in repository
    }
    
    /// Normalize a game name for matching (lowercase, remove special chars, remove spaces for matching variants like "ShadowRun" vs "Shadow Run").
    private func normalizeGameNameForMatch(_ name: String) -> String {
        return GameNameFormatter.normalizedComparisonKey(cleanGameName(name))
    }
    
    // MARK: - Manifest Management
    
    /// Refresh the manifest for a system (force fetch from GitHub).
    func refreshManifest(systemID: String) async throws -> [BezelEntry] {
        return try await apiService.fetchManifest(systemID: systemID)
    }
    
    /// Get cached bezel entries for a system.
    func getBezels(systemID: String) async throws -> [BezelEntry] {
        return try await apiService.getManifest(systemID: systemID)
    }
    
    /// Get bezel entries with download status updated.
    func getBezelsWithStatus(systemID: String) async -> [BezelEntry] {
        do {
            let entries = try await apiService.getManifest(systemID: systemID)
            return entries.map { updateDownloadStatus(for: $0, systemID: systemID) }
        } catch {
            LoggerService.info(category: "Bezel", "Failed to load bezels for \(systemID): \(error)")
            return []
        }
    }
    
    private func updateDownloadStatus(for entry: BezelEntry, systemID: String) -> BezelEntry {
        let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: entry.id)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return BezelEntry(
                id: entry.id,
                filename: entry.filename,
                rawURL: entry.rawURL,
                localURL: localURL
            )
        }
        return entry
    }
    
    // MARK: - Custom Bezels
    
    /// Import a custom bezel from a user-selected file.
    func importCustomBezel(from sourceURL: URL, systemID: String, gameName: String) throws -> URL {
        try storageManager.ensureDirectoriesExist()
        
        let destinationURL = storageManager.bezelFilePath(systemID: systemID, gameName: gameName)
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Copy the file
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // Invalidate cache
        imageCache.removeObject(forKey: destinationURL.path as NSString)
        
        return destinationURL
    }
    
    /// Remove a bezel file for a game.
    func removeBezel(systemID: String, gameName: String) throws {
        let localURL = storageManager.bezelFilePath(systemID: systemID, gameName: gameName)
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
            imageCache.removeObject(forKey: localURL.path as NSString)
        }
    }
    
    // MARK: - Helpers
    
    /// Clean a game name by removing region/language suffixes for better matching.
    private func cleanGameName(_ name: String) -> String {
        var cleaned = name
        
        // Remove common region/language suffixes
        let suffixesToRemove = [
            " (USA)", " (Europe)", " (World)", " (Japan)",
            " (UK)", " (France)", " (Germany)", " (Spain)",
            " (Italy)", " (Australia)", " (Brazil)",
            " (Korea)", " (China)", " (Russia)",
            " (En)", " (Ja)", " (Fr)", " (De)",
            " (Es)", " (It)", " (Pt)", " (Ru)",
            " (En,Fr,De)", " (En,Ja)", "(En,Fr,De,Es,It)",
            " (En,Fr)", " (En,De)", " (En,Es)",
            " Rev A", " Rev B", " Rev C", " Rev 1",
            " (Version 1.0)", " (Version 1.1)",
            " (Virtual Console)", " (PSN)",
            " Plus"
        ]
        
        for suffix in suffixesToRemove {
            cleaned = cleaned.replacingOccurrences(
                of: suffix,
                with: "",
                options: .caseInsensitive
            )
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Check if a system has bezel support.
    func hasBezelSupport(for systemID: String) -> Bool {
        return BezelSystemMapping.hasBezelSupport(for: systemID)
    }
    
    /// Check if a bezel exists locally for a game.
    func bezelExists(systemID: String, gameName: String) -> Bool {
        let url = storageManager.bezelFilePath(systemID: systemID, gameName: gameName)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
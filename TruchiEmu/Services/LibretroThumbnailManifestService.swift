import Foundation
import Combine

// Fetches and caches Libretro Thumbnail repository manifests (Git trees) via GitHub API.
// This allows checking if a thumbnail exists on the CDN without performing multiple HEAD requests.
@MainActor
class LibretroThumbnailManifestService: ObservableObject {
    static let shared = LibretroThumbnailManifestService()
    
    private let logCategory = "LibretroManifest"
    
    // Maps repo name (e.g. "Nintendo_-_Super_Nintendo_Entertainment_System") to its file set.
    private var manifestCache: [String: Set<String>] = [:]
    
    // Active fetch tasks to avoid redundant network calls for the same repo.
    private var activeTasks: [String: Task<Set<String>, Error>] = [:]
    private var cacheRepo: ResourceCacheRepository {
        ResourceCacheRepository(context: SwiftDataContainer.shared.mainContext)
    }
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.httpAdditionalHeaders = [
            "User-Agent": "TruchiEmu/\(version) (macOS)"
        ]
        return URLSession(configuration: config)
    }()

    @Published var isRefreshing = false
    @Published var refreshProgress: Double = 0
    @Published var currentRepoRefreshing: String = ""

    private init() {
        Task {
            await loadBundledManifests()
        }
    }

    // MARK: - Metadata Check

    /// Checks if the remote repository has been updated since the last local manifest was saved.
    /// - Parameter repoName: The GitHub repository name.
    /// - Returns: True if the remote repository is newer than the local manifest.
    func checkIfManifestNeedsUpdate(for repoName: String) async -> Bool {
        let gitTreesURL = "https://api.github.com/repos/libretro-thumbnails/\(repoName)/git/trees/master?recursive=1"
        guard let url = URL(string: gitTreesURL) else { return true }

        #if LOG_DEBUG
        LoggerService.debug(category: logCategory, "Checking if manifest for \(repoName) needs update via GitHub metadata... at \(gitTreesURL)")
        #endif

        let cacheKey = ResourceCacheEntry.makeThumbnailManifestKey(repoName: repoName)
        
        // We need to know when our CURRENT local manifest was last updated.
        guard let localEntry = cacheRepo.getEntry(cacheKey: cacheKey) else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "No local manifest found for \(repoName), must download.")
            #endif
            return true
        }

        // If we have an expiry in the future, we don't even bother checking GitHub metadata.
        if let expiresAt = localEntry.expiresAt, expiresAt > Int(Date().timeIntervalSince1970) {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "Local manifest for \(repoName) is still valid (expires at \(expiresAt)). Skipping GitHub check.")
            #endif
            return false
        }

        do {
            // Perform a lightweight HEAD request to check for changes.
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            
            let (_, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return true }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 304 {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "GitHub metadata check successful for \(repoName). Proceeding to fetch.")
                #endif
                return true
            }

            LoggerService.warning(category: logCategory, "GitHub metadata check returned \(httpResponse.statusCode) for \(repoName)")
            return true 
        } catch {
            LoggerService.error(category: logCategory, "Error checking GitHub metadata for \(repoName): \(error.localizedDescription)")
            return true // Fallback to download on error
        }
    }

    // Loads pre-bundled manifests from the app's resource bundle.
    private func loadBundledManifests() async {
        guard let resourceURL = Bundle.main.url(forResource: "ThumbnailManifests", withExtension: nil) else {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "No bundled ThumbnailManifests directory found")
            #endif
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            for fileURL in files where fileURL.pathExtension == "json" {
                let repoName = fileURL.deletingPathExtension().lastPathComponent
                if let data = try? Data(contentsOf: fileURL),
                   let response = try? JSONDecoder().decode(GitTreesResponse.self, from: data) {
                    let set = Set(response.tree.map { $0.path })
                    manifestCache[repoName] = set
                    LoggerService.info(category: logCategory, "Loaded bundled manifest for \(repoName) (\(set.count) entries)")
                }
            }
        } catch {
            LoggerService.warning(category: logCategory, "Failed to read bundled manifests: \(error.localizedDescription)")
        }
    }

    // Explicitly refreshes all manifests currently in use or for primary systems.
    func refreshAllManifests() async {
        let systems = LibretroThumbnailResolver.allKnownSystemRepos()
        guard !systems.isEmpty else { return }
        
        await MainActor.run {
            isRefreshing = true
            refreshProgress = 0
        }
        
        var completed = 0
        for repoName in systems {
            await MainActor.run { currentRepoRefreshing = repoName }
            _ = try? await fetchManifestFromGitHub(repoName: repoName, force: true)
            completed += 1
            await MainActor.run { refreshProgress = Double(completed) / Double(systems.count) }
        }
        
        await MainActor.run {
            isRefreshing = false
            currentRepoRefreshing = ""
            refreshProgress = 1.0
        }
    }

    // Checks if a candidate URL is likely to exist on the Libretro CDN using the manifest.
    // - Parameters:
    //   - url: The full CDN URL to check (e.g. https://thumbnails.libretro.com/System/Type/Game.png)
    //   - folderName: The folder name used in the CDN (e.g. "Nintendo - Nintendo Entertainment System")
    // - Returns: True if the file is present in the manifest, or true if the manifest cannot be fetched (fallback to HEAD).
    func existsInManifest(url: URL, folderName: String) async -> Bool {
        let repoName = LibretroThumbnailResolver.githubRepoName(for: folderName)
        
        do {
            let fileSet = try await getManifest(for: repoName)
            
            // The manifest paths in Git are like "Named_Boxarts/Game.png"
            // The URL path is like "/System%20Name/Named_Boxarts/Game.png"
            // We need to extract the part after System Name
            let pathComponents = url.pathComponents
            guard pathComponents.count >= 3 else { return true } // Fallback
            
            // Last two components are usually [TypeFolder, FileName]
            let typeFolder = pathComponents[pathComponents.count - 2]
            let fileName = pathComponents[pathComponents.count - 1]
            
            // GitHub Git Tree uses unencoded names with forward slashes
            // So we reconstruct the relative path: "Named_Boxarts/Game Name.png"
            let relativePath = "\(typeFolder)/\(fileName)".removingPercentEncoding ?? "\(typeFolder)/\(fileName)"
            
            let exists = fileSet.contains(relativePath)
            if !exists {
                #if LOG_EXTREME
                LoggerService.extreme(category: logCategory, "Manifest miss: '\(relativePath)' not found in \(repoName)")
                #endif
            } else {
                #if LOG_EXTREME
                LoggerService.extreme(category: logCategory, "Manifest hit: '\(relativePath)' found in \(repoName)")
                #endif
            }
            return exists
        } catch {
            LoggerService.warning(category: logCategory, "Manifest fetch failed for \(repoName): \(error.localizedDescription). Falling back to network check.")
            return true // Fallback to HEAD check if manifest fails
        }
    }

    // Probes whether a GitHub repository exists for the given repo name.
    // Returns true if the repo responds with 200, false if 404 or other error.
    func repoExists(repoName: String) async -> Bool {
        let probeURL = "https://api.github.com/repos/libretro-thumbnails/\(repoName)"
        guard let url = URL(string: probeURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let exists = httpResponse.statusCode == 200
            if !exists {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "Repo probe: \(repoName) → HTTP \(httpResponse.statusCode) (does not exist)")
                #endif
            } else {
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "Repo probe: \(repoName) → exists")
                #endif
            }
            return exists
        } catch {
            #if LOG_DEBUG
            LoggerService.debug(category: logCategory, "Repo probe: \(repoName) → error: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Returns the cached manifest file set for a repo, fetching it if needed.
    func getManifestFileSet(for repoName: String) async throws -> Set<String> {
        try await getManifest(for: repoName)
    }

    // Retrieves the file manifest for a specific system repository, with caching.
    private func getManifest(for repoName: String) async throws -> Set<String> {
        if let cached = manifestCache[repoName] {
            return cached
        }
        
        if let active = activeTasks[repoName] {
            return try await active.value
        }
        
        let task = Task<Set<String>, Error> {
            // Check if we actually need to download a new one based on GitHub metadata
            let needsUpdate = await checkIfManifestNeedsUpdate(for: repoName)
            
            if needsUpdate {
                LoggerService.info(category: logCategory, "Manifest for \(repoName) needs update. Fetching from GitHub...")
                let set = try await fetchManifestFromGitHub(repoName: repoName)
                manifestCache[repoName] = set
                return set
            } else {
                // This part is tricky: if it doesn't need update, we still need to get the data
                // but we don't want to trigger a full download if we have nothing.
                // However, getManifest is only called when we DON'T have it in manifestCache.
                // So if it doesn't need update, but we don't have it in manifestCache, 
                // it means we probably have it in the ResourceCache (disk) but not in memory.
                
                #if LOG_DEBUG
                LoggerService.debug(category: logCategory, "Manifest for \(repoName) is up-to-date but not in memory. Loading from disk cache...")
                #endif
                return try await fetchManifestFromGitHub(repoName: repoName, force: false)
            }
        }
        
        activeTasks[repoName] = task
        defer { activeTasks[repoName] = nil }
        
        return try await task.value
    }

    private func fetchManifestFromGitHub(repoName: String, force: Bool = false) async throws -> Set<String> {
        let gitTreesURL = "https://api.github.com/repos/libretro-thumbnails/\(repoName)/git/trees/master?recursive=1"
        guard let url = URL(string: gitTreesURL) else {
            throw URLError(.badURL)
        }
        
        LoggerService.info(category: logCategory, "Fetching manifest for \(repoName) from GitHub (force=\(force))...")
        
        let cacheKey = ResourceCacheEntry.makeThumbnailManifestKey(repoName: repoName)

        let data: Data
        do {
            data = try await ResourceCacheInterceptor.shared.fetchWithCache(
                url: url,
                type: .thumbnailManifest,
                cacheKey: cacheKey,
                expiry: .conditional
            ).data
        } catch {
            LoggerService.warning(category: logCategory, "GitHub manifest fetch failed for \(repoName): \(error.localizedDescription)")
            throw error
        }

        if let response = try? JSONDecoder().decode(GitTreesResponse.self, from: data) {
            let paths = Set(response.tree.map { $0.path })
            manifestCache[repoName] = paths
            LoggerService.info(category: logCategory, "Manifest for \(repoName) loaded with \(paths.count) entries")
            return paths
        }

        // The cached/304 data failed to decode — the on-disk file is corrupt (its etag
        // still matches the server, so a conditional request would 304 the same bad bytes).
        // Invalidate the entry and force a fresh unconditional GET that overwrites it.
        LoggerService.warning(category: logCategory, "Manifest for \(repoName) failed to decode; re-fetching unconditionally")
        ResourceCacheInterceptor.shared.invalidate(cacheKey: cacheKey)
        let freshData = try await ResourceCacheInterceptor.shared.fetchWithCache(
            url: url,
            type: .thumbnailManifest,
            cacheKey: cacheKey,
            expiry: .force
        ).data

        let response = try JSONDecoder().decode(GitTreesResponse.self, from: freshData)
        let paths = Set(response.tree.map { $0.path })
        manifestCache[repoName] = paths
        LoggerService.info(category: logCategory, "Manifest for \(repoName) loaded with \(paths.count) entries (after forced re-fetch)")
        return paths
    }
}

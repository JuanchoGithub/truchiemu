import Foundation
import SwiftUI
import SwiftData

@MainActor
final class MetadataSyncCoordinator: ObservableObject {
    static let shared = MetadataSyncCoordinator()

    enum Phase: Equatable {
        case idle
        case downloading
        case extracting
        case parsing
        case indexing
        case syncing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var isActive: Bool = false

    private init() {}

    func runAfterLibraryUpdate(library: ROMLibrary, targetROMs: [ROM]? = nil) async {
        guard LaunchBoxGamesDBService.shared.isEnabled else { return }

        if RunningGamesTracker.shared.isGameRunning {
            #if LOG_DEBUG
            LoggerService.debug(category: "MetadataSync", "Skipping metadata sync — game is running")
            #endif
            return
        }

        let metadataService = LaunchBoxMetadataService.shared
        let scope = targetROMs ?? library.roms

        // Disk gate: skip ROMs LaunchBox already searched and found NO match for
        // on a previous run. Re-querying unmatchable ROMs every scan wastes ~66ms
        // each (in-memory name-index lookup) for zero benefit — across a 1900-ROM
        // library that's the bulk of Phase 3b. Persisted with a timestamp; entries
        // expire after the TTL so a transient failure (or later-added metadata)
        // is retried rather than permanently blocked.
        let negativeCacheTTL: TimeInterval = 7 * 24 * 3600
        let noMatchCache: [String: Date] = {
            guard let data = AppSettings.getData("launchbox_noMatchROMs"),
                  let map = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
            return map
        }()
        let noMatchROMPaths = noMatchCache.filter { Date().timeIntervalSince($0.value) < negativeCacheTTL }.keys

        // Positive cache: ROMs already enriched by LaunchBox in a previous run.
        // The store may have the metadata, but the in-memory `scope` copies used
        // by the filter can predate the metadata merge (or carry nil metadata), so
        // we can't rely on `rom.metadata` to skip already-enriched ROMs. Without
        // this gate, every re-scan re-runs ~1684 lookups + store writes for data
        // that's already on disk — that's the entire 128s LaunchBox phase.
        let syncedCacheTTL: TimeInterval = 30 * 24 * 3600
        let syncedCache: [String: Date] = {
            guard let data = AppSettings.getData("launchbox_syncedROMs"),
                  let map = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
            return map
        }()
        let syncedROMPaths = syncedCache.filter { Date().timeIntervalSince($0.value) < syncedCacheTTL }.keys

        let needMetadata = scope.filter { rom in
            guard !(noMatchROMPaths.contains(rom.path.path)) else { return false }
            guard !(syncedROMPaths.contains(rom.path.path)) else { return false }
            return (rom.metadata?.description?.isEmpty ?? true) ||
                   (rom.metadata?.developer?.isEmpty ?? true) ||
                   (rom.metadata?.publisher?.isEmpty ?? true)
        }

        guard !needMetadata.isEmpty else { return }

        isActive = true
        defer {
            isActive = false
            phase = .idle
            progress = 0
            statusLine = ""
        }

        phase = .downloading
        statusLine = "Checking LaunchBox database..."

        guard await metadataService.downloadIfNeeded(progress: { [weak self] p in
            Task { @MainActor in
                self?.progress = p
                self?.statusLine = "Downloading Metadata.zip: \(Int(p * 100))% (501 MB)"
            }
        }) else {
            statusLine = "LaunchBox database download failed"
            return
        }

        phase = .parsing
        progress = 0

        guard await metadataService.parseAndIndexIfNeeded(status: { [weak self] msg in
            Task { @MainActor in
                if msg.hasPrefix("Indexed ") {
                    self?.phase = .indexing
                } else if msg.hasPrefix("Extracting") {
                    self?.phase = .extracting
                } else {
                    self?.phase = .parsing
                }
                self?.statusLine = msg
            }
        }) else {
            statusLine = "LaunchBox database parse failed"
            return
        }

        phase = .syncing
        let total = needMetadata.count
        var completed = 0
        var enriched = 0

        var enrichedIDs: [UUID] = []
        var newlyNoMatch: [String] = []
        for rom in needMetadata {
            let found = await metadataService.fetchAndApplyMetadata(for: rom, library: library, downloadBoxArt: false, persistImmediately: false)
            completed += 1
            if found {
                enriched += 1; enrichedIDs.append(rom.id)
            } else {
                newlyNoMatch.append(rom.path.path)
            }
            progress = Double(completed) / Double(max(total, 1))
            let systemID = rom.systemID ?? "?"
            statusLine = "\(completed)/\(total) — \(rom.displayName) (\(systemID))" + (found ? " ✓" : " — no match")
            if completed % 20 == 0 { await Task.yield() }
        }

        if !newlyNoMatch.isEmpty {
            var map = noMatchCache
            let now = Date()
            for path in newlyNoMatch { map[path] = now }
            if let data = try? JSONEncoder().encode(map) {
                AppSettings.setData("launchbox_noMatchROMs", value: data)
            }
        }

        if !enrichedIDs.isEmpty {
            var map = syncedCache
            let now = Date()
            for id in enrichedIDs {
                if let rom = scope.first(where: { $0.id == id }) { map[rom.path.path] = now }
            }
            if let data = try? JSONEncoder().encode(map) {
                AppSettings.setData("launchbox_syncedROMs", value: data)
            }
        }

        if !enrichedIDs.isEmpty {
            statusLine = "Flushing changes to disk..."
            LibraryMetadataStore.shared.flushDirtyToSwiftData()
            library.saveROMsToDatabase(only: enrichedIDs)
        }
        progress = 1
        statusLine = "Done — \(enriched) enriched of \(total) ROMs"
    }

    func forceSync(library: ROMLibrary) async {
        guard LaunchBoxGamesDBService.shared.isEnabled else { return }

        isActive = true
        defer {
            isActive = false
            phase = .idle
            progress = 0
            statusLine = ""
        }

        let metadataService = LaunchBoxMetadataService.shared

        phase = .downloading
        statusLine = "Downloading LaunchBox metadata (forced refresh)..."

        guard await metadataService.downloadIfNeeded(force: true, progress: { [weak self] p in
            Task { @MainActor in
                self?.progress = p
                self?.statusLine = "Downloading Metadata.zip: \(Int(p * 100))% (501 MB)"
            }
        }) else {
            statusLine = "LaunchBox database download failed"
            return
        }

        phase = .parsing
        progress = 0

        guard await metadataService.parseAndIndexIfNeeded(force: true, status: { [weak self] msg in
            Task { @MainActor in
                if msg.hasPrefix("Indexed ") {
                    self?.phase = .indexing
                } else if msg.hasPrefix("Extracting") {
                    self?.phase = .extracting
                } else {
                    self?.phase = .parsing
                }
                self?.statusLine = msg
            }
        }) else {
            statusLine = "LaunchBox database parse failed"
            return
        }

        phase = .syncing

        let allROMs = library.roms
        let total = allROMs.count
        var completed = 0
        var enriched = 0

        var enrichedIDs: [UUID] = []
        for rom in allROMs {
            let found = await metadataService.fetchAndApplyMetadata(for: rom, library: library, downloadBoxArt: false, persistImmediately: false)
            completed += 1
            if found { enriched += 1; enrichedIDs.append(rom.id) }
            progress = Double(completed) / Double(max(total, 1))
            let systemID = rom.systemID ?? "?"
            statusLine = "\(completed)/\(total) — \(rom.displayName) (\(systemID))" + (found ? " ✓" : " — no match")
            if completed % 20 == 0 { await Task.yield() }
        }

        if !enrichedIDs.isEmpty {
            statusLine = "Flushing changes to disk..."
            LibraryMetadataStore.shared.flushDirtyToSwiftData()
            library.saveROMsToDatabase(only: enrichedIDs)
        }
        progress = 1
        statusLine = "Force sync complete — \(enriched) matched of \(total) ROMs"
    }
}

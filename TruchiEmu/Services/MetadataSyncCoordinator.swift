import Foundation
import SwiftUI

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

        let needMetadata = scope.filter { rom in
            (rom.metadata?.description?.isEmpty ?? true) ||
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

        for rom in needMetadata {
            let found = await metadataService.fetchAndApplyMetadata(for: rom, library: library)
            completed += 1
            if found { enriched += 1 }
            progress = Double(completed) / Double(max(total, 1))
            let systemID = rom.systemID ?? "?"
            statusLine = "\(completed)/\(total) — \(rom.displayName) (\(systemID))" + (found ? " ✓" : " — no match")
            try? await Task.sleep(nanoseconds: 50_000_000)
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

        for rom in allROMs {
            let found = await metadataService.fetchAndApplyMetadata(for: rom, library: library)
            completed += 1
            if found { enriched += 1 }
            progress = Double(completed) / Double(max(total, 1))
            let systemID = rom.systemID ?? "?"
            statusLine = "\(completed)/\(total) — \(rom.displayName) (\(systemID))" + (found ? " ✓" : " — no match")
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        progress = 1
        statusLine = "Force sync complete — \(enriched) matched of \(total) ROMs"
    }
}

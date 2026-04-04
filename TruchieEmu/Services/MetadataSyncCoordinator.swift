import Foundation
import SwiftUI

/// Background coordinator that integrates LaunchBox metadata fetching into the
/// post-scan automation pipeline.
@MainActor
final class MetadataSyncCoordinator: ObservableObject {
    static let shared = MetadataSyncCoordinator()

    enum Phase: Equatable {
        case idle
        case syncing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var isActive: Bool = false

    private init() {}

    /// Run after library update: sync LaunchBox metadata for ROMs that need it.
    /// Only runs when the feature is enabled in settings.
    func runAfterLibraryUpdate(library: ROMLibrary) async {
        let launchbox = LaunchBoxGamesDBService.shared
        guard launchbox.isEnabled else { return }

        let snapshot = library.roms
        let needMetadata = snapshot.filter { rom in
            (rom.metadata?.description?.isEmpty ?? true) ||
            (rom.metadata?.developer?.isEmpty ?? true)
        }
        guard !needMetadata.isEmpty else { return }

        isActive = true
        defer {
            isActive = false
            phase = .idle
            progress = 0
            statusLine = ""
        }

        phase = .syncing
        let total = Double(needMetadata.count)

        let maxConcurrent = 3
        var completed = 0

        await withTaskGroup(of: (Bool, String).self) { group in
            var iter = needMetadata.makeIterator()
            var active = 0

            while active < maxConcurrent, let rom = iter.next() {
                group.addTask {
                    let ok = await launchbox.fetchAndApplyMetadata(for: rom, library: library)
                    return (ok, rom.displayName)
                }
                active += 1
            }

            for await (_, name) in group {
                active -= 1
                completed += 1
                let frac = Double(completed) / max(total, 1)
                progress = frac
                statusLine = "Fetching metadata: \(Int(frac * 100))% — \(name)"

                if let next = iter.next() {
                    group.addTask {
                        let ok = await launchbox.fetchAndApplyMetadata(for: next, library: library)
                        return (ok, next.displayName)
                    }
                    active += 1
                }
            }
        }

        progress = 1
        statusLine = "Fetching metadata: 100% — done"
        launchbox.recordSyncDate()
    }

    /// Full manual sync of all games.
    func fullSync(library: ROMLibrary) async {
        await LaunchBoxGamesDBService.shared.batchSyncLibrary(library: library) { [weak self] completed, total, label in
            guard let self = self else { return }
            self.phase = .syncing
            self.progress = Double(completed) / max(Double(total), 1)
            self.statusLine = "Syncing metadata: \(completed)/\(total) — \(label)"
        }
        self.phase = .idle
    }
}

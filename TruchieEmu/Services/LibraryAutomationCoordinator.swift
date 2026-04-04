import Foundation
import SwiftUI

/// Post-scan: identify ROMs missing metadata, then download Libretro box art. Drives the global status bar.
@MainActor
final class LibraryAutomationCoordinator: ObservableObject {
    static let shared = LibraryAutomationCoordinator()

    enum Phase: Equatable {
        case idle
        case identifying
        case downloadingArt
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var isActive: Bool = false

    private init() {}

    func runAfterLibraryUpdate(library: ROMLibrary) async {
        let snapshot = library.roms
        let needIdentify = snapshot.filter { $0.needsAutomaticIdentification }
        let needArt = snapshot.filter { $0.needsAutomaticBoxArt }

        guard !needIdentify.isEmpty || !needArt.isEmpty else { return }

        // Warm-up delay: let the UI settle after a library scan before starting background work
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await Task.yield()

        isActive = true
        defer {
            isActive = false
            phase = .idle
            progress = 0
            statusLine = ""
        }

        // Phase 1: Identification — throttled to keep UI responsive
        if !needIdentify.isEmpty {
            phase = .identifying
            let total = Double(needIdentify.count)
            for (idx, rom) in needIdentify.enumerated() {
                let label = rom.path.lastPathComponent
                let current = library.roms.first(where: { $0.id == rom.id }) ?? rom
                _ = await library.identifyROM(current)
                let done = Double(idx + 1) / max(total, 1)
                progress = done
                statusLine = "Identifying games: \(Int(done * 100))% — Checking \(label)"

                // Throttle: 500ms + yield between identifications to keep UI responsive
                try? await Task.sleep(nanoseconds: 500_000_000)
                await Task.yield()
            }
            progress = 1
            statusLine = "Identifying games: 100% — done"
        }

        // Brief pause between phases to give the MainActor runloop time to process UI updates
        try? await Task.sleep(nanoseconds: 500_000_000)
        await Task.yield()

        // Phase 2: Box art downloads
        let artTargets = library.roms.filter { $0.needsAutomaticBoxArt }
        guard !artTargets.isEmpty else { return }

        phase = .downloadingArt
        progress = 0
        statusLine = "Downloading box art: 0% — …"
        await BoxArtService.shared.batchDownloadBoxArtLibretro(
            for: artTargets,
            library: library
        ) { [weak self] completed, totalCount, fileLabel in
            guard let self = self else { return }
            let frac = Double(completed) / max(Double(totalCount), 1)
            self.progress = frac
            self.statusLine = "Downloading box art: \(Int(frac * 100))% — \(fileLabel)"
        }

        // Brief pause before LaunchBox phase
        try? await Task.sleep(nanoseconds: 500_000_000)
        await Task.yield()

        // After Libretro CDN, try LaunchBox GamesDB for remaining ROMs still missing art
        if LaunchBoxGamesDBService.shared.downloadAfterScan {
            let stillMissing = library.roms.filter { rom in
                let hasBoxart = rom.boxArtPath.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                return rom.needsAutomaticBoxArt && !hasBoxart
            }
            if !stillMissing.isEmpty {
                statusLine = "Trying LaunchBox GamesDB for \(stillMissing.count) games…"
                await LaunchBoxGamesDBService.shared.batchDownloadBoxArt(
                    for: stillMissing,
                    library: library
                ) { [weak self] completed, totalCount, fileLabel in
                    guard let self = self else { return }
                    let frac = Double(completed) / max(Double(totalCount), 1)
                    self.progress = frac
                    self.statusLine = "LaunchBox box art: \(Int(frac * 100))% — \(fileLabel)"
                }
            }
        }

        progress = 1
        statusLine = "Downloading box art: 100% — done"
    }
}

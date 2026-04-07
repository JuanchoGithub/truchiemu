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
        // Skip if any game is running — identification and box-art downloads
        // are network- and I/O-heavy and degrade gameplay performance.
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.debug(category: "LibraryAutomation", "Skipping post-scan automation — game is running")
            return
        }

        let snapshot = library.roms

        // Phase 0: Scan for pre-existing local boxart in /boxart subfolders
        // This populates boxArtPath for ROMs that have local artwork but haven't
        // been downloaded by the app yet (e.g., user-provided boxart files)
        let romsToCheck = snapshot.filter { $0.boxArtPath == nil }
        LoggerService.info(category: "LibraryAutomation", "📼 Checking \(romsToCheck.count) ROM(s) for local boxart in /boxart folders...")
        let romsWithLocalArt = BoxArtService.shared.resolveLocalBoxArtBatch(for: romsToCheck)
        if !romsWithLocalArt.isEmpty {
            LoggerService.info(category: "LibraryAutomation", "✅ Found local boxart for \(romsWithLocalArt.count) ROM(s)")
            for rom in romsWithLocalArt {
                library.updateROM(rom)
            }
        } else {
            LoggerService.info(category: "LibraryAutomation", "No local boxart found in scanned ROMs")
        }

        let needIdentify = library.roms.filter { $0.needsAutomaticIdentification && !$0.isHidden }
        let needArt = library.roms.filter { $0.needsAutomaticBoxArt && !$0.isHidden }

        guard !needIdentify.isEmpty || !needArt.isEmpty else { return }

        // Warm-up delay: let the UI settle after a library scan before starting background work
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await Task.yield()

        // Re-check after the delay — a game may have launched during the warm-up.
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.debug(category: "LibraryAutomation", "Skipping post-scan automation (game started during warm-up)")
            return
        }

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

            // Flush all in-memory metadata changes to SwiftData in a single batch.
            // This replaces the previous per-ROM save (which saved all 4248 ROMs each time).
            LibraryMetadataStore.shared.flushToSwiftData()
            library.saveROMsToDatabase()
        }

        // Brief pause between phases to give the MainActor runloop time to process UI updates
        try? await Task.sleep(nanoseconds: 500_000_000)
        await Task.yield()

        // Phase 2: Box art downloads (skip hidden ROMs)
        let artTargets = library.roms.filter { $0.needsAutomaticBoxArt && !$0.isHidden }
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

import Foundation
import SwiftUI

// Post-scan: identify ROMs missing metadata, then download Libretro box art. Drives the global status bar.
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

    func runAfterLibraryUpdate(library: ROMLibrary, targetROMs: [ROM]? = nil) async {
        // Skip if any game is running — identification and box-art downloads
        // are network- and I/O-heavy and degrade gameplay performance.
        
        // 1. Create a list to track ROMs modified in this batch
        var batchModifiedROMs: [ROM] = []

        // If targetROMs is provided, use it. Otherwise, fallback to full library.
        let scope = targetROMs ?? library.roms
        
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.debug(category: "LibraryAutomation", "Skipping post-scan automation — game is running")
            return
        }

        let needIdentify = scope.filter { $0.needsAutomaticIdentification && !$0.isHidden }
        let needArt = scope.filter { $0.needsAutomaticBoxArt && !$0.isHidden }

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

        // Phase 1: Identification — parallelized + grouped by system for maximum efficiency
        if !needIdentify.isEmpty {
            phase = .identifying
            let total = Double(needIdentify.count)
            var completedCount = 0
            
            // Track which ROMs were actually modified/identified to avoid saving 4000+ records redundantly
            var modifiedIDs: [UUID] = []
            
            // Grouping by system minimizes redundant DAT/Index loading across calls
            let groupedRoms = Dictionary(grouping: needIdentify) { $0.systemID ?? "unknown" }
            
            // Process systems one by one to keep logging and progress logical
            for (systemID, romsForSystem) in groupedRoms {
                let systemName = SystemDatabase.system(forID: systemID)?.name ?? systemID
                
                // Process ROMs of the same system in parallel batches
                let batchSize = 100
                for i in stride(from: 0, to: romsForSystem.count, by: batchSize) {
                    let batch = Array(romsForSystem[i..<min(i + batchSize, romsForSystem.count)])
                    
                    // Perform multi-ROM identification in background threads
                    let identificationResults = await Task.detached(priority: .userInitiated) {
                        await withTaskGroup(of: (UUID, ROMIdentifyResult).self) { group in
                            for rom in batch {
                                group.addTask {
                                    let result = await ROMIdentifierService.shared.identify(rom: rom, preferNameMatch: true)
                                    return (rom.id, result)
                                }
                            }
                            var results: [(UUID, ROMIdentifyResult)] = []
                            for await res in group { results.append(res) }
                            return results
                        }
                    }.value
                    

                    // 1. Create a quick-lookup map for the current batch
                    let batchLookup = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })

                    // 2. Apply all results to library once batch is ready
                    for (romID, result) in identificationResults {
                        // Instant lookup (O(1)) instead of scanning the entire library array (O(n))
                        if let current = batchLookup[romID] { 
                                 // Capture the returned updated ROM
                                 if let updated = library.applyIdentificationResult(result, to: current, persist: false, silent: true) {
                                     var refreshed = updated
                                     refreshed.refreshDerivedFields()
                                     batchModifiedROMs.append(refreshed)
                                     modifiedIDs.append(romID)
                                 }
                            completedCount += 1
                        }
                    }
                    
                    let done = Double(completedCount) / total
                    progress = done
                    statusLine = "Identifying \(systemName): \(Int(done * 100))%"
                    
                    await Task.yield()
                }
            }
            
            progress = 1
            statusLine = "Identifying games: 100% — done"

            // Save ONLY the ROMs that were modified in this phase.
            // This avoids a massive MainActor hang by saving 1000 items instead of 4250.
            library.saveROMsToDatabase(only: modifiedIDs)
        }

        // Brief pause between phases to give the MainActor runloop time to process UI updates
        try? await Task.sleep(nanoseconds: 500_000_000)
        await Task.yield()

        // Phase 2: Box art downloads (skip hidden ROMs)
        let artTargets = scope.filter { $0.needsAutomaticBoxArt && !$0.isHidden }
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
            let stillMissing = scope.filter { rom in
                !rom.hasBoxArt
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

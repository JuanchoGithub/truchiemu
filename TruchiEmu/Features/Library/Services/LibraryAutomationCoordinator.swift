import Foundation
import SwiftUI

// Post-scan: identify ROMs missing metadata, then download Libretro box art. Drives the global status bar.
@MainActor
final class LibraryAutomationCoordinator: ObservableObject {
    static let shared = LibraryAutomationCoordinator()

    enum Phase: Equatable {
        case idle
        case identifying
        case enriching
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

            // Save identification results before enrichment phase
            library.saveROMsToDatabase(only: modifiedIDs)
        }

        // Phase 1.5: Apply MAME genre metadata from Progetto-SNAPS
        // This runs after identification but before enrichment so LaunchBox can override
        // First, ensure metadata is available (download if needed)
        if ProgettoSnapsService.shared.autoUpdateEnabled {
            _ = await ProgettoSnapsService.shared.downloadMetadataIfNeeded()

            let mamEROMs = scope.filter { rom in
                MAMEGenreService.shared.isMAME(rom.systemID) && rom.metadata?.genre == nil
            }
            if !mamEROMs.isEmpty {
                phase = .identifying
                progress = 0
                statusLine = "Downloading MAME metadata..."

                // Ensure metadata is downloaded
                if !ProgettoSnapsService.shared.isMetadataAvailable {
                    await ProgettoSnapsService.shared.downloadMetadata()
                }

                statusLine = "Applying MAME genres: 0% — …"
                let total = Double(mamEROMs.count)
                for (index, rom) in mamEROMs.enumerated() {
                    let shortName = rom.shortNameForMAME.lowercased()
                    if let genre = await ProgettoSnapsService.shared.getGenre(for: shortName),
                       let idx = library.roms.firstIndex(where: { $0.id == rom.id }) {
                        if library.roms[idx].metadata == nil {
                            library.roms[idx].metadata = ROMMetadata()
                        }
                        library.roms[idx].metadata?.genre = genre
                    }

                    let frac = Double(index + 1) / total
                    progress = frac
                    statusLine = "Applying MAME genres: \(Int(frac * 100))% — \(shortName)"

                    if index % 50 == 0 { await Task.yield() }
                }

                progress = 1
                statusLine = "Applying MAME genres: 100% — done"
                library.saveROMsToDatabase(only: mamEROMs.map { $0.id })
            }
        }

        // Phase 2: Enrichment — batch metadata (players, genre) from cached LibretroMetadataLibrary
        // This is pure in-memory O(1) dictionary lookups — no I/O, no network
        if !batchModifiedROMs.isEmpty {
            let identifiedROMs = batchModifiedROMs.filter { $0.crc32 != nil }
            if identifiedROMs.isEmpty {
                statusLine = "Enrichment skipped: no CRC data"
            } else {
                phase = .enriching
                progress = 0
                statusLine = "Enriching metadata: 0% — …"
                
                let total = Double(identifiedROMs.count)
                var enrichedCount = 0
                var enrichedROMs: [ROM] = []
                
                let groupedBySystem = Dictionary(grouping: identifiedROMs) { $0.systemID ?? "unknown" }
                
                for (systemID, romsForSystem) in groupedBySystem {
                    guard SystemDatabase.system(forID: systemID) != nil else { continue }
                    
                    await LibretroMetadataLibrary.shared.ensureLoaded(for: systemID)
                    
                    for var rom in romsForSystem {
                        guard rom.crc32 != nil else { continue }
                        
                        if rom.enrichmentAttempted {
                            enrichedCount += 1
                            progress = Double(enrichedCount) / total
                            continue
                        }
                        
                        var enriched = await LibretroMetadataLibrary.shared.enrich(rom: rom)
                        enriched.enrichmentAttempted = true
                        
                        if enriched.metadata?.players != rom.metadata?.players ||
                           enriched.metadata?.genre != rom.metadata?.genre {
                            enriched.enrichmentFailed = false
                        } else {
                            enriched.enrichmentFailed = true
                        }
                        enrichedROMs.append(enriched)
                        
                        enrichedCount += 1
                        progress = Double(enrichedCount) / total
                        if enrichedCount % 100 == 0 {
                            statusLine = "Enriching metadata: \(Int(progress * 100))% — \(systemID)"
                        }
                    }
                    
                    await Task.yield()
                }
                
                if !enrichedROMs.isEmpty {
                    let enrichedIDs = enrichedROMs.map { $0.id }
                    for enriched in enrichedROMs {
                        if let idx = library.roms.firstIndex(where: { $0.id == enriched.id }) {
                            library.roms[idx] = enriched
                        }
                    }
                    library.saveROMsToDatabase(only: enrichedIDs)
                }
                
                progress = 1
                statusLine = "Enriching metadata: 100% — done"
                
                try? await Task.sleep(nanoseconds: 500_000_000)
                await Task.yield()
            }
        }

        // Phase 3: Box art downloads (skip hidden ROMs)
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

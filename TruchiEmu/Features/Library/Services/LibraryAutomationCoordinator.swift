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

    // Transient dedupe so the box-art progress closure doesn't flood @Published
    // writes (which SwiftUI coalesces, leaving the status text frozen).
    private var lastBoxArtPercent: Int = -1

    private init() {}

    private var loc: LocalizationManager { LocalizationManager.shared }

    private func localizedStatus(_ key: String, _ args: String...) -> String {
        var result = loc.localized(key)
        for (index, arg) in args.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: arg)
        }
        return result
    }

    func runAfterLibraryUpdate(library: ROMLibrary, targetROMs: [ROM]? = nil) async {
        // Skip if any game is running — identification and box-art downloads
        // are network- and I/O-heavy and degrade gameplay performance.

        // Total-wall-time counter — emitted at the end so we can compare against the
        // 60-second scan+save+enrichment target. INFO level so it shows up in normal logs.
        let automationStart = Date()
        LoggerService.info(category: "LibraryAutomation", "=== POST-SCAN AUTOMATION STARTED (scope=\(targetROMs?.count ?? library.roms.count) ROMs) ===")

        // 1. Create a list to track ROMs modified in this batch
        var batchModifiedROMs: [ROM] = []

        // If targetROMs is provided, use it. Otherwise, fallback to full library.
        let scope = targetROMs ?? library.roms

        if RunningGamesTracker.shared.isGameRunning {
            #if LOG_DEBUG
            LoggerService.debug(category: "LibraryAutomation", "Skipping post-scan automation — game is running")
            #endif
            return
        }

        let needIdentify = scope.filter { $0.needsAutomaticIdentification && !$0.isHidden }
        let needArt = scope.filter { $0.needsAutomaticBoxArt && !$0.isHidden }
        LoggerService.info(category: "LibraryAutomation", "Phase scope: needIdentify=\(needIdentify.count) needArt=\(needArt.count)")

        guard !needIdentify.isEmpty || !needArt.isEmpty else {
            LoggerService.info(category: "LibraryAutomation", "=== POST-SCAN AUTOMATION SKIPPED (nothing to do) in \(String(format: "%.2f", Date().timeIntervalSince(automationStart)))s ===")
            return
        }

        // Warm-up delay: historically 2 s to let the UI settle after a library scan.
        // Removed — Phase 1 already runs in detached TaskGroup, so the main actor
        // is free to handle SwiftUI updates. Saves 2 s off the 60 s budget.

        // Pre-build a UUID → index map of library.roms once to give O(1) lookups
        // instead of per-ROM `firstIndex(where: { $0.id == rom.id })` (O(N) per call,
        // O(N²) per phase, millions of comparisons for a 1600-ROM library).
        let libraryIndexByID = Dictionary(uniqueKeysWithValues: library.roms.enumerated().map { ($0.element.id, $0.offset) })

        // Pre-fetch all candidate-system DATs up front, in parallel, before
        // running per-ROM identification. Eliminates the cold-cache network fetches
        // that were interleaved with hashing inside identifyByCRC at scan time
        // (one HTTP download per ambiguous-extension ROM × candidate system).
        let datPrefetchStart = Date()
        let candidateSystemIDs = Set(needIdentify.compactMap { $0.systemID })
        await withTaskGroup(of: Void.self) { group in
            for sysID in candidateSystemIDs {
                guard let system = SystemDatabase.system(forID: sysID) else { continue }
                group.addTask { _ = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system) }
            }
        }
        LoggerService.info(category: "LibraryAutomation", "Phase 0 (pre-fetch DATs for \(candidateSystemIDs.count) systems) finished in \(String(format: "%.2f", Date().timeIntervalSince(datPrefetchStart)))s")
        #if LOG_DEBUG
        LoggerService.debug(category: "LibraryAutomation", "Pre-fetched DATs for \(candidateSystemIDs.count) candidate systems")
        #endif

        isActive = true
        defer {
            isActive = false
            phase = .idle
            progress = 0
            statusLine = ""
        }

        // Phase 1: Identification — parallelized + grouped by system for maximum efficiency
        let phase1Start = Date()
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
                guard let system = SystemDatabase.system(forID: systemID) else { continue }

                // Load this system's DAT once for the whole system group instead of
                // re-funneling every ROM through the LibretroDatabaseLibrary actor.
                let systemDB = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)

                // Process ROMs of the same system in parallel batches
                let batchSize = 100
                for i in stride(from: 0, to: romsForSystem.count, by: batchSize) {
                    let batch = Array(romsForSystem[i..<min(i + batchSize, romsForSystem.count)])
                    
                    // Perform multi-ROM identification in background threads
                    let identificationResults = await Task.detached(priority: .userInitiated) {
                        await withTaskGroup(of: (UUID, ROMIdentifyResult).self) { group in
                            for rom in batch {
                                group.addTask {
                                    let result = await ROMIdentifierService.shared.identify(rom: rom, database: systemDB, preferNameMatch: true)
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
                    statusLine = localizedStatus("library.automation.identifyingSystem", systemName, "\(Int(done * 100))")
                    
                    await Task.yield()
                }
            }
            
            progress = 1
            statusLine = loc.localized("library.automation.identifyingDone")

            // Save identification results before enrichment phase
            library.saveROMsToDatabase(only: modifiedIDs)
        }
        LoggerService.info(category: "LibraryAutomation", "Phase 1 (identify \(needIdentify.count) ROMs) finished in \(String(format: "%.2f", Date().timeIntervalSince(phase1Start)))s")

        // Phase 1.5: Apply MAME genre metadata from Progetto-SNAPS
        // This runs after identification but before enrichment so LaunchBox can override
        // First, ensure metadata is available (download if needed)
        let phase15Start = Date()
        if ProgettoSnapsService.shared.autoUpdateEnabled {
            _ = await ProgettoSnapsService.shared.downloadMetadataIfNeeded()

            let mamEROMs = scope.filter { rom in
                MAMEGenreService.shared.isMAME(rom.systemID) && rom.metadata?.genre == nil
            }
            if !mamEROMs.isEmpty {
                phase = .identifying
                progress = 0
                statusLine = loc.localized("library.automation.downloadingMameMetadata")

                // Ensure metadata is downloaded
                if !ProgettoSnapsService.shared.isMetadataAvailable {
                    await ProgettoSnapsService.shared.downloadMetadata()
                }

                statusLine = loc.localized("library.automation.applyingMameGenresStart")
                let total = Double(mamEROMs.count)
                for (index, rom) in mamEROMs.enumerated() {
                    let shortName = rom.shortNameForMAME.lowercased()
                    if let genre = ProgettoSnapsService.shared.getGenre(for: shortName),
                       let idx = libraryIndexByID[rom.id] {
                        if library.roms[idx].metadata == nil {
                            library.roms[idx].metadata = ROMMetadata()
                        }
                        library.roms[idx].metadata?.genre = genre
                    }

                    let frac = Double(index + 1) / total
                    progress = frac
                    statusLine = localizedStatus("library.automation.applyingMameGenres", "\(Int(frac * 100))", shortName)

                    if index % 50 == 0 { await Task.yield() }
                }

                progress = 1
                statusLine = loc.localized("library.automation.applyingMameGenresDone")
                library.saveROMsToDatabase(only: mamEROMs.map { $0.id })
            }
        }
        LoggerService.info(category: "LibraryAutomation", "Phase 1.5 (MAME genre metadata) finished in \(String(format: "%.2f", Date().timeIntervalSince(phase15Start)))s")

        // Phase 1.75: Re-identify ROMs that have title but are missing libretro metadata (genre, publisher, etc.)
        // These ROMs were previously identified (e.g., via games.xml or earlier scan) but never enriched.
        // They skip Phase 1 because needsAutomaticIdentification = false (title exists), but need enrichment.
        // PARALLELIZED — previously a serial `for rom in ... { await identify(rom) }` loop that hogged
        // a single async thread for the entire phase. Now uses the same Task.detached + withTaskGroup
        // pattern as Phase 1, batches of 100.
        let romsMissingLibretroMetadata = scope.filter { rom in
            rom.metadata?.title != nil && !rom.metadata!.title!.isEmpty &&
            rom.metadata?.genre == nil && !rom.isHidden
        }
        
        let phase175Start = Date()
        if !romsMissingLibretroMetadata.isEmpty {
            phase = .identifying
            progress = 0
            statusLine = loc.localized("library.automation.identifyingMissingMetadataStart")
            
            let total = Double(romsMissingLibretroMetadata.count)
            var reidentifiedCount = 0
            var reidentifiedROMs: [ROM] = []
            
            let groupedBySystem = Dictionary(grouping: romsMissingLibretroMetadata) { $0.systemID ?? "unknown" }

            // Pre-fetch DATs for systems unique to Phase 1.75 (didn't appear in Phase 1)
            let phase175SystemIDs = Set(romsMissingLibretroMetadata.compactMap { $0.systemID })
            let missingDATSystems = phase175SystemIDs.subtracting(candidateSystemIDs)
            await withTaskGroup(of: Void.self) { group in
                for sysID in missingDATSystems {
                    guard let system = SystemDatabase.system(forID: sysID) else { continue }
                    group.addTask { _ = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system) }
                }
            }
            
            for (systemID, romsForSystem) in groupedBySystem {
                let systemName = SystemDatabase.system(forID: systemID)?.name ?? systemID
                guard let system = SystemDatabase.system(forID: systemID) else { continue }

                // Load this system's DAT once for the whole group (see Phase 1 rationale).
                let systemDB = await LibretroDatabaseLibrary.shared.fetchAndLoadDat(for: system)

                // Parallel batches — same shape as Phase 1.
                let batchSize = 100
                for i in stride(from: 0, to: romsForSystem.count, by: batchSize) {
                    let batch = Array(romsForSystem[i..<min(i + batchSize, romsForSystem.count)])

                    let batchResults = await Task.detached(priority: .userInitiated) {
                        await withTaskGroup(of: (UUID, ROMIdentifyResult?).self) { group in
                            for rom in batch {
                                group.addTask {
                                    let result = await ROMIdentifierService.shared.identify(rom: rom, database: systemDB, preferNameMatch: true)
                                    return (rom.id, result)
                                }
                            }
                            var results: [(UUID, ROMIdentifyResult?)] = []
                            for await res in group { results.append(res) }
                            return results
                        }
                    }.value

                    let batchLookup = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })

                    for (romID, result) in batchResults {
                        if let current = batchLookup[romID], let result = result,
                           let updated = library.applyIdentificationResult(result, to: current, persist: false, silent: true) {
                            var refreshed = updated
                            refreshed.enrichmentAttempted = false  // Will be enriched in Phase 2
                            refreshed.refreshDerivedFields()
                            reidentifiedROMs.append(refreshed)
                        }

                        reidentifiedCount += 1
                        let frac = Double(reidentifiedCount) / total
                        progress = frac
                        statusLine = localizedStatus("library.automation.identifyingMissingMetadata", "\(Int(frac * 100))", systemName)
                    }

                    await Task.yield()
                }
            }
            
            // Update library with re-identified ROMs using the prebuilt index (O(1) lookups)
            if !reidentifiedROMs.isEmpty {
                let reidentifiedIDs = reidentifiedROMs.map { $0.id }
                for reidentified in reidentifiedROMs {
                    if let idx = libraryIndexByID[reidentified.id], idx < library.roms.count {
                        library.roms[idx] = reidentified
                    }
                }
                library.saveROMsToDatabase(only: reidentifiedIDs)
            }
            
            progress = 1
            statusLine = loc.localized("library.automation.identifyingMissingMetadataDone")
        }
        LoggerService.info(category: "LibraryAutomation", "Phase 1.75 (re-identify \(romsMissingLibretroMetadata.count) ROMs missing libretro metadata) finished in \(String(format: "%.2f", Date().timeIntervalSince(phase175Start)))s")

        // Phase 2: Enrichment — batch metadata (players, genre) from cached LibretroMetadataLibrary
        // This is pure in-memory O(1) dictionary lookups — no I/O, no network
        // Run enrichment on ALL ROMs in scope that have CRC and haven't had enrichment attempted,
        // not just the ones newly identified in Phase 1 (some ROMs may have been previously identified
        // but still need enrichment to get libretro metadata like genre).
        let phase2Start = Date()
        let romsNeedingEnrichment = scope.filter { rom in
            rom.crc32 != nil && !rom.enrichmentAttempted && !rom.isHidden
        }
        
        if !romsNeedingEnrichment.isEmpty {
            let identifiedROMs = romsNeedingEnrichment
            if identifiedROMs.isEmpty {
                statusLine = loc.localized("library.automation.enrichmentSkipped")
            } else {
                phase = .enriching
                progress = 0
                statusLine = loc.localized("library.automation.enrichingMetadataStart")
                
                let total = Double(identifiedROMs.count)
                var enrichedCount = 0
                var enrichedROMs: [ROM] = []
                
                let groupedBySystem = Dictionary(grouping: identifiedROMs) { $0.systemID ?? "unknown" }
                
                for (systemID, romsForSystem) in groupedBySystem {
                    guard SystemDatabase.system(forID: systemID) != nil else { continue }
                    
                    await LibretroMetadataLibrary.shared.ensureLoaded(for: systemID)
                    
                    for rom in romsForSystem {
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
                            statusLine = localizedStatus("library.automation.enrichingMetadata", "\(Int(progress * 100))", systemID)
                        }
                    }
                    
                    await Task.yield()
                }
                
                if !enrichedROMs.isEmpty {
                    let enrichedIDs = enrichedROMs.map { $0.id }
                    for enriched in enrichedROMs {
                        if let idx = libraryIndexByID[enriched.id], idx < library.roms.count {
                            library.roms[idx] = enriched
                        }
                    }
                    library.saveROMsToDatabase(only: enrichedIDs)
                }
                
                progress = 1
                statusLine = loc.localized("library.automation.enrichingMetadataDone")

                // Half-second sleep removed — it was pure latency right before Phase 3
                // (box art download). The main actor already yields between phases,
                // and Phase 3 now runs in a non-blocking background Task from the caller.
            }
        }
        LoggerService.info(category: "LibraryAutomation", "Phase 2 (enrich \(romsNeedingEnrichment.count) ROMs) finished in \(String(format: "%.2f", Date().timeIntervalSince(phase2Start)))s")

        // The 60-second scan+save+enrichment target ENDS HERE. Phase 3 (box art
        // download) below is network-bound background work delegated back to the
        // caller — it runs in a non-awaited Task so we still want to time it for
        // profiling, but it's no longer part of the 60s budget.
        LoggerService.info(category: "LibraryAutomation", "=== POST-SCAN IDENTIFICATION+ENRICHMENT COMPLETE in \(String(format: "%.2f", Date().timeIntervalSince(automationStart)))s ===")

        // Phase 3: Box art + LaunchBox fallback. These are NETWORK-bound background
        // work — explicitly OUTSIDE the 60s scan+save+enrichment budget. Previously
        // they were `await`ed here, so the caller's SCAN-TO-ENRICHED timer ballooned
        // to hundreds of seconds while blocking identification results from returning.
        // Now we fire them on a detached background Task and return immediately so the
        // user-visible scan completes with metadata-rich ROMs in ~60s.
        let artTargets = scope.filter {
            !$0.isHidden && $0.needsAutomaticBoxArt
        }

        guard !artTargets.isEmpty else {
            LoggerService.info(category: "LibraryAutomation", "=== POST-SCAN AUTOMATION COMPLETE (no box art needed) in \(String(format: "%.2f", Date().timeIntervalSince(automationStart)))s ===")
            return
        }

        Task.detached(priority: .utility) { [scope, automationStart] in
            // Capture the @MainActor library reference for the box-art progress callback.
            let lib = library

            await MainActor.run {
                self.isActive = true
                self.phase = .downloadingArt
                self.progress = 0
                self.statusLine = self.loc.localized("library.automation.downloadingBoxArtStart")
            }

            let boxArtStart = Date()
            var lbStart = boxArtStart
            LoggerService.info(category: "LibraryAutomation", "Phase 3 (box art, background) started for \(artTargets.count) targets")
            await BoxArtService.shared.batchDownloadBoxArtLibretro(
                for: artTargets,
                library: lib,
                onItemProgress: { [weak self] completed, totalCount, fileLabel, _ in
                    guard let self = self else { return }
                    let frac = Double(completed) / max(Double(totalCount), 1)
                    let pct = Int(frac * 100)
                    Task { @MainActor in
                        self.progress = frac
                        guard pct != self.lastBoxArtPercent else { return }
                        self.lastBoxArtPercent = pct
                        self.statusLine = self.localizedStatus("library.automation.downloadingBoxArt", "\(pct)", fileLabel)
                    }
                }
            )
            LoggerService.info(category: "LibraryAutomation", "Phase 3 (box art, background) finished in \(String(format: "%.2f", Date().timeIntervalSince(boxArtStart)))s")

            // After Libretro CDN, try LaunchBox GamesDB for remaining ROMs still missing metadata/art
            let downloadAfterScan = await LaunchBoxGamesDBService.shared.downloadAfterScan
            if downloadAfterScan {
                let stillNeeded = scope.filter { rom in
                    !rom.hasBoxArt ||
                    (rom.metadata?.description?.isEmpty ?? true) ||
                    (rom.metadata?.developer?.isEmpty ?? true)
                }
                if !stillNeeded.isEmpty {
                    let lbStartActual = Date()
                    lbStart = lbStartActual
                    LoggerService.info(category: "LibraryAutomation", "Phase 3b (LaunchBox fallback, background) started for \(stillNeeded.count) ROMs")
                    await MetadataSyncCoordinator.shared.runAfterLibraryUpdate(
                        library: lib,
                        targetROMs: stillNeeded
                    )
                    LoggerService.info(category: "LibraryAutomation", "Phase 3b (LaunchBox fallback, background) finished in \(String(format: "%.2f", Date().timeIntervalSince(lbStart)))s")
                }
            }

            // RetroAchievements matching is intentionally NOT part of the scan pipeline.
            // It requires a full-file hash per ROM (RomHasher) and previously turned a
            // 120s scan into 12+ minutes / 500s+. RA sync already happens per-game at
            // launch time (GameLauncher), so bulk matching here is redundant with that
            // and must not dominate scan time. Kept out of the timed total below.

            Task { @MainActor in
                self.isActive = false
                self.progress = 1
                self.statusLine = self.loc.localized("library.automation.downloadingBoxArtDone")
                self.phase = .idle
            }
            LoggerService.info(category: "LibraryAutomation", "=== POST-SCAN AUTOMATION COMPLETE (incl. background box art + LaunchBox) in \(String(format: "%.2f", Date().timeIntervalSince(automationStart)))s ===")
            LoggerService.info(category: "LibraryAutomation", "PHASE BREAKDOWN :: total=\(String(format: "%.2f", Date().timeIntervalSince(automationStart)))s boxArt=\(String(format: "%.2f", Date().timeIntervalSince(boxArtStart)))s launchBox=\(String(format: "%.2f", Date().timeIntervalSince(lbStart)))s")
        }
    }
}

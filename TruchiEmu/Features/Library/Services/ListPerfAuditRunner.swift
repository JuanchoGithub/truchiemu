import Foundation
import QuartzCore

/// One-shot library filter-switch perf audit.
///
/// Triggered from `TruchiEmuApp.init()` only when the environment variable
/// `TRUCHI_LIST_PERF_AUDIT == "1"`. Dead code path when the env var is unset.
///
/// Drives the real UI switch path (posts `.navigateToFilter`, the same
/// notification the sidebar menu uses) and measures per switch:
///   - firstUpdateMs: time until LibraryViewModel publishes a new displayedROMs
///     array (data pipeline: filter + sort)
///   - settleMs:      time from switch start to the first main-queue hop after
///     the last published update (perceived switch latency, incl. rendering)
///   - busyMs:        total main-thread time blocked in >20ms chunks between
///     hops (SwiftUI render stalls)
///
/// The view mode under test comes from `TRUCHI_LIST_PERF_MODE` (list|grid|holo)
/// and is written to AppSettings before the library view first appears.
///
/// Writes `report.md` under ~/Library/Application Support/TruchiEmu/ListPerfAudit/,
/// prints one line per switch, then exits.
///
/// Run from the terminal:
///   TRUCHI_LIST_PERF_AUDIT=1 TRUCHI_LIST_PERF_MODE=list \
///     /path/to/TruchiEmu.app/Contents/MacOS/TruchiEmu
enum ListPerfAuditRunner {

    static func runIfNeeded(library: ROMLibrary) {
        let env = ProcessInfo.processInfo.environment
        guard env["TRUCHI_LIST_PERF_AUDIT"] == "1" else { return }
        let mode = env["TRUCHI_LIST_PERF_MODE"] ?? "list"
        MainActor.assumeIsolated {
            // Restore the user's saved mode when the audit finishes.
            let savedMode = AppSettings.getString("gridViewMode")
            // Must land before LibraryGridView.onAppear restores the saved mode.
            AppSettings.set("gridViewMode", value: mode)
            Task { @MainActor in
                await Self.run(library: library, mode: mode, savedMode: savedMode)
            }
        }
    }

    // MARK: - Audit execution

    private struct SwitchResult {
        let target: String
        let firstUpdateMs: Double
        let settleMs: Double
        let busyMs: Double
        let updates: Int
        let romCount: Int
    }

    @MainActor
    private static func run(library: ROMLibrary, mode: String, savedMode: String?) async {
        print("[ListPerfAudit] mode=\(mode) waiting for library…")
        let loadDeadline = Date().addingTimeInterval(60)
        while Date() < loadDeadline {
            if !library.isScanning && library.roms.count > 0 { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard library.roms.count > 0 else {
            print("[ListPerfAudit] library empty; aborting")
            exit(1)
        }
        // Let launch-time work (onAppear art resolution, metadata sync) drain.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // all <-> arcade (mame) <-> nes, three full cycles.
        let sequence = ["system-mame", "all", "system-nes", "all",
                        "system-mame", "all", "system-nes", "all"]
        var results: [SwitchResult] = []
        for target in sequence {
            results.append(await measureSwitch(to: target))
        }

        writeReport(mode: mode, library: library, results: results)
        if let savedMode {
            AppSettings.set("gridViewMode", value: savedMode)
        }
        exit(0)
    }

    @MainActor
    private static func measureSwitch(to target: String) async -> SwitchResult {
        var updateTimes: [CFTimeInterval] = []
        var updateCounts: [Int] = []
        let sink = NotificationCenter.default
            .publisher(for: .libraryDisplayedROMsDidChange)
            .sink { note in
                updateTimes.append(CACurrentMediaTime())
                updateCounts.append((note.object as? Int) ?? -1)
            }

        let t0 = CACurrentMediaTime()
        NotificationCenter.default.post(name: .navigateToFilter, object: target)

        // Observe the main queue for 2s. A hop that returns late means the
        // main thread was blocked rendering; chunks >20ms count as busy time.
        // Hops are spaced 5ms so the runloop can idle between them (a tight
        // spin would keep the main thread hot and pollute profiles).
        let observationEnd = t0 + 2.0
        var busyMs = 0.0
        var settleMs = 0.0
        var seenUpdates = 0
        var lastHop = t0
        while CACurrentMediaTime() < observationEnd {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { cont.resume() }
            }
            let now = CACurrentMediaTime()
            let delta = now - lastHop
            if delta > 0.020 { busyMs += delta * 1000 }
            lastHop = now
            if updateTimes.count > seenUpdates {
                seenUpdates = updateTimes.count
                // Extends with every published update; the last extension is
                // the perceived switch latency.
                settleMs = (now - t0) * 1000
            }
        }
        sink.cancel()

        let firstUpdateMs = updateTimes.first.map { ($0 - t0) * 1000 } ?? -1
        print("[ListPerfAudit] -> \(target) "
              + "firstUpdate=\(String(format: "%.1f", firstUpdateMs))ms "
              + "settle=\(String(format: "%.1f", settleMs))ms "
              + "busy=\(String(format: "%.1f", busyMs))ms "
              + "updates=\(seenUpdates) roms=\(updateCounts.last ?? -1)")
        return SwitchResult(target: target, firstUpdateMs: firstUpdateMs, settleMs: settleMs,
                            busyMs: busyMs, updates: seenUpdates, romCount: updateCounts.last ?? -1)
    }

    // MARK: - Report

    @MainActor
    private static func writeReport(mode: String, library: ROMLibrary, results: [SwitchResult]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TruchiEmu/ListPerfAudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var md = "# Library filter-switch perf audit\n\n"
        md += "- view mode: \(mode)\n"
        md += "- library size: \(library.roms.count)\n"
        md += "- rom counts: mame=\(library.romCounts["mame"] ?? 0) nes=\(library.romCounts["nes"] ?? 0)\n\n"
        md += "| target | firstUpdateMs | settleMs | busyMs | updates | roms |\n"
        md += "|---|---|---|---|---|---|\n"
        for r in results {
            md += "| \(r.target) | \(String(format: "%.1f", r.firstUpdateMs)) | \(String(format: "%.1f", r.settleMs)) | \(String(format: "%.1f", r.busyMs)) | \(r.updates) | \(r.romCount) |\n"
        }
        let url = dir.appendingPathComponent("report.md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        print("[ListPerfAudit] report: \(url.path)")
    }
}

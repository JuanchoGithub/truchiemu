import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore

// MARK: - Counters

/// Cheap main-thread-only counters consumed by the env-gated scroll perf
/// audit (`ScrollPerfAuditRunner`). Every mutation happens on the main thread
/// (collection-view item configure, `thumbnailSync`'s call sites, and the
/// prefetch delegate callback are all main-queue), so plain values are
/// race-free without atomics. Adds cost ~ns; always compiled so Release
/// builds can be audited too.
enum ScrollPerfCounters {
    nonisolated(unsafe) static var gridItemsCreated = 0
    nonisolated(unsafe) static var gridItemsReused = 0
    nonisolated(unsafe) static var holoItemsCreated = 0
    nonisolated(unsafe) static var holoItemsReused = 0
    nonisolated(unsafe) static var thumbnailSyncCalls = 0
    nonisolated(unsafe) static var thumbnailSyncMainThreadNs: Int64 = 0
    nonisolated(unsafe) static var thumbnailSyncColdDiskReads = 0
    nonisolated(unsafe) static var prefetchIndexPaths = 0
}

// MARK: - Display-link scroll FPS

/// Counts display refreshes on which the scroll position had advanced since
/// the previous refresh — the rendered scroll FPS. The main-thread audit loop
/// publishes the latest clip-view origin into `latestOriginY`; the display-link
/// callback (its own thread) compares it across ticks. Reads/writes are single
/// aligned Doubles/Ints shared with one producer and one consumer thread pair,
/// which is benign for an audit tool that exits after the run.
final class ScrollDisplayLink {
    static let shared = ScrollDisplayLink()
    private var link: CVDisplayLink?

    // Written by the audit loop (main thread), read by the callback thread.
    nonisolated(unsafe) var latestOriginY: Double = 0
    // Callback-thread state.
    private nonisolated(unsafe) var lastSeenY: Double = 0
    private nonisolated(unsafe) var advancedTicks = 0
    private nonisolated(unsafe) var totalTicks = 0

    func record(originY: Double) { latestOriginY = originY }

    func start() {
        var newLink: CVDisplayLink?
        var createError = CVDisplayLinkCreateWithActiveCGDisplays(&newLink)
        if createError != kCVReturnSuccess || newLink == nil {
            // Fall back to the main display if the active-displays lookup fails.
            createError = CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &newLink)
        }
        guard createError == kCVReturnSuccess, let newLink else {
            print("[ScrollPerfAudit] CVDisplayLink create failed: \(createError)")
            return
        }
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, _ in
            let counter = ScrollDisplayLink.shared
            counter.totalTicks += 1
            let y = counter.latestOriginY
            if y != counter.lastSeenY {
                counter.advancedTicks += 1
                counter.lastSeenY = y
            }
            return kCVReturnSuccess
        }
        let setError = CVDisplayLinkSetOutputCallback(newLink, callback, nil)
        guard setError == kCVReturnSuccess else {
            print("[ScrollPerfAudit] CVDisplayLinkSetOutputCallback failed: \(setError)")
            return
        }
        CVDisplayLinkStart(newLink)
        link = newLink
    }

    func stopAndCollect() -> (advanced: Int, total: Int) {
        if let link { CVDisplayLinkStop(link) }
        link = nil
        let result = (advancedTicks, totalTicks)
        advancedTicks = 0
        totalTicks = 0
        lastSeenY = latestOriginY
        return result
    }
}

// MARK: - Scroll perf audit

/// One-shot library scroll perf audit.
///
/// Triggered from `TruchiEmuApp.init()` only when the environment variable
/// `TRUCHI_SCROLL_PERF_AUDIT == "1"`. Dead code path when the env var is unset.
///
/// Drives the real library view through scripted scroll bursts on the real
/// library and measures, per burst:
///   - busyMs:   main-thread time blocked, approximated by >20 ms gaps between
///     4 ms-cadence main-queue samples (SwiftUI render / cell configure /
///     synchronous I/O stalls all show up here)
///   - stalls:   sample gaps > 50 ms (dropped frames the user feels as a hitch)
///   - rFps:     rendered scroll FPS — display refreshes per second on which
///     the clip-view origin advanced. Smooth scrolling pins this to the
///     display refresh rate; skipped commits drop it.
///   - counters: NSCollectionViewItem created vs reused (cell recycling),
///     `thumbnailSync` main-thread time and cold disk reads (synchronous
///     image I/O), prefetch batch size
///
/// Scroll bursts are delivered as synthesized `NSEvent` scroll-wheel events fed
/// to `NSScrollView.scrollWheel(with:)` — AppKit's real responder entry point
/// for wheel events (live-scroll machinery, content preparation, recycling,
/// prefetching), minus the window server. The per-event delta is calibrated
/// against a probe scroll so bursts run at a consistent ~4000 px/s. If wheel
/// delivery does not move the view, the audit falls back to programmatic
/// clip-view scrolling.
///
/// The view mode under test comes from `TRUCHI_SCROLL_PERF_MODE` (grid|holo)
/// and the group-view boxart display mode from
/// `TRUCHI_SCROLL_PERF_DISPLAY` (fillBlurred|cropSquare); both are written to
/// AppSettings before the library view first appears. The window is centered
/// on screen (rendering must be live for the numbers to mean anything) and
/// its original frame is restored before exit.
///
/// Writes `report.md` under ~/Library/Application Support/TruchiEmu/ScrollPerfAudit/,
/// prints one line per burst, restores the saved settings, then exits.
///
/// Run from the terminal:
///   TRUCHI_SCROLL_PERF_AUDIT=1 TRUCHI_SCROLL_PERF_MODE=grid \
///     TRUCHI_SCROLL_PERF_DISPLAY=fillBlurred \
///     /path/to/TruchiEmu.app/Contents/MacOS/TruchiEmu
enum ScrollPerfAuditRunner {

    private struct BurstResult {
        let label: String
        let durationMs: Double
        let distancePx: CGFloat
        let busyMs: Double
        let maxHopMs: Double
        let stalls: Int
        let settleBusyMs: Double
        let settleMaxHopMs: Double
        let renderedFps: Double
        let refreshRate: Double
        let gridCreated: Int
        let gridReused: Int
        let holoCreated: Int
        let holoReused: Int
        let thumbSyncMs: Double
        let thumbColdReads: Int
        let prefetchPaths: Int
        let visibleItems: Int
    }

    private struct CounterSnapshot {
        let gridCreated: Int
        let gridReused: Int
        let holoCreated: Int
        let holoReused: Int
        let syncCalls: Int
        let syncNs: Int64
        let coldReads: Int
        let prefetch: Int
    }

    private static func snapshotCounters() -> CounterSnapshot {
        CounterSnapshot(
            gridCreated: ScrollPerfCounters.gridItemsCreated,
            gridReused: ScrollPerfCounters.gridItemsReused,
            holoCreated: ScrollPerfCounters.holoItemsCreated,
            holoReused: ScrollPerfCounters.holoItemsReused,
            syncCalls: ScrollPerfCounters.thumbnailSyncCalls,
            syncNs: ScrollPerfCounters.thumbnailSyncMainThreadNs,
            coldReads: ScrollPerfCounters.thumbnailSyncColdDiskReads,
            prefetch: ScrollPerfCounters.prefetchIndexPaths
        )
    }

    static func runIfNeeded(library: ROMLibrary) {
        let env = ProcessInfo.processInfo.environment
        guard env["TRUCHI_SCROLL_PERF_AUDIT"] == "1" else { return }
        let mode = env["TRUCHI_SCROLL_PERF_MODE"] ?? "grid"
        let display = env["TRUCHI_SCROLL_PERF_DISPLAY"] ?? "fillBlurred"
        MainActor.assumeIsolated {
            // Restore the user's saved settings when the audit finishes. Must
            // land before LibraryGridView.onAppear reads them.
            let savedMode = AppSettings.getString("gridViewMode")
            let savedDisplay = AppSettings.getString("library_boxart_display_mode")
            AppSettings.set("gridViewMode", value: mode)
            AppSettings.set("library_boxart_display_mode", value: display)
            Task { @MainActor in
                await Self.run(library: library, mode: mode, display: display,
                               savedMode: savedMode, savedDisplay: savedDisplay)
            }
        }
    }

    // MARK: - Audit execution

    @MainActor
    private static func run(library: ROMLibrary, mode: String, display: String,
                           savedMode: String?, savedDisplay: String?) async {
        print("[ScrollPerfAudit] mode=\(mode) display=\(display) waiting for library…")
        let loadDeadline = Date().addingTimeInterval(60)
        while Date() < loadDeadline {
            if !library.isScanning && library.roms.count > 0 { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard library.roms.count > 0 else {
            print("[ScrollPerfAudit] library empty; aborting")
            exit(1)
        }
        // Let launch-time work (onAppear art resolution, metadata sync) drain.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Largest filter for the biggest scroll range.
        NotificationCenter.default.post(name: .navigateToFilter, object: "all")
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        guard let scrollView = await waitForScrollView(timeout: 10) else {
            print("[ScrollPerfAudit] no NSCollectionView scroll view found; aborting")
            exit(1)
        }
        guard let window = scrollView.window else {
            print("[ScrollPerfAudit] scroll view has no window; aborting")
            exit(1)
        }

        // Rendering must be live or every metric is meaningless: center the
        // window on the main screen, bring it front, activate the app.
        let originalWindowFrame = window.frame
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let cv = scrollView.documentView as? NSCollectionView
        print("[ScrollPerfAudit] window='\(window.title)' frame=\(NSStringFromRect(window.frame)) "
              + "occlusionVisible=\(window.occlusionState.contains(.visible)) "
              + "visibleItems=\(cv?.indexPathsForVisibleItems().count ?? -1) "
              + "contentHeight=\(scrollView.contentView.documentRect.height)")

        warpCursor(over: scrollView)
        let calibration = await calibrateWheel(scrollView)
        if calibration == nil {
            print("[ScrollPerfAudit] wheel events ineffective; using programmatic scrolling")
            // Programmatic scroll(to:) only drives NSCollectionView content
            // preparation when the clip view posts bounds-changed notifications
            // (the holo grid enables this; the boxart grid relies on the live
            // scroll machinery). Enable it so the fallback measures real cell
            // configure/render work.
            scrollView.contentView.postsBoundsChangedNotifications = true
        }
        resetToTop(scrollView)
        try? await Task.sleep(nanoseconds: 800_000_000)

        var results: [BurstResult] = []
        results.append(await burst(scrollView, label: "down-cold", deltaY: -1, calibration: calibration))
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        results.append(await burst(scrollView, label: "down-cold2", deltaY: -1, calibration: calibration))
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        results.append(await burst(scrollView, label: "up-warm", deltaY: 1, calibration: calibration))
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        results.append(await burst(scrollView, label: "down-warm", deltaY: -1, calibration: calibration))

        writeReport(mode: mode, display: display, romCount: library.roms.count,
                    driver: calibration != nil ? "wheelEvents" : "programmatic", results: results)
        // Restore everything the audit touched.
        window.setFrame(originalWindowFrame, display: false)
        if let savedMode {
            AppSettings.set("gridViewMode", value: savedMode)
        }
        if let savedDisplay {
            AppSettings.set("library_boxart_display_mode", value: savedDisplay)
        }
        exit(0)
    }

    // MARK: - Burst measurement

    @MainActor
    private static func burst(_ scrollView: NSScrollView, label: String,
                              deltaY: CGFloat, calibration: (deltaUnits: CGFloat, windowPoint: NSPoint)?) async -> BurstResult {
        let clip = scrollView.contentView
        let startOriginY = clip.bounds.origin.y
        let c0 = snapshotCounters()
        let displayLink = ScrollDisplayLink.shared
        displayLink.record(originY: startOriginY)
        displayLink.start()

        let t0 = CACurrentMediaTime()
        var lastSample = t0
        var busyMs = 0.0
        var maxHopMs = 0.0
        var stalls = 0

        let iterations = 400
        let sampleIntervalNs: UInt64 = 4_000_000
        for _ in 0..<iterations {
            if let calibration {
                if let event = makeWheelEvent(for: scrollView, at: calibration.windowPoint, delta: deltaY * calibration.deltaUnits) {
                    scrollView.scrollWheel(with: event)
                }
            } else {
                clip.scroll(to: CGPoint(x: clip.bounds.origin.x,
                                        y: clip.bounds.origin.y + deltaY * 16))
                scrollView.reflectScrolledClipView(clip)
            }
            try? await Task.sleep(nanoseconds: sampleIntervalNs)

            let now = CACurrentMediaTime()
            let gapMs = (now - lastSample) * 1000
            if gapMs > 20 { busyMs += gapMs }
            if gapMs > 50 { stalls += 1 }
            maxHopMs = max(maxHopMs, gapMs)
            lastSample = now
            displayLink.record(originY: clip.bounds.origin.y)
        }

        let scrollDuration = CACurrentMediaTime() - t0
        let (advancedTicks, totalTicks) = displayLink.stopAndCollect()

        // Tail: the gesture settle (holo flips isScrolling false ~300 ms after
        // the last event and swaps every visible card back to the full card).
        var settleBusyMs = 0.0
        var settleMaxHopMs = 0.0
        var settleLast = CACurrentMediaTime()
        displayLink.start()
        for _ in 0..<250 {
            try? await Task.sleep(nanoseconds: sampleIntervalNs)
            let now = CACurrentMediaTime()
            let gapMs = (now - settleLast) * 1000
            if gapMs > 20 { settleBusyMs += gapMs }
            settleMaxHopMs = max(settleMaxHopMs, gapMs)
            settleLast = now
            displayLink.record(originY: clip.bounds.origin.y)
        }
        _ = displayLink.stopAndCollect()

        let duration = scrollDuration
        let c1 = snapshotCounters()
        let distance = abs(clip.bounds.origin.y - startOriginY)
        let renderedFps = duration > 0 ? Double(advancedTicks) / duration : 0
        let refreshRate = duration > 0 ? Double(totalTicks) / duration : 0
        let thumbSyncMs = Double(c1.syncNs - c0.syncNs) / 1_000_000
        let visibleItems = scrollView.documentView is NSCollectionView
            ? (scrollView.documentView as! NSCollectionView).indexPathsForVisibleItems().count
            : -1

        let result = BurstResult(
            label: label,
            durationMs: duration * 1000,
            distancePx: distance,
            busyMs: busyMs,
            maxHopMs: maxHopMs,
            stalls: stalls,
            settleBusyMs: settleBusyMs,
            settleMaxHopMs: settleMaxHopMs,
            renderedFps: renderedFps,
            refreshRate: refreshRate,
            gridCreated: c1.gridCreated - c0.gridCreated,
            gridReused: c1.gridReused - c0.gridReused,
            holoCreated: c1.holoCreated - c0.holoCreated,
            holoReused: c1.holoReused - c0.holoReused,
            thumbSyncMs: thumbSyncMs,
            thumbColdReads: c1.coldReads - c0.coldReads,
            prefetchPaths: c1.prefetch - c0.prefetch,
            visibleItems: visibleItems
        )
        print("[ScrollPerfAudit] \(label) "
              + "dur=\(String(format: "%.0f", result.durationMs))ms "
              + "dist=\(String(format: "%.0f", result.distancePx))px "
              + "busy=\(String(format: "%.0f", result.busyMs))ms "
              + "stalls=\(result.stalls) "
              + "maxHop=\(String(format: "%.0f", result.maxHopMs))ms "
              + "settleBusy=\(String(format: "%.0f", result.settleBusyMs))ms "
              + "settleHop=\(String(format: "%.0f", result.settleMaxHopMs))ms "
              + "rFps=\(String(format: "%.0f", result.renderedFps))/\(String(format: "%.0f", result.refreshRate)) "
              + "created=\(result.gridCreated + result.holoCreated) "
              + "reused=\(result.gridReused + result.holoReused) "
              + "thumbSync=\(String(format: "%.0f", result.thumbSyncMs))ms "
              + "coldReads=\(result.thumbColdReads) "
              + "prefetch=\(result.prefetchPaths) "
              + "visible=\(result.visibleItems)")
        return result
    }

    // MARK: - View discovery and scroll driving

    @MainActor
    private static func waitForScrollView(timeout: TimeInterval) async -> NSScrollView? {
        let deadline = Date().addingTimeInterval(timeout)
        var logged = false
        while Date() < deadline {
            var candidates: [(sv: NSScrollView, items: Int, window: String)] = []
            for window in NSApp.windows where window.isVisible {
                for sv in collectCollectionViewScrollViews(in: window.contentView) {
                    let cv = sv.documentView as? NSCollectionView
                    let items = (0..<max(1, cv?.numberOfSections ?? 1))
                        .reduce(0) { $0 + (cv?.numberOfItems(inSection: $1) ?? 0) }
                    candidates.append((sv, items, window.title))
                }
            }
            if !logged, !candidates.isEmpty {
                logged = true
                for c in candidates {
                    print("[ScrollPerfAudit] candidate sv items=\(c.items) window='\(c.window)'")
                }
            }
            if let best = candidates.max(by: { $0.items < $1.items }), best.items > 0 {
                return best.sv
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private static func collectCollectionViewScrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        var result: [NSScrollView] = []
        if let sv = view as? NSScrollView, sv.documentView is NSCollectionView {
            result.append(sv)
        }
        for sub in view.subviews {
            result.append(contentsOf: collectCollectionViewScrollViews(in: sub))
        }
        return result
    }

    /// Moves the cursor over the scroll view so posted wheel events route to
    /// the grid exactly as a real user's would. AppKit screen coordinates are
    /// bottom-left origin; CG is top-left, so flip within the window's screen
    /// (single-display assumption — this is a dev-machine audit tool).
    /// Returns the CG point the cursor was warped to; synthesized events must
    /// carry this location or the window server routes them to (0,0) — the
    /// menu bar — and they never reach the grid.
    @MainActor
    @discardableResult
    private static func warpCursor(over scrollView: NSScrollView) -> CGPoint? {
        guard let window = scrollView.window,
              let screen = window.screen ?? NSScreen.main else { return nil }
        let rectInWindow = scrollView.convert(scrollView.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        let cgPoint = CGPoint(x: rectOnScreen.midX, y: screen.frame.maxY - rectOnScreen.midY)
        let error = CGWarpMouseCursorPosition(cgPoint)
        print("[ScrollPerfAudit] cursor warp to \(NSStringFromPoint(cgPoint)) error=\(error.rawValue)")
        return cgPoint
    }

    /// Probes the real wheel path and returns the per-event delta (in wheel
    /// units) that yields ~4000 px/s at the burst's 4 ms cadence, plus the
    /// window point to stamp on the events. Returns nil when wheel delivery
    /// does not move the view.
    @MainActor
    private static func calibrateWheel(_ scrollView: NSScrollView) async -> (deltaUnits: CGFloat, windowPoint: NSPoint)? {
        let clip = scrollView.contentView
        let windowPoint = CGPoint(x: scrollView.convert(scrollView.bounds, to: nil).midX,
                                  y: scrollView.convert(scrollView.bounds, to: nil).midY)
        let start = clip.bounds.origin.y
        let probeUnits: CGFloat = 12
        for _ in 0..<10 {
            // Downward: the document starts at the top, so upward deltas would
            // rubber-band into nothing and read as "ineffective".
            guard let event = makeWheelEvent(for: scrollView, at: windowPoint, delta: -probeUnits) else { return nil }
            scrollView.scrollWheel(with: event)
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        let moved = clip.bounds.origin.y - start
        guard abs(moved) > 5 else { return nil }
        let pxPerUnit = abs(moved) / (10 * probeUnits)
        // Target ~4000 px/s at one event per 4 ms (250 events/s).
        let deltaUnits = 4000.0 / 250.0 / pxPerUnit
        print("[ScrollPerfAudit] wheel probe moved \(String(format: "%.0f", moved))px "
              + "(\(String(format: "%.1f", pxPerUnit)) px/unit) → "
              + "\(String(format: "%.2f", deltaUnits)) units/event")
        resetToTop(scrollView)
        return (deltaUnits, windowPoint)
    }

    @MainActor
    private static func makeWheelEvent(for scrollView: NSScrollView, at windowPoint: NSPoint,
                                       delta: CGFloat) -> NSEvent? {
        guard let window = scrollView.window,
              let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                    wheel1: Int32(delta), wheel2: 0, wheel3: 0) else { return nil }
        // The event carries its location in CG global (top-left origin)
        // coordinates; convert the AppKit window point accordingly.
        let screenPoint = window.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
        let screenFrame = (window.screen ?? NSScreen.main)?.frame ?? .zero
        cgEvent.location = CGPoint(x: screenPoint.x, y: screenFrame.maxY - screenPoint.y)
        return NSEvent(cgEvent: cgEvent)
    }

    @MainActor
    private static func resetToTop(_ scrollView: NSScrollView) {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Report

    @MainActor
    private static func writeReport(mode: String, display: String, romCount: Int,
                                    driver: String, results: [BurstResult]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TruchiEmu/ScrollPerfAudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var md = "# Library scroll perf audit\n\n"
        md += "- view mode: \(mode)\n"
        md += "- boxart display mode: \(display)\n"
        md += "- library size: \(romCount)\n"
        md += "- scroll driver: \(driver)\n\n"
        md += "Metrics: `busy` = main-thread ms in >20ms gaps between 4ms samples; "
        md += "`stalls` = gaps >50ms; `rFps` = display refreshes per second on which the "
        md += "scroll origin advanced (renderFps / display refresh rate); "
        md += "`created`/`reused` = NSCollectionViewItem recycling; "
        md += "`thumbSync` = synchronous main-thread image-I/O ms inside `ImageCache.thumbnailSync`.\n\n"
        md += "| burst | durMs | distPx | busyMs | maxHopMs | stalls>50 | settleBusyMs | settleHopMs | rFps | refresh | created | reused | thumbSyncMs | coldReads | prefetch | visible |\n"
        md += "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        for r in results {
            md += "| \(r.label) "
            + "| \(String(format: "%.0f", r.durationMs)) "
            + "| \(String(format: "%.0f", r.distancePx)) "
            + "| \(String(format: "%.0f", r.busyMs)) "
            + "| \(String(format: "%.0f", r.maxHopMs)) "
            + "| \(r.stalls) "
            + "| \(String(format: "%.0f", r.settleBusyMs)) "
            + "| \(String(format: "%.0f", r.settleMaxHopMs)) "
            + "| \(String(format: "%.0f", r.renderedFps)) "
            + "| \(String(format: "%.0f", r.refreshRate)) "
            + "| \(r.gridCreated + r.holoCreated) "
            + "| \(r.gridReused + r.holoReused) "
            + "| \(String(format: "%.0f", r.thumbSyncMs)) "
            + "| \(r.thumbColdReads) "
            + "| \(r.prefetchPaths) "
            + "| \(r.visibleItems) |\n"
        }
        let url = dir.appendingPathComponent("report.md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        print("[ScrollPerfAudit] report: \(url.path)")
    }
}

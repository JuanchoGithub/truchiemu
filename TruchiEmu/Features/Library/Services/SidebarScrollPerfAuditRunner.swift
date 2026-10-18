import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore

// MARK: - Counters

/// Cheap main-thread-only counters consumed by the env-gated sidebar scroll
/// perf audit (`SidebarScrollPerfAuditRunner`). Every mutation happens on the
/// main thread (sidebar body/row builds, `emuImage` calls from row bodies,
/// `visibleSidebarFilters` reads are all main-queue), so plain values are
/// race-free without atomics. Adds cost ~ns; always compiled so Release
/// builds can be audited too.
enum SidebarPerfCounters {
    nonisolated(unsafe) static var sidebarBodyBuilds = 0
    nonisolated(unsafe) static var rowBuilds = 0
    nonisolated(unsafe) static var iconCalls = 0
    nonisolated(unsafe) static var iconMainNs: Int64 = 0
    nonisolated(unsafe) static var iconColdProbes = 0
    nonisolated(unsafe) static var visibleListBuilds = 0

    static func noteSidebarBody() { sidebarBodyBuilds += 1 }
    static func noteRow() { rowBuilds += 1 }
    static func noteIconCall(nanoseconds: UInt64) {
        iconCalls += 1
        iconMainNs &+= Int64(nanoseconds)
    }
    static func noteIconColdProbe() { iconColdProbes += 1 }
    static func noteVisibleList() { visibleListBuilds += 1 }
}

// MARK: - Sidebar scroll perf audit

/// One-shot sidebar scroll perf audit.
///
/// Triggered from `TruchiEmuApp.init()` only when the environment variable
/// `TRUCHI_SIDEBAR_SCROLL_AUDIT == "1"`. Dead code path when the env var is unset.
///
/// Drives the real system sidebar through scripted scroll bursts and measures,
/// per burst:
///   - busyMs:   main-thread time blocked, approximated by >20 ms gaps between
///     4 ms-cadence main-queue samples (row builds, synchronous icon I/O,
///     SwiftUI render stalls all show up here)
///   - stalls:   sample gaps > 50 ms (dropped frames the user feels as a hitch)
///   - rFps:     rendered scroll FPS — display refreshes per second on which
///     the clip-view origin advanced (see `ScrollDisplayLink`)
///   - counters: sidebar body builds, row builds, `emuImage(size:132)`
///     main-thread time + cold probes (cache misses that fall through to
///     bundle/disk lookups), `visibleSidebarFilters` array rebuilds
///
/// Scroll bursts are delivered as synthesized trackpad-style scroll events:
/// began → changed… → ended phases, posted through the most real driver the
/// machine allows, in order: HID tap (`CGEvent.post`, full window-server
/// path), `NSApp.sendEvent` (responder routing), direct
/// `NSScrollView.scrollWheel(with:)`, and programmatic clip-view scrolling as
/// a last resort. SwiftUI's `HostingScrollView` ignores window-less wheel
/// events, so the direct driver usually fails for the sidebar — the probe
/// detects this and falls through. Driving the real input path matters
/// because the sidebar's scroll range is short and dominated by rubber-band
/// bounce, pinned-header re-layout, and hover enter/exit churn as rows pass
/// under the cursor — none of which programmatic scrolling reproduces.
///
/// Writes `report.md` under ~/Library/Application Support/TruchiEmu/SidebarScrollPerfAudit/,
/// prints one line per burst, then exits.
///
/// Run from the terminal:
///   TRUCHI_SIDEBAR_SCROLL_AUDIT=1 /path/to/TruchiEmu.app/Contents/MacOS/TruchiEmu
enum SidebarScrollPerfAuditRunner {

    private enum ScrollDriver: String {
        case hidPost = "hidEventTap"
        case sendEvent = "nsAppSendEvent"
        case directWheel = "directScrollWheel"
        case programmatic = "programmatic"
    }

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
        let bodyBuilds: Int
        let rowBuilds: Int
        let iconMs: Double
        let iconCalls: Int
        let iconColdProbes: Int
        let visibleListBuilds: Int
    }

    private struct CounterSnapshot {
        let bodyBuilds: Int
        let rowBuilds: Int
        let iconCalls: Int
        let iconNs: Int64
        let iconCold: Int
        let visibleList: Int
    }

    private static func snapshotCounters() -> CounterSnapshot {
        CounterSnapshot(
            bodyBuilds: SidebarPerfCounters.sidebarBodyBuilds,
            rowBuilds: SidebarPerfCounters.rowBuilds,
            iconCalls: SidebarPerfCounters.iconCalls,
            iconNs: SidebarPerfCounters.iconMainNs,
            iconCold: SidebarPerfCounters.iconColdProbes,
            visibleList: SidebarPerfCounters.visibleListBuilds
        )
    }

    static func runIfNeeded(library: ROMLibrary) {
        let env = ProcessInfo.processInfo.environment
        guard env["TRUCHI_SIDEBAR_SCROLL_AUDIT"] == "1" else { return }
        Task { @MainActor in
            await Self.run(library: library)
        }
    }

    // MARK: - Audit execution

    @MainActor
    private static func run(library: ROMLibrary) async {
        print("[SidebarScrollAudit] waiting for library…")
        let loadDeadline = Date().addingTimeInterval(60)
        while Date() < loadDeadline {
            if !library.isScanning && library.roms.count > 0 { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard library.roms.count > 0 else {
            print("[SidebarScrollAudit] library empty; aborting")
            exit(1)
        }
        // Let launch-time work (library view onAppear, metadata sync) drain.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        guard let scrollView = await waitForSidebarScrollView(timeout: 10) else {
            print("[SidebarScrollAudit] no sidebar scroll view found; aborting")
            exit(1)
        }
        guard let window = scrollView.window else {
            print("[SidebarScrollAudit] scroll view has no window; aborting")
            exit(1)
        }

        // Rendering must be live or every metric is meaningless.
        let originalWindowFrame = window.frame
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        print("[SidebarScrollAudit] window='\(window.title)' frame=\(NSStringFromRect(window.frame)) "
              + "occlusionVisible=\(window.occlusionState.contains(.visible)) "
              + "contentHeight=\(scrollView.contentView.documentRect.height)")

        warpCursor(over: scrollView)
        let windowPoint = CGPoint(x: scrollView.convert(scrollView.bounds, to: nil).midX,
                                  y: scrollView.convert(scrollView.bounds, to: nil).midY)
        let driver = await probeDriver(scrollView, at: windowPoint)

        // Round 1 runs cold (no prewarm) — first-scroll row materialization
        // and icon loads are part of what a user feels. Then a programmatic
        // prewarm pass materializes every row + icon; rounds 2 and 3 measure
        // steady-state scrolling. Each burst flags background library changes
        // (enrichment/metadata publishes re-render the library content and
        // pollute main-thread measurements).
        var results: [BurstResult] = []
        var libChange = library.lastChangeDate
        resetToTop(scrollView)
        try? await Task.sleep(nanoseconds: 800_000_000)
        await waitForQuiescence()

        results.append(await burst(scrollView, label: "cold-r1", deltaY: -1, driver: driver, windowPoint: windowPoint, library: library, libChange: &libChange))
        results.append(await burst(scrollView, label: "up-r1", deltaY: 1, driver: driver, windowPoint: windowPoint, library: library, libChange: &libChange))

        prewarm(scrollView)
        try? await Task.sleep(nanoseconds: 800_000_000)
        await waitForQuiescence()

        results.append(await burst(scrollView, label: "warm-r2", deltaY: -1, driver: driver, windowPoint: windowPoint, library: library, libChange: &libChange))
        results.append(await burst(scrollView, label: "up-r2", deltaY: 1, driver: driver, windowPoint: windowPoint, library: library, libChange: &libChange))

        await waitForQuiescence()
        results.append(await burst(scrollView, label: "warm-r3", deltaY: -1, driver: driver, windowPoint: windowPoint, library: library, libChange: &libChange))
        results.append(await burst(scrollView, label: "up-r3", deltaY: 1, driver: driver, windowPoint: windowPoint, library: library, libChange: &libChange))

        writeReport(romCount: library.roms.count, driver: driver.rawValue, results: results)
        window.setFrame(originalWindowFrame, display: false)
        exit(0)
    }

    /// Waits until the main thread has been quiet (no >10 ms hops between 4 ms
    /// samples) for 1.5 s, so burst measurements don't overlap background
    /// library work (enrichment, metadata sync, box-art publishes). Gives up
    /// after 30 s.
    @MainActor
    private static func waitForQuiescence() async {
        let deadline = Date().addingTimeInterval(30)
        var quietStart: Date? = nil
        var lastSample = CACurrentMediaTime()
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 4_000_000)
            let now = CACurrentMediaTime()
            let gapMs = (now - lastSample) * 1000
            lastSample = now
            if gapMs > 10 {
                quietStart = nil
            } else {
                if quietStart == nil { quietStart = Date() }
                if let start = quietStart, Date().timeIntervalSince(start) > 1.5 {
                    print("[SidebarScrollAudit] main thread quiet; measuring")
                    return
                }
            }
        }
        print("[SidebarScrollAudit] quiescence not reached in 30s; measuring anyway")
    }

    /// Programmatic full-range scroll pass to materialize every row and icon
    /// before the warm rounds.
    @MainActor
    private static func prewarm(_ scrollView: NSScrollView) {
        let clip = scrollView.contentView
        let maxY = scrollView.contentView.documentRect.height - clip.bounds.height
        if maxY > 0 {
            clip.scroll(to: CGPoint(x: 0, y: maxY))
            scrollView.reflectScrolledClipView(clip)
        }
        resetToTop(scrollView)
    }

    // MARK: - Burst measurement

    @MainActor
    private static func burst(_ scrollView: NSScrollView, label: String, deltaY: CGFloat,
                              driver: ScrollDriver, windowPoint: NSPoint,
                              library: ROMLibrary, libChange: inout Date) async -> BurstResult {
        let clip = scrollView.contentView
        // Down bursts start at the top (reset programmatically). Up bursts
        // start from wherever the previous burst naturally settled — jumping
        // the clip view externally makes SwiftUI re-sync and rebuild the
        // content, which a real user never triggers.
        if deltaY < 0 {
            resetToTop(scrollView)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        let startOriginY = clip.bounds.origin.y
        let libChangeAtStart = libChange
        let c0 = snapshotCounters()
        let displayLink = ScrollDisplayLink.shared
        displayLink.record(originY: startOriginY)
        displayLink.start()

        // ~4000 px/s at one event per 4 ms (250 events/s) for the event-driven
        // paths; 16 px per programmatic step matches.
        let eventDelta = deltaY * 16
        // Re-establish focus and cursor over the sidebar before every burst:
        // wheel events route to the window under the cursor, and the user's
        // real mouse can have moved since the warp.
        if let window = scrollView.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        warpCursor(over: scrollView)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let t0 = CACurrentMediaTime()
        var lastSample = t0
        var busyMs = 0.0
        var maxHopMs = 0.0
        var stalls = 0

        let iterations = 400
        let sampleIntervalNs: UInt64 = 4_000_000
        for i in 0..<iterations {
            switch driver {
            case .programmatic:
                clip.scroll(to: CGPoint(x: clip.bounds.origin.x,
                                        y: clip.bounds.origin.y + eventDelta))
                scrollView.reflectScrolledClipView(clip)
            case .hidPost, .sendEvent, .directWheel:
                // Real trackpad gesture shape: mayBegin → began → changed… → ended.
                let phase: CGScrollPhase = i == 0 ? .mayBegin : (i == 1 ? .began : .changed)
                if let cgEvent = makeScrollCGEvent(for: scrollView, at: windowPoint,
                                                   delta: i == 0 ? 0 : eventDelta, phase: phase) {
                    dispatch(driver, cgEvent: cgEvent, scrollView: scrollView)
                }
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

        // End the gesture so SwiftUI's smooth-scroll machinery settles.
        if driver != .programmatic,
           let cgEvent = makeScrollCGEvent(for: scrollView, at: windowPoint,
                                          delta: 0, phase: .ended) {
            dispatch(driver, cgEvent: cgEvent, scrollView: scrollView)
        }

        let scrollDuration = CACurrentMediaTime() - t0
        let (advancedTicks, totalTicks) = displayLink.stopAndCollect()

        // Tail: gesture settle (rubber-band spring-back, row animations).
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
        let iconMs = Double(c1.iconNs - c0.iconNs) / 1_000_000
        let libraryChangedDuringBurst = library.lastChangeDate != libChangeAtStart
        libChange = library.lastChangeDate

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
            bodyBuilds: c1.bodyBuilds - c0.bodyBuilds,
            rowBuilds: c1.rowBuilds - c0.rowBuilds,
            iconMs: iconMs,
            iconCalls: c1.iconCalls - c0.iconCalls,
            iconColdProbes: c1.iconCold - c0.iconCold,
            visibleListBuilds: c1.visibleList - c0.visibleList
        )
        let flag = libraryChangedDuringBurst ? " ⚠️libraryChanged" : ""
        let line = String(
            format: "[SidebarScrollAudit] %@ dur=%.0fms dist=%.0fpx busy=%.0fms stalls=%d maxHop=%.0fms "
                + "settleBusy=%.0fms settleHop=%.0fms rFps=%.0f/%.0f bodies=%d rows=%d "
                + "icon=%.0fms/%dcalls coldProbes=%d visibleListBuilds=%d%@",
            label, result.durationMs, result.distancePx, result.busyMs, result.stalls, result.maxHopMs,
            result.settleBusyMs, result.settleMaxHopMs, result.renderedFps, result.refreshRate,
            result.bodyBuilds, result.rowBuilds, result.iconMs, result.iconCalls,
            result.iconColdProbes, result.visibleListBuilds, flag)
        print(line)
        return result
    }

    // MARK: - View discovery and scroll driving

    @MainActor
    private static func waitForSidebarScrollView(timeout: TimeInterval) async -> NSScrollView? {
        let deadline = Date().addingTimeInterval(timeout)
        var logged = false
        while Date() < deadline {
            var candidates: [(sv: NSScrollView, width: CGFloat, doc: String, height: CGFloat, window: String)] = []
            for window in NSApp.windows where window.isVisible {
                for sv in collectScrollViews(in: window.contentView) {
                    candidates.append((sv, sv.bounds.width,
                                       String(describing: type(of: sv.documentView)),
                                       sv.contentView.documentRect.height, window.title))
                }
            }
            if !logged, !candidates.isEmpty {
                logged = true
                for c in candidates {
                    print("[SidebarScrollAudit] candidate sv=\(type(of: c.sv)) "
                          + "w=\(String(format: "%.0f", c.width)) "
                          + "doc=\(c.doc) "
                          + "contentHeight=\(String(format: "%.0f", c.height)) "
                          + "window='\(c.window)'")
                }
            }
            // The sidebar is the narrowest scroll view whose document is not a
            // collection or table view (those belong to the library content).
            let sidebars = candidates.filter { c in
                !(c.sv.documentView is NSCollectionView) && !(c.sv.documentView is NSTableView)
            }
            if let best = sidebars.min(by: { $0.width < $1.width }),
               best.sv.contentView.documentRect.height > 50 {
                return best.sv
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private static func collectScrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        var result: [NSScrollView] = []
        if let sv = view as? NSScrollView {
            result.append(sv)
        }
        for sub in view.subviews {
            result.append(contentsOf: collectScrollViews(in: sub))
        }
        return result
    }

    @MainActor
    @discardableResult
    private static func warpCursor(over scrollView: NSScrollView) -> CGPoint? {
        guard let window = scrollView.window,
              let screen = window.screen ?? NSScreen.main else { return nil }
        let rectInWindow = scrollView.convert(scrollView.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        let cgPoint = CGPoint(x: rectOnScreen.midX, y: screen.frame.maxY - rectOnScreen.midY)
        let error = CGWarpMouseCursorPosition(cgPoint)
        print("[SidebarScrollAudit] cursor warp to \(NSStringFromPoint(cgPoint)) error=\(error.rawValue)")
        return cgPoint
    }

    /// Probes the candidate drivers from most-real to least-real and returns
    /// the first one that actually moves the sidebar: HID event tap (full
    /// window-server path), `NSApp.sendEvent` (responder routing), direct
    /// `scrollWheel(with:)` with trackpad-style phases, programmatic clip
    /// scrolling. SwiftUI's HostingScrollView ignores window-less unphased
    /// wheel events, which is why the library grid's direct driver is only a
    /// fallback here.
    @MainActor
    private static func probeDriver(_ scrollView: NSScrollView, at windowPoint: NSPoint) async -> ScrollDriver {
        let candidates: [ScrollDriver] = [.hidPost, .sendEvent, .directWheel]
        for driver in candidates {
            resetToTop(scrollView)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let clip = scrollView.contentView
            let start = clip.bounds.origin.y
            for i in 0..<10 {
                let phase: CGScrollPhase = i == 0 ? .mayBegin : (i == 1 ? .began : .changed)
                guard let cgEvent = makeScrollCGEvent(for: scrollView, at: windowPoint,
                                                      delta: i == 0 ? 0 : -12, phase: phase) else { break }
                dispatch(driver, cgEvent: cgEvent, scrollView: scrollView)
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
            if let endEvent = makeScrollCGEvent(for: scrollView, at: windowPoint,
                                                delta: 0, phase: .ended) {
                dispatch(driver, cgEvent: endEvent, scrollView: scrollView)
            }
            // Let momentum/smooth-scroll apply before judging effectiveness.
            try? await Task.sleep(nanoseconds: 400_000_000)
            let moved = clip.bounds.origin.y - start
            print("[SidebarScrollAudit] probe \(driver.rawValue) moved \(String(format: "%.0f", moved))px")
            if abs(moved) > 5 { return driver }
        }
        print("[SidebarScrollAudit] no event driver effective; using programmatic scrolling")
        return .programmatic
    }

    private static func dispatch(_ driver: ScrollDriver, cgEvent: CGEvent, scrollView: NSScrollView) {
        switch driver {
        case .hidPost:
            cgEvent.post(tap: .cghidEventTap)
        case .sendEvent:
            if let nsEvent = NSEvent(cgEvent: cgEvent) { NSApp.sendEvent(nsEvent) }
        case .directWheel:
            if let nsEvent = NSEvent(cgEvent: cgEvent) { scrollView.scrollWheel(with: nsEvent) }
        case .programmatic:
            break
        }
    }

    @MainActor
    private static func makeScrollCGEvent(for scrollView: NSScrollView, at windowPoint: NSPoint,
                                          delta: CGFloat, phase: CGScrollPhase) -> CGEvent? {
        guard let window = scrollView.window,
              let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                    wheel1: Int32(delta), wheel2: 0, wheel3: 0) else { return nil }
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        // The event carries its location in CG global (top-left origin)
        // coordinates; convert the AppKit window point accordingly.
        let screenPoint = window.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
        let screenFrame = (window.screen ?? NSScreen.main)?.frame ?? .zero
        cgEvent.location = CGPoint(x: screenPoint.x, y: screenFrame.maxY - screenPoint.y)
        return cgEvent
    }

    @MainActor
    private static func resetToTop(_ scrollView: NSScrollView) {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Report

    @MainActor
    private static func writeReport(romCount: Int, driver: String, results: [BurstResult]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TruchiEmu/SidebarScrollPerfAudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var md = "# Sidebar scroll perf audit\n\n"
        md += "- library size: \(romCount)\n"
        md += "- scroll driver: \(driver)\n\n"
        md += "Metrics: `busy` = main-thread ms in >20ms gaps between 4ms samples; "
        md += "`stalls` = gaps >50ms; `rFps` = display refreshes per second on which the "
        md += "scroll origin advanced (renderFps / display refresh rate); "
        md += "`bodies` = SystemSidebarView body evaluations; "
        md += "`rows` = sidebarRow builds; "
        md += "`icon` = emuImage(size:132) main-thread ms / calls; "
        md += "`coldProbes` = icon cache misses that fell through to bundle/disk lookups; "
        md += "`visibleListBuilds` = GamepadNavCoordinator.visibleSidebarFilters array rebuilds.\n\n"
        md += "| burst | durMs | distPx | busyMs | maxHopMs | stalls>50 | settleBusyMs | settleHopMs | rFps | refresh | bodies | rows | iconMs | iconCalls | coldProbes | visibleListBuilds |\n"
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
            + "| \(r.bodyBuilds) "
            + "| \(r.rowBuilds) "
            + "| \(String(format: "%.0f", r.iconMs)) "
            + "| \(r.iconCalls) "
            + "| \(r.iconColdProbes) "
            + "| \(r.visibleListBuilds) |\n"
        }
        let url = dir.appendingPathComponent("report.md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        print("[SidebarScrollAudit] report: \(url.path)")
    }
}

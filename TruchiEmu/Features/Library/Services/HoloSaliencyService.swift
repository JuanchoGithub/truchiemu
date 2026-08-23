import AppKit
import BoxArtLayers
import CoreImage
import Foundation
import os.lock
import UniformTypeIdentifiers

// Region alpha masks for one box art, produced by the BoxArtLayers
// decomposition. `background` is the sky (heavy holo), `title` / `chrome` /
// `hero` are the frozen-but-subtly-holoed regions.
struct HoloMaskSet: Sendable {
    let hero: NSImage?
    let title: NSImage?
    let chrome: NSImage?
    let background: NSImage?
    // Per-card random flags: whether title/chrome also pick up the background
    // holo at their subtle level, and whether hero gets its rare 5% holo.
    let heroHolo: Bool
    let titleBackgroundHolo: Bool
    let chromeBackgroundHolo: Bool
}

extension HoloMaskSet: Equatable {
    // NSImage isn't Equatable; compare by reference identity. Masks are
    // cached and reused wholesale (never mutated in place), so identity is
    // a correct and cheap equality for our purposes.
    static func == (lhs: HoloMaskSet, rhs: HoloMaskSet) -> Bool {
        lhs.hero === rhs.hero
            && lhs.title === rhs.title
            && lhs.chrome === rhs.chrome
            && lhs.background === rhs.background
            &&         lhs.heroHolo == rhs.heroHolo
            && lhs.titleBackgroundHolo == rhs.titleBackgroundHolo
            && lhs.chromeBackgroundHolo == rhs.chromeBackgroundHolo
    }
}

// Produces the per-region holo masks from the BoxArtLayers decomposition:
//
//   - background (sky)  -> heavy holo
//   - title / chrome    -> subtle holo, their own pattern
//   - hero              -> usually no holo (low random chance of subtle 5%)
//
// Masks are persisted to disk at
//   ~/Library/Application Support/TruchiEmu/HoloMasks/<romID>_<role>.png
// so each box art is decomposed only once. A tinted debug preview
//   ~/Library/Application Support/TruchiEmu/HoloMasks/<romID>.preview.png
// shows the layer split (red hero, yellow title, green mid, blue sky,
// gray chrome).
//
// Per-card pattern choices and heroHolo/titleBackgroundHolo/chromeBackgroundHolo
// flags are persisted as JSON sidecar `<romID>.meta.json` so the look stays
// stable across launches (matches the cached-on-disk masks).
//
// Decomposition failures (Vision returned no useful masks, throws, etc.) are
// marked with `<romID>.failed` so we don't retry on every card view appearance.
// The marker is honored for 24h, after which a fresh attempt is allowed.
//
// Concurrency model: this is NOT a Swift actor. Using `actor` would serialize
// every `holoMasks(romID:)` call across all cards in the library — meaning a
// system switch queues 50+ Vision decomposes behind whatever was in-flight for
// the previous system, and the user-visible cards stay stuck on the old roms
// until the queue drains. Instead the cache + inFlight tables are guarded by
// an `OSAllocatedUnfairLock` and work is dispatched onto a background
// cooperative queue. Different romIDs run concurrently; the same romID is
// deduplicated via inFlight.
final class HoloSaliencyService: @unchecked Sendable, ObservableObject {
    static let shared = HoloSaliencyService()

    private let cache: OSAllocatedUnfairLock<[String: HoloMaskSet]> = .init(initialState: [:])
    private let inFlight: OSAllocatedUnfairLock<[String: Task<HoloMaskSet?, Never>]> = .init(initialState: [:])
    private let generating: OSAllocatedUnfairLock<Set<String>> = .init(initialState: [])
    /// Number of romIDs currently running a Vision decompose. Published on the
    /// main thread so the sidebar can show a "generating holo FX" indicator.
    @Published private(set) var activeDecomposeCount: Int = 0

    // Vision decomposition is CPU-heavy. A full page of 50 cards would
    // otherwise spawn 50 concurrent Vision runs and pin every core, stalling
    // the UI while masks generate. Limit to a few at a time; system switches
    // cancel the rest outright (see `cancelAll()`).
    //
    // Must be an ASYNC semaphore, never a blocking DispatchSemaphore. A
    // `DispatchSemaphore.wait()` inside a Swift Task blocks a cooperative
    // thread-pool worker, and that block is NOT cancellation-aware: when a
    // system switch cancels a page of in-flight card tasks, the waiters stay
    // wedged on `.wait()` and hold their cooperative threads hostage. With 50
    // cards that exhausts the pool and freezes the whole app (the main actor
    // can't even schedule). An async semaphore suspends waiters instead, so a
    // cancelled waiter releases its slot immediately when signalled and the
    // pool is never blocked.
    private static let decomposeLimiter = AsyncSemaphore(maxConcurrent: 3)

    private static let failureTTL: TimeInterval = 24 * 60 * 60

    nonisolated static var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("TruchiEmu/HoloMasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func maskFileURL(for romID: String, role: String) -> URL {
        storageDirectory.appendingPathComponent("\(romID)_\(role).png")
    }

    nonisolated static func previewFileURL(for romID: String) -> URL {
        storageDirectory.appendingPathComponent("\(romID).preview.png")
    }

    nonisolated static func metaFileURL(for romID: String) -> URL {
        storageDirectory.appendingPathComponent("\(romID).meta.json")
    }

    nonisolated static func failureMarkerURL(for romID: String) -> URL {
        storageDirectory.appendingPathComponent("\(romID).failed")
    }

    /// Synchronous cache peek. Safe to call from the main thread — never
    /// touches disk. Lets `HoloGameCardView.task` bail out immediately if
    /// the masks are already loaded in memory, without awaiting the actor
    /// (or in the new model, without even dispatching a Task).
    nonisolated func cachedMasksSync(for romID: String) -> HoloMaskSet? {
        cache.withLock { $0[romID] }
    }

    /// Primary entry point. Returns the mask set for the romID, loading from
    /// disk cache or decomposing on demand. Cancelled when the caller (the
    /// SwiftUI .task that owns the card view) is cancelled — important when
    /// the user switches systems mid-decompose, so 50 in-flight decomposes
    /// don't keep the OS pinned.
    func holoMasks(romID: String, image: NSImage) async -> HoloMaskSet? {
        // 1. In-memory cache hit — instantly return.
        if let cached = cachedMasksSync(for: romID) { return cached }

        // 2. Another caller is already working on this romID — share the task.
        if let existing: Task<HoloMaskSet?, Never> = inFlight.withLock({ $0[romID] }) {
            return await existing.value
        }

        // 3. Fresh failure marker for this romID — skip until TTL expires.
        if await Self.failureMarkerIsFresh(romID: romID) {
            return nil
        }

        // 4. Spawn a Task that does the disk-cache lookup off-main and, if
        //    missing, the Vision decompose on a background queue. The Task is
        //    registered in `inFlight` *before* returning so concurrent callers
        //    dedupe via the inFlight check above.
        let task = Task.detached(priority: .utility) { [weak self] () -> HoloMaskSet? in
            guard let self else { return nil }
            // Always clear the inFlight entry, even on cancellation, so a
            // late caller for the same romID doesn't pick up a dead task.
            defer {
                self.inFlight.withLock { $0.removeValue(forKey: romID) }
            }
            // Check cancellation before any I/O — when a system switch
            // cancels all the in-flight .tasks, the next thing the user sees
            // should be the new system's cards, not the previous decomposes
            // still running.
            if Task.isCancelled { return nil }

            // 4a. Disk-cache hit. Decode four PNGs off-main.
            if let onDisk = await Self.loadMaskSetOffMain(romID: romID) {
                self.cache.withLock { $0[romID] = onDisk }
                return onDisk
            }
            if Task.isCancelled { return nil }

            // 4b. Decompose. Bounded to a few concurrent Vision runs by the
            //     limiter so a page of cards can't pin the machine; a system
            //     switch cancels the waiters/batch via `cancelAll()`.
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            guard await Self.decomposeLimiter.wait() else {
                // Cancelled before acquiring a slot — no defer to release.
                return nil
            }
            defer { Self.decomposeLimiter.signal() }
            self.setGenerating(romID, on: true)
            defer { self.setGenerating(romID, on: false) }
            if Task.isCancelled { return nil }
            let bundle: LayerBundle
            do {
                bundle = try await BoxArtDecomposer().decompose(cgImage)
            } catch is CancellationError {
                // User switched away mid-decompose. Not a failure — don't
                // write a failure marker or the 24h TTL would block a
                // legitimate retry when the user comes back.
                return nil
            } catch {
                Self.writeFailureMarker(romID: romID)
                return nil
            }
            if Task.isCancelled { return nil }

            // 4c. Convert + persist. Off-main.
            let masks = await Self.buildAndPersistMaskSet(bundle: bundle, romID: romID)
            if let masks {
                self.cache.withLock { $0[romID] = masks }
            } else {
                Self.writeFailureMarker(romID: romID)
            }
            return masks
        }
        inFlight.withLock { $0[romID] = task }
        // Hook up cancellation: when the caller (the SwiftUI .task) is
        // cancelled (e.g. system switch tears down the card view), cancel
        // the detached work so we don't keep running 50 decomposes for a
        // system the user just left. Without this the OS stays pinned for
        // seconds after the user has moved on.
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Drop the in-memory cache entry for a romID. Used by debug / menu paths
    /// that want to force re-decompose after editing the mask files by hand.
    nonisolated func invalidate(romID: String) {
        cache.withLock { $0.removeValue(forKey: romID) }
    }

    /// Drop everything. Heavy; only useful for tests.
    nonisolated func invalidateAll() {
        cache.withLock { $0.removeAll() }
    }

    /// Fully reset the masks for a romID: drop the in-memory cache entry,
    /// cancel any in-flight generation, and delete the on-disk mask PNGs,
    /// preview, meta, and failure marker. The masks are keyed only by romID,
    /// so when the underlying box art is replaced the old masks would
    /// otherwise persist and the holo foil would render against the wrong
    /// image. Call this from the box-art replacement flow so the next
    /// `holoMasks` call re-decomposes the new image.
    nonisolated func resetMasks(romID: String) {
        cache.withLock { $0.removeValue(forKey: romID) }
        if let task = inFlight.withLock({ $0.removeValue(forKey: romID) }) {
            task.cancel()
        }
        let files = [
            Self.maskFileURL(for: romID, role: "hero"),
            Self.maskFileURL(for: romID, role: "title"),
            Self.maskFileURL(for: romID, role: "chrome"),
            Self.maskFileURL(for: romID, role: "background"),
            Self.previewFileURL(for: romID),
            Self.metaFileURL(for: romID),
            Self.failureMarkerURL(for: romID),
        ]
        let fm = FileManager.default
        for url in files {
            try? fm.removeItem(at: url)
        }
    }

    /// Cancel every in-flight mask generation immediately. Called when the
    /// user switches systems: any decomposes still chewing the CPU for the
    /// system they just left are aborted right away (the decompose checks
    /// cancellation between its heavy steps), so the app stays responsive and
    /// a quick switch-back doesn't stack a second batch on top of a stale one.
    nonisolated func cancelAll() {
        let tasks = inFlight.withLock { Array($0.values) }
        for task in tasks { task.cancel() }
    }

    /// Track active Vision decomposes for the sidebar progress indicator. The
    /// `on` flag toggles romID membership; the resulting count is republished
    /// on the main thread so SwiftUI observes the change.
    nonisolated private func setGenerating(_ romID: String, on: Bool) {
        let count = generating.withLock { set in
            if on { set.insert(romID) } else { set.remove(romID) }
            return set.count
        }
        DispatchQueue.main.async { [weak self] in
            self?.activeDecomposeCount = count
        }
    }

    // MARK: - Disk I/O (off-main)

    /// Reads the four PNG masks + meta JSON from disk on a background queue
    /// and assembles a `HoloMaskSet`. Never touches the main thread.
    /// Cancellation of the awaiting task (system switch) propagates to the
    /// inner work so a stale disk load doesn't keep running.
    nonisolated private static func loadMaskSetOffMain(romID: String) async -> HoloMaskSet? {
        let heroURL = maskFileURL(for: romID, role: "hero")
        let titleURL = maskFileURL(for: romID, role: "title")
        let chromeURL = maskFileURL(for: romID, role: "chrome")
        let backgroundURL = maskFileURL(for: romID, role: "background")
        let metaURL = metaFileURL(for: romID)

        let task = Task.detached(priority: .utility) { () -> HoloMaskSet? in
            if Task.isCancelled { return nil }
            let hero = loadMaskSync(from: heroURL)
            let title = loadMaskSync(from: titleURL)
            let chrome = loadMaskSync(from: chromeURL)
            let background = loadMaskSync(from: backgroundURL)
            if Task.isCancelled { return nil }
            guard hero != nil || title != nil || chrome != nil || background != nil else {
                return nil
            }

            var meta = HoloMaskMeta()
            if let data = try? Data(contentsOf: metaURL),
               let decoded = try? JSONDecoder().decode(HoloMaskMeta.self, from: data) {
                meta = decoded
            }

            return HoloMaskSet(
                hero: hero,
                title: title,
                chrome: chrome,
                background: background,
                heroHolo: meta.heroHolo,
                titleBackgroundHolo: meta.titleBackgroundHolo,
                chromeBackgroundHolo: meta.chromeBackgroundHolo
            )
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Run Vision-style decomposition (CPU-bound, off-main) and persist the
    /// resulting PNGs + meta sidecar. Returns the assembled mask set or nil.
    /// Runs in the caller's task context, so `Task.isCancelled` reflects the
    /// in-flight generation task and aborts the work when the user switches
    /// systems.
    nonisolated private static func buildAndPersistMaskSet(bundle: LayerBundle, romID: String) async -> HoloMaskSet? {
        if Task.isCancelled { return nil }
        let hero = grayscaleToAlphaMask(bundle.masks.hero)
        let title = grayscaleToAlphaMask(bundle.masks.title)
        let chrome = grayscaleToAlphaMask(bundle.masks.chrome)
        let background = grayscaleToAlphaMask(bundle.masks.background)
        if Task.isCancelled { return nil }

        if let hero { saveMask(hero, to: maskFileURL(for: romID, role: "hero")) }
        if let title { saveMask(title, to: maskFileURL(for: romID, role: "title")) }
        if let chrome { saveMask(chrome, to: maskFileURL(for: romID, role: "chrome")) }
        if let background { saveMask(background, to: maskFileURL(for: romID, role: "background")) }
        writePNG(bundle.preview, to: previewFileURL(for: romID))
        if Task.isCancelled { return nil }

        var rng = SplitMix64(seed: stableSeed(romID))
        let heroHolo = (rng.next() % 100) < 20
        let titleBackgroundHolo = (rng.next() % 100) < 50
        let chromeBackgroundHolo = (rng.next() % 100) < 50

        let meta = HoloMaskMeta(
            heroHolo: heroHolo,
            titleBackgroundHolo: titleBackgroundHolo,
            chromeBackgroundHolo: chromeBackgroundHolo
        )
        writeMeta(meta, to: metaFileURL(for: romID))

        return HoloMaskSet(
            hero: hero,
            title: title,
            chrome: chrome,
            background: background,
            heroHolo: heroHolo,
            titleBackgroundHolo: titleBackgroundHolo,
            chromeBackgroundHolo: chromeBackgroundHolo
        )
    }

    nonisolated private static func loadMaskSync(from url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }

    nonisolated private static func saveMask(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    nonisolated private static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    nonisolated private static func writeMeta(_ meta: HoloMaskMeta, to url: URL) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // BoxArtLayers masks are grayscale (white = region present, no alpha
    // channel). SwiftUI's .mask() reads the alpha channel, so convert
    // luminance -> alpha (white -> opaque).
    // Avoids CIContext.render(toBitmap:) — Core Image is Y-up and flips output.
    private static func grayscaleToAlphaMask(_ mask: CGImage) -> NSImage? {
        let ci = CIImage(cgImage: mask)
        let alpha = ci.applyingFilter("CIMaskToAlpha")
        let context = CIContext()
        guard let out = context.createCGImage(alpha, from: alpha.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: mask.width, height: mask.height))
    }

    // MARK: - Failure marker

    nonisolated private static func writeFailureMarker(romID: String) {
        let url = failureMarkerURL(for: romID)
        let payload = "\(Date().timeIntervalSince1970)".data(using: .utf8) ?? Data()
        try? payload.write(to: url, options: .atomic)
    }

    nonisolated private static func failureMarkerIsFresh(romID: String) async -> Bool {
        let url = failureMarkerURL(for: romID)
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let s = String(data: data, encoding: .utf8),
                  let written = TimeInterval(s) else { return false }
            let age = Date().timeIntervalSince1970 - written
            return age < failureTTL
        }.value
    }
}

// MARK: - Meta sidecar

private struct HoloMaskMeta: Codable {
    var heroHolo: Bool = false
    var titleBackgroundHolo: Bool = false
    var chromeBackgroundHolo: Bool = false
}

// MARK: - Async semaphore

// An async concurrency limiter. `wait()` SUSPENDS the calling task until a
// slot frees — it never blocks a cooperative thread-pool worker. This is the
// safe replacement for a `DispatchSemaphore` inside Swift concurrency: a
// blocked `.wait()` on a DispatchSemaphore holds a cooperative thread
// hostage and is not cancelled when the task is cancelled, which (with a page
// of cards) exhausts the thread pool and freezes the app during a system
// switch. `wait()` is cancellation-aware: if the calling task is cancelled
// while queued, the waiter is removed and `wait()` returns immediately so the
// task can unwind.
private final class AsyncSemaphore: @unchecked Sendable {
    private struct State {
        var available: Int
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        var order: [UUID] = []
    }

    private let lock: OSAllocatedUnfairLock<State>

    init(maxConcurrent: Int) {
        lock = OSAllocatedUnfairLock(initialState: State(available: maxConcurrent))
    }

    /// Waits for a slot. Returns `true` if the caller acquired the slot (and
    /// MUST call `signal()` when done), `false` if the caller was cancelled
    /// before acquiring — in which case it must NOT signal, because it never
    /// held a slot.
    func wait() async -> Bool {
        let acquired = lock.withLock { state -> Bool in
            if state.available > 0 {
                state.available -= 1
                return true
            }
            return false
        }
        if acquired { return true }
        // Cancellation-aware queue: if the waiting task is cancelled, drop it
        // from the queue and resume it so the cancelled work can unwind
        // instead of waiting for a slot that may not come (the running
        // decomposes hold their slots until they finish or are cancelled).
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.withLock { state in
                    if Task.isCancelled {
                        // Cancellation raced ahead of registration; don't queue
                        // a waiter that will never be signalled.
                        cont.resume()
                    } else {
                        state.waiters[id] = cont
                        state.order.append(id)
                    }
                }
            }
        } onCancel: {
            lock.withLock { state in
                if let cont = state.waiters.removeValue(forKey: id) {
                    state.order.removeAll { $0 == id }
                    cont.resume()
                }
            }
        }
        // If the task is now cancelled we were resumed by the cancellation
        // handler and never held a slot.
        return !Task.isCancelled
    }

    func signal() {
        while true {
            let done = lock.withLock { state -> Bool in
                if let id = state.order.first {
                    state.order.removeFirst()
                    if let cont = state.waiters.removeValue(forKey: id) {
                        cont.resume()
                        return true
                    }
                    // Waiter was cancelled while queued (removed + resumed by
                    // the cancellation handler); pass the slot to the next.
                    return false
                }
                state.available += 1
                return true
            }
            if done { return }
        }
    }
}

// FNV-1a 64-bit. Stable across launches (unlike Swift's randomized Hasher).
func stableSeed(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for byte in s.utf8 {
        h ^= UInt64(byte)
        h &*= 0x100000001b3
    }
    return h
}

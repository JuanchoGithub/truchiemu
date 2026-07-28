import Foundation

struct TimeMachineEntry {
    let frameIndex: UInt64
    let data: Data
}

class TimeMachineBuffer {
    private var entries: [TimeMachineEntry] = []
    private let lock = NSLock()
    private let maxMemoryBytes: Int
    private var currentMemoryBytes: Int = 0
    private(set) var captureInterval: Int = 3
    private(set) var maxEntries: Int = 0

    init(maxMemoryBytes: Int = 256 * 1024 * 1024) {
        self.maxMemoryBytes = maxMemoryBytes
    }

    func configure(stateSize: Int) {
        lock.withLock {
            let entryOverhead = 64
            let stateSizeWithOverhead = stateSize + entryOverhead
            captureInterval = max(3, (stateSize * 20) / (maxMemoryBytes / 120))
            // maxEntries is a hint based on the startup state size; the real
            // bound is enforced in push by total bytes, because cores (e.g.
            // PPSSPP) can grow their serialize size mid-session (FMVs allocate
            // decoder state) and a stale entry count would let the buffer
            // balloon past the user's memory budget.
            maxEntries = maxMemoryBytes / stateSizeWithOverhead
            if maxEntries < 30 { maxEntries = 30 }
            entries.removeAll(keepingCapacity: true)
            currentMemoryBytes = 0
        }
    }

    /// Push a new entry to the buffer. Returns any entries evicted by this
    /// push (oldest first) so the caller can react — e.g. a recording
    /// pipeline can write each evicted entry's serialized state to the
    /// video file as a "committed" gameplay frame.
    @discardableResult
    func push(frameIndex: UInt64, data: Data) -> [TimeMachineEntry] {
        lock.withLock {
            let entryOverhead = 64
            let incomingBytes = data.count + entryOverhead
            // Evict oldest entries until both the entry-count and byte-budget
            // caps are satisfied. Bounding on actual bytes prevents OOM when
            // the core's serialize size grows mid-session (e.g. PPSSPP spawning
            // MpegContext during FMVs) beyond what configure() assumed — using
            // entry count alone could balloon memory by the size-growth ratio.
            // Captures arrive in frame order, so the oldest entry is at index 0.
            var evicted: [TimeMachineEntry] = []
            while (entries.count >= maxEntries || currentMemoryBytes + incomingBytes > maxMemoryBytes)
                    && !entries.isEmpty {
                let removed = entries.removeFirst()
                currentMemoryBytes -= (removed.data.count + entryOverhead)
                evicted.append(removed)
            }
            entries.append(TimeMachineEntry(frameIndex: frameIndex, data: data))
            currentMemoryBytes += incomingBytes
            return evicted
        }
    }

    func entry(at frameIndex: UInt64) -> TimeMachineEntry? {
        lock.withLock {
            entries.first(where: { $0.frameIndex == frameIndex })
        }
    }

    func nearestEntry(before frameIndex: UInt64) -> TimeMachineEntry? {
        lock.withLock {
            entries
                .filter { $0.frameIndex <= frameIndex }
                .max(by: { $0.frameIndex < $1.frameIndex })
        }
    }

    func nearestEntry(after frameIndex: UInt64) -> TimeMachineEntry? {
        lock.withLock {
            entries
                .filter { $0.frameIndex >= frameIndex }
                .min(by: { $0.frameIndex < $1.frameIndex })
        }
    }

    var oldestFrameIndex: UInt64? {
        lock.withLock { entries.min(by: { $0.frameIndex < $1.frameIndex })?.frameIndex }
    }

    var newestFrameIndex: UInt64? {
        lock.withLock { entries.max(by: { $0.frameIndex < $1.frameIndex })?.frameIndex }
    }

    var entryCount: Int {
        lock.withLock { entries.count }
    }

    func clear() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            currentMemoryBytes = 0
        }
    }

    /// Drop any entry whose frameIndex is strictly greater than `frameIndex`.
    /// Used after the user scrubs back and resumes — frames beyond the
    /// playhead are gone (that "future" was erased), so the timeline's total
    /// duration reflects only the remaining history.
    func truncate(after frameIndex: UInt64) {
        lock.withLock {
            let entryOverhead = 64
            let removed = entries.filter { $0.frameIndex > frameIndex }
            for entry in removed {
                currentMemoryBytes -= (entry.data.count + entryOverhead)
            }
            entries.removeAll { $0.frameIndex > frameIndex }
        }
    }
}

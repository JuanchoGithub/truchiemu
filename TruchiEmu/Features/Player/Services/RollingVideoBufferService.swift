import Foundation
import AVFoundation
import AppKit
import Combine

@MainActor
final class RollingVideoBufferService: ObservableObject {
    static let shared = RollingVideoBufferService()

    @Published var isEnabled: Bool = false {
        didSet { if isEnabled != oldValue { handleEnableChange() } }
    }
    @Published var duration: TimeInterval = 60
    @Published var recordDisplayResolution: Bool = false

    private var rollTimer: Timer?
    private var chunks: [URL] = []
    private var lastFrameWidth: Int = 0
    private var lastFrameHeight: Int = 0
    private var isSaving: Bool = false

    // The runner currently driving the active game window. Set by the game
    // launcher so we can ask it for captureSize (display vs. core resolution,
    // DAR letterboxing) when sizing rolling-buffer chunks — matching what a
    // manual record would produce.
    @MainActor weak var activeRunner: EmulatorRunner?

    static let bufferSaved = Notification.Name("rollingBufferSaved")

    private static let maxChunkSeconds: TimeInterval = 60

    private var chunkSeconds: TimeInterval {
        min(duration, Self.maxChunkSeconds)
    }

    /// Maximum number of chunks retained on disk at any time. We need enough
    /// chunks on hand to cover two back-to-back "Save Last X Seconds" clicks:
    /// one immediately after the previous save (which finalized the in-flight
    /// chunk) and another ~5s later when there is barely a fresh chunk yet.
    /// The retention is `duration` worth of chunks plus a safety margin of a
    /// couple of extra chunks for rolling-eviction tolerance.
    private var maxChunks: Int {
        let needed = Int(ceil(duration / chunkSeconds))
        return max(needed + 2, 3)
    }

    private init() {
        loadSettings()
    }

    private func loadSettings() {
        let config = RollingBufferConfig.load()
        isEnabled = config.enabled
        duration = config.duration.actualDuration
        recordDisplayResolution = config.recordDisplayResolution
    }

    func saveSettings() {
        var config = RollingBufferConfig.load()
        config.enabled = isEnabled
        config.duration = RollingBufferDuration.allCases.first(where: { $0.actualDuration == duration }) ?? .custom
        config.recordDisplayResolution = recordDisplayResolution
        config.save()
    }

    private func handleEnableChange() {
        if isEnabled {
            // Don't capture yet if no game is running — recording nothing but
            // a chunk file would write 60 seconds of black frames when the
            // user later launches a game. Defer to startCaptureIfReady().
            startCaptureIfReady()
        } else {
            stopRolling()
        }
    }

    /// Begin rolling capture if the buffer is enabled and a game runner is
    /// active. Otherwise no-op (we stay armed for when a game launches).
    func startCaptureIfReady() {
        guard isEnabled else { return }
        guard activeRunner != nil else { return }
        guard chunks.isEmpty else { return }
        appendNewChunk()
        startRollTimer()
    }

    /// Triggered by the game launcher when a runner is assigned. Starts the
    /// buffer if the user has it enabled.
    @MainActor
    func didAssignActiveRunner() {
        startCaptureIfReady()
    }

    private func startRolling() {
        startCaptureIfReady()
    }

    private func stopRolling() {
        rollTimer?.invalidate()
        rollTimer = nil
        StreamRecordingService.shared.stop()
        let existing = chunks
        chunks = []
        lastFrameWidth = 0
        lastFrameHeight = 0
        DispatchQueue.global(qos: .background).async {
            for url in existing {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Called when the active game runner disappears (window closed). Stops
    /// rolling capture without clearing the user's "enabled" preference so a
    /// later game launch can resume it.
    func stopRollingForNoRunner() {
        guard isEnabled else { return }
        stopRolling()
    }

    /// Preempted by a user-initiated user record action (toolbar/share button
    /// for `startVideoRecording` / stream*). Closes the active rolling chunk
    /// without changing the user's enabled preference; capture can resume
    /// later via `startCaptureIfReady()` once the user-initiated session ends.
    func suspendActiveCapture() {
        guard isEnabled else { return }
        stopRolling()
    }

    private func makeTempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("TruchiEmu_RollingBuffer_\(UUID().uuidString).mp4")
    }

    private func appendNewChunk() {
        // No game is active — don't burn cycles writing a chunk of black
        // frames. Capture will be started by startCaptureIfReady() once a
        // game runner is assigned.
        guard activeRunner != nil else { return }

        let url = makeTempURL()
        chunks.append(url)
        while chunks.count > maxChunks {
            let evicted = chunks.removeFirst()
            DispatchQueue.global(qos: .background).async {
                try? FileManager.default.removeItem(at: evicted)
            }
        }
        // Match the rolling-buffer chunk dimensions to what a manual record
        // would produce (display resolution with shaders / recordWithShaders
        // honored, or core + DAR letterboxing otherwise). Fall back to the
        // most recent captured frame size, or 1920x1080 if we've never seen
        // a frame yet.
        var w: Int = 1920
        var h: Int = 1080
        if let runner = activeRunner {
            let size = runner.captureSize
            if size.width > 0, size.height > 0 {
                w = Int(size.width)
                h = Int(size.height)
            }
        }
        if w <= 0 || h <= 0 {
            w = lastFrameWidth > 0 ? lastFrameWidth : 1920
            h = lastFrameHeight > 0 ? lastFrameHeight : 1080
        }
        StreamRecordingService.shared.startRecording(
            outputURL: url,
            width: w,
            height: h,
            fps: 60,
            initiator: .rollingBuffer
        )
    }

    private func startRollTimer() {
        rollTimer?.invalidate()
        let t = Timer(timeInterval: chunkSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rotateChunk()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rollTimer = t
    }

    func ensureRecordingMatches(width: Int, height: Int) {
        guard isEnabled else { return }
        lastFrameWidth = width
        lastFrameHeight = height
        let size = StreamRecordingService.shared.videoSize
        if Int(size.width) != width || Int(size.height) != height {
            rotateChunk()
        }
    }

    private func rotateChunk() {
        guard isEnabled, !isSaving else { return }
        StreamRecordingService.shared.stop()
        appendNewChunk()
    }

    func saveBufferToFile(completion: @escaping (URL?) -> Void) {
        guard isEnabled else {
            completion(nil)
            return
        }
        guard !isSaving else {
            completion(nil)
            return
        }
        isSaving = true
        defer { isSaving = false }

        let destDir: URL = {
            if let saved = StreamRecordingService.localOutputPath, !saved.isEmpty {
                return URL(fileURLWithPath: saved)
            }
            return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        }()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let date = formatter.string(from: Date())
        let filename = "TruchiEmu_Clip_\(date).mp4"
        let destURL = destDir.appendingPathComponent(filename)

        Task { @MainActor in
            await Self.finalizeCurrentRecording()

            let present = self.chunks.filter { FileManager.default.fileExists(atPath: $0.path) }

            guard !present.isEmpty else {
                completion(nil)
                return
            }

            do {
                if present.count == 1 {
                    try await Self.rebuildAndTrim(
                        chunk: present[0],
                        trimToDuration: self.duration,
                        outputURL: destURL
                    )
                } else {
                    try await Self.stitchAndTrim(
                        chunks: present,
                        trimToDuration: self.duration,
                        outputURL: destURL
                    )
                }

                // Don't drop the chunks we just saved from — keep the rolling
                // window intact so back-to-back saves can each produce a
                // full-duration clip. Eviction continues to happen naturally
                // inside appendNewChunk via maxChunks (which retains
                // ceil(duration/chunkSeconds) + safety_margin chunks on disk).
                if self.isEnabled {
                    self.appendNewChunk()
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.bufferSaved, object: nil, userInfo: ["url": destURL])
                    completion(destURL)
                }
            } catch {
                LoggerService.error(category: "RollingBuffer", "Save failed: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    /// Rebuilds a single chunk through AVMutableComposition. Forces a proper A/V re-mux
    /// (since AVAssetWriter MP4 metadata can have mismatched audio/video track durations).
    /// Trims to `trimToDuration` if the source is longer.
    private static func rebuildAndTrim(
        chunk: URL,
        trimToDuration: TimeInterval,
        outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "RollingBuffer", code: 1)
        }

        let asset = AVURLAsset(url: chunk)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let v = videoTracks.first {
            let vDur = try await v.load(.timeRange).duration
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: v, at: .zero)
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let a = audioTracks.first {
            let aDur = try await a.load(.timeRange).duration
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: aDur), of: a, at: .zero)
        }

        if !audioTrack.timeRange.duration.isValid || audioTrack.timeRange.duration <= .zero {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: chunk, to: outputURL)
            return
        }
        if !videoTrack.timeRange.duration.isValid || videoTrack.timeRange.duration <= .zero {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: chunk, to: outputURL)
            return
        }

        if audioTrack.timeRange.duration > videoTrack.timeRange.duration {
            audioTrack.scaleTimeRange(
                CMTimeRange(start: .zero, duration: audioTrack.timeRange.duration),
                toDuration: videoTrack.timeRange.duration
            )
        }

        let total = composition.duration
        let trimTo = CMTime(seconds: trimToDuration, preferredTimescale: 600)
        let trimStart = total - trimTo
        let effectiveStart = trimStart < .zero ? .zero : trimStart
        let exportRange = CMTimeRange(start: effectiveStart, duration: total - effectiveStart)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "RollingBuffer", code: 2)
        }
        try? FileManager.default.removeItem(at: outputURL)
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = exportRange
        session.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                cont.resume()
            }
        }

        if session.status == .failed || session.status == .cancelled {
            // Passthrough can fail to satisfy the timeRange on fragmented
            // inputs that cannot be re-streamed with a non-zero timeRange.
            // Fall back to re-encoding via a codec-aware highest-quality
            // preset so the clip still goes out with the user-chosen quality.
            try? FileManager.default.removeItem(at: outputURL)
            try await Self.reencodeWithTrim(
                composition: composition,
                exportRange: exportRange,
                outputURL: outputURL
            )
            return
        }

        if session.status != .completed {
            throw session.error ?? NSError(domain: "RollingBuffer", code: Int(session.status.rawValue))
        }
    }

    private static func reencodeWithTrim(
        composition: AVMutableComposition,
        exportRange: CMTimeRange,
        outputURL: URL
    ) async throws {
        let preset: String
        let fileType: AVFileType
        switch StreamRecordingService.shared.customVideoCodec {
        case .proRes422, .proRes4444:
            preset = AVAssetExportPresetAppleProRes422LPCM
            fileType = .mov
        case .h264:
            preset = AVAssetExportPresetHighestQuality
            fileType = .mp4
        case .hevc:
            preset = AVAssetExportPresetHEVCHighestQuality
            fileType = .mp4
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw NSError(domain: "RollingBuffer", code: 2)
        }
        session.outputURL = outputURL
        session.outputFileType = fileType
        session.timeRange = exportRange
        session.shouldOptimizeForNetworkUse = false
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                cont.resume()
            }
        }
        if session.status != .completed {
            throw session.error ?? NSError(domain: "RollingBuffer", code: Int(session.status.rawValue))
        }
    }

    /// Asks StreamRecordingService to finalize its current recording, awaiting the file flush.
    /// Idempotent: if not recording, just returns.
    @MainActor
    private static func finalizeCurrentRecording() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let srs = StreamRecordingService.shared
            guard srs.isRecording, let writer = srs.assetWriter else {
                cont.resume()
                return
            }

            srs.videoInput?.markAsFinished()
            srs.audioInput?.markAsFinished()

            srs.assetWriter = nil
            srs.videoInput = nil
            srs.audioInput = nil
            srs.pixelBufferAdaptor = nil
            srs.resetSession()

            writer.finishWriting {
                cont.resume()
            }
        }
    }

    private static func stitchAndTrim(
        chunks: [URL],
        trimToDuration: TimeInterval,
        outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "RollingBuffer", code: 1)
        }

        var videoCursor = CMTime.zero
        var audioCursor = CMTime.zero
        for url in chunks {
            let asset = AVURLAsset(url: url)
            let assetDuration = try await asset.load(.duration)

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let v = videoTracks.first {
                let vDur = try await v.load(.timeRange).duration
                let videoDuration = (vDur < assetDuration) ? vDur : assetDuration
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: v, at: videoCursor)
                videoCursor = videoCursor + videoDuration
            } else {
                videoCursor = videoCursor + assetDuration
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let a = audioTracks.first {
                let aDur = try await a.load(.timeRange).duration
                let audioLen = (aDur < assetDuration) ? aDur : assetDuration
                let insertAt = audioCursor
                try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioLen), of: a, at: insertAt)
                audioCursor = audioCursor + audioLen
            }
        }

        if videoTrack.timeRange.duration < audioTrack.timeRange.duration {
            audioTrack.scaleTimeRange(
                CMTimeRange(start: .zero, duration: audioTrack.timeRange.duration),
                toDuration: videoTrack.timeRange.duration
            )
        }

        let total = composition.duration
        let trimTo = CMTime(seconds: trimToDuration, preferredTimescale: 600)
        let trimStart = total - trimTo
        let effectiveStart = trimStart < .zero ? .zero : trimStart
        let exportRange = CMTimeRange(start: effectiveStart, duration: total - effectiveStart)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "RollingBuffer", code: 2)
        }
        try? FileManager.default.removeItem(at: outputURL)
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = exportRange
        session.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                cont.resume()
            }
        }

        if session.status == .failed || session.status == .cancelled {
            try? FileManager.default.removeItem(at: outputURL)
            try await Self.reencodeWithTrim(
                composition: composition,
                exportRange: exportRange,
                outputURL: outputURL
            )
            return
        }

        if session.status != .completed {
            throw session.error ?? NSError(domain: "RollingBuffer", code: Int(session.status.rawValue))
        }
    }

    func estimatedMemoryUsageMB() -> Double { 0 }

    func estimatedFileSizeMB() -> Double {
        // ~12 Mbps video + ~128 kbps audio
        let bytesPerSec = (12_000_000.0 + 128_000.0) / 8.0
        return bytesPerSec * duration / (1024.0 * 1024.0)
    }
}

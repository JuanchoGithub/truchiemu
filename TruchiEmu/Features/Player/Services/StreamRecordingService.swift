import Foundation
import AVFoundation
import VideoToolbox
import AVFAudio
import AppKit
import Network

enum StreamingMode: String, Codable, CaseIterable {
    case localFile
    case twitch
    case youtube
    case custom
}

enum RecordingVideoCodec: String, Codable, CaseIterable {
    case h264
    case hevc
    case proRes422
    case proRes4444

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        case .proRes422: return .proRes422
        case .proRes4444: return .proRes4444
        }
    }

    var isLossless: Bool {
        switch self {
        case .proRes422, .proRes4444: return true
        default: return false
        }
    }

    var supportsCustomBitrate: Bool {
        switch self {
        case .h264, .hevc: return true
        default: return false
        }
    }
}

enum RecordingQuality: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case lossless

    var videoBitrate: Int {
        switch self {
        case .low: return 2_500_000
        case .medium: return 5_000_000
        case .high: return 12_000_000
        case .lossless: return 0
        }
    }

    var audioBitrate: Int {
        switch self {
        case .low: return 96_000
        case .medium: return 128_000
        case .high: return 192_000
        case .lossless: return 320_000
        }
    }

    var frameRate: Int {
        switch self {
        case .low: return 30
        case .medium: return 30
        case .high: return 60
        case .lossless: return 60
        }
    }

    var videoCodec: RecordingVideoCodec {
        switch self {
        case .low: return .h264
        case .medium: return .h264
        case .high: return .h264
        case .lossless: return .proRes422
        }
    }
}

enum StreamStatus: Equatable {
    case idle
    case connecting
    case streaming
    case failed(String)
}

enum RecordingInitiator {
    /// Recording started in response to a user action (toolbar record button,
    /// share button with startVideoRecording/stream*, etc). UI shows the
    /// recording badge and the stop button when set.
    case user
    /// Recording started by the rolling-clip-buffer background loop. The user
    /// hasn't asked for a recording — the buffer is just continuously
    /// rotating chunks to disk so "save last X seconds" can produce a clip.
    /// UI suppresses the recording badge and stop button in this case.
    case rollingBuffer
}

@MainActor
class StreamRecordingService: ObservableObject {
    static let shared = StreamRecordingService()

    @Published var isRecording = false {
        didSet { isRecordingFlag = isRecording }
    }
    /// True when an active writer session was started by the user (not by
    /// the rolling-clip-buffer's background loop). Drives UI like the
    /// recording badge and the toolbar's Stop Recording button.
    @Published var isUserRecording: Bool = false
    /// What initiated the currently active writer session, if any.
    private(set) var currentInitiator: RecordingInitiator?
    @Published var recordingStartTime: Date?
    @Published var mode: StreamingMode = .localFile
    @Published var streamingEnabled = false
    @Published var quality: RecordingQuality = .high
    @Published var recordWithShaders = true
    @Published var streamResolution: StreamResolution = .p1080
    @Published var streamStatus: StreamStatus = .idle
    @Published var streamError: String?

    @Published var customVideoBitrate: Int = 12_000_000
    @Published var customAudioBitrate: Int = 192_000
    @Published var customFrameRate: Int = 60
    @Published var customVideoCodec: RecordingVideoCodec = .h264

    /// The next four AVFoundation writer primitives (`assetWriter`,
    /// `videoInput`, `audioInput`, `pixelBufferAdaptor`) are written on
    /// MainActor at session start/stop and read from the recording queue on
    /// the per-frame hot path (via `appendVideoFrame` / `captureAudioSamples`).
    /// `nonisolated(unsafe)` is the right escape hatch: we never start a new
    /// session until the previous writer is finalized (and these are nil);
    /// the renderer pause-then-resume ordering guarantees non-overlap.
    nonisolated(unsafe) var assetWriter: AVAssetWriter?
    nonisolated(unsafe) var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) var audioInput: AVAssetWriterInput?
    nonisolated(unsafe) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    /// Pool used by the renderer (MetalCoordinator) to obtain recycled
    /// IOSurface-backed CVPixelBuffers for the active recording session. The
    /// GPU blits the frame directly into a buffer pulled from this pool, then
    /// hands it to `appendVideoFrame` on a background queue. Zero CPU copies.
    /// Written on MainActor at session start/stop; read from the renderer
    /// thread — controlled hand-off, not a concurrent race (sessions don't
    /// overlap; pool is replaced only when the previous session is finished).
    nonisolated(unsafe) var pixelBufferPool: CVPixelBufferPool?
    var outputURL: URL?
    nonisolated(unsafe) private var frameCount: Int64 = 0
    nonisolated(unsafe) private var isRecordingFlag: Bool = false

    /// Video dims used by the streaming pipe-write path. Set at session start
    /// (MainActor), read on the recording thread to compute row stride for
    /// raw BGRA writes to the ffmpeg stdin pipe.
    nonisolated(unsafe) var videoSize: CGSize = .zero

    /// Dedicated queue for all back-ground recording work (frame append,
    /// ffmpeg pipe writes, audio capture, writer finalization). Both the
    /// video and audio paths feed through here; nothing recording-related
    /// touches the MainActor on the per-frame hot path. `MetalCoordinator`
    /// hops completed-frame work onto this queue via the static
    /// `appendVideoFrameOnRecordingQueue(...)` entrypoint.
    private let writingQueue = DispatchQueue(label: "com.truchiemu.recording", qos: .userInitiated)
    private var audioTimer: DispatchSourceTimer?
    nonisolated(unsafe) private var audioFramePosition: Int64 = 0
    // Wall-clock anchor set when the session starts. Audio PTS is derived from
    // this (matching video's CACurrentMediaTime scheme in MetalCoordinator) so
    // the two streams stay aligned regardless of how the audio timer lags.
    nonisolated(unsafe) private var audioSessionAnchor: CFTimeInterval = 0

    // Audio capture
    nonisolated(unsafe) var coreAudioSampleRate: Double = 44100
    nonisolated(unsafe) var outputAudioSampleRate: Double = 44100
    /// Reused scratch buffers for the audio capture timer. Allocated once
    /// per session in `startRecording`/`startStreaming`, drained into the
    /// encoder/fifo each tick. Avoids per-tick `[Int16]` / `Data` / `[UInt8]`
    /// allocations on the audio timer's hot path.
    nonisolated(unsafe) private var audioReadScratch: [Int16] = []
    nonisolated(unsafe) private var audioResampleScratch: [Int16] = []

    nonisolated private static let validAACSampleRates: [Double] = [
        8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000
    ]

    nonisolated static func nearestValidAACSampleRate(for rate: Double) -> Double {
        Self.validAACSampleRates.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 44100
    }

    nonisolated static func resampleInterleaved16(_ input: [Int16], from inputRate: Double, to outputRate: Double) -> [Int16] {
        guard inputRate > 0, outputRate > 0, !input.isEmpty else { return input }
        let ratio = inputRate / outputRate
        let outputCount = Int(Double(input.count) / ratio)
        guard outputCount > 0 else { return [] }
        var output = [Int16](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcPos = Double(i) * ratio
            let srcIdx = Int(srcPos)
            guard srcIdx + 1 < input.count else {
                if srcIdx < input.count { output[i] = input[srcIdx] }
                continue
            }
            let frac = srcPos - Double(srcIdx)
            output[i] = Int16(clamping: Int32(input[srcIdx]) + Int32((Double(Int32(input[srcIdx + 1]) - Int32(input[srcIdx])) * frac).rounded()))
        }
        return output
    }

    /// Build an IOSurface-backed `CVPixelBufferPool` for a recording session.
    /// Buffers handed out by this pool are bound by `MetalCoordinator` to a
    /// Metal texture via `CVMetalTextureCacheCreateTextureFromImage`; the GPU
    /// blits directly into the IOSurface, and the encoder consumes the same
    /// buffer — eliminating the per-frame CPU readback that previously caused
    /// the renderer to stall.
    nonisolated static func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        var poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        var pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess else {
            LoggerService.error(category: "Recording", "CVPixelBufferPoolCreate failed: \(status)")
            return nil
        }
        return pool
    }

    /// Obtain a fresh IOSurface-backed `CVPixelBuffer` from the active pool.
    /// Returns `nil` if recording isn't running or the pool is exhausted
    /// (caller may drop the frame in that case — encoder backpressure).
    nonisolated func acquireFramePixelBuffer() -> CVPixelBuffer? {
        guard isRecordingFlag, let pool = pixelBufferPool else { return nil }
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, pool, nil, &pb
        )
        guard status == kCVReturnSuccess else { return nil }
        return pb
    }

    /// Run a closure on the recording service's dedicated background queue.
    /// `MetalCoordinator.performFrameCapture` uses this to hop off the
    /// command-buffer completion handler onto the recording thread, so the
    /// frame append (and any pipe-write for streaming) doesn't block the
    /// renderer's draw loop.
    nonisolated func runOnRecordingQueue(_ body: @escaping @Sendable () -> Void) {
        writingQueue.async(execute: body)
    }

    private let audioChannels: Int = 2

    // RTMPHaishinKit-backed live streaming. Owned only while a non-.localFile
    // mode is active; nil for local recording. Created at startStreaming, torn
    // down at stopStreaming/forceStop. All RTMP handshake + RTMPStatus events
    // live inside this object; we just translate them to our streamStatus enum.
    // Marked `nonisolated(unsafe)` because the per-frame append path runs on
    // the recording queue and reads this to dispatch frames — the same protocol
    // as `videoPipeFD`/`pixelBufferPool`: written on MainActor at session
    // boundaries, read on the recording queue mid-frame.
    nonisolated(unsafe) private(set) var streamingService: RTMPStreamingService?

    private init() {
        signal(SIGPIPE, SIG_IGN)
        loadSettings()
    }

    private func loadSettings() {
        streamingEnabled = AppSettings.getBool("streaming_enabled", defaultValue: false)
        if let raw = AppSettings.getString("streaming_mode") {
            mode = StreamingMode(rawValue: raw) ?? .localFile
        }
        if let raw = AppSettings.getString("streaming_quality") {
            if let q = RecordingQuality(rawValue: raw) {
                quality = q
                applyPreset(q)
            }
        }
        recordWithShaders = AppSettings.getBool("streaming_record_with_shaders", defaultValue: true)
        customVideoBitrate = AppSettings.getInt("streaming_video_bitrate", defaultValue: customVideoBitrate)
        customAudioBitrate = AppSettings.getInt("streaming_audio_bitrate", defaultValue: customAudioBitrate)
        customFrameRate = AppSettings.getInt("streaming_frame_rate", defaultValue: customFrameRate)
        if let raw = AppSettings.getString("streaming_video_codec") {
            customVideoCodec = RecordingVideoCodec(rawValue: raw) ?? .h264
        }
        streamResolution = StreamResolution.load()
    }

    func saveSettings() {
        AppSettings.setBool("streaming_enabled", value: streamingEnabled)
        AppSettings.setString("streaming_mode", value: mode.rawValue)
        AppSettings.setString("streaming_quality", value: quality.rawValue)
        AppSettings.setBool("streaming_record_with_shaders", value: recordWithShaders)
        AppSettings.setInt("streaming_video_bitrate", value: customVideoBitrate)
        AppSettings.setInt("streaming_audio_bitrate", value: customAudioBitrate)
        AppSettings.setInt("streaming_frame_rate", value: customFrameRate)
        AppSettings.setString("streaming_video_codec", value: customVideoCodec.rawValue)
    }

    func applyPreset(_ preset: RecordingQuality) {
        customVideoBitrate = preset.videoBitrate
        customAudioBitrate = preset.audioBitrate
        customFrameRate = preset.frameRate
        customVideoCodec = preset.videoCodec
    }

    static var twitchStreamKey: String? {
        get { AppSettings.getString("streaming_twitch_key") }
        set { AppSettings.setString("streaming_twitch_key", value: newValue) }
    }

    static var youtubeStreamKey: String? {
        get { AppSettings.getString("streaming_youtube_key") }
        set { AppSettings.setString("streaming_youtube_key", value: newValue) }
    }

    static var localOutputPath: String? {
        get { AppSettings.getString("streaming_output_path") }
        set { AppSettings.setString("streaming_output_path", value: newValue) }
    }

    static let defaultTwitchURL = "rtmp://live.twitch.tv/app/"
    static let defaultYoutubeURL = "rtmp://a.rtmp.youtube.com/live2/"

    static var twitchStreamURL: String {
        get { AppSettings.getString("streaming_twitch_url") ?? Self.defaultTwitchURL }
        set { AppSettings.setString("streaming_twitch_url", value: newValue) }
    }

    static var youtubeStreamURL: String {
        get { AppSettings.getString("streaming_youtube_url") ?? Self.defaultYoutubeURL }
        set { AppSettings.setString("streaming_youtube_url", value: newValue) }
    }

    static var customStreamName: String {
        get { AppSettings.getString("streaming_custom_name") ?? "Custom" }
        set { AppSettings.setString("streaming_custom_name", value: newValue) }
    }

    static var customStreamKey: String? {
        get { AppSettings.getString("streaming_custom_key") }
        set { AppSettings.setString("streaming_custom_key", value: newValue) }
    }

    static var customStreamURL: String {
        get { AppSettings.getString("streaming_custom_url") ?? "" }
        set { AppSettings.setString("streaming_custom_url", value: newValue) }
    }

    static func verifyStreamKey(mode: StreamingMode) async -> Result<String, VerifyError> {
        let rtmpURLString: String
        switch mode {
        case .twitch:
            guard let key = twitchStreamKey, !key.isEmpty else {
                return .failure(.noKey("Twitch"))
            }
            rtmpURLString = "\(twitchStreamURL)\(key)"
        case .youtube:
            guard let key = youtubeStreamKey, !key.isEmpty else {
                return .failure(.noKey("YouTube"))
            }
            rtmpURLString = "\(youtubeStreamURL)\(key)"
        case .custom:
            guard let key = customStreamKey, !key.isEmpty else {
                return .failure(.noKey("custom"))
            }
            let url = customStreamURL
            guard !url.isEmpty else {
                return .failure(.noURL)
            }
            rtmpURLString = "\(url)\(key)"
        case .localFile:
            return .failure(.localRecording)
        }

        guard let url = URL(string: rtmpURLString), let host = url.host, !host.isEmpty,
              url.scheme == "rtmp" || url.scheme == "rtmps" else {
            return .failure(.invalidURL)
        }

        return await RTMPStreamingService.verify(rtmpURL: url)
    }

    enum VerifyError: LocalizedError {
        case noKey(String)
        case noURL
        case localRecording
        case invalidURL
        case connectionFailed(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .noKey(let provider): return "No \(provider) stream key configured."
            case .noURL: return "No custom stream URL configured."
            case .localRecording: return "Local recording does not require verification."
            case .invalidURL: return "Invalid stream URL format."
            case .connectionFailed(let detail): return "Connection failed: \(detail)"
            case .timeout: return "Connection timed out after 5 seconds."
            }
        }
    }

    func startRecording(outputURL: URL, width: Int, height: Int, fps: Int = 60, initiator: RecordingInitiator = .user) {
        // User-initiated recording preempts any active rolling-buffer capture.
        if initiator == .user, StreamRecordingService.shared.isRecording {
            // Rolling buffer (or any pre-existing session) is in the writer.
            // Close it cleanly so the user's recording can take over the
            // writer. This produces a finalized chunk file at the buffer's
            // temp URL — preserved on disk for "Save Last X Seconds".
            let buffer = RollingVideoBufferService.shared
            if buffer.isEnabled {
                buffer.suspendActiveCapture()
            } else {
                // Generic teardown in case something else holds the writer.
                StreamRecordingService.shared.stop()
            }
        }
        guard !isRecording else { return }
        // Re-read user-controlled recording settings (codec, bitrate, fps,
        // quality preset) at session start. `loadSettings()` runs once at
        // singleton init, but the user can change these in Settings after
        // the singleton is already constructed — without this, recordings
        // silently use stale settings from launch-time.
        loadSettings()
        self.mode = .localFile
        self.currentInitiator = initiator
        self.isUserRecording = (initiator == .user)
        self.outputURL = outputURL
        self.videoSize = CGSize(width: width, height: height)
        self.frameCount = 0
        coreAudioSampleRate = XPCBridgeAdapter.shared.audioSampleRate()
        outputAudioSampleRate = customVideoCodec.isLossless
            ? coreAudioSampleRate
            : Self.nearestValidAACSampleRate(for: coreAudioSampleRate)

        let actualFPS = customFrameRate > 0 ? customFrameRate : fps
        let codec = customVideoCodec

        let fileManager = FileManager.default
        let parentDir = outputURL.deletingLastPathComponent().path
        if !fileManager.fileExists(atPath: parentDir) {
            try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        let outputFileType: AVFileType = codec.isLossless ? .mov : .mp4
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: outputFileType) else {
            LoggerService.error(category: "Recording", "Failed to create AVAssetWriter")
            return
        }
        assetWriter = writer

        let videoSettings: [String: Any]
        if codec.isLossless {
            videoSettings = [
                AVVideoCodecKey: codec.avCodec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        } else {
            videoSettings = [
                AVVideoCodecKey: codec.avCodec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: customVideoBitrate,
                    AVVideoProfileLevelKey: codec == .h264 ? AVVideoProfileLevelH264HighAutoLevel : (kVTProfileLevel_HEVC_Main_AutoLevel as String),
                    AVVideoExpectedSourceFrameRateKey: actualFPS
                ]
            ]
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = CGAffineTransform.identity
        self.videoInput = videoInput

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        self.pixelBufferAdaptor = adaptor

        let audioFormatID = codec.isLossless ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC
        var audioSettings: [String: Any] = [
            AVFormatIDKey: audioFormatID,
            AVSampleRateKey: outputAudioSampleRate,
            AVNumberOfChannelsKey: audioChannels
        ]
        if codec.isLossless {
            audioSettings[AVLinearPCMIsBigEndianKey] = false
            audioSettings[AVLinearPCMBitDepthKey] = 16
            audioSettings[AVLinearPCMIsFloatKey] = false
            audioSettings[AVLinearPCMIsNonInterleaved] = false
        } else {
            audioSettings[AVEncoderBitRateKey] = customAudioBitrate
        }

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        self.audioInput = audioInput

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }

        if writer.startWriting() {
            writer.startSession(atSourceTime: .zero)
            // Build a self-managed CVPixelBufferPool sized to this session.
            // The renderer pulls IOSurface-backed buffers from here; the GPU
            // blits straight into the IOSurface, so the encoder consumes the
            // very same buffer — no per-frame `getBytes` readback, no Swift
            // `[UInt8]` allocations, no `CVPixelBufferCreate` per frame.
            // (AVAssetWriterInputPixelBufferAdaptor has its own internal pool
            //  too, but exposing ours lets MetalCoordinator bind a Metal
            //  texture to the IOSurface *before* the GPU submit.)
            pixelBufferPool = Self.makePixelBufferPool(width: width, height: height)
            audioReadScratch = [Int16](repeating: 0, count: 4096)
            isRecording = true
            recordingStartTime = Date()
            audioSessionAnchor = CACurrentMediaTime()
            LoggerService.info(category: "Recording", "Started recording to \(outputURL.path)")

            startAudioCapture()
        } else {
            LoggerService.error(category: "Recording", "AVAssetWriter failed to start: \(writer.error?.localizedDescription ?? "unknown")")
            self.videoInput = nil
            self.audioInput = nil
            self.pixelBufferAdaptor = nil
            self.pixelBufferPool = nil
            self.assetWriter = nil
        }
    }

    func startStreaming(mode: StreamingMode, initiator: RecordingInitiator = .user) {
        if initiator == .user, isRecording {
            let buffer = RollingVideoBufferService.shared
            if buffer.isEnabled {
                buffer.suspendActiveCapture()
            } else {
                StreamRecordingService.shared.stop()
            }
        }
        guard !isRecording else { return }
        guard mode != .localFile else { return }
        // Re-read user settings (codec, bitrate, fps) at session start so
        // changes made in Settings after the singleton's first init take
        // effect for the next recording/stream. See `startRecording` for
        // the same rationale.
        loadSettings()
        self.mode = mode
        self.currentInitiator = initiator
        self.isUserRecording = (initiator == .user)
        coreAudioSampleRate = XPCBridgeAdapter.shared.audioSampleRate()
        outputAudioSampleRate = Self.nearestValidAACSampleRate(for: coreAudioSampleRate)

        let streamKey: String?
        switch mode {
        case .twitch:
            streamKey = Self.twitchStreamKey
        case .youtube:
            streamKey = Self.youtubeStreamKey
        case .custom:
            streamKey = Self.customStreamKey
        case .localFile:
            streamKey = nil
        }

        guard let key = streamKey, !key.isEmpty else {
            LoggerService.error(category: "Recording", "No stream key configured for \(mode.rawValue)")
            return
        }

        let rtmpURL: String
        switch mode {
        case .twitch:
            rtmpURL = "\(Self.twitchStreamURL)\(key)"
        case .youtube:
            rtmpURL = "\(Self.youtubeStreamURL)\(key)"
        case .custom:
            let baseURL = Self.customStreamURL
            guard !baseURL.isEmpty else {
                LoggerService.error(category: "Recording", "No custom stream URL configured")
                return
            }
            rtmpURL = "\(baseURL)\(key)"
        case .localFile:
            return
        }

        guard let url = URL(string: rtmpURL) else {
            LoggerService.error(category: "Recording", "Invalid stream URL: \(rtmpURL)")
            return
        }

        // Resolve the desired stream target dims. ProRes is demoted to H.264
        // for streaming (FLV/RTMP doesn't support ProRes); lossless bitrate is
        // bumped to the lossy default so we don't try to RTMP-publish 500Mbps.
        let streamCodec = customVideoCodec.isLossless ? RecordingVideoCodec.h264 : customVideoCodec
        let streamBitrate = customVideoCodec.isLossless ? 12_000_000 : customVideoBitrate

        // Pool size matches the core's aspect ratio at the user's chosen stream
        // resolution so the GPU render-convert pass fills the pool without
        // stretching (Twitch's player letterboxes non-16:9 streams itself).
        // For `.native` we fall back to a 640-wide liquidated size.
        let coreAspect = Double(XPCBridgeAdapter.shared.aspectRatio())
        let poolSize: CGSize
        if let target = streamResolution.size {
            poolSize = Self.aspectPoolSize(target: target, coreAspect: coreAspect)
        } else {
            poolSize = Self.defaultCoreFrameSize(coreAspect: coreAspect)
        }
        pixelBufferPool = Self.makePixelBufferPool(width: Int(poolSize.width), height: Int(poolSize.height))

        // Set up the recording session's audio scratch buffers up-front so the
        // capture timer can't allocate mid-stream.
        audioReadScratch = [Int16](repeating: 0, count: 4096)

        let service = RTMPStreamingService(
            resolution: poolSize,
            fps: customFrameRate > 0 ? customFrameRate : 60,
            videoCodec: streamCodec,
            videoBitrate: streamBitrate,
            audioBitrate: customAudioBitrate,
            audioSampleRate: outputAudioSampleRate
        )
        streamingService = service
        service.onStatus = { [weak self] status in
            self?.applyStreamStatus(status)
        }
        service.onDisconnect = { [weak self] reason in
            self?.applyStreamDisconnect(reason: reason)
        }

        isRecording = true
        recordingStartTime = Date()
        audioSessionAnchor = CACurrentMediaTime()
        streamStatus = .connecting
        LoggerService.info(category: "Recording", "Started streaming to \(mode.rawValue) at \(Int(poolSize.width))x\(Int(poolSize.height)) via HaishinKit")

        Task { @MainActor in
            await service.start(rtmpURL: url)
        }
    }

    private func applyStreamStatus(_ status: RTMPStreamingService.Status) {
        switch status {
        case .idle:
            streamStatus = .idle
        case .connecting:
            // Only meaningful if we haven't already moved on; let .streaming
            // and .failed override.
            if case .streaming = streamStatus { return }
            if case .failed = streamStatus { return }
            streamStatus = .connecting
        case .streaming:
            streamStatus = .streaming
        case .failed(let message):
            streamStatus = .failed(message)
            streamError = message
            clearStreamError()
        }
    }

    private func applyStreamDisconnect(reason: RTMPStreamingService.DisconnectReason) {
        guard isRecordingFlag else { return }
        // Mirrors the old ffmpeg terminationHandler's session teardown but is
        // triggered by a real RTMP failure (rejected key, network drop,
        // timeout) instead of an opaque exit code.
        LoggerService.info(category: "Recording", "stream disconnected: \(reason)")
        if case .userInitiated = reason {
            return
        }
        let wasUserInitiated = (currentInitiator == .user)
        isRecording = false
        isUserRecording = false
        currentInitiator = nil
        streamStatus = .idle
        recordingStartTime = nil
        audioSessionAnchor = 0
        streamingService = nil
        pixelBufferPool = nil
        stopAudioCapture()
        if wasUserInitiated, RollingVideoBufferService.shared.isEnabled {
            RollingVideoBufferService.shared.startCaptureIfReady()
        }
    }

    /// Liquidated stream resolution when the user picks `.native`: 640 wide
    /// scaled to the requested core aspect ratio, falling back to 640×480
    /// when no aspect info is available. Caller can always pass a fixed
    /// `videoSize` instead.
    private static func defaultCoreFrameSize(coreAspect: Double) -> CGSize {
        guard coreAspect > 0 else { return CGSize(width: 640, height: 480) }
        let width: CGFloat = 640
        let height = (width / CGFloat(coreAspect)).rounded()
        return CGSize(width: width, height: max(64, Self.makeEven(height)))
    }

    /// Computes the stream pixel-buffer pool size for a user-chosen stream
    /// resolution (720p / 1080p / 1440p / 4K) and the running core's aspect
    /// ratio. The pool's aspect ratio matches the core's so the GPU render-
    /// convert pass scales source UVs `[0,1]` to fill the pool without
    /// stretching — Twitch's player letterboxes any non-16:9 stream itself,
    /// so we don't pad on our side. The longer side of `target` is preserved
    /// and the shorter side is shrunk by the core aspect, so we never use
    /// more pixels than the chosen resolution target.
    ///
    /// Examples:
    /// - NES (aspect 256:224 ≈ 1.143) at 1080p (1920×1080) → 1235×1080
    /// - SNES (4:3 ≈ 1.333) at 1080p                  → 1440×1080
    /// - N64 (4:3) at 1080p                            → 1440×1080
    /// - Generic 16:9 system at 1080p                  → 1920×1080 (unchanged)
    /// - Game Boy (10:9 ≈ 1.111) at 1080p              → 1200×1080
    /// - Portrait Game Boy (1:1) at 1080p              → 1080×1080
    private static func aspectPoolSize(target: CGSize, coreAspect: Double) -> CGSize {
        guard coreAspect > 0 else { return target }
        let resAspect = target.width / target.height
        let coreAspect = CGFloat(coreAspect)
        if coreAspect > resAspect {
            // Core is wider than the stream target → width-bound.
            let width = target.width
            let height = (width / coreAspect).rounded(.toNearestOrEven)
            return CGSize(width: width, height: max(64, Self.makeEven(height)))
        } else {
            // Core is narrower than (or equal to) the stream target → height-bound.
            let height = target.height
            let width = (height * coreAspect).rounded(.toNearestOrEven)
            return CGSize(width: max(64, Self.makeEven(width)), height: height)
        }
    }

    /// Force a dimension to the nearest even integer. VideoToolbox's H.264/HEVC
    /// encoder requires even source dimensions because NV12 (4:2:0) chroma
    /// planes are half the luma dimensions — an odd width/height would force
    /// non-integer chroma sizes and the encoder's internal `VTPixelTransferSession`
    /// rejects the pixel buffer (err=-536870206). Cores with non-round aspect
    /// ratios (e.g., picodrive's default 10:7 PAR → 1543-wide pool at 1080p)
    /// hit this. Rounding down to even keeps the pool within the chosen stream
    /// resolution target; the encoder's `scalingMode = .letterbox` pads any
    /// residual aspect mismatch during encode.
    private static func makeEven(_ value: CGFloat) -> CGFloat {
        let int = Int(value.rounded())
        return CGFloat(int - (int & 1))
    }

    func forceStop() {
        if isRecording {
            stop()
            return
        }
        guard streamingService != nil || assetWriter != nil else { return }
        if streamingService != nil {
            LoggerService.info(category: "Recording", "forceStop: tearing down RTMP stream service")
            Task { @MainActor in
                await streamingService?.stop()
                streamingService = nil
                streamStatus = .idle
            }
        }
        if let writer = assetWriter {
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            let w = writer
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            pixelBufferAdaptor = nil
            pixelBufferPool = nil
            isUserRecording = false
            currentInitiator = nil
            recordingStartTime = nil
            audioSessionAnchor = 0
            w.finishWriting {
                if let e = w.error {
                    LoggerService.error(category: "Recording", "forceStop writer error: \(e.localizedDescription)")
                }
            }
        }
        pixelBufferPool = nil
        stopAudioCapture()
        streamStatus = .idle
    }

    func stop() {
        guard isRecording else {
            if case .failed = streamStatus { streamStatus = .idle }
            return
        }

        let wasUserInitiated = (currentInitiator == .user)
        isRecording = false
        isUserRecording = false
        currentInitiator = nil
        streamStatus = .idle
        recordingStartTime = nil
        audioSessionAnchor = 0

        stopAudioCapture()

        if streamingService != nil {
            stopStreaming()
        } else if assetWriter != nil {
            stopLocalRecording()
        } else {
            LoggerService.info(category: "Recording", "Recording already stopped externally")
            return
        }

        if wasUserInitiated, RollingVideoBufferService.shared.isEnabled {
            RollingVideoBufferService.shared.startCaptureIfReady()
        }

        LoggerService.info(category: "Recording", "Recording stopped")
    }

    private func stopLocalRecording() {
        guard let writer = assetWriter else { return }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let writerRef = writer
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        pixelBufferPool = nil

        writer.finishWriting {
            if let error = writerRef.error {
                LoggerService.error(category: "Recording", "AVAssetWriter error: \(error.localizedDescription)")
            } else {
                LoggerService.info(category: "Recording", "Recording saved")
            }
        }
    }

    private func stopStreaming() {
        // Capture the service reference, drop our MainActor handle so in-flight
        // frame/audio appenders bail on the next `isRecordingFlag` check (the
        // HaishinKit service's `stop()` is async; cleanly closing both actors
        // takes an unbounded time depending on RTMP server-side finalize).
        guard let service = streamingService else { return }
        streamingService = nil
        pixelBufferPool = nil

        Task { @MainActor in
            await service.stop()
        }
    }

    // MARK: - Frame Capture

    /// Append a captured frame to the active recording. Called from the
    /// renderer's command-buffer completion handler (via
    /// `appendVideoFrameOnRecordingQueue`) on a background queue — never on
    /// the MainActor. `pixelBuffer` is a pool-allocated IOSurface-backed
    /// CVPixelBuffer that the GPU has just finished writing into.
    nonisolated func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecordingFlag else { return }

        // Streaming: hand the IOSurface-backed pixel buffer straight to the
        // RTMPHaishinKit service. No CPU readback, no `[UInt8]` swap, no pipe
        // write. HaishinKit's MediaMixer/VideoCodec handles the encode (H.264
        // / HEVC) and FLV/RTMP mux on its own actor.
        if let streamService = streamingService {
            // Kick the audio capture timer once per streaming session. We use
            // `audioTimer == nil` (not `frameCount == 0`) as the discriminator
            // so this also fires on the SECOND+ stream session in the same
            // app lifetime — frameCount carries over from the previous session
            // because `startStreaming` doesn't reset it.
            //
            // `audioTimer` is MainActor-isolated, so we hop to the MainActor
            // for both the read and the call. `startAudioCapture` itself
            // reschedules, so a redundant Task launch is benign (the second
            // Task that loses the race sees `audioTimer != nil` and no-ops).
            Task { @MainActor in
                guard self.audioTimer == nil else { return }
                LoggerService.info(category: "Recording", "appendVideoFrame: first streaming frame received, kicking audio capture")
                self.startAudioCapture()
            }
            streamService.submitVideoFrame(pixelBuffer, presentationTime: time)
            frameCount &+= 1
            return
        }

        // Local recording: hand the IOSurface-backed pixel buffer directly
        // to the adaptor. No CPU readback, no copy — the encoder reads from
        // the IOSurface on its own thread. Skip the frame when the encoder
        // isn't ready (backpressure) and let the pool reclaim the buffer.
        guard let adaptor = pixelBufferAdaptor, let input = videoInput else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Recording", "appendVideoFrame: skipped — adaptor/videoInput nil (session state) frameCount=\(frameCount)")
            #endif
            return
        }
        guard input.isReadyForMoreMediaData else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Recording", "appendVideoFrame: skipped — encoder backpressure frameCount=\(frameCount)")
            #endif
            return
        }
        if frameCount == 0 {
            LoggerService.info(category: "Recording", "appendVideoFrame: first local frame appended")
        }
        adaptor.append(pixelBuffer, withPresentationTime: time)
        frameCount &+= 1
    }

    private func startAudioCapture() {
        SharedMemoryManager.shared.resetAudioReadPosition()
        audioFramePosition = 0
        let timer = DispatchSource.makeTimerSource(queue: writingQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.captureAudioSamples()
        }
        timer.resume()
        audioTimer = timer
    }

    private func clearStreamError() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { self?.streamError = nil }
        }
    }

    private func stopAudioCapture() {
        audioTimer?.cancel()
        audioTimer = nil
        // Clear the scratch buffers on the writing queue so the teardown is
        // serialized behind any in-flight `captureAudioSamples()` handler.
        // `audioTimer.cancel()` does NOT wait for the currently-executing
        // handler, so resetting these `nonisolated(unsafe)` arrays inline from
        // the MainActor would race a mid-flight copy and fault (empty buffer
        // read → index out of range).
        writingQueue.async { [weak self] in
            self?.audioReadScratch = []
            self?.audioResampleScratch = []
        }
    }

    nonisolated private func captureAudioSamples() {
        guard isRecordingFlag else { return }

        let maxSamples = audioReadScratch.count
        guard maxSamples > 0 else { return }
        let count = audioReadScratch.withUnsafeMutableBufferPointer { ptr in
            SharedMemoryManager.shared.readAudioSamples(into: ptr.baseAddress!, maxCount: maxSamples)
        }
        guard count > 0 else { return }

        // Resample to valid AAC rate if needed. Grows `audioResampleScratch`
        // lazily rather than allocating a fresh `[Int16]` per tick.
        let resampledCount: Int
        if coreAudioSampleRate != outputAudioSampleRate {
            let needed = Int(Double(count) * (outputAudioSampleRate / coreAudioSampleRate)) + 2
            if audioResampleScratch.count < needed {
                audioResampleScratch = [Int16](repeating: 0, count: needed)
            }
            let inputSlice = Array(audioReadScratch[..<count])
            let resampled = Self.resampleInterleaved16(inputSlice, from: coreAudioSampleRate, to: outputAudioSampleRate)
            audioResampleScratch.replaceSubrange(0..<resampled.count, with: resampled)
            resampledCount = resampled.count
        } else {
            // No resample needed — copy the active prefix into the resample
            // scratch so the AVAssetWriter path has one uniform owner for the
            // sample bytes. (Avoids the previous `Array(samples[..<count])`
            // allocation.)
            if audioResampleScratch.count < count {
                audioResampleScratch = [Int16](repeating: 0, count: count)
            }
            audioResampleScratch.withUnsafeMutableBufferPointer { dst in
                audioReadScratch.withUnsafeBufferPointer { src in
                    for i in 0..<count { dst[i] = src[i] }
                }
            }
            resampledCount = count
        }
        guard resampledCount > 0 else { return }

        let sampleCount = resampledCount / audioChannels
        guard sampleCount > 0 else { return }

        // Streaming destination: build an AVAudioPCMBuffer of interleaved
        // s16le PCM and hand it to HaishinKit's RTMPStream via
        // `append(_:when:)`. HaishinKit's AudioCodec re-encodes to AAC using
        // the AudioCodecSettings configured at session start. The CMSampleBuffer
        // path below is only used for local AVAssetWriter recording.
        if let streamService = streamingService {
            if let pcmBuffer = buildAVAudioPCMBuffer(sampleCount: sampleCount) {
                let pts = AVAudioTime(sampleTime: AVAudioFramePosition(audioFramePosition),
                                      atRate: outputAudioSampleRate)
                streamService.submitAudio(pcmBuffer, when: pts)
                audioFramePosition += Int64(sampleCount)
            }
            return
        }

        // Local recording destination: build the PCM s16le CMSampleBuffer only
        // when actually recording to file (avoids CMAudioFormatDescription /
        // CMBlockBuffer alloc on every tick when streaming).
        let sampleBuffer: CMSampleBuffer? = buildAudioSampleBuffer(
            sampleCount: sampleCount,
            byteCount: resampledCount * 2
        )
        guard let sbuf = sampleBuffer else { return }

        // Local recording destination: AVAssetWriter video/audio tracks.
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }
        input.append(sbuf)
        audioFramePosition += Int64(sampleCount)
    }

    /// Build an `AVAudioPCMBuffer` of interleaved s16le PCM at
    /// `outputAudioSampleRate` for HaishinKit's `RTMPStream.append(_:when:)`.
    /// Copy is direct from `audioResampleScratch` into the buffer's
    /// `int16ChannelData`. Caller hands the resulting buffer to
    /// `RTMPStreamingService.submitAudio(_:when:)`.
    nonisolated private func buildAVAudioPCMBuffer(sampleCount: Int) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputAudioSampleRate,
            channels: AVAudioChannelCount(audioChannels),
            interleaved: true
        ) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let frameByteCount = sampleCount * audioChannels * 2
        audioResampleScratch.withUnsafeBufferPointer { src in
            buffer.int16ChannelData?.pointee.withMemoryRebound(to: UInt8.self, capacity: frameByteCount) { dst in
                dst.update(from: src.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: frameByteCount) { $0 }, count: frameByteCount)
            }
        }
        return buffer
    }

    /// Build a `CMSampleBuffer` of uncompressed interleaved s16le PCM at
    /// `outputAudioSampleRate`, with PTS wall-clock-aligned to the video
    /// stream. Caller owns no additional state — both streaming and local
    /// recording consume the same buffer.
    nonisolated private func buildAudioSampleBuffer(sampleCount: Int, byteCount: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: outputAudioSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * audioChannels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * audioChannels),
            mChannelsPerFrame: UInt32(audioChannels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard let fd = formatDesc else { return nil }

        // Allocate the CMBlockBuffer at the resampled sample byte size and
        // copy directly from the scratch buffer — no per-tick Data / [UInt8]
        // allocations.
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return nil }
        audioResampleScratch.withUnsafeBufferPointer { srcPtr in
            _ = srcPtr.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: byteCount) { srcBytes in
                CMBlockBufferReplaceDataBytes(
                    with: srcBytes,
                    blockBuffer: bb,
                    offsetIntoDestination: 0,
                    dataLength: byteCount
                )
            }
        }

        let pts = CMTime(seconds: CACurrentMediaTime() - audioSessionAnchor, preferredTimescale: 600)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: Int64(sampleCount), timescale: Int32(outputAudioSampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fd,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

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

    var ffmpegCodec: String {
        switch self {
        case .h264: return "h264_videotoolbox"
        case .hevc: return "hevc_videotoolbox"
        case .proRes422: return "prores_videotoolbox"
        case .proRes4444: return "prores_videotoolbox"
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
    nonisolated(unsafe) private var videoPipeFD: Int32 = -1

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
    nonisolated(unsafe) private var audioFifoWriteScratch: Data = Data()

    private static let validAACSampleRates: [Double] = [
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

    // ffmpeg streaming. The video pipe fd is read on the per-frame recording
    // thread (`appendVideoFrame`); the other 3 are written at session
    // start/stop on MainActor and only read by the same recording thread.
    private var ffmpegProcess: Process?
    private var ffmpegVideoPipe: Pipe?
    nonisolated(unsafe) private var audioFifoPath: String?
    nonisolated(unsafe) private var audioFifoHandle: FileHandle?

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
        let rtmpURL: String
        switch mode {
        case .twitch:
            guard let key = twitchStreamKey, !key.isEmpty else {
                return .failure(.noKey("Twitch"))
            }
            rtmpURL = "\(twitchStreamURL)\(key)"
        case .youtube:
            guard let key = youtubeStreamKey, !key.isEmpty else {
                return .failure(.noKey("YouTube"))
            }
            rtmpURL = "\(youtubeStreamURL)\(key)"
        case .custom:
            guard let key = customStreamKey, !key.isEmpty else {
                return .failure(.noKey("custom"))
            }
            let url = customStreamURL
            guard !url.isEmpty else {
                return .failure(.noURL)
            }
            rtmpURL = "\(url)\(key)"
        case .localFile:
            return .failure(.localRecording)
        }

        guard let url = URL(string: rtmpURL), let host = url.host, !host.isEmpty else {
            return .failure(.invalidURL)
        }

        let port: UInt16
        if let explicitPort = url.port {
            port = UInt16(explicitPort)
        } else {
            port = 1935
        }

        return await withUnsafeContinuation { continuation in
            var didResume = false
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !didResume else { return }
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: .success("Connected to \(host):\(port)"))
                case .failed(let error):
                    guard !didResume else { return }
                    didResume = true
                    connection.cancel()
                    continuation.resume(returning: .failure(.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(returning: .failure(.timeout))
            }
        }
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

        guard let ffmpegPath = Self.ffmpegPath() else {
            LoggerService.error(category: "Recording", "ffmpeg not found")
            return
        }

        let fifoPath = NSTemporaryDirectory() + "truchiemu_audio_\(UUID().uuidString).pcm"
        self.audioFifoPath = fifoPath
        mkfifo(fifoPath, 0o666)

        // Open the FIFO with O_RDWR before launching ffmpeg — this returns
        // immediately (no blocking), and the handle acts as a persistent writer
        // so ffmpeg's O_RDONLY open also won't block during init.
        let fifoFD = open(fifoPath, O_RDWR)
        if fifoFD >= 0 {
            audioFifoHandle = FileHandle(fileDescriptor: fifoFD, closeOnDealloc: true)
        }

        let streamCodec = customVideoCodec.isLossless ? RecordingVideoCodec.h264 : customVideoCodec
        let streamBitrate = customVideoCodec.isLossless ? 12_000_000 : customVideoBitrate

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)

        process.arguments = [
            "-f", "rawvideo", "-pix_fmt", "bgra",
            "-s", "\(Int(videoSize.width))x\(Int(videoSize.height))",
            "-r", "\(customFrameRate > 0 ? customFrameRate : 60)",
            "-use_wallclock_as_timestamps", "1",
            "-i", "pipe:0",
            "-f", "s16le", "-ar", "\(Int(coreAudioSampleRate))", "-ac", "2",
            "-use_wallclock_as_timestamps", "1",
            "-i", fifoPath,
            "-c:v", streamCodec.ffmpegCodec,
            "-b:v", "\(streamBitrate)",
            "-c:a", "aac",
            "-b:a", "\(customAudioBitrate)",
            "-f", "flv",
            "-flvflags", "no_duration_filesize",
            rtmpURL
        ]

        let videoPipe = Pipe()
        let stderrPath = NSTemporaryDirectory() + "truchiemu_ffmpeg_\(UUID().uuidString.prefix(8)).log"
        let stderrFD = open(stderrPath, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        if stderrFD >= 0 {
            process.standardError = FileHandle(fileDescriptor: stderrFD, closeOnDealloc: true)
        }
        process.standardInput = videoPipe
        self.ffmpegVideoPipe = videoPipe
        self.ffmpegProcess = process
        self.videoPipeFD = videoPipe.fileHandleForWriting.fileDescriptor
        // Mark the video pipe write end non-blocking. If ffmpeg stalls (RTMP
        // handshake, slow VideoToolbox, crashed), `write()` returns EAGAIN
        // instead of blocking the dispatcher frame loop (and freezing stop()).
        let videoFlags = fcntl(self.videoPipeFD, F_GETFL)
        if videoFlags != -1 {
            _ = fcntl(self.videoPipeFD, F_SETFL, videoFlags | O_NONBLOCK)
        }
        LoggerService.info(category: "Recording", "ffmpeg stderr -> \(stderrPath)")

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self = self else { return }
                let exitCode = process.terminationStatus
                guard self.isRecording else { return }
                LoggerService.info(category: "Recording", "ffmpeg terminated (code \(exitCode)): connection dropped, bad key, etc.")
                if exitCode != 0 {
                    self.streamError = "Stream stopped unexpectedly (code \(exitCode))"
                    self.clearStreamError()
                }
                // Full session reset: matching stop()'s state clearance, then
                // offload blocking cleanup to the background queue.
                let wasUserInitiated = (self.currentInitiator == .user)
                let processKill = self.ffmpegProcess
                let pipeClose = self.ffmpegVideoPipe
                let fifoPathClean = self.audioFifoPath
                let fifoHandleClean = self.audioFifoHandle

                self.isUserRecording = false
                self.currentInitiator = nil
                self.isRecording = false
                self.streamStatus = .idle
                self.recordingStartTime = nil
                self.audioSessionAnchor = 0
                self.ffmpegProcess = nil
                self.ffmpegVideoPipe = nil
                self.videoPipeFD = -1
                self.audioFifoPath = nil
                self.audioFifoHandle = nil
                self.pixelBufferPool = nil
                self.audioReadScratch = []
                self.audioResampleScratch = []
                self.audioFifoWriteScratch = Data()
                self.stopAudioCapture()

                self.writingQueue.async {
                    pipeClose?.fileHandleForWriting.closeFile()
                    // ffmpeg already dead; just kill-strike if still alive
                    if let pid = processKill?.processIdentifier, pid > 0 {
                        let dead = (processKill == nil) || !processKill!.isRunning
                        if !dead {
                            Darwin.kill(pid, SIGKILL)
                        }
                    }
                    fifoHandleClean?.closeFile()
                    if let path = fifoPathClean {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }

                if wasUserInitiated, RollingVideoBufferService.shared.isEnabled {
                    RollingVideoBufferService.shared.startCaptureIfReady()
                }
            }
        }

        do {
            try process.run()
            // Set up the recording session's audio scratch buffers and pixel
            // pool up-front so the capture timer / renderer can't allocate
            // mid-stream. There's no AVAssetWriter for streaming (ffmpeg owns
            // the encoder side), so pixelBufferPool stays nil here; the
            // IOSurface-backed pool is only needed for the AVAssetWriter path.
            audioReadScratch = [Int16](repeating: 0, count: 4096)
            isRecording = true
            recordingStartTime = Date()
            audioSessionAnchor = CACurrentMediaTime()
            streamStatus = .connecting
            LoggerService.info(category: "Recording", "Started streaming to \(mode.rawValue), ffmpeg pid \(process.processIdentifier)")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    guard let self = self, case .connecting = self.streamStatus else { return }
                    LoggerService.info(category: "Recording", "Stream assumed connected after 3s")
                    self.streamStatus = .streaming
                }
            }
        } catch {
            streamStatus = .failed("Failed to launch ffmpeg: \(error.localizedDescription)")
            LoggerService.error(category: "Recording", "Failed to launch ffmpeg: \(error.localizedDescription)")
            ffmpegProcess = nil
            ffmpegVideoPipe = nil
            videoPipeFD = -1
            audioFifoHandle?.closeFile()
            audioFifoHandle = nil
            if let path = audioFifoPath {
                try? FileManager.default.removeItem(atPath: path)
                audioFifoPath = nil
            }
        }
    }

    func forceStop() {
        if isRecording {
            stop()
            return
        }
        guard ffmpegProcess != nil || assetWriter != nil else { return }
        if let p = ffmpegProcess, p.isRunning {
            LoggerService.info(category: "Recording", "forceStop: sending SIGKILL to pid \(p.processIdentifier)")
            let processToKill = p
            let pipeToClose = ffmpegVideoPipe
            let fifoPathClean = audioFifoPath
            let fifoHandleClean = audioFifoHandle
            ffmpegProcess = nil
            ffmpegVideoPipe = nil
            videoPipeFD = -1
            audioFifoPath = nil
            audioFifoHandle = nil
            pixelBufferPool = nil
            streamStatus = .idle
            stopAudioCapture()
            writingQueue.async {
                pipeToClose?.fileHandleForWriting.closeFile()
                Darwin.kill(processToKill.processIdentifier, SIGKILL)
                fifoHandleClean?.closeFile()
                if let path = fifoPathClean {
                    try? FileManager.default.removeItem(atPath: path)
                }
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
            stopAudioCapture()
            w.finishWriting {
                if let e = w.error {
                    LoggerService.error(category: "Recording", "forceStop writer error: \(e.localizedDescription)")
                }
            }
        }
        pixelBufferPool = nil
        audioReadScratch = []
        audioResampleScratch = []
        audioFifoWriteScratch = Data()
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

        if ffmpegProcess != nil {
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
        audioReadScratch = []
        audioResampleScratch = []
        audioFifoWriteScratch = Data()

        writer.finishWriting {
            if let error = writerRef.error {
                LoggerService.error(category: "Recording", "AVAssetWriter error: \(error.localizedDescription)")
            } else {
                LoggerService.info(category: "Recording", "Recording saved")
            }
        }
    }

    private func stopStreaming() {
        // Capture everything the background cleanup needs; nil out `@MainActor`
        // references immediately so in-flight frame/audio handlers bail early
        // via `guard isRecording` / `guard fd >= 0`.
        let processToKill = ffmpegProcess
        let pipeToClose = ffmpegVideoPipe
        let fifoPathToClean = audioFifoPath
        let fifoHandleToClean = audioFifoHandle

        ffmpegProcess = nil
        ffmpegVideoPipe = nil
        videoPipeFD = -1
        audioFifoPath = nil
        audioFifoHandle = nil
        pixelBufferPool = nil
        audioReadScratch = []
        audioResampleScratch = []
        audioFifoWriteScratch = Data()

        // Offload all work that may touch file descriptors to a background
        // queue. Closing the video pipe, interrupting ffmpeg, and cleaning the
        // audio FIFO all involve kernel-level syscalls that can block on a
        // congested or zombie process. Doing them on the writingQueue (which
        // already services audio/video writes) keeps the main thread
        // responsive and prevents the deadlock where close() races with an
        // in-flight write() from the per-frame pipe writer.
        writingQueue.async {
            // Tell ffmpeg we're done feeding frames; this sends EOF to stdin
            // so it can finalize its RTMP stream and exit.
            pipeToClose?.fileHandleForWriting.closeFile()

            // Ask ffmpeg to shutdown. SIGINT is part of a graceful exit; if
            // the process is hung in a non-interruptible VideoToolbox or RTMP
            // operation it may not respond immediately. The cancellation
            // observer below enforces a deadline.
            processToKill?.interrupt()

            // If ffmpeg is unresponsive, forcibly kill it after a short grace
            // period so the pipe/FIFO file descriptors don't sit around open.
            if let pid = processToKill?.processIdentifier, pid > 0 {
                let deadline = DispatchTime.now() + .milliseconds(750)
                let killObserver = DispatchWorkItem {
                    let dead: Bool
                    if let p = processToKill {
                        dead = !p.isRunning
                    } else {
                        dead = true
                    }
                    if !dead {
                        LoggerService.info(category: "Recording", "ffmpeg unresponsive — sending SIGKILL to pid \(pid)")
                        Darwin.kill(pid, SIGKILL)
                    }
                }
                DispatchQueue.global(qos: .default).asyncAfter(deadline: deadline, execute: killObserver)
            }

            // Clean FIFO: close the writer handle and remove the temp file.
            fifoHandleToClean?.closeFile()
            if let path = fifoPathToClean {
                try? FileManager.default.removeItem(atPath: path)
            }

            LoggerService.info(category: "Recording", "Streaming cleanup complete")
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

        // Streaming: stream raw BGRA bytes to ffmpeg's stdin pipe. The buffer
        // is already IOSurface-backed; lock for CPU read, write straight to
        // the fd, unlock. No Swift `[UInt8]` buffer, no double-buffer swap.
        if videoPipeFD >= 0 {
            let fd = videoPipeFD
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let h = CVPixelBufferGetHeight(pixelBuffer)
                let rowBytes = Int(videoSize.width) * 4
                writeFrameToPipe(fd, base: base, bytesPerRow: bpr, rowBytes: rowBytes, height: h)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

            if frameCount == 0 {
                // First frame written synchronously — ffmpeg blocks on
                // pipe:0 until data arrives and won't open the audio FIFO
                // otherwise. Start audio capture now so audio data doesn't
                // accumulate in the FIFO before ffmpeg is ready to read it.
                // `startAudioCapture` mutates MainActor-owned `audioTimer`,
                // so hop to MainActor for this one-time kick.
                Task { @MainActor in self.startAudioCapture() }
            }
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

    /// Write the raw BGRA frame bytes to the ffmpeg video pipe (`write(2)`).
    /// Handles EINTR/EAGAIN and drops the rest of a frame on EAGAIN so a
    /// stalled ffmpeg backpressures the publisher rather than blocking it.
    nonisolated private func writeFrameToPipe(_ fd: Int32,
                                             base: UnsafeMutableRawPointer,
                                             bytesPerRow: Int,
                                             rowBytes: Int,
                                             height: Int) {
        if bytesPerRow == rowBytes {
            // Tight layout — single writev span.
            var iov = iovec(iov_base: base, iov_len: Int(rowBytes * height))
            var written = 0
            let total = rowBytes * height
            while written < total {
                let n = writev(fd, &iov, 1)
                if n > 0 {
                    written += n
                    iov.iov_base = base.advanced(by: written)
                    iov.iov_len = total - written
                } else if n < 0 {
                    if errno == EINTR { continue }
                    // EAGAIN/EWOULDBLOCK or any other error: drop the rest
                    // of this frame so the publisher isn't blocked.
                    return
                } else {
                    return
                }
            }
        } else {
            // Padded rows — write each row, skipping the per-row padding.
            let src = base.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                let rowPtr = src.advanced(by: row * bytesPerRow)
                var remaining = rowBytes
                var off = 0
                while remaining > 0 {
                    let n = write(fd, rowPtr.advanced(by: off), remaining)
                    if n > 0 { off += n; remaining -= n }
                    else if n < 0 {
                        if errno == EINTR { continue }
                        return
                    } else {
                        return
                    }
                }
            }
        }
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
    }

    nonisolated private func captureAudioSamples() {
        guard isRecordingFlag else { return }

        let maxSamples = audioReadScratch.count
        guard maxSamples > 0 else { return }
        let count = audioReadScratch.withUnsafeMutableBufferPointer { ptr in
            SharedMemoryManager.shared.readAudioSamples(into: ptr.baseAddress!, maxCount: maxSamples)
        }
        guard count > 0 else { return }

        // Write to ffmpeg FIFO for streaming (uses raw core-rate data,
        // persistent handle). Skip the per-tick `Data(bytes:count:)` alloc
        // by using `FileHandle.write(_:)` with a raw buffer view; the FIFO
        // write path doesn't need to copy the bytes into a Data wrapper.
        if audioFifoPath != nil, let handle = audioFifoHandle {
            audioFifoWriteScratch.withUnsafeMutableBytes { _ in /* ensure capacity */ }
            audioFifoWriteScratch.count = count * 2
            audioReadScratch.withUnsafeBufferPointer { srcPtr in
                audioFifoWriteScratch.withUnsafeMutableBytes { dstPtr in
                    dstPtr.copyBytes(from: UnsafeRawBufferPointer(start: srcPtr.baseAddress!, count: count * 2))
                }
            }
            do {
                try handle.write(contentsOf: audioFifoWriteScratch)
            } catch {
                LoggerService.error(category: "Recording", "Audio FIFO write error: \(error.localizedDescription)")
            }
            return
        }

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

        // Write to AVAssetWriter for local recording
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }

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
        guard let fd = formatDesc else { return }

        // Allocate the CMBlockBuffer at the resampled sample byte size and
        // copy directly from the scratch buffer — no per-tick Data / [UInt8]
        // allocations. The blockBuffer owns its own allocated memory block
        // since we pass `memoryBlock: nil` (allocator-owned), so it's safe
        // to release the scratch buffer immediately after the copy.
        let byteCount = resampledCount * 2
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
        guard blockStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return }
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

        // Derive PTS from a wall-clock anchor that's synchronized with video
        // (which uses CACurrentMediaTime() in MetalCoordinator). Without this
        // the audio and video PTS streams were aligned to different time bases
        // (audioFramePosition/sampleRate vs. now - recordingStartTime), causing
        // the two tracks to drift or split into separate timelines in the
        // output file. Duration is the actual sample run length so the muxer
        // lays out samples over the correct wall-clock window.
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
        if let sbuf = sampleBuffer {
            input.append(sbuf)
            audioFramePosition += Int64(sampleCount)
        }
    }

    // MARK: - ffmpeg Path

    static func ffmpegPath() -> String? {
        if let bundled = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return bundled
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "ffmpeg"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        return nil
    }

    static func isFfmpegAvailable() -> Bool {
        ffmpegPath() != nil
    }
}

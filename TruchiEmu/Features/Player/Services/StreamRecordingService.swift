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

    @Published var customVideoBitrate: Int = 12_000_000
    @Published var customAudioBitrate: Int = 192_000
    @Published var customFrameRate: Int = 60
    @Published var customVideoCodec: RecordingVideoCodec = .h264

    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var outputURL: URL?
    nonisolated(unsafe) private var frameCount: Int64 = 0
    nonisolated(unsafe) private var isRecordingFlag: Bool = false
    nonisolated(unsafe) private var videoPipeFD: Int32 = -1

    // Double-buffered frame staging: main thread writes into one buffer
    // while the background thread drains the other into the pipe.
    nonisolated(unsafe) private var frameBuffers: [[UInt8]] = [[], []]
    nonisolated(unsafe) private var writeBufferIndex: Int = 0
    nonisolated(unsafe) private var readyBufferIndex: Int = -1
    nonisolated(unsafe) private var frameReady: Bool = false
    private let frameLock = NSLock()
    var videoSize: CGSize = .zero

    private let writingQueue = DispatchQueue(label: "com.truchiemu.recording", qos: .userInitiated)
    private let videoWritingQueue = DispatchQueue(label: "com.truchiemu.recording.video", qos: .userInteractive)
    private var audioTimer: DispatchSourceTimer?
    nonisolated(unsafe) private var audioFramePosition: Int64 = 0
    // Wall-clock anchor set when the session starts. Audio PTS is derived from
    // this (matching video's CACurrentMediaTime scheme in MetalCoordinator) so
    // the two streams stay aligned regardless of how the audio timer lags.
    nonisolated(unsafe) private var audioSessionAnchor: CFTimeInterval = 0

    // Audio capture
    private var coreAudioSampleRate: Double = 44100
    private var outputAudioSampleRate: Double = 44100

    private static let validAACSampleRates: [Double] = [
        8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000
    ]

    nonisolated static func nearestValidAACSampleRate(for rate: Double) -> Double {
        validAACSampleRates.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 44100
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

    private let audioChannels: Int = 2

    // ffmpeg streaming
    private var ffmpegProcess: Process?
    private var ffmpegVideoPipe: Pipe?
    private var audioFifoPath: String?
    private var audioFifoHandle: FileHandle?

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
        process.standardInput = videoPipe
        self.ffmpegVideoPipe = videoPipe
        self.ffmpegProcess = process
        self.videoPipeFD = videoPipe.fileHandleForWriting.fileDescriptor

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                LoggerService.info(category: "Recording", "ffmpeg process terminated")
                guard let self = self, self.isRecording else { return }
                self.isRecording = false
                self.stopAudioCapture()
                self.cleanupStreaming()
            }
        }

        do {
            try process.run()
            isRecording = true
            recordingStartTime = Date()
            audioSessionAnchor = CACurrentMediaTime()
            LoggerService.info(category: "Recording", "Started streaming to \(mode.rawValue)")
        } catch {
            LoggerService.error(category: "Recording", "Failed to launch ffmpeg: \(error.localizedDescription)")
            cleanupFifo()
        }
    }

    func stop() {
        guard isRecording else { return }

        let wasUserInitiated = (currentInitiator == .user)
        isRecording = false
        isUserRecording = false
        currentInitiator = nil
        recordingStartTime = nil
        audioSessionAnchor = 0

        stopAudioCapture()

        if ffmpegProcess != nil {
            stopStreaming()
        } else if assetWriter != nil {
            stopLocalRecording()
        } else {
            cleanupStreaming()
            LoggerService.info(category: "Recording", "Recording already stopped externally")
            return
        }

        // If the user-initiated session was preempting an enabled rolling
        // buffer, restart capture so chunks continue to roll.
        if wasUserInitiated, RollingVideoBufferService.shared.isEnabled {
            MainActor.assumeIsolated {
                RollingVideoBufferService.shared.startCaptureIfReady()
            }
        }

        LoggerService.info(category: "Recording", "Recording stopped")
    }

    private func stopLocalRecording() {
        guard let writer = assetWriter else { return }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let writerRef = writer
        let prevAssetWriter = assetWriter
        let prevVideoInput = videoInput
        let prevAudioInput = audioInput
        let prevAdaptor = pixelBufferAdaptor
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil

        writer.finishWriting {
            if let error = writerRef.error {
                LoggerService.error(category: "Recording", "AVAssetWriter error: \(error.localizedDescription)")
            } else {
                LoggerService.info(category: "Recording", "Recording saved")
            }
            _ = prevAssetWriter; _ = prevVideoInput; _ = prevAudioInput; _ = prevAdaptor
        }
    }

    private func stopStreaming() {
        ffmpegVideoPipe?.fileHandleForWriting.closeFile()
        ffmpegProcess?.interrupt()
        cleanupStreaming()
    }

    private func cleanupStreaming() {
        ffmpegProcess = nil
        ffmpegVideoPipe = nil
        videoPipeFD = -1
        frameBuffers = [[], []]
        writeBufferIndex = 0
        readyBufferIndex = -1
        frameReady = false
        cleanupFifo()
    }

    private func cleanupFifo() {
        audioFifoHandle?.closeFile()
        audioFifoHandle = nil
        if let path = audioFifoPath {
            try? FileManager.default.removeItem(atPath: path)
            audioFifoPath = nil
        }
    }

    // MARK: - Frame Capture

    func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording else { return }

        // Streaming: copy pixel data into double buffer, then hand off to
        // background writing thread
        if ffmpegVideoPipe != nil {
            let fd = videoPipeFD
            guard fd >= 0 else { return }

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let h = CVPixelBufferGetHeight(pixelBuffer)
                let rowBytes = Int(videoSize.width) * 4
                let frameSize = h * rowBytes

                frameLock.lock()
                let idx = writeBufferIndex
                if frameBuffers[idx].count != frameSize {
                    frameBuffers[idx] = [UInt8](repeating: 0, count: frameSize)
                }
                frameLock.unlock()

                let src = base.assumingMemoryBound(to: UInt8.self)
                if bpr == rowBytes {
                    frameBuffers[idx].withUnsafeMutableBufferPointer { dst in
                        dst.baseAddress!.initialize(from: src, count: frameSize)
                    }
                } else {
                    for row in 0..<h {
                        frameBuffers[idx].withUnsafeMutableBufferPointer { dst in
                            dst.baseAddress!.advanced(by: row * rowBytes)
                                .initialize(from: src.advanced(by: row * bpr),
                                            count: rowBytes)
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

            // Swap: the buffer we just wrote becomes the ready buffer
            frameLock.lock()
            let readyIdx = writeBufferIndex
            writeBufferIndex = writeBufferIndex == 0 ? 1 : 0
            readyBufferIndex = readyIdx
            frameReady = true
            frameLock.unlock()

            if frameCount == 0 {
                // First frame written synchronously — ffmpeg blocks on pipe:0
                // until data arrives and won't open the audio FIFO otherwise.
                // Start audio capture now so audio data doesn't accumulate
                // in the FIFO before ffmpeg is ready to read it.
                drainFrameBuffer(to: fd)
                startAudioCapture()
            } else {
                videoWritingQueue.async { [weak self] in
                    guard let self = self, self.isRecordingFlag else { return }
                    self.drainFrameBuffer(to: fd)
                }
            }
            frameCount += 1
            return
        }

        // Local recording: append to AVAssetWriter
        guard let adaptor = pixelBufferAdaptor, let input = videoInput, input.isReadyForMoreMediaData else {
            return
        }
        adaptor.append(pixelBuffer, withPresentationTime: time)
        frameCount += 1
    }

    // MARK: - Audio Capture

    private func drainFrameBuffer(to fd: Int32) {
        frameLock.lock()
        guard frameReady, readyBufferIndex >= 0 else {
            frameLock.unlock()
            return
        }
        let idx = readyBufferIndex
        let buf = frameBuffers[idx]
        frameReady = false
        frameLock.unlock()

        let total = buf.count
        guard total > 0 else { return }
        buf.withUnsafeBufferPointer { ptr in
            var written = 0
            while written < total {
                let n = write(fd, ptr.baseAddress! + written, total - written)
                if n > 0 { written += n }
                else if n < 0 && errno != EINTR { break }
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

    private func stopAudioCapture() {
        audioTimer?.cancel()
        audioTimer = nil
    }

    private func captureAudioSamples() {
        guard isRecording else { return }

        let maxSamples = 4096
        var samples = [Int16](repeating: 0, count: maxSamples)
        let count = samples.withUnsafeMutableBufferPointer { ptr in
            SharedMemoryManager.shared.readAudioSamples(into: ptr.baseAddress!, maxCount: maxSamples)
        }
        guard count > 0 else { return }

        // Write to ffmpeg FIFO for streaming (uses raw core-rate data, persistent handle)
        if audioFifoPath != nil, let handle = audioFifoHandle {
            let data = Data(bytes: samples, count: count * 2)
            do {
                try handle.write(contentsOf: data)
            } catch {
                LoggerService.error(category: "Recording", "Audio FIFO write error: \(error.localizedDescription)")
            }
            return
        }

        // Resample to valid AAC rate if needed
        var resampledSamples: [Int16]
        let resampledCount: Int
        if coreAudioSampleRate != outputAudioSampleRate {
            resampledSamples = Self.resampleInterleaved16(Array(samples[..<count]), from: coreAudioSampleRate, to: outputAudioSampleRate)
            resampledCount = resampledSamples.count
        } else {
            resampledSamples = Array(samples[..<count])
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

        var blockBuffer: CMBlockBuffer?
        let audioData = Data(bytes: resampledSamples, count: resampledCount * 2)
        let bytes = [UInt8](audioData)
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return }
        CMBlockBufferReplaceDataBytes(with: bytes, blockBuffer: bb, offsetIntoDestination: 0, dataLength: bytes.count)

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

import AVFAudio
import AVFoundation
import CoreMedia
import Foundation
import HaishinKit
import RTMPHaishinKit
import VideoToolbox

/// Live RTMP streaming via HaishinKit's in-process VideoToolbox + RTMP client.
///
/// Owned by `StreamRecordingService` when `mode != .localFile`. Receives
/// captured frames from `MetalCoordinator.performFrameCapture` (BGRA,
/// IOSurface-backed, sized to the user-selected `StreamResolution`) and audio
/// `AVAudioPCMBuffer`s from the shared audio capture timer.
///
/// Uses HaishinKit's `RTMPSession` (via `SessionBuilderFactory`) which handles
/// the RTMP URL → (tcUrl, streamName) split mandated by Twitch/YouTube: the
/// `rtmp://host/app/<key>` URL is decomposed so `connect` only sends
/// `rtmp://host/app` and `publish` carries `<key>`. Drives status via
/// `Session.readyState` (`.connecting` → `.open` → `.closed`) and surfaces
/// underlying `RTMPConnection.Error` / `RTMPStream.Error` through the thrown
/// error path on `connect`.
///
/// Replaces the previous ffmpeg-subprocess + raw-BGRA-pipe streaming path
/// (silent frame drops, fake "connected after 3s" status) and an earlier
/// direct-`RTMPConnection.connect` attempt that stuffed the stream key into
/// the RTMP `app` parameter so Twitch silently dropped every publish.
@MainActor
final class RTMPStreamingService {
    /// High-level status surfaced to upstream UI.
    enum Status: Equatable {
        case idle
        case connecting
        case streaming
        case failed(String)
    }

    /// Why the connection dropped. Already localized upstream.
    enum DisconnectReason: Sendable {
        case userInitiated
        case serverRejected
        case networkUnreachable
        case timeout
        case other(String)
    }

    weak var statusDelegate: AnyObject?

    private var session: (any Session)?
    private var rtmpStream: (any StreamConvertible)?
    private let videoSettings: VideoCodecSettings
    private let audioSettings: AudioCodecSettings
    private var readyStateTask: Task<Void, Never>?
    private var isConnected = false
    // Frame counters for periodic debug logging — nonisolated(unsafe) because
    // the per-frame hot path (submitVideoFrame/submitAudio) is called off the
    // MainActor. Throttled to one log line per 60 frames.
    nonisolated(unsafe) private var videoFrameCount: Int64 = 0
    nonisolated(unsafe) private var audioFrameCount: Int64 = 0
    nonisolated(unsafe) private var lastVideoLogTime: Date = .distantPast
    nonisolated(unsafe) private var lastAudioLogTime: Date = .distantPast

    var onStatus: (@MainActor (Status) -> Void)?
    var onDisconnect: (@MainActor (DisconnectReason) -> Void)?

    init(resolution: CGSize,
         fps: Int,
         videoCodec: RecordingVideoCodec,
         videoBitrate: Int,
         audioBitrate: Int,
         audioSampleRate: Double) {
        self.videoSettings = Self.makeVideoSettings(
            resolution: resolution,
            fps: fps,
            videoCodec: videoCodec,
            videoBitrate: videoBitrate
        )
        self.audioSettings = AudioCodecSettings(
            bitRate: audioBitrate,
            downmix: true,
            sampleRate: audioSampleRate,
            format: .aac
        )
    }

    private static func makeVideoSettings(resolution: CGSize,
                                          fps: Int,
                                          videoCodec: RecordingVideoCodec,
                                          videoBitrate: Int) -> VideoCodecSettings {
        let profileLevel: String
        switch videoCodec {
        case .hevc:
            profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel as String
        case .h264, .proRes422, .proRes4444:
            fallthrough
        @unknown default:
            profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
        }
        var settings = VideoCodecSettings(
            videoSize: resolution,
            bitRate: videoBitrate,
            profileLevel: profileLevel,
            scalingMode: .letterbox,
            maxKeyFrameIntervalDuration: 2,
            // Disable B-frames for live streaming. allowFrameReordering == true
            // produces B-frames whose dependency chain breaks on any dropped frame
            // between keyframes — the decoder shows "shadow" then "snap-to-position"
            // artifacts (Mario appears to move via a ghost copy, then blips forward
            // when the next keyframe resets the prediction). P-frames-only in
            // presentation order fits live RTMP / low-latency rate control.
            allowFrameReordering: false,
            dataRateLimits: nil,
            isLowLatencyRateControlEnabled: true,
            isHardwareAcceleratedEnabled: true,
            expectedFrameRate: Double(fps)
        )
        settings.bitRateMode = .average
        return settings
    }

    // MARK: - Lifecycle

    /// Open the RTMP connection and begin publishing. `rtmpURL` is the full
    /// `rtmp://host/app/<streamKey>` URL; HaishinKit's `RTMPSession` splits it
    /// into tcUrl + streamName internally (`RTMPURL.command` / `.streamName`).
    func start(rtmpURL: URL) async {
        guard let session = try? await SessionBuilderFactory.shared.make(rtmpURL)
            .setMode(.publish)
            .build() else {
            let msg = LocalizationManager.shared.localized("settings.streaming.connection.failed")
            onStatus?(.failed(msg))
            onDisconnect?(.other("SessionBuilderFactory returned nil"))
            return
        }
        self.session = session

        do {
            if let stream = await session.stream as? RTMPStream {
                try? await stream.setVideoSettings(videoSettings)
                try? await stream.setAudioSettings(audioSettings)
                self.rtmpStream = stream
            }
        }

        startReadyStateListener()

        onStatus?(.connecting)
        do {
            try await session.connect { [weak self] in
                Task { @MainActor in
                    self?.handleDisconnect(reason: .userInitiated)
                }
            }
            isConnected = true
            onStatus?(.streaming)
        } catch let err as RTMPConnection.Error {
            LoggerService.error(category: "RTMP", "connect failed: \(err)")
            let reason = mapConnectionError(err)
            onStatus?(.failed(localizedFailure(for: reason)))
            onDisconnect?(reason)
        } catch let err as RTMPStream.Error {
            LoggerService.error(category: "RTMP", "publish failed: \(err)")
            let reason = mapStreamError(err)
            onStatus?(.failed(localizedFailure(for: reason)))
            onDisconnect?(reason)
        } catch {
            LoggerService.error(category: "RTMP", "session.connect failed: \(error)")
            let reason = DisconnectReason.other(error.localizedDescription)
            onStatus?(.failed(localizedFailure(for: reason)))
            onDisconnect?(reason)
        }
    }

    /// Gracefully close the session and connection. Safe to call multiple times.
    func stop() async {
        readyStateTask?.cancel()
        readyStateTask = nil
        if let session {
            _ = try? await session.close()
        }
        isConnected = false
        session = nil
        rtmpStream = nil
    }

    /// Real-handshake probe used by the Settings page "Verify" button.
    /// Opens a publish-mode session, awaits `.open`, then closes — surfaces the
    /// underlying RTMP error if the connect/publish handshake fails.
    static func verify(rtmpURL: URL) async -> Result<String, StreamRecordingService.VerifyError> {
        guard let session = try? await SessionBuilderFactory.shared.make(rtmpURL)
            .setMode(.publish)
            .build() else {
            return .failure(.connectionFailed("SessionBuilderFactory returned nil"))
        }
        // Materialize the RTMPStream BEFORE connecting so it registers with the
        // connection (via `RTMPStream.init` → `connection.addStream`). On a
        // successful connect, `RTMPConnection.connect` iterates its registered
        // streams and calls `createStream()` on each — which assigns the real
        // RTMP stream id that the subsequent publish handshake needs. The live
        // `start()` path does this implicitly by touching `session.stream` to
        // set video/audio settings; without it here the publish races its own
        // async stream registration and times out, so verification fails even
        // though real streaming works.
        _ = await session.stream
        do {
            try await session.connect { }
            _ = try? await session.close()
            return .success("Connected")
        } catch let err as RTMPConnection.Error {
            _ = try? await session.close()
            switch err {
            case .connectionTimedOut:
                return .failure(.timeout)
            case .socketErrorOccurred:
                return .failure(.connectionFailed("Network unreachable"))
            case .requestFailed(let response):
                return .failure(.connectionFailed(response.status?.description ?? "Rejected"))
            default:
                return .failure(.connectionFailed("\(err)"))
            }
        } catch let err as RTMPStream.Error {
            _ = try? await session.close()
            switch err {
            case .requestTimedOut:
                return .failure(.timeout)
            default:
                return .failure(.connectionFailed("\(err)"))
            }
        } catch {
            _ = try? await session.close()
            return .failure(.connectionFailed(error.localizedDescription))
        }
    }

    // MARK: - Frame submission (called from renderer / audio timer)

    /// Append a captured video frame. BGRA CVPixelBuffer sized to `resolution`
    /// passed at init. HaishinKit's `RTMPStream.append(_ sampleBuffer:)` routes
    /// uncompressed video through `OutgoingStream` → `VideoCodec`
    /// (VideoToolbox H.264/HEVC encode) → back as a compressed CMSampleBuffer
    /// → `RTMPVideoMessage` chunks → TCP.
    nonisolated func submitVideoFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        videoFrameCount &+= 1
        // Throttled log: once per second. INFO level so it appears under the
        // default log level. Confirms frames are arriving at the service.
        let now = Date()
        if now.timeIntervalSince(lastVideoLogTime) > 1.0 {
            lastVideoLogTime = now
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let fmtStr = String(format: "0x%08X", fmt)
            LoggerService.info(category: "RTMP",
                "submitVideoFrame #\(videoFrameCount) \(w)x\(h) fmt=\(fmtStr) pts=\(presentationTime.seconds)s")
        }

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let desc = formatDesc else {
            LoggerService.error(category: "RTMP", "submitVideoFrame: CMVideoFormatDescriptionCreateForImageBuffer failed for BGRA pixel buffer")
            return
        }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sbuf = sampleBuffer else {
            LoggerService.error(category: "RTMP", "submitVideoFrame: CMSampleBufferCreateReadyWithImageBuffer failed")
            return
        }
        Task { await rtmpStream?.append(sbuf) }
    }

    /// Append captured PCM audio. `pcmBuffer` must be interleaved s16le at
    /// `audioSettings.sampleRate`. HaishinKit's `RTMPStream.append(_:when:)`
    /// routes `AVAudioPCMBuffer` through `AudioCodec` (AAC encode) → FLV/RTMP.
    nonisolated func submitAudio(_ pcmBuffer: AVAudioPCMBuffer, when: AVAudioTime) {
        audioFrameCount &+= 1
        let now = Date()
        if now.timeIntervalSince(lastAudioLogTime) > 1.0 {
            lastAudioLogTime = now
            LoggerService.info(category: "RTMP",
                "submitAudio #\(audioFrameCount) frames=\(pcmBuffer.frameLength) rate=\(pcmBuffer.format.sampleRate) ch=\(pcmBuffer.format.channelCount) pts=\(when.sampleTime)")
        }
        Task { await rtmpStream?.append(pcmBuffer, when: when) }
    }

    // MARK: - Status translation

    @MainActor
    private func startReadyStateListener() {
        guard let session else { return }
        readyStateTask = Task { [weak self] in
            for await readyState in await session.readyState {
                guard !Task.isCancelled else { return }
                self?.handleReadyState(readyState)
            }
        }
    }

    @MainActor
    private func handleReadyState(_ readyState: SessionReadyState) {
        LoggerService.info(category: "RTMP", "session readyState: \(readyState)")
        switch readyState {
        case .connecting:
            // Only set if we haven't already moved past connecting.
            if !isConnected {
                onStatus?(.connecting)
            }
        case .open:
            isConnected = true
            onStatus?(.streaming)
        case .closing:
            break
        case .closed:
            handleDisconnect(reason: isConnected ? .userInitiated : .networkUnreachable)
        }
    }

    @MainActor
    private func handleDisconnect(reason: DisconnectReason) {
        guard isConnected else {
            // Was never connected — surface as failure unless we already did.
            return
        }
        isConnected = false
        if case .userInitiated = reason {
            // Clean stop from above.
            return
        }
        onStatus?(.failed(localizedFailure(for: reason)))
        onDisconnect?(reason)
    }

    private func mapConnectionError(_ err: RTMPConnection.Error) -> DisconnectReason {
        switch err {
        case .connectionTimedOut: return .timeout
        case .socketErrorOccurred: return .networkUnreachable
        case .requestFailed(let resp):
            if resp.status?.code == RTMPConnection.Code.connectRejected.rawValue {
                return .serverRejected
            }
            return .other(resp.status?.description ?? "\(err)")
        default: return .other("\(err)")
        }
    }

    private func mapStreamError(_ err: RTMPStream.Error) -> DisconnectReason {
        switch err {
        case .requestTimedOut: return .timeout
        default: return .other("\(err)")
        }
    }

    private func localizedFailure(for reason: DisconnectReason) -> String {
        switch reason {
        case .serverRejected:
            return LocalizationManager.shared.localized("settings.streaming.connection.invalidKey")
        case .networkUnreachable:
            return LocalizationManager.shared.localized("settings.streaming.connection.hostUnreachable")
        case .timeout:
            return LocalizationManager.shared.localized("settings.streaming.connection.hostUnreachable")
        case .other(let msg):
            return LocalizationManager.shared.localized("settings.streaming.connection.failed") + " (\(msg))"
        case .userInitiated:
            return ""
        }
    }
}

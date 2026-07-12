import Foundation

struct MediaConfig {
    var streaming: StreamingSection
    var quality: QualitySection
    var destinations: DestinationsSection
    var output: OutputSection
    var screenshot: ScreenshotSection
    var share: ShareSection
    var rollingBuffer: RollingBufferSection
    var recordingBadge: BadgeSection
    var streamingBadge: BadgeSection

    static func load() -> MediaConfig {
        let s = StreamingSection.load()
        return MediaConfig(
            streaming: s,
            quality: QualitySection.load(from: s),
            destinations: DestinationsSection.load(),
            output: OutputSection.load(),
            screenshot: ScreenshotSection.load(),
            share: ShareSection.load(),
            rollingBuffer: RollingBufferSection.load(),
            recordingBadge: BadgeSection.load(keyPrefix: "recording_badge"),
            streamingBadge: BadgeSection.load(keyPrefix: "streaming_badge")
        )
    }

    struct StreamingSection: Equatable {
        var enabled: Bool
        var recordWithShaders: Bool
        var resolution: StreamResolution

        static func load() -> StreamingSection {
            StreamingSection(
                enabled: AppSettings.getBool("streaming_enabled", defaultValue: false),
                recordWithShaders: AppSettings.getBool("streaming_record_with_shaders", defaultValue: true),
                resolution: StreamResolution.load()
            )
        }

        func save() {
            AppSettings.setBool("streaming_enabled", value: enabled)
            AppSettings.setBool("streaming_record_with_shaders", value: recordWithShaders)
            resolution.save()
        }
    }

    struct QualitySection: Equatable {
        var preset: RecordingQuality
        var codec: RecordingVideoCodec
        var videoBitrate: Int
        var audioBitrate: Int
        var frameRate: Int
        var customized: Bool

        static func load(from streaming: StreamingSection) -> QualitySection {
            let preset: RecordingQuality = {
                if let raw = AppSettings.getString("streaming_quality"),
                   let q = RecordingQuality(rawValue: raw) {
                    return q
                }
                return .high
            }()
            let codec: RecordingVideoCodec = {
                if let raw = AppSettings.getString("streaming_video_codec"),
                   let c = RecordingVideoCodec(rawValue: raw) {
                    return c
                }
                return preset.videoCodec
            }()
            let videoBitrate = AppSettings.getInt("streaming_video_bitrate", defaultValue: preset.videoBitrate)
            let audioBitrate = AppSettings.getInt("streaming_audio_bitrate", defaultValue: preset.audioBitrate)
            let frameRate = AppSettings.getInt("streaming_frame_rate", defaultValue: preset.frameRate)
            let customized = videoBitrate != preset.videoBitrate
                || audioBitrate != preset.audioBitrate
                || frameRate != preset.frameRate
                || codec != preset.videoCodec
            return QualitySection(
                preset: preset,
                codec: codec,
                videoBitrate: videoBitrate,
                audioBitrate: audioBitrate,
                frameRate: frameRate,
                customized: customized
            )
        }

        func save() {
            AppSettings.setString("streaming_quality", value: preset.rawValue)
            AppSettings.setString("streaming_video_codec", value: codec.rawValue)
            AppSettings.setInt("streaming_video_bitrate", value: videoBitrate)
            AppSettings.setInt("streaming_audio_bitrate", value: audioBitrate)
            AppSettings.setInt("streaming_frame_rate", value: frameRate)
        }

        mutating func applyPreset(_ preset: RecordingQuality) {
            self.preset = preset
            self.codec = preset.videoCodec
            self.videoBitrate = preset.videoBitrate
            self.audioBitrate = preset.audioBitrate
            self.frameRate = preset.frameRate
            self.customized = false
        }

        var summaryText: String {
            "\(codec.shortLabel) · \(formattedBitrate) · \(frameRate) fps"
        }

        var formattedBitrate: String {
            if codec.isLossless {
                return "Lossless"
            }
            let mbps = Double(videoBitrate) / 1_000_000.0
            if mbps >= 1 {
                return String(format: "%.1f Mbps", mbps)
            }
            return String(format: "%.0f kbps", Double(videoBitrate) / 1_000.0)
        }
    }

    struct DestinationsSection: Equatable {
        var twitchKey: String
        var twitchURL: String
        var youtubeKey: String
        var youtubeURL: String
        var customName: String
        var customKey: String
        var customURL: String

        private static let defaultTwitchURL = "rtmp://live.twitch.tv/app/"
        private static let defaultYoutubeURL = "rtmp://a.rtmp.youtube.com/live2/"

        static func load() -> DestinationsSection {
            DestinationsSection(
                twitchKey: AppSettings.getString("streaming_twitch_key") ?? "",
                twitchURL: AppSettings.getString("streaming_twitch_url") ?? defaultTwitchURL,
                youtubeKey: AppSettings.getString("streaming_youtube_key") ?? "",
                youtubeURL: AppSettings.getString("streaming_youtube_url") ?? defaultYoutubeURL,
                customName: AppSettings.getString("streaming_custom_name") ?? "Custom",
                customKey: AppSettings.getString("streaming_custom_key") ?? "",
                customURL: AppSettings.getString("streaming_custom_url") ?? ""
            )
        }

        func save() {
            AppSettings.setString("streaming_twitch_key", value: twitchKey.isEmpty ? nil : twitchKey)
            AppSettings.setString("streaming_twitch_url", value: twitchURL)
            AppSettings.setString("streaming_youtube_key", value: youtubeKey.isEmpty ? nil : youtubeKey)
            AppSettings.setString("streaming_youtube_url", value: youtubeURL)
            AppSettings.setString("streaming_custom_name", value: customName)
            AppSettings.setString("streaming_custom_key", value: customKey.isEmpty ? nil : customKey)
            AppSettings.setString("streaming_custom_url", value: customURL)
        }

        var twitchConfigured: Bool { !twitchKey.isEmpty }
        var youtubeConfigured: Bool { !youtubeKey.isEmpty }
        var customConfigured: Bool { !customKey.isEmpty && !customURL.isEmpty }
    }

    struct OutputSection: Equatable {
        var localPath: String

        static func load() -> OutputSection {
            OutputSection(localPath: AppSettings.getString("streaming_output_path") ?? "")
        }

        func save() {
            AppSettings.setString("streaming_output_path", value: localPath.isEmpty ? nil : localPath)
        }

        var hasPath: Bool { !localPath.isEmpty }
    }

    struct ScreenshotSection: Equatable {
        var includeNative: Bool
        var outputPath: String

        static func load() -> ScreenshotSection {
            ScreenshotSection(
                includeNative: AppSettings.getBool("screenshot_include_native", defaultValue: false),
                outputPath: AppSettings.getString("screenshot_output_path") ?? ""
            )
        }

        func save() {
            AppSettings.setBool("screenshot_include_native", value: includeNative)
            AppSettings.setString("screenshot_output_path", value: outputPath.isEmpty ? nil : outputPath)
        }

        var hasCustomPath: Bool { !outputPath.isEmpty }
    }

    struct ShareSection: Equatable {
        var singlePress: ShareBehavior
        var longPress: ShareBehavior

        static func load() -> ShareSection {
            let cfg = ShareButtonConfig.load()
            return ShareSection(singlePress: cfg.singlePress, longPress: cfg.longPress)
        }

        func save() {
            let cfg = ShareButtonConfig(singlePress: singlePress, longPress: longPress)
            cfg.save()
        }
    }

    struct RollingBufferSection: Equatable {
        var enabled: Bool
        var duration: RollingBufferDuration
        var customSeconds: Double
        var recordDisplayResolution: Bool

        static func load() -> RollingBufferSection {
            let cfg = RollingBufferConfig.load()
            return RollingBufferSection(
                enabled: cfg.enabled,
                duration: cfg.duration,
                customSeconds: cfg.duration.actualDuration,
                recordDisplayResolution: cfg.recordDisplayResolution
            )
        }

        func save() {
            var cfg = RollingBufferConfig()
            cfg.enabled = enabled
            cfg.duration = duration
            cfg.recordDisplayResolution = recordDisplayResolution
            cfg.save()
        }

        var effectiveSeconds: Double {
            duration == .custom ? customSeconds : duration.actualDuration
        }

        func estimatedFileSizeMB() -> Double {
            let bytesPerSec = (12_000_000.0 + 128_000.0) / 8.0
            return bytesPerSec * effectiveSeconds / (1024.0 * 1024.0)
        }
    }

    struct BadgeSection: Equatable {
        var enabled: Bool
        var position: BadgePosition

        static func load(keyPrefix: String) -> BadgeSection {
            BadgeSection(
                enabled: AppSettings.getBool("\(keyPrefix)_enabled", defaultValue: true),
                position: BadgePosition(rawValue: AppSettings.getInt("\(keyPrefix)_position", defaultValue: 1)) ?? .topRight
            )
        }

        func save(keyPrefix: String) {
            AppSettings.setBool("\(keyPrefix)_enabled", value: enabled)
            AppSettings.setInt("\(keyPrefix)_position", value: position.rawValue)
        }
    }
}

extension RecordingVideoCodec {
    var shortLabel: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes422: return "ProRes 422"
        case .proRes4444: return "ProRes 4444"
        }
    }
}

enum StreamResolution: String, CaseIterable, Identifiable {
    case native
    case p720
    case p1080
    case p1440
    case p4k

    var id: String { rawValue }

    /// Returns the stream's pixel dimensions, or `nil` for `.native` (size
    /// follows the raw core frame / post-shader drawable).
    var size: CGSize? {
        switch self {
        case .native: return nil
        case .p720:   return CGSize(width: 1280, height: 720)
        case .p1080:  return CGSize(width: 1920, height: 1080)
        case .p1440:  return CGSize(width: 2560, height: 1440)
        case .p4k:    return CGSize(width: 3840, height: 2160)
        }
    }

    var localizationKey: String {
        switch self {
        case .native: return "settings.streaming.resolution.native"
        case .p720:   return "settings.streaming.resolution.720p"
        case .p1080:  return "settings.streaming.resolution.1080p"
        case .p1440:  return "settings.streaming.resolution.1440p"
        case .p4k:    return "settings.streaming.resolution.4k"
        }
    }

    private static let storageKey = "streaming_resolution"

    static func load() -> StreamResolution {
        guard let raw = AppSettings.getString(storageKey),
              let res = StreamResolution(rawValue: raw) else {
            return .p1080
        }
        return res
    }

    func save() {
        AppSettings.setString(Self.storageKey, value: rawValue)
    }
}

enum MediaTab: String, CaseIterable, Identifiable {
    case recording
    case streaming
    case screenshots
    case sharing
    case hotkeys

    var id: String { rawValue }

    var localizationKey: String {
        "settings.media.tab." + rawValue
    }

    private static let storageKey = "media.activeTab"

    static func load() -> MediaTab {
        guard let raw = AppSettings.getString(storageKey),
              let tab = MediaTab(rawValue: raw) else {
            return .recording
        }
        return tab
    }

    func save() {
        AppSettings.setString(Self.storageKey, value: rawValue)
    }
}

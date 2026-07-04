import Foundation
import SwiftUI

extension MediaConfig {
    func availableShareBehaviors(rollingBufferEnabled: Bool? = nil) -> [ShareBehavior] {
        let isRollingEnabled = rollingBufferEnabled ?? rollingBuffer.enabled
        return ShareBehavior.allCases.filter { behavior in
            !behavior.requiresRollingBuffer || isRollingEnabled
        }
    }

    func qualityCustomizationExpanded(defaultFor quality: RecordingQuality) -> Bool {
        let key = "media.qualityCustomizationExpanded.\(quality.rawValue)"
        if let data = AppSettings.getData(key), !data.isEmpty { return true }
        return AppSettings.getBool(key, defaultValue: false)
    }

    func setQualityCustomizationExpanded(_ expanded: Bool, for quality: RecordingQuality) {
        AppSettings.setBool("media.qualityCustomizationExpanded.\(quality.rawValue)", value: expanded)
    }
}

extension MediaConfig.DestinationsSection {
    var configuredCount: Int {
        var count = 0
        if twitchConfigured { count += 1 }
        if youtubeConfigured { count += 1 }
        if customConfigured { count += 1 }
        return count
    }
}

enum MediaConfigHelpers {
    static func formatDurationSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60
        let s = total % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

import AppKit

/// Centralized tactile feedback for satisfying, arcade-flavored interactions.
///
/// Wraps `NSHapticFeedbackManager`, which automatically respects the user's
/// system "Force Click and haptic feedback" setting (feedback is a no-op on
/// hardware/trackpads that don't support it), so callers don't need to gate.
enum AppHaptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// A completed action worth celebrating (save state written, load succeeded).
    static func success() { perform(.levelChange) }

    /// A discrete selection change (slot switch, toggle flip).
    static func selection() { perform(.alignment) }

    /// A generic press/tap.
    static func tap() { perform(.generic) }
}

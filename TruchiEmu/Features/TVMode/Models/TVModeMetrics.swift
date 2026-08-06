import SwiftUI
import AppKit

/// Resolution-adaptive scaling for TV Mode.
///
/// TV Mode runs fullscreen, so the window covers the entire screen. All
/// dimensions in TV Mode views (tile sizes, fonts, paddings, blur radii)
/// are authored against the 13" MacBook baseline (logical height ~982pt).
/// This type computes a single `scale` factor from the active screen's
/// logical height, clamped to `[1.0, 2.5]`:
///
///   - 13" MacBook (~982 logical pt)         → 1.0 (unchanged baseline)
///   - 1440p display (~1440 logical pt)      → ~1.47
///   - 4K display (~2160 logical pt)         → ~2.2
///   - 5K+ / larger                          → 2.5
///
/// Uses logical points (`screen.frame.height`), not backing pixels — so the
/// Retina 13" (1964 backing px ≈ 982pt) stays at the baseline 1.0× instead of
/// being scaled up by its pixel density.
enum TVModeMetrics {
    /// Current scale factor. Computed once per call (cheap: NSScreen lookups
    /// are O(1) and cached by AppKit). Reads `NSScreen.main` — the screen
    /// hosting the app's main window, which in fullscreen is the screen the
    /// TV Mode view actually fills.
    static var scale: CGFloat {
        guard let screen = NSScreen.main else { return 1.0 }
        return scale(for: screen)
    }

    /// Scale factor for a specific screen. Reads logical points
    /// (`screen.frame.height`), not backing pixels.
    static func scale(for screen: NSScreen) -> CGFloat {
        let logicalHeight = screen.frame.height
        let raw = logicalHeight / 982.0
        return min(max(raw, 1.0), 2.5)
    }
}

/// Environment-carried TV Mode scale factor. Set once at the `TVModeView`
/// root and read by all leaf views via `@Environment(\.tvModeScale)`.
private struct TVModeScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var tvModeScale: CGFloat {
        get { self[TVModeScaleKey.self] }
        set { self[TVModeScaleKey.self] = newValue }
    }
}

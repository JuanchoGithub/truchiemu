import SwiftUI

/// Shared colour language for the TV-mode chrome.
///
/// The bold theme follows the app's light/dark appearance. The muted and
/// boxart themes are cinema surfaces: their canvas is always dark, so text and
/// glass stay legible in both appearances (the old muted theme paired a
/// near-black background with `.primary` text, which turned black in light
/// mode).
struct TVModePalette {
    let theme: TVModeSettings.Theme
    let colorScheme: ColorScheme

    var isDarkCanvas: Bool { theme != .bold }

    var accent: Color { AppColors.accentForScheme(colorScheme) }

    var textPrimary: Color {
        isDarkCanvas ? Color.white.opacity(0.96) : AppColors.textPrimary(colorScheme)
    }

    var textSecondary: Color {
        isDarkCanvas ? Color.white.opacity(0.62) : AppColors.textSecondary(colorScheme)
    }

    var textTertiary: Color {
        isDarkCanvas ? Color.white.opacity(0.40) : AppColors.textTertiary(colorScheme)
    }

    /// Subtle glass fill for panels, chips and the theme switch.
    var panelFill: Color {
        isDarkCanvas ? Color.white.opacity(0.06) : AppColors.cardBackground(colorScheme).opacity(0.75)
    }

    /// Stronger glass for the focused item and selected segments.
    var panelFillStrong: Color {
        isDarkCanvas ? Color.white.opacity(0.11) : AppColors.cardBackground(colorScheme)
    }

    var panelStroke: Color {
        isDarkCanvas ? Color.white.opacity(0.12) : AppColors.cardBorder(colorScheme)
    }

    /// Ring drawn around the focused system / poster.
    var focusRing: Color {
        theme == .bold ? accent : Color.white.opacity(0.92)
    }

    var shadow: Color {
        isDarkCanvas ? .black.opacity(0.55) : .black.opacity(0.18)
    }

    var scrimTop: Color {
        isDarkCanvas ? .black.opacity(0.55) : AppColors.windowBackground(colorScheme).opacity(0.55)
    }

    var scrimBottom: Color {
        isDarkCanvas ? .black.opacity(0.92) : AppColors.windowBackground(colorScheme).opacity(0.92)
    }

    /// Fill used for the action chips under the hero.
    var actionFill: Color {
        theme == .bold ? accent.opacity(0.22) : Color.white.opacity(0.10)
    }
}

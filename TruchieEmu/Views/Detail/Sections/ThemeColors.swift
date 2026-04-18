import SwiftUI

// MARK: - Light/Dark Theme Color Tokens

// Centralized color tokens for GameDetailView — works in both light and dark mode.
// Prevents hardcoded `.white.opacity(x)` colors that break in light mode.
struct ThemeColors {
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMuted: Color
    let divider: Color
    let cardBackground: Color
    let cardBackgroundSubtle: Color
    let cardBorder: Color
    let iconPrimary: Color
    let iconSecondary: Color
    let iconMuted: Color
    let sidebarBackground: Color
    let headerBackground: Color
    let buttonBackground: Color
    let pillBackground: Color
    let pillBackgroundSubtle: Color
    let slotBackground: Color
    let slotBackgroundActive: Color
    let statusBackground: Color
    
    init(colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark
        textPrimary = isDark ? .white.opacity(0.85) : .primary
        textSecondary = isDark ? .white.opacity(0.5) : .secondary
        textTertiary = isDark ? .white.opacity(0.4) : .secondary.opacity(0.7)
        textMuted = isDark ? .white.opacity(0.3) : .secondary.opacity(0.5)
        divider = isDark ? .white.opacity(0.08) : .secondary.opacity(0.15)
        cardBackground = isDark ? .white.opacity(0.06) : .secondary.opacity(0.05)
        cardBackgroundSubtle = isDark ? .white.opacity(0.03) : .secondary.opacity(0.03)
        cardBorder = isDark ? .white.opacity(0.1) : .secondary.opacity(0.12)
        iconPrimary = isDark ? .white.opacity(0.7) : .secondary
        iconSecondary = isDark ? .white.opacity(0.5) : .secondary
        iconMuted = isDark ? .white.opacity(0.3) : .secondary.opacity(0.5)
        sidebarBackground = isDark ? .white.opacity(0.03) : .secondary.opacity(0.03)
        headerBackground = isDark ? .black.opacity(0.5) : .secondary.opacity(0.08)
        buttonBackground = isDark ? .white.opacity(0.1) : .secondary.opacity(0.12)
        pillBackground = isDark ? .white.opacity(0.1) : .secondary.opacity(0.1)
        pillBackgroundSubtle = isDark ? .white.opacity(0.06) : .secondary.opacity(0.06)
        slotBackground = isDark ? .white.opacity(0.05) : .secondary.opacity(0.04)
        slotBackgroundActive = isDark ? .blue.opacity(0.2) : .blue.opacity(0.1)
        statusBackground = isDark ? .black.opacity(0.5) : .secondary.opacity(0.08)
    }
    
    static func `for`(_ colorScheme: ColorScheme) -> ThemeColors {
        ThemeColors(colorScheme: colorScheme)
    }
}
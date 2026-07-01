import SwiftUI

// MARK: - Oklch Color Space Support

extension Color {
    /// Create a color from Oklch components (lightness, chroma, hue).
    /// Uses the Oklch color space (macOS 14+) for perceptually uniform warm colors.
    static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double, alpha: Double = 1.0) -> Color {
        let hRad = hue * .pi / 180.0
        let a = chroma * cos(hRad)
        let b = chroma * sin(hRad)

        // Oklab to linear sRGB conversion
        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b

        // Cube to get linear LMS
        let lLMS = l_ * l_ * l_
        let mLMS = m_ * m_ * m_
        let sLMS = s_ * s_ * s_

        // LMS to linear sRGB matrix (inverse of sRGB→LMS from CSS Color Level 4)
        let rLin = 4.0767416614 * lLMS - 3.3077115905 * mLMS + 0.2309699287 * sLMS
        let gLin = -1.2684380042 * lLMS + 2.6097574008 * mLMS - 0.3413193963 * sLMS
        let bLin = -0.0041960858 * lLMS - 0.7034186150 * mLMS + 1.7076147010 * sLMS

        func gamma(_ c: Double) -> Double {
            let sign = c < 0 ? -1.0 : 1.0
            let absC = abs(c)
            if absC > 0.0031308 {
                return sign * (1.055 * pow(absC, 1 / 2.4) - 0.055)
            }
            return 12.92 * c
        }

        return Color(.sRGB, red: gamma(rLin), green: gamma(gLin), blue: gamma(bLin), opacity: alpha)
    }
}

// MARK: - TruchiEmu Design System
// A unified design system providing consistent colors, typography, spacing, and components
// across all views and windows in the application.

// MARK: - Theme Colors

// Centralized color tokens that adapt to light and dark mode
struct AppColors {
    // MARK: - Brand Colors
    
    // Cyan — the TruchiEmu brand accent (#0891b2 Tailwind cyan-600)
    // brandAccent is computed from the current NSApp appearance so all usages
    // automatically resolve to the correct light/dark variant.
    static var brandAccent: Color {
        isDarkMode ? brandAccentDarkMode : brandAccentLight
    }

    /// Stored light-mode accent (set by ThemeManager)
    static var brandAccentLight: Color = Color(.sRGB, red: 0.012, green: 0.412, blue: 0.631, opacity: 1.0)
    static var brandAccentDimmed: Color = Color(.sRGB, red: 0.010, green: 0.345, blue: 0.529, opacity: 1.0)
    static var brandAccentDark: Color = Color(.sRGB, red: 0.008, green: 0.271, blue: 0.416, opacity: 1.0)
    static var brandAccentSecondary: Color {
        isDarkMode ? brandAccentSecondaryDarkMode : brandAccentSecondaryLight
    }

    static var brandAccentSecondaryLight: Color = Color(.sRGB, red: 0.039, green: 0.702, blue: 0.890, opacity: 1.0)

    // Dark-mode variants (set by ThemeManager for themes that differ between light/dark)
    static var brandAccentDarkMode: Color = Color(.sRGB, red: 0.150, green: 0.650, blue: 0.850, opacity: 1.0)
    static var brandAccentDimmedDarkMode: Color = Color(.sRGB, red: 0.126, green: 0.546, blue: 0.714, opacity: 1.0)
    static var brandAccentDarkDarkMode: Color = Color(.sRGB, red: 0.105, green: 0.455, blue: 0.595, opacity: 1.0)
    static var brandAccentSecondaryDarkMode: Color = Color(.sRGB, red: 0.039, green: 0.702, blue: 0.890, opacity: 1.0)

    private static var isDarkMode: Bool {
        NSApp.effectiveAppearance.name == .darkAqua
    }
    
    // Resolve the correct accent for the current color scheme
    static func accentForScheme(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? brandAccentDarkMode : brandAccentLight
    }

    static func accentDimmedForScheme(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? brandAccentDimmedDarkMode : brandAccentDimmed
    }

    static func accentDarkForScheme(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? brandAccentDarkDarkMode : brandAccentDark
    }

    static func accentSecondaryForScheme(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? brandAccentSecondaryDarkMode : brandAccentSecondaryLight
    }

    // MARK: - Semantic Colors
    
    // Primary background color for cards and panels with subtle accent tint
    static func cardBackground(_ colorScheme: ColorScheme) -> Color {
        let tintStrength: CGFloat = colorScheme == .dark ? 0.03 : 0.015
        let accent = accentForScheme(colorScheme)
        guard let baseNS = NSColor.controlBackgroundColor.usingColorSpace(.sRGB),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = baseNS.blended(withFraction: tintStrength, of: accentNS) else {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(nsColor: blended)
    }

    // Subtle background for sections within cards
    static func cardBackgroundSubtle(_ colorScheme: ColorScheme) -> Color {
        cardBackground(colorScheme).opacity(0.6)
    }
    
    // Card border with subtle visibility
    static func cardBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }
    
    // Separator/divider color
    static func divider(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }
    
    static func textPrimary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
        ? .oklch(0.92, 0.03, 55)
        : .oklch(0.20, 0.03, 55)
    }

    static func textSecondary(_ colorScheme: ColorScheme) -> Color {
        tintedText(base: colorScheme == .dark ? .oklch(0.75, 0.02, 55) : .oklch(0.42, 0.02, 55), colorScheme: colorScheme)
    }

    static func textTertiary(_ colorScheme: ColorScheme) -> Color {
        tintedText(base: colorScheme == .dark ? .oklch(0.68, 0.02, 55) : .oklch(0.50, 0.02, 55), colorScheme: colorScheme)
    }

    static func textMuted(_ colorScheme: ColorScheme) -> Color {
        tintedText(base: colorScheme == .dark ? .oklch(0.62, 0.01, 55) : .oklch(0.48, 0.01, 55), colorScheme: colorScheme)
    }

    static func textOnAccent(_ colorScheme: ColorScheme) -> Color {
        let accent = accentForScheme(colorScheme)
        return textColorOnBackground(accent, colorScheme: colorScheme)
    }

    static func textOnAccent(for accent: Color, colorScheme: ColorScheme) -> Color {
        return textColorOnBackground(accent, colorScheme: colorScheme)
    }

    private static func textColorOnBackground(_ bg: Color, colorScheme: ColorScheme) -> Color {
        guard let nsColor = NSColor(bg).usingColorSpace(.sRGB) else {
            return colorScheme == .dark
                ? .oklch(0.97, 0.005, 55)
                : .oklch(0.98, 0.005, 55)
        }
        let r = nsColor.redComponent
        let g = nsColor.greenComponent
        let b = nsColor.blueComponent
        let linR = r <= 0.04045 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4)
        let linG = g <= 0.04045 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4)
        let linB = b <= 0.04045 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4)
        let luminance = 0.2126 * linR + 0.7152 * linG + 0.0722 * linB
        return luminance > 0.35
            ? .oklch(0.18, 0.02, 55)
            : (colorScheme == .dark ? .oklch(0.97, 0.005, 55) : .oklch(0.98, 0.005, 55))
    }

    static func textSecondaryNeutral(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .oklch(0.75, 0.00, 55) : .oklch(0.42, 0.00, 55)
    }

    static func textPrimaryNeutral(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .oklch(0.92, 0.00, 55) : .oklch(0.20, 0.00, 55)
    }

    private static func tintedText(base: Color, colorScheme: ColorScheme) -> Color {
        let accent = accentForScheme(colorScheme)
        guard let baseNS = NSColor(base).usingColorSpace(.sRGB),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = baseNS.blended(withFraction: 0.10, of: accentNS) else { return base }
        return Color(nsColor: blended)
    }
    
    // MARK: - Accent Colors
    
    // Primary accent — warm amber brand color
    static var accent: Color { .accentColor }
    
    // Accent tint for selected states
    static func accentTint(_ colorScheme: ColorScheme) -> Color {
        accentForScheme(colorScheme)
    }
    
    // Accent background (subtle) — higher opacity for more confident color use
    static func accentBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? accentSecondaryForScheme(colorScheme).opacity(0.25)
            : accentSecondaryForScheme(colorScheme).opacity(0.15)
    }
    
    // Secondary accent — warm coral/terracotta for complementary actions
    static var accentSecondary: Color { .oklch(0.65, 0.15, 30) }
    
    // Tertiary accent — warm teal for complementary accents
    static var accentTertiary: Color { .oklch(0.70, 0.10, 170) }
    
    // Warm golden yellow for highlights and decorative elements
    static var accentWarm: Color { .oklch(0.78, 0.13, 75) }
    
    // Success green (warm-tinted)
    static func success(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .oklch(0.62, 0.12, 150)
            : .oklch(0.45, 0.14, 150)
    }

    // Warning amber (warm-tinted)
    static func warning(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .oklch(0.72, 0.14, 75)
            : .oklch(0.48, 0.14, 75)
    }

    // Error red (warm-tinted)
    static func error(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .oklch(0.65, 0.16, 25)
            : .oklch(0.48, 0.18, 25)
    }
    
    // MARK: - Surface Colors
    
    // Main window background with subtle accent tint
    static func windowBackground(_ colorScheme: ColorScheme, tinted: Bool = true) -> Color {
        guard tinted else {
            return Color(nsColor: .windowBackgroundColor)
        }
        let tintStrength: CGFloat = colorScheme == .dark ? 0.04 : 0.08
        let accent = accentForScheme(colorScheme)
        guard let baseNS = NSColor.windowBackgroundColor.usingColorSpace(.sRGB),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = baseNS.blended(withFraction: tintStrength, of: accentNS) else {
            return Color(nsColor: .windowBackgroundColor)
        }
        return Color(nsColor: blended)
    }

    // Sidebar background (with material effect + accent tint)
    static func sidebarBackground(_ colorScheme: ColorScheme, tinted: Bool = true) -> Color {
        guard tinted else {
            return Color(nsColor: .underPageBackgroundColor)
        }
        if colorScheme == .dark {
            return tintedSidebarDark(colorScheme)
        }
        let tintStrength: CGFloat = 0.08
        let accent = accentForScheme(colorScheme)
        guard let baseNS = NSColor.underPageBackgroundColor.usingColorSpace(.sRGB),
              let lightened = baseNS.blended(withFraction: 0.8, of: NSColor.white),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = lightened.blended(withFraction: tintStrength, of: accentNS) else {
            return Color(nsColor: .underPageBackgroundColor)
        }
        return Color(nsColor: blended)
    }

    // Toolbar/chrome background
    static func toolbarBackground(_ colorScheme: ColorScheme, tinted: Bool = true) -> Color {
        guard tinted else {
            return Color(nsColor: .underPageBackgroundColor)
        }
        if colorScheme == .dark {
            return tintedSidebarDark(colorScheme)
        }
        let tintStrength: CGFloat = 0.08
        let accent = accentForScheme(colorScheme)
        guard let baseNS = NSColor.underPageBackgroundColor.usingColorSpace(.sRGB),
              let lightened = baseNS.blended(withFraction: 0.8, of: NSColor.white),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = lightened.blended(withFraction: tintStrength, of: accentNS) else {
            return Color(nsColor: .underPageBackgroundColor)
        }
        return Color(nsColor: blended)
    }

    private static func tintedSidebarDark(_ colorScheme: ColorScheme) -> Color {
        let tintStrength: CGFloat = 0.04
        let accent = accentForScheme(colorScheme)
        guard let baseNS = NSColor.underPageBackgroundColor.usingColorSpace(.sRGB),
              let accentNS = NSColor(accent).usingColorSpace(.sRGB),
              let blended = baseNS.blended(withFraction: tintStrength, of: accentNS) else {
            return Color(nsColor: .underPageBackgroundColor)
        }
        return Color(nsColor: blended)
    }
    
    // Elevated surface (popovers, sheets)
    static func surface(_ colorScheme: ColorScheme, tinted: Bool = true) -> Color {
        windowBackground(colorScheme, tinted: tinted)
    }
    
    // MARK: - Overlay Colors
    
    // Shadow overlay for cards
    static func shadowOverlay(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(hue: 0.08, saturation: 0.05, brightness: 0.0).opacity(0.45)
            : Color(hue: 0.08, saturation: 0.05, brightness: 0.0).opacity(0.12)
    }
    
    // Glass overlay effect
    static func glassOverlay(_ colorScheme: ColorScheme) -> some ShapeStyle {
        colorScheme == .dark ?
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ) :
            LinearGradient(
                colors: [Color.white.opacity(0.6), Color.white.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }
}

// MARK: - Spacing Tokens

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xl2: CGFloat = 20
    static let xl3: CGFloat = 24
    static let xl4: CGFloat = 32
    static let xl5: CGFloat = 40
    static let xl6: CGFloat = 48
    static let xl8: CGFloat = 64
}

// MARK: - Border Radius

enum AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xl2: CGFloat = 16
    static let xl3: CGFloat = 20
    static let full: CGFloat = 9999
}

// MARK: - Shadows

enum AppShadows {
    static func subtle(_ colorScheme: ColorScheme) -> some View {
        AnyView(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(Color.clear)
                .shadow(
                    color: colorScheme == .dark ?
                        Color.black.opacity(0.3) : Color.black.opacity(0.08),
                    radius: 8,
                    y: 4
                )
        )
    }
    
    static func elevated(_ colorScheme: ColorScheme) -> some View {
        AnyView(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(Color.clear)
                .shadow(
                    color: colorScheme == .dark ?
                        Color.black.opacity(0.4) : Color.black.opacity(0.12),
                    radius: 16,
                    y: 8
                )
        )
    }
}

// MARK: - Card Component

struct AppCard<Content: View>: View {
    let style: AppCardStyle
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        style: AppCardStyle = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if style.showHeader, let header = style.header {
                header
                if style.headerDivider {
                    Divider()
                        .padding(.vertical, AppSpacing.sm)
                        .overlay(AppColors.divider(colorScheme))
                }
            }
            content
        }
        .padding(style.isPadded ? AppSpacing.lg : AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: style.radius)
                .fill(AppColors.cardBackground(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: style.radius)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
        .clipped()
    }
}

enum AppCardStyle {
    case `default`
    case subtle
    case elevated
    case transparent
    
    var showHeader: Bool { false }
    var header: AnyView? { nil }
    var headerDivider: Bool { false }
    var isPadded: Bool { true }
    var radius: CGFloat {
        switch self {
        case .default: return AppRadius.xl
        case .subtle: return AppRadius.lg
        case .elevated: return AppRadius.xl
        case .transparent: return AppRadius.md
        }
    }
}

// MARK: - Section Header

struct AppSectionHeader: View {
    let icon: String
    let title: String
    var badge: String?
    @Environment(\.colorScheme) private var colorScheme
    
    init(icon: String, title: String, badge: String? = nil) {
        self.icon = icon
        self.title = title
        self.badge = badge
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(AppColors.textTertiary(colorScheme))
            
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .tracking(0.5)
            
            if let badge = badge {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColors.accentBackground(colorScheme))
                    .foregroundColor(AppColors.accentTint(colorScheme))
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
    }
}

// MARK: - Data Row

struct AppDataRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var copyAction: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xl) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .lineLimit(2)
                .truncationMode(.middle)
                .font(isMonospaced ? .body.monospaced() : .body)
            
            Spacer()
            
            if let copyAction = copyAction {
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - Pill Button

struct AppPillButton: View {
    let icon: String
    let label: String
    var style: AppPillStyle = .primary
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
            }
            .foregroundColor(style.foregroundColor(colorScheme))
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(style.background(colorScheme))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

enum AppPillStyle {
    case primary
    case secondary
    case success
    case warning
    case danger
    
    func foregroundColor(_ colorScheme: ColorScheme) -> Color {
        switch self {
        case .primary:
            return AppColors.textOnAccent(colorScheme)
        case .secondary:
            return AppColors.textSecondary(colorScheme)
        case .success:
            return AppColors.success(colorScheme)
        case .warning:
            return AppColors.warning(colorScheme)
        case .danger:
            return AppColors.error(colorScheme)
        }
    }
    
    func background(_ colorScheme: ColorScheme) -> Color {
        switch self {
        case .primary:
            return AppColors.brandAccent
        case .secondary:
            return AppColors.cardBackgroundSubtle(colorScheme)
        case .success:
            return AppColors.success(colorScheme).opacity(colorScheme == .dark ? 0.2 : 0.1)
        case .warning:
            return AppColors.warning(colorScheme).opacity(colorScheme == .dark ? 0.2 : 0.1)
        case .danger:
            return AppColors.error(colorScheme).opacity(colorScheme == .dark ? 0.2 : 0.1)
        }
    }
}

// MARK: - Bouncing Progress Bar

struct BouncingProgressBar: View {
    @State private var isExpanded = false

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * 0.35
            let travelDistance = geo.size.width - barWidth

            RoundedRectangle(cornerRadius: AppRadius.full)
                .fill(AppGradients.accent)
                .frame(width: barWidth, height: 4)
                .offset(x: isExpanded ? travelDistance : 0)
                .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 6)
                .onAppear {
                    withAnimation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                    ) {
                        isExpanded = true
                    }
                }
        }
        .frame(height: 4)
        .padding(.horizontal, 60)
    }
}

// MARK: - Continuous Pulse Modifier

// Infinite pulsing animation for icons and decorative elements
struct ContinuousPulse: ViewModifier {
    @State private var isPulsing = false
    var scaleRange: ClosedRange<Double> = 0.95...1.05
    var duration: Double = 1.8
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? scaleRange.upperBound : scaleRange.lowerBound)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Gradient Assets

enum AppGradients {
    // Warm amber brand accent gradient
    static var accent: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.brandAccent.opacity(0.90),
                AppColors.brandAccentDimmed.opacity(0.80)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // Deeper warm-copper gradient for hero/emphasis elements
    static var warmAccent: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 0.10, saturation: 0.65, brightness: 0.75).opacity(0.85),
                Color(hue: 0.08, saturation: 0.55, brightness: 0.60).opacity(0.75)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // Subtle background gradient for cards
    static func subtleCard(_ colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark ?
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ) :
            LinearGradient(
                colors: [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }
}

// MARK: - Animation Presets

enum AppAnimations {
    static let quick: Animation = .easeInOut(duration: 0.15)
    static let standard: Animation = .easeInOut(duration: 0.25)
    static let smooth: Animation = .easeInOut(duration: 0.35)
    static let spring: Animation = .interpolatingSpring(stiffness: 170, damping: 20)
    static let springGentle: Animation = .interpolatingSpring(stiffness: 200, damping: 25)
    
    static func timedAppear(delay: Double = 0) -> Animation {
        .easeOut(duration: 0.4).delay(delay)
    }
}

// MARK: - Motion Language

enum AppMotion {
    /// Entrance: staggered ease-out for content appearing on screen
    static func entrance(delay: Double = 0) -> Animation {
        .easeOut(duration: 0.4).delay(delay)
    }
    
    /// Micro-interaction: spring feel for hover, toggle, press feedback
    static let micro: Animation = .interpolatingSpring(stiffness: 200, damping: 25)
    
    /// State change: content swap, panel show/hide
    static let stateChange: Animation = .easeInOut(duration: 0.25)
    
    /// Quick feedback: press, tap, dismiss
    static let feedback: Animation = .easeOut(duration: 0.12)
}

// MARK: - Typography Scale

enum AppTypography {
    // Display font for large hero text — uses .rounded design for distinctive headings
    static let displayFont = Font.system(.largeTitle, design: .rounded)
    
    // Modular type scale (ratio 1.25) for consistent typographic rhythm
    
    // Display — large hero text
    static let display = Font.system(size: 44, weight: .bold, design: .rounded)
    static let display2 = Font.system(size: 34, weight: .bold, design: .rounded)
    
    // Titles
    static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let title3 = Font.system(size: 18, weight: .semibold, design: .rounded)
    
    // Headings
    static let headline = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let subheadline = Font.system(size: 15, weight: .medium, design: .rounded)
    
    // Body
    static let body = Font.system(size: 14)
    static let callout = Font.system(size: 13)
    static let footnote = Font.system(size: 12)
    
    // Captions
    static let caption1 = Font.system(size: 11)
    static let caption2 = Font.system(size: 10)
    
    // Light weight variants for contrast
    static let displayLight = Font.system(size: 44, weight: .ultraLight, design: .rounded)
    static let display2Light = Font.system(size: 34, weight: .ultraLight, design: .rounded)
    static let title1Light = Font.system(size: 28, weight: .light, design: .rounded)
    static let title2Light = Font.system(size: 22, weight: .light, design: .rounded)
    static let bodyLight = Font.system(size: 14, weight: .light)
    static let calloutLight = Font.system(size: 13, weight: .light)
    
    // Brand heading shortcuts (SF Rounded for distinctive macOS-native headings)
    static let headingLarge = Font.system(size: 22, weight: .bold, design: .rounded)
    static let headingMedium = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let headingSmall = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let sectionHeader = Font.system(size: 12, weight: .semibold, design: .rounded)
}

// MARK: - Decorative Gradients

enum AppDecorativeGradients {
    // Subtle warm radial gradient for background ambiance
    static var warmGlow: some View {
        RadialGradient(
            colors: [
                AppColors.brandAccent.opacity(0.08),
                AppColors.brandAccent.opacity(0.0)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )
    }
    
    // Subtle warm tint gradient for card hover states
    static func cardHover(_ colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                AppColors.brandAccent.opacity(colorScheme == .dark ? 0.06 : 0.04),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Warm amber gradient for primary buttons
    static var buttonPrimary: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.brandAccent,
                AppColors.brandAccentDimmed
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Surface Tints

enum AppSurfaces {
    // Subtle warm tint overlay for card backgrounds
    static func warmTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.3)
            : AppColors.brandAccent.opacity(0.03)
    }
}

// MARK: - Retro Effects

enum AppRetroEffects {
    // Subtle CRT-inspired overlay for retro game room feel
    // Uses alternating opacity stripes to mimic scanlines
    static func scanlineOverlay(opacity: Double = 0.03) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(opacity),
                        .clear,
                        .black.opacity(opacity * 0.5),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }
}

extension View {
    func sectionHeaderStyle() -> some View {
        self.font(AppTypography.sectionHeader).textCase(.uppercase).tracking(0.8)
    }
}

extension Text {
    func headingLarge() -> Text {
        font(AppTypography.headingLarge)
    }
    func headingMedium() -> Text {
        font(AppTypography.headingMedium)
    }
    func headingSmall() -> Text {
        font(AppTypography.headingSmall)
    }
}

// MARK: - Button Styles

// Primary action button with consistent styling
struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var accent: Color?
    var foreground: Color?
    var fullWidth: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        let resolvedAccent = accent ?? AppColors.accentSecondaryForScheme(colorScheme)
        let resolvedForeground = foreground ?? AppColors.textOnAccent(for: resolvedAccent, colorScheme: colorScheme)
        return configuration.label
            .fontWeight(.semibold)
            .foregroundColor(resolvedForeground)
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule()
                    .fill(resolvedAccent.opacity(configuration.isPressed ? 0.7 : 1.0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Secondary/outlined button style
struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppColors.textSecondary(colorScheme))
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.lg)
            .background(
                Capsule()
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        Capsule()
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Toggle Styles

struct AppToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        let accent = AppColors.accentSecondaryForScheme(colorScheme)
        return Button(action: {
            withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                configuration.isOn.toggle()
            }
        }) {
            HStack(spacing: AppSpacing.md) {
                configuration.label
                
                Spacer()
                
                ZStack {
                    Capsule()
                        .fill(configuration.isOn ?
                            accent.opacity(0.3) :
                            AppColors.cardBackgroundSubtle(colorScheme))
                        .frame(width: 40, height: 24)
                    
                    Circle()
                        .fill(configuration.isOn ? accent : AppColors.textMuted(colorScheme))
                        .frame(width: 20, height: 20)
                        .offset(x: configuration.isOn ? 8 : -8)
                }
                .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Field

struct AppSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let accent = AppColors.accentSecondaryForScheme(colorScheme)
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? accent : AppColors.textTertiary(colorScheme))
                .font(.footnote)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .focused($isFocused)
                .onSubmit { onSubmit?() }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .font(.footnote)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(isFocused ?
                    AppColors.accentBackground(colorScheme) :
                    AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .stroke(isFocused ? accent.opacity(0.3) : AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Empty State

struct AppEmptyState: View {
    let icon: String
    let title: String
    let description: String
    var actionLabel: String?
    var action: (() -> Void)? = nil
    @State private var iconAppeared = false
    @State private var titleAppeared = false
    @State private var descriptionAppeared = false
    @State private var buttonAppeared = false
    @State private var isPulsing = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(AppColors.textMuted(colorScheme))
                .scaleEffect(isPulsing ? 1.05 : 0.95)
                .opacity(iconAppeared ? 1 : 0)
            
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .opacity(titleAppeared ? 1 : 0)
            
            Text(description)
                .font(.body)
                .foregroundColor(AppColors.textTertiary(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .opacity(descriptionAppeared ? 1 : 0)
            
            if let actionLabel = actionLabel, let action = action {
                Button(actionLabel, action: action)
                    .buttonStyle(AppPrimaryButtonStyle())
                    .opacity(buttonAppeared ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Staggered appearance: icon -> title -> description -> button
            withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                iconAppeared = true
                isPulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                    titleAppeared = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                    descriptionAppeared = true
                }
            }
            if actionLabel != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                        buttonAppeared = true
                    }
                }
            }
        }
    }
}

// MARK: - Chip / Filter

struct AppChip: View, Identifiable {
    let id: String
    let label: String
    var icon: String? 
    var isSelected: Bool
    var accent: Color?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        label: String,
        icon: String? = nil,
        isSelected: Bool = false,
        accent: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.id = label
        self.label = label
        self.icon = icon
        self.isSelected = isSelected
        self.accent = accent
        self.action = action
    }
    
    var body: some View {
        let resolvedAccent = accent ?? AppColors.accentSecondaryForScheme(colorScheme)
        return Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .foregroundColor(isSelected ? AppColors.textOnAccent(for: resolvedAccent, colorScheme: colorScheme) : AppColors.textSecondary(colorScheme))
            .background(
                Capsule()
                    .fill(isSelected ? resolvedAccent.opacity(0.85) : AppColors.cardBackgroundSubtle(colorScheme))
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: isSelected)
    }
}

// MARK: - Settings Section Card

// A reusable card component for settings sections with consistent styling.
// Provides a titled container with proper spacing, padding, and background.
struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header
            HStack(spacing: AppSpacing.sm) {
                if let icon = icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
                Text(title)
                    .font(.headline)
            }
            
            // Content
            content
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
    }
}

// A settings row with a label and control, properly aligned.
struct SettingsRow<Content: View>: View {
    let label: String
    let description: String?
    @ViewBuilder var control: Content
    @Environment(\.colorScheme) private var colorScheme
    
    init(_ label: String, description: String? = nil, @ViewBuilder control: () -> Content) {
        self.label = label
        self.description = description
        self.control = control()
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(label)
                    .font(.body)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
            }
            Spacer()
            control
        }
        .padding(.vertical, AppSpacing.sm)
    }
}

// MARK: - Stat Card

struct AppStatCard: View {
    let icon: String
    let value: String
    let label: String
    var accent: Color?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let resolvedAccent = accent ?? AppColors.accentForScheme(colorScheme)
        return VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(resolvedAccent)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textPrimary(colorScheme))
            
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.textTertiary(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
        )
    }
}

// MARK: - Text Fields

/// A canonical text input with cardinal surface styling.
/// Use for free-form value entry in settings forms.
struct AppTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var systemImage: String?
    var monospaced: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, text: Binding<String>, placeholder: String = "", systemImage: String? = nil, monospaced: Bool = false) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
        self.monospaced = monospaced
    }

    var body: some View {
        TextField(title, text: $text, prompt: placeholder.isEmpty ? nil : Text(placeholder))
            .textFieldStyle(.plain)
            .font(monospaced ? .body.monospaced() : .body)
            .foregroundColor(AppColors.textPrimary(colorScheme))
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
    }
}

/// A canonical secure input with cardinal surface styling.
struct AppSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var systemImage: String?
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, text: Binding<String>, placeholder: String = "", systemImage: String? = nil) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.systemImage = systemImage
    }

    var body: some View {
        SecureField(title, text: $text, prompt: placeholder.isEmpty ? nil : Text(placeholder))
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundColor(AppColors.textPrimary(colorScheme))
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Info Row

/// A label + monospaced value row with an optional trailing button.
/// Used wherever a settings view needs to display a path, identifier,
/// or other read-only value with optional actions (Reveal in Finder, Copy, etc.).
struct AppInfoRow<Trailing: View>: View {
    let label: String
    let value: String
    let valueMonospaced: Bool
    let truncate: Text.TruncationMode
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    init(_ label: String,
         value: String,
         monospaced: Bool = true,
         truncate: Text.TruncationMode = .middle,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.value = value
        self.valueMonospaced = monospaced
        self.truncate = truncate
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Text(label)
                .font(.body)
            Spacer(minLength: AppSpacing.md)
            Text(value)
                .font(valueMonospaced ? .callout.monospaced() : .callout)
                .lineLimit(1)
                .truncationMode(truncate)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .help(value)
            trailing()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

/// Convenience: a directory path row with a "Reveal in Finder" trailing button.
struct AppPathRow: View {
    let label: String
    let url: URL
    let monospaced: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(_ label: String, url: URL, monospaced: Bool = true) {
        self.label = label
        self.url = url
        self.monospaced = monospaced
    }

    var body: some View {
        AppInfoRow(label, value: url.path, monospaced: monospaced) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
    }
}

// MARK: - Toast

/// Style variants for `AppToast`.
enum AppToastStyle {
    case success
    case info
    case warning
    case error

    func background(_ colorScheme: ColorScheme) -> Color {
        switch self {
        case .success: return AppColors.success(colorScheme)
        case .info:    return AppColors.accentSecondaryForScheme(colorScheme)
        case .warning: return AppColors.warning(colorScheme)
        case .error:   return AppColors.error(colorScheme)
        }
    }

    func icon() -> String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
}

/// A transient feedback pill rendered as an overlay.
/// Render inside `.overlay(alignment: .bottom)` and toggle visibility
/// via `withAnimation`; the toast auto-dismisses after `duration`.
struct AppToast: View {
    let message: String
    let style: AppToastStyle
    var duration: TimeInterval = 3
    var onDismiss: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible: Bool = true

    var body: some View {
        if visible {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: style.icon())
                    .foregroundStyle(.white)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .background(style.background(colorScheme).opacity(0.95))
            .clipShape(Capsule())
            .shadow(radius: AppRadius.lg)
            .padding(.bottom, AppSpacing.xl5)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation {
                        visible = false
                        onDismiss?()
                    }
                }
            }
        }
    }
}

// MARK: - Stat Group

/// Horizontal three-up stat group: three equally-spaced `AppStatCard`s
/// separated by 1pt vertical dividers.
/// Replaces the hand-rolled three-up stat tiles found in several settings views.
struct StatGroup: View {
    let primary: AppStatCard
    let secondary: AppStatCard
    let tertiary: AppStatCard
    @Environment(\.colorScheme) private var colorScheme

    init(_ primary: AppStatCard, _ secondary: AppStatCard, _ tertiary: AppStatCard) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }

    var body: some View {
        HStack(spacing: AppSpacing.xl) {
            primary
            Divider()
                .frame(height: 40)
                .overlay(AppColors.divider(colorScheme))
            secondary
            Divider()
                .frame(height: 40)
                .overlay(AppColors.divider(colorScheme))
            tertiary
        }
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity)
    }
}
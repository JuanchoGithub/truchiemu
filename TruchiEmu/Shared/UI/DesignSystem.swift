import SwiftUI

// MARK: - TruchiEmu Design System
// A unified design system providing consistent colors, typography, spacing, and components
// across all views and windows in the application.

// MARK: - Theme Colors

// Centralized color tokens that adapt to light and dark mode
struct AppColors {
    // MARK: - Semantic Colors
    
    // Primary background color for cards and panels
    static func cardBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.12).opacity(0.8) : Color(white: 0.96)
    }
    
    // Subtle background for sections within cards
    static func cardBackgroundSubtle(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.15).opacity(0.5) : Color(white: 0.98)
    }
    
    // Card border with subtle visibility
    static func cardBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    // Separator/divider color
    static func divider(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    // Primary text color
    static func textPrimary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : Color(white: 0.1)
    }
    
    // Secondary text (labels, descriptions)
    static func textSecondary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.45)
    }
    
    // Tertiary text (meta, timestamps)
    static func textTertiary(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.5) : Color(white: 0.6)
    }
    
    // Muted text for disabled/inactive states
    static func textMuted(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.35) : Color(white: 0.65)
    }
    
    // MARK: - Accent Colors
    
    // Primary accent (blue) - standard interactive elements
    static var accent: Color { .accentColor }
    
    // Accent tint for selected states (adapts to mode)
    static func accentTint(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.blue : Color.blue
    }
    
    // Accent background (subtle)
    static func accentBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.blue.opacity(0.15) : Color.blue.opacity(0.08)
    }
    
    // Success green
    static func success(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.2, green: 0.85, blue: 0.3) : Color(red: 0.1, green: 0.65, blue: 0.2)
    }
    
    // Warning orange
    static func warning(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.orange : Color.orange
    }
    
    // Error red
    static func error(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(red: 0.85, green: 0.15, blue: 0.15)
    }
    
    // MARK: - Surface Colors
    
    // Main window background
    static func windowBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.06) : Color(white: 0.94)
    }
    
    // Sidebar background (with material effect)
    static var sidebarBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }
    
    // Toolbar/chrome background
    static func toolbarBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96)
    }
    
    // Elevated surface (popovers, sheets)
    static func surface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.15) : .white
    }
    
    // MARK: - Overlay Colors
    
    // Shadow overlay for cards
    static func shadowOverlay(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.12)
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
            return colorScheme == .dark ? Color.white : .blue
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
            return colorScheme == .dark ? Color.blue.opacity(0.3) : .blue.opacity(0.12)
        case .secondary:
            return AppColors.cardBackgroundSubtle(colorScheme)
        case .success:
            return colorScheme == .dark ? Color.green.opacity(0.2) : .green.opacity(0.1)
        case .warning:
            return colorScheme == .dark ? Color.orange.opacity(0.2) : .orange.opacity(0.1)
        case .danger:
            return colorScheme == .dark ? Color.red.opacity(0.2) : .red.opacity(0.1)
        }
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
    // Refined emerald-to-teal accent gradient
    static var accent: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.6, blue: 0.35).opacity(0.85),
                Color(red: 0.15, green: 0.65, blue: 0.55).opacity(0.85)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // Warm amber-to-orange gradient for hero elements
    static var warmAccent: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.65, blue: 0.15).opacity(0.85),
                Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.75)
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

// MARK: - Button Styles

// Primary action button with consistent styling
struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var accent: Color = .blue
    var fullWidth: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule()
                    .fill(accent.opacity(configuration.isPressed ? 0.7 : 1.0))
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
        Button(action: {
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
                            Color.blue.opacity(0.3) :
                            AppColors.cardBackgroundSubtle(colorScheme))
                        .frame(width: 40, height: 24)
                    
                    Circle()
                        .fill(configuration.isOn ? .blue : AppColors.textMuted(colorScheme))
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
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? .blue : AppColors.textTertiary(colorScheme))
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
                        .stroke(isFocused ? Color.blue.opacity(0.3) : AppColors.cardBorder(colorScheme), lineWidth: 1)
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
    var accent: Color = .blue
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        label: String,
        icon: String? = nil,
        isSelected: Bool = false,
        accent: Color = .accentColor,
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
        Button(action: action) {
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
            .foregroundColor(isSelected ? .white : AppColors.textSecondary(colorScheme))
            .background(
                Capsule()
                    .fill(isSelected ? accent.opacity(0.85) : AppColors.cardBackgroundSubtle(colorScheme))
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
    var accent: Color = .blue
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(accent)
            
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
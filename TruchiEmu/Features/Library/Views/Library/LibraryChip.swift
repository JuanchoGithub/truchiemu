import SwiftUI

// MARK: - Library Chip
//
// One capsule pill for the library filter bar. This is the single source of
// truth for the pill shape, type, hover and active fill. The sort chips, the
// filter chips, and the "Other"/"Genre" entries all use it, so the bar reads
// as one row of equal pills instead of five near-copies.
//
// The optional counted badge follows the library hero: a small tinted capsule
// with a bold number, not a parenthesized text run.

struct LibraryChip: View {
    let icon: String
    let title: String
    /// Shown as a small capsule after the title. Nil or 0 hides it.
    var count: Int? = nil
    var isActive: Bool = false
    var tint: Color = AppColors.brandAccent
    /// Popover rows stretch to the full width. Bar chips stay at their ideal width.
    var fillsWidth: Bool = false
    var tooltip: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var activeFill: Color {
        AppColors.selectedFill(for: tint)
    }

    private var foreground: Color {
        if isActive {
            return AppColors.textOnAccent(for: activeFill, colorScheme: colorScheme)
        }
        return isHovered ? tint : AppColors.textPrimary(colorScheme)
    }

    private var fill: Color {
        if isActive { return activeFill }
        return isHovered ? AppColors.accentBackground(colorScheme) : AppColors.cardBackgroundSubtle(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .scaleEffect(isActive ? 1.1 : 1)

                Text(verbatim: title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)

                if let count, count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? foreground : tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.white.opacity(0.20) : tint.opacity(0.14))
                        )
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 30)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [activeFill, activeFill.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(fill)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive
                            ? Color.white.opacity(0.18)
                            : AppColors.cardBorder(colorScheme),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                // Inner catch-light so the active pill reads as a raised key.
                Capsule()
                    .fill(Color.white.opacity(isActive ? 0.20 : 0))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.top, 1)
            }
            .shadow(
                color: isActive
                    ? tint.opacity(isHovered ? 0.42 : 0.30)
                    : (isHovered ? tint.opacity(0.18) : .clear),
                radius: isActive ? (isHovered ? 8 : 5) : 4,
                y: 2
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.035 : 1)
            .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
        }
        .buttonStyle(LibraryChipPressStyle(reduceMotion: reduceMotion))
        .help(tooltip ?? title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text(verbatim: tooltip ?? title))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isActive)
    }
}

/// Press feedback for the filter pills. Hover already lifts the chip; a short
/// press-down completes the "raised key" language so a click reads as physical.
private struct LibraryChipPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

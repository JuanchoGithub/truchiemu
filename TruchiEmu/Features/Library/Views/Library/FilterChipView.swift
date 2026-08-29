import SwiftUI

// MARK: - Filter Chip View

struct FilterChipView: View {
    let option: GameFilterOption
    let isActive: Bool
    var fillsWidth: Bool = false
    let action: () -> Void
    
    @Namespace private var chipAnimation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 10, weight: .medium))
                    .scaleEffect(isActive ? 1.1 : 1)
                Text(option.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundColor(isActive ? .white : (isHovered ? AppColors.brandAccent : .secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 30)
            .background(
                Capsule()
                    .fill(isActive ? option.activeColor : (isHovered ? AppColors.brandAccent.opacity(0.12) : AppColors.cardBackgroundSubtle(colorScheme)))
                    .scaleEffect(isHovered ? 1.05 : 1)
                    .shadow(color: isActive ? option.activeColor.opacity(0.3) : (isHovered ? AppColors.brandAccent.opacity(0.2) : .clear), radius: isHovered ? 4 : 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .help(option.tooltip)
        .accessibilityLabel(option.label)
        .accessibilityHint(option.tooltip)
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.2), value: isActive)
    }
    
    @State private var isHovered = false
}

import SwiftUI

// MARK: - Filter Chip View

struct FilterChipView: View {
    let option: GameFilterOption
    let isActive: Bool
    let action: () -> Void
    
    @Namespace private var chipAnimation
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 10, weight: .medium))
                    .scaleEffect(isActive ? 1.1 : 1)
                Text(option.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(
                Capsule()
                    .fill(isActive ? option.activeColor : Color.secondary.opacity(0.12))
                    .scaleEffect(isHovered ? 1.05 : 1)
                    .shadow(color: isActive ? option.activeColor.opacity(0.3) : .clear, radius: isHovered ? 4 : 0, y: 2)
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

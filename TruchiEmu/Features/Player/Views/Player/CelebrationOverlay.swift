import SwiftUI
import Combine

/// A temporary celebration that a window can render (confetti + branded pill).
struct Celebration: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String?
    let style: ConfettiStyle
    var dismissAfter: TimeInterval = 5
}

/// Reusable celebration dispatcher.
///
/// Any code in the app can call `CelebrationManager.shared.celebrate(...)`
/// and a `CelebrationOverlay` rendered in *any* window will pick it up. This
/// keeps the celebration moment feeling in-context rather than always
/// requiring the user to be in the main window.
@MainActor
final class CelebrationManager: ObservableObject {
    static let shared = CelebrationManager()

    @Published private(set) var current: Celebration?
    private var dismissTask: Task<Void, Never>?

    func celebrate(icon: String, title: String, subtitle: String? = nil, style: ConfettiStyle = .standard) {
        let next = Celebration(icon: icon, title: title, subtitle: subtitle, style: style)
        current = next
        ConfettiManager.shared.burst(style: style)
        AppHaptics.success()

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(next.dismissAfter * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            if self.current?.id == next.id {
                self.current = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

/// Brand-aligned celebration pill. Renders in any window.
struct CelebrationPill: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    let celebration: Celebration

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.brandAccent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: celebration.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppGradients.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: celebration.title)
                    .font(AppTypography.headingMedium)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                if let subtitle = celebration.subtitle {
                    Text(verbatim: subtitle)
                        .font(AppTypography.callout)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button {
                CelebrationManager.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(AppColors.cardBackgroundSubtle(colorScheme))
                            .opacity(isHovering ? 1 : 0.6)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(AppMotion.stateChange) { isHovering = hovering }
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppColors.brandAccent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.brandAccent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: AppColors.brandAccent.opacity(0.25), radius: 18, y: 6)
        )
    }
}

/// Drop-in celebration overlay. Mirrors the NotificationPill pattern.
///
/// IMPORTANT: the outer `Color.clear` is always rendered so the host
/// views in both windows stay full-size even when no celebration is
/// active. Returning an effectively-empty view body would collapse
/// `SafeHostingView` to its 10×10 minimum and the game window would
/// disappear mid-play.
struct CelebrationOverlay: View {
    @ObservedObject private var manager = CelebrationManager.shared
    @ObservedObject private var confetti = ConfettiManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.clear

            if let celebration = manager.current {
                VStack {
                    Spacer()
                    CelebrationPill(celebration: celebration)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 16)
                        .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }
            if confetti.isShowing {
                ConfettiView(particleCount: confetti.particleCount) {
                    confetti.isShowing = false
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? AppAnimations.quick : AppMotion.micro, value: manager.current?.id)
        .animation(.easeInOut(duration: 0.2), value: confetti.isShowing)
        .allowsHitTesting(false)
    }
}

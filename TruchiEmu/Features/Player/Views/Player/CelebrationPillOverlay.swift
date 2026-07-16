import SwiftUI

/// Game-window-safe celebration overlay.
///
/// Only renders the branded pill — never confetti — so a running game's
/// window is never blanketed by celebration particles. Used in the
/// standalone game window in place of `CelebrationOverlay` so confetti
/// stays reserved for the main library window.
///
/// IMPORTANT: the outer `Color.clear` container is always present so
/// `SafeHostingView` has a non-zero intrinsic content size. Returning
/// `EmptyView` from the body would collapse the host view to its
/// 10×10 minimum and make the game window disappear.
struct CelebrationPillOverlay: View {
    @ObservedObject private var manager = CelebrationManager.shared
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? AppAnimations.quick : AppMotion.micro, value: manager.current?.id)
        .allowsHitTesting(false)
    }
}

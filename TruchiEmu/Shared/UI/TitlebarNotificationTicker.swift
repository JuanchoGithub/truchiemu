import SwiftUI

/// Isolated `ToolbarContent` hosting the ticker in the `.navigation` slot
/// (between traffic lights and the first toolbar button). Kept separate so
/// the large `LibraryGridView` toolbar closure stays untouched.
struct TickerToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            TitlebarNotificationTicker()
        }
        .hideSharedBackgroundIfAvailable()
    }
}

extension ToolbarContent {
    /// Hides the Liquid Glass container macOS 26 draws around toolbar items.
    /// Without this the ticker slot renders as an empty glass box with a
    /// border, which breaks the slide effect. No-op on older systems.
    @ToolbarContentBuilder
    func hideSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Unobtrusive notification ticker for the empty titlebar gap between the
/// traffic lights and the first toolbar button.
///
/// Display-only: no click, no hover, no actions. It mirrors
/// `NotificationPillManager.shared.currentNotification` (same item and same
/// duration as the bottom pill) and stays hidden while TV Mode is active.
/// While the ticker shows an item, the main-window bottom pill stays hidden
/// (see `ContentView.mainInterface`) so the notification appears once.
///
/// Animation runs in strict phases:
/// 1. Empty capsule wipes left to right from the left edge.
/// 2. Text slides from the left edge to center (hidden before that).
/// 3. Hold while the pill is alive.
/// 4. Text slides back left and fades while the capsule collapses to the
///    left edge on dismiss.
///
/// Anchoring note: the toolbar centers a view whose own width animates, so
/// a width-animated outer frame grows/shrinks from the center. Everything
/// therefore animates *inside* a fixed-width slot (constant while shown):
/// the slot never moves, only its content does.
struct TitlebarNotificationTicker: View {
    @ObservedObject private var pillManager = NotificationPillManager.shared
    @ObservedObject private var tvMode = TVModeSettingsManager.shared

    @State private var displayed: PillNotification?
    @State private var capsuleWidth: CGFloat = 0
    @State private var textOffset: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var spinTrigger = 0
    @State private var generation = 0

    private let tickerWidth: CGFloat = 320
    private let tickerHeight: CGFloat = 26
    private let expandDuration = 0.35
    private let slideDuration = 0.45
    private let collapseDuration = 0.35

    var body: some View {
        HStack(spacing: 0) {
            if let item = displayed, !tvMode.isActive {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule()
                                .fill(AppColors.brandAccent.opacity(0.08))
                        )
                        .frame(width: capsuleWidth, height: tickerHeight)
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppGradients.accent)
                            .frame(width: 16, height: 16)
                            .keyframeAnimator(initialValue: 0.0, trigger: spinTrigger) { content, value in
                                content.rotationEffect(.degrees(value))
                            } keyframes: { _ in
                                // Wind up slightly the other way first.
                                CubicKeyframe(-22.0, duration: 0.18)
                                // Two fast spins, easing out of the spin.
                                CubicKeyframe(720.0, duration: 0.7)
                                // Overshoot, then settle back (= 0 degrees).
                                SpringKeyframe(752.0, duration: 0.28, spring: .snappy)
                                SpringKeyframe(720.0, duration: 0.4, spring: .bouncy)
                            }
                        Text(item.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(width: tickerWidth, alignment: .center)
                    .offset(x: textOffset)
                    .opacity(textOpacity)
                }
                .frame(width: tickerWidth, alignment: .leading)
                .clipped()
                .allowsHitTesting(false)
            }
        }
        .onReceive(pillManager.$currentNotification) { next in
            handle(next)
        }
        .onAppear {
            if displayed == nil, let current = pillManager.currentNotification {
                handle(current)
            }
        }
        .onChange(of: tvMode.isActive) { _, active in
            if active {
                generation += 1
                displayed = nil
                capsuleWidth = 0
            } else if let current = pillManager.currentNotification {
                handle(current)
            }
        }
    }

    private func handle(_ next: PillNotification?) {
        generation += 1
        let g = generation
        if let next {
            if displayed?.id == next.id { return }
            displayed = next
            capsuleWidth = 0
            textOffset = -tickerWidth / 2
            textOpacity = 0
            // Phase 1: empty capsule wipes from the fixed left edge.
            withAnimation(.easeOut(duration: expandDuration)) {
                capsuleWidth = tickerWidth
            }
            // Phase 2: only after the capsule is full, slide text to center.
            // Phase 3: once centered, play the icon spin.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(expandDuration * 1_000_000_000))
                guard g == generation else { return }
                withAnimation(.easeOut(duration: slideDuration)) {
                    textOffset = 0
                    textOpacity = 1
                }
                try? await Task.sleep(nanoseconds: UInt64(slideDuration * 1_000_000_000))
                guard g == generation else { return }
                spinTrigger += 1
            }
        } else if displayed != nil {
            // Phase 4: text retreats left and fades while the capsule
            // collapses to the fixed left edge. Both move left together,
            // then the view is removed.
            withAnimation(.easeIn(duration: collapseDuration)) {
                textOffset = -tickerWidth / 2
                textOpacity = 0
                capsuleWidth = 0
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(collapseDuration * 1_000_000_000))
                guard g == generation else { return }
                displayed = nil
                textOffset = 0
                textOpacity = 0
            }
        }
    }
}

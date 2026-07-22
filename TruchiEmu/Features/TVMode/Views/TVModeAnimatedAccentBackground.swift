import SwiftUI
import AppKit

/// Subtle animated version of the bold TV mode backdrop. Two soft radial
/// accents drift slowly around the window — radii and alphas cycle through
/// a small set of values to give the impression of a "breathing" surface
/// without ever competing with foreground content.
struct TVModeAnimatedAccentBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Phase = .a

    enum Phase: CaseIterable {
        case a, b, c, d
    }

    var body: some View {
        ZStack {
            AppColors.windowBackground(colorScheme, tinted: true)

            // Top accent: floats left <-> right while pulsing slightly.
            RadialGradient(
                colors: [topColor.opacity(0.22), .clear],
                center: phase == .b ? .topLeading : .top,
                startRadius: 0,
                endRadius: phase == .a || phase == .c ? 600 : 760
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: phaseDuration), value: phase)

            // Bottom accent: mirrors the top, slightly offset in time for an
            // organic, non-mechanical rhythm.
            RadialGradient(
                colors: [bottomColor.opacity(0.18), .clear],
                center: phase == .c ? .bottomTrailing : .bottom,
                startRadius: 0,
                endRadius: phase == .b || phase == .d ? 700 : 540
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: phaseDuration), value: phase)
        }
        .task {
            // Drive a slow 4-phase loop. Phase advances every `phaseDuration`
            // seconds, so a full breath takes ~24 s. Cheap: just a state tick.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(phaseDuration * 1_000_000_000))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: phaseDuration)) {
                    phase = Phase.allCases[(Phase.allCases.firstIndex(of: phase).map { $0 + 1 } ?? 0) % Phase.allCases.count]
                }
            }
        }
    }

    private var phaseDuration: Double { 6.0 }

    private var topColor: Color {
        AppColors.accentForScheme(colorScheme)
    }

    private var bottomColor: Color {
        AppColors.accentForScheme(colorScheme)
    }
}

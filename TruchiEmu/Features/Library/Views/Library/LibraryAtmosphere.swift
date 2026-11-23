import SwiftUI

// MARK: - Library Atmosphere
//
// Ambient bed behind the library column: an accent wash, two slowly drifting
// blooms, one diagonal light beam and a soft vignette. Every layer is painted
// with a gradient (no blur) and the whole bed is clipped to the column bounds,
// so it can never bleed over the sidebar.
struct LibraryAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var driftA = false
    @State private var driftB = false

    private var accent: Color { AppColors.brandAccent }
    private var secondary: Color { AppColors.brandAccentSecondary }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isDark = colorScheme == .dark
            let bloom = max(w, h)

            ZStack {
                AppColors.windowBackground(
                    colorScheme,
                    tinted: ThemeManager.shared.tintedSurfacesEnabled
                )

                // Leading bloom: cool accent wash behind the hero and the
                // first rows of the grid.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(isDark ? 0.16 : 0.10),
                                accent.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloom * 0.34
                        )
                    )
                    .frame(width: w * 1.05, height: w * 0.85)
                    .offset(
                        x: -w * 0.20 + (driftA ? 26 : -18),
                        y: -h * 0.26 + (driftA ? -16 : 22)
                    )

                // Trailing bloom: secondary accent, lower in the column.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                secondary.opacity(isDark ? 0.11 : 0.07),
                                secondary.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloom * 0.30
                        )
                    )
                    .frame(width: w * 0.95, height: w * 0.75)
                    .offset(
                        x: w * 0.32 + (driftB ? -22 : 16),
                        y: h * 0.12 + (driftB ? 18 : -14)
                    )

                // One long diagonal light beam keeps the bed from reading as
                // two unrelated spots.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(isDark ? 0.025 : 0.14),
                                .white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: w * 2.2, height: max(160, h * 0.24))
                    .rotationEffect(.degrees(-14))
                    .offset(y: -h * 0.16)

                // Vignette: pulls the eye toward the middle of the grid.
                RadialGradient(
                    colors: [.clear, Color.black.opacity(isDark ? 0.20 : 0.04)],
                    center: .center,
                    startRadius: min(w, h) * 0.30,
                    endRadius: max(w, h) * 0.80
                )
            }
            .frame(width: w, height: h)
            .clipShape(Rectangle())
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                driftA = true
            }
            withAnimation(.easeInOut(duration: 31).repeatForever(autoreverses: true)) {
                driftB = true
            }
        }
    }
}

import SwiftUI
import AppKit

// A self-contained live preview of the holographic foil effect, used by the
// onboarding wizard so the user can see what the reverse-holo looks like on the
// box art for their chosen region before enabling the option.
//
// It REUSES the exact same production renderer the app uses — `HoloWebCardView`
// (the simeydotme `pokemon-cards-css` reverse-holo). This is the source-faithful
// reverse holo: a rainbow sheen over an etched foil, driven by the app's own
// pointer position. We do not re-implement the foil in SwiftUI — we host the
// same `WKWebView` the grid cards use, mirroring `HoloGameCardView`'s
// `holoArtworkDefault` layout (cover-fit art + cursor parallax + clip + hit-test
// disabled) so the preview is pixel-consistent with the real cards.
//
// Motion: by default the pointer drifts on a slow synthetic orbit (TimelineView)
// so the foil shimmers on its own. While the pointer is over the card the
// synthetic motion pauses and the foil tracks the real cursor; when the pointer
// leaves, the self-driven orbit resumes.
struct HoloPreviewCard: View {
    let image: NSImage
    let romID: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var masks: HoloMaskSet?
    @State private var hoverActive = false
    @State private var mouseNorm = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Same cursor-parallax shift the production card uses.
            let artShift = min(w, h) * 0.03

            ZStack {
                // Card backing so any transparent web-view edge reads as a card.
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.cardBackground(colorScheme))

                TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                    let t = ctx.date.timeIntervalSince1970
                    let autoX = 0.5 + 0.35 * sin(t * 0.9)
                    let autoY = 0.5 + 0.35 * cos(t * 0.6)
                    let px = hoverActive ? mouseNorm.x : autoX
                    let py = hoverActive ? mouseNorm.y : autoY
                    let artPX = (0.5 - px) * artShift
                    let artPY = (0.5 - py) * artShift

                    // Reuse the production reverse-holo renderer (`reverse-holo`
                    // is the simeydotme CSS variant the app renders via WebKit).
                    HoloWebCardView(
                        image: image,
                        variantClass: "reverse-holo",
                        pointerX: px,
                        pointerY: py,
                        heroMask: masks?.hero,
                        frameSize: CGSize(width: w, height: h),
                        fitMode: .cover
                    )
                    .offset(x: artPX, y: artPY)
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    let nx = loc.x / max(w, 1)
                    let ny = loc.y / max(h, 1)
                    mouseNorm = CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
                    hoverActive = true
                case .ended:
                    hoverActive = false
                }
            }
        }
        .task(id: romID) {
            if let m = await HoloSaliencyService.shared.holoMasks(romID: romID, image: image, maxVisionDim: 640) {
                await MainActor.run { masks = m }
            }
        }
    }
}

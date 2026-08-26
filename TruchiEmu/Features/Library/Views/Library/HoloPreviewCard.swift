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
// `holoArtworkDefault` layout (cursor parallax + clip + hit-test disabled) so the
// preview is pixel-consistent with the real cards.
//
// Aspect ratio: the three region samples have different shapes (US/EU are
// landscape, JP is portrait). The card is sized to the image's own aspect ratio,
// centred inside the 200×280 area, so no region is cropped or stretched — just
// like real box-art cards keep their shape in the grid.
//
// Motion: by default the pointer drifts on a slow synthetic orbit (TimelineView)
// so the foil shimmers on its own. While the pointer is over the card the
// synthetic motion pauses and the foil tracks the real cursor; when the pointer
// leaves, the self-driven orbit resumes.
struct HoloPreviewCard: View {
    let image: NSImage
    let heroMask: NSImage?

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverActive = false
    @State private var mouseNorm = CGPoint(x: 0.5, y: 0.5)

    /// Fit the box art into the available area preserving its own aspect ratio,
    /// so landscape US/EU and portrait JP all show uncropped.
    private func fittedBoxartSize(image: NSImage?, w: CGFloat, h: CGFloat) -> CGSize {
        guard let img = image, img.size.width > 0, img.size.height > 0 else {
            return CGSize(width: w, height: h)
        }
        let artAspect = img.size.width / img.size.height
        let cardAspect = w / h
        if artAspect > cardAspect {
            return CGSize(width: w, height: w / artAspect)
        }
        return CGSize(width: h * artAspect, height: h)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let artSize = fittedBoxartSize(image: image, w: w, h: h)
            // Same cursor-parallax shift the production card uses (scaled to the
            // actual art size so the foil tracks consistently across ratios).
            let artShift = min(artSize.width, artSize.height) * 0.03

            ZStack {
                // Card backing fills the (possibly letterboxed) frame so the art
                // is never shown against a transparent gap for wide/tall ratios.
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

                    // Reuse the production reverse-holo renderer. The web view is
                    // sized to the art's own aspect ratio, so `cover` never crops.
                    // Render the web view 6% LARGER than the display frame and
                    // clip to `artSize`. This hides the parallax edge (same goal
                    // as the grid card's offset+clipped) WITHOUT upscaling the
                    // rendered raster — `.scaleEffect` here would blur the art.
                    ZStack {
                        HoloWebCardView(
                            image: image,
                            variantClass: "reverse-holo",
                            pointerX: px,
                            pointerY: py,
                            heroMask: heroMask,
                            frameSize: CGSize(width: artSize.width * 1.06, height: artSize.height * 1.06),
                            fitMode: .cover,
                            isActive: true
                        )
                        .frame(width: artSize.width * 1.06, height: artSize.height * 1.06)
                        .offset(x: artPX, y: artPY)
                    }
                    .frame(width: artSize.width, height: artSize.height)
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    // `loc` is in the card's local space; normalise against the
                    // centred fitted art rect so the foil tracks the cursor over
                    // the actual box art (not the letterboxed frame).
                    let artX = (w - artSize.width) / 2
                    let artY = (h - artSize.height) / 2
                    let nx = (loc.x - artX) / artSize.width
                    let ny = (loc.y - artY) / artSize.height
                    mouseNorm = CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
                    hoverActive = true
                case .ended:
                    hoverActive = false
                }
            }
        }
    }
}

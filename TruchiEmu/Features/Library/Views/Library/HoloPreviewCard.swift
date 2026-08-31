import SwiftUI
import AppKit

// A self-contained live preview of the holographic foil effect, used by the
// onboarding wizard so the user can see what the reverse-holo looks like on the
// box art for their chosen region before enabling the option.
//
// It reuses the exact same production renderer the grid cards use — the native
// SwiftUI/Metal `HoloFoilLayers` (the source-faithful simeydotme
// reverse-holo shine). The legacy WKWebView renderer has been removed, so this
// preview is now pixel-consistent with the real cards without hosting a web
// view. `HoloGameCardView.holoArtworkDefault` mirrors this layout (cursor
// parallax + clip + hit-test disabled).
//
// Aspect ratio: the three region samples have different shapes (US/EU are
// landscape, JP is portrait). The card is sized to the image's own aspect ratio,
// centred inside the available area, so no region is cropped or stretched — just
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

    /// Masks for the preview foil. A solid white mask lets the reverse-holo foil
    /// cover the whole card (the region split is irrelevant for a single demo
    /// card); `hero` uses the supplied mask when available.
    private func previewMasks() -> HoloMaskSet {
        let white = NSImage(size: NSSize(width: 8, height: 8))
        white.lockFocus()
        NSColor.white.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        white.unlockFocus()
        return HoloMaskSet(
            hero: heroMask ?? white,
            title: white,
            chrome: white,
            background: white
        )
    }

    /// Snapshot pinned to the reverse-holo (native) variant, so the preview
    /// always shows the reverse-holo shine regardless of the user's roll
    /// weights.
    private func previewSnapshot() -> HoloSettingsSnapshot {
        var snapshot = HoloSettingsSnapshot(from: HoloSettingsStore.shared, romID: "holo-preview")
        snapshot.randomization = HoloCardRandomization(
            seed: 1,
            variantWeights: [.reverseHolo: 1.0]
        )
        return snapshot
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let artSize = fittedBoxartSize(image: image, w: w, h: h)

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

                    ZStack {
                        BoxArtBaseView(
                            image: image,
                            normalizedMouseX: px,
                            normalizedMouseY: py,
                            isPressed: false,
                            w: artSize.width,
                            h: artSize.height,
                            tiltEnabled: false
                        )

                        HoloFoilLayers(
                            masks: previewMasks(),
                            settings: previewSnapshot(),
                            w: artSize.width,
                            h: artSize.height,
                            pointerX: px,
                            pointerY: py,
                            isHovered: true,
                            allowBump: false
                        )
                        .frame(width: artSize.width, height: artSize.height)

                        HoloScratchLayer(w: artSize.width, h: artSize.height)
                            .frame(width: artSize.width, height: artSize.height)

                        HoloSheenEffect(pointerX: px, pointerY: py)
                            .frame(width: artSize.width, height: artSize.height)
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

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
    /// Precomputed per-region masks for the sample box art, loaded from the
    /// bundle (see `SetupWizardView.maskSet(for:)`). The wizard never decomposes
    /// at runtime — these are generated offline via BoxArtLayers and shipped in
    /// `Resources/BoxArtSamples/`. When a region is missing (shouldn't happen),
    /// the fallback below covers the whole card so the foil never disappears.
    let masks: HoloMaskSet?

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

    /// Masks for the preview foil. Uses the bundled per-region masks when
    /// present. The fallback is a solid white mask so the foil still covers
    /// the whole card rather than vanishing if a mask is missing.
    private func previewMasks() -> HoloMaskSet {
        if let masks { return masks }
        let white = NSImage(size: NSSize(width: 8, height: 8))
        white.lockFocus()
        NSColor.white.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        white.unlockFocus()
        return HoloMaskSet(
            hero: white,
            title: white,
            chrome: white,
            background: white
        )
    }

    /// Snapshot pinned to the rainbow-rare (native) variant, so the preview
    /// always shows the rainbow-rare shine regardless of the user's roll
    /// weights.
    private func previewSnapshot() -> HoloSettingsSnapshot {
        var snapshot = HoloSettingsSnapshot(from: HoloSettingsStore.shared, romID: "holo-preview")
        snapshot.randomization = HoloCardRandomization(
            seed: 1,
            variantWeights: [.rainbowHolo: 1.0]
        )
        return snapshot
    }

    // MARK: - 3D pivot (mirrors HoloGameCardView)
    //
    // The artwork pivots toward the cursor exactly like the grid cards
    // (simeydotme `.card__rotator`): the box art rotates about its own centre
    // while the backing card stays flat. rotX/rotY reach ±maxTiltAngle at the
    // edges and are combined into a single axis-angle rotation so the
    // perspective projection applies exactly once (see HoloGameCardView for
    // the rationale).

    private let maxTiltAngle: Double = 9
    private let tiltPerspective: CGFloat = 0.5

    private func tiltRotationX(px: Double, py: Double) -> Double {
        (py - 0.5) * 2 * maxTiltAngle
    }

    private func tiltRotationY(px: Double, py: Double) -> Double {
        (0.5 - px) * 2 * maxTiltAngle
    }

    private func tiltCombinedAngle(px: Double, py: Double) -> Double {
        let ax = tiltRotationX(px: px, py: py) * .pi / 180
        let ay = tiltRotationY(px: px, py: py) * .pi / 180
        let qw = cos(ay / 2) * cos(ax / 2)
        return 2 * acos(min(max(qw, -1), 1)) * 180 / .pi
    }

    private func tiltCombinedAxis(px: Double, py: Double) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let ax = tiltRotationX(px: px, py: py) * .pi / 180
        let ay = tiltRotationY(px: px, py: py) * .pi / 180
        var x = cos(ay / 2) * sin(ax / 2)
        var y = sin(ay / 2) * cos(ax / 2)
        var z = -sin(ay / 2) * sin(ax / 2)
        let len = sqrt(x * x + y * y + z * z)
        if len < 1e-6 { return (1, 0, 0) }
        return (x / len, y / len, z / len)
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
                            tiltX: tiltRotationX(px: px, py: py),
                            tiltY: tiltRotationY(px: px, py: py),
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
                    .rotation3DEffect(
                        .degrees(tiltCombinedAngle(px: px, py: py)),
                        axis: tiltCombinedAxis(px: px, py: py),
                        anchor: .center,
                        perspective: tiltPerspective
                    )
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

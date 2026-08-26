import SwiftUI
import AppKit

// A self-contained live preview of the holographic foil effect, used by the
// onboarding wizard so the user can see what holo masks look like on the box
// art for their chosen region before enabling the option.
//
// It uses the SAME native SwiftUI/Metal renderer the app uses for the
// "Reverse Swift" variant (HoloFoilLayers + HoloSheenEffect + HoloScratchLayer),
// and mirrors how the real grid cards confine the foil to the box art's own
// fitted rectangle — so boxes of any aspect ratio (US / Japan / Europe previews
// differ in size and shape) are shown without zooming or stretching, with the
// holo effect clipped to the actual art.
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

    private var snapshot: HoloSettingsSnapshot {
        var snap = HoloSettingsSnapshot(from: HoloSettingsStore.shared)
        // Force the native reverse-holo ("Reverse Swift") look for the preview.
        // HoloCardRandomization has no memberwise init, so roll it with variant
        // weights that always pick .reverseSwift and a full deviation chance so
        // each zone gets its own mask/intensity/pattern.
        snap.randomization = HoloCardRandomization(
            seed: 1,
            deviationChance: 1.0,
            variantWeights: [.reverseSwift: 1.0]
        )
        return snap
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

                // Box art fit to its own aspect ratio — no zoom, no stretch.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)

                TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                    let t = ctx.date.timeIntervalSince1970
                    let autoX = 0.5 + 0.35 * sin(t * 0.9)
                    let autoY = 0.5 + 0.35 * cos(t * 0.6)
                    let px = hoverActive ? mouseNorm.x : autoX
                    let py = hoverActive ? mouseNorm.y : autoY
                    holoStack(px: px, py: py, artSize: artSize, isHovered: hoverActive)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    // `loc` is in the card's local space; normalise against the
                    // centered fitted art rect so the foil tracks the cursor over
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
        .task(id: romID) {
            if let m = await HoloSaliencyService.shared.holoMasks(romID: romID, image: image, maxVisionDim: 640) {
                await MainActor.run { masks = m }
            }
        }
    }

    @ViewBuilder
    private func holoStack(px: CGFloat, py: CGFloat, artSize: CGSize, isHovered: Bool) -> some View {
        ZStack {
            HoloFoilLayers(
                masks: masks,
                settings: snapshot,
                w: artSize.width,
                h: artSize.height,
                pointerX: px,
                pointerY: py,
                isHovered: isHovered,
                allowBump: false
            )
            HoloSheenEffect(pointerX: px, pointerY: py)
            HoloScratchLayer(w: artSize.width, h: artSize.height)
        }
        .frame(width: artSize.width, height: artSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

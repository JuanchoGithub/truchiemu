import SwiftUI
import AppKit

// One tile-view per variant, used by the Settings → Holo → Variant Weights
// rows. It renders the SAME foil surface the library cards use, lit by a
// fixed light so the swatch shows the material instead of a flat gradient.
// The light sits off-centre so the relief and its colour bands are visible
// at a glance.
struct VariantTileView: View {
    let variant: HoloVariant
    let settings: HoloSettingsSnapshot
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HoloFoilSurface(
            pattern: variant.sourceFoilPattern,
            colourway: variant.colourway(settings: settings),
            lightX: -0.55,
            lightY: 0.65,
            huePhase: 0.18,
            w: width,
            h: height,
            intensity: 1
        )
        .frame(width: width, height: height)
        .clipped()
    }
}

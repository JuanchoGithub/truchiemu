import SwiftUI
import AppKit

// One tile-view per variant. Stacks each shine layer as its own Canvas,
// applied with that layer's `mix-blend-mode` (`BlendMode`) plus its filter
// recipe (`brightness/contrast/saturate`). Source-faithful composition: the
// source CSS assigns one `.card__shine` block per layer with its own
// gradient + blend + filter, and the browser stacks them bottom-up with
// the blend mode resolving against layers below. SwiftUI's ZStack + per-view
// `.blendMode` does the same compositing in real time — no pre-baked
// `ImageRenderer` cache, since `ImageRenderer` does not honour non-trivial
// blend modes (colorDodge/hardLight etc. collapse to plain alpha).
//
// Each subview is fully static (depends only on the recipe), so SwiftUI's
// own view-graph caching keeps theGradient drawings recomputed once per
// state change; per-cursor effects (brightness/hue/sweep/mask) attach
// outside this view in `HoloFoilLayers`.
struct VariantTileView: View {
    let recipe: HoloVariantRecipe
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(recipe.shineLayers.enumerated()), id: \.offset) { idx, layer in
                let isBase = idx == 0
                HoloShineCanvasLayer(layer: layer, width: width, height: height)
                    // Per-layer filter applied BEFORE blend mode (matches
                    // CSS spec: filter, then mix-blend-mode). SwiftUI's
                    // `.brightness` is additive (-1..1); CSS's
                    // `brightness(N)` is multiplicative — map with `N - 1`.
                    // `.contrast` and `.saturation` are multiplier-style in
                    // both models (1.0 = neutral).
                    .brightness(max(-1, min(1, layer.filter.brightness - 1.0)))
                    .contrast(layer.filter.contrast)
                    .saturation(layer.filter.saturation)
                    // First layer = base opaque (source `.card__shine`'s own
                    // background-image, no internal mix-blend-mode). The
                    // ELEMENT's `mix-blend-mode: color-dodge` (vs art) is
                    // applied OUTSIDE — in `HoloFoilLayers` — so we must NOT
                    // colorDodge HERE against the transparent ZStack backdrop
                    // (that would self-destruct: colorDodge of opaque rainbow
                    // vs transparent = nothing). Subsequent layers carry
                    // `:before`/`:after` blend modes (hardLight, luminosity,
                    // overlay, ...) and composite against the base correctly.
                    .blendMode(isBase ? .normal : layer.blendMode)
            }
        }
    }
}

// One shine layer drawn to a Canvas. The drawing is just a filled rect with
// a gradient (repeating-linear-gradient or radial at the cursor). The blend
// mode, filter and any per-cursor modulation live on the parent SwiftUI
// view, not in the Canvas — `GraphicsContext` has no per-draw filters.
private struct HoloShineCanvasLayer: View {
    let layer: HoloShineLayer
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var mutCtx = ctx
            drawLayer(&mutCtx, in: size)
        }
        .frame(width: width, height: height)
    }

    private func drawLayer(_ ctx: inout GraphicsContext, in size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        if let radial = layer.radial {
            let stops = radial.stops.map { Gradient.Stop(color: $0.1, location: $0.0) }
            let gradient = Gradient(stops: stops)
            let cx = size.width * 0.5
            let cy = size.height * 0.5
            let radius = hypot(size.width, size.height)
            ctx.fill(
                Path(rect),
                with: .radialGradient(
                    gradient,
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0,
                    endRadius: radius
                )
            )
        } else {
            let palette = layer.palette
            guard !palette.colors.isEmpty else { return }
            let stops = palette.colors.enumerated().map { idx, color in
                Gradient.Stop(color: color, location: CGFloat(idx) / CGFloat(max(palette.colors.count - 1, 1)))
            }
            let gradient = Gradient(stops: stops)

            let period = size.width / max(CGFloat(palette.colors.count), 1)
            let cover = hypot(size.width, size.height) + period * 4
            let center = CGPoint(x: size.width * layer.basePositionX,
                                 y: size.height * layer.basePositionY)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: .degrees(palette.angle))
            ctx.translateBy(x: -center.x, y: -center.y)

            var x: CGFloat = -cover / 2
            let endX = cover / 2
            while x < endX {
                ctx.fill(
                    Path(CGRect(x: x, y: -cover, width: period, height: cover * 2)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: x, y: -cover),
                        endPoint: CGPoint(x: x + period, y: -cover)
                    )
                )
                x += period
            }
        }
    }
}

import SwiftUI
import AppKit
import Foundation
import CoreImage
import os.lock

// MARK: - CSS Color Palette (from simeydotme/pokemon-cards-css)

enum HoloCSSColors {
    static let violet = Color(red: 0.788, green: 0.161, blue: 0.945)   // #c929f1
    static let blue   = Color(red: 0.051, green: 0.741, blue: 0.914)   // #0dbde9
    static let green  = Color(red: 0.129, green: 0.914, blue: 0.522)   // #21e985
    static let yellow = Color(red: 0.933, green: 0.875, blue: 0.063)   // #eedf10
    static let red    = Color(red: 0.973, green: 0.055, blue: 0.208)   // #f80e35
}

// MARK: - Repeating Linear Gradient (Canvas-based, faithful to CSS repeating-linear-gradient)

struct RepeatingLinearGradientView: View {
    let colors: [Color]
    let angle: Double
    let period: CGFloat
    var centerOffset: CGSize = .zero

    var body: some View {
        Canvas { ctx, size in
            let cover = hypot(size.width, size.height) + period * 2
            let gradient = Gradient(colors: colors)

            ctx.translateBy(x: size.width / 2 + centerOffset.width, y: size.height / 2 + centerOffset.height)
            ctx.rotate(by: .degrees(angle))
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)

            var startX: CGFloat = -cover / 2
            let endX = cover / 2
            while startX < endX {
                ctx.fill(
                    Path(CGRect(x: startX, y: -cover, width: period, height: cover * 2)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: startX, y: -cover),
                        endPoint: CGPoint(x: startX + period, y: -cover)
                    )
                )
                startX += period
            }
        }
    }
}

// MARK: - Pre-rendered Foil Tiles

// The rainbow + texture + scanline foil is expensive to render (Canvas-based
// repeating gradients). Rendering it inside the view body on every cursor
// event was the source of the hover lag. Instead we pre-render each region's
// foil as an NSImage once per (pattern, size) — the cursor then only moves a
// layer transform, never re-runs a Canvas.
@MainActor
final class HoloFoilTileCache {
    static let shared = HoloFoilTileCache()

    private var tiles: [TileKey: NSImage] = [:]
    private var cacheOrder: [TileKey] = []
    // Bounded LRU of the pre-rendered foil tiles. Each tile is a full-bleed
    // `2w × 2h` NSImage, so the limit is the dominant Swift-engine memory cost.
    // Kept low and flushed on idle (see HoloSwiftCacheCoordinator) to mirror the
    // WebView pool's memory behaviour.
    private let cacheLimit = 12

    /// Drop all cached tiles. Called by HoloSwiftCacheCoordinator on idle so the
    /// warmed Swift-engine caches don't hold hundreds of MB for the app lifetime.
    func flush() {
        tiles.removeAll()
        cacheOrder.removeAll()
    }

    struct TileKey: Hashable {
        let pattern: HoloPattern
        let variantKey: String
        let width: Int
        let height: Int
    }

    /// A `2w × 2h` tile: the source's `background-size: 400% 400%` slide needs
    /// headroom around the card, otherwise shifting the foil would expose its
    /// edge. Masked to the foil texture, with the 90° scanline bars blended
    /// on top — everything `patternLayer` used to draw per frame.
    ///
    /// When `variant` is supplied, the rainbow colours come from that
    /// variant's first shine layer's palette (cosmos's six-rainbow, shiny's
    /// silver, radiant's faded-blue, etc.), making per-card variation a
    /// pure colour-swap of the same texture-masked holographic effect.
    /// When nil, the classic `violet/blue/.../red` palette is used.
    func tile(for pattern: HoloPattern, variant: HoloVariant? = nil, w: CGFloat, h: CGFloat) -> NSImage? {
        // Called on every Swift-engine foil render frame, so this keeps the
        // idle-flush coordinator's "last active" timestamp fresh while a card
        // is hovered (preventing a flush mid-hover).
        HoloSwiftCacheCoordinator.shared.noteUsage()
        let bw = Int((w * 2).rounded())
        let bh = Int((h * 2).rounded())
        guard bw > 0, bh > 0 else { return nil }
        let key = TileKey(pattern: pattern, variantKey: variant?.rawValue ?? "default", width: bw, height: bh)
        if let cached = tiles[key] {
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            return cached
        }

        guard let tex = HoloPatternStore.shared.alphaMask(
            for: pattern,
            scaledTo: NSSize(width: CGFloat(bw), height: CGFloat(bh))
        ) else { return nil }

        // Source rainbow palette, or the variant's first shine-layer palette
        // (variant.choose → shineLayers.first?.palette). Empty palette (e.g.
        // radiantHolo grayscale) falls back to the source rainbow to keep the
        // holographic colour visible.
        let paletteColors: [Color] = {
            if let variant,
               let firstPalette = variant.recipe.shineLayers.first?.palette,
               !firstPalette.colors.isEmpty {
                return firstPalette.colors
            }
            return [HoloCSSColors.violet, HoloCSSColors.blue, HoloCSSColors.green, HoloCSSColors.yellow, HoloCSSColors.red]
        }()
        // Use the variant's source-defined rainbow angle (cosmos 82°, shiny 0°,
        // amazing 133°, …) instead of a hardcoded 110°, so the swift foil tilts
        // like the simeydotme CSS rather than always at the regular-holo angle.
        let paletteAngle = variant?.recipe.shineLayers.first?.palette.angle ?? 110

        let content = ZStack {
            RepeatingLinearGradientView(
                colors: paletteColors,
                angle: paletteAngle,
                period: w * 1.4 // one full rainbow ≈ 1.4 card widths (source: 3 rainbows across the 400% tile)
            )
            .frame(width: CGFloat(bw), height: CGFloat(bh))
            .mask(
                Image(nsImage: tex)
                    .resizable()
                    .frame(width: CGFloat(bw), height: CGFloat(bh))
            )

            // Scanlines: the source's second repeating-linear-gradient (90°,
            // 1px dark/light bars) under `background-blend-mode: overlay`.
            RepeatingLinearGradientView(
                colors: [Color(white: 0.4, opacity: 0.18), Color(white: 0.0, opacity: 0.0), Color(white: 0.4, opacity: 0.18)],
                angle: 90,
                period: 2,
                centerOffset: .zero
            )
            .frame(width: CGFloat(bw), height: CGFloat(bh))
            .blendMode(.overlay)
        }
        .frame(width: CGFloat(bw), height: CGFloat(bh))

        let renderer = ImageRenderer(content: content)
        // The foil tile is a smooth rainbow gradient (plus faint 1px scanlines),
        // so rendering at 1× and letting SwiftUI upscale on-screen is visually
        // identical to the old 2× but uses a quarter of the tile memory. With the
        // LRU cap at 12 this is the single largest Swift-engine memory saving.
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(bw), height: CGFloat(bh)))
        tiles[key] = img
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            tiles[cacheOrder.removeFirst()] = nil
        }
        return img
    }
}

// Variant-aware contrast/saturation/brightness applied to the whole
// `HoloFoilLayers` stack (before `colorDodge`). The standard rainbow variants
// keep the source-faithful high-contrast "blowout"; Reverse Holo in solid /
// background colour mode uses a mild, colour-preserving treatment that is
// visible at rest (real reverse holo foils the whole card), and never rotates
// the user's chosen hue.
// MARK: - Per-layer shine tiles (faithful layer stack)

// The web (simeydotme CSS) renders each variant as a STACK of shine layers,
// each with its own gradient, `mix-blend-mode`, and `filter`. To match that in
// SwiftUI without per-frame Canvas redraw (the original hover-lag source), we
// pre-render each layer's pure gradient once into a `2w × 2h` tile and stack
// them with their blend modes + per-layer parallax. The cursor only moves cheap
// transforms (offset/hue), so the heavy drawing is cached.
@MainActor
final class HoloShineLayerTileCache {
    static let shared = HoloShineLayerTileCache()

    private var tiles: [TileKey: NSImage] = [:]
    private var order: [TileKey] = []
    private let limit = 18

    struct TileKey: Hashable {
        let variant: String
        let index: Int
        let w: Int
        let h: Int
    }

    func tile(variant: HoloVariant, layerIndex: Int, w: CGFloat, h: CGFloat) -> NSImage? {
        guard layerIndex >= 0, layerIndex < variant.recipe.shineLayers.count else { return nil }
        let bw = Int((w * 2).rounded())
        let bh = Int((h * 2).rounded())
        guard bw > 0, bh > 0 else { return nil }
        let key = TileKey(variant: variant.rawValue, index: layerIndex, w: bw, h: bh)
        if let cached = tiles[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return cached
        }
        let layer = variant.recipe.shineLayers[layerIndex]
        // `visibleWidth = w` keeps the stripe density identical to the preview
        // swatch (which draws at the visible width) while the 2× canvas gives
        // parallax headroom so the rainbow can slide without exposing an edge.
        // The layer's own `filter` (brightness/contrast/saturation) is baked in
        // here so the single-Canvas stack (which composites with the reliable
        // `GraphicsContext.blendMode`) doesn't need per-draw filters.
        let content = ShineLayerTileCanvas(layer: layer, size: CGSize(width: bw, height: bh), visibleWidth: w)
            .frame(width: CGFloat(bw), height: CGFloat(bh))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        var img = NSImage(cgImage: cg, size: NSSize(width: bw, height: bh))
        // Apply the layer's `filter` as a true CSS-style brightness/contrast/
        // saturation (multiplicative around 0.5), NOT SwiftUI's additive
        // `.brightness()` — additive darkens dark palettes toward black, which is
        // what made cosmos / v-full-art / shiny render as nothing.
        img = Self.cssFiltered(img, layer.filter)
        tiles[key] = img
        order.append(key)
        if order.count > limit { tiles[order.removeFirst()] = nil }
        return img
    }

    // CSS-accurate brightness/contrast/saturation via a Core Image color matrix.
    // brightness & contrast are multiplicative (CSS `brightness(N)` scales RGB,
    // `contrast(N)` pivots at 0.5); saturation is the standard luma mix. SwiftUI's
    // `.brightness()` is additive and would clamp dark colors to black, so we avoid it.
    private static func cssFiltered(_ img: NSImage, _ f: HoloFilterRecipe) -> NSImage {
        guard (f.brightness != 1.0 || f.contrast != 1.0 || f.saturation != 1.0),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return img }
        let ci = CIImage(cgImage: cg)
        let filter = CIFilter.colorMatrix()
        let bc = f.brightness * f.contrast
        let s = max(0.0, f.saturation)
        let lr: CGFloat = 0.2126, lg: CGFloat = 0.7152, lb: CGFloat = 0.0722
        filter.rVector = CIVector(x: (lr + s * (1 - lr)) * bc, y: lg * (1 - s) * bc, z: lb * (1 - s) * bc, w: 0)
        filter.gVector = CIVector(x: lr * (1 - s) * bc, y: (lg + s * (1 - lg)) * bc, z: lb * (1 - s) * bc, w: 0)
        filter.bVector = CIVector(x: lr * (1 - s) * bc, y: lg * (1 - s) * bc, z: (lb + s * (1 - lb)) * bc, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let bias = 0.5 * (1 - f.contrast)
        filter.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        filter.inputImage = ci
        guard let out = filter.outputImage,
              let cgOut = CIContext(options: nil).createCGImage(out, from: out.extent) else { return img }
        return NSImage(cgImage: cgOut, size: img.size)
    }

    func flush() {
        tiles.removeAll()
        order.removeAll()
    }
}

/// One shine layer drawn to a Canvas — identical maths to `HoloShineCanvasLayer`
/// (the preview swatch renderer) but rendered at an arbitrary size with a
/// caller-supplied `visibleWidth` so the stripe density matches the card while
/// the canvas is oversized for parallax.
private struct ShineLayerTileCanvas: View {
    let layer: HoloShineLayer
    let size: CGSize
    let visibleWidth: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let rect = CGRect(origin: .zero, size: size)
            if let radial = layer.radial {
                let stops = radial.stops.map { Gradient.Stop(color: $0.1, location: $0.0) }
                let radius = hypot(size.width, size.height)
                let center = CGPoint(x: size.width * layer.basePositionX,
                                     y: size.height * layer.basePositionY)
                ctx.fill(
                    Path(rect),
                    with: .radialGradient(
                        Gradient(stops: stops),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            } else {
                let palette = layer.palette
                guard !palette.colors.isEmpty else { return }
                let stops = palette.colors.enumerated().map {
                    Gradient.Stop(color: $0.1, location: CGFloat($0.0) / CGFloat(max(palette.colors.count - 1, 1)))
                }
                let period = visibleWidth / CGFloat(max(palette.colors.count, 1))
                let cover = hypot(size.width, size.height) + period * 4
                let center = CGPoint(x: size.width * layer.basePositionX,
                                     y: size.height * layer.basePositionY)
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: .degrees(palette.angle))
                ctx.translateBy(x: -center.x, y: -center.y)
                var x = -cover / 2
                let endX = cover / 2
                while x < endX {
                    ctx.fill(
                        Path(CGRect(x: x, y: -cover, width: period, height: cover * 2)),
                        with: .linearGradient(
                            Gradient(stops: stops),
                            startPoint: CGPoint(x: x, y: -cover),
                            endPoint: CGPoint(x: x + period, y: -cover)
                        )
                    )
                    x += period
                }
            }
        }
    }
}

struct HoloFoilContrastModifier: ViewModifier {
    let isReverse: Bool
    let isRegularHolo: Bool
    let isRadiant: Bool
    let isAmazingRare: Bool
    let isShinyRare: Bool
    let isVFullArt: Bool
    let isCosmos: Bool
    let isRainbowHolo: Bool
    let isLayered: Bool
    let revRainbow: Bool
    let pfc: CGFloat

    func body(content: Content) -> some View {
        if revRainbow {
            content
                .contrast(2.75)
                .saturation(0.65)
                .brightness(-0.4 + pfc * 0.25)
        } else if isCosmos {
            // Cosmos is a live, pointer-tracking shine (`cosmosShine`): a bright
            // 82deg rainbow + a cyan radial glow. The element-level modifier must
            // NOT darken it (additive `.brightness()` blacked out the galaxy), so
            // only a mild CSS-like contrast/saturation lift for the colour-dodge.
            content
                .contrast(1.2)
                .saturation(1.1)
        } else if isLayered {
            // The layered stack already carries each layer's own CSS-accurate
            // `filter` (brightness/contrast/saturation, now applied multiplicatively
            // in the tile cache). The element-level modifier therefore only adds a
            // mild CSS-like contrast/saturation lift for the colour-dodge — NO
            // additive `.brightness()` (that darkened dark palettes to black, which
            // made cosmos / v-full-art / shiny render as nothing).
            content
                .contrast(1.35)
                .saturation(1.15)
        } else if isReverse || isRegularHolo || isRadiant || isAmazingRare || isShinyRare || isVFullArt || isRainbowHolo {
            // Reverse Holo / Holofoil Rare bake their own source-faithful filter
            // into the live shine (`reverseShine` / `regularHoloShine`) before
            // the colour-dodge, so the body-level modifier is a no-op (brightness
            // only) here to avoid double-applying the generic high-contrast
            // "blowout". Only the pointer-from-center brightness lift (base.css) is kept.
            content
                .contrast(1.0)
                .saturation(1.0)
                .brightness(-0.4 + pfc * 0.25)
        } else {
            content
                .contrast(2.75)
                .saturation(0.65)
                .brightness(-0.4 + pfc * 0.25)
        }
    }
}

// MARK: - Holo Foil (cached tiles, static position)

// Faithful to simeydotme/pokemon-cards-css `regular-holo.css` `.card__shine`:
//   background-image: repeating-linear-gradient(110deg, violet…red),
//                     repeating-linear-gradient(90deg, scanlines);
//   background-size: 400% 400%, cover;
//   background-blend-mode: overlay;
//   filter: brightness(calc((var(--pointer-from-center)*0.25) + 0.6))
//           contrast(1.1) saturate(1.2);
//   mix-blend-mode: color-dodge;
// The rainbow is rendered ONCE into a pre-rendered tile (see
// `HoloFoilTileCache`) and clipped to each region mask, which stays fixed to
// the art. The foil never translates with the cursor (shifting the gradient
// against non-tilting art read as the mask drifting with the mouse). Instead
// the cursor drives the foil's *appearance* through cheap, GPU-only effects,
// keeping the masks glued to the art:
//   • brightness from pointer-from-center — the foil brightens (0.6 -> 0.85)
//     as the cursor moves off-center, matching the source's
//     `--pointer-from-center` filter modulation. This is the vivid "blowout"
//     the source is known for;
//   • hue shift — `.hueRotation` rotates the whole rainbow as the cursor
//     moves, like tilting a real holo card to change which colors show;
//   • sweep band — a bright specular strip glides across each masked region
//     following the cursor, the classic holo "light reflection".
// The source does NOT confine the foil to a tight radial spotlight under
// the cursor — the foil is visible across the whole masked region, with
// brightness (not opacity) reacting to cursor proximity. That gives the
// "light shines on the foil" feel without hiding most of the rainbow.
struct HoloFoilLayers: View, Equatable {
    let masks: HoloMaskSet?
    let settings: HoloSettingsSnapshot
    let w: CGFloat
    let h: CGFloat
    /// Normalized cursor X (0…1) within the artwork. Drives the hue shift, the
    /// sweep band, and the radial reveal center. Falls back to 0.5 (centered)
    /// when the cursor is away — harmless since the parent gates the whole
    /// layer off via `holoIntensity`.
    let pointerX: CGFloat
    /// Normalized cursor Y (0…1) within the artwork. Centers the radial reveal
    /// vertically. Same fallback convention as `pointerX`.
    let pointerY: CGFloat
    /// Card tilt in degrees about X (top rises when negative). Drives the
    /// bump shader's light direction (rotated into the tilted card's frame)
    /// and the parallax shear on the foil tile. Default 0 so the parallax
    /// mode can fall back to pure cursor-driven motion when the caller
    /// doesn't supply tilt (e.g. variant preview swatches).
    var tiltX: Double = 0
    /// Card tilt in degrees about Y (left rises when negative). Same fallback
    /// as `tiltX`.
    var tiltY: Double = 0
    /// Whether the card is currently hovered. The Metal bump shader is
    /// expensive (a full render per region per cursor move), so we only
    /// render it for the hovered card — every other card falls back to the
    /// cheap parallax layer (or nothing in pure-bump mode).
    var isHovered: Bool = false
    /// Allow the Metal bump pass. Disabled for tiny secondary reflections
    /// (e.g. the holo card's own glass-orb play button), where the bump
    /// relief is invisible at that scale and re-running the renderer
    /// concurrently with the card's own pass is wasteful and unsafe.
    var allowBump: Bool = true

    var body: some View {
        let isReverse = (settings.randomization?.variant == .reverseHolo)
        let isRegularHolo = (settings.randomization?.variant == .regularHolo)
        let isRadiant = false
        let isAmazingRare = false
        let isShinyRare = false
        let isVFullArt = false
        let isCosmos = false
        let isRainbowHolo = (settings.randomization?.variant == .rainbowHolo)
        let isLayered = false
        let revRainbow = isReverse && settings.reverseColorMode == .rainbow
        let hueDegrees = (pointerX - 0.5) * settings.hueCycles * 360 + (pointerY - 0.5) * settings.hueCycles * 360
        let regionFoil = ZStack {
            if let masks {
                if let randomization = settings.randomization {
                    // Per-launch, per-card roll: each zone picks its own
                    // texture pattern via `randomization.pattern(zone)` AND
                    // its own holo variant via `randomization.variant`. The
                    // pattern provides the diffraction-grating (scanlines)
                    // base; the variant provides the rainbow/color-sweep
                    // character (regularHolo rainbow stripes, cosmos radial
                    // glow, etc.). Stacked source-faithfully inside
                    // `regionLayer`.
                    if randomization.active(.background), let background = masks.background {
                        regionLayer(randomization.pattern(.background),
                                    variant: randomization.variant,
                                    intensity: randomization.intensity(.background),
                                    mask: background, w: w, h: h)
                    }
                    if randomization.active(.title), let title = masks.title {
                        regionLayer(randomization.pattern(.title),
                                    variant: randomization.variant,
                                    intensity: randomization.intensity(.title),
                                    mask: title, w: w, h: h)
                    }
                    if randomization.active(.chrome), let chrome = masks.chrome {
                        regionLayer(randomization.pattern(.chrome),
                                    variant: randomization.variant,
                                    intensity: randomization.intensity(.chrome),
                                    mask: chrome, w: w, h: h)
                    }
                    if randomization.active(.hero), let hero = masks.hero {
                        regionLayer(randomization.pattern(.hero),
                                    variant: randomization.variant,
                                    intensity: randomization.intensity(.hero),
                                    mask: hero, w: w, h: h)
                    }
                }
            }
        }
        // Parallax shear (source-faithful illusion). When the cursor moves
        // off-center the rainbow tile is shifted inside its 2w × 2h frame so
        // the rainbow visibly slides across the etched mask. The tile is
        // already 2× over-sized, so a shear up to ±25% stays inside the
        // frame and never exposes an edge. Strength scales with the user
        // slider; cursor X is shifted by 2.6× its offset, Y by 3.5× (matches
        // the source repo's `regular-holo.css` `background-position` formula).
        // The tilt axes (tiltX, tiltY) add a small secondary shear so the
        // rainbow visibly responds to card rotation too — the source repo
        // achieves this via its 3D rotator; we mirror it as a 2D offset for
        // the non-bump path.
        .offset(parallaxOffset(variant: settings.randomization?.variant))
        // The per-region stack (texture-masked rainbow + sweep band) is
        // flattened into one layer so the outer `.colorDodge` treats the
        // whole masked foil as a single source vs the art — matches CSS
        // `mix-blend-mode` on `.card__shine` which composites a
        // (pre-flattened) element. Without this each child would colorDodge
        // the art separately and blow everything white.
        .compositingGroup()
        // Source base.css `.card__shine` filter: `brightness(.85)
        // contrast(2.75) saturate(.65)`. HIGH CONTRAST (2.75) leaves only
        // the brightest rainbow bands as visible light once colorDodge'd
        // (dark rainbow stops → black → colorDodge identity); LOW SATURATION
        // (.65) keeps the rainbow from becoming a saturated wash.
        // SwiftUI's `.brightness` is additive (-1..1); CSS `brightness(N)`
        // is multiplicative so 0.85 → -0.15 (slight dim before dodge).
        .modifier(HoloFoilContrastModifier(isReverse: isReverse, isRegularHolo: isRegularHolo, isRadiant: isRadiant, isAmazingRare: isAmazingRare, isShinyRare: isShinyRare, isVFullArt: isVFullArt, isCosmos: isCosmos, isRainbowHolo: isRainbowHolo, isLayered: isLayered, revRainbow: revRainbow, pfc: pointerFromCenter))
        // Blend mode. Reverse Holo uses `color-dodge` (source-faithful blowout).
        // Holofoil Rare also uses `color-dodge` in the source, but that blend
        // LIGHTENS — over our bright/white card art a bright rainbow blows
        // straight to white (invisible), so only the mid-tone edges show any
        // colour. `multiply` is the complement: rainbow × white art = the
        // rainbow itself, so the full diagonal rainbow reads across the bright
        // card. Trade-off: pure-black art areas go black (no rainbow there),
        // which is acceptable since our cards are predominantly light.
                    .blendMode(.colorDodge)
        // Angular hue shift: rotate the whole rainbow as the cursor moves.
        // `settings.hueCycles` full 360° rotations occur as the cursor travels
        // from one edge to the opposite edge along each axis (both axes
        // contribute, so moving diagonally shifts hue on both), matching the
        // `hueShiftDegrees` fed to the Metal bump shader below. 0 disables the
        // shift; the default of 4 makes the rainbow cycle four times across the
        // card. Pure GPU color filter on the pre-rendered tiles — no re-render
        // per cursor event.
        // `hueRotation` rotates the WHOLE foil. For variants whose foil is a
        // fixed rainbow (regularHolo-like) that's correct, but for variants that
        // carry a texture (cosmos) the texture — not the rainbow — must be the
        // colour/hue carrier (mirrors reverseSwift's `.colorMultiply`/`rainbowHue`
        // on its texture). So cosmos is excluded here; its texture is hued inside
        // `cosmosShine`.
        .hueRotation(.degrees(revRainbow || (!isReverse && !isRegularHolo && !isCosmos && !isRainbowHolo && !isAmazingRare && !isShinyRare && !isVFullArt) ? hueDegrees : 0))

        // Glare — `.card__glare` is a SEPARATE element in the source, blended
        // `overlay` (not colour-dodge) on top of the foil. For Holofoil Rare it
        // adds the bright sweeping highlight. Kept outside the colour-dodge
        // group so it keeps its own overlay blend.
        return ZStack {
            regionFoil
            if isRegularHolo {
                regularHoloGlare(w: w, h: h)
                    .blendMode(.overlay)
            }
            if isRainbowHolo {
                rainbowHoloGlare(w: w, h: h)
                    .blendMode(.hardLight)
            }
            if isRadiant {
                radiantGlare(w: w, h: h)
                    .blendMode(.hardLight)
            }
        }
    }

    /// Normalized distance from the artwork center (0 at center, 1 at corner).
    /// Drives the pointer-from-center brightness modulation above. Maximum
    /// distance in unit space is sqrt(0.5² + 0.5²) = ~0.707, so we divide by
    /// that to normalize. Matches the source's `--pointer-from-center`:
    /// `sqrt((x-50)² + (y-50)²) / 50` (their units are %, ours are 0..1).
    private var pointerFromCenter: CGFloat {
        let dx = pointerX - 0.5
        let dy = pointerY - 0.5
        return min(hypot(dx, dy) / 0.70710678, 1)
    }

    /// Source-faithful parallax shear applied to the rainbow tile. Multipliers
    /// (2.6× horizontal, 3.5× vertical) match the source repo's
    /// `regular-holo.css` `background-position` formula
    /// `calc(((50% - var(--background-x)) * 2.6) + 50%)`. The tilt
    /// contribution adds a small secondary shear proportional to the card's
    /// rotation angles — at ±9° max tilt, this peaks at ~±3pt on a 240pt-wide
    /// card, which is below the visible threshold but adds motion during
    /// tilt. Net effect: rainbow visibly slides across the etched mask as
    /// the cursor moves or the card tilts, replicating the source repo's
    /// actual technique (NOT a bump map — see AGENTS.md commentary).
    private func parallaxOffset(variant: HoloVariant?) -> CGSize {
        // Hard-disabled when bump-only is requested: the bump shader has its
        // own light-direction math, parallax shear would double-up.
        let mode = settings.depthMode
        let strength = settings.parallaxStrength
        guard mode != .bump, strength > 0.001 else { return .zero }
        // Reverse Holo / Holofoil Rare have their own internal parallax (the
        // rainbow/beam slide in `reverseShine` / `regularHoloShine`); adding
        // the global shear would double the motion.
        if variant == .reverseHolo || variant == .regularHolo { return .zero }
        let cx = (pointerX - 0.5) * 2.6
        let cy = (pointerY - 0.5) * 3.5
        // Tilt contributes ~0.05× the rotation in degrees → points. At max
        // tilt (9°) this is 0.45pt on a 240pt card, giving a subtle drift.
        let tx = CGFloat(tiltY) * -0.05 * strength
        let ty = CGFloat(tiltX) *  0.05 * strength
        // Negative: source uses `50% - var(--background-x)` so positive
        // cursor offset pulls the rainbow opposite direction.
        return CGSize(width: -cx * strength + tx, height: -cy * strength + ty)
    }

    @ViewBuilder
    private func maskView(_ mask: NSImage?, w: CGFloat, h: CGFloat) -> some View {
        if let mask {
            Image(nsImage: mask)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipped()
        } else {
            // Source semantics: `mask-image: var(--mask)` only applies foil
            // where the mask says. No mask = no foil for that region. We must
            // NOT fall back to white (would paint foil everywhere); clear
            // hides the region entirely.
            Color.clear
        }
    }

    /// One region's foil, source-faithful. The rainbow is masked by the
    /// selected `holo_*.png` texture's luminance (`CIMaskToAlpha`): bright
    /// texture pixels = opaque, dark = transparent. So the holographic
    /// effect appears ONLY in the texture's bright shape — the texture is
    /// effectively a coverage map for the holo shimmer, exactly like a
    /// texture map in a 3D shader that gates a holographic highlight. The
    /// card itself is never darkened — `.colorDodge` only ever LIGHTENS
    /// the art where the texture-masked foil is opaque-bright, and leaves
    /// transparent (dark-texture) areas exactly untouched.
    ///
    ///   1. **Per-layer shine stack** — for the layered variants (cosmos,
    ///      rainbow, shiny, v-full-art, secret, amazing) each `HoloShineLayer`
    ///      of the variant recipe is a cached `2w×2h` gradient tile, composited
    ///      bottom-up with its own `blendMode` + `filter` (`layeredShine`),
    ///      faithfully reproducing the simeydotme CSS `.card__shine` layer stack
    ///      (and the preview swatch). The `holo_*.png` texture tile
    ///      (`HoloFoilTileCache.tile`) is retained only as the normal map for the
    ///      optional Metal bump relief, not as the visible foil.
    ///   2. **Specular sweep band** — a narrow white strip that follows the
    ///      cursor across the masked region. Source's specular-light feel;
    ///      LIFT ONLY at the cursor location, no darkening elsewhere.
    ///
    /// Outer `HoloFoilLayers` flattens both with
    /// `.compositingGroup().colorDodge()` against the box art — source's
    /// `mix-blend-mode: color-dodge` on `.card__shine`. colorDodge of pure
    /// black (transparent area) leaves the art unchanged; colorDodge of the
    /// bright rainbow AT the texture's bright pixels LIGHTENS the art
    /// holographically. No dark pass. The card never goes darker than
    /// without the foil.
    @MainActor
    @ViewBuilder
    private func regionLayer(_ pattern: HoloPattern, variant: HoloVariant?, intensity: Double, mask: NSImage, w: CGFloat, h: CGFloat) -> some View {
        let isReverse = (variant == .reverseHolo)
        // Holofoil Rare (regularHolo) is also a live, pointer-driven shine
        // (`regularHoloShine`), so it shares Reverse Holo's "no baked tile"
        // treatment. Every other variant uses the pre-rendered tile.
        let isLiveShine = isReverse || variant == .regularHolo
        // Reverse Holo / Holofoil Rare are rendered as live, pointer-driven
        // shines — no baked tile, because the moving highlight must track the
        // cursor. Every other variant uses the pre-rendered tile.
        let textureTile: NSImage? = isLiveShine
            ? nil
            : HoloFoilTileCache.shared.tile(for: pattern, variant: variant, w: w, h: h)
        let bandWidth = w * 0.5
        ZStack {
            // Bump path: skipped for live shines (Reverse Holo / Holofoil Rare)
            // — their highlight is a 2D parallax illusion driven by the cursor;
            // the Metal bump would double up and lose the cursor-tracking read.
            if !isLiveShine, settings.depthMode != .bump, isHovered, allowBump {
                bumpLayer(pattern: pattern, variant: variant, mask: mask, textureTile: textureTile, w: w, h: h, intensity: intensity)
            }
            // Parallax path: always on for live shines (their only path).
            if settings.depthMode != .bump || isLiveShine {
                parallaxLayer(pattern: pattern, variant: variant, intensity: intensity, mask: mask, w: w, h: h, textureTile: textureTile, bandWidth: bandWidth)
            }
        }
        .frame(width: w * 2, height: h * 2)
        .frame(width: w, height: h, alignment: .center)
        .clipped()
        .mask(maskView(mask, w: w, h: h))
        // Edge-fade: source reverse-holo.css sets
        //   opacity: calc((1.5 * card-opacity) - pointer-from-center)
        // so the foil is strongest at the cursor-centre and fades toward the
        // card edges as the pointer moves out. Applied to Reverse Holo only
        // (the base `.card__shine` has no pointer-distance fade).
        .opacity(isReverse
            ? min(1.0, max(0.0, intensity * (1.5 - pointerFromCenter)))
            : intensity)
    }

    /// Parallax illusion layer — the existing source-faithful rainbow tile
    /// + sweep band, or the live Reverse Holo shine. Rendered when
    /// `depthMode != .bump` (so it's shown in `.parallax` and `.both` modes),
    /// and unconditionally for Reverse Holo.
    @ViewBuilder
    private func parallaxLayer(pattern: HoloPattern, variant: HoloVariant?, intensity: Double, mask: NSImage, w: CGFloat, h: CGFloat, textureTile: NSImage?, bandWidth: CGFloat) -> some View {
        if let variant, variant == .reverseHolo {
            // Live, pointer-driven Reverse Holo shine (reverse-holo.css).
            reverseShine(w: w, h: h)
                .frame(width: w * 2, height: h * 2)
        } else if let variant, variant == .regularHolo {
            // Live, pointer-driven Holofoil Rare shine (regular-holo.css).
            regularHoloShine(w: w, h: h)
                .frame(width: w * 2, height: h * 2)
        } else if let variant, variant == .rainbowHolo {
            // Live, pointer-driven Rainbow Rare shine (rare-rainbow.css): glitter
            // texture + 7-hue rainbow with `luminosity`/`soft-light` blends, a
            // `:after` colour-dodge rainbow, and an illusion-mask `:before`.
            rainbowHoloShine(w: w, h: h)
                .frame(width: w * 2, height: h * 2)
        } else if let tile = textureTile {
            Image(nsImage: tile)
                .resizable()
                .frame(width: w * 2, height: h * 2)
        }
        // Sweep band for the rainbow variants (subtle gloss). Suppressed for
        // Reverse Holo and Holofoil Rare — their moving highlight comes from
        // their live shines (the rainbow slide / the vertical beam bars).
        let isReverse = (variant == .reverseHolo)
        let bandPeak: Double = (isReverse || variant == .regularHolo || variant == .rainbowHolo) ? 0.0 : 0.7
        let bandW: CGFloat = bandWidth
        if bandPeak > 0 {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(bandPeak),
                    Color.white.opacity(0.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: bandW, height: h * 2)
            .offset(x: (pointerX - 0.5) * w * 2)
        }
    }



    /// Source-faithful Reverse Holo `.card__shine` (reverse-holo.css), built
    /// LIVE (not a baked NSImage) so the highlight tracks the cursor:
    ///   layer 3 (foil):  the grating "paper" — a generated diamond lattice
    ///                     (two crossed repeating gradients multiplied), tinted
    ///                     to the chosen/background colour. The source builds
    ///                     its foil the same way: layered CSS gradients that
    ///                     interact through blend modes (no image file needed).
    ///   layer 2 (shade): a -45° black→white→black band that slides with the
    ///                     cursor (overlay), so each texture cell lifts then
    ///                     drops — same colour, varying shade.
    ///   layer 1 (glare): a cursor-centred radial (soft-light).
    ///   filter: brightness(.55) contrast(1.5) saturate(1);
    ///   mix-blend-mode: color-dodge onto the art (the outer HoloFoilLayers
    ///   clips to the region mask and colour-dodges).
    // MARK: - Reverse Holo (faithful to simeydotme reverse-holo.css)
    //
    // Source model (reverse-holo.css): the shine is three layers —
    //   1. radial-gradient(circle at pointer, #fff 5%, #000 50%, #fff 80%)  -> soft-light
    //   2. linear-gradient(-45deg, #000 15%, #fff, #000 85%)                -> difference
    //   3. var(--foil)  (a diamond-lattice etch, injected at runtime)        -> normal
    // then  filter: brightness(.55) contrast(1.5) saturate(1);
    // then  mix-blend-mode: color-dodge  onto the card art.
    //
    // Layer 2 is the moving diagonal "light ray": blended with `difference`
    // over the foil lattice, the ray INVERTS the diamonds it covers. So cells
    // under the ray flip bright/dark (the inverse relation) while cells away
    // from the ray keep the lattice. colour-dodge then lifts the bright cells
    // to white and leaves the dark cells as a darker shade of the card's own
    // colour — exactly the metallic-paper reverse holo read.

    /// Full reverse-holo shine: foil lattice + moving difference ray + radial
    /// soft-light glow, filtered and colour-dodged onto the art by the caller.
    @ViewBuilder
    private func reverseShine(w: CGFloat, h: CGFloat) -> some View {
        let period = max(w, h) * 0.06
        let mode = settings.reverseColorMode
        // The diagonal ray is offset along its own (-45°) axis as the pointer
        // moves, so the white band slides across the foil (its `background-
        // position` tracks the pointer in the source).
        let rayOffset = CGSize(width: (pointerX - 0.5) * w * 1.6,
                              height: -(pointerY - 0.5) * h * 1.6)

        ZStack {
            // Layer 3 — the foil (greyscale metallic lattice for every mode;
            // rainbow's hue is added as a separate lit-area overlay below).
            reverseFoil(period: period, w: w, h: h)

            // Layers 2 + 1 (the moving light/dark sweep). For rainbow these are
            // masked by the foil heightmap so they ONLY play on the lit cells —
            // the dark (non-hue) cells get zero light/dark change (the card
            // shows through untouched). Other modes keep the full sweep.
            ZStack {
                // Layer 2 — the moving diagonal light ray, difference-blended
                // over the foil. White centre inverts the lattice (bright<->dark
                // flip); black ends leave it untouched. This is the source's
                // `difference`.
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: .black, location: 0.15),
                        Gradient.Stop(color: .white, location: 0.5),
                        Gradient.Stop(color: .black, location: 0.85),
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .blendMode(.difference)
                .frame(width: w * 3, height: h * 3)
                .offset(rayOffset)

                // Layer 1 — cursor radial glow, soft-light (source-faithful).
                // softLight with BLACK squares the foil (a -> a^2), which is
                // perfect for solid/background (dark + highlights) but crushes
                // rainbow's dark cells to near-black. For rainbow, lift the
                // mid-stop to a mid-grey so the glow stays without nuking the
                // colour.
                RadialGradient(
                    stops: [
                    Gradient.Stop(color: .white, location: 0.05),
                    Gradient.Stop(color: mode == .rainbow ? Color(white: 0.45) : .black, location: 0.5),
                    Gradient.Stop(color: .white, location: 0.8),
                    ],
                    center: UnitPoint(x: pointerX, y: pointerY),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.75
                )
                .blendMode(.softLight)
                .frame(width: w * 2, height: h * 2)
            }
            // The light/dark sweep is gated by the foil's luminance mask in
            // EVERY mode (not just rainbow). This is what makes the reverse
            // holo sections read as transparent: the sweep — which is white and
            // colour-dodged so it would otherwise cover the whole card — only
            // plays through the etch's visible (mid-bright) cells, so the dark
            // valleys and blown-out highlights let the card art show through.
            .mask(foilLuminanceMask(period: period, w: w, h: h))
        }
        .compositingGroup()
        // source: filter: brightness(.55) contrast(1.5) saturate(1).
        // Rainbow's dark areas are fully transparent (metallic base dropped),
        // so there's no dark/light artifact. colour-dodge blows bright hues to
        // white, so for rainbow we KEEP saturation cranked and AVOID lightening
        // (low/no brightness lift, lower multiply) so the dodge preserves colour
        // instead of washing it out.
        .colorMultiply(Color(white: mode == .rainbow ? 0.8 : 0.55))
        .contrast(mode == .rainbow ? 1.5 : 1.5)
        .brightness(mode == .rainbow ? 0.0 : 0.0)
        .saturation(mode == .rainbow ? 3.0 : 1.0)
        .frame(width: w * 2, height: h * 2)
    }

    /// Foil heightmap as an alpha mask, shared by the rainbow hue and the
    /// light/dark sweep. The etch's luminance (bright cells -> visible, dark
    /// valleys -> hidden) is remapped by the `reverseHoloMask` tone curve so it
    /// reads like real holographic paper: transparent at max dark AND max
    /// bright, most visible in the bright mid-tones, quick falloff at the top.
    /// So both the hue AND the moving ray/radial only touch the texture's lit
    /// cells — the dark cells stay untouched (card shows through).
    @ViewBuilder
    private func foilLuminanceMask(period: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        if settings.reverseTextureMode != .generated,
           let p = settings.reverseTexturePattern,
           let m = HoloPatternStore.shared.tiledAlphaMask(for: p, size: NSSize(width: w * 2, height: h * 2), scale: settings.reverseTextureScale) {
            Image(nsImage: m)
                .resizable()
                .frame(width: w * 2, height: h * 2)
                .colorEffect(Shader(function: ShaderLibrary.reverseHoloMask, arguments: []))
        } else {
            ZStack {
                RepeatingLinearGradientView(colors: [.white, .clear], angle: 45, period: period)
                RepeatingLinearGradientView(colors: [.white, .clear], angle: -45, period: period)
                    .blendMode(.multiply)
            }
            .frame(width: w * 2, height: h * 2)
            .colorEffect(Shader(function: ShaderLibrary.reverseHoloMask, arguments: []))
        }
    }

    /// Rainbow hue for Reverse Holo: a smooth spectrum gated by the FOIL's
    /// luminance (the heightmap). Dark foil areas get ZERO hue; bright areas get
    /// hue whose intensity scales with the foil's brightness (lighter = more
    /// intense). Returned as a layer to be composited *inside* the foil so the
    /// moving `difference` ray in `reverseShine` sweeps/inverts it like the
    /// source does to the textured foil.
    @ViewBuilder
    private func rainbowHue(period: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let spectrum = LinearGradient(
            colors: [HoloCSSColors.violet, HoloCSSColors.blue, HoloCSSColors.green,
                     HoloCSSColors.yellow, HoloCSSColors.red, HoloCSSColors.violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // Heightmap mask: the etch's luminance (alpha) when a bundled texture is
        // used, otherwise the generated lattice's bright diamonds. Both give
        // transparent darks -> no hue, opaque/alpha brights -> hue.
        spectrum
            .blendMode(.screen)
            .opacity(settings.reverseRainbowIntensity)
            .mask(foilLuminanceMask(period: period, w: w, h: h))
            .frame(width: w * 2, height: h * 2)
    }

    /// Generated foil etch: a fine diamond lattice (two crossed repeating
    /// gradients multiplied). The foil is alpha-masked by its own luminance
    /// so the etched pattern's dark valleys fade to transparent and only the
    /// bright cells remain visible — proportional to luminance, not a binary
    /// gate. This is what makes the reverse holo read as a metallic lattice
    /// instead of a dark mesh printed on the card. The hue / tint / colour
    /// character is layered on top of this luminance-masked shape.
    ///   • `Rainbow` and `Random` only show the hue (added in `rainbowHue`),
    ///     already gated by the same luminance mask.
    ///   • `Background` keeps the lattice greyscale.
    ///   • `Solid` tints the lattice to the chosen colour.
    @ViewBuilder
    private func reverseFoil(period: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let mode = settings.reverseColorMode

        // When a bundled etch is selected (`.random` picks one per card), it
        // becomes the foil — the source repo's `var(--foil)`. Variation (when
        // on) tiles it at a random scale (0.1…1.0×) and may layer a second etch
        // on top with a random blend, for a richer reverse-holo look. `.solid`
        // still tints it to the chosen colour.
        let forceLattice = settings.reverseTextureMode == .generated || settings.reverseTexturePattern == nil

        if !forceLattice,
           let p1 = settings.reverseTexturePattern,
           let img1 = HoloPatternStore.shared.tiledImage(for: p1, size: NSSize(width: w * 2, height: h * 2), scale: settings.reverseTextureScale) {
            if mode == .rainbow {
                // Rainbow: show ONLY the luminance-gated hue. The dark etch
                // areas (no hue) become fully transparent so the card art shows
                // through — there is no metallic base to go dark/light. Bright
                // texture areas light up in the rainbow hue, exactly as wanted.
                rainbowHue(period: period, w: w, h: h)
            } else {
                ZStack {
                    Image(nsImage: img1)
                        .resizable()
                        .frame(width: w * 2, height: h * 2)
                        .blendMode(.normal)
                    if let p2 = settings.reverseTexturePattern2,
                       let img2 = HoloPatternStore.shared.tiledImage(for: p2, size: NSSize(width: w * 2, height: h * 2), scale: settings.reverseTextureScale2) {
                        Image(nsImage: img2)
                            .resizable()
                            .frame(width: w * 2, height: h * 2)
                            .blendMode(settings.reverseTextureBlend2.blendMode)
                    }
                }
                .frame(width: w * 2, height: h * 2)
                // Mask the foil by its own luminance so dark cells fade to
                // transparent (linear, proportional). Before this the dark
                // valleys of the foil survived the contrast/dodge pass as
                // near-opaque black, which read as a black mesh instead of a
                // metallic holo pattern.
                .mask(foilLuminanceMask(period: period, w: w, h: h))
                .colorMultiply(mode == .solid ? settings.reverseSolidColor : Color.white)
            }
        } else {
            // Built-in generated diamond lattice (default Reverse Holo foil).
            switch mode {
            case .rainbow:
                // Rainbow: only the hue, gated by the lattice heightmap (dark
                // gaps -> transparent, so the card art shows through; no
                // rainbow-coloured diagonals, just a hue on the bright metal).
                rainbowHue(period: period, w: w, h: h)
            case .random:
                // Random per-card hue: same heightmap-gated rainbow as `.rainbow`;
                // the per-card hue variation is applied via the outer hueRotation.
                rainbowHue(period: period, w: w, h: h)
            case .background:
                // Greyscale metallic lattice. The two crossed gradients use
                // `[.white, .clear]` so the gaps are already alpha 0, and the
                // whole stack is then masked by its own luminance (proportional
                // to luminance) so the transition from bright cells to dark
                // gaps is smooth instead of a hard line.
                ZStack {
                    RepeatingLinearGradientView(colors: [.white, .clear], angle: 45, period: period)
                    RepeatingLinearGradientView(colors: [.white, .clear], angle: -45, period: period)
                        .blendMode(.multiply)
                }
                .frame(width: w * 2, height: h * 2)
                .mask(foilLuminanceMask(period: period, w: w, h: h))
            case .solid:
                ZStack {
                    RepeatingLinearGradientView(colors: [.white, .clear], angle: 45, period: period)
                    RepeatingLinearGradientView(colors: [.white, .clear], angle: -45, period: period)
                        .blendMode(.multiply)
                }
                .frame(width: w * 2, height: h * 2)
                .mask(foilLuminanceMask(period: period, w: w, h: h))
                .colorMultiply(settings.reverseSolidColor)
            }
        }
    }

    // MARK: - Holofoil Rare (faithful to simeydotme regular-holo.css)
    //
    // Source `.card__shine` (rare holo) is layered gradients that slide with
    // the cursor via `background-position`, then colour-dodged:
    //   • rainbow   repeating-linear-gradient(110deg, violet…red)  — the holo
    //   • scanlines repeating-linear-gradient(90deg, dark/light)  — overlay
    //   • bars (:before)  two 90° black/grey bar gradients -> screen, then the
    //     whole element `hard-light`s onto the base (the "vertical beam")
    //   • radial (:after)  cursor-centred radial -> luminosity
    //   filter: brightness(1.1) contrast(1.1) saturate(1.2)
    //   mix-blend-mode: color-dodge onto the art
    // The cursor reactivity is the sliding `background-position` (we offset the
    // rainbow + bar layers), exactly as the source rotates the effect while
    // tilting the card. Built LIVE (not a baked tile) so it tracks the cursor,
    // MARK: - Radiant Holofoil (radiant-holo.css)
    //
    // Source `.card__shine` = a cursor-centred radial glow + a CRISS-CROSS of
    // fine diagonal grayscale bars (45° and −45°) whose luminance ramps
    // dark→light→dark, giving the "starburst" texture; `.card__shine:after`
    // layers a 55° spectral rainbow (hard-lighted) on top. Both are
    // `color-dodge`d onto the art. `.card__shine:before` / `.card__glare`
    // add the cursor glow (overlay / hard-light) — handled by `radiantGlare`.






    // Rainbow Rare foil textures, bundled in `Resources/HoloPatterns/`.
    private static var holoPatternCache: [String: NSImage] = [:]
    private static func holoPatternTexture(_ name: String) -> NSImage? {
        if let cached = holoPatternCache[name] { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let img = NSImage(contentsOfFile: path) else { return nil }
        holoPatternCache[name] = img
        return img
    }

    /// Radiant glare — `.card__shine:before` (glitter + cursor radial,
    /// `overlay`) and `.card__glare` (cursor radial, `hard-light`). Kept
    /// outside the colour-dodge group so each keeps its own blend.
    @ViewBuilder
    private func radiantGlare(w: CGFloat, h: CGFloat) -> some View {
        // Web `.card[data-rarity="radiant rare"] .card__glare`: a cursor-centred
        // white radial, `hard-light`. (The grey `:before` glitter radial lives in
        // `radiantShine`, not here — duplicating it here veiled the whole card.)
        RadialGradient(
            stops: [
                Gradient.Stop(color: Color.white.opacity(0.33), location: 0.0),
                Gradient.Stop(color: Color.white.opacity(0.33), location: 0.25),
                Gradient.Stop(color: Color(white: 0.0).opacity(0.0), location: 1.10),
            ],
            center: UnitPoint(x: pointerX, y: pointerY),
            startRadius: 0,
            endRadius: max(w, h) * 0.9
        )
        .blendMode(.hardLight)
        .frame(width: w * 2, height: h * 2)
    }

    // mirroring how `reverseShine` is done.
    @ViewBuilder
    private func regularHoloShine(w: CGFloat, h: CGFloat) -> some View {
        // Full spectral loop (red→…→red) so the rainbow reads as a smooth,
        // vivid spectrum across the card. High saturation is what makes it
        // "huge and beautiful" once multiplied onto bright card art.
        // Web `.card[data-rarity="rare holo"] .card__shine` — faithfully mirrored.
        // Source rainbow stops (3 loops of 5 hues), 110deg.
        let red    = Color(red: 0.972, green: 0.055, blue: 0.208)
        let yellow = Color(red: 0.933, green: 0.875, blue: 0.063)
        let green  = Color(red: 0.129, green: 0.914, blue: 0.522)
        let blue   = Color(red: 0.051, green: 0.741, blue: 0.914)
        let violet = Color(red: 0.788, green: 0.161, blue: 0.945)
        let rainbowColors: [Color] = [violet, blue, green, yellow, red]

        // Source `background-size: 400% 400%` with a 15-stop (3-loop) repeating
        // gradient ⇒ one full 5-hue loop spans ≈ 1.33 card widths.
        let rainbowPeriod = w * 1.33
        // Source `background-position`: ((50% - x) * 2.6) + 50% , ((50% - y) * 3.5) + 50%.
        let rainbowOffset = CGSize(
            width: (0.5 - pointerX) * w * 2.6,
            height: (0.5 - pointerY) * h * 3.5
        )

        // Scanlines (`--scanlines-space: 1px` ⇒ 2px dark / 2px light, 90deg).
        let scanlinePeriod = max(2.0, (w * 0.013) / max(0.05, settings.holofoilRareScanlineDensity))

        // Beam bars (`--bars: 3%`, `--bar-color: hsl(0,0%,70%)`, `--bar-bg: black`).
        let barColor = Color(white: 0.70)
        let barBg = Color.black
        let i = settings.holofoilRareIntensity
        let over = max(0.0, i - 1.0)

        ZStack {
            // Base `.card__shine`: rainbow + scanlines, `background-blend-mode: overlay`.
            ZStack {
                RepeatingLinearGradientView(colors: rainbowColors, angle: 110, period: rainbowPeriod)
                    .frame(width: w * 4, height: h * 4)
                    .offset(rainbowOffset)
                    // Colour-dodge of a full-brightness rainbow onto bright art
                    // blows out to white, so the rainbow itself must be dimmed
                    // (hue/saturation preserved) before the dodge. This is the
                    // main lever that keeps Holofoil Rare a vivid shimmer instead
                    // of a burned wash.
                    .brightness(0.5)
                RepeatingLinearGradientView(
                    colors: [barBg, barColor],
                    angle: 90, period: scanlinePeriod
                )
                .frame(width: w * 4, height: h * 4)
                .blendMode(.overlay)
            }
            // Source `filter: brightness(1.1) contrast(1.1) saturate(1.2)`, but the
            // rainbow is already dimmed (see above) before the colour-dodge, so we
            // keep the element filter mild to avoid re-blowing it out.
            .brightness(0.95)
            .contrast(1.0)
            .saturation(1.05 + over * 0.3)

            // `:before` — two vertical beam bars, `background-blend-mode: screen`,
            // `mix-blend-mode: hard-light`.
            ZStack {
                RepeatingLinearGradientView(colors: [barBg, barColor], angle: 90, period: w * 0.06)
                    .frame(width: w * 2, height: h * 2)
                    .offset(x: (0.5 - pointerX) * w * 1.65 + pointerY * h * 0.5, y: 0)
                RepeatingLinearGradientView(colors: [barBg, barColor], angle: 90, period: w * 0.06)
                    .frame(width: w * 2, height: h * 2)
                    .offset(x: (0.5 - pointerX) * -w * 0.9 - pointerY * h * 0.75, y: 0)
                    .blendMode(.screen)
            }
            .brightness(1.15)
            .contrast(1.1)
            .blendMode(.hardLight)

            // `:after` — cursor radial, `mix-blend-mode: luminosity`,
            // `filter: brightness(0.6) contrast(4)`. Confines the rainbow to the
            // cursor, exactly like the web (omitting it washed the whole card in
            // flat rainbow, which is why it never matched).
            RadialGradient(
                stops: [
                    .init(color: Color(white: 0.90).opacity(0.55), location: 0.0),
                    .init(color: Color(white: 0.78).opacity(0.08), location: 0.25),
                    .init(color: Color(white: 0.0).opacity(1.0), location: 0.90)
                ],
                center: UnitPoint(x: pointerX, y: pointerY),
                startRadius: 0,
                endRadius: sqrt(w * w + h * h) * 0.9
            )
            .frame(width: w, height: h)
            .brightness(0.4)
            .contrast(1.5)
            .blendMode(.luminosity)
        }
        // User master intensity (alpha capped at 1; >1 overdrives saturation).
        .opacity(min(1.0, i))
        .frame(width: w * 2, height: h * 2)
    }

    // MARK: - Holofoil Rare glare (.card__glare)
    //
    // Source `.card__glare` (regular-holo.css): `opacity: card-opacity * .8`,
    // `filter: brightness(.8) contrast(1.5)`, `mix-blend-mode: overlay`. The
    // visible highlight is `.card__glare:after` — a cursor-centred cyan-white
    // radial (`hsl(180,100%,95%)` 5% → `hsla(0,0%,39%,.25)` 55% →
    // `hsla(0,0%,0%,.36)` 110%), `overlay`-blended with `filter: brightness(.6)
    // contrast(3)`. Rendered as a SEPARATE sibling of the colour-dodged foil
    // (not inside it) so it keeps its own overlay blend — exactly like the
    // source's two distinct elements.
    @ViewBuilder
    private func regularHoloGlare(w: CGFloat, h: CGFloat) -> some View {
        // Source `.card__glare:after` is a cursor-centred cyan-white radial that
        // reads as a moving spotlight. The source fades it to a dark outer
        // (`hsla(0,0%,0%,.36)`) for contrast, but that DARKENS the card — and
        // since the glare tracks the cursor, reaching a card edge puts the whole
        // card inside that dark outer. The user's rule: the holo must never
        // darken the image by more than ~10%. So we fade the glare to
        // TRANSPARENT instead of black — it only ever *lightens* the art,
        // giving the bright sweeping highlight without any darkening.
        RadialGradient(
            stops: [
                Gradient.Stop(color: Color(hue: 0.5, saturation: 1.0, brightness: 0.8, opacity: 0.55), location: 0.0),
                Gradient.Stop(color: Color(hue: 0.5, saturation: 0.5, brightness: 0.8, opacity: 0.18), location: 0.45),
                Gradient.Stop(color: Color(hue: 0.5, saturation: 0.0, brightness: 0.7, opacity: 0.0), location: 1.0),
            ],
            center: UnitPoint(x: pointerX, y: pointerY),
            startRadius: 0,
            endRadius: max(w, h) * 0.95
        )
        .blendMode(.overlay)
        .frame(width: w * 2, height: h * 2)
        // Source `.card__glare` opacity `card-opacity * .8`, scaled by the
        // user's glare setting. No darkening filters applied. The 0.8 multiplier
        // is dropped to 0.45 because the full-strength cyan glare read as a
        // blown-out white circle on bright art.
        .opacity(settings.holofoilRareGlare * 0.45)
    }

    /// Rainbow Rare shine — faithful to `rare-rainbow.css`:
    ///   base `.card__shine`: linear(-45deg) 2-col gradient (bottom) +
    ///     glitter texture (`luminosity`) + linear(-30deg) 7-col rainbow
    ///     (`soft-light`); `filter: brightness contrast saturate`; colour-dodged
    ///     onto the card at the layer level.
    ///   `:before`: illusion-mask foil, `mix-blend-mode: darken`.
    ///   `:after`:  glitter + 7-col rainbow(-60deg), `soft-light`, `colour-dodge`.
    @ViewBuilder
    private func rainbowHoloShine(w: CGFloat, h: CGFloat) -> some View {
        // Source rainbow stops (r-clr-1 … r-clr-7). The web uses low lightness
        // (~0.35) but its `brightness()` is multiplicative, so the hues survive
        // the color-dodge. SwiftUI's additive `.brightness()` would crush these
        // to black, so we lift the lightness here and darken multiplicatively
        // (via `colorMultiply`) instead — keeping the rainbow visible.
        let r1 = Color(hue: 0.000, saturation: 0.57, brightness: 0.62)
        let r2 = Color(hue: 0.111, saturation: 0.53, brightness: 0.64)
        let r3 = Color(hue: 0.250, saturation: 0.60, brightness: 0.60)
        let r4 = Color(hue: 0.500, saturation: 0.60, brightness: 0.60)
        let r5 = Color(hue: 0.500, saturation: 0.60, brightness: 0.60)
        let r6 = Color(hue: 0.583, saturation: 0.57, brightness: 0.64)
        let r7 = Color(hue: 0.778, saturation: 0.55, brightness: 0.56)
        let rainbowColors: [Color] = [r1, r2, r3, r4, r5, r6, r7]

        let pfc = pointerFromCenter
        let glitter = Self.holoPatternTexture("holo_glitter")
        let foil = Self.holoPatternTexture("holo_illusion-mask")

        let rainbowPeriod = w * 1.27
        // Source `background-position` for the -30deg rainbow:
        //   calc(25% + (pointer-x / 2)), calc(25% + (pointer-y / 2)).
        let rainbowOffset = CGSize(
            width: (0.25 + pointerX * 0.5 - 0.5) * w * 2,
            height: (0.25 + pointerY * 0.5 - 0.5) * h * 2
        )
        // Source `background-position` for the -45deg gradient:
        //   calc(25% + 50%*fromLeft), calc(25% + 50%*fromTop).
        let grad45Offset = CGSize(
            width: (pointerX - 0.5) * w,
            height: (pointerY - 0.5) * h
        )

        ZStack {
            // Base `.card__shine`.
            ZStack {
                // bg1: -45deg 2-col gradient (bottom layer; normal blend).
                RepeatingLinearGradientView(colors: [r1, r5], angle: -45, period: w * 2)
                    .frame(width: w * 4, height: h * 4)
                    .offset(grad45Offset)
                // bg2: glitter, `luminosity` onto bg1.
                if let glitter {
                    Image(nsImage: glitter)
                        .resizable(resizingMode: .tile)
                        .frame(width: w * 4, height: h * 4)
                        .blendMode(.luminosity)
                }
                // bg3: -30deg 7-col rainbow, `soft-light` onto the result.
                RepeatingLinearGradientView(colors: rainbowColors, angle: -30, period: rainbowPeriod)
                    .frame(width: w * 4, height: h * 4)
                    .offset(rainbowOffset)
                    .blendMode(.softLight)
            }
            // CSS `brightness(N)` is multiplicative, so use `colorMultiply` (not
            // additive `.brightness()`, which would crush the rainbow to black).
            .colorMultiply(Color(white: 0.8 + pfc * 0.2))
            .contrast(1.6)
            .saturation(1.15)

            // `:before`: illusion-mask foil, `mix-blend-mode: darken`.
            if let foil {
                Image(nsImage: foil)
                    .resizable()
                    .frame(width: w * 2, height: h * 2)
                    .brightness(0.3)
                    .opacity((pfc + 0.4) * 0.6)
                    .blendMode(.darken)
            }

            // `:after`: glitter + 7-col rainbow(-60deg), `soft-light`, `colour-dodge`.
            ZStack {
                if let glitter {
                    Image(nsImage: glitter)
                        .resizable(resizingMode: .tile)
                        .frame(width: w * 2, height: h * 2)
                }
                RepeatingLinearGradientView(colors: rainbowColors, angle: -60, period: rainbowPeriod)
                    .frame(width: w * 2, height: h * 2)
                    .blendMode(.softLight)
            }
            .colorMultiply(Color(white: 0.75 + pfc * 0.25))
            .contrast(1.8)
            .saturation(1.2)
            .blendMode(.colorDodge)
        }
        .frame(width: w * 2, height: h * 2)
    }

    /// Rainbow Rare glare — `.card[data-rarity="rare rainbow"] .card__glare`:
    /// cursor radial, `mix-blend-mode: hard-light`, `filter: brightness(.9)
    /// contrast(1.75)`, `opacity: var(--pointer-from-center) * 0.9`.
    private func rainbowHoloGlare(w: CGFloat, h: CGFloat) -> some View {
        RadialGradient(
            stops: [
                .init(color: Color(white: 0.80), location: 0.0),
                .init(color: Color(hue: 0.519, saturation: 0.10, brightness: 0.85, opacity: 0.25), location: 0.30),
                .init(color: Color(hue: 0.547, saturation: 0.06, brightness: 0.25), location: 1.0),
            ],
            center: UnitPoint(x: pointerX, y: pointerY),
            startRadius: 0,
            endRadius: max(w, h) * 1.2
        )
        .brightness(-0.1)
        .contrast(1.75)
        .opacity(pointerFromCenter * 0.9)
    }

    /// Bump layer — Metal-rendered. Synthesizes a mask-only base image
    /// (because the host paints the masked artwork underneath us; the bump
    /// shader needs the masked art as input texture) and renders the bump
    /// shader into a SwiftUI Image. Falls back to a transparent image if
    /// Metal isn't available or the shader fails to build (the parallax
    /// layer still shows through if mode == .both).
    @ViewBuilder
    private func tileRegionLayer<Content: View>(intensity: Double, mask: NSImage, w: CGFloat, h: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        Group {
            content()
        }
        .frame(width: w * 2, height: h * 2)
        .frame(width: w, height: h, alignment: .center)
        .clipped()
        .mask(maskView(mask, w: w, h: h))
        .opacity(intensity)
    }

    /// Bump layer — Metal-rendered, but crucially the expensive GPU pass +
    /// CPU readback runs OFF the main thread (see `HoloBumpRenderer.renderBump`
    /// and its serial `renderQueue`). This view only re-requests a render when
    /// the *bucketed* inputs actually change (via `signature`), so a fast
    /// cursor swipe triggers at most a handful of renders and the UI thread
    /// is never blocked. The displayed image starts empty (transparent →
    /// color-dodge leaves the art untouched) and fills in once the first
    /// render completes.
    @MainActor
    @ViewBuilder
    private func bumpLayer(pattern: HoloPattern, variant: HoloVariant?, mask: NSImage, textureTile: NSImage?, w: CGFloat, h: CGFloat, intensity: Double) -> some View {
        // Feed the actual holographic foil tile (rainbow + grating) to the
        // bump renderer — the shader derives both the relief and the colour
        // from this texture, so the embossed foil matches what parallax shows.
        let foilKey = "\(pattern.rawValue)|\(variant?.rawValue ?? "default")"
        HoloBumpImageView(
            foilImage: textureTile,
            foilKey: foilKey,
            w: w, h: h,
            intensity: intensity,
            pointerX: pointerX,
            pointerY: pointerY,
            tiltX: tiltX,
            tiltY: tiltY,
            specularPower: settings.specularPower,
            cursorInfluence: settings.cursorInfluence,
            tiltInfluence: settings.tiltInfluence,
            hueCycles: settings.hueCycles
        )
    }
}

/// Displays the Metal bump foil without blocking the UI. The expensive GPU
/// pass + CPU readback run off the main thread (see `HoloBumpRenderer`), and
/// this view only re-requests a render when the *bucketed* inputs change (via
/// `signature`), so a fast cursor swipe triggers at most a handful of renders.
/// The displayed image starts empty (transparent → color-dodge leaves the art
/// untouched) and fills in once the first render completes.
@MainActor
private struct HoloBumpImageView: View {
    let foilImage: NSImage?
    let foilKey: String
    let w: CGFloat
    let h: CGFloat
    let intensity: Double
    let pointerX: CGFloat
    let pointerY: CGFloat
    let tiltX: Double
    let tiltY: Double
    let specularPower: Double
    let cursorInfluence: Double
    let tiltInfluence: Double
    let hueCycles: Double

    @State private var renderedImage: NSImage?
    @State private var lastSig: String = ""

    private var signature: String {
        "\(pointerX.coarseBucketed)|\(pointerY.coarseBucketed)|" +
        "\(tiltX.coarseBucketed)|\(tiltY.coarseBucketed)|" +
        "\(specularPower.bucketed)|\(intensity.bucketed)|" +
        "\(cursorInfluence.bucketed)|\(tiltInfluence.bucketed)"
    }

    var body: some View {
        Group {
            if let renderedImage {
                Image(nsImage: renderedImage)
                    .resizable()
                    .frame(width: w * 2, height: h * 2)
                    .allowsHitTesting(false)
            }
        }
        // The bump pass runs asynchronously off the main thread, so the first
        // valid image arrives a frame or two after the layer appears. Fade it
        // in (rather than hard-popping) so the first rendered frame — which is
        // computed at the cursor's hover-entry position and can look briefly
        // over-bright/warped — eases in instead of snapping the whole card.
        .opacity(renderedImage != nil ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: renderedImage != nil)
        .onAppear { trigger() }
        .onChange(of: signature) { _, _ in trigger() }
    }

    private func trigger() {
        let sig = signature
        guard sig != lastSig, let foilImage else {
            lastSig = sig
            return
        }
        lastSig = sig
        HoloBumpRenderer.shared.renderBump(
            foilNSImage: foilImage,
            foilKey: foilKey,
            size: NSSize(width: max(1, w * 2), height: max(1, h * 2)),
            cursorX: pointerX,
            cursorY: pointerY,
            tiltX: tiltX,
            tiltY: tiltY,
            specularPower: specularPower,
            intensity: intensity,
            hueShiftDegrees: Double((pointerX - 0.5) * hueCycles * 360 + (pointerY - 0.5) * hueCycles * 360),
            saturation: 0.65,
            cursorInfluence: cursorInfluence,
            tiltInfluence: tiltInfluence
        ) { [self] img in
            Task { @MainActor in self.renderedImage = img }
        }
    }
}

// The "light" the user can shine on the card by hovering — a small spotlight
// that tracks the cursor and lifts the foil underneath it. Kept deliberately
// small and neutral: a full-card radial with a boosted cyan core (the
// source's `:after` glow) read as a cyan wash over the whole box art and hid
// the region-masked foil, which is the actual effect.
struct HoloSheenEffect: View {
    let pointerX: CGFloat
    let pointerY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // A tight spotlight, roughly a third of the card's smaller
            // dimension. The bright core itself is well within that.
            let radius = min(w, h) * 0.30

            ZStack {
                // Soft white glow that follows the pointer, lightening the
                // foil below it. Dies off quickly so only a small patch
                // under the cursor highlights.
                RadialGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.50), location: 0.0),
                        .init(color: Color.white.opacity(0.25), location: 0.35),
                        .init(color: Color.white.opacity(0.0),  location: 0.7)
                    ],
                    center: UnitPoint(x: pointerX, y: pointerY),
                    startRadius: 0,
                    endRadius: radius
                )
                .frame(width: w, height: h)
                .blendMode(.screen)

                // Subtle dark falloff around the spotlight for the "point of
                // light" feel. Overlay blend so it only affects mid-tones.
                RadialGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.0),  location: 0.0),
                        .init(color: Color.black.opacity(0.0),  location: 0.5),
                        .init(color: Color.black.opacity(0.22), location: 1.0)
                    ],
                    center: UnitPoint(x: pointerX, y: pointerY),
                    startRadius: 0,
                    endRadius: radius * 1.6
                )
                .frame(width: w, height: h)
                .blendMode(.overlay)
            }
        }
    }
}

// MARK: - Holo Scratch / Sparkle Layer

// Re-implements the pokemon-cards-css "sparkle" overlay: a faint scratch-band
// texture (bundled `holo_illusion-mask.png`) drawn over the whole card with a
// thin white band pattern. Both the band and the texture stay fixed in place
// — same reasoning as `patternLayer`: translating them against a
// non-tilting card looked like the holo was sliding on top of the art.
//
// Opacity is intentionally low (~0.08). It works whether or not the
// decomposer cleanly peeled the box art, giving the card a non-rainbow
// source of foil texture that doesn't depend on region masks.
struct HoloScratchLayer: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        Group {
            if let scratch = HoloPatternStore.shared.scratchMask() {
                RepeatingLinearGradientView(
                    colors: [
                        Color.white.opacity(0.30),
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.30)
                    ],
                    angle: 90,
                    period: h * 0.5,
                    centerOffset: .zero
                )
                .mask(
                    Image(nsImage: scratch)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                )
                .blendMode(.screen)
                .opacity(0.08)
            }
        }
    }
}

// MARK: - Simple RNG for glitter

struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    init(seed: UInt32) {
        self.init(seed: UInt64(seed))
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return z
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

// MARK: - Swift-engine cache coordinator

// Mirrors the WebView pool's idle-flush behaviour for the *native* Swift holo
// engine (HoloFoilTileCache, HoloBumpRenderer, HoloPatternStore). Those caches
// are bounded singletons, but unlike the WebView pool they otherwise hold their
// warmed contents for the app's lifetime — the foil tiles alone can reach
// hundreds of MB. This drops them after a short idle window so peak memory
// returns to near-zero when the user isn't hovering holo cards.
final class HoloSwiftCacheCoordinator {
    static let shared = HoloSwiftCacheCoordinator()

    private let lock = OSAllocatedUnfairLock<Date>(initialState: .distantPast)
    private var timer: DispatchSourceTimer?
    private let checkInterval: TimeInterval = 5
    private let idleThreshold: TimeInterval = 8

    private init() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + checkInterval, repeating: checkInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    // Called from the Swift-engine render hot paths (HoloFoilTileCache.tile and
    // HoloBumpRenderer.render) so the "last active" timestamp stays fresh while
    // a card is hovered — preventing a flush mid-hover.
    func noteUsage() {
        lock.withLock { $0 = Date() }
    }

    private func tick() {
        guard Date().timeIntervalSince(lock.withLock { $0 }) >= idleThreshold else { return }
        flushAll()
    }

    // Reclaim every Swift-engine cache. Safe to call from the main thread (the
    // idle timer and the game-launch hook both run there).
    func flushAll() {
        MainActor.assumeIsolated {
            HoloFoilTileCache.shared.flush()
            HoloPatternStore.shared.flush()
        }
        HoloBumpRenderer.shared.flush()
        // Largest native-engine footprint: full-res region mask NSImages.
        HoloSaliencyService.shared.flush()
    }
}
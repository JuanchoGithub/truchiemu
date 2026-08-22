import SwiftUI

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
        let bw = Int((w * 2).rounded())
        let bh = Int((h * 2).rounded())
        guard bw > 0, bh > 0 else { return nil }
        let key = TileKey(pattern: pattern, variantKey: variant?.rawValue ?? "default", width: bw, height: bh)
        if let cached = tiles[key] { return cached }

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

        let content = ZStack {
            RepeatingLinearGradientView(
                colors: paletteColors,
                angle: 110,
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
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(bw), height: CGFloat(bh)))
        tiles[key] = img
        return img
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

    var body: some View {
        ZStack {
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
                } else {
                    // User-configured path: region-specific patterns /
                    // intensities from the settings store. No variant roll —
                    // the texture alone provides the holographic look.
                    let fallbackBoost = fallbackBoost(for: masks)
                    let bgIntensity = max(0, min(1, settings.backgroundIntensity + fallbackBoost))
                    if let background = masks.background {
                        regionLayer(resolvedPattern(for: .background),
                                    variant: nil,
                                    intensity: bgIntensity,
                                    mask: background, w: w, h: h)
                    }
                    if settings.regionIsActive(.title, maskPresent: masks.title != nil),
                       let title = masks.title {
                        regionLayer(resolvedPattern(for: .title),
                                    variant: nil,
                                    intensity: settings.titleIntensity,
                                    mask: title, w: w, h: h)
                    }
                    if settings.regionIsActive(.chrome, maskPresent: masks.chrome != nil),
                       let chrome = masks.chrome {
                        regionLayer(resolvedPattern(for: .chrome),
                                    variant: nil,
                                    intensity: settings.chromeIntensity,
                                    mask: chrome, w: w, h: h)
                    }
                    if masks.heroHolo,
                       settings.regionIsActive(.hero, maskPresent: masks.hero != nil),
                       let hero = masks.hero {
                        regionLayer(resolvedPattern(for: .hero),
                                    variant: nil,
                                    intensity: settings.heroIntensity,
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
        .offset(parallaxOffset)
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
        .contrast(2.75)
        .saturation(0.65)
        // Pointer-from-center modulation — source's
        // `filter: brightness(calc((--pointer-from-center*0.25) + 0.6))`.
        // At cursor-center pfc=0 → brightness ~-0.4 (rainbow near-black,
        // invisible under colorDodge, texture pattern not visible at
        // rest-on-hover). As cursor moves pfc → 1 → brightness lifts to
        // ~-0.15 (rainbow bright bands become visible through the
        // texture). This is the "holographic textures only become visible
        // when they change color/get brighter" behavior — at rest the
        // foil is near-invisible, only the cursor-driven hueRotation +
        // sweep + brightness lift reveal it as the user explores the card.
        .brightness(-0.4 + pointerFromCenter * 0.25)
        // color-dodge = the holo "blowout" — source's `mix-blend-mode:
        // color-dodge` on `.card__shine`. Applied after `compositingGroup`
        // so the masking clustered region stack is flattened first.
        // colorDodge of transparent/black texture areas leaves the art
        // unchanged; colorDodge of the bright rainbow AT the texture's
        // bright pixels LIGHTENS the art holographically. The card never
        // darkens — colorDodge only adds light.
        .blendMode(.colorDodge)
        // Angular hue shift: rotate the whole rainbow as the cursor moves —
        // ±60° over the card horizontally and ±60° vertically (both axes
        // contribute, so moving up/down shifts hue just like left/right).
        // Pure GPU color filter on the pre-rendered tiles — no re-render per
        // cursor event.
        .hueRotation(.degrees((pointerX - 0.5) * 120 + (pointerY - 0.5) * 120))
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
    private var parallaxOffset: CGSize {
        // Hard-disabled when bump-only is requested: the bump shader has its
        // own light-direction math, parallax shear would double-up.
        let mode = settings.depthMode
        let strength = settings.parallaxStrength
        guard mode != .bump, strength > 0.001 else { return .zero }
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

    @inline(__always)
    private func fallbackBoost(for masks: HoloMaskSet) -> Double {
        var boost: Double = 0
        if masks.title == nil, settings.titleIntensity > 0    { boost += settings.titleIntensity * 0.5    }
        if masks.chrome == nil, settings.chromeIntensity > 0   { boost += settings.chromeIntensity * 0.5   }
        if masks.heroHolo, masks.hero == nil, settings.heroIntensity > 0 {
            boost += settings.heroIntensity * 0.5
        }
        return boost
    }

    @inline(__always)
    private func resolvedPattern(for region: HoloRegion) -> HoloPattern {
        switch region {
        case .title:      return settings.titlePattern
        case .chrome:     return settings.chromePattern
        case .hero:       return settings.heroPattern
        case .background: return settings.backgroundPattern
        }
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
    ///   1. **Texture-masked rainbow tile** (`HoloFoilTileCache.tile`) —
    ///      rainbow gradient masked by the texture PNG. Bright PNG pixels
    ///      = opaque rainbow visible there; dark pixels = transparent (art
    ///      shows through). Scanlines blended on top via `.overlay` inside
    ///      the tile. When `variant` is set, its first shine-layer palette
    ///      replaces the default `violet/blue/.../red` rainbow — this is
    ///      the per-card variation: a pure COLOUR swap of the same
    ///      texture-gated payoff, not a separate layer (no rainbow drawn
    ///      outside the texture).
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
        let textureTile = HoloFoilTileCache.shared.tile(for: pattern, variant: variant, w: w, h: h)
        let bandWidth = w * 0.5
        ZStack {
            // Bump path (mode == .bump or .both): a Metal-rendered image
            // that combines the masked base art + the procedurally-derived
            // normal map + a synthesized rainbow via the HoloBump shader.
            // When mode is .parallax this layer is invisible (no renderer
            // call) and the parallax stack takes over.
            if settings.depthMode != .parallax, isHovered {
                bumpLayer(pattern: pattern, variant: variant, mask: mask, textureTile: textureTile, w: w, h: h, intensity: intensity)
            }
            if settings.depthMode != .bump {
                parallaxLayer(pattern: pattern, variant: variant, intensity: intensity, mask: mask, w: w, h: h, textureTile: textureTile, bandWidth: bandWidth)
            }
        }
        .frame(width: w * 2, height: h * 2)
        .frame(width: w, height: h, alignment: .center)
        .clipped()
        .mask(maskView(mask, w: w, h: h))
        .opacity(intensity)
    }

    /// Parallax illusion layer — the existing source-faithful rainbow tile
    /// + sweep band. Rendered when `depthMode != .bump` (so it's shown in
    /// `.parallax` and `.both` modes).
    @ViewBuilder
    private func parallaxLayer(pattern: HoloPattern, variant: HoloVariant?, intensity: Double, mask: NSImage, w: CGFloat, h: CGFloat, textureTile: NSImage?, bandWidth: CGFloat) -> some View {
        if let tile = textureTile {
            Image(nsImage: tile)
                .resizable()
                .frame(width: w * 2, height: h * 2)
        }
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.7),
                Color.white.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth, height: h * 2)
        .offset(x: (pointerX - 0.5) * w * 2)
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
            tiltInfluence: settings.tiltInfluence
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
            hueShiftDegrees: Double((pointerX - 0.5) * 120 + (pointerY - 0.5) * 120),
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
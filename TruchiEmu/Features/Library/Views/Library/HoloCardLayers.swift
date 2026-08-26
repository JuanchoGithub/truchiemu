import SwiftUI
import AppKit

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

// Variant-aware contrast/saturation/brightness applied to the whole
// `HoloFoilLayers` stack (before `colorDodge`). The standard rainbow variants
// keep the source-faithful high-contrast "blowout"; Reverse Holo in solid /
// background colour mode uses a mild, colour-preserving treatment that is
// visible at rest (real reverse holo foils the whole card), and never rotates
// the user's chosen hue.
struct HoloFoilContrastModifier: ViewModifier {
    let isReverse: Bool
    let isRegularHolo: Bool
    let isRadiant: Bool
    let revRainbow: Bool
    let pfc: CGFloat

    func body(content: Content) -> some View {
        if revRainbow {
            content
                .contrast(2.75)
                .saturation(0.65)
                .brightness(-0.4 + pfc * 0.25)
        } else if isReverse || isRegularHolo || isRadiant {
            // Reverse Holo / Holofoil Rare bake their own source-faithful filter
            // into the live shine (`reverseShine` / `regularHoloShine`) before
            // the colour-dodge, so the body-level modifier is a no-op here to
            // avoid double-applying the generic high-contrast "blowout".
            content
                .contrast(1.0)
                .saturation(1.0)
                .brightness(0.0)
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
        let isReverse = (settings.randomization?.variant == .reverseSwift)
        let isRegularHolo = (settings.randomization?.variant == .regularHolo)
        let isRadiant = (settings.randomization?.variant == .radiantHolo)
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
        .modifier(HoloFoilContrastModifier(isReverse: isReverse, isRegularHolo: isRegularHolo, isRadiant: isRadiant, revRainbow: revRainbow, pfc: pointerFromCenter))
        // Blend mode. Reverse Holo uses `color-dodge` (source-faithful blowout).
        // Holofoil Rare also uses `color-dodge` in the source, but that blend
        // LIGHTENS — over our bright/white card art a bright rainbow blows
        // straight to white (invisible), so only the mid-tone edges show any
        // colour. `multiply` is the complement: rainbow × white art = the
        // rainbow itself, so the full diagonal rainbow reads across the bright
        // card. Trade-off: pure-black art areas go black (no rainbow there),
        // which is acceptable since our cards are predominantly light.
        .blendMode(isRadiant ? .screen : .colorDodge)
        // Angular hue shift: rotate the whole rainbow as the cursor moves.
        // `settings.hueCycles` full 360° rotations occur as the cursor travels
        // from one edge to the opposite edge along each axis (both axes
        // contribute, so moving diagonally shifts hue on both), matching the
        // `hueShiftDegrees` fed to the Metal bump shader below. 0 disables the
        // shift; the default of 4 makes the rainbow cycle four times across the
        // card. Pure GPU color filter on the pre-rendered tiles — no re-render
        // per cursor event.
        .hueRotation(.degrees(revRainbow || (!isReverse && !isRegularHolo) ? hueDegrees : 0))

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
            if isRadiant {
                radiantGlare(w: w, h: h)
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
        if variant == .reverseSwift || variant == .regularHolo { return .zero }
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
        let isReverse = (variant == .reverseSwift)
        // Holofoil Rare (regularHolo) is also a live, pointer-driven shine
        // (`regularHoloShine`), so it shares Reverse Holo's "no baked tile"
        // treatment. Every other variant uses the pre-rendered tile.
        let isLiveShine = isReverse || variant == .regularHolo || variant == .radiantHolo
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
        if let variant, variant == .reverseSwift {
            // Live, pointer-driven Reverse Holo shine (reverse-holo.css).
            reverseShine(w: w, h: h)
                .frame(width: w * 2, height: h * 2)
        } else if let variant, variant == .regularHolo {
            // Live, pointer-driven Holofoil Rare shine (regular-holo.css).
            regularHoloShine(w: w, h: h)
                .frame(width: w * 2, height: h * 2)
        } else if let variant, variant == .radiantHolo {
            // Live, pointer-driven Radiant shine (radiant-holo.css).
            radiantShine(w: w, h: h)
                .frame(width: w * 2, height: h * 2)
        } else if let tile = textureTile {
            Image(nsImage: tile)
                .resizable()
                .frame(width: w * 2, height: h * 2)
        }
        // Sweep band for the rainbow variants (subtle gloss). Suppressed for
        // Reverse Holo and Holofoil Rare — their moving highlight comes from
        // their live shines (the rainbow slide / the vertical beam bars).
        let isReverse = (variant == .reverseSwift)
        let bandPeak: Double = (isReverse || variant == .regularHolo) ? 0.0 : 0.7
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
            .mask(mode == .rainbow
                  ? AnyView(foilLuminanceMask(period: period, w: w, h: h))
                  : AnyView(Color.white.frame(width: w * 6, height: h * 6)))
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
    /// light/dark sweep. Dark foil areas -> transparent (alpha 0); bright areas
    /// -> opaque. So both the hue AND the moving ray/radial only touch the
    /// texture's lit cells — the dark cells stay untouched (card shows through).
    @ViewBuilder
    private func foilLuminanceMask(period: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        if settings.reverseTextureMode != .generated,
           let p = settings.reverseTexturePattern,
           let m = HoloPatternStore.shared.tiledAlphaMask(for: p, size: NSSize(width: w * 2, height: h * 2), scale: settings.reverseTextureScale) {
            Image(nsImage: m)
                .resizable()
                .frame(width: w * 2, height: h * 2)
        } else {
            ZStack {
                RepeatingLinearGradientView(colors: [.white, .clear], angle: 45, period: period)
                RepeatingLinearGradientView(colors: [.white, .clear], angle: -45, period: period)
                    .blendMode(.multiply)
            }
            .frame(width: w * 2, height: h * 2)
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
    /// gradients multiplied). Greyscale so that, after colour-dodge onto the
    /// card, bright cells blow to white and dark cells resolve to a *darker
    /// shade of the card's own colour*. `Solid` tints it; `Rainbow` and
    /// `Background` keep it greyscale — rainbow's hue is added separately (in
    /// `reverseShine`) only to the lit areas.
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
            case .background:
                // Same greyscale metallic lattice as rainbow's base, but shown
                // (no hue) so the background variant reads as neutral metal.
                ZStack {
                    RepeatingLinearGradientView(colors: [.white, Color(white: 0.3)], angle: 45, period: period)
                    RepeatingLinearGradientView(colors: [.white, Color(white: 0.3)], angle: -45, period: period)
                        .blendMode(.multiply)
                }
                .frame(width: w * 2, height: h * 2)
            case .solid:
                ZStack {
                    RepeatingLinearGradientView(colors: [.white, Color(white: 0.3)], angle: 45, period: period)
                    RepeatingLinearGradientView(colors: [.white, Color(white: 0.3)], angle: -45, period: period)
                        .blendMode(.multiply)
                }
                .frame(width: w * 2, height: h * 2)
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
    @ViewBuilder
    private func radiantShine(w: CGFloat, h: CGFloat) -> some View {
        // Everything is drawn additively (`.screen`) into one canvas, then the
        // whole canvas is `.screen`'d onto the (dark) card. `screen` keeps the
        // colours close to their literal values — so the pastel spectrum stays
        // pastel and the lattice reads as soft silver, unlike `color-dodge`
        // which blows pastels into neon.
        let glowCenter = CGPoint(x: pointerX * 0.5 + 0.25,
                                 y: pointerY * 0.5 + 0.25)
        let latticePeriod = w * 0.085
        let lineWidth = max(1.0, w * 0.007)
        let specPar = -2.5
        let specPeriod = w * 0.5
        // Lattice slides with the pointer (parallax).
        let latOff = (pointerX - 0.5) * latticePeriod * 2.0

        return Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let cover = hypot(size.width, size.height)

            // Rotate about the centre, run `body`, then undo the transform.
            func rotate(_ angle: Double, _ body: () -> Void) {
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: .degrees(angle))
                ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
                body()
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: .degrees(-angle))
                ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
            }

            ctx.blendMode = .screen

            // 1. Cyan cursor glow (`.card__shine` radial, `--card-glow` cyan).
            let glow = Gradient(stops: [
                Gradient.Stop(color: Color(hue: 0.5, saturation: 0.9, brightness: 0.95).opacity(0.95), location: 0.0),
                Gradient.Stop(color: Color(hue: 0.5, saturation: 0.8, brightness: 0.55).opacity(0.0), location: 1.0),
            ])
            ctx.fill(Path(rect), with: .radialGradient(glow,
                                                     center: CGPoint(x: glowCenter.x * size.width,
                                                                     y: glowCenter.y * size.height),
                                                     startRadius: 0,
                                                     endRadius: max(size.width, size.height) * 0.9))

            // 2. Criss-cross silver lattice (two diagonal line families).
            for family in [45.0, -45.0] {
                rotate(family) {
                    var y = -cover
                    while y < cover {
                        let yy = y + latOff
                        let path = Path { p in
                            p.move(to: CGPoint(x: -cover, y: yy))
                            p.addLine(to: CGPoint(x: cover, y: yy))
                        }
                        ctx.stroke(path, with: .color(Color(white: 0.92).opacity(0.32)),
                                   lineWidth: lineWidth)
                        y += latticePeriod
                    }
                }
            }

            // 3. Pastel spectrum sheen (`.card__shine:after`, 55°, low alpha).
            let spectrum: [Color] = [
                Color(hue: 0.99, saturation: 0.55, brightness: 0.92).opacity(0.18),
                Color(hue: 0.15, saturation: 0.55, brightness: 0.86).opacity(0.18),
                Color(hue: 0.27, saturation: 0.55, brightness: 0.86).opacity(0.18),
                Color(hue: 0.49, saturation: 0.55, brightness: 0.90).opacity(0.18),
                Color(hue: 0.63, saturation: 0.55, brightness: 0.88).opacity(0.18),
                Color(hue: 0.79, saturation: 0.55, brightness: 0.86).opacity(0.18),
                Color(hue: 0.99, saturation: 0.55, brightness: 0.92).opacity(0.18),
            ]
            rotate(55) {
                let span = cover * 2
                let grad = Gradient(colors: spectrum)
                let ox = (pointerX - 0.5) * specPar * size.width
                let oy = (pointerY - 0.5) * specPar * size.height
                ctx.translateBy(x: ox, y: oy)
                var x = -span
                while x < span {
                    ctx.fill(Path(CGRect(x: x, y: -span, width: specPeriod, height: span * 2)),
                             with: .linearGradient(grad,
                                                  startPoint: CGPoint(x: x, y: -span),
                                                  endPoint: CGPoint(x: x + specPeriod, y: -span)))
                    x += specPeriod
                }
                ctx.translateBy(x: -ox, y: -oy)
            }

            ctx.blendMode = .normal
        }
        .frame(width: w * 2, height: h * 2)
        .compositingGroup()
    }

    /// Radiant glare — `.card__shine:before` (glitter + cursor radial,
    /// `overlay`) and `.card__glare` (cursor radial, `hard-light`). Kept
    /// outside the colour-dodge group so each keeps its own blend.
    @ViewBuilder
    private func radiantGlare(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            // `.card__shine:before` — soft cursor radial (overlay).
            RadialGradient(
                stops: [
                    Gradient.Stop(color: Color(white: 0.58).opacity(0.8), location: 0.10),
                    Gradient.Stop(color: Color(white: 0.20).opacity(0.9), location: 0.20),
                    Gradient.Stop(color: Color(white: 0.20).opacity(0.5), location: 0.50),
                ],
                center: UnitPoint(x: pointerX, y: pointerY),
                startRadius: 0,
                endRadius: max(w, h) * 0.9
            )
            .blendMode(.overlay)
            .frame(width: w * 2, height: h * 2)
            // `.card__glare` — cursor radial, `hard-light`.
            RadialGradient(
                stops: [
                    Gradient.Stop(color: Color.white.opacity(0.33), location: 0.0),
                    Gradient.Stop(color: Color(white: 0.25), location: 1.10),
                ],
                center: UnitPoint(x: pointerX, y: pointerY),
                startRadius: 0,
                endRadius: max(w, h) * 0.9
            )
            .blendMode(.hardLight)
            .frame(width: w * 2, height: h * 2)
        }
    }

    // mirroring how `reverseShine` is done.
    @ViewBuilder
    private func regularHoloShine(w: CGFloat, h: CGFloat) -> some View {
        // Full spectral loop (red→…→red) so the rainbow reads as a smooth,
        // vivid spectrum across the card. High saturation is what makes it
        // "huge and beautiful" once multiplied onto bright card art.
        let rainbowColors: [Color] = [
            Color(hue: 0.00, saturation: 1.0, brightness: 1.0),
            Color(hue: 0.15, saturation: 1.0, brightness: 1.0),
            Color(hue: 0.33, saturation: 1.0, brightness: 1.0),
            Color(hue: 0.50, saturation: 1.0, brightness: 1.0),
            Color(hue: 0.66, saturation: 1.0, brightness: 1.0),
            Color(hue: 0.83, saturation: 1.0, brightness: 1.0),
            Color(hue: 1.00, saturation: 1.0, brightness: 1.0)
        ]
        // Source: one rainbow ≈ 1.4 card widths across the 400% tile; the
        // 110° angle gives the diagonal holo read. A slightly tighter period
        // makes the bands read as a large, obvious rainbow across the card.
        let rainbowPeriod = w * 1.15
        // Source `background-position`: ((50% - x) * 2.6) + 50% , ((50% - y) * 3.5) + 50%.
        // The +50% is "centred"; we express the slide as a point offset. The
        // rainbow layer is oversized (4w×4h) so the offset never exposes an edge
        // (the gradient repeats).
        let rainbowOffset = CGSize(
            width: (0.5 - pointerX) * w * 2.6,
            height: (0.5 - pointerY) * h * 3.5
        )

        // Scanline density: higher setting -> finer (smaller period) lines.
        // The scanlines stay subtle so they don't stripe the rainbow away.
        let scanlinePeriod = max(2.0, (max(3.0, w * 0.015)) / max(0.05, settings.holofoilRareScanlineDensity))
        // Beam strength scales the bar colour's lightness (0 -> invisible).
        // Kept low so the beam reads as a subtle moving highlight, not a set of
        // dark bars that punch holes in the rainbow.
        let barLightness = 0.35 * max(0.0, min(1.0, settings.holofoilRareBeamStrength))
        // Intensity (0…2): drives the colour-dodge "blowout". The brightness /
        // contrast / saturation below make the rainbow vivid through the dodge;
        // values above 1 overdrive it for an even more saturated holo.
        let i = settings.holofoilRareIntensity
        let over = max(0.0, i - 1.0)
        // Multiply model (not colour-dodge): the rainbow must stay saturated and
        // only mildly contrasted so it multiplies onto bright art as vivid colour
        // instead of washing to grey. Values > 1 (intensity overdrive) push
        // saturation/contrast harder for an even richer holo.
        // colour-dodge model (same as Reverse Holo, which works on your art):
        // keep the foil bright and saturation cranked so the dodge resolves to a
        // vivid rainbow on dark art instead of washing out. Intensity > 1
        // overdrives saturation/contrast for an even richer holo.
        let shineBrightness = 0.0
        let shineContrast = 1.5 + over * 0.5
        let shineSaturation = 3.0 + over * 1.0
        let shineAlpha = min(1.0, i)

        ZStack {
            // `.card__shine` — rainbow + scanlines + beam bars + radial, carrying
            // the source's brightness(1.1) contrast(1.1) saturate(1.2) filter
            // (boosted here so the colour-dodge onto the art reads as a vivid
            // rainbow rather than a washed-out grey).
            ZStack {
                // Base `.card__shine` — rainbow + scanlines. Source `90deg`
                // scanlines are VERTICAL bands; our `90` would render them
                // horizontal, so we use `0` to match the source.
                ZStack {
                    RepeatingLinearGradientView(colors: rainbowColors, angle: 110, period: rainbowPeriod)
                        .frame(width: w * 4, height: h * 4)
                        .offset(rainbowOffset)
                        // Mirror Reverse Holo's proven rainbow: `screen` so the
                        // spectrum is bright (colour-dodge onto dark art then
                        // reads as a vivid rainbow, not a dim wash).
                        .blendMode(.screen)
                        .opacity(shineAlpha)
                        // Gate the rainbow to the holofoil's vertical-stripe
                        // texture: it shows only in the "clear" (lit) bands
                        // between the dark stripe lines — so it reads as a
                        // holographic shimmer on the texture, not a flat wash
                        // across the whole image. Mask is sized to the oversized
                        // rainbow frame so the cursor slide never exposes an
                        // unmasked edge.
                        .mask(
                            // Mostly-lit vertical-stripe mask: the rainbow shows
                            // in ~75% of the card (the "clear" bands) and is
                            // gated out only on the thin dark stripe lines. This
                            // keeps the rainbow HUGE while still reading as a
                            // holographic texture, not a flat wash.
                            RepeatingLinearGradientView(
                                colors: [Color(white: 1.0), Color(white: 1.0), Color(white: 1.0), Color(white: 0.0)],
                                angle: 0,
                                period: scanlinePeriod
                            )
                            .frame(width: w * 4, height: h * 4)
                        )
                    RepeatingLinearGradientView(
                        colors: [Color(white: 0.15), Color(white: 0.32)],
                        angle: 0, period: scanlinePeriod
                    )
                    .frame(width: w * 2, height: h * 2)
                    .blendMode(.overlay)
                }

                // `:before` — vertical beam bars. Two `90deg` black/grey bar
                // gradients (source `--bar-color: 70% grey`, `--bars: 3%`),
                // screen-blended together, then the whole element `hard-light`s
                // onto the base — the moving "beam" the source slides via
                // background-position. Source angle is `90deg` -> vertical.
                ZStack {
                    RepeatingLinearGradientView(
                        colors: [Color.black, Color(white: barLightness)],
                        angle: 0, period: w * 0.06
                    )
                    .frame(width: w * 2, height: h * 2)
                    .offset(x: (0.5 - pointerX) * w * 1.65 + pointerY * h * 0.5,
                            y: 0)
                    RepeatingLinearGradientView(
                        colors: [Color.black, Color(white: barLightness)],
                        angle: 0, period: w * 0.06
                    )
                    .frame(width: w * 2, height: h * 2)
                    .offset(x: (0.5 - pointerX) * -w * 0.9 - pointerY * h * 0.75,
                            y: 0)
                    .blendMode(.screen)
                }
                .blendMode(.hardLight)

                // NOTE: the source's `:after` radial uses `luminosity`, which
                // takes the radial's (mostly dark) luminance and crushes the
                // rainbow to near-black except a tiny centre spot. Over our
                // darker card art that erases the rainbow entirely, so we omit
                // it here — the glare sibling already supplies the moving
                // highlight. Re-add subtly only if the art proves bright enough.
            }
            // Source `.card__shine` filter: brightness(1.1) contrast(1.1)
            // saturate(1.2) — matched to Reverse Holo's vivid colour-dodge
            // recipe (bright + high saturation).
            .colorMultiply(Color(white: 0.8))
            .brightness(shineBrightness)
            .contrast(shineContrast)
            .saturation(shineSaturation)
            // Flatten the internal overlay/hardLight/screen blends into one
            // layer so they composite among themselves (not onto the card art)
            // before the external `.colorDodge` is applied.
            .compositingGroup()
        }
        // User master intensity (alpha is capped at 1; the overdrive above
        // drives the brightness/contrast/saturation instead).
        .opacity(shineAlpha)
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
                Gradient.Stop(color: Color(hue: 0.5, saturation: 1.0, brightness: 0.95, opacity: 0.9), location: 0.0),
                Gradient.Stop(color: Color(hue: 0.5, saturation: 0.5, brightness: 0.85, opacity: 0.25), location: 0.45),
                Gradient.Stop(color: Color(hue: 0.5, saturation: 0.0, brightness: 0.7, opacity: 0.0), location: 1.0),
            ],
            center: UnitPoint(x: pointerX, y: pointerY),
            startRadius: 0,
            endRadius: max(w, h) * 0.95
        )
        .blendMode(.overlay)
        .frame(width: w * 2, height: h * 2)
        // Source `.card__glare` opacity `card-opacity * .8`, scaled by the
        // user's glare setting. No darkening filters applied.
        .opacity(settings.holofoilRareGlare * 0.8)
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
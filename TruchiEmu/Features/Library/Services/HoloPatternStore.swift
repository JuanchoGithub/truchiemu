import AppKit
import CoreImage
import Foundation
import SwiftUI

// Encode/decode a SwiftUI `Color` as an `r,g,b` (0..1) string so it can be
// persisted through `AppSettings`' String store, and used as a stable cache
// key for pre-rendered foil tiles.
func holoEncodeColor(_ color: Color) -> String {
    let ns = NSColor(color)
    let srgb = ns.usingColorSpace(.sRGB) ?? ns
    return String(format: "%.4f,%.4f,%.4f", srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
}

func holoDecodeColor(_ string: String?) -> Color {
    // Default: a bright silver — the classic non-rare reverse-holo tint that
    // reads clearly under colorDodge against any art.
    let fallback = Color(red: 0.92, green: 0.92, blue: 0.94)
    guard let string else { return fallback }
    let parts = string.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 3 else { return fallback }
    return Color(red: parts[0], green: parts[1], blue: parts[2])
}

// Static foil pattern textures bundled from the pokemon-cards-css project
// (https://github.com/simeydotme/pokemon-cards-css/blob/main/public/img).
// Used to give title / chrome / hero regions their own distinct holo look,
// clipped by the computed region mask.
//
// The source textures are grayscale with NO alpha channel, so before they can
// gate a SwiftUI .mask() the luminance must be converted to alpha.
enum HoloPattern: String, CaseIterable, Identifiable {
    case ancient
    case angular
    case crossover
    case geometric
    case glitter
    case galaxy
    case illusion
    case illusion2
    case metal
    case stylish
    case stylish2
    case trainerbg
    case vmaxbg
    case wave

    var id: String { rawValue }

    /// Patterns permitted as the SECOND (overlay) etch in Reverse Holo. Only
    /// these may be layered on top of another pattern, and they themselves are
    /// never given a second pattern (exclusive to the overlay role).
    static let secondPatternWhitelist: [HoloPattern] = [.galaxy, .glitter]

    /// Bundle filename. Resources are flattened at build time, so the
    /// `holo_` prefix keeps these unambiguous at the bundle root.
    var resourceName: String { "holo_\(rawValue)" }

    var displayName: String {
        rawValue.capitalized
    }
}

@MainActor
final class HoloPatternStore: ObservableObject {
    static let shared = HoloPatternStore()

    private var patterns: [HoloPattern: NSImage] = [:]
    private var alphaMasks: [HoloPattern: NSImage] = [:]
    // Scaled alpha masks, keyed by pattern + integer size bucket. The foil
    // band is rendered larger than the card so it can slide beneath the
    // region masks as the pointer moves (source `background-position`); we
    // cache a few buckets instead of re-scaling per frame.
    private var scaledAlphaMasks: [ScaledAlphaKey: NSImage] = [:]

    struct ScaledAlphaKey: Hashable {
        let pattern: HoloPattern
        let width: Int
        let height: Int
    }

    func image(for pattern: HoloPattern) -> NSImage? {
        if let cached = patterns[pattern] { return cached }
        guard let url = Bundle.main.url(forResource: pattern.resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        patterns[pattern] = image
        return image
    }

    /// Luminance -> alpha version of the texture. Bright foil areas (white)
    /// become opaque, dark areas transparent, so the holo rainbow only shows
    /// through the foil's bright pattern instead of as a uniform wash.
    func alphaMask(for pattern: HoloPattern) -> NSImage? {
        if let cached = alphaMasks[pattern] { return cached }
        guard let base = image(for: pattern),
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        // CIMaskToAlpha: luminance -> alpha (white -> opaque).
        let alpha = ci.applyingFilter("CIMaskToAlpha")
        let context = CIContext()
        guard let out = context.createCGImage(alpha, from: alpha.extent) else { return nil }
        let mask = NSImage(cgImage: out, size: NSSize(width: cg.width, height: cg.height))
        alphaMasks[pattern] = mask
        return mask
    }

    /// Luminance->alpha mask tiled to a target size. Faithful to the source's
    /// `background-repeat: repeat` with `--glittersize: 25%` (relative to the
    /// card): the small texture is repeated across the rect instead of
    /// stretched to fill it, so the foil keeps its fine repeating pattern
    /// rather than one blown-up copy. Used by `HoloFoilTileCache` to gate
    /// the rainbow.
    func alphaMask(for pattern: HoloPattern, scaledTo size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = ScaledAlphaKey(pattern: pattern, width: Int(size.width), height: Int(size.height))
        if let cached = scaledAlphaMasks[key] { return cached }

        guard let base = alphaMask(for: pattern),
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // The foil tile is rendered at 2× the card so the mask aligns 1:1
        // with the art, but the pattern itself tiles at the source's
        // `--glittersize: 25%` of the card width — i.e. 12.5% of the tile's
        // width (size.width = 2 × card width). Cell aspect follows the
        // texture; square textures produce square cells.
        let cellW = size.width / 8
        let cellH = cellW * (CGFloat(cg.height) / CGFloat(cg.width))

        let source = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let out = NSImage(size: size, flipped: true) { rect in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    source.draw(
                        in: NSRect(x: x, y: y, width: cellW, height: cellH),
                        from: NSRect(x: 0, y: 0, width: cg.width, height: cg.height),
                        operation: .copy,
                        fraction: 1.0
                    )
                    x += cellW
                }
                y += cellH
            }
            return true
        }
        scaledAlphaMasks[key] = out
        return out
    }

    /// The bundled global scratch / sparkle mask (holo_illusion-mask.png).
    /// Applied across the whole card at low opacity to add the pokemon-cards-css
    /// sparkle/scratch sub-effect. Done lazily in alpha-mask form so SwiftUI
    /// `.mask()` accepts it. Thread-safe under MainActor (the class is @MainActor).
    private var _scratchMask: NSImage?
    func scratchMask() -> NSImage? {
        if let cached = _scratchMask { return cached }
        guard let url = Bundle.main.url(forResource: "holo_illusion-mask", withExtension: "png"),
              let base = NSImage(contentsOf: url),
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg).applyingFilter("CIMaskToAlpha")
        let context = CIContext()
        if let out = context.createCGImage(ci, from: ci.extent) {
            let mask = NSImage(cgImage: out, size: NSSize(width: cg.width, height: cg.height))
            _scratchMask = mask
            return mask
        }
        return nil
    }

    /// A bundled etch tiled into an `NSSize` image, repeated at `scale`×
    /// (1× = one copy filling the surface; 0.1× = a fine repeat). Used by the
    /// Reverse Holo foil so each card's etch can be a small repeating pattern
    /// rather than one stretched copy. Cached per (pattern, scale-bucket, size)
    /// so it's drawn once per card, not every cursor frame.
    private var tiledImages: [TiledImageKey: NSImage] = [:]
    struct TiledImageKey: Hashable {
        let pattern: HoloPattern
        let scaleBucket: Int
        let width: Int
        let height: Int
    }

    func tiledImage(for pattern: HoloPattern, size: NSSize, scale: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = TiledImageKey(
            pattern: pattern,
            scaleBucket: Int((scale * 200).rounded()),
            width: Int(size.width),
            height: Int(size.height)
        )
        if let cached = tiledImages[key] { return cached }
        guard let base = image(for: pattern),
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let cellW = max(1.0, size.width * scale)
        let cellH = cellW * (CGFloat(cg.height) / CGFloat(cg.width))
        let src = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let out = NSImage(size: size, flipped: false) { rect in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    src.draw(
                        in: NSRect(x: x, y: y, width: cellW, height: cellH),
                        from: .zero,
                        operation: .copy,
                        fraction: 1.0
                    )
                    x += cellW
                }
                y += cellH
            }
            return true
        }
            tiledImages[key] = out
        return out
    }

    /// Luminance→alpha mask of a tiled etch, at the SAME (pattern, scale, size)
    /// as `tiledImage` so it aligns 1:1 with the foil. Dark etch pixels become
    /// transparent (zero hue), bright pixels opaque (full hue) — the heightmap
    /// the Reverse Holo rainbow is gated by. Cached so it is built once per card,
    /// not on every cursor frame.
    private var tiledAlphaMasks: [TiledImageKey: NSImage] = [:]
    func tiledAlphaMask(for pattern: HoloPattern, size: NSSize, scale: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = TiledImageKey(
            pattern: pattern,
            scaleBucket: Int((scale * 200).rounded()),
            width: Int(size.width),
            height: Int(size.height)
        )
        if let cached = tiledAlphaMasks[key] { return cached }
        guard let tiled = tiledImage(for: pattern, size: size, scale: scale) else { return nil }
        // `tiledImage` is a block-drawn NSImage, which does NOT reliably vend a
        // CGImage via `cgImage(forProposedRect:)` (unlike the bundle PNGs). If we
        // let that return nil here, the rainbow falls back to the 1x lattice
        // mask and prints at full size while the foil texture is tiled small.
        // Rasterise through a bitmap rep so the luminance->alpha conversion is
        // dependable and stays aligned with the tiled foil.
        guard let tiff = tiled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return nil }
        let ci = CIImage(cgImage: cg).applyingFilter("CIMaskToAlpha")
        let context = CIContext()
        guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }
        let mask = NSImage(cgImage: out, size: NSSize(width: cg.width, height: cg.height))
        tiledAlphaMasks[key] = mask
        return mask
    }
}

// Persisted holo parameters. Observable so visible cards re-render when the
// user changes an intensity or pattern in HoloSettingsView. Two layers:
//   - `maskDeviationChance`: the % chance (0…1) that a section
//     (title/chrome/hero) deviates from the background's randomized mask. The
//     background is always randomized per card (see `HoloCardRandomization`);
//     each section rolls this chance to get its own mask, otherwise it
//     inherits the background's mask.
//   - per-region intensity: how strongly each region picks up the foil.
@MainActor
final class HoloSettingsStore: ObservableObject {
    static let shared = HoloSettingsStore()

    // Random seed, fresh each launch. Combined with the per-rom FNV-1a seed
    // it gives every visible card a stable-for-the-session but
    // different-every-launch randomization (pattern, mask chance, intensity).
    static let launchSeed: UInt64 = UInt64.random(in: .min ... .max)

    // Storage keys (existing — kept compatible with prior releases).
    static let titleIntensityKey = "holo_title_intensity"
    static let chromeIntensityKey = "holo_chrome_intensity"
    static let heroIntensityKey = "holo_hero_intensity"
    static let backgroundIntensityKey = "holo_background_intensity"
    static let titlePatternKey = "holo_title_pattern"
    static let chromePatternKey = "holo_chrome_pattern"
    static let heroPatternKey = "holo_hero_pattern"
    static let backgroundPatternKey = "holo_background_pattern"
    static let maskDeviationChanceKey = "holo_mask_deviation_chance"
    static let variantWeightsKey = "holo_variant_weights"
    static let depthModeKey = "holo_depth_mode"
    static let specularPowerKey = "holo_specular_power"
    static let cursorInfluenceKey = "holo_cursor_influence"
    static let tiltInfluenceKey = "holo_tilt_influence"
    static let parallaxStrengthKey = "holo_parallax_strength"
    static let showPlayButtonKey = "holo_show_play_button"
    static let hueCyclesKey = "holo_hue_cycles"
    static let reverseColorModeKey = "holo_reverse_color_mode"
    static let reverseSolidColorKey = "holo_reverse_solid_color"
    static let reverseRainbowIntensityKey = "holo_reverse_rainbow_intensity"
    static let reverseTextureModeKey = "holo_reverse_texture_mode"
    static let reverseTextureVariationKey = "holo_reverse_texture_variation"

    @Published var titleIntensity: Double {
        didSet { AppSettings.setDouble(Self.titleIntensityKey, value: titleIntensity) }
    }
    @Published var chromeIntensity: Double {
        didSet { AppSettings.setDouble(Self.chromeIntensityKey, value: chromeIntensity) }
    }
    @Published var heroIntensity: Double {
        didSet { AppSettings.setDouble(Self.heroIntensityKey, value: heroIntensity) }
    }
    @Published var backgroundIntensity: Double {
        didSet { AppSettings.setDouble(Self.backgroundIntensityKey, value: backgroundIntensity) }
    }
    @Published var titlePattern: HoloPattern {
        didSet { AppSettings.set(Self.titlePatternKey, value: titlePattern.rawValue) }
    }
    @Published var chromePattern: HoloPattern {
        didSet { AppSettings.set(Self.chromePatternKey, value: chromePattern.rawValue) }
    }
    @Published var heroPattern: HoloPattern {
        didSet { AppSettings.set(Self.heroPatternKey, value: heroPattern.rawValue) }
    }
    @Published var backgroundPattern: HoloPattern {
        didSet { AppSettings.set(Self.backgroundPatternKey, value: backgroundPattern.rawValue) }
    }
    // % chance (0…1) that a section (title/chrome/hero) deviates from the
    // background's randomized mask. The background is always randomized per
    // card. Each section rolls this chance: on success it gets its own
    // randomized mask, on failure it inherits the background's mask. 0 = every
    // section uses the background's mask; 1 = every section rolls its own.
    @Published var maskDeviationChance: Double {
        didSet { AppSettings.setDouble(Self.maskDeviationChanceKey, value: maskDeviationChance) }
    }
    // Depth rendering mode. Default `.parallax` matches the prior effect
    // exactly so existing users see no change after upgrading. Switching
    // to `.bump` or `.both` engages the Metal bump shader.
    @Published var depthMode: HoloDepthMode {
        didSet { AppSettings.set(Self.depthModeKey, value: depthMode.rawValue) }
    }
    // Blinn-Phong specular exponent for the bump shader. 16 (broad) to
    // 64 (sharp). Only used when `depthMode != .parallax`.
    @Published var specularPower: Double {
        didSet { AppSettings.setDouble(Self.specularPowerKey, value: specularPower) }
    }
    // 0..1 — how strongly the cursor adds lateral offset to the bump
    // light direction. 0 = pure card tilt drives the light; 1 = cursor
    // dominates.
    @Published var cursorInfluence: Double {
        didSet { AppSettings.setDouble(Self.cursorInfluenceKey, value: cursorInfluence) }
    }
    // 0..1 — how strongly the card's 3D tilt rotates the bump light
    // direction. 0 = light stays fixed in world space; 1 = light is
    // fully anchored to the card (highlights follow the tilt).
    @Published var tiltInfluence: Double {
        didSet { AppSettings.setDouble(Self.tiltInfluenceKey, value: tiltInfluence) }
    }
    // 0..1 — multiplier on the parallax shear applied to the
    // non-bump `HoloFoilLayers` rendering. 0 = no shear (existing look);
    // 1 = full source-faithful parallax multipliers (background-position
    // shifts 2.6x/3.5x with the cursor). Used by both `.parallax` and
    // `.both` modes.
    @Published var parallaxStrength: Double {
        didSet { AppSettings.setDouble(Self.parallaxStrengthKey, value: parallaxStrength) }
    }
    // Show the glass-orb play button on holo grid cards. Default false (hidden)
    // so the holo artwork stays unobstructed unless the user opts in.
    @Published var showPlayButton: Bool {
        didSet { AppSettings.set(Self.showPlayButtonKey, value: showPlayButton) }
    }
    // Number of full hue-rotation cycles applied as the cursor travels from one
    // edge of the card to the opposite edge (per axis). 0 = no hue shift;
    // higher = the rainbow cycles more times across the artwork. Default 4.
    @Published var hueCycles: Double {
        didSet { AppSettings.setDouble(Self.hueCyclesKey, value: hueCycles) }
    }
    // Reverse Holo's pattern-sheen colour source (solid / rainbow / background).
    @Published var reverseColorMode: HoloReverseColorMode {
        didSet { AppSettings.set(Self.reverseColorModeKey, value: reverseColorMode.rawValue) }
    }
    // User-chosen solid tint for the Reverse Holo pattern (encoded as
    // `r,g,b` floats 0..1 so it round-trips through AppSettings' Data store).
    @Published var reverseSolidColor: Color {
        didSet { AppSettings.set(Self.reverseSolidColorKey, value: holoEncodeColor(reverseSolidColor)) }
    }
    // 0..1 — saturation/brightness of the Reverse Holo rainbow sheen. Only
    // used when `reverseColorMode == .rainbow`. Default 1.0.
    @Published var reverseRainbowIntensity: Double {
        didSet { AppSettings.setDouble(Self.reverseRainbowIntensityKey, value: reverseRainbowIntensity) }
    }
    // Reverse Holo foil source: built-in lattice vs. a random bundled etch.
    @Published var reverseTextureMode: HoloReverseTextureMode {
        didSet { AppSettings.set(Self.reverseTextureModeKey, value: reverseTextureMode.rawValue) }
    }
    // When on (and the foil source is Random), each card's etch is tiled at a
    // random scale (0.1…1.0×) and has a chance to layer a second etch on top
    // with a random blend — the "randomly merge textures" richness.
    @Published var reverseTextureVariation: Bool {
        didSet { AppSettings.set(Self.reverseTextureVariationKey, value: reverseTextureVariation) }
    }

    /// Per-variant probability weight (0..1 share). A card rolls a variant
    /// against these weights; the chosen variant stays for the session.
    /// Default: equal distribution across the catalog (1/N each) so all
    /// variants appear with equal frequency. Setting one to 1 and the rest
    /// to 0 forces that variant; setting all to 0 falls back to regularHolo.
    @Published var variantWeights: [HoloVariant: Double] {
        didSet { persistVariantWeights() }
    }

    private init() {
        self.titleIntensity = AppSettings.getDouble(Self.titleIntensityKey, defaultValue: 0.35)
        self.chromeIntensity = AppSettings.getDouble(Self.chromeIntensityKey, defaultValue: 0.45)
        self.heroIntensity = AppSettings.getDouble(Self.heroIntensityKey, defaultValue: 0.15)
        self.backgroundIntensity = AppSettings.getDouble(Self.backgroundIntensityKey, defaultValue: 0.60)
        self.titlePattern = HoloPattern(rawValue: AppSettings.getString(Self.titlePatternKey, defaultValue: HoloPattern.ancient.rawValue) ?? "") ?? .ancient
        self.chromePattern = HoloPattern(rawValue: AppSettings.getString(Self.chromePatternKey, defaultValue: HoloPattern.geometric.rawValue) ?? "") ?? .geometric
        self.heroPattern = HoloPattern(rawValue: AppSettings.getString(Self.heroPatternKey, defaultValue: HoloPattern.illusion.rawValue) ?? "") ?? .illusion
        self.backgroundPattern = HoloPattern(rawValue: AppSettings.getString(Self.backgroundPatternKey, defaultValue: HoloPattern.wave.rawValue) ?? "") ?? .wave
        self.maskDeviationChance = AppSettings.getDouble(Self.maskDeviationChanceKey, defaultValue: 0.0)
        self.variantWeights = Self.loadVariantWeights()
        self.depthMode = HoloDepthMode(rawValue: AppSettings.getString(Self.depthModeKey, defaultValue: HoloDepthMode.parallax.rawValue) ?? "") ?? .parallax
        self.specularPower = AppSettings.getDouble(Self.specularPowerKey, defaultValue: 32.0)
        self.cursorInfluence = AppSettings.getDouble(Self.cursorInfluenceKey, defaultValue: 0.6)
        self.tiltInfluence = AppSettings.getDouble(Self.tiltInfluenceKey, defaultValue: 0.8)
        self.parallaxStrength = AppSettings.getDouble(Self.parallaxStrengthKey, defaultValue: 1.0)
        self.showPlayButton = AppSettings.getBool(Self.showPlayButtonKey, defaultValue: false)
        self.hueCycles = AppSettings.getDouble(Self.hueCyclesKey, defaultValue: 4.0)
        self.reverseColorMode = HoloReverseColorMode(rawValue: AppSettings.getString(Self.reverseColorModeKey, defaultValue: HoloReverseColorMode.solid.rawValue) ?? "") ?? .solid
        self.reverseSolidColor = holoDecodeColor(AppSettings.getString(Self.reverseSolidColorKey))
        self.reverseRainbowIntensity = AppSettings.getDouble(Self.reverseRainbowIntensityKey, defaultValue: 1.0)
        self.reverseTextureMode = HoloReverseTextureMode(rawValue: AppSettings.getString(Self.reverseTextureModeKey, defaultValue: HoloReverseTextureMode.generated.rawValue) ?? "") ?? .generated
        self.reverseTextureVariation = AppSettings.getBool(Self.reverseTextureVariationKey, defaultValue: true)
    }

    /// Load the per-variant weight dictionary from AppSettings. Stored as a
    /// comma-separated `variant.rawValue:weight` string so the format stays
    /// stable across new variants being added.
    private static func loadVariantWeights() -> [HoloVariant: Double] {
        let defaults = equalWeights()
        guard let raw = AppSettings.getString(variantWeightsKey) else { return defaults }
        var result: [HoloVariant: Double] = [:]
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: ":")
            guard parts.count == 2,
                  let variant = HoloVariant(rawValue: String(parts[0])),
                  let weight = Double(parts[1]) else { continue }
            result[variant] = weight
        }
        // Fill in any new variants not yet in storage with the equal default.
        for variant in HoloVariant.allCases where result[variant] == nil {
            result[variant] = defaults[variant] ?? 0
        }
        return result
    }

    private func persistVariantWeights() {
        let entries = HoloVariant.allCases.compactMap { variant -> String? in
            guard let weight = variantWeights[variant] else { return nil }
            return "\(variant.rawValue):\(weight)"
        }
        AppSettings.set(Self.variantWeightsKey, value: entries.joined(separator: ","))
    }

    /// Equal-share weights across all variants (1/N each). The user can
    /// adjust per-variant weights in HoloSettingsView.
    static func equalWeights() -> [HoloVariant: Double] {
        let n = HoloVariant.allCases.count
        guard n > 0 else { return [:] }
        let share = 1.0 / Double(n)
        return Dictionary(uniqueKeysWithValues: HoloVariant.allCases.map { ($0, share) })
    }

    /// Adjust one variant's weight to `newValue` (0...1) and redistribute the
    /// remainder proportionally across the other variants so the total always
    /// sums to 1.0. Other variants keep their relative ratios — so when all
    /// are equal (the default), each remaining variant stays equal; when the
    /// user has an asymmetric setup, that intent is preserved.
    ///
    /// Edge cases: if `newValue` is 0 or 1 the remainder goes fully to the
    /// others pro rata; if the other variants are all 0 the remainder is
    /// distributed equally across them.
    func setVariantWeight(_ variant: HoloVariant, newValue: Double) {
        let clamped = max(0.0, min(1.0, newValue))
        let remainder = 1.0 - clamped
        var othersTotal = 0.0
        for other in HoloVariant.allCases where other != variant {
            othersTotal += variantWeights[other] ?? 0
        }
        var updated = variantWeights
        updated[variant] = clamped
        if othersTotal > 0.0001 {
            for other in HoloVariant.allCases where other != variant {
                let share = (variantWeights[other] ?? 0) / othersTotal
                updated[other] = remainder * share
            }
        } else {
            // All others currently zero — distribute remainder equally so the
            // total still sums to 1.0.
            let n = HoloVariant.allCases.count - 1
            guard n > 0 else { return }
            let equal = remainder / Double(n)
            for other in HoloVariant.allCases where other != variant {
                updated[other] = equal
            }
        }
        variantWeights = updated
    }

    /// Reset variant weights to equal share across all variants.
    func resetVariantWeights() {
        variantWeights = Self.equalWeights()
    }

    /// Whether a region should show its own pattern (vs. folding its mask
    /// into the background pattern). A region only renders its own pattern
    /// when both its intensity is > 0 and its mask is non-nil.
    func regionIsActive(_ region: HoloRegion, maskPresent: Bool) -> Bool {
        guard maskPresent else { return false }
        switch region {
        case .title: return titleIntensity > 0.001
        case .chrome: return chromeIntensity > 0.001
        case .hero: return heroIntensity > 0.001
        case .background: return backgroundIntensity > 0.001
        }
    }
}

enum HoloRegion: String, CaseIterable {
    case title, chrome, hero, background
}

// How the holographic foil is rendered. `parallax` is the existing
// pure-SwiftUI effect (rainbow gradient + texture mask + CSS blend modes);
// `bump` swaps the per-region foil for a Metal fragment shader that
// samples a procedural normal map and computes Blinn-Phong specular
// against a light direction derived from cursor + tilt; `both` stacks
// parallax under bump so the rainbow still hue-shifts while the bump
// shader adds true specular highlights on top.
enum HoloDepthMode: String, CaseIterable, Identifiable {
    case parallax
    case bump
    case both

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .parallax: return "holo.depthMode.parallax"
        case .bump:     return "holo.depthMode.bump"
        case .both:     return "holo.depthMode.both"
        }
    }
}

// Colour source for the Reverse Holo variant's pattern sheen.
//   - .solid: a user-chosen colour (with quick presets) tints the pattern.
//   - .rainbow: an iridescent rainbow sheen, with its own intensity slider.
//   - .background: each card's own detected background median colour tints
//     the pattern, so the foil harmonises with the box art.
enum HoloReverseColorMode: String, CaseIterable, Identifiable {
    case solid
    case rainbow
    case background

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .solid:      return "holo.reverse.colorMode.solid"
        case .rainbow:    return "holo.reverse.colorMode.rainbow"
        case .background: return "holo.reverse.colorMode.background"
        }
    }
}

// How the Reverse Holo foil texture is chosen.
//   - .generated: the built-in procedurally-generated diamond lattice (current).
//   - .random:    one of the bundled etch textures (holo_*.png, the source
//                 repo's `var(--foil)` images) is picked at random per card,
//                 so each reverse-holo card gets a different, richer foil that
//                 the `difference` ray then inverts — the cooler, varied look.
enum HoloReverseTextureMode: String, CaseIterable, Identifiable {
    case generated
    case random

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .generated: return "holo.reverse.textureMode.generated"
        case .random:    return "holo.reverse.textureMode.random"
        }
    }
}

// Blend mode used when two etch textures are composited into the Reverse Holo
// foil. Picked at random per card (when variation is on) for extra variety.
enum HoloTextureBlend: Int, CaseIterable, Equatable, Identifiable {
    case overlay, multiply, screen

    var id: Int { rawValue }

    var blendMode: BlendMode {
        switch self {
        case .overlay:  return .overlay
        case .multiply: return .multiply
        case .screen:   return .screen
        }
    }
}

// Quick-pick colour swatches for the Reverse Holo `.solid` mode. Gives users
// one-tap access to common foil tints without opening the colour well.
struct HoloReversePreset: Hashable {
    let name: String
    let color: Color

    static let all: [HoloReversePreset] = [
        HoloReversePreset(name: "Silver", color: Color(white: 0.80)),
        HoloReversePreset(name: "White",  color: Color(white: 0.95)),
        HoloReversePreset(name: "Gold",   color: Color(red: 1.00, green: 0.84, blue: 0.30)),
        HoloReversePreset(name: "Red",    color: Color(red: 0.95, green: 0.25, blue: 0.30)),
        HoloReversePreset(name: "Blue",   color: Color(red: 0.30, green: 0.55, blue: 0.95)),
        HoloReversePreset(name: "Green",  color: Color(red: 0.30, green: 0.85, blue: 0.45)),
        HoloReversePreset(name: "Purple", color: Color(red: 0.70, green: 0.40, blue: 0.95)),
        HoloReversePreset(name: "Teal",   color: Color(red: 0.25, green: 0.85, blue: 0.80)),
    ]
}

// Backwards-compatible static facade. Reads delegate to the shared
// HoloSettingsStore so behavior matches the @Published path used by SwiftUI.
@MainActor
enum HoloSettings {
    static var titleIntensity: Double {
        get { HoloSettingsStore.shared.titleIntensity }
        set { HoloSettingsStore.shared.titleIntensity = newValue }
    }
    static var chromeIntensity: Double {
        get { HoloSettingsStore.shared.chromeIntensity }
        set { HoloSettingsStore.shared.chromeIntensity = newValue }
    }
    static var heroIntensity: Double {
        get { HoloSettingsStore.shared.heroIntensity }
        set { HoloSettingsStore.shared.heroIntensity = newValue }
    }
    static var backgroundIntensity: Double {
        get { HoloSettingsStore.shared.backgroundIntensity }
        set { HoloSettingsStore.shared.backgroundIntensity = newValue }
    }
    static var titlePattern: HoloPattern {
        get { HoloSettingsStore.shared.titlePattern }
        set { HoloSettingsStore.shared.titlePattern = newValue }
    }
    static var chromePattern: HoloPattern {
        get { HoloSettingsStore.shared.chromePattern }
        set { HoloSettingsStore.shared.chromePattern = newValue }
    }
    static var heroPattern: HoloPattern {
        get { HoloSettingsStore.shared.heroPattern }
        set { HoloSettingsStore.shared.heroPattern = newValue }
    }
    static var backgroundPattern: HoloPattern {
        get { HoloSettingsStore.shared.backgroundPattern }
        set { HoloSettingsStore.shared.backgroundPattern = newValue }
    }
    static var maskDeviationChance: Double {
        get { HoloSettingsStore.shared.maskDeviationChance }
        set { HoloSettingsStore.shared.maskDeviationChance = newValue }
    }
    static var depthMode: HoloDepthMode {
        get { HoloSettingsStore.shared.depthMode }
        set { HoloSettingsStore.shared.depthMode = newValue }
    }
    static var specularPower: Double {
        get { HoloSettingsStore.shared.specularPower }
        set { HoloSettingsStore.shared.specularPower = newValue }
    }
    static var cursorInfluence: Double {
        get { HoloSettingsStore.shared.cursorInfluence }
        set { HoloSettingsStore.shared.cursorInfluence = newValue }
    }
    static var tiltInfluence: Double {
        get { HoloSettingsStore.shared.tiltInfluence }
        set { HoloSettingsStore.shared.tiltInfluence = newValue }
    }
    static var parallaxStrength: Double {
        get { HoloSettingsStore.shared.parallaxStrength }
        set { HoloSettingsStore.shared.parallaxStrength = newValue }
    }
    static var showPlayButton: Bool {
        get { HoloSettingsStore.shared.showPlayButton }
        set { HoloSettingsStore.shared.showPlayButton = newValue }
    }
    static var hueCycles: Double {
        get { HoloSettingsStore.shared.hueCycles }
        set { HoloSettingsStore.shared.hueCycles = newValue }
    }
    static var reverseColorMode: HoloReverseColorMode {
        get { HoloSettingsStore.shared.reverseColorMode }
        set { HoloSettingsStore.shared.reverseColorMode = newValue }
    }
    static var reverseSolidColor: Color {
        get { HoloSettingsStore.shared.reverseSolidColor }
        set { HoloSettingsStore.shared.reverseSolidColor = newValue }
    }
    static var reverseRainbowIntensity: Double {
        get { HoloSettingsStore.shared.reverseRainbowIntensity }
        set { HoloSettingsStore.shared.reverseRainbowIntensity = newValue }
    }
    static var reverseTextureMode: HoloReverseTextureMode {
        get { HoloSettingsStore.shared.reverseTextureMode }
        set { HoloSettingsStore.shared.reverseTextureMode = newValue }
    }
    static var reverseTextureVariation: Bool {
        get { HoloSettingsStore.shared.reverseTextureVariation }
        set { HoloSettingsStore.shared.reverseTextureVariation = newValue }
    }
}

// Value snapshot of the holo settings that the static foil depends on.
// Equatable so `HoloFoilLayers` can be wrapped in `.equatable()` — when only
// the cursor moves, the settings are unchanged and SwiftUI skips re-evaluating
// the foil subtree entirely.
struct HoloSettingsSnapshot: Equatable {
    var titleIntensity: Double
    var chromeIntensity: Double
    var heroIntensity: Double
    var backgroundIntensity: Double
    var titlePattern: HoloPattern
    var chromePattern: HoloPattern
    var heroPattern: HoloPattern
    var backgroundPattern: HoloPattern
    var maskDeviationChance: Double
    var depthMode: HoloDepthMode
    var specularPower: Double
    var cursorInfluence: Double
    var tiltInfluence: Double
    var parallaxStrength: Double
    var hueCycles: Double
    // Reverse Holo colour-sheen configuration.
    var reverseColorMode: HoloReverseColorMode
    var reverseSolidColor: Color
    var reverseRainbowIntensity: Double
    // Reverse Holo foil source. `reverseTexturePattern` holds the (possibly
    // randomly chosen) bundled etch to use as the foil; nil means the built-in
    // generated lattice should be used.
    var reverseTextureMode: HoloReverseTextureMode
    var reverseTexturePattern: HoloPattern?
    // Variation (only meaningful when `reverseTextureMode == .random`): the
    // primary etch is tiled at `reverseTextureScale` (0.1…1.0×), and a second
    // etch (`reverseTexturePattern2`, when present) is composited on top with
    // `reverseTextureBlend2` at its own random scale.
    var reverseTextureScale: CGFloat
    var reverseTexturePattern2: HoloPattern?
    var reverseTextureScale2: CGFloat
    var reverseTextureBlend2: HoloTextureBlend
    // Per-card background median colour (r,g,b 0..1), used when
    // `reverseColorMode == .background`. Nil when unavailable.
    var backgroundMedianRGB: [Float]?
    // Per-launch, per-card randomized holo appearance. Non-nil only when the
    // card's `maskDeviationChance` roll succeeds; drives that card's per-zone
    // mask chance, intensity, and pattern (see `HoloCardRandomization`).
    var randomization: HoloCardRandomization?

    @MainActor
    init(from store: HoloSettingsStore) {
        self.titleIntensity = store.titleIntensity
        self.chromeIntensity = store.chromeIntensity
        self.heroIntensity = store.heroIntensity
        self.backgroundIntensity = store.backgroundIntensity
        self.titlePattern = store.titlePattern
        self.chromePattern = store.chromePattern
        self.heroPattern = store.heroPattern
        self.backgroundPattern = store.backgroundPattern
        self.maskDeviationChance = store.maskDeviationChance
        self.depthMode = store.depthMode
        self.specularPower = store.specularPower
        self.cursorInfluence = store.cursorInfluence
        self.tiltInfluence = store.tiltInfluence
        self.parallaxStrength = store.parallaxStrength
        self.hueCycles = store.hueCycles
        self.reverseColorMode = store.reverseColorMode
        self.reverseSolidColor = store.reverseSolidColor
        self.reverseRainbowIntensity = store.reverseRainbowIntensity
        self.reverseTextureMode = store.reverseTextureMode
        let cfg = Self.resolveReverseFoilConfig(
            mode: store.reverseTextureMode,
            variation: store.reverseTextureVariation,
            seed: HoloSettingsStore.launchSeed
        )
        self.reverseTexturePattern = cfg.pattern
        self.reverseTextureScale = cfg.scale
        self.reverseTexturePattern2 = cfg.pattern2
        self.reverseTextureScale2 = cfg.scale2
        self.reverseTextureBlend2 = cfg.blend2
        self.backgroundMedianRGB = nil
        self.randomization = nil
    }

    /// The card-specific snapshot. The background is always randomized
    /// (per-card, per-launch) — it leads the way. Each of the other sections
    /// (title/chrome/hero) separately rolls `maskDeviationChance`: on success
    /// it gets its own randomized mask; on failure it inherits the
    /// background's mask. Deterministic within a session — re-renders and
    /// scroll do not re-roll — but different every launch.
    @MainActor
    init(from store: HoloSettingsStore, romID: String) {
        self.init(from: store)
        let seed = HoloSettingsStore.launchSeed &+ stableSeed(romID)
        // Re-roll the random foil against the card-specific seed so each
        // reverse-holo card gets its own etch, scale, and (maybe) second etch.
        let cfg = Self.resolveReverseFoilConfig(
            mode: self.reverseTextureMode,
            variation: store.reverseTextureVariation,
            seed: seed
        )
        self.reverseTexturePattern = cfg.pattern
        self.reverseTextureScale = cfg.scale
        self.reverseTexturePattern2 = cfg.pattern2
        self.reverseTextureScale2 = cfg.scale2
        self.reverseTextureBlend2 = cfg.blend2
        self.randomization = HoloCardRandomization(
            seed: seed,
            deviationChance: Float(store.maskDeviationChance),
            variantWeights: store.variantWeights
        )
    }

    func regionIsActive(_ region: HoloRegion, maskPresent: Bool) -> Bool {
        guard maskPresent else { return false }
        switch region {
        case .title: return titleIntensity > 0.001
        case .chrome: return chromeIntensity > 0.001
        case .hero: return heroIntensity > 0.001
        case .background: return backgroundIntensity > 0.001
        }
    }

    /// Resolve the full Reverse Holo foil config for `.random` mode. All
    /// choices are derived deterministically from `seed` (stable per
    /// launch/rom, but varied across cards):
    ///   - `pattern`  — the primary bundled etch.
    ///   - `scale`    — tile scale 0.1…1.0× (1× = one copy; 0.1× = fine repeat).
    ///   - `pattern2` — a second etch composited on top (≈35% chance when
    ///                 variation is on), else nil.
    ///   - `scale2`   — that second etch's tile scale.
    ///   - `blend2`   — how the second etch is composited (overlay/multiply/screen).
    /// For `.generated` returns nil/identity so the built-in lattice is used.
    static func resolveReverseFoilConfig(
        mode: HoloReverseTextureMode,
        variation: Bool,
        seed: UInt64
    ) -> (pattern: HoloPattern?, scale: CGFloat, pattern2: HoloPattern?, scale2: CGFloat, blend2: HoloTextureBlend) {
        guard mode == .random else { return (nil, 1.0, nil, 1.0, .overlay) }
        let all = HoloPattern.allCases
        guard !all.isEmpty else { return (nil, 1.0, nil, 1.0, .overlay) }
        let p1 = all[Int(seed % UInt64(all.count))]
        let s1: CGFloat = variation ? CGFloat(0.1 + Double(seed % 1000) / 1000.0 * 0.9) : 1.0
        var p2: HoloPattern? = nil
        var s2: CGFloat = 1.0
        var blend2: HoloTextureBlend = .overlay

        // Second-pattern rules:
        //   - p1 may be ANY pattern.
        //   - p2, when present, may ONLY be a whitelisted pattern (galaxy /
        //     glitter).
        //   - galaxy / glitter NEVER get a second pattern, so if p1 is one of
        //     them, p2 stays nil.
        let whitelist = HoloPattern.secondPatternWhitelist
        let p1IsWhitelisted = whitelist.contains(p1)
        if variation, !p1IsWhitelisted, !whitelist.isEmpty, Int((seed >> 20) % 100) < 35 {
            p2 = whitelist[Int((seed >> 40) % UInt64(whitelist.count))]
            s2 = CGFloat(0.1 + Double((seed >> 10) % 1000) / 1000.0 * 0.9)
            blend2 = HoloTextureBlend.allCases[Int((seed >> 50) % UInt64(HoloTextureBlend.allCases.count))]
        }
        return (p1, s1, p2, s2, blend2)
    }
}

// Per-card, per-launch randomized holo appearance, seeded from the launch
// seed XOR the rom's FNV-1a hash. Every visible card rolls fresh values when
// the app starts, and the same card keeps them for the whole session (the
// roll is deterministic per launch+rom, so re-renders never flicker).
//
// The background is ALWAYS randomized — it leads the way with its own
// per-card mask. The other sections roll `deviationChance` to pick a mask:
// on success they get their own randomized mask, on failure they inherit the
// background's mask (same pattern/intensity, clipped to their own region).
// Hero is the exception: it never gets holo for now (0% mask chance, and it
// never inherits the background).
//
// When a section rolls its own mask, per user spec:
//   zone        mask chance  intensity range
//   background  100%         50–100%
//   chrome      100%         50–100%
//   title       80%          50–100%
//   hero        0%           20–60%
// A failed mask chance means the zone shows no holo at all (intensity 0).
struct HoloCardRandomization: Equatable {
    struct Zone: Equatable {
        let active: Bool
        let intensity: Double
        let pattern: HoloPattern
    }
    let background: Zone
    let chrome: Zone
    let title: Zone
    let hero: Zone
    /// Per-card holo variant (regularHolo, cosmosHolo, rainbowHolo, ...).
    /// Rolled from `HoloSettingsStore.variantWeights` at launch. Drives the
    /// shine-layer composition (`HoloVariantTileCache`) instead of the
    /// single-pattern texture overlay.
    let variant: HoloVariant

    init(seed: UInt64, deviationChance: Float, variantWeights: [HoloVariant: Double]) {
        var rng = SplitMix64(seed: seed)

        func roll(chance: Float, range: ClosedRange<Double>) -> Zone {
            let active = rng.nextFloat() < chance
            let intensity = active
                ? range.lowerBound + Double(rng.nextFloat()) * (range.upperBound - range.lowerBound)
                : 0
            let all = HoloPattern.allCases
            let pattern = all[Int(rng.next() % UInt64(all.count))]
            return Zone(active: active, intensity: intensity, pattern: pattern)
        }

        // The background always rolls its own mask.
        let background = roll(chance: 1.00, range: 0.50...1.00)
        self.background = background

        // Each other section rolls `deviationChance` to get its own mask;
        // otherwise it inherits the background's mask.
        func deviated(_ chance: Float, _ range: ClosedRange<Double>) -> Zone {
            if rng.nextFloat() < deviationChance {
                return roll(chance: chance, range: range)
            }
            return background
        }

        self.chrome = deviated(1.00, 0.50...1.00)
        self.title = deviated(0.80, 0.50...1.00)
        // Hero never gets holo for now: always rolled with 0% mask chance, and
        // never inherits the background's mask.
        self.hero = roll(chance: 0.00, range: 0.20...0.60)
        self.variant = HoloVariantRoller.pick(rng: &rng, weights: variantWeights)
    }

    func active(_ region: HoloRegion) -> Bool {
        switch region {
        case .background: return background.active
        case .chrome: return chrome.active
        case .title: return title.active
        case .hero: return hero.active
        }
    }

    func intensity(_ region: HoloRegion) -> Double {
        switch region {
        case .background: return background.intensity
        case .chrome: return chrome.intensity
        case .title: return title.intensity
        case .hero: return hero.intensity
        }
    }

    func pattern(_ region: HoloRegion) -> HoloPattern {
        switch region {
        case .background: return background.pattern
        case .chrome: return chrome.pattern
        case .title: return title.pattern
        case .hero: return hero.pattern
        }
    }
}

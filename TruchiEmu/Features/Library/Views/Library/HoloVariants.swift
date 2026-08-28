import SwiftUI
import AppKit

// Source-faithful holo variants ported from simeydotme/pokemon-cards-css
// (https://github.com/simeydotme/pokemon-cards-css). Each variant defines a
// distinct visual recipe — gradient definition, blend-mode stack, filter
// values, and pointer-driven modulation — faithful to the source's
// `.card__shine`/`.card__glare` rules for that rarity. The renderer below
// draws a `2w*2h` tile per variant that is then masked to each region
// (background/title/chrome/hero) and pointer-reacted (brightness from
// pointer-from-center, hue rotation, sweep band).
//
// The user picks a variant per card via weighted randomization configured in
// HoloSettingsStore.variantWeights. Each weight is a 0..1 share; per-card
// the variant is chosen by rolling against the weight distribution.
enum HoloVariant: String, CaseIterable, Identifiable {
    case regularHolo     // regular-holo.css — diagonal rainbow stripes (Holofoil Rare)
    case rainbowHolo     // rainbow-holo.css — rainbow + glitter, 2 layers (Rainbow Rare)
    case reverseHolo     // reverse-holo.css — full-card foil, inverted mask (Reverse Holo)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regularHolo: return "Holofoil Rare"
        case .rainbowHolo: return "Rainbow Rare"
        case .reverseHolo: return "Reverse Holo"
        }
    }

    /// Localized display name (keyed `holo.variant.<rawValue>`). Falls back to
    /// the English `displayName` when no translation is present. Used in the
    /// Settings → Holo → Variant Weights section.
    var localizedName: String {
        let key = "holo.variant.\(rawValue)"
        let translated = LocalizationManager.shared.localized(key)
        return translated == key ? displayName : translated
    }

    /// Short, one-line visual description for the variant. Keyed
    /// `holo.variantDescription.<rawValue>`; falls back to a stable English
    /// string defined in-code so the UI is never blank.
    var localizedDescription: String {
        let key = "holo.variantDescription.\(rawValue)"
        let translated = LocalizationManager.shared.localized(key)
        if translated != key { return translated }
        return defaultDescription
    }

    private var defaultDescription: String {
        switch self {
        case .regularHolo: return "Diagonal rainbow stripe holo foil (Regular Holo)."
        case .rainbowHolo: return "Rainbow + glitter, two stacked layers."
        case .reverseHolo: return "Full-card pattern foil with a moving silver/coloured sheen."
        }
    }
}

// One rainbow stripe in a repeating-linear-gradient. The source variants use
// these extensively (6-7 color stops repeated across the card).
struct HoloStripePalette {
    let colors: [Color]
    /// Gradient angle in degrees (0 = vertical, 90 = horizontal), matching the
    /// source's `repeating-linear-gradient(<deg>, ...)` convention.
    let angle: Double

    static let regularRainbow = HoloStripePalette(
        colors: [
            Color(red: 0.788, green: 0.161, blue: 0.945),  // violet
            Color(red: 0.051, green: 0.741, blue: 0.914),  // blue
            Color(red: 0.129, green: 0.914, blue: 0.522),  // green
            Color(red: 0.933, green: 0.875, blue: 0.063),  // yellow
            Color(red: 0.973, green: 0.055, blue: 0.208),  // red
        ],
        angle: 110
    )

    static let cosmosRainbow = HoloStripePalette(
        colors: [
            Color(hue: 0.147, saturation: 0.65, brightness: 0.60),
            Color(hue: 0.258, saturation: 0.56, brightness: 0.50),
            Color(hue: 0.488, saturation: 0.54, brightness: 0.49),
            Color(hue: 0.633, saturation: 0.59, brightness: 0.55),
            Color(hue: 0.783, saturation: 0.60, brightness: 0.55),
            Color(hue: 0.906, saturation: 0.59, brightness: 0.51),
        ],
        angle: 82
    )

    static let rainbowRare = HoloStripePalette(
        colors: [
            Color(hue: 0.000, saturation: 0.57, brightness: 0.37),
            Color(hue: 0.111, saturation: 0.53, brightness: 0.39),
            Color(hue: 0.250, saturation: 0.60, brightness: 0.35),
            Color(hue: 0.500, saturation: 0.60, brightness: 0.35),
            Color(hue: 0.583, saturation: 0.60, brightness: 0.35),
            Color(hue: 0.583, saturation: 0.57, brightness: 0.39),
            Color(hue: 0.778, saturation: 0.55, brightness: 0.31),
        ],
        angle: -30
    )

    /// Metallic silver gradient — shiny-rare / v-full-art. Source defines a
    /// 0deg rainbow + a 133deg silver pattern with dark stripes. The silver
    /// stripe palette below is used for the 133deg layer.
    static let metallicSilver = HoloStripePalette(
        colors: [
            Color(red: 0.055, green: 0.082, blue: 0.180),  // #0e152e (dark)
            Color(hue: 0.5, saturation: 0.10, brightness: 0.60),
            Color(hue: 0.5, saturation: 0.29, brightness: 0.66),
            Color(hue: 0.5, saturation: 0.10, brightness: 0.60),
            Color(red: 0.055, green: 0.082, blue: 0.180),
            Color(red: 0.055, green: 0.082, blue: 0.180),
        ],
        angle: 133
    )
}

// CSS-style filter values applied to the rendered shine tile. Source uses
// `filter: brightness(N) contrast(N) saturate(N)`. Values are non-additive
// multipliers (matching CSS, not SwiftUI's `.brightness(N)` which adds).
struct HoloFilterRecipe {
    var brightness: Double
    var contrast: Double
    var saturation: Double

    init(brightness: Double, contrast: Double, saturation: Double) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
    }

    static let regularHolo = HoloFilterRecipe(brightness: 1.1, contrast: 1.1, saturation: 1.2)
    static let cosmosBase   = HoloFilterRecipe(brightness: 1.0, contrast: 1.0, saturation: 0.8)
    static let cosmosMid    = HoloFilterRecipe(brightness: 1.25, contrast: 1.75, saturation: 0.8)
    static let cosmosTop    = HoloFilterRecipe(brightness: 1.25, contrast: 1.75, saturation: 0.8)
    static let rainbowBase  = HoloFilterRecipe(brightness: 1.0, contrast: 1.0, saturation: 1.0)
    static let radiantBase  = HoloFilterRecipe(brightness: 0.5, contrast: 2.0, saturation: 1.75)
    static let radiantTop   = HoloFilterRecipe(brightness: 0.6, contrast: 3.0, saturation: 2.0)
    static let amazingBase  = HoloFilterRecipe(brightness: 1.0, contrast: 1.0, saturation: 0.9)
    static let shinyBase    = HoloFilterRecipe(brightness: 0.4, contrast: 1.4, saturation: 2.25)
    static let shinyTop     = HoloFilterRecipe(brightness: 0.8, contrast: 1.5, saturation: 1.25)
    static let vFullArtBase = HoloFilterRecipe(brightness: 0.4, contrast: 1.4, saturation: 2.25)
    static let vFullArtTop  = HoloFilterRecipe(brightness: 0.8, contrast: 1.5, saturation: 1.25)
    static let secretBase   = HoloFilterRecipe(brightness: 1.0, contrast: 1.0, saturation: 1.0)
    static let reverseBase  = HoloFilterRecipe(brightness: 0.55, contrast: 1.5, saturation: 1.0)
}

// A pointer-modulated opacity rule: `opacity: calc(var(--card-opacity) * (0.25 + var(--pointer-from-center))).
struct HoloOpacityRecipe {
    /// Multiplier applied to the user's `card-opacity` (= our holoIntensity).
    var cardMultiplier: Double
    /// Constant offset added to pointer-from-center before multiplication.
    var fromCenterOffset: Double = 0
    /// Multiplier on pointer-from-center. If 0, opacity is purely card-driven.
    var fromCenterScale: Double = 0

    func opacity(holoIntensity: Double, pointerFromCenter: Double) -> Double {
        let base = cardMultiplier * (fromCenterOffset + fromCenterScale * pointerFromCenter)
        return base * holoIntensity
    }

    static let regularHolo  = HoloOpacityRecipe(cardMultiplier: 0.8)
    static let cosmosGlare  = HoloOpacityRecipe(cardMultiplier: 1.0, fromCenterOffset: 0.25, fromCenterScale: 1.0)
    static let radiantBase  = HoloOpacityRecipe(cardMultiplier: 1.0)
    static let shinyBase    = HoloOpacityRecipe(cardMultiplier: 1.0, fromCenterScale: 1.0)
    static let rainbowBase  = HoloOpacityRecipe(cardMultiplier: 1.0)
    static let vFullArtBase = HoloOpacityRecipe(cardMultiplier: 1.0)
    static let reverseGlare = HoloOpacityRecipe(cardMultiplier: 1.5, fromCenterScale: -1.0)
}

// One shine layer: a rainbow stripe palette + filter + blend mode. Variants
// compose 1-3 of these stacked. The renderer iterates the layers and draws
// each into a shared ImageRenderer.
struct HoloShineLayer {
    let palette: HoloStripePalette
    let filter: HoloFilterRecipe
    /// SwiftUI blend mode (e.g. `.colorDodge`, `.overlay`, `.multiply`,
    /// `.hardLight`, `.luminosity`). Equivalent to the source's `mix-blend-mode`.
    let blendMode: BlendMode
    /// Repeating period as a fraction of the card width. Source uses
    /// `background-size` ratios like 200% 700%, 400% 400%.
    let sizeX: CGFloat
    let sizeY: CGFloat
    /// Initial position (0..1) of the gradient before pointer parallax. Source
    /// uses 50% 50% with pointer-driven offset.
    let basePositionX: CGFloat
    let basePositionY: CGFloat
    /// How strongly pointer-from-left/right shifts the gradient's x position.
    /// Source uses values like * 1.5 or * 2.6.
    let parallaxX: CGFloat
    let parallaxY: CGFloat
    /// For radial layers (cosmos glare, radiant base): the cursor-centered
    /// radial gradient. When set, `palette` is ignored and a radial gradient
    /// at the pointer is drawn instead.
    let radial: HoloRadialRecipe?

    static func regularHolo(palette: HoloStripePalette = .regularRainbow,
                            angle: Double = 110) -> HoloShineLayer {
        HoloShineLayer(
            palette: HoloStripePalette(colors: palette.colors, angle: angle),
            filter: .regularHolo,
            blendMode: .colorDodge,
            sizeX: 4.0, sizeY: 4.0,
            basePositionX: 0.5, basePositionY: 0.5,
            parallaxX: 2.6, parallaxY: 3.5,
            radial: nil
        )
    }
}

// Radial gradient at the cursor — used for cosmos glare, radiant base, etc.
struct HoloRadialRecipe {
    /// Stops: (location 0..1, RGBA color).
    let stops: [(CGFloat, Color)]
    /// Optional blend mode for the radial layer (vs the whole-layer blendMode).
    /// nil means use the layer's blendMode.
    let blendMode: BlendMode?

    static let cosmosCenterGlow = HoloRadialRecipe(
        stops: [
            (0.05, Color(hue: 0.5, saturation: 1.0, brightness: 0.95).opacity(0.5)),
            (0.40, Color(hue: 0.5, saturation: 0.14, brightness: 0.57).opacity(0.3)),
            (1.30, Color.black),
        ],
        blendMode: nil
    )

    static let radiantGlow = HoloRadialRecipe(
        stops: [
            (0.20, Color(white: 0.95)),
            (1.30, Color.clear),
        ],
        blendMode: nil
    )

    static let cosmosGlare = HoloRadialRecipe(
        stops: [
            (0.05, Color(hue: 0.567, saturation: 1.0, brightness: 0.95).opacity(0.8)),
            (1.50, Color(hue: 0.694, saturation: 0.15, brightness: 0.20)),
        ],
        blendMode: nil
    )
}

// One full variant recipe — the layer stack that produces the shine. The
// renderer iterates the layers from bottom to top.
struct HoloVariantRecipe {
    let shineLayers: [HoloShineLayer]
    let glare: HoloGlareRecipe
}

// Cursor-centered radial — the white "light" highlight that follows the
// pointer. Source calls this `.card__glare`.
struct HoloGlareRecipe {
    let stops: [(CGFloat, Color)]
    let filter: HoloFilterRecipe
    let blendMode: BlendMode
    let opacity: HoloOpacityRecipe

    static let regularGlare = HoloGlareRecipe(
        stops: [
            (0.0,  Color.white.opacity(0.8)),
            (0.20, Color.white.opacity(0.65)),
            (0.90, Color.black.opacity(0.5)),
        ],
        filter: HoloFilterRecipe(brightness: 0.85, contrast: 1.0, saturation: 1.0),
        blendMode: .overlay,
        opacity: .regularHolo
    )

    static let cosmosGlare = HoloGlareRecipe(
        stops: [
            (0.05, Color(hue: 0.567, saturation: 1.0, brightness: 0.95).opacity(0.8)),
            (1.50, Color(hue: 0.694, saturation: 0.15, brightness: 0.20)),
        ],
        filter: HoloFilterRecipe(brightness: 0.75, contrast: 2.0, saturation: 2.0),
        blendMode: .overlay,
        opacity: .cosmosGlare
    )

    static let radiantGlare = HoloGlareRecipe(
        stops: [
            (0.0,  Color.white.opacity(0.33)),
            (1.10, Color(white: 0.25)),
        ],
        filter: HoloFilterRecipe(brightness: 1.0, contrast: 1.5, saturation: 1.0),
        blendMode: .hardLight,
        opacity: .radiantBase
    )

    static let shinyGlare = HoloGlareRecipe(
        stops: [
            (0.0,  Color.white),
            (1.50, Color(hue: 0.889, saturation: 0.05, brightness: 0.15)),
        ],
        filter: HoloFilterRecipe(brightness: 1.2, contrast: 1.0, saturation: 0.7),
        blendMode: .multiply,
        opacity: .shinyBase
    )

    static let vFullArtGlare = HoloGlareRecipe(
        stops: [
            (0.05, Color(white: 0.75)),
            (0.60, Color(hue: 0.555, saturation: 0.05, brightness: 0.35)),
            (1.50, Color(hue: 0.889, saturation: 0.40, brightness: 0.10)),
        ],
        filter: HoloFilterRecipe(brightness: 1.0, contrast: 1.2, saturation: 1.0),
        blendMode: .hardLight,
        opacity: HoloOpacityRecipe(cardMultiplier: 0.75)
    )
}

extension HoloVariant {
    /// Source-faithful recipe for this variant. Drives the renderer.
    var recipe: HoloVariantRecipe {
        switch self {
        case .regularHolo:
            return HoloVariantRecipe(
                shineLayers: [
                    HoloShineLayer.regularHolo(),
                    HoloShineLayer(
                        palette: HoloStripePalette(colors: HoloStripePalette.regularRainbow.colors, angle: 90),
                        filter: HoloFilterRecipe(brightness: 1.15, contrast: 1.1, saturation: 1.0),
                        blendMode: .hardLight,
                        sizeX: 1.0, sizeY: 1.0,
                        basePositionX: 0.5, basePositionY: 0.5,
                        parallaxX: 0, parallaxY: 0,
                        radial: nil
                    ),
                ],
                glare: .regularGlare
            )

        case .rainbowHolo:
            // Rainbow-rare: a -45deg linear gradient at the top, glitter
            // texture in the middle, and a -30deg repeating rainbow at the
            // bottom. The linear-gradient layer uses luminosity blend mode.
            return HoloVariantRecipe(
                shineLayers: [
                    HoloShineLayer(
                        palette: HoloStripePalette(colors: [
                            Color(hue: 0.000, saturation: 0.57, brightness: 0.37),
                            Color(hue: 0.500, saturation: 0.60, brightness: 0.35),
                        ], angle: -45),
                        filter: HoloFilterRecipe(brightness: 1.0, contrast: 1.0, saturation: 1.0),
                        blendMode: .luminosity,
                        sizeX: 2.0, sizeY: 2.0,
                        basePositionX: 0.5, basePositionY: 0.5,
                        parallaxX: 0.5, parallaxY: 0.5,
                        radial: nil
                    ),
                    HoloShineLayer(
                        palette: .rainbowRare,
                        filter: HoloFilterRecipe(
                            brightness: 1.0, contrast: 2.2, saturation: 0.75
                        ),
                        blendMode: .softLight,
                        sizeX: 4.0, sizeY: 4.0,
                        basePositionX: 0.5, basePositionY: 0.5,
                        parallaxX: 0.5, parallaxY: 0.5,
                        radial: nil
                    ),
                ],
                glare: .regularGlare
            )

        case .reverseHolo:
            // Reverse holo: full-card foil. The pattern covers the whole card
            // (per-region masks) and a silver/metallic sheen reflects a moving
            // specular band — the "different parts of the pattern light up as
            // the card moves" read. The Holo settings let the user swap the
            // sheen colour between a solid pick, rainbow, and the card's own
            // background colour.
            return HoloVariantRecipe(
                shineLayers: [
                    HoloShineLayer(
                        palette: .metallicSilver,
                        filter: HoloFilterRecipe(brightness: 0.5, contrast: 1.6, saturation: 1.0),
                        blendMode: .hardLight,
                        sizeX: 3.0, sizeY: 3.0,
                        basePositionX: 0.5, basePositionY: 0.5,
                        parallaxX: 1.0, parallaxY: 1.0,
                        radial: nil
                    ),
                ],
                glare: HoloGlareRecipe(
                    stops: [
                        (0.0, Color.white.opacity(0.8)),
                        (1.0, Color.white.opacity(0.0)),
                    ],
                    filter: HoloFilterRecipe(brightness: 0.9, contrast: 1.5, saturation: 1.0),
                    blendMode: .overlay,
                    opacity: .reverseGlare
                )
            )

        }
    }

    /// Fixed, source-faithful foil texture for this variant. The WKWebView CSS
    /// path is deterministic — every card of a variant foils identically — but
    /// the native SwiftUI path used to pick a RANDOM `HoloPattern` per zone per
    /// card. Pinning the pattern here removes that per-card randomness so the
    /// swift render reads like the web render. Stands in for the CSS
    /// `--foil`/grating of each rarity.
    var sourceFoilPattern: HoloPattern {
        switch self {
        case .regularHolo:  return .wave
        case .rainbowHolo:  return .glitter
        case .reverseHolo:  return .stylish
        }
    }

    /// Deterministic baseline holo strength (0…1) for this variant, approximating
    /// the CSS variant's overall foil brightness. The native path used to roll a
    /// fully random 0.5…1.0 intensity per card; centering on this baseline with a
    /// small ±jitter keeps a subtle per-card variance without the wild swing.
    var sourceIntensity: Double {
        switch self {
        case .regularHolo:  return 0.70
        case .rainbowHolo:  return 0.60
        case .reverseHolo:  return 0.70
        }
    }
}

// Weighted selection: given a [variant: weight] map, pick one variant by
// rolling against the weights. Weights are normalized internally so the sum
// does not need to be 1.0. A weight of 0 excludes the variant.
enum HoloVariantRoller {
    static func pick(rng: inout SplitMix64, weights: [HoloVariant: Double]) -> HoloVariant {
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return .regularHolo }
        let roll = Double(rng.nextFloat()) * total
        var cumulative: Double = 0
        for variant in HoloVariant.allCases {
            cumulative += weights[variant] ?? 0
            if roll < cumulative { return variant }
        }
        return HoloVariant.allCases.last ?? .regularHolo
    }
}



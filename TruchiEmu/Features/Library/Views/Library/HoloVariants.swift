import SwiftUI
import AppKit

// Holographic foil variants. Each variant is a COLOURWAY of one shared
// physical foil model: an etched diffraction sheet lit by a moving light
// (see `HoloFoilLight.metal`). A variant only changes the metal tint, the
// spectrum spread, the specular sharpness, the etch depth and the etch
// pattern — the light model itself is identical for every card, so the grid
// reads as one material.
//
// The user picks a variant per card via weighted randomization configured in
// HoloSettingsStore.variantWeights. Each weight is a 0..1 share; per-card
// the variant is chosen by rolling against the weight distribution.
enum HoloVariant: String, CaseIterable, Identifiable {
    case regularHolo     // silver sheet, narrow rainbow bands (Holofoil Rare)
    case rainbowHolo     // fine glitter flake, wide spectrum (Rainbow Rare)
    case reverseHolo     // full-card silver lattice with a moving ray

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
        case .regularHolo: return "Silver etched sheet with narrow rainbow bands."
        case .rainbowHolo: return "Fine glitter foil with a wide moving spectrum."
        case .reverseHolo: return "Full-card metallic lattice with a moving ray."
        }
    }

    /// Fixed etch texture for this variant. The bundled `holo_*.png` sheets are
    /// the diffraction grating the light reflects off.
    var sourceFoilPattern: HoloPattern {
        switch self {
        case .regularHolo:  return .wave
        case .rainbowHolo:  return .glitter
        case .reverseHolo:  return .stylish
        }
    }

    /// Deterministic baseline foil strength (0…1) for this variant.
    var sourceIntensity: Double {
        switch self {
        case .regularHolo:  return 0.70
        case .rainbowHolo:  return 0.60
        case .reverseHolo:  return 0.70
        }
    }
}

// One foil colourway. Everything the renderer needs to describe the material:
// what the metal is, how much spectrum it throws, how sharp the highlight is,
// how deep the etch relief reads and how much of the sheet foils.
struct HoloFoilColourway: Equatable {
    /// Metal base colour (silver, gold, the user's solid tint, ...).
    var tint: Color = Color(red: 0.93, green: 0.93, blue: 0.96)
    /// 0 = pure metal, 1 = full thin-film spectrum in the reflections.
    var saturation: Double = 0.72
    /// How far the hue travels across the relief. Higher = more colour bands.
    var hueSpread: Double = 0.30
    /// Blinn-Phong exponent for the specular glint.
    var specularPower: Double = 32
    /// Etch relief depth fed to the normal derivation (0…1).
    var relief: Double = 0.55
    /// Foil coverage of the flat (non-etched) parts of the sheet (0…1).
    var coverage: Double = 0.06
    /// Edge coverage gain: how strongly cell edges light up (0…1).
    var edgeGain: Double = 0.35
    /// Etch cell size as a fraction of the card width. Smaller = finer grain.
    var etchScale: CGFloat = 0.18
    /// Strength of the hot specular glint on top of the sheet.
    var glare: Double = 0.8
    /// Static hue offset (per-card variation for `.random` reverse holo).
    var hueOffset: Double = 0
    /// Overall foil strength multiplier for this card.
    var intensity: Double = 1
}

extension HoloVariant {
    /// The colourway for this variant, resolving the user's tunables.
    func colourway(settings: HoloSettingsSnapshot, hueOffset: Double = 0) -> HoloFoilColourway {
        // The user's relief slider scales every variant's etch depth, so the
        // slider always has a visible effect whichever variant a card rolled.
        let reliefScale = 0.30 + 0.70 * max(0, min(1, settings.parallaxStrength))

        switch self {
        case .regularHolo:
            // Classic Holofoil Rare: a silver sheet with a narrow rainbow
            // band that rakes across it. The three user sliders in Settings →
            // Holo → Holofoil Rare map to strength, etch density and glare.
            var c = HoloFoilColourway()
            c.saturation = 0.72
            c.hueSpread = 0.30
            c.specularPower = settings.specularPower
            c.relief = 0.55 * reliefScale
            c.coverage = 0.05
            c.edgeGain = 0.35
            c.etchScale = 0.18 / max(0.25, settings.holofoilRareScanlineDensity)
            c.glare = settings.holofoilRareGlare
            c.hueOffset = hueOffset
            c.intensity = settings.holofoilRareIntensity
            return c

        case .rainbowHolo:
            // Rainbow Rare: fine glitter flake. The etch is much denser, the
            // spectrum much wider, and the highlight sharper, so the whole
            // sheet sparkles instead of showing one broad band.
            var c = HoloFoilColourway()
            c.saturation = 0.95
            c.hueSpread = 0.55
            c.specularPower = min(64, settings.specularPower * 1.2)
            c.relief = 0.85 * reliefScale
            c.coverage = 0.10
            c.edgeGain = 0.45
            c.etchScale = 0.10
            c.glare = 0.9
            c.hueOffset = hueOffset
            c.intensity = 1
            return c

        case .reverseHolo:
            // Reverse Holo: the whole card is foil. Coarser lattice, broader
            // highlight (lower specular power) and full-sheet coverage, with
            // the colour driven by the Reverse Holo colour mode.
            var c = HoloFoilColourway()
            c.specularPower = 22
            c.relief = 0.80 * reliefScale
            c.coverage = 0.30
            c.edgeGain = 0.30
            c.etchScale = 0.22
            c.glare = 0.7
            c.hueOffset = hueOffset
            c.intensity = 1
            switch settings.reverseColorMode {
            case .solid:
                c.tint = settings.reverseSolidColor
                c.saturation = 0.08
            case .background:
                if let rgb = settings.backgroundMedianRGB, rgb.count == 3 {
                    c.tint = Color(
                        red: 0.55 + 0.45 * Double(rgb[0]),
                        green: 0.55 + 0.45 * Double(rgb[1]),
                        blue: 0.55 + 0.45 * Double(rgb[2])
                    )
                }
                c.saturation = 0.08
            case .rainbow, .random:
                c.tint = Color(white: 0.97)
                c.saturation = 0.35 + 0.65 * settings.reverseRainbowIntensity
                c.hueSpread = 0.45
            }
            return c
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

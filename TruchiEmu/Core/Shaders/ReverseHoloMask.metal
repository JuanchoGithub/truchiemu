#include <metal_stdlib>
using namespace metal;

// Reverse Holo foil mask tone curve.
//
// Real holographic paper is transparent in the deepest shadows (no light to
// reflect, so no foil) and in blown-out highlights (overexposed -> white, no
// colour), and shows the iridescent foil most strongly in the bright mid-tones.
//
// This remaps the greyscale foil-etch luminance `v` (0..1) to an alpha that:
//   - is 0 at v = 0 (max dark) and at v = 1 (max bright),
//   - rises progressively with brightness (0.12 -> 0.50),
//   - peaks in a narrow bright-mid band and falls off quickly at max bright,
//   - never exceeds `peakAlpha`, so the foil reads as a sheen and the card
//     art always shows through (real holo is never fully opaque).
//
// Applied via `.colorEffect` to the SwiftUI foil luminance mask, so every
// Reverse Holo use (rainbow hue, moving sweep, and the foil etch itself) shares
// the same paper-like response to the underlying etch brightness.
[[ stitchable ]]
half4 reverseHoloMask(float2 position, half4 color) {
    // Luminance of the etch mask (greyscale, so rgb == the mask strength).
    // Using luminance (not alpha) is robust whether the mask encodes its
    // strength in the alpha channel or in RGB brightness.
    float v = saturate(dot(float3(color.rgb), float3(0.299, 0.587, 0.114)));

    constexpr float peakAlpha = 0.55;                // max foil opacity (a sheen)
    float lo = smoothstep(0.12, 0.50, v);            // progressive rise with brightness
    float hi = 1.0 - smoothstep(0.60, 0.90, v);      // quick falloff at max bright
    float a = peakAlpha * lo * hi;

    // Pre-multiplied opaque white at alpha `a`; only the alpha drives the mask.
    return half4(half3(a), half(a));
}
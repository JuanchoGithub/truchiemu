#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// ============================================================
// HoloFoilLight — physically-lit holographic foil (layerEffect)
//
// The input layer is a grayscale ETCH texture (a bundled `holo_*.png`
// diffraction pattern, tiled). Its luminance is the foil's height field:
// every etched cell catches the light, the flat gaps between cells do not.
//
// The shader:
//   1. derives a per-pixel normal from the etch via finite differences
//      (the same model as `HoloBump.metal`, but in-process — no render
//      target, no CPU readback, no per-card Metal renderer),
//   2. lights it with a single directional light that the host moves from
//      the pointer position and the card tilt (Blinn-Phong specular),
//   3. tints the reflection with a thin-film interference spectrum whose
//      hue depends on the angle between the normal and the light, so the
//      rainbow bands slide across the etch as the card turns — the way a
//      real foil behaves. The foil stays mostly silver; only the specular
//      bands carry colour.
//   4. gates visibility with a "paper" coverage curve: the foil shows on
//      the etched structure and fades out in the flat areas, so the box
//      art always reads through it.
//
// Output is premultiplied. The host composites it with `.screen`, which
// can only lighten the art (a holo card never darkens the print).
// ============================================================

// Smooth full-spectrum ramp (violet -> blue -> green -> yellow -> red).
static inline float3 holoSpectrum(float t) {
    t = fract(t);
    return 0.5 + 0.5 * cos(6.28318530718 * (t + float3(0.0, 0.333333, 0.666667)));
}

// Linear luminance of a premultiplied sample. The etch tiles are opaque, so
// the alpha channel is always 1 and this is a straight luma.
static inline float holoLuma(half4 c) {
    return dot(float3(c.rgb), float3(0.2126, 0.7152, 0.0722));
}

[[ stitchable ]]
half4 holoFoilLight(
    float2 position,
    SwiftUI::Layer layer,
    // xy: light direction in tangent space (-1..1), z: specular exponent,
    // w: overall foil intensity (per-region).
    float4 lightSpec,
    // x: hue phase (thin-film spectrum offset), y: hue spread across the
    // relief, z: spectrum saturation (0 = pure metal), w: relief depth.
    float4 look,
    // xy: layer size in points, z: base coverage, w: edge coverage gain.
    float4 surface,
    // x: glare strength (the hot specular glint on top of the sheet).
    float4 extra,
    // Metal tint. Pure silver unless the variant is a solid-colour foil.
    half4 tint
) {
    float2 size = max(surface.xy, float2(1.0));
    float2 uv = position / size;

    // --- 1. Height field + normal -------------------------------------
    // One-point central differences. The etch tiles repeat every ~50-80
    // points, so a single point resolves the cell edges without aliasing.
    float h0 = holoLuma(layer.sample(position));
    float hR = holoLuma(layer.sample(position + float2(1.0, 0.0)));
    float hL = holoLuma(layer.sample(position - float2(1.0, 0.0)));
    float hD = holoLuma(layer.sample(position + float2(0.0, 1.0)));
    float hU = holoLuma(layer.sample(position - float2(0.0, 1.0)));

    float2 grad = float2(hR - hL, hD - hU) * 0.5;
    float depth = max(look.w, 0.0) * 26.0;
    float3 n = normalize(float3(-grad.x * depth, -grad.y * depth, 1.0));

    // --- 2. Lighting ---------------------------------------------------
    float3 L = normalize(float3(lightSpec.xy, 1.0));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 Hv = normalize(L + V);

    float ndl = saturate(dot(n, L));
    float ndh = saturate(dot(n, Hv));
    float spec = pow(ndh, max(lightSpec.z, 1.0));
    float fresnel = pow(1.0 - saturate(dot(n, V)), 4.0);

    // --- 3. Thin-film interference -------------------------------------
    // Hue follows the angle between the relief normal and the light, plus
    // the viewing angle across the sheet. This is what makes the rainbow
    // bands travel as the foil tilts instead of sitting still on the art.
    float angle = dot(n, L);
    float hue = look.x
              + angle * look.y * 1.4
              + (uv.x - 0.5) * 0.22
              + (uv.y - 0.5) * 0.14;

    float3 spectral = holoSpectrum(hue);
    float3 metal = mix(float3(tint.rgb), spectral, saturate(look.z));

    // Broad metallic response + tight specular glint + rim sheen.
    float glare = max(extra.x, 0.0);
    float3 foil = metal * (0.12 + 0.50 * ndl)
                + metal * spec * 1.30 * (0.45 + 0.85 * glare)
                + float3(1.0) * spec * spec * 0.70 * (0.30 + 1.10 * glare)
                + metal * fresnel * 0.40;

    // --- 4. Paper coverage --------------------------------------------
    // Bright etch areas foil; cell edges foil strongly; flat gaps stay
    // clear so the printed art shows through. `surface.z` lifts the whole
    // sheet for full-surface foils (reverse holo).
    float gradMag = length(grad);
    float coverage = saturate(
        surface.z
        + smoothstep(0.05, 0.60, h0) * 0.75
        + gradMag * surface.w * 8.0
    );

    float alpha = saturate(coverage * lightSpec.w);
    return half4(half3(clamp(foil, 0.0, 1.0) * alpha), half(alpha));
}

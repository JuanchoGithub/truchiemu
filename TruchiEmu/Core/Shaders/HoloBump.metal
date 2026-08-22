#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// HoloBump Shader — true surface-relief hologram
//
// Per-fragment: derive a tangent-space normal from the holo pattern mask
// itself via finite-differences (no separate normal-map pass needed),
// transform into world space via the card's tilt rotation, compute a
// Blinn-Phong specular highlight against a light direction derived from
// cursor + tilt, and modulate an iridescent rainbow (synthesized at shader
// time from the source CSS palette violet→red) by a relief-shaded base so
// the whole masked foil glows. Output is the shine at full alpha; the host
// SwiftUI tree composes it over the artwork with
// `.compositingGroup().blendMode(.colorDodge)` — same as the parallax path.
//
// Vertex function emits a fullscreen triangle covering the artwork rect.
// The host code passes `artRect` so the vertex shader maps UVs from
// artwork-local space (0..1, top-left origin) into clip space.
// ============================================================

struct HoloBumpUniforms {
    // 3x3 row-major rotation matrix: rotates the tangent-space normal into
    // world (card-local) space. The card's 3D tilt (Rx then Ry) is reduced
    // to this 3x3 by the host. The bump normal map is baked in XY tangent
    // space; Z points out of the card surface.
    float4x4 tiltMatrix;
    // Light direction in card-local space (after tilt). Default `(0, 0, 1)`
    // (light directly above the card); host offsets it by (cursorX - 0.5,
    // cursorY - 0.5, 0) scaled by `cursorInfluence`. Pre-normalized.
    float3 lightDir;
    // Pointer X (0..1, left-to-right), Y (0..1, top-to-bottom), normalised
    // 0..1 over the artwork frame.
    float pointerX;
    float pointerY;
    // 0..1: how strongly cursor offset adds to the light direction.
    float cursorInfluence;
    // 0..1: how strongly card tilt adds to the light direction (rotates
    // the rest light vector with the card). Host passes a derived unit
    // vector after applying tiltMatrix to (0,0,1) and re-normalizing.
    float tiltInfluence;
    // Blinn-Phong specular exponent. Higher = sharper highlights. The
    // slider in settings maps to 16..64. Default 32.
    float specularPower;
    // Global intensity multiplier. Matches `intensity` from the existing
    // HoloFoilLayers region loop (per-region slider, randomised).
    float intensity;
    // Iridescent rainbow phase shift driven by cursor (degrees). The
    // rainbow pattern slides across the card as the user moves the mouse
    // — same feel as the source repo's CSS hue rotation.
    float hueShiftDegrees;
    // Saturation multiplier on the rainbow (CSS saturate() analogue).
    float saturation;
};

// MARK: - Vertex

vertex VertexOut vertexHoloBump(uint vid [[vertex_id]],
                                constant float4 &artRect [[buffer(0)]]) {
    // Emit a fullscreen triangle that fully covers the viewport. The three
    // vertices are positioned outside the [-1,1] NDC square so the rasterizer
    // clips it to exactly the viewport rect, with no need to render two
    // triangles. artRect is ignored here — the triangle always covers the
    // full pass attachment, which is what we want for a per-fragment bump.
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 texCoords[3] = {
        float2(0.0, 0.0),
        float2(2.0, 0.0),
        float2(0.0, 2.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

// Rotates an RGB colour around the luminance axis (proper hue rotation via
// the Rodrigues formula with the (1/√3, 1/√3, 1/√3) axis). Used to apply the
// cursor-driven hue shift to the foil sampled from the texture.
inline float3 hueRotate(float3 color, float angleDeg) {
    float a = angleDeg * 0.01745329252;
    float c = cos(a);
    float s = sin(a);
    float k = 0.57735026919;
    float kk = k * k;
    float3x3 m = float3x3(
        float3(c + (1.0 - c) * kk,       (1.0 - c) * kk + s * k,   (1.0 - c) * kk - s * k),
        float3((1.0 - c) * kk - s * k,    c + (1.0 - c) * kk,       (1.0 - c) * kk + s * k),
        float3((1.0 - c) * kk + s * k,    (1.0 - c) * kk - s * k,   c + (1.0 - c) * kk)
    );
    return m * color;
}

// MARK: - Fragment

fragment float4 fragmentHoloBump(VertexOut in [[stage_in]],
                                 texture2d<float, access::sample> foilTex   [[texture(0)]],
                                 constant HoloBumpUniforms &u               [[buffer(0)]]) {
    constexpr sampler samp(filter::linear, address::repeat, mip_filter::linear);

    float2 uv = in.texCoord;
    // The foil tile is 2w×2h and the output is rendered at that same
    // resolution, so sampling 1:1 (foilUV = uv) makes the bump foil pixel-
    // align with the parallax foil underneath. The visible card-sized region
    // is then selected by the SwiftUI clip, exactly like the parallax layer.
    float2 foilUV = uv;
    float2 texel = 1.0 / float2(foilTex.get_width(), foilTex.get_height());

    // 1. Sample the actual holographic foil texture (rainbow + scanlines,
    //    masked by the diffraction-grating). Its ALPHA gates where the foil
    //    is visible — identical to how the parallax path uses the foil tile,
    //    so the bump and the parallax foil agree on shape. Its LUMINANCE IS
    //    the embossed relief: the etched foil pattern catches the light. This
    //    is the "use the texture as the bump map" model — the foil itself is
    //    the height field, not a synthesized diagonal rainbow.
    float4 foil = foilTex.sample(samp, foilUV);
    float maskA = foil.a;

    float l = dot(foilTex.sample(samp, foilUV + float2(-texel.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float r = dot(foilTex.sample(samp, foilUV + float2( texel.x, 0.0)).rgb, float3(0.299, 0.587, 0.114));
    float u_ = dot(foilTex.sample(samp, foilUV + float2(0.0, -texel.y)).rgb, float3(0.299, 0.587, 0.114));
    float d = dot(foilTex.sample(samp, foilUV + float2(0.0,  texel.y)).rgb, float3(0.299, 0.587, 0.114));
    float dHdu = (r - l) * 3.0;
    float dHdv = (d - u_) * 3.0;
    float3 nTangent = normalize(float3(-dHdu, -dHdv, 1.0));

    // 2. Rotate the tangent-space normal into card-local (world) space via
    //    the tilt matrix.
    float3 nWorld = (u.tiltMatrix * float4(nTangent, 0.0)).xyz;
    nWorld = normalize(nWorld);

    // 3. Light direction (already in card-local space, pre-normalized).
    float3 L = normalize(u.lightDir);

    // 4. Blinn-Phong specular.
    float3 V = float3(0.0, 0.0, 1.0);
    float3 H = normalize(L + V);
    float NdotH = saturate(dot(nWorld, H));
    float spec = pow(NdotH, u.specularPower);

    // 5. Foil colour comes from the texture itself, so the colour and the
    //    relief always agree. Apply the cursor-driven hue shift + saturation.
    float3 rainbow = hueRotate(foil.rgb, u.hueShiftDegrees);
    float lum = dot(rainbow, float3(0.299, 0.587, 0.114));
    rainbow = mix(float3(lum), rainbow, u.saturation);

    // 6. Compose the foil.
    //    - colour: the actual foil colour from the texture.
    //    - highlight: additive specular glint, brightest where the bump
    //      normal catches the light (tracks the cursor/tilt). Purely
    //      additive — it can only brighten, never darken.
    //    - alpha: the foil texture's alpha, so the bump shows exactly where
    //      the parallax foil shows.
    float3 highlight = rainbow * spec * 1.4;
    float3 shine = rainbow + highlight;

    return float4(clamp(shine, 0.0, 1.0), maskA);
}

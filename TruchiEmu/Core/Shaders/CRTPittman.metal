#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

//////////////////////////////////////////////////////////////////////////
//
// CC0 1.0 Universal (CC0 1.0)
// Public Domain Dedication
//
// To the extent possible under law, J. Kyle Pittman has waived all
// copyright and related or neighboring rights to this implementation
// of CRT simulation. This work is published from the United States.
//
// For more information, please visit
// https://creativecommons.org/publicdomain/zero/1.0/
//
//////////////////////////////////////////////////////////////////////////

/**
 * CRT PITTMAN SHADER (MinorKeyGames CRTSim port)
 * ---------------------------------------------
 * Metal port of the CRT simulation from "Super Win the Game" /
 * "Gunmetal Arcadia" by J. Kyle Pittman (MinorKeyGames/CRTSim, CC0 1.0).
 *
 * The original Direct3D9 chain runs as separate passes:
 *   composite.fx  -> NTSC artifacts, unsharp mask (overshoot/undershoot),
 *                    spatial + temporal bleed, phosphor persistence
 *   screen (crtbase.fx SampleCRT) -> shadow mask, overscan, barrel warp,
 *                    saturation
 *   post.fx       -> Poisson downsample + upsample for bloom
 *   present.fx    -> PreBloom + ColorPow(Blurred) * Scalar
 *
 * This file mirrors that chain with one fragment function per pass.
 * MetalCoordinator encodes the passes in order, using the existing
 * 5-frame temporalTextures ring for the previous-frame input.
 *
 * Deviations from the original (documented, not silent):
 * - artifacts.bmp / mask.bmp are procedural. The artifact map is a
 *   phase-shifted diagonal RGB triad; the shadow mask is an
 *   aperture-grille triad with a mild vertical scan component baked in.
 * - The post.fx upsample pass is merged into the present pass: the
 *   downsampled blur texture is sampled with a linear filter at
 *   upscale time, which is equivalent to a blur + bilinear upsample.
 * - The 3D screen lighting (diffuse/specular/fresnel) and vertex-color
 *   dimming from screen.fx are skipped: the fullscreen quad has no
 *   normals and a white vertex color, so dimming is a no-op (white
 *   lerped with white). The emissive SampleCRT path is fully ported.
 */

// --- [ UNIFORMS ] ---
// Field order must match CRTPittmanUniforms in ShaderUniforms.swift exactly.

struct CRTPittmanUniforms {
    float tuningSharp;      // [0,1] unsharp-mask weight (orig default 0.8)
    float persistR;         // [0,1] red phosphor persistence (orig 0.7)
    float persistG;         // [0,1] green phosphor persistence (orig 0.525)
    float persistB;         // [0,1] blue phosphor persistence (orig 0.42)
    float tuningBleed;      // [0,1] neighbor blend of previous frame (orig 0.5)
    float tuningArtifacts;  // [0,1] NTSC artifact weight (orig 0.5)
    float ntscLerp;         // 0/1 alternating for vsync, 0.5 for unsynced (orig dynamic)
    float artifactScale;    // NTSC stripe density (libretro default 255)
    float bloomSpread;      // Poisson blur radius in UV (orig 0.025)
    float bloomPower;       // Color-preserving power curve (orig 2.0)
    float bloomIntensity;   // Bloom add scalar (orig 0.25)
    float maskScale;        // Shadow-mask triad density (libretro default 0.25)
    float tuningSatur;      // Saturation (orig 1.35)
    float maskBrightness;   // Mask lift, added before opacity (orig 0.45)
    float maskOpacity;      // Mask blend (orig 1.0)
    float overscan;         // Zoom after mask sampling (orig 1.0)
    float barrel;           // UV warp, negative curves inward (orig -0.115)
    float dimming;          // Screen dimming (orig 0.5; no-op on fullscreen quad)
    float time;             // Animation clock (unused, kept for parity)
    float texSizeX;         // Source frame width
    float texSizeY;         // Source frame height
    float outputWidth;      // Drawable width
    float outputHeight;     // Drawable height
    float frameIndex;       // Monotonic frame counter (NTSC phase animation)
    float padding;
};

struct PittmanBlurUniforms {
    float spread;           // Poisson tap radius in UV
    float swapXY;           // >0.5 swaps Poisson offsets (upsample decorrelation)
};

// Unsharp-mask tap weights from composite.fx: alternating signs simulate
// overshoot (+1.0) then undershoot (-0.316, +0.1) at 1/2/3 px distance.
constant float PittSharpWeight[3] = { 1.0, -0.3162277, 0.1 };

// 7-tap Poisson disc from post.fx.
constant float2 PittPoisson[7] = {
    float2(0.000000, 0.000000),
    float2(0.000000, 1.000000),
    float2(0.000000, -1.000000),
    float2(-0.866025, 0.500000),
    float2(-0.866025, -0.500000),
    float2(0.866025, 0.500000),
    float2(0.866025, -0.500000)
};

static inline float pittBrightness(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

// Procedural stand-in for artifacts.bmp: diagonal RGB stripe triad.
// Phase shifts by PI between the two NTSC field states.
static inline float3 pittArtifactTriad(float diag, float phase) {
    return 0.5 + 0.5 * cos(diag + phase + float3(0.0, 2.0943951, 4.1887902));
}

// Color-preserving power curve from present.fx. Guards the black case
// (ActLuma == 0) that the original marks TODO.
static inline float3 pittColorPow(float3 c, float p) {
    float luma = max(dot(c, float3(0.299, 0.587, 0.114)), 1e-4);
    return (c / luma) * pow(luma, p);
}

// --- [ PASS 1: COMPOSITE ] ---
// Direct port of compositePixelShader in composite.fx.

fragment float4 fragmentPittmanComposite(VertexOut in [[stage_in]],
                                        texture2d<float> cur [[texture(0)]],
                                        texture2d<float> prev [[texture(1)]],
                                        constant CRTPittmanUniforms &u [[buffer(0)]]) {
    constexpr sampler pointS(filter::nearest, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float2 rcp = float2(1.0 / u.texSizeX, 1.0 / u.texSizeY);

    // NTSC field states. Even frames use ntscLerp, odd frames use its
    // mirror, so the default 1.0 alternates states (vsynced 60 fps) and
    // 0.5 holds a constant midpoint (unsynced), per the original comment.
    float diag = (uv.x * u.texSizeX + uv.y * u.texSizeY * 2.0) * 6.2831853
               * u.texSizeX / max(u.artifactScale, 1.0);
    float3 artA = pittArtifactTriad(diag, 0.0);
    float3 artB = pittArtifactTriad(diag, 3.14159265);
    float parity = fmod(u.frameIndex, 2.0);
    float3 ntArtifact = mix(mix(artA, artB, u.ntscLerp),
                            mix(artA, artB, 1.0 - u.ntscLerp),
                            step(0.5, parity));

    float3 curL = cur.sample(pointS, uv - float2(rcp.x, 0.0)).rgb;
    float3 curC = cur.sample(pointS, uv).rgb;
    float3 curR = cur.sample(pointS, uv + float2(rcp.x, 0.0)).rgb;

    float3 tunedNTSC = ntArtifact * u.tuningArtifacts;

    float3 prevL = prev.sample(pointS, uv - float2(rcp.x, 0.0)).rgb;
    float3 prevC = prev.sample(pointS, uv).rgb;
    float3 prevR = prev.sample(pointS, uv + float2(rcp.x, 0.0)).rgb;

    // NTSC chroma overlap from luma differences with neighbors.
    curC = saturate(curC + ((curL - curC) + (curR - curC)) * tunedNTSC);

    float curBrt = pittBrightness(curC);
    float offset = 0.0;
    for (int i = 0; i < 3; ++i) {
        float2 stepUV = float2((float(i + 1) / u.texSizeX), 0.0);
        offset += ((curBrt - pittBrightness(cur.sample(pointS, uv - stepUV).rgb))
                 + (curBrt - pittBrightness(cur.sample(pointS, uv + stepUV).rgb)))
                * PittSharpWeight[i];
    }
    curC = saturate(curC + (offset * u.tuningSharp * mix(float3(1.0), ntArtifact, u.tuningArtifacts)));

    // Persistence affects trails AND bleed; bleed only affects bleed.
    // max() (not add) so dark areas lift without blowing out brights.
    float3 persist = float3(u.persistR, u.persistG, u.persistB);
    float denom = 1.0 + 2.0 * u.tuningBleed;
    float3 trail = persist * (prevC + (prevL + prevR) * u.tuningBleed) / denom;
    curC = saturate(max(curC, trail));

    return float4(curC, 1.0);
}

// --- [ PASS 2: POISSON BLUR ] ---
// Shared by the downsample step. The original upsample step only swaps
// Poisson X/Y to decorrelate taps (set swapXY > 0.5 to reproduce it).

fragment float4 fragmentPittmanBlur(VertexOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   constant PittmanBlurUniforms &b [[buffer(0)]]) {
    constexpr sampler linS(filter::linear, address::clamp_to_edge);
    float3 acc = float3(0.0);
    for (int i = 0; i < 7; ++i) {
        float2 tap = (b.swapXY > 0.5) ? PittPoisson[i].yx : PittPoisson[i];
        acc += src.sample(linS, in.texCoord + tap * b.spread).rgb;
    }
    return float4(acc * (1.0 / 7.0), 1.0);
}

// --- [ PASS 3: SCREEN + PRESENT ] ---
// SampleCRT (crtbase.fx) folded with present.fx: shadow mask, overscan,
// barrel warp, saturation, then PreBloom + ColorPow(Blur) * Intensity.
// The blur texture is linear-filtered, so sampling it here performs the
// original upsample step implicitly.

fragment float4 fragmentPittmanPresent(VertexOut in [[stage_in]],
                                      texture2d<float> comp [[texture(0)]],
                                      texture2d<float> blur [[texture(1)]],
                                      constant CRTPittmanUniforms &u [[buffer(0)]]) {
    constexpr sampler linS(filter::linear, address::clamp_to_edge);

    // Aperture-grille triad standing in for mask.bmp. Triad width tracks
    // maskScale so denser masks tile faster across the output.
    float triadW = max(3.0 * (0.25 / max(u.maskScale, 1e-3)), 1.0);
    float mx = fmod(in.position.x / triadW, 3.0);
    float3 scantex = (mx < 1.0) ? float3(1.0, 0.25, 0.25)
                   : ((mx < 2.0) ? float3(0.25, 1.0, 0.25)
                                 : float3(0.25, 0.25, 1.0));
    // Mild vertical scan component: the baked mask tile carried both.
    float scanRow = 0.92 + 0.08 * sin(in.position.y * 3.14159265);
    scantex *= scanRow;

    scantex += u.maskBrightness;
    scantex = mix(float3(1.0), scantex, clamp(u.maskOpacity, 0.0, 1.0));

    // Overscan is applied AFTER mask sampling, then the barrel warp.
    float2 over = (in.texCoord * u.overscan) - ((u.overscan - 1.0) * 0.5);
    float2 c = over - 0.5;
    float rsq = dot(c, c);
    float2 buv = c + c * (u.barrel * rsq) + 0.5;
    if (buv.x < 0.0 || buv.x > 1.0 || buv.y < 0.0 || buv.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float3 comptex = comp.sample(linS, buv).rgb;
    float3 emissive = comptex * scantex;
    float desat = dot(emissive, float3(0.299, 0.587, 0.114));
    emissive = mix(float3(desat), emissive, u.tuningSatur);
    // dimming intentionally not applied: screen.fx modulates by the 3D
    // vertex color, which is constant white for a fullscreen quad.

    float3 blurred = blur.sample(linS, in.texCoord).rgb;
    float3 outColor = emissive + pittColorPow(blurred, u.bloomPower) * u.bloomIntensity;
    return float4(saturate(outColor), 1.0);
}

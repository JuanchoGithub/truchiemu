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
 * The original Direct3D9 chain (see Main.cpp Render()) runs as:
 *   composite.fx  -> NTSC artifacts, unsharp mask (overshoot/undershoot),
 *                    spatial + temporal bleed, phosphor persistence.
 *                    Reads the clean frame + the PREVIOUS COMPOSITE
 *                    (even/odd ping-pong RTTs), 1-frame feedback.
 *   screen (crtbase.fx SampleCRT) -> shadow mask from mask.bmp (LINEAR +
 *                    WRAP, tile covers 2x1 source px), overscan, barrel
 *                    warp, saturation. Rendered on a 3D screen mesh.
 *   post.fx       -> Poisson downsample to dst/16, then Poisson upsample
 *                    back to full res (XY-swapped taps).
 *   present.fx    -> PreBloom + ColorPow(Blurred, Power) * Intensity.
 *
 * This file mirrors that chain with one fragment function per pass.
 * MetalCoordinator encodes the passes in order into source-size
 * (composite), full-size (screen, upsample) and dst/16 (downsample)
 * targets, and keeps the previous composite in a dedicated texture
 * (same 1-frame feedback as the even/odd RTT ping-pong).
 *
 * Texture findings reproduced here (measured from the repo binaries):
 * - artifacts.bmp (256x224): hard diagonal primaries, top-down texel
 *   (x,y) holds R/B/G where (x-y)%3 is 0/1/2. Emulated with wrap for
 *   any source size; even frames sample the frame's row, odd frames
 *   one row down (NTSCLerp 0/1).
 * - mask.bmp (64x32, base 79): R/G/B lobes at texels 4.5/15.5/26.5
 *   (period 32), amplitudes 176/147/176, vertical envelope ramping
 *   2.5->7, flat to 23.5, down by 28.5. The right half of the tile is
 *   the left half shifted down by 16 rows (staggered slot mask), so
 *   the envelope phase follows floor(tileX/32). Fitted below.
 *
 * Remaining deviations from the original (documented, not silent):
 * - The shadow-mask lobes are a smoothstep fit of mask.bmp, not the
 *   bitmap itself. Worst-case fit error is ~0.2 at isolated texels on
 *   the lobe shoulders.
 * - The 3D screen lighting (diffuse/specular/fresnel), the frame mesh
 *   reflections, and vertex-color dimming from screen.fx are skipped:
 *   the fullscreen quad has no normals and a constant vertex color.
 * - Aspect/pixel-ratio letterboxing (UVScalar, 8:7) is left to the
 *   app's viewport, which already letterboxes the game rect.
 * - The unsharp-mask tap step uses 1/sourceWidth (libretro behavior)
 *   instead of the hardcoded 1/256 of the HLSL, so wide systems
 *   (e.g. Genesis 320px) do not overshoot.
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
    float bloomSpread;      // Poisson blur radius in UV (orig 0.025)
    float bloomPower;       // Color-preserving power curve (orig 2.0)
    float bloomIntensity;   // Bloom add scalar (orig 0.25)
    float tuningSatur;      // Saturation (orig 1.35)
    float maskBrightness;   // Mask lift, added before opacity (orig 0.45)
    float maskOpacity;      // Mask blend (orig 1.0)
    float overscan;         // Zoom factor (orig 1.0; applied as 1/overscan)
    float barrel;           // UV warp, negative curves inward (orig -0.115)
    float dimming;          // Screen dimming (orig 0.5; skipped, see above)
    float time;             // Animation clock (unused, kept for parity)
    float texSizeX;         // Source frame width
    float texSizeY;         // Source frame height
    float outputWidth;      // Drawable width
    float outputHeight;     // Drawable height
    float frameIndex;       // Monotonic frame counter (NTSC field phase)
    float padding;
};

struct PittmanBlurUniforms {
    float spread;           // Poisson tap radius in target-texture UV
    float aspect;           // X-axis scale (target height / target width)
    float swapXY;           // >0.5 swaps Poisson offsets (upsample decorrelation)
    float pad;
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

// mask.bmp lobe centers within one 32-texel triad period. The lobe shape
// is a symmetric smoothstep fit: it matches the bitmap under bilinear
// sampling better in situ than tighter per-texel fits ( lobe shoulders
// differ between the two tile halves; the symmetric compromise wins).
constant float PittLobeR = 4.5;
constant float PittLobeG = 15.5;
constant float PittLobeB = 26.5;

static inline float pittBrightness(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

// Floor-based mod-3 that stays in [0,3) for negative inputs
// (Metal fmod keeps the dividend sign; texel indices go negative).
static inline float pittMod3(float x) {
    return x - 3.0 * floor(x / 3.0);
}

// One channel of the artifacts.bmp diagonal triad: 0->R, 1->B, 2->G.
static inline float3 pittArtifactColor(float m) {
    return (m < 0.5) ? float3(1.0, 0.0, 0.0)
         : ((m < 1.5) ? float3(0.0, 0.0, 1.0)
                      : float3(0.0, 1.0, 0.0));
}

// Smoothstep fit of one mask.bmp phosphor lobe (base removed).
// d is the wrapped distance to the lobe center in tile texels.
static inline float pittLobe(float d) {
    float s = smoothstep(1.0, 5.0, d);
    return 1.0 - s * s;
}

static inline float pittWrappedDist(float mx, float center) {
    float d = mx - center;
    d -= 32.0 * step(16.0, d);
    d += 32.0 * step(d, -16.0);
    return fabs(d);
}

// Color-preserving power curve from present.fx. Guards the black case
// (ActLuma == 0) that the original marks TODO.
static inline float3 pittColorPow(float3 c, float p) {
    float luma = max(dot(c, float3(0.299, 0.587, 0.114)), 1e-4);
    return (c / luma) * pow(luma, p);
}

// --- [ PASS 1: COMPOSITE ] ---
// Direct port of compositePixelShader in composite.fx. `prev` must be the
// previous frame's composite output (even/odd ping-pong in the original),
// not the raw frame.

fragment float4 fragmentPittmanComposite(VertexOut in [[stage_in]],
                                        texture2d<float> cur [[texture(0)]],
                                        texture2d<float> prev [[texture(1)]],
                                        constant CRTPittmanUniforms &u [[buffer(0)]]) {
    constexpr sampler pointS(filter::nearest, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float2 rcp = float2(1.0 / u.texSizeX, 1.0 / u.texSizeY);

    // artifacts.bmp (256x224), POINT+WRAP sampled at the frame UV:
    // hard primaries where top-down texel (x,y) holds R/B/G at
    // (x-y)%3 == 0/1/2 (verified against the bitmap: 100% agreement).
    // The second sample is one texture row down. Even frames take the
    // first sample (NTSCLerp=0), odd frames the second (NTSCLerp=1).
    // The fmod wrap generalizes the 256x224 tile to any source size,
    // matching D3D WRAP addressing.
    float ax = fmod(floor(uv.x * 256.0), 256.0);
    float ay = fmod(floor(uv.y * 224.0), 224.0);
    float ay2 = fmod(ay + 1.0, 224.0);
    // (ax-ay)%3 with floor-mod: Metal fmod keeps the dividend sign,
    // so pittMod3 re-bases into [0,3) explicitly.
    float3 art1 = pittArtifactColor(pittMod3(ax - ay));
    float3 art2 = pittArtifactColor(pittMod3(ax - ay2));
    float3 ntArtifact = mix(art1, art2, step(0.5, fmod(u.frameIndex, 2.0)));

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
// Shared by the downsample and upsample steps of post.fx. Taps live in the
// render target's UV space with X scaled by the target inverse aspect,
// exactly like BloomScale in Main.cpp.

fragment float4 fragmentPittmanBlur(VertexOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   constant PittmanBlurUniforms &b [[buffer(0)]]) {
    constexpr sampler linS(filter::linear, address::clamp_to_edge);
    float3 acc = float3(0.0);
    for (int i = 0; i < 7; ++i) {
        float2 tap = (b.swapXY > 0.5) ? PittPoisson[i].yx : PittPoisson[i];
        acc += src.sample(linS, in.texCoord + tap * b.spread * float2(b.aspect, 1.0)).rgb;
    }
    return float4(acc * (1.0 / 7.0), 1.0);
}

// --- [ PASS 3b/2b: 3D SCREEN + CABINET MESHES ] ---
// Ports of screenPixelShader (screen.fx) and framePixelShader (frame.fx).
// The meshes (screen.m3d, frame.m3d) carry position/normal/color/uv(+blend)
// streams; lighting runs in world space exactly like the HLSL (worldMat is
// identity in the original, kept as a uniform for parity). The emissive
// path reuses the SampleCRT core via pittScreenEmissive.

struct PittmanMeshUniforms {
    float4x4 wvpMat;
    float4x4 worldMat;
    float4 camPos;
    float4 lightPos;
};

struct PittmanLightUniforms {
    float diffBrightness;   // Tuning_Diff_Brightness (orig 0.5)
    float specBrightness;   // Tuning_Spec_Brightness (orig 0.35)
    float specPower;        // Tuning_Spec_Power (orig 50)
    float fresBrightness;   // Tuning_Fres_Brightness (orig 1.0)
    float4 frameColor;      // Tuning_FrameColor (orig 0.06 gray)
    float reflScalar;       // Tuning_ReflScalar (orig 0.3)
    float dimming;          // Tuning_Dimming (orig 0.5)
    float pad;
};

struct PittmanMeshVertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
    float blend [[attribute(4)]];
};

struct PittmanMeshOut {
    float4 clipPos [[position]];
    float4 color;
    float2 uv;
    float blend;
    float3 norm;
    float3 camDir;
    float3 lightDir;
};

vertex PittmanMeshOut pittmanVertexMesh(PittmanMeshVertex in [[stage_in]],
                                       constant PittmanMeshUniforms &u [[buffer(1)]]) {
    PittmanMeshOut out;
    out.clipPos = u.wvpMat * float4(in.position, 1.0);
    float3 worldPos = (u.worldMat * float4(in.position, 1.0)).xyz;
    out.color = in.color;
    out.uv = in.texCoord;
    out.blend = in.blend;
    out.norm = in.normal;
    // Unnormalized pre-pixel, like the HLSL (normalized in fragment).
    out.camDir = u.camPos.xyz - worldPos;
    out.lightDir = u.lightPos.xyz - worldPos;
    return out;
}

// Shared SampleCRT core (crtbase.fx): shadow mask from the UNWARPED uv,
// then overscan + barrel warp applied to the composite lookup only,
// then saturation. dimming intentionally excluded (mesh color instead).
static inline float3 pittScreenEmissive(float2 screenUV, texture2d<float> comp,
                                       sampler s, constant CRTPittmanUniforms &u) {
    float2 srcPx = screenUV * float2(u.texSizeX, u.texSizeY);
    float mx = fmod(srcPx.x * 32.0, 64.0);
    float my = fract(srcPx.y) * 32.0;
    float u32 = fmod(mx, 32.0);
    float yy = fmod(my + 16.0 * step(32.0, mx), 32.0);
    float dR = pittWrappedDist(u32, PittLobeR);
    float dG = pittWrappedDist(u32, PittLobeG);
    float dB = pittWrappedDist(u32, PittLobeB);
    float env = smoothstep(2.5, 7.0, yy) * (1.0 - smoothstep(24.0, 28.5, yy));
    float3 lobes = float3(pittLobe(dR), pittLobe(dG), pittLobe(dB));
    float3 scantex = (79.0 + float3(176.0, 147.0, 176.0) * lobes * env) / 255.0;
    scantex += u.maskBrightness;
    scantex = mix(float3(1.0), scantex, clamp(u.maskOpacity, 0.0, 1.0));

    float over = 1.0 / max(u.overscan, 1e-3);
    float2 overUV = (screenUV * over) - ((over - 1.0) * 0.5);
    float2 c = overUV - 0.5;
    float rsq = dot(c, c);
    float2 buv = c + c * (u.barrel * rsq) + 0.5;
    float3 comptex = (buv.x < 0.0 || buv.x > 1.0 || buv.y < 0.0 || buv.y > 1.0)
        ? float3(0.0) : comp.sample(s, buv).rgb;
    float3 emissive = comptex * scantex;
    float desat = dot(emissive, float3(0.299, 0.587, 0.114));
    return mix(float3(desat), emissive, u.tuningSatur);
}

fragment float4 fragmentPittmanScreenMesh(PittmanMeshOut in [[stage_in]],
                                         texture2d<float> comp [[texture(0)]],
                                         constant CRTPittmanUniforms &u [[buffer(0)]],
                                         constant PittmanLightUniforms &l [[buffer(2)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 norm = normalize(in.norm);
    float3 camDir = normalize(in.camDir);
    float3 lightDir = normalize(in.lightDir);

    float diffuse = saturate(dot(norm, lightDir));
    float3 colordiff = float3(0.175, 0.15, 0.2) * diffuse * l.diffBrightness;

    float3 halfVec = normalize(lightDir + camDir);
    float spec = pow(saturate(dot(norm, halfVec)), l.specPower);
    float3 colorspec = float3(0.25) * spec * l.specBrightness;

    float fres = 1.0 - dot(camDir, norm);
    fres = (fres * fres) * l.fresBrightness;
    float3 colorfres = float3(0.45, 0.4, 0.5) * fres;

    float3 emissive = pittScreenEmissive(in.uv, comp, s, u);
    float3 nearfinal = colorfres + colordiff + colorspec + emissive;
    return float4(nearfinal * mix(float3(1.0), in.color.rgb, l.dimming), 1.0);
}

fragment float4 fragmentPittmanFrameMesh(PittmanMeshOut in [[stage_in]],
                                        texture2d<float> comp [[texture(0)]],
                                        constant CRTPittmanUniforms &u [[buffer(0)]],
                                        constant PittmanLightUniforms &l [[buffer(2)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 norm = normalize(in.norm);
    float3 camDir = normalize(in.camDir);
    float3 lightDir = normalize(in.lightDir);

    float diffuse = saturate(dot(norm, lightDir));
    float hemi = dot(norm, float3(0.0, 0.0, 1.0)) * 0.5 + 0.5;
    hemi = hemi * 0.4 + 0.3;
    float3 colordiff = l.frameColor.rgb * (diffuse + hemi) * l.diffBrightness;

    float3 halfVec = normalize(lightDir + camDir);
    float spec = pow(saturate(dot(norm, halfVec)), l.specPower);
    float3 colorspec = float3(0.25) * spec * l.specBrightness;

    float3 emissive = pittScreenEmissive(in.uv, comp, s, u);
    colorspec += emissive * in.blend * l.reflScalar;

    float fres = 1.0 - dot(camDir, norm);
    fres = (fres * fres) * l.fresBrightness;
    float3 colorfres = float3(0.15) * fres;

    float3 nearfinal = colorfres + colordiff + colorspec;
    return float4(nearfinal * mix(float3(1.0), in.color.rgb, l.dimming), 1.0);
}
// --- [ PASS 3: SCREEN (flat fallback) ---
// SampleCRT (crtbase.fx) without the 3D mesh: shadow mask, overscan,
// barrel warp, saturation. Renders the full-size pre-bloom image that
// post.fx downsamples.

fragment float4 fragmentPittmanScreen(VertexOut in [[stage_in]],
                                     texture2d<float> comp [[texture(0)]],
                                     constant CRTPittmanUniforms &u [[buffer(0)]]) {
    constexpr sampler linS(filter::linear, address::clamp_to_edge);
    // Main.cpp passes 1/Tuning_Overscan to the screen shader.
    float over = 1.0 / max(u.overscan, 1e-3);
    float2 overUV = (in.texCoord * over) - ((over - 1.0) * 0.5);
    float2 c = overUV - 0.5;
    float rsq = dot(c, c);
    float2 buv = c + c * (u.barrel * rsq) + 0.5;

    // Shadow mask in source-pixel space, sampled from the UNWARPED uv
    // like the original (only the composite lookup takes the warp): the
    // 64-texel tile covers 2 source pixels, one 32-row tile covers one
    // source row, and the right half staggers down 16 rows (slot mask).
    // mask.bmp is sampled LINEAR+WRAP in the original, so the smooth
    // analytic fit evaluates equivalently.
    float2 srcPx = in.texCoord * float2(u.texSizeX, u.texSizeY);
    float mx = fmod(srcPx.x * 32.0, 64.0);
    float my = fract(srcPx.y) * 32.0;
    float u32 = fmod(mx, 32.0);
    float yy = fmod(my + 16.0 * step(32.0, mx), 32.0);
    float dR = pittWrappedDist(u32, PittLobeR);
    float dG = pittWrappedDist(u32, PittLobeG);
    float dB = pittWrappedDist(u32, PittLobeB);
    float env = smoothstep(2.5, 7.0, yy) * (1.0 - smoothstep(24.0, 28.5, yy));
    float3 lobes = float3(pittLobe(dR), pittLobe(dG), pittLobe(dB));
    float3 scantex = (79.0 + float3(176.0, 147.0, 176.0) * lobes * env) / 255.0;

    scantex += u.maskBrightness;
    scantex = mix(float3(1.0), scantex, clamp(u.maskOpacity, 0.0, 1.0));

    // compFrameSampler uses BORDER black in the original.
    float3 comptex = (buv.x < 0.0 || buv.x > 1.0 || buv.y < 0.0 || buv.y > 1.0)
        ? float3(0.0) : comp.sample(linS, buv).rgb;
    float3 emissive = comptex * scantex;
    float desat = dot(emissive, float3(0.299, 0.587, 0.114));
    emissive = mix(float3(desat), emissive, u.tuningSatur);
    // dimming intentionally not applied: screen.fx modulates by the 3D
    // mesh vertex color, which is constant for a fullscreen quad.

    return float4(saturate(emissive), 1.0);
}

// --- [ PASS 4: PRESENT ] ---
// present.fx: PreBloom + ColorPow(Upsampled, Power) * Intensity. Both
// inputs are full-size here, so UVs map 1:1.

fragment float4 fragmentPittmanPresent(VertexOut in [[stage_in]],
                                      texture2d<float> pre [[texture(0)]],
                                      texture2d<float> blur [[texture(1)]],
                                      constant CRTPittmanUniforms &u [[buffer(0)]]) {
    constexpr sampler linS(filter::linear, address::clamp_to_edge);
    float3 preBloom = pre.sample(linS, in.texCoord).rgb;
    float3 blurred = blur.sample(linS, in.texCoord).rgb;
    float3 outColor = preBloom + pittColorPow(blurred, u.bloomPower) * u.bloomIntensity;
    return float4(saturate(outColor), 1.0);
}

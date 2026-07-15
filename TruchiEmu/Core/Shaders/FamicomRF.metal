#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

/**
 * FAMICOM RF (ANTENNA TV) SHADER
 * ------------------------------
 * Stylized recreation of the GOROman/famicom-rf-hackrf-decoder "retro TV"
 * look: a Famicom feeding a CRT through the VHF RF/antenna switch.
 *
 * Combines:
 *   - Antenna static / snow (driven by signal strength)
 *   - RF luma bleed (horizontal smear, stronger in darks)
 *   - RF chroma fringing (R/B misregistration at the edges)
 *   - Barrel-distorted CRT scanlines + vignette + warm tint + flicker
 *   - Green "CH1/CH2" channel OSD with a sync-lock LED
 *
 * NOTE: This is a post-processing shader on an already-decoded RGBA frame.
 * It does NOT perform RF/SDR decoding (that is a sequential CPU DSP pipeline).
 *
 * Reuses vertexPassthrough from CRTFilter.metal (single default MTLLibrary).
 */

// --- [ CONSTANTS ] ---

static constant float RF_V_TRIM = 0.033333;
static constant float RF_V_SCALE = 0.933334;
static constant float RF_INV_RES_X = 0.00024414;
static constant float RF_JITTER = 0.00015;

// --- [ UNIFORMS ] ---

struct FamicomRFUniforms {
    float time;
    float texSizeX;
    float texSizeY;
    float signalStrength;   // 0.0 (no signal) .. 1.0 (locked)
    float snowAmount;       // 0.0 .. 1.0
    float bleedAmount;      // RF luma bleed
    float chromaAmount;     // RF chroma fringing
    float barrelAmount;     // barrel distortion
    float scanlineIntensity;
    float vignetteStrength;
    float flickerStrength;
    float colorBoost;
    float tintR;
    float tintG;
    float tintB;
    float channel;          // 1.0 or 2.0
    float showOSD;          // toggle
    float useDistort;
    float useScan;
    float useBleed;
    float useChroma;
    float useVig;
    float useFlick;
    float useBezel;
    float bezelRounding;
    float bezelGlow;
    float outputWidth;
    float outputHeight;
};

// --- [ HELPERS ] ---

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

struct ShaderContext {
    float2 centered;
    float distSq;
};

static ShaderContext prepareContext(float2 uv, bool distort) {
    ShaderContext ctx;
    if (distort) {
        ctx.centered = (uv - float2(0.5, 0.52)) * 2.0;
        ctx.centered *= float2(1.06, 1.08);
        ctx.distSq = dot(ctx.centered, ctx.centered);
    } else {
        ctx.centered = 0; ctx.distSq = 0;
    }
    return ctx;
}

static float2 getDistortedUV(float2 uv, ShaderContext ctx, float amount, bool active) {
    if (!active) return uv;
    float2 offset = ctx.centered * ctx.centered;
    float2 distort = ctx.centered + (ctx.centered * (offset.yx * amount));
    return distort * 0.5 + 0.5;
}

// --- [ CHANNEL OSD ] ---
// 3x5 bitmap font. Each glyph is 15 bits (row-major, MSB = left column).
// Glyphs needed: C, H, 1, 2

// 3x5 bitmap glyphs (row-major, MSB = top-left / row0-col0).
static constant uint C_GLYPH   = 0x3923; // 011 100 100 100 011
static constant uint H_GLYPH   = 0x29E4; // 100 100 111 100 100
static constant uint ONE_GLYPH = 0x2C97; // 010 110 010 010 111
static constant uint TWO_GLYPH = 0x72A7; // 111 001 010 100 111

// Returns coverage (0..1) of a glyph at logical pixel (gx, gy) within a 3x5 cell.
static float glyphCoverage(uint bits, float2 cell) {
    if (cell.x < 0.0 || cell.x >= 3.0 || cell.y < 0.0 || cell.y >= 5.0) return 0.0;
    int col = int(cell.x);
    int row = int(cell.y);
    uint bit = (bits >> (uint((4 - row) * 3 + (2 - col)))) & 1u;
    return float(bit);
}

// Draw "CHx" (x = 1 or 2) at the top-left in screen pixels.
static float3 drawChannelOSD(float3 rgb, float2 fragPx, float channel) {
    // Layout: 3 glyphs, each 3x5 px, 1px gap, scaled by 6 for a chunky retro readout.
    float scale = 6.0;
    float2 origin = float2(40.0, 40.0); // top-left margin (y grows downward in screen px)
    float2 local = fragPx - origin;
    if (local.x < 0.0 || local.y < 0.0) return rgb;
    float2 cell = local / scale;
    uint glyph = 0u;
    float inGlyph = 0.0;
    if (cell.x >= 0.0 && cell.x < 3.0)                       { glyph = C_GLYPH;   inGlyph = 1.0; }
    else if (cell.x >= 4.0 && cell.x < 7.0)                  { glyph = H_GLYPH;   inGlyph = 1.0; cell.x -= 4.0; }
    else if (cell.x >= 8.0 && cell.x < 11.0)                 { glyph = (channel > 1.5) ? TWO_GLYPH : ONE_GLYPH; inGlyph = 1.0; cell.x -= 8.0; }
    if (inGlyph < 0.5) return rgb;
    float cov = glyphCoverage(glyph, cell);
    if (cov > 0.5) {
        float3 chColor = float3(0.25, 1.0, 0.35); // retro green
        rgb = mix(rgb, chColor, 0.9);
    }
    return rgb;
}

// Small sync-lock LED, top-right. Green when locked, yellow when searching.
static float3 drawLockLED(float3 rgb, float2 fragPx, float2 viewSize, float signal) {
    float2 center = float2(viewSize.x - 46.0, 46.0);
    float2 d = fragPx - center;
    float r = length(d);
    if (r < 10.0) {
        float3 led = (signal > 0.5) ? float3(0.2, 1.0, 0.3) : float3(1.0, 0.85, 0.2);
        float edge = smoothstep(10.0, 7.0, r);
        rgb = mix(rgb, led, edge);
    }
    return rgb;
}

// --- [ MAIN FRAGMENT ] ---

fragment float4 fragmentFamicomRF(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant FamicomRFUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    const bool DISTORT = u.useDistort > 0.5;
    const bool SCAN = u.useScan > 0.5;
    const bool BLEED = u.useBleed > 0.5;
    const bool CHROMA = u.useChroma > 0.5;
    const bool VIG = u.useVig > 0.5;
    const bool FLICK = u.useFlick > 0.5;
    const bool BEZEL = u.useBezel > 0.5;

    // Weak signal -> vertical roll (antenna searching for sync).
    float roll = 0.0;
    float weak = clamp(1.0 - u.signalStrength, 0.0, 1.0);
    if (weak > 0.6) {
        roll = fract(u.time * 0.5) * (weak - 0.6) * 1.5;
    }

    ShaderContext ctx = prepareContext(in.texCoord, DISTORT);
    float2 distortedUV = getDistortedUV(in.texCoord, ctx, u.barrelAmount, DISTORT);
    float2 sampleUV = distortedUV;
    sampleUV.y = fract(distortedUV.y * RF_V_SCALE + RF_V_TRIM + roll);

    float jitter = sin(in.position.y * 0.1 + u.time * 60.0) * RF_JITTER;
    sampleUV.x += floor(jitter * 4096.0) * RF_INV_RES_X;

    float3 mainColor = tex.sample(s, sampleUV).rgb;

    // RF luma bleed: horizontal smear, stronger in darks.
    float spread = 1.0 / u.texSizeX;
    float3 colL = tex.sample(s, sampleUV - float2(spread, 0.0)).rgb;
    float3 colR = tex.sample(s, sampleUV + float2(spread, 0.0)).rgb;
    float3 rgb = mainColor;
    if (BLEED) {
        float3 bleed = (mainColor + colL + colR) * u.bleedAmount;
        float luma = dot(mainColor, float3(0.2126, 0.7152, 0.0722));
        rgb = mix(mix(mainColor, bleed, 2.0), mainColor, 0.5 + luma * 0.5);
    }

    // RF chroma fringing: R/B opposite shift at the edges.
    if (CHROMA) {
        float shift = u.chromaAmount * 0.01 * (0.2 + ctx.distSq);
        rgb.r = tex.sample(s, sampleUV + float2(shift, 0.0)).r;
        rgb.b = tex.sample(s, sampleUV - float2(shift, 0.0)).b;
    }

    // Color boost + warm RF tint.
    rgb *= u.colorBoost;
    rgb *= float3(u.tintR, u.tintG, u.tintB);

    // Scanlines.
    if (SCAN) {
        float scan = sin(sampleUV.y * u.texSizeY * 3.14159) * 0.5 + 0.5;
        float scanPow = scan * scan * scan;
        rgb *= mix(1.0, 1.0 - u.scanlineIntensity, scanPow);
    }

    // Flicker.
    if (FLICK) {
        rgb *= (sin(u.time * 60.0) * u.flickerStrength) + (1.0 - u.flickerStrength);
    }

    // Vignette.
    if (VIG) {
        rgb *= saturate(1.0 - (ctx.distSq * u.vignetteStrength * u.vignetteStrength));
    }

    // Antenna static / snow.
    float noise = hash21(in.position.xy * 0.5 + float2(u.time * 53.0, u.time * 71.0));
    float snowLevel = u.snowAmount * weak;
    float staticMask = step(noise, snowLevel);
    float3 snow = float3(noise) * (0.6 + 0.4 * hash21(in.position.xy + u.time));
    rgb = mix(rgb, snow, staticMask);

    // Channel OSD (screen space, in physical pixels).
    if (u.showOSD > 0.5) {
        rgb = drawChannelOSD(rgb, in.position.xy, u.channel);
        float2 viewSize = float2(u.outputWidth, u.outputHeight);
        rgb = drawLockLED(rgb, in.position.xy, viewSize, u.signalStrength);
    }

    // Bezel tube mask + glow.
    if (BEZEL) {
        float2 maskEdge = abs(distortedUV - 0.5) * 2.0;
        float2 m2 = maskEdge * maskEdge;
        float2 m4 = m2 * m2;
        float2 m8 = m4 * m4;
        float cornerMask = (m8.x * m4.x) + (m8.y * m4.y);
        float tubeVis = 1.0 - smoothstep(1.0, 1.0 + u.bezelRounding, cornerMask);
        if (distortedUV.x < 0.0 || distortedUV.x > 1.0 || distortedUV.y < 0.0 || distortedUV.y > 1.0) tubeVis = 0.0;
        rgb *= tubeVis;
        if (tubeVis < 0.99) {
            float2 mirUV = 1.0 - abs(1.0 - abs(sampleUV));
            rgb += tex.sample(s, mix(mirUV, sampleUV, 0.08)).rgb * u.colorBoost * (1.0 - tubeVis) * u.bezelGlow;
        }
    }

    return float4(saturate(rgb), 1.0);
}

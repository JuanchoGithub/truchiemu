#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

/**
 * RF DECODER DISPLAY PASS
 * -----------------------
 * Shown after the famidec RF decoder (digital -> RF -> decode) has produced a
 * decoded 640x480 RGBA frame. Applies only the *tube* CRT look (barrel
 * distortion, scanlines, vignette, flicker) plus the retro channel OSD — the
 * RF/NTSC artifacts themselves come from the decoder, so there is intentionally
 * NO re-NTSC pass here (that would double-apply chroma crawl, etc.).
 *
 * The bridge also drives a set of *display-stage* instability effects (grey
 * static on carrier loss, vertical-hold roll + diagonal shear, horizontal tear
 * bands, and random "bump" glitches) which it publishes each frame via
 * RfDynamicState. Those are applied here on top of the decoded picture.
 *
 * Reuses the channel-OSD / barrel helpers from FamicomRF.metal.
 */

static constant float PI = 3.14159265359;

struct RfDisplayUniforms {
    float time;
    float texSizeX;
    float texSizeY;
    float outputWidth;
    float outputHeight;
    float barrelAmount;
    float scanlineIntensity;
    float vignetteStrength;
    float flickerStrength;
    float colorBoost;
    float tintR;
    float tintG;
    float tintB;
    float channel;
    float showOSD;
    float useDistort;
    float useScan;
    float useVig;
    float useFlick;
    // Display-stage instability (published by the bridge each frame).
    float signalLoss;   // 0..1 grey static / carrier-loss mix
    float rollOffset;   // 0..1 vertical scroll (wraps)
    float rollShear;    // 0..1 horizontal shear per vertical unit (diagonal)
    float glitch;       // 0..1 bump glitch intensity
    float tear;         // 0..1 horizontal tear bands
    float hShift;       // -1..1 random horizontal jump
};

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

static constant uint C_GLYPH   = 0x3923; // 011 100 100 100 011
static constant uint H_GLYPH   = 0x29E4; // 100 100 111 100 100
static constant uint ONE_GLYPH = 0x2C97; // 010 110 010 010 111
static constant uint TWO_GLYPH = 0x72A7; // 111 001 010 100 111

static float glyphCoverage(uint bits, float2 cell) {
    if (cell.x < 0.0 || cell.x >= 3.0 || cell.y < 0.0 || cell.y >= 5.0) return 0.0;
    int col = int(cell.x);
    int row = int(cell.y);
    uint bit = (bits >> (uint((4 - row) * 3 + (2 - col)))) & 1u;
    return float(bit);
}

static float3 drawChannelOSD(float3 rgb, float2 uv, float channel, float2 imgSize) {
    float csx = 36.0 / imgSize.x;
    float csy = 36.0 / imgSize.y;
    float2 origin = float2(0.02, 0.02);
    float2 local = uv - origin;
    if (local.x < 0.0 || local.y < 0.0) return rgb;
    float2 cell = float2(local.x / csx, local.y / csy);
    uint glyph = 0u;
    float inGlyph = 0.0;
    if (cell.x >= 0.0 && cell.x < 3.0)            { glyph = C_GLYPH;   inGlyph = 1.0; }
    else if (cell.x >= 4.0 && cell.x < 7.0)       { glyph = H_GLYPH;   inGlyph = 1.0; cell.x -= 4.0; }
    else if (cell.x >= 8.0 && cell.x < 11.0)      { glyph = (channel > 1.5) ? TWO_GLYPH : ONE_GLYPH; inGlyph = 1.0; cell.x -= 8.0; }
    if (inGlyph < 0.5) return rgb;
    if (glyphCoverage(glyph, cell) > 0.5) {
        rgb = mix(rgb, float3(0.25, 1.0, 0.35), 0.9);
    }
    return rgb;
}

static float3 drawLockLED(float3 rgb, float2 uv, float2 imgSize, float signal) {
    float2 center = float2(1.0 - 0.02, 0.02);
    float2 d = (uv - center) * imgSize;
    float r = length(d);
    if (r < 10.0) {
        float3 led = (signal > 0.5) ? float3(0.2, 1.0, 0.3) : float3(1.0, 0.85, 0.2);
        rgb = mix(rgb, led, smoothstep(10.0, 7.0, r));
    }
    return rgb;
}

// Cheap hash + TV "snow" generator.
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float3 greyStatic(float2 uv, float t) {
    float2 p = uv * float2(320.0, 240.0);
    float n = hash21(floor(p) + floor(t * 50.0));
    // A faint green-ish cast like a mistuned CRT with no signal.
    return float3(n) * float3(0.95, 1.0, 0.92);
}

// Apply the bridge's display-stage instability to a content UV (wraps).
static float2 applyInstability(float2 uv, RfDisplayUniforms u) {
    // Vertical roll (wraps vertically).
    uv.y = fract(uv.y + u.rollOffset);
    // Horizontal shear scaled by vertical position -> diagonal drift.
    uv.x = fract(uv.x + u.rollShear * uv.y + u.hShift * 0.04f);
    // Horizontal tear: some scanline bands jump sideways.
    if (u.tear > 0.001f) {
        float band = floor(uv.y * 36.0f);
        float r = hash21(float2(band, floor(u.time * 24.0f)));
        if (r > 0.72f) {
            uv.x = fract(uv.x + (r - 0.85f) * 2.0f * u.tear * 0.12f);
        }
    }
    return uv;
}

fragment float4 fragmentRfDisplay(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant RfDisplayUniforms &u [[buffer(0)]]) {
    constexpr sampler repeatS(filter::linear, address::repeat);

    const bool DISTORT = u.useDistort > 0.5;
    const bool SCAN = u.useScan > 0.5;
    const bool VIG = u.useVig > 0.5;
    const bool FLICK = u.useFlick > 0.5;

    ShaderContext ctx = prepareContext(in.texCoord, DISTORT);
    float2 uv = getDistortedUV(in.texCoord, ctx, u.barrelAmount, DISTORT);

    // Roll / shear / tear / bump glitch on the content UV, then sample.
    float2 cuv = applyInstability(uv, u);
    float3 rgb = tex.sample(repeatS, cuv).rgb;

    // Bump glitch: RGB channel split + occasional dark rip.
    if (u.glitch > 0.001f) {
        float off = u.glitch * 0.02f * (hash21(float2(floor(u.time * 60.0), 1.0)) - 0.5f);
        float rr = tex.sample(repeatS, cuv + float2(off, 0.0)).r;
        float bb = tex.sample(repeatS, cuv - float2(off, 0.0)).b;
        rgb = float3(rr, rgb.g, bb);
        if (hash21(float2(floor(u.time * 30.0), floor(cuv.y * 200.0))) > 0.96f)
            rgb *= 0.3f;
    }

    // Color boost + warm RF tint.
    rgb *= u.colorBoost;
    rgb *= float3(u.tintR, u.tintG, u.tintB);

    // Carrier loss -> grey static (moving snow) replaces the picture.
    if (u.signalLoss > 0.001f) {
        float3 st = greyStatic(cuv, u.time);
        rgb = mix(rgb, st, clamp(u.signalLoss, 0.0, 1.0));
    }

    if (SCAN) {
        float scan = sin(uv.y * u.texSizeY * 3.14159) * 0.5 + 0.5;
        float scanPow = scan * scan * scan;
        rgb *= mix(1.0, 1.0 - u.scanlineIntensity, scanPow);
    }

    if (FLICK) {
        rgb *= (sin(u.time * 60.0) * u.flickerStrength) + (1.0 - u.flickerStrength);
    }

    if (VIG) {
        rgb *= saturate(1.0 - (ctx.distSq * u.vignetteStrength * u.vignetteStrength));
    }

    if (u.showOSD > 0.5) {
        float2 imgSize = float2(u.outputWidth, u.outputHeight);
        rgb = drawChannelOSD(rgb, in.texCoord, u.channel, imgSize);
        rgb = drawLockLED(rgb, in.texCoord, imgSize, 1.0 - clamp(u.signalLoss, 0.0, 1.0));
    }

    return float4(saturate(rgb), 1.0);
}

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
    // Manual sync-hold + picture position (user knobs; independent of the
    // random instability scheduler above).
    float vHold;        // baseline vertical-hold offset (roll)
    float hHold;        // baseline horizontal-sync offset
    float vPos;         // static vertical picture nudge
    float hPos;         // static horizontal picture nudge
    // Bezel tube mask + reflection glow (matches CRT Classic semantics).
    float useBezel;
    float useBezelReflection;
    float bezelRounding;
    float bezelGlow;
    float bezelReflectionBlur;
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

// Channel OSD glyphs, 5x6 (higher resolution than the old 3x5), one row per
// entry (MSB = leftmost pixel). CH1 / CH2 readout.
static constant uint CH_C[6] = { 0b01110, 0b10001, 0b10000, 0b10000, 0b10001, 0b01110 };
static constant uint CH_H[6] = { 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001 };
static constant uint CH_1[6] = { 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b01110 };
static constant uint CH_2[6] = { 0b11111, 0b00001, 0b00001, 0b00110, 0b01000, 0b11111 };

static float glyphCoverage(const constant uint* rows, int gh, float2 cell) {
    int col = int(floor(cell.x));
    int row = int(floor(cell.y));
    if (col < 0 || col > 4 || row < 0 || row >= gh) return 0.0;
    return float((rows[row] >> (4 - col)) & 1u);
}

static float3 drawChannelOSD(float3 rgb, float2 uv, float channel, float2 imgSize) {
    if (channel < 0.5) return rgb;  // OFF
    // 25% smaller than the old 36px cells.
    float cs = 27.0;
    // Pulled in from the very top-left edge so the barrel distortion at the
    // screen corner doesn't clip the top of the glyphs.
    float2 origin = float2(0.035, 0.05);
    float2 local = uv - origin;
    if (local.x < 0.0 || local.y < 0.0) return rgb;
    float2 cell = local * (imgSize / cs);
    const int GH = 6;
    const constant uint* rows = nullptr;
    float inGlyph = 0.0;
    float cx = cell.x;
    if (cx >= 0.0 && cx < 5.0)              { rows = CH_C; inGlyph = 1.0; }
    else if (cx >= 6.0 && cx < 11.0)        { rows = CH_H; inGlyph = 1.0; cell.x -= 6.0; }
    else if (cx >= 12.0 && cx < 17.0)       { rows = (channel > 1.5f) ? CH_2 : CH_1; inGlyph = 1.0; cell.x -= 12.0; }
    if (inGlyph < 0.5) return rgb;
    if (glyphCoverage(rows, GH, cell) > 0.5) {
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

    // Manual picture position nudge (static), then manual sync-hold
    // (baseline V-roll / H-offset), then the random instability pass.
    uv += float2(u.hPos, u.vPos);

    // The bezel mask is anchored to this static distorted geometry (before any
    // hold/scroll offsets), so rotating V-Hold/H-Hold still tiles/repeats the
    // texture like a real TV while only the barrel-wrapped screen edge is kept
    // black. Hold offsets are intentionally NOT part of `geo`.
    float2 geo = uv;

    uv.y = fract(uv.y + u.vHold);
    uv.x = fract(uv.x + u.hHold);

    // Roll / shear / tear / bump glitch on the content UV, then sample.
    float2 cuv = applyInstability(uv, u);

    // 1.0 where the distorted geometry sits inside the decoded frame.
    float inScreen = step(0.0, geo.x) * step(geo.x, 1.0)
                   * step(0.0, geo.y) * step(geo.y, 1.0);
    // Clamp the sample UV to the texture bounds so the analog-instability
    // scroll never pulls in wrapped content from the opposite edge of the
    // decoded frame. The instability math still runs (so vHold/rollOffset
    // appear to move the picture, but only up to the texture edge), and the
    // rest of the bezel reflection still operates on the wrapped UV if needed.
    float3 rgb = tex.sample(repeatS, clamp(cuv, 0.0, 1.0)).rgb;

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

    // Bezel tube mask + reflection. The wrapped `repeat` sampler is preserved
    // for the analog-instability aesthetic (roll/shear/tear still scroll the
    // picture inside the visible tube area, and V-Hold/H-Hold tile the frame
    // like a real TV), but the static `inScreen` mask blackens the barrel-
    // wrapped seam where the distorted geometry leaves the decoded frame, so
    // the bezel reads as a solid tube instead of repeating the opposite edge.
    // Anything past the rounded tube edge is hard-clipped and replaced by a
    // soft glow sampled from the *clamped* (non-wrapped) screen edge.
    if (u.useBezel > 0.5) {
        float2 maskEdge = abs(in.texCoord - 0.5) * 2.0;
        float2 m2 = maskEdge * maskEdge;
        float2 m4 = m2 * m2;
        float2 m8 = m4 * m4;
        float cornerMask = (m8.x * m4.x) + (m8.y * m4.y);
        float tubeVis = 1.0 - smoothstep(1.0, 1.0 + u.bezelRounding, cornerMask);
        if (in.texCoord.x < 0.0 || in.texCoord.x > 1.0 ||
            in.texCoord.y < 0.0 || in.texCoord.y > 1.0) tubeVis = 0.0;

        rgb *= step(0.99, tubeVis) * inScreen;

        // The rounded tube frame + reflection glow is drawn ON TOP of the seam
        // (rather than leaving a hard black ring between content and glow), so
        // the frame covers the barrel-wrapped region. Glow covers the tube-edge
        // band *and* the wrapped seam, sampling the nearest visible-screen
        // pixel (clamped, no wrapping/mirroring). Gated by useBezelReflection
        // so the glow can be disabled while the black bezel seam remains.
        float frameFrac = max(1.0 - tubeVis, 1.0 - inScreen);
        if (u.useBezelReflection > 0.5 && frameFrac > 0.001) {
            // Glow band: fixed UV-space fraction so reflection thickness is
            // consistent across resolutions.
            float glowWidth = 0.12;
            float bezelW = frameFrac * (1.0 - smoothstep(1.0, 1.0 + glowWidth, max(maskEdge.x, maskEdge.y)));

            if (bezelW > 0.001) {
                // Sample the nearest visible-screen pixel (no wrapping, no
                // mirroring). A real CRT bezel is a soft glow of the adjacent
                // screen edge — not a mirror of the opposite side. Sampling the
                // *static* geometry (`geo`, before hold/scroll offsets) keeps
                // the glow anchored to the screen edge so it reads as a CRT
                // reflection instead of showing whatever content scrolls by.
                float2 clampedUV = clamp(geo, 0.0, 1.0);

                float blur = u.bezelReflectionBlur;
                float3 reflected = tex.sample(repeatS, clampedUV).rgb;
                reflected += tex.sample(repeatS, clampedUV + float2( blur, 0.0)).rgb;
                reflected += tex.sample(repeatS, clampedUV + float2(-blur, 0.0)).rgb;
                reflected += tex.sample(repeatS, clampedUV + float2(0.0,  blur)).rgb;
                reflected += tex.sample(repeatS, clampedUV + float2(0.0, -blur)).rgb;
                reflected /= 5.0;

                rgb += reflected * u.colorBoost * bezelW * u.bezelGlow;
            }
        }
    }

    if (u.showOSD > 0.5) {
        float2 imgSize = float2(u.outputWidth, u.outputHeight);
        rgb = drawChannelOSD(rgb, in.texCoord, u.channel, imgSize);
        rgb = drawLockLED(rgb, in.texCoord, imgSize, 1.0 - clamp(u.signalLoss, 0.0, 1.0));
    }

    return float4(saturate(rgb), 1.0);
}

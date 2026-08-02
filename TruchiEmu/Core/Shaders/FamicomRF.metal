    #include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

/**
 * FAMICOM RF (ANTENNA TV) SHADER
 * ------------------------------
 * Stylized recreation of the GOROman/famicom-rf-hackrf-decoder "retro TV"
 * look: a Famicom feeding a CRT through the VHF RF/antenna switch.
 *
 * Replicates the repo's visual pipeline (operating on an already-decoded
 * RGBA frame -- it does NOT perform RF/SDR decoding, which is a sequential
 * CPU DSP pipeline). Inspired directly by the repo's DSP (ntsc_decoder.cpp):
 *   - Antenna static / snow (signal strength)
 *   - Off-tune herringbone interference (carrier offset)
 *   - NTSC composite decode: Y/C band split (band-limited chroma),
 *     per-line color-burst phase (120 deg/line) wobble, chroma-luma
 *     dot-crawl, saturation + hue trim, color/gray mode
 *   - Random interference (shock/glitch): when the line PLL / color burst
 *     is disturbed the image loses chroma (gray), tears horizontally and
 *     shears diagonally, sweeps white/grey impulse bars, and rolls.
 *   - RF multipath ghosting (a dim, time-delayed spatial echo)
 *   - AGC brightness / contrast
 *   - RF luma bleed + RF chroma fringing
 *   - Barrel-distorted CRT scanlines + vignette + warm tint + flicker
 *   - Green "CH1/CH2" channel OSD with a sync-lock LED
 *
 * Reuses vertexPassthrough from CRTFilter.metal (single default MTLLibrary).
 */

// --- [ CONSTANTS ] ---

static constant float RF_V_TRIM = 0.033333;
static constant float RF_V_SCALE = 0.933334;
static constant float RF_INV_RES_X = 0.00024414;
static constant float RF_JITTER = 0.00015;
static constant float PI = 3.14159265359;

// --- [ UNIFORMS ] ---

struct FamicomRFUniforms {
    float time;
    float texSizeX;
    float texSizeY;
    float outputWidth;
    float outputHeight;
    float signalStrength;   // 0.0 (no signal) .. 1.0 (locked)
    float snowAmount;       // 0.0 .. 1.0
    float tuning;           // 0.0 .. 1.0 carrier offset -> herringbone
    float overscan;         // 0.0 .. 0.15
    float saturation;       // --sat
    float hue;              // --hue (degrees)
    float colorMode;        // 1.0 color, 0.0 gray
    float brightness;       // AGC brightness
    float contrast;         // AGC contrast
    float bleedAmount;      // RF luma bleed
    float chromaAmount;     // RF chroma fringing
    float ntscAmount;       // NTSC dot-crawl / chroma-luma crosstalk
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
    float useNtsc;
    float useDistort;
    float useScan;
    float useBleed;
    float useChroma;
    float useVig;
    float useFlick;
    float useBezel;
    float bezelRounding;
    float bezelGlow;
    float bezelReflectionBlur;
    // Interference / glitch (repo: shock -> sync & burst loss)
    float interference;     // master glitch rate/strength 0..1
    float ghosting;         // RF multipath echo 0..1
    float tearing;          // horizontal sync tear baseline 0..1
    float colorLoss;        // burst-drop gray baseline 0..1
    float barsAmount;       // white/grey impulse bars 0..1
};

// --- [ HELPERS ] ---

static float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

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

// --- [ NTSC COMPOSITE DECODE ] ---

static float3 rgb2yuv(float3 c) {
    float y = dot(c, float3(0.299, 0.587, 0.114));
    float u = (c.b - y) * 0.564;
    float v = (c.r - y) * 0.713;
    return float3(y, u, v);
}

static float3 yuv2rgb(float3 yuv) {
    float y = yuv.x, u = yuv.y, v = yuv.z;
    float r = y + 1.403 * v;
    float g = y - 0.344 * u - 0.714 * v;
    float b = y + 1.770 * u;
    return float3(r, g, b);
}

// Faithful-ish NTSC decode: band-limited (frequency-split) chroma, per-line
// burst-phase advance (120 deg/line) with PLL wobble, chroma-luma dot-crawl,
// saturation + hue trim, and gray mode (color=0 -> burst dropped).
static float3 applyNTSC(float3 center, float3 left, float3 right, float2 fragPx,
                        float sat, float hueDeg, float crawl, float color) {
    float3 cYUV = rgb2yuv(center);
    float3 lYUV = rgb2yuv(left);
    float3 rYUV = rgb2yuv(right);

    // Y/C band split: chroma is band-limited (~1.5 MHz vs luma ~4 MHz) -> blur U/V.
    float2 chroma = mix(cYUV.yz, (lYUV.yz + rYUV.yz) * 0.5, 0.6);

    // Hue trim (rotate I/Q) and saturation.
    float a = hueDeg * PI / 180.0;
    chroma = float2(chroma.x * cos(a) - chroma.y * sin(a),
                    chroma.x * sin(a) + chroma.y * cos(a));
    chroma *= sat * color; // color=0 forces gray (burst dropped)

    // Per-line color-burst phase (NES advances 120 deg/line) + imperfect PLL wobble.
    float linePhase = fragPx.y * (2.0 * PI / 3.0) + 0.02 * sin(fragPx.y * 0.7);
    float phaseC = PI * fragPx.x + linePhase;

    // Clean luma via 1px comb (chroma cancels between neighbors).
    float lumaClean = (lYUV.x + rYUV.x) * 0.5;

    // Dot-crawl: leak the chroma-modulated term back into luma (cross-color).
    float chromaTerm = chroma.x * cos(phaseC) + chroma.y * sin(phaseC);
    float Y = lumaClean + crawl * chromaTerm;

    return yuv2rgb(float3(Y, chroma.x, chroma.y));
}

// --- [ CHANNEL OSD ] ---
// 3x5 bitmap font. Each glyph is 15 bits (row-major, MSB = top-left).
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

// Drawn in image-normalized UV space (in.texCoord is 0..1 across the visible
// picture), so the readout always rasterizes on the image regardless of the
// letterboxed viewport. Square glyph cells via the image aspect ratio.
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

// --- [ MAIN FRAGMENT ] ---

fragment float4 fragmentFamicomRF(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant FamicomRFUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    const bool NTSC = u.useNtsc > 0.5;
    const bool DISTORT = u.useDistort > 0.5;
    const bool SCAN = u.useScan > 0.5;
    const bool BLEED = u.useBleed > 0.5;
    const bool CHROMA = u.useChroma > 0.5;
    const bool VIG = u.useVig > 0.5;
    const bool FLICK = u.useFlick > 0.5;
    const bool BEZEL = u.useBezel > 0.5;

    float2 fragPx = in.position.xy;
    float weak = clamp(1.0 - u.signalStrength, 0.0, 1.0);

    // --- Random interference / shock glitch system (repo: sync & burst loss) ---
    // Time-divided "slots"; a slot triggers a glitch with probability ~ interference.
    float glitchTime = u.time * (0.6 + u.interference * 3.0);
    float slot = floor(glitchTime);
    float phase = fract(glitchTime);
    float evRand = hash11(slot);
    float event = step(1.0 - u.interference, evRand);
    // quick attack, slower decay within the slot
    float env = event * smoothstep(0.0, 0.04, phase) * (1.0 - smoothstep(0.15, 0.9, phase));
    // per-line / per-slot randomness so different lines glitch differently
    float lineR  = hash11(slot * 1.7 + floor(fragPx.y));
    float lineR2 = hash11(slot * 2.3 + floor(fragPx.y * 0.5));

    // Weak signal -> vertical roll (antenna searching for sync).
    float roll = 0.0;
    if (weak > 0.6) {
        roll = fract(u.time * 0.5) * (weak - 0.6) * 1.5;
    }
    // Glitch roll (vsync lost) adds to it.
    roll += env * 0.5 * fract(u.time * 1.7 + slot);

    ShaderContext ctx = prepareContext(in.texCoord, DISTORT);
    float2 distortedUV = getDistortedUV(in.texCoord, ctx, u.barrelAmount, DISTORT);
    float2 sampleUV = distortedUV;
    float ov = u.overscan;
    sampleUV = (sampleUV - 0.5) * (1.0 - 2.0 * ov) + 0.5;
    sampleUV.y = fract(sampleUV.y * RF_V_SCALE + RF_V_TRIM + roll);

    // Horizontal sync tear (baseline + glitch) per line, plus diagonal shear.
    float tear = u.tearing * 0.5 + env;
    float lineShift = (hash11(slot * 3.1 + floor(fragPx.y)) - 0.5) * tear * 0.06;
    sampleUV.x += lineShift;
    sampleUV.x += env * 0.03 * (fragPx.y / max(u.outputHeight, 1.0)); // diagonal shear

    float jitter = sin(fragPx.y * 0.1 + u.time * 60.0) * RF_JITTER;
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

    // NTSC composite decode (band-limited chroma, dot-crawl, hue/sat, gray).
    // Burst drop (repo kMinBurstAmp): lose chroma -> grayscale during glitch.
    float colorAmt = (u.colorMode > 0.5)
        ? max(0.0, 1.0 - (u.colorLoss + env * step(0.5, lineR)))
        : 0.0;
    if (NTSC) {
        rgb = applyNTSC(rgb, colL, colR, fragPx,
                        u.saturation, u.hue, u.ntscAmount, colorAmt);
    } else if (colorAmt < 0.5) {
        float g = dot(rgb, float3(0.299, 0.587, 0.114));
        rgb = float3(g);
    }

    // RF chroma fringing: R/B opposite shift at the edges.
    if (CHROMA) {
        float shift = u.chromaAmount * 0.01 * (0.2 + ctx.distSq);
        rgb.r = tex.sample(s, sampleUV + float2(shift, 0.0)).r;
        rgb.b = tex.sample(s, sampleUV - float2(shift, 0.0)).b;
    }

    // AGC brightness / contrast.
    rgb *= u.brightness;
    rgb = (rgb - 0.5) * u.contrast + 0.5;

    // Color boost + warm RF tint.
    rgb *= u.colorBoost;
    rgb *= float3(u.tintR, u.tintG, u.tintB);

    // RF multipath ghosting: dim, horizontally-delayed spatial echo.
    if (u.ghosting > 0.001) {
        float2 ghostUV = sampleUV + float2(u.ghosting * 0.04 + env * 0.02, 0.0);
        float3 ghost = tex.sample(s, ghostUV).rgb;
        float gAmt = clamp(u.ghosting + env * 0.3, 0.0, 1.0);
        rgb = mix(rgb, rgb * 0.6 + ghost * 0.7, gAmt * 0.6);
    }

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

    // Off-tune herringbone interference (carrier offset).
    if (u.tuning > 0.001) {
        float herring = sin((fragPx.x + fragPx.y) * 0.35 + u.time * 9.0);
        rgb += herring * u.tuning * 0.12;
    }

    // White / grey impulse bars sweeping vertically (repo: shock impulse noise).
    if (u.barsAmount > 0.001 || env > 0.0) {
        float barPos = fragPx.y * 0.015 - u.time * (3.0 + 6.0 * env);
        float band = abs(fract(barPos) - 0.5);
        float barMask = smoothstep(0.47, 0.5, band);
        float barSeed = hash11(floor(barPos));
        float barVal = mix(0.5, 1.0, step(0.5, barSeed)); // grey or white
        float barTrig = clamp(u.barsAmount + env, 0.0, 1.0);
        rgb = mix(rgb, float3(barVal), barMask * barTrig * 0.6);
    }

    // Antenna static / snow (signal strength + glitch boost).
    float noise = hash21(fragPx * 0.5 + float2(u.time * 53.0, u.time * 71.0));
    float snowLevel = max(u.snowAmount * weak, env * 0.5);
    float staticMask = step(noise, snowLevel);
    float3 snow = float3(noise) * (0.6 + 0.4 * hash21(fragPx + u.time));
    rgb = mix(rgb, snow, staticMask);

    // Force B&W once chroma is dropped (Color Mode off / burst lost). The RF
    // chroma-fringe and ghosting effects above sample the colored source
    // texture, so without this they would re-introduce color into a picture
    // that is supposed to be grayscale. OSD/bezel are drawn afterward.
    if (colorAmt < 0.5) {
        float g = dot(rgb, float3(0.299, 0.587, 0.114));
        rgb = float3(g);
    }

    // Channel OSD (image-normalized space, drawn on top of the picture).
    if (u.showOSD > 0.5) {
        float2 imgSize = float2(u.outputWidth, u.outputHeight);
        rgb = drawChannelOSD(rgb, in.texCoord, u.channel, imgSize);
        rgb = drawLockLED(rgb, in.texCoord, imgSize, u.signalStrength);
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

        // With bezel on, hard-clip the screen at the tube edge so un-mirrored
        // content does not leak into the cut-off corners. Without bezel, fade
        // smoothly to match the soft edge.
        if (u.useBezel > 0.5) {
            rgb *= step(0.99, tubeVis);
        } else {
            rgb *= tubeVis;
        }

        if (u.useBezel > 0.5 && tubeVis < 0.99) {
            // Fixed UV-space glow band so the reflection thickness is consistent
            // regardless of source resolution.
            float glowWidth = 0.12;
            float bezelW = (1.0 - tubeVis) * (1.0 - smoothstep(1.0, 1.0 + glowWidth, max(maskEdge.x, maskEdge.y)));

            if (bezelW > 0.001) {
                // Sample the nearest visible-screen pixel (no mirroring). A real
                // CRT bezel shows a soft glow of the ADJACENT screen edge — not
                // a mirror of the opposite side. The sawtooth mirror formula
                // pulled in unrelated content (e.g. the ceiling after overscan
                // trim) and produced duplicated imagery around the frame.
                float2 edgeUV = clamp(sampleUV, 0.0, 1.0);

                // 5-tap cross blur so the reflection reads as a soft color glow,
                // not a sharp image.
                float blur = u.bezelReflectionBlur;
                float3 reflected = tex.sample(s, edgeUV).rgb;
                reflected += tex.sample(s, edgeUV + float2( blur, 0.0)).rgb;
                reflected += tex.sample(s, edgeUV + float2(-blur, 0.0)).rgb;
                reflected += tex.sample(s, edgeUV + float2(0.0,  blur)).rgb;
                reflected += tex.sample(s, edgeUV + float2(0.0, -blur)).rgb;
                reflected /= 5.0;

                rgb += reflected * u.colorBoost * bezelW * u.bezelGlow;
            }
        }
    }

    return float4(saturate(rgb), 1.0);
}

/*
 * TruchiEmu: 8bit Game Boy Color Hardware Simulation (Dandelion + Spectral Interference)
 * VERSION HISTORY:
 * v24.3: THE SPECTRAL UPDATE
 * - REPLACED: Sine-wave Newton's Rings with Physical Spectral Interference
 * - ADDED: Fractal Brownian Motion (fBM) and Domain Warping for organic glints
 * - MAINTAINED: Refined Exponential Ghosting, Metallic Reflector, and GBC Shell
 * - CONTROL: Aggression now scales with u.lightStrength (defaults to slight glint)
 */

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// --- FEATURE FLAGS ---
#define FLAG_GHOSTING     (1 << 0)
#define FLAG_GRID         (1 << 1)
#define FLAG_ABERRATION   (1 << 2)
#define FLAG_BLEED        (1 << 3)
#define FLAG_NEWTON_RINGS (1 << 4)
#define FLAG_JITTER       (1 << 5)
#define FLAG_REFLECTION   (1 << 6)
#define FLAG_GRAIN        (1 << 7)
#define FLAG_VIGNETTE     (1 << 8)
#define FLAG_TOPOGRAPHY   (1 << 9)
#define FLAG_COLOR_MATRIX (1 << 10)

struct GBCUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float physicalDepth;
    float ghostingWeight;
    uint  frameIndex;
    uint  flags;
    float brightnessBoost;
    float showShell;
    float lightPositionIndex;
    float lightStrength;
    float shellColorIndex;
    float shellView;
    float gridThicknessDark;
    float gridThicknessLight;
    float4 sourceSize;
    float4 outputSize;
};

// --- SIMULATION MODULES ---

float pcg_hash_gbc(float2 p) {
    uint2 v = uint2(p);
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    return float(v.x) * (1.0 / 4294967296.0);
}

float hardware_gold_noise(float2 p, float seed) {
    return fract(tan(distance(p * 1.61803398875, p) * seed) * (p.x + seed));
}

float irisNoise(float2 p) {
    float n = sin(p.x * 0.15) * sin(p.y * 0.15);
    n += sin(p.x * 0.4 + p.y * 0.3) * 0.5;
    n += sin(p.x * 1.1 - p.y * 0.9) * 0.25;
    return n;
}

// Fractal Brownian Motion for "Organic" variation
float fbm_gbc(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * irisNoise(p);
        p *= 2.2;
        a *= 0.5;
    }
    return v;
}

// Approximates RGB interference (Newton's Rings)
float3 spectral_gbc(float t) {
    float3 w = float3(6.1, 5.2, 4.4); // Wavelength scaling
    float3 c = 0.5 + 0.5 * cos(6.28318 * (t / w));
    return saturate(c);
}

float3 applyNaturalInterference(float2 uv, float intensity) {
    float2 center = float2(0.5, 0.5);
    float d = length(uv - center);

    // Domain Warping: Fractal noise distorts the noise field itself
    float2 warp = float2(fbm_gbc(uv * 4.0), fbm_gbc(uv * 4.0 + float2(1.7)));
    float thickness = d * 18.0 + fbm_gbc(uv * 10.0 + warp) * 3.5;

    float3 iris = spectral_gbc(thickness);
    float mask = smoothstep(0.9, 0.4, d) * smoothstep(0.0, 0.3, d);
    
    return iris * (intensity * 0.15) * mask;
}

float3 apply_ghosting_refinedGBC(float3 f0, float3 f1, float3 f2, float3 f3, float3 f4, float weight) {
    float3 trail = mix(f1, mix(f2, mix(f3, f4, 0.3), 0.4), 0.5);
    return mix(f0, trail, weight);
}

float3 applyMetallicReflector(float3 color, float2 p, float2 res, constant GBCUniforms &u) {
    float2 lightPos;
    int idx = int(u.lightPositionIndex);
    if (idx == 0)      lightPos = float2(res.x, 0.0);
    else if (idx == 1) lightPos = float2(0.0, 0.0);
    else if (idx == 2) lightPos = float2(res.x * 0.5, 0.0);
    else if (idx == 3) lightPos = float2(res.x * 0.5, res.y * 0.5);
    else if (idx == 4) lightPos = float2(0.0, res.y * 0.5);
    else if (idx == 5) lightPos = float2(res.x, res.y * 0.5);
    else if (idx == 6) lightPos = float2(0.0, res.y);
    else if (idx == 7) lightPos = float2(res.x * 0.5, res.y);
    else               lightPos = float2(res.x, res.y);

    float distToLight = length(p - lightPos);
    float wave1 = sin(p.x * 5.0 - p.y * 2.5);
    float wave2 = sin(p.x * 2.1 + p.y * 4.8);
    float metallicGrain = (wave1 * wave2) * 0.5 + 0.5;
    float sheen = smoothstep(-res.x * 0.6, res.x * 1.1, p.x - p.y);
    float glare = smoothstep(res.x * 0.8, 0.0, distToLight);
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    float reflectionMask = smoothstep(0.05, 0.5, luma);
    
    return (glare * 0.25 + sheen * 0.10 + metallicGrain * 0.02) * float3(0.9, 0.95, 1.0) * reflectionMask * u.lightStrength;
}

// --- SHELL RENDERING ---
//
// Geometry is expressed in GBC pixels: 1 unit == 1 LCD pixel, so the 160x144
// screen is exactly 160x144 units. Body, lens and control positions come from
// the real hardware (78 x 133.5 mm body, 44 x 40 mm LCD, 68 x 60 mm lens),
// scaled at 3.6 units/mm.
//
// Space: origin at the centre of the body, +x right, +y down (framebuffer).

constant float2 BODY_HALF      = float2(140.5, 240.5);
constant float2 SCREEN_CENTER  = float2(0.0, -121.0);
constant float2 SCREEN_HALF    = float2(80.0, 72.0);
constant float2 LENS_CENTER    = float2(0.0, -110.5);
constant float2 LENS_HALF      = float2(122.5, 107.5);
constant float2 DPAD_CENTER    = float2(-84.5, 77.0);
constant float2 BTN_B_CENTER   = float2(45.5, 84.0);
constant float2 BTN_A_CENTER   = float2(96.0, 66.5);
constant float2 SELECT_CENTER  = float2(-23.5, 157.5);
constant float2 START_CENTER   = float2(17.5, 157.0);
constant float2 SPEAKER_CENTER = float2(91.5, 185.0);
constant float2 LED_CENTER     = float2(-117.0, -152.0);

// "Screen close-up" view: a 300 x 270 unit frame around the lens, centred
// slightly above the lens centre so the top edge of the case stays visible.
constant float2 CLOSEUP_CENTER = float2(0.0, -118.0);
constant float2 CLOSEUP_FRAME  = float2(300.0, 270.0);

float3 getShellColor(float idx) {
 if (idx < 0.5) return float3(0.74, 0.11, 0.34); // Berry
 if (idx < 1.5) return float3(0.38, 0.22, 0.62); // Grape
 if (idx < 2.5) return float3(0.14, 0.14, 0.15); // Onyx
 if (idx < 3.5) return float3(0.58, 0.74, 0.85); // Glacier
 if (idx < 4.5) return float3(0.92, 0.45, 0.08); // Orange
 if (idx < 5.5) return float3(0.46, 0.12, 0.32); // Dahlia
 if (idx < 6.5) return float3(0.10, 0.58, 0.55); // Teal
 if (idx < 7.5) return float3(0.16, 0.22, 0.60); // Indigo
 return float3(0.74, 0.11, 0.34);
}

// --- 3x5 font (3 px wide glyphs, 1 px gap) ---
uint getCharBlockGBC(int c) {
    switch(c) {
        case 0:  return 11245; // A
        case 1:  return 27566; // B
        case 2:  return 31015; // C
        case 3:  return 27502; // D
        case 4:  return 31143; // E
        case 5:  return 31087; // G
        case 6:  return 29847; // I
        case 7:  return 18727; // L
        case 8:  return 24429; // M
        case 9:  return 23917; // N
        case 10: return 15211; // O
        case 11: return 31716; // P
        case 12: return 27565; // R
        case 13: return 31183; // S
        case 14: return 29842; // T
        case 15: return 23403; // U
        case 16: return 23421; // W
        case 17: return 23186; // Y
        default: return 0;
    }
}

constant int TEXT_GAMEBOY[8]  = {5, 0, 8, 4, -1, 1, 10, 17};  // GAME BOY
constant int TEXT_COLOR[5]    = {2, 10, 7, 10, 12};          // COLOR
constant int TEXT_POWER[5]    = {11, 10, 16, 4, 12};         // POWER
constant int TEXT_NINTENDO[8] = {9, 6, 9, 14, 4, 9, 3, 10};  // NINTENDO
constant int TEXT_SELECT[6]   = {13, 4, 7, 4, 2, 14};        // SELECT
constant int TEXT_START[5]    = {13, 14, 0, 12, 14};         // START

// `p` is the local coordinate, origin at the top-left of the string.
// `px` is the size of one font pixel in shader units.
float drawStringGBC(float2 p, constant int* textArray, int len, float px) {
    float2 q = p / px;
    if (q.y < 0.0 || q.y >= 5.0) return 0.0;
    int charIndex = int(floor(q.x / 4.0));
    if (charIndex < 0 || charIndex >= len) return 0.0;
    float2 charP = float2(fmod(q.x, 4.0), q.y);
    if (charP.x < 0.0 || charP.x >= 3.0) return 0.0;
    int c = textArray[charIndex];
    if (c < 0) return 0.0;
    uint glyph = getCharBlockGBC(c);
    int bit = 14 - (int(floor(charP.y)) * 3 + int(floor(charP.x)));
    return (glyph & (1u << bit)) != 0 ? 1.0 : 0.0;
}

// Single glyph, origin at the top-left.
float glyphMaskGBC(float2 p, int c, float px) {
    float2 q = p / px;
    if (q.x < 0.0 || q.x >= 3.0 || q.y < 0.0 || q.y >= 5.0) return 0.0;
    uint glyph = getCharBlockGBC(c);
    int bit = 14 - (int(floor(q.y)) * 3 + int(floor(q.x)));
    return (glyph & (1u << bit)) != 0 ? 1.0 : 0.0;
}

// --- SDF PRIMITIVES ---
float sdRoundRectGBC(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + float2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

// Rounded box with per-corner radii: x=TL, y=TR, z=BL, w=BR.
float sdRoundBox4(float2 p, float2 b, float4 r) {
    float rad = (p.x > 0.0) ? ((p.y > 0.0) ? r.w : r.y) : ((p.y > 0.0) ? r.z : r.x);
    float2 q = abs(p) - b + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

float sdTriangle(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Triangle pointing along `dir`, centred on the origin.
float sdArrow(float2 p, float2 dir) {
    float2 t = float2(-dir.y, dir.x);
    return sdTriangle(p, dir * 6.0, -dir * 3.5 + t * 5.0, -dir * 3.5 - t * 5.0);
}

// Body outline: rounded box with a gently domed bottom edge (the GBC "chin").
float sdGBCBody(float2 p) {
    float t = saturate(abs(p.x) / BODY_HALF.x);
    float2 q = p - float2(0.0, 13.0 * (1.0 - t * t));
    return sdRoundBox4(q, BODY_HALF, float4(20.0, 20.0, 34.0, 34.0));
}

float2 bodyNormal(float2 p, float e) {
    float2 n = float2(sdGBCBody(p + float2(e, 0.0)) - sdGBCBody(p - float2(e, 0.0)),
                      sdGBCBody(p + float2(0.0, e)) - sdGBCBody(p - float2(0.0, e)));
    return n / max(length(n), 1e-5);
}

// Direction *towards* the light, matching lightPositionIndex in the reflector.
float2 shellLightDir(float idx) {
    int i = int(idx);
    if (i == 0) return normalize(float2( 0.80, -0.60));
    if (i == 1) return normalize(float2(-0.80, -0.60));
    if (i == 2) return float2(0.0, -1.0);
    if (i == 3) return float2(0.0, -0.20);
    if (i == 4) return float2(-1.0, 0.0);
    if (i == 5) return float2( 1.0, 0.0);
    if (i == 6) return normalize(float2(-0.80, 0.60));
    if (i == 7) return float2(0.0, 1.0);
    return normalize(float2(0.80, 0.60));
}

// Shade a circular depression: shadow on the lit side of the rim, a faint
// reflected highlight on the opposite wall.
float3 shadeRecess(float3 col, float sd, float2 q, float2 light, float depth) {
    float rim = 1.0 - smoothstep(0.0, depth, -sd);
    float2 n = q / max(length(q), 1e-4);
    float facing = dot(n, light);
    col *= 1.0 - rim * 0.17 * saturate(facing);
    col += rim * 0.05 * saturate(-facing);
    return col;
}

// --- CONTROL DETAILS ---

float3 drawSpeaker(float3 col, float2 p) {
    float2 q = p - SPEAKER_CENTER;
    float cell = 7.7;
    float rowIdx = floor(q.y / cell + 0.5);
    float stag = 0.5 * fmod(rowIdx, 2.0);
    float2 g = float2(q.x / cell - stag, q.y / cell);
    float2 idx = floor(g + 0.5);
    float2 f = (g - idx) * cell;
    float2 holeCenter = float2((idx.x + stag) * cell, idx.y * cell);

    // only holes whose centre sits inside the grille patch exist
    float inPatch = smoothstep(4.0, -4.0,
                               sdRoundRectGBC(holeCenter, float2(28.0, 33.0), 15.0));
    if (inPatch <= 0.0) return col;

    float dist = length(f);
    float hole = smoothstep(1.30, 0.70, dist);
    float3 holeCol = col * 0.20 + float3(0.010);
    holeCol += float3(0.05) * smoothstep(1.30, 1.00, dist)
                            * smoothstep(0.35, 1.10, dist)
                            * saturate(f.y / 1.2);
    return mix(col, holeCol, hole * inPatch);
}

float3 drawDPad(float3 col, float2 p, float2 light, float px) {
    float2 q = p - DPAD_CENTER;

    float well = length(q) - 42.0;
    if (well < 9.0) col = shadeRecess(col, well, q, light, 9.0);

    // cross: union of two rounded bars
    float pad = min(sdRoundRectGBC(q, float2(35.0, 11.5), 5.0),
                    sdRoundRectGBC(q, float2(11.5, 35.0), 5.0));
    if (pad >= 2.0) return col;

    float2 nq = q / 35.0;
    float shade = saturate(dot(nq, light) * 0.5 + 0.5);
    float3 c = float3(0.115, 0.115, 0.125) * mix(0.60, 1.24, shade);
    c *= mix(0.55, 1.0, smoothstep(0.0, 1.4, -pad));          // edge line
    c += float3(0.045) * smoothstep(1.6, 0.0, -pad);           // top bevel

    // raised centre boss
    float boss = length(q) - 8.0;
    if (boss < 1.5) {
        c *= mix(0.80, 1.14, shade);
        c *= mix(0.60, 1.0, smoothstep(0.0, 1.2, -boss));
    }

    // moulded arrows
    float arrows = min(min(sdArrow(q - float2( 25.0, 0.0), float2( 1.0, 0.0)),
                           sdArrow(q - float2(-25.0, 0.0), float2(-1.0, 0.0))),
                       min(sdArrow(q - float2(0.0, -25.0), float2(0.0, -1.0)),
                           sdArrow(q - float2(0.0,  25.0), float2(0.0,  1.0))));
    c = mix(c, c * 0.42, smoothstep(px, -px, arrows));

    return mix(col, c, smoothstep(px, -px, pad));
}

float3 drawABButton(float3 col, float2 p, float2 center, int letter,
                    float2 light, float px) {
    float2 q = p - center;

    float well = length(q) - 23.0;
    if (well < 7.0) col = shadeRecess(col, well, q, light, 7.0);

    float d = length(q) - 16.0;
    if (d >= 2.0) return col;

    float2 nq = q / 16.0;
    float shade = saturate(dot(nq, light) * 0.5 + 0.5);
    float3 c = float3(0.125, 0.125, 0.135) * mix(0.55, 1.26, shade);
    c += float3(0.05) * saturate(1.0 - length(nq) * 1.15);     // dome centre
    c *= mix(0.55, 1.0, smoothstep(0.0, 1.5, -d));             // rim line

    float glyph = glyphMaskGBC(q - float2(-3.6, -6.0), letter, 2.4);
    c = mix(c, float3(0.52, 0.53, 0.55), glyph * 0.9);

    return mix(col, c, smoothstep(px, -px, d));
}

float3 drawPill(float3 col, float2 p, float2 center, float px) {
    float2 q = p - center;
    float d = sdRoundRectGBC(q, float2(11.5, 4.3), 4.3);
    if (d >= 4.0) return col;

    col *= mix(1.0, 0.86, smoothstep(4.0, 0.0, d));            // recess
    float3 c = float3(0.115, 0.115, 0.125) * mix(1.30, 0.62, smoothstep(-4.3, 4.3, q.y));
    c += float3(0.04) * smoothstep(1.2, 0.0, -d);
    return mix(col, c, smoothstep(px, -px, d));
}

// --- SHELL COMPOSITE ---

float4 renderGBCShell(float2 p, constant GBCUniforms &u, float px) {
    float2 light = shellLightDir(u.lightPositionIndex);
    float sdBody = sdGBCBody(p);

    // Backdrop glow that hugs the device and fades to the black clear colour,
    // so the letterboxed viewport edge never shows a seam.
    float3 bg = float3(0.050, 0.052, 0.062) * exp(-max(sdBody, 0.0) / 55.0);
    float bodyMask = smoothstep(px, -px, sdBody);
    if (bodyMask <= 0.0) return float4(bg, 1.0);

    // --- plastic body ---
    float3 col = getShellColor(u.shellColorIndex) * mix(1.08, 0.82, smoothstep(-230.0, 240.0, p.y));

    float2 bn = bodyNormal(p, 1.5);
    float bevel = 1.0 - smoothstep(0.0, 11.0, -sdBody);
    float lit = dot(bn, light);
    col *= 1.0 + bevel * (saturate(lit) * 0.45 - 0.30);
    col += bevel * 0.035 * saturate(lit);

    col += (pcg_hash_gbc(p * 1.7 + 512.0) - 0.5) * 0.012;      // moulding grain

    // --- controls ---
    col = drawSpeaker(col, p);
    col = drawDPad(col, p, light, px);
    col = drawABButton(col, p, BTN_B_CENTER, 1, light, px);
    col = drawABButton(col, p, BTN_A_CENTER, 0, light, px);
    col = drawPill(col, p, SELECT_CENTER, px);
    col = drawPill(col, p, START_CENTER, px);

    // printed labels
    col = mix(col, col * 0.60, drawStringGBC(p - float2(-41.5, 166.5), TEXT_SELECT, 6, 1.5));
    col = mix(col, col * 0.60, drawStringGBC(p - float2(2.5, 166.5), TEXT_START, 5, 1.5));
    col = mix(col, col * 0.90 + 0.045, drawStringGBC(p - float2(-35.2, 4.0), TEXT_NINTENDO, 8, 2.2));

    // --- lens ---
    float sdLens = sdRoundRectGBC(p - LENS_CENTER, LENS_HALF, 16.0);
    if (sdLens > 0.0) {
        col *= mix(0.42, 1.0, smoothstep(0.0, 2.0, sdLens));    // seam
        col *= 1.0 - 0.18 * smoothstep(24.0, 0.0, sdLens);      // contact shadow
        return float4(mix(bg, col, bodyMask), 1.0);
    }

    // --- glossy lens glass ---
    float2 lq = (p - LENS_CENTER) / LENS_HALF;
    float3 glass = float3(0.028, 0.028, 0.034);
    glass += float3(0.050, 0.052, 0.064) * saturate(0.55 - lq.y * 0.55);
    float band = pow(saturate(1.0 - abs(lq.x * 0.80 + lq.y * 1.05 - 0.15)), 3.0);
    glass += float3(0.075, 0.068, 0.095) * band * (0.45 + u.lightStrength * 0.45);
    float lip = smoothstep(-2.5, 0.0, sdLens);
    glass += float3(0.085) * lip * saturate(dot(lq / max(length(lq), 1e-4), -light));
    col = glass;

    // --- power indicator ---
    float2 led = p - LED_CENTER;
    float ledR = length(led);
    col += float3(0.95, 0.25, 0.30) * 0.20 * exp(-max(ledR - 3.2, 0.0) / 4.0)
                                            * smoothstep(11.0, 0.0, ledR);
    col = mix(col, float3(0.92, 0.28, 0.34), smoothstep(px, -px, ledR - 3.2));

    float arcs = 0.0;
    for (int i = 0; i < 3; i++) {
        float r = 9.0 + float(i) * 6.0;
        float ring = smoothstep(1.1, 0.4, abs(ledR - r));
        float span = smoothstep(0.75, 0.55, abs(atan2(led.y, led.x)));
        arcs = max(arcs, ring * span);
    }
    col = mix(col, float3(0.60, 0.64, 0.68), arcs * 0.85);

    col = mix(col, float3(0.55, 0.58, 0.62),
              drawStringGBC(p - float2(-125.5, -145.5), TEXT_POWER, 5, 1.9));

    // --- GAME BOY COLOR wordmark ---
    float2 logoP = p - float2(-77.0, -38.0);
    col = mix(col, float3(0.78, 0.80, 0.83),
              drawStringGBC(logoP, TEXT_GAMEBOY, 8, 2.75));
    float2 colorP = logoP - float2(99.0, 0.0);
    float cm = drawStringGBC(colorP, TEXT_COLOR, 5, 2.75);
    if (cm > 0.0) {
        float3 cCols[5] = {float3(0.86, 0.12, 0.42), float3(0.55, 0.36, 0.86),
                           float3(0.36, 0.80, 0.28), float3(0.96, 0.80, 0.16),
                           float3(0.16, 0.74, 0.86)};
        int ci = clamp(int(floor(colorP.x / 11.0)), 0, 4);
        col = mix(col, cCols[ci], cm);
    }

    // --- LCD surround (the game image is composited on top by the caller) ---
    float sdScreen = sdRoundRectGBC(p - SCREEN_CENTER, SCREEN_HALF, 2.0);
    if (sdScreen > 0.0) col *= mix(0.30, 1.0, smoothstep(0.0, 4.0, sdScreen));

    return float4(mix(bg, col, bodyMask), 1.0);
}

// --- MAIN FRAGMENT SHADER ---

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> frame0 [[texture(0)]],
                                texture2d<float> frame1 [[texture(1)]],
                                texture2d<float> frame2 [[texture(2)]],
                                texture2d<float> frame3 [[texture(3)]],
                                texture2d<float> frame4 [[texture(4)]],
                                constant GBCUniforms &u [[buffer(0)]]) {
    
   // Shell mode frames the same game image inside the device. The screen rect
   // is exactly 160x144 units, so the game maps 1:1 onto the LCD.
   bool inShell = u.showShell > 0.5;
   float2 uv;
   float screenMask = 1.0;
   float shellShade = 1.0;
   float3 shellColor = float3(0.0);

   if (inShell) {
      // .xy = drawable size (viewport is centred in it), .zw = viewport size,
      // so the device fits the letterboxed game area at any window aspect.
      float2 vp = (u.outputSize.zw.x > 0.0) ? u.outputSize.zw : u.outputSize.xy;
      // shellView 0 = close-up on the screen area, 1 = whole device.
      bool closeUp = u.shellView < 0.5;
      float scale = closeUp ? min(vp.x / CLOSEUP_FRAME.x, vp.y / CLOSEUP_FRAME.y)
                            : min(vp.x / 300.0, vp.y / 500.0);
      float2 viewCenter = closeUp ? CLOSEUP_CENTER : float2(0.0);
      float2 p = (in.position.xy - (u.outputSize.xy * 0.5)) / scale + viewCenter;
      float px = 1.0 / scale;

      float sdScreen = sdRoundRectGBC(p - SCREEN_CENTER, SCREEN_HALF, 2.0);
      screenMask = smoothstep(px, -px, sdScreen);
      if (screenMask <= 0.0) return renderGBCShell(p, u, px);

      uv = float2((p.x - SCREEN_CENTER.x + SCREEN_HALF.x) / (SCREEN_HALF.x * 2.0),
                  (p.y - SCREEN_CENTER.y + SCREEN_HALF.y) / (SCREEN_HALF.y * 2.0));
      shellShade = mix(0.62, 1.0, smoothstep(-4.0, 0.0, sdScreen));

      if (screenMask < 1.0) shellColor = renderGBCShell(p, u, px).rgb;
   } else {
      uv = in.texCoord;
   }

    // --- CORE EFFECT PIPELINE ---
    const float2 gbcRes = u.sourceSize.xy;
    float2 centeredUV = uv - float2(0.5, 0.5);
    float sqDist = dot(centeredUV, centeredUV);
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);

    float3 f0 = frame0.sample(s, uv).rgb;
    if (u.flags & FLAG_ABERRATION) {
        float abOffset = 0.0006 * sqDist;
        f0.r = frame0.sample(s, uv + float2(abOffset, 0.0)).r;
        f0.b = frame0.sample(s, uv - float2(abOffset, 0.0)).b;
    }

    float3 proc = f0;
    if (u.flags & FLAG_GHOSTING) {
        float pWeight = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.72;
        float3 f1 = frame1.sample(s, uv).rgb;
        float3 f2 = frame2.sample(s, uv).rgb;
        float3 f3 = frame3.sample(s, uv).rgb;
        float3 f4 = frame4.sample(s, uv).rgb;
        proc = apply_ghosting_refinedGBC(f0, f1, f2, f3, f4, pWeight);
    }

    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03, 0.10, 0.75, 0.15, 0.08, 0.10, 0.82);
    float3 sCol = (u.flags & FLAG_COLOR_MATRIX) ? (proc * gbcMat) * u.colorBoost * 1.44 : proc * u.colorBoost;
    
    float2 pCoord = uv * gbcRes;
    float2 pixelIndex = floor(uv * gbcRes);
    float topoShimmer = 0.0;
    
    if (u.flags & FLAG_TOPOGRAPHY) {
        float2 cellUV = fract(pCoord + hardware_gold_noise(pixelIndex, 12.12) * 0.005);
        float2 pNormal = (cellUV - 0.5) * 2.0;
        float wellDepth = saturate(1.0 - length(pNormal * 1.1));
        topoShimmer = pow(wellDepth, 0.5);
        sCol *= (0.85 + topoShimmer * 0.15);
    }

    sCol += applyMetallicReflector(sCol, pCoord, gbcRes, u);
    
    if (u.flags & FLAG_BLEED) {
        float4 bleedSample = frame0.sample(s, float2(uv.x, 0.5));
        float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
        sCol -= float3(bleedVal * 0.008);
        sCol *= (0.97 + pcg_hash_gbc(pixelIndex * 3.3) * 0.06);
    }

    float maskG = 1.0; float maskS = 1.0;
    if (u.flags & FLAG_GRID) {
        float thick = mix(1.0 - (u.gridThicknessDark > 0.0 ? u.gridThicknessDark : 0.2), 1.0 - (u.gridThicknessLight > 0.0 ? u.gridThicknessLight : 0.1), dot(proc, float3(0.299, 0.587, 0.114)));
        maskG = smoothstep(thick, 0.0, abs(fract(pCoord) - 0.5).x) * smoothstep(thick, 0.0, abs(fract(pCoord) - 0.5).y);
        float2 sOffset = normalize(centeredUV) * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);
        maskS = smoothstep(thick, 0.0, abs(fract(pCoord + sOffset) - 0.5).x) * smoothstep(thick, 0.0, abs(fract(pCoord + sOffset) - 0.5).y);
   }

   // GBC screen background color for authentic pixel gaps
   float3 bg = mix(float3(0.593, 0.622, 0.604), float3(0.20, 0.21, 0.18), maskS) + (sCol * 0.05);
    float3 final = mix(bg, sCol, maskG * u.dotOpacity + (1.0 - u.dotOpacity)) * 0.65;

    if (u.flags & FLAG_NEWTON_RINGS) {
        float aggression = (u.lightStrength > 0.0) ? u.lightStrength : 1.0;
        final += applyNaturalInterference(uv, 0.07 * aggression);
        final.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * ((pcg_hash_gbc(float2(float(u.frameIndex % 60u) * 0.01)) * 0.1) + 0.9);
    }

    if (u.flags & FLAG_REFLECTION) {
        float sheen = pow(saturate(uv.x + (1.0 - uv.y) - 0.8), 3.0) * (u.specularShininess * 0.09) * 0.2;
        final += (float3(0.92, 0.96, 1.0) * (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, length(uv - float2(1.0, 0.0)))) * 0.2);
        final += (float3(0.92, 0.95, 1.0) * sheen * (0.8 + topoShimmer * 0.2));
        final += (float3(1.0) * pow(pcg_hash_gbc(uv * 4000.0 + 1.0), 30.0) * sheen * 0.2);
    }

    if (u.flags & FLAG_JITTER) final += (pcg_hash_gbc(uv * 4000.0 + float(u.frameIndex % 60u) * 0.01) - 0.5) * 0.015;
    if (u.flags & FLAG_GRAIN) final += (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025 + (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;
    
    float vign = (u.flags & FLAG_VIGNETTE) ? 1.0 - 0.08 * pow(sqDist, 2.0) : 1.0;
    float3 outCol = final * vign * u.brightnessBoost;

    if (inShell) {
        outCol *= shellShade;
        outCol = mix(shellColor, outCol, screenMask);
    }

    return float4(outCol, 1.0);
}

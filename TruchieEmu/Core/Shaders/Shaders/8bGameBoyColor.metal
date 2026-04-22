/*
 * TruchieEmu: 8bit Game Boy Color Hardware Simulation (Final Elite)
 * Multi-Frame Temporal Response Edition
 * Developed by JayJay & Gemini
 */

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct GBCUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float physicalDepth;
    float ghostingWeight;
    uint  frameIndex;
};

float pcg_hash_gbc(float2 p) {
    uint2 v = uint2(p);
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    return float(v.x) * (1.0 / 4294967296.0);
}

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> frame0 [[texture(0)]], // Current
                                texture2d<float> frame1 [[texture(1)]], // T-1
                                texture2d<float> frame2 [[texture(2)]], // T-2
                                texture2d<float> frame3 [[texture(3)]], // T-3
                                texture2d<float> frame4 [[texture(4)]], // T-4
                                constant GBCUniforms &u [[buffer(0)]]) {
    
    const float2 gbcRes = float2(160.0, 144.0);
    
    // 1. LENS & COORDINATES
    float2 centeredUV = in.texCoord - 0.5;
    float sqDist = dot(centeredUV, centeredUV);
    float2 uv = centeredUV * (1.0 + 0.015 * sqDist) + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return float4(0.0, 0.0, 0.0, 1.0);

    const float2 pixelIndex = floor(uv * gbcRes);
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    
    // 2. CHROMATIC ABERRATION
    float abOffset = 0.0006 * sqDist;
    float3 nowCol;
    nowCol.r = frame0.sample(s, uv + float2(abOffset, 0.0)).r;
    nowCol.g = frame0.sample(s, uv).g;
    nowCol.b = frame0.sample(s, uv - float2(abOffset, 0.0)).b;
    
    // 3. MULTI-FRAME TEMPORAL FEEDBACK (LCD Ghosting)
    // Simulating the slow crystal state transition over 5 frames total
    float3 f1 = frame1.sample(s, uv).rgb;
    float3 f2 = frame2.sample(s, uv).rgb;
    float3 f3 = frame3.sample(s, uv).rgb;
    float3 f4 = frame4.sample(s, uv).rgb;

    // Decay weights: Current frame is dominant, others fade exponentially
    float w = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.5;
    
    // Weighted sum for the "Elite" motion trail
    float3 ghostedRGB = nowCol * 0.40 +
                        f1 * (0.25 * w * 2.0) +
                        f2 * (0.15 * w * 1.5) +
                        f3 * (0.12 * w) +
                        f4 * (0.08 * w);

    // 4. HARDWARE JITTER
    float tSeed = float(u.frameIndex % 60) * 0.01;
    float noiseVal = pcg_hash_gbc(uv * 4000.0 + tSeed);
    
    // 5. COLOR & SUBPIXEL VARIANCE
    // GBC Hardware Palette Emulation
    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03,
                                     0.10, 0.75, 0.15,
                                     0.08, 0.10, 0.82);
    float3 sCol = (ghostedRGB * gbcMat) * u.colorBoost * 1.44;
    
    // 6. LONGITUDINAL BLEED (Vertical Driver Crosstalk)
    float colBleed = frame0.sample(s, float2(uv.x, 0.5)).a * 0.008;
    sCol -= colBleed;

    float pV = pcg_hash_gbc(pixelIndex * 3.3);
    sCol *= (0.97 + pV * 0.06);

    // 7. POWER LED & NEWTON'S RINGS
    float flicker = (pcg_hash_gbc(float2(tSeed)) * 0.1) + 0.9;
    sCol.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * flicker;

    float rDist = distance(uv, float2(1.1, -0.1));
    float3 rbw = float3(sin(rDist * 18.0), sin(rDist * 18.0 + 2.0), sin(rDist * 18.0 + 4.0));
    rbw = pow(saturate(rbw * 0.5 + 0.5), 2.0) * 0.045;

    // 8. DOT MATRIX & DYNAMIC SHADOW
    const float3 pCol = float3(0.20, 0.21, 0.18);
    float lum = dot(ghostedRGB, float3(0.299, 0.587, 0.114));
    float thick = mix(0.24, 0.10, lum);
    float2 pCoord = uv * gbcRes;
    float2 fW = fwidth(pCoord);
    
    float2 lDir = normalize(uv - float2(1.0, 0.0));
    float2 sOffset = lDir * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);

    // Shadow Layer (Screen depth)
    float2 sGrid = fract(pCoord + sOffset);
    float sMask = smoothstep(thick-fW.x, thick, sGrid.x) * (1.0-smoothstep(1.0-thick, 1.0-thick+fW.x, sGrid.x)) *
                  smoothstep(thick-fW.y, thick, sGrid.y) * (1.0-smoothstep(1.0-thick, 1.0-thick+fW.y, sGrid.y));

    // LCD Grid Layer
    float2 gGrid = fract(pCoord + (noiseVal * 0.015));
    float gMask = smoothstep(thick-fW.x, thick, gGrid.x) * (1.0-smoothstep(1.0-thick, 1.0-thick+fW.x, gGrid.x)) *
                  smoothstep(thick-fW.y, thick, gGrid.y) * (1.0-smoothstep(1.0-thick, 1.0-thick+fW.y, gGrid.y));

    // 9. POLARIZER TEXTURE & GRAIN
    float grain = (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025;
    float polarizer = (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;

    // 10. FINAL COMPOSITE
    float lDist = distance(uv, float2(1.0, 0.0));
    float diff = 1.0 - smoothstep(0.0, 0.79, lDist);
    float3 refl = (float3(0.92, 0.96, 1.0) + rbw) * (u.specularShininess * 0.038) * diff;

    // Background panel color mixed with simulated shadows
    float3 bg = mix(pCol * 0.50 + (sCol * 0.09), pCol + (sCol * 0.09), sMask) + grain + polarizer;
    
    // Mix the active pixel color with the background
    float3 activeP = mix(bg, sCol, 0.85); // Alpha fixed at 0.85 for "reflective" feel
    float3 pWithG = mix(bg, activeP, gMask);
    
    float3 bMix = mix(activeP, pWithG, u.dotOpacity);
    float3 final = bMix + refl + (noiseVal - 0.5) * 0.015;

    // Corner Vignette
    final *= (1.0 - 0.08 * pow(sqDist, 2.0));

    return float4(final, 1.0);
}

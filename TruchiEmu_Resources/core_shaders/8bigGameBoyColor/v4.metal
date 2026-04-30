/*
 * TruchiEmu: 8bit Game Boy Color Hardware Simulation (Hybrid Elite)
 * Multi-Frame Temporal Response + Dynamic Organic Grid
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

// High-entropy hash for grid jitter
float hardware_gold_noise(float2 p, float seed) {
    return fract(tan(distance(p * 1.61803398875, p) * seed) * (p.x + seed));
}

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
                                texture2d<float> frame0 [[texture(0)]],
                                texture2d<float> frame1 [[texture(1)]],
                                texture2d<float> frame2 [[texture(2)]],
                                texture2d<float> frame3 [[texture(3)]],
                                texture2d<float> frame4 [[texture(4)]],
                                constant GBCUniforms &u [[buffer(0)]]) {
    
    const float2 gbcRes = float2(160.0, 144.0);
    float2 uv = in.texCoord; // Barrel distortion remains removed as requested
    float2 centeredUV = uv - 0.5;
    float sqDist = dot(centeredUV, centeredUV);
    const float2 pixelIndex = floor(uv * gbcRes);
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    
    // 1. RADIAL CHROMATIC ABERRATION
    float abOffset = 0.0006 * sqDist;
    float3 nowCol;
    nowCol.r = frame0.sample(s, uv + float2(abOffset, 0.0)).r;
    nowCol.g = frame0.sample(s, uv).g;
    nowCol.b = frame0.sample(s, uv - float2(abOffset, 0.0)).b;
    
    // 2. MULTI-FRAME GHOSTING
    float3 f1 = frame1.sample(s, uv).rgb;
    float3 f2 = frame2.sample(s, uv).rgb;
    float3 f3 = frame3.sample(s, uv).rgb;
    float3 f4 = frame4.sample(s, uv).rgb;
    float w = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.5;
    
    float3 ghostedRGB = nowCol * 0.40 +
                        f1 * (0.25 * w * 2.0) +
                        f2 * (0.15 * w * 1.5) +
                        f3 * (0.12 * w) +
                        f4 * (0.08 * w);

    // 3. HARDWARE JITTER
    float tSeed = float(u.frameIndex % 60) * 0.01;
    float noiseVal = pcg_hash_gbc(uv * 4000.0 + tSeed);
    
    // 4. COLOR & PALETTE
    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03, 0.10, 0.75, 0.15, 0.08, 0.10, 0.82);
    float3 sCol = (ghostedRGB * gbcMat) * u.colorBoost * 1.44;
    
    // 5. RESTORED: ALPHA-BASED LONGITUDINAL BLEED
    // Sampling Alpha again as in version 2, but falling back to Green if Alpha is 1.0
    float4 bleedSample = frame0.sample(s, float2(uv.x, 0.5));
    float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
    sCol -= bleedVal * 0.008;
    sCol *= (0.97 + pcg_hash_gbc(pixelIndex * 3.3) * 0.06);

    // 6. POWER LED & NEWTON'S RINGS
    float flicker = (pcg_hash_gbc(float2(tSeed)) * 0.1) + 0.9;
    sCol.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * flicker;
    float rDist = distance(uv, float2(1.1, -0.1));
    float3 rbw = pow(saturate(float3(sin(rDist*18.0), sin(rDist*18.0+2.0), sin(rDist*18.0+4.0))*0.5+0.5), 2.0)*0.045;

    // 7. RESTORED: DYNAMIC GRID THICKNESS + ANTI-MOIRE
    float lum = dot(ghostedRGB, float3(0.299, 0.587, 0.114));
    // Brighter pixels "expand" (thinner grid), dark pixels "contract" (thicker grid)
    float thick = mix(0.45, 0.25, lum);
    
    float2 pCoord = uv * gbcRes;
    float2 unitF = fwidth(pCoord);
    float gridJitter = hardware_gold_noise(pixelIndex, 12.1234);
    
    // Grid Mask with stochastic edge + restored dynamic thickness
    float2 grid = abs(fract(pCoord + (gridJitter * 0.015)) - 0.5);
    float2 gridAA = smoothstep(thick, thick - unitF * 2.2, grid);
    float gMask = gridAA.x * gridAA.y;
    
    // Drop Shadow Layer
    float2 lDir = normalize(uv - float2(1.0, 0.0));
    float2 sOffset = lDir * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);
    float2 shadowGrid = abs(fract(pCoord + sOffset) - 0.5);
    float2 shadowAA = smoothstep(thick, thick - unitF * 2.2, shadowGrid);
    float sMask = shadowAA.x * shadowAA.y;

    // 8. POLARIZER & GRAIN
    float grain = (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025;
    float polarizer = (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;

    // 9. FINAL COMPOSITE
    // 9. FINAL COMPOSITE
    const float3 pCol = float3(0.20, 0.21, 0.18); // This defines the "off" LCD panel color
    float lDist = distance(uv, float2(1.0, 0.0));
    float3 refl = (float3(0.92, 0.96, 1.0) + rbw) * (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, lDist));

    float3 bg = mix(pCol * 0.50 + (sCol * 0.09), pCol + (sCol * 0.09), sMask) + grain + polarizer;
    float3 activeP = mix(bg, sCol, 0.85);
    float3 pWithG = mix(bg, activeP, gMask);
    
    float3 bMix = mix(activeP, pWithG, u.dotOpacity);
    float3 final = bMix + refl + (noiseVal - 0.5) * 0.015;

    final *= (1.0 - 0.08 * pow(sqDist, 2.0));

    return float4(final, 1.0);
}

/*
 * TruchieEmu: 8bit Game Boy Color Hardware Simulation
 * * VERSION HISTORY:
 * v16.2: Full Physical Response Model + Tightened Grid.
 * - Chained EMA (Exponential Moving Average) for 60Hz flicker "Burn-in".
 * - Reduced grid thickness range (0.32 - 0.12) to prevent over-separation.
 * - Softened Grid AA for a more organic, less "digital" look.
 * - Restored all hardware artifacts: Aberration, Bleed, Rings, and Jitter.
 * * Developed by JayJay & Gemini
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

// --- HELPER FUNCTIONS ---

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

// --- MAIN FRAGMENT SHADER ---

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> frame0 [[texture(0)]],
                                texture2d<float> frame1 [[texture(1)]],
                                texture2d<float> frame2 [[texture(2)]],
                                texture2d<float> frame3 [[texture(3)]],
                                texture2d<float> frame4 [[texture(4)]],
                                constant GBCUniforms &u [[buffer(0)]]) {
    
    const float2 gbcRes = float2(160.0, 144.0);
    float2 uv = in.texCoord;
    float2 centeredUV = uv - 0.5;
    float sqDist = dot(centeredUV, centeredUV);
    const float2 pixelIndex = floor(uv * gbcRes);
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    
    // 1. RADIAL CHROMATIC ABERRATION
    float abOffset = 0.0006 * sqDist;
    float3 f0;
    f0.r = frame0.sample(s, uv + float2(abOffset, 0.0)).r;
    f0.g = frame0.sample(s, uv).g;
    f0.b = frame0.sample(s, uv - float2(abOffset, 0.0)).b;
    
    // 2. PHYSICAL RESPONSE GHOSTING (EMA Chain)
    // Simulates the 40-60ms rise/fall time of passive-matrix LCDs.
    float3 f1 = frame1.sample(s, uv).rgb;
    float3 f2 = frame2.sample(s, uv).rgb;
    float3 f3 = frame3.sample(s, uv).rgb;
    float3 f4 = frame4.sample(s, uv).rgb;

    float p = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.72;
    
    float3 stage1 = mix(f0, f1, p);
    float3 stage2 = mix(stage1, f2, p * 0.85);
    float3 stage3 = mix(stage2, f3, p * 0.70);
    float3 ghostedRGB = mix(stage3, f4, p * 0.50);

    // 3. HARDWARE JITTER
    float tSeed = float(u.frameIndex % 60) * 0.01;
    float noiseVal = pcg_hash_gbc(uv * 4000.0 + tSeed);
    
    // 4. COLOR & PALETTE
    const float3x3 gbcMat = float3x3(0.82, 0.15, 0.03, 0.10, 0.75, 0.15, 0.08, 0.10, 0.82);
    float3 sCol = (ghostedRGB * gbcMat) * u.colorBoost * 1.44;
    
    // 5. LONGITUDINAL BLEED
    float4 bleedSample = frame0.sample(s, float2(uv.x, 0.5));
    float bleedVal = (bleedSample.a < 1.0) ? bleedSample.a : bleedSample.g;
    sCol -= bleedVal * 0.008;
    sCol *= (0.97 + pcg_hash_gbc(pixelIndex * 3.3) * 0.06);

    // 6. POWER LED & NEWTON'S RINGS
    float flicker = (pcg_hash_gbc(float2(tSeed)) * 0.1) + 0.9;
    sCol.r += (1.0 - smoothstep(0.0, 0.15, uv.x)) * 0.015 * flicker;
    float rDist = distance(uv, float2(1.1, -0.1));
    float3 rbw = pow(saturate(float3(sin(rDist*18.0), sin(rDist*18.0+2.0), sin(rDist*18.0+4.0))*0.5+0.5), 2.0)*0.045;

    // 7. DYNAMIC GRID THICKNESS (Tightened for v16.2)
    float lum = dot(ghostedRGB, float3(0.299, 0.587, 0.114));
    float thick = mix(0.32, 0.12, lum); // Narrower range = fatter pixels
    float2 pCoord = uv * gbcRes;
    float2 unitF = fwidth(pCoord);
    float gridJitter = hardware_gold_noise(pixelIndex, 12.1234);
    
    float2 grid = abs(fract(pCoord + (gridJitter * 0.015)) - 0.5);
    float2 gridAA = smoothstep(thick, thick - unitF * 1.5, grid); // Softer edges
    float gMask = gridAA.x * gridAA.y;
    
    float2 lDir = normalize(uv - float2(1.0, 0.0));
    float2 sOffset = lDir * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);
    float2 shadowGrid = abs(fract(pCoord + sOffset) - 0.5);
    float2 shadowAA = smoothstep(thick, thick - unitF * 1.5, shadowGrid);
    float sMask = shadowAA.x * shadowAA.y;

    // 8. POLARIZER & GRAIN
    float grain = (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.025;
    float polarizer = (sin(uv.x * 800.0) * sin(uv.y * 800.0)) * 0.005;

    // 9. FINAL COMPOSITE
    const float3 pCol = float3(0.20, 0.21, 0.18); 
    float lDist = distance(uv, float2(1.0, 0.0));
    float3 refl = (float3(0.92, 0.96, 1.0) + rbw) * (u.specularShininess * 0.038) * (1.0 - smoothstep(0.0, 0.79, lDist));

    float3 bg = mix(pCol * 0.50 + (sCol * 0.09), pCol + (sCol * 0.09), sMask) + grain + polarizer;
    
    float3 activeP = mix(bg, sCol, 0.98);
    float3 pWithG = mix(bg, activeP, gMask);
    
    float3 bMix = mix(activeP, pWithG, u.dotOpacity);
    float3 final = bMix + refl + (noiseVal - 0.5) * 0.015;

    final *= (1.0 - 0.08 * pow(sqDist, 2.0));

    return float4(final, 1.0);
}
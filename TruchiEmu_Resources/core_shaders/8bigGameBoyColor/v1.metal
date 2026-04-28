/*
 * TruchieEmu: 8bit Game Boy Color Hardware Simulation (Final Elite)
 * Neutral Transflective Model - Color-Correct Edition
 * Fixed: Removed "Pea-Soup" Green DMG tint.
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
    float2 uv = in.texCoord;
    float2 centeredUV = uv - 0.5;
    float sqDist = dot(centeredUV, centeredUV);
    const float2 pixelIndex = floor(uv * gbcRes);
    float tSeed = float(u.frameIndex % 60) * 0.01;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    // --- 1. LIGHTING ENVIRONMENT (Neutral GBC Calibration) ---
    float3 ambientLight = float3(1.0, 1.0, 1.0); 
    // Shifted from olive/green to a neutral silver-grey
    float3 reflectorBase = float3(0.52, 0.52, 0.54); 
    
    // --- 2. ROM DATA (Neutral Matrix) ---
    float3 nowCol = frame0.sample(s, uv).rgb;
    float3 f1 = frame1.sample(s, uv).rgb;
    float3 ghostedRGB = nowCol * 0.6 + f1 * (0.4 * (u.ghostingWeight > 0.0 ? u.ghostingWeight : 0.5));
    
    // Removed the color skew; now focuses on saturation/boost without tinting
    const float3x3 gbcMat = float3x3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
    float3 pixelFilter = saturate(ghostedRGB * gbcMat * u.colorBoost);

    // --- 3. TOPOGRAPHY & GRID ---
    float2 pCoord = uv * gbcRes;
    float2 unitF = fwidth(pCoord); 
    float2 cellUV = fract(pCoord + hardware_gold_noise(pixelIndex, 12.12)*0.005);
    float2 pNormal = (cellUV - 0.5) * 2.0; 
    float wellDepth = saturate(1.0 - length(pNormal * 1.1)); 
    float topoShimmer = pow(wellDepth, 0.5); 
    
    float gridX = smoothstep(0.5, 0.5 - unitF.x * 2.5, abs(cellUV.x - 0.5));
    float gridY = smoothstep(0.5, 0.5 - unitF.y * 2.5, abs(cellUV.y - 0.5));
    float gMask = gridX * gridY;

    // --- 4. TRANSFLECTIVE PATH (High Visibility) ---
    float3 bounceLight = (ambientLight * reflectorBase * pixelFilter) * 1.45;
    
    float2 pOffset = centeredUV * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.15);
    float2 sGridUV = abs(fract(pCoord + (pOffset + float2(0.1, -0.1))) - 0.5);
    float sMask = 1.0 - (smoothstep(0.5, 0.5 - unitF.x * 2.5, sGridUV.x) * smoothstep(0.5, 0.5 - unitF.y * 2.5, sGridUV.y));
    bounceLight *= (1.0 - (sMask * 0.15)); // Light shadows for neutral look

    // --- 5. LENS SURFACE (Soft Cool Sheen) ---
    float linearGrad = saturate(uv.x + (1.0 - uv.y) - 0.8);
    float sheenIntensity = pow(linearGrad, 3.0) * (u.specularShininess * 0.09);
    
    float dustNoise = pcg_hash_gbc(uv * 4000.0 + 1.0);
    float3 surfaceGlints = float3(1.0) * pow(dustNoise, 30.0) * sheenIntensity * 1.2;
    // Cool bluish tint for the glass reflection only, not the LCD
    float3 sheen = float3(0.92, 0.95, 1.0) * sheenIntensity * (0.8 + topoShimmer * 0.2);

    // --- 6. FINAL MIX ---
    float3 inactiveGrid = (reflectorBase * 0.5) * ambientLight;
    float3 screenContent = mix(inactiveGrid, bounceLight, gMask);
    float3 final = mix(bounceLight, screenContent, u.dotOpacity);
    
    final = saturate(final + sheen + surfaceGlints);
    final += (pcg_hash_gbc(uv * 1200.0) - 0.5) * 0.01;

    // LED Power Light (The only red on the frame usually!)
    float ledF = (pcg_hash_gbc(float2(tSeed)) * 0.1) + 0.9;
    final.r += (1.0 - smoothstep(0.0, 0.10, uv.x)) * 0.008 * ledF;

    return float4(final * (1.0 - (sqDist * 0.05)), 1.0);
}
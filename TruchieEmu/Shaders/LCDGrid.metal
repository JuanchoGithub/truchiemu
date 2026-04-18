#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct LCDGridUniforms {
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float colorBoost;
    float4 sourceSize;
    float4 outputSize;
};

// Helper for 0.5% color variance
float3 colorNoise(float2 p) {
    float n = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    return float3(n) * 0.005; // 0.5% max variance
}

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    // --- INTERNAL CONFIGURATION ---
    float washOutAmount = 0.30; 
    float3 washColor = float3(0.55, 0.60, 0.50); 
    
    // BLEED CONTROLS
    float bleedIntensity = 0.25; // 0.0 to 1.0
    float bleedSpread = 0.40;    // How far light spills from center
    
    // 1. COORDINATE LOCK
    float2 gameRes = float2(160.0, 144.0);
    float2 scale = u.outputSize.xy / gameRes;
    float intScale = max(1.0, floor(min(scale.x, scale.y)));
    float2 offset = (u.outputSize.xy - (gameRes * intScale)) * 0.5;
    
    float2 screenPos = in.position.xy - offset;
    
    if (screenPos.x < 0.0 || screenPos.x >= (gameRes.x * intScale) ||
        screenPos.y < 0.0 || screenPos.y >= (gameRes.y * intScale)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 pixelIndex = floor(screenPos / intScale);
    float2 pixelFract = fract(screenPos / intScale);

    // 2. SAMPLING & CONTROLLABLE BLEED
    float2 uv = (pixelIndex + 0.5) / gameRes;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 sourceCol = pow(tex.sample(s, uv).rgb, 1.1);
    
    // Apply controllable spill logic
    float2 bleedDir = sign(pixelFract - 0.5);
    float2 neighborUV = (pixelIndex + 0.5 + bleedDir) / gameRes;
    float3 neighborCol = pow(tex.sample(s, neighborUV).rgb, 1.1);
    
    // The bleed is stronger toward the edges of the cell
    float distFromCenter = length(pixelFract - 0.5);
    float spillFactor = smoothstep(0.0, bleedSpread, distFromCenter) * bleedIntensity;
    sourceCol = mix(sourceCol, neighborCol, spillFactor);

    float luma = dot(sourceCol, float3(0.299, 0.587, 0.114));

    // 3. COLOR COMPENSATION & VARIANCE
    float3 finalTarget = float3(0.430, 0.516, 0.188);
    float3 compensatedGreen = finalTarget - float3(0.0, -0.100, 0.350);
    
    // Add the 0.5% variance here so it's part of the base pixel color
    compensatedGreen += (colorNoise(pixelIndex) - 0.0025); 
    
    sourceCol.b -= 0.350;
    sourceCol.g += 0.100;

    // 4. GRID & BLOOM
    float waveH = sin(pixelIndex.y * 0.25) * 0.02; 
    float waveV = cos(pixelIndex.x * 0.30) * 0.02; 
    float baseGap = u.pixelSeparation * 0.45;
    
    float bloomThreshold = smoothstep(0.05, 0.5, luma);
    float dynamicGap = mix(baseGap + 0.08 + waveH + waveV, -0.4, bloomThreshold);

    // 5. MASK
    float2 dist = abs(pixelFract - 0.5);
    float2 delta = fwidth(pixelFract);
    float2 edge = 0.5 - dynamicGap;
    float2 maskXY = smoothstep(edge + delta, edge - delta, dist);
    float gridMask = maskXY.x * maskXY.y;

    // 6. COMPOSITING
    float finalMask = mix(1.0, gridMask, u.gridStrength);
    float3 finalColor = mix(compensatedGreen, sourceCol, finalMask);
    
    // 7. RESTORE TARGET COLORS
    finalColor.b = clamp(finalColor.b + 0.440, 0.0, 1.0);
    finalColor.g = clamp(finalColor.g - 0.175, 0.0, 1.0);

    // 8. GLOBAL WASHOUT
    finalColor = mix(finalColor, washColor, washOutAmount);

    return float4(max(finalColor, 0.0) * u.brightnessBoost * u.colorBoost, 1.0);
}
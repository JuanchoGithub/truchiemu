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

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    // 1. COORDINATE LOCK
    float2 gameRes = float2(160.0, 144.0);
    float intScale = max(1.0, floor(min(u.outputSize.x / gameRes.x, u.outputSize.y / gameRes.y)));
    float2 offset = (u.outputSize.xy - (gameRes * intScale)) * 0.5;
    float2 pixelCoord = floor(in.position.xy - offset) / intScale;

    if (pixelCoord.x < 0.0 || pixelCoord.x >= gameRes.x || 
        pixelCoord.y < 0.0 || pixelCoord.y >= gameRes.y) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // 2. RAW DATA SAMPLE
    float2 uv = (floor(pixelCoord) + 0.5) / gameRes;
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 sourceCol = tex.sample(s, uv).rgb;

    // 3. COLOR TARGETING & "INK" MAPPING
    float3 targetRed = float3(0.536, 0.155, 0.148);
    float3 physicalBG = float3(0.584, 0.576, 0.431); // Your 149, 147, 110
    
    // We define "LCD Black" as a very dark version of the background
    float3 lcdBlack = physicalBG * 0.15; 
    
    float3 activeColor;
    bool isRed = (sourceCol.r > 0.7 && sourceCol.g < 0.3 && sourceCol.b < 0.3);

    if (isRed) {
        activeColor = targetRed;
    } else {
        // We blend between our "LCD Black" and the background based on game color.
        // This ensures $(0,0,0)$ becomes our dark olive ink.
        activeColor = mix(lcdBlack, physicalBG, sourceCol.r); 
    }

    // 4. GRID MASK
    float2 gridFract = fract(pixelCoord);
    float mask = step(u.pixelSeparation, gridFract.x) * step(gridFract.x, 1.0 - u.pixelSeparation) *
                 step(u.pixelSeparation, gridFract.y) * step(gridFract.y, 1.0 - u.pixelSeparation);

    // 5. GRID LERP (Shadow logic)
    // The grid lines should be even darker than the "Black Ink" to stay visible.
    float3 gridLineColor = lcdBlack * 0.5; 
    
    // If mask > 0.5 (Inside pixel), show activeColor.
    // If mask < 0.5 (Grid line), show gridLineColor.
    float3 finalColor = mix(gridLineColor, activeColor, (mask > 0.5 ? 1.0 : (1.0 - u.gridStrength)));

    return float4(finalColor * u.brightnessBoost * u.colorBoost, 1.0);
}

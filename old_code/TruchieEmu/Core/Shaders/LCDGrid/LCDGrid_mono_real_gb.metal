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
    
    float2 scaledCoord = (in.position.xy - offset) / intScale;
    float2 pixelIndex = floor(scaledCoord);
    float2 pixelFract = fract(scaledCoord);

    if (pixelIndex.x < 0.0 || pixelIndex.x >= gameRes.x ||
        pixelIndex.y < 0.0 || pixelIndex.y >= gameRes.y) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // 2. RAW DATA SAMPLE
    float2 uv = (pixelIndex + 0.5) / gameRes;
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 sourceCol = tex.sample(s, uv).rgb;
    
    float inkAmount = 1.0 - sourceCol.r;
    bool isRed = (sourceCol.r > 0.7 && sourceCol.g < 0.3 && sourceCol.b < 0.3);

    // 3. TARGET COLOR PALETTE & TEXTURE
    // Updated background color to match the reference image
    float3 baseBgColor = float3(0.487, 0.569, 0.272);
    // Darkened the ink slightly to maintain contrast with the new richer background
    float3 inkColor    = float3(0.140, 0.200, 0.080);
    
    if (isRed) {
        inkColor = float3(0.450, 0.200, 0.200); // Muted red
        inkAmount = 1.0;
    }

    // Subtle noise texture for the reflective foil
    float noise = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
    float3 texturedBg = baseBgColor * (0.97 + 0.03 * noise);

    // 4. DROP SHADOW (Depth)
    float2 shadowUV = (pixelIndex + float2(-1.0, -1.0) + 0.5) / gameRes;
    float3 shadowCol = tex.sample(s, shadowUV).rgb;
    float shadowInkAmount = 1.0 - shadowCol.r;
    
    // Softened shadow to match the muted aesthetic
    texturedBg *= (1.0 - shadowInkAmount * 0.12);

    // 5. CELL COLOR (The physical LCD pixel)
    float3 cellOffColor = texturedBg * 0.95; // Faint outline when off
    float3 cellActiveColor = mix(texturedBg, inkColor, 0.90);
    float3 finalCellColor = mix(cellOffColor, cellActiveColor, inkAmount);

    // 6. VISIBLE GRID MASK
    // Enforce a distinct gap. If u.pixelSeparation is 0, we still want a tiny physical gap.
    float gap = max(u.pixelSeparation, 0.15);
    
    // Calculate distance from center of the pixel (0.0 to 0.5)
    float2 dist = abs(pixelFract - 0.5);
    
    // Smoothstep creates the slight softness on the edge of the pixel crystal
    float edge0 = 0.5 - gap;
    float edge1 = 0.5 - (gap * 0.4);
    
    float maskX = 1.0 - smoothstep(edge0, edge1, dist.x);
    float maskY = 1.0 - smoothstep(edge0, edge1, dist.y);
    float mask = maskX * maskY;

    // 7. FINAL COMPOSITING
    // The gaps between pixels are slightly darker than the flat background foil
    float3 gapColor = texturedBg * 0.92;
    
    float blendFactor = mix(1.0, mask, u.gridStrength);
    float3 finalColor = mix(gapColor, finalCellColor, blendFactor);

    return float4(finalColor * u.brightnessBoost * u.colorBoost, 1.0);
}

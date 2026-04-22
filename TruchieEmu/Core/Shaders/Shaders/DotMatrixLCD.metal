#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct DotMatrixLCDUniforms {
    float dotOpacity;
    float metallicIntensity;
    float specularShininess;
    float colorBoost;
    float4 sourceSize;
    float4 outputSize;
};

// PCG Hash for stable organic randomness
float pcg_hash(float2 p) {
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

fragment float4 fragmentDotMatrixLCD(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     constant DotMatrixLCDUniforms &u [[buffer(0)]]) {
    
    const float2 gbcRes = u.sourceSize.xy;
    const float2 uv = in.texCoord;
    const float2 pixelIndex = floor(uv * gbcRes);
    
    // 1. ORGANIC JITTER & NOISE
    float noise = pcg_hash(uv * 4000.0);
    float2 jiggle = float2(pcg_hash(pixelIndex * 1.1),
                           pcg_hash(pixelIndex * 2.2)) * 0.0015;
    
    // 2. SAMPLING & HARDWARE COLOR MATRIX
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 rawColor = tex.sample(s, uv + (jiggle * 0.2));
    
    const float3x3 gbcMatrix = float3x3(
        0.82, 0.15, 0.03,
        0.10, 0.75, 0.15,
        0.08, 0.10, 0.82
    );
    
    float3 screenColor = (rawColor.rgb * gbcMatrix) * u.colorBoost * 1.44;

    // 3. ORGANIC PIXEL VARIANCE
    float pVar = pcg_hash(pixelIndex * 3.3);
    float pVarColor = pcg_hash(pixelIndex * 4.4);
    screenColor *= (0.97 + pVar * 0.06);
    screenColor.r *= (0.98 + pVarColor * 0.04);
    screenColor.b *= (0.98 + (1.0 - pVarColor) * 0.04);
    
    // --- 4. ENHANCED NEWTON'S RINGS ---
    float2 ringCenter = float2(1.1, -0.1);
    float distToCenter = distance(uv, ringCenter);
    
    // Increased frequency (18.0) and bumped intensity to 0.045
    float3 rainbow = float3(
        sin(distToCenter * 18.0 + 0.0),
        sin(distToCenter * 18.0 + 2.0),
        sin(distToCenter * 18.0 + 4.0)
    );
    // Sharpen the bands for a more "oily" look
    rainbow = pow(saturate(rainbow * 0.5 + 0.5), 2.0) * 0.045;

    // 5. BLACK FLOOR LIFT & SUBSTRATE
    const float3 gbcPanelColor = float3(0.18, 0.19, 0.17);
    float3 blackFloor = gbcPanelColor * 0.16;
    screenColor = max(screenColor, blackFloor);

    // 6. DYNAMIC GRID THICKNESS
    float luma = dot(rawColor.rgb, float3(0.299, 0.587, 0.114));
    float thickness = mix(0.24, 0.10, luma);
    float2 pixelCoord = uv * gbcRes;
    float2 fw = fwidth(pixelCoord);
    
    // 7. DYNAMIC SHADOW OFFSET
    float2 lightOrigin = float2(1.0, 0.0);
    float2 lightToPixel = normalize(uv - lightOrigin);
    float physicalGapDepth = 0.22;
    float2 dynamicShadowOffset = lightToPixel * physicalGapDepth;

    float2 shadowGridPos = fract(pixelCoord + dynamicShadowOffset);
    float2 shadowBox = smoothstep(thickness - fw, thickness, shadowGridPos) * (1.0 - smoothstep(1.0 - thickness, 1.0 - thickness + fw, shadowGridPos));
    float shadowMask = shadowBox.x * shadowBox.y;

    // 8. MAIN PIXEL GRID
    float2 gridPos = fract(pixelCoord + (noise * 0.02));
    float2 box = smoothstep(thickness - fw, thickness, gridPos) * (1.0 - smoothstep(1.0 - thickness, 1.0 - thickness + fw, gridPos));
    float gapMask = box.x * box.y;

    // 9. HARDWARE BACKGROUND & TOP-RIGHT GLARE
    float distToLight = distance(uv, lightOrigin);
    float diffuseReflection = 1.0 - smoothstep(0.0, 0.79, distToLight);
    
    float subtleGlint = diffuseReflection * (u.specularShininess * 0.038);
    float3 reflectionColor = (float3(0.92, 0.96, 1.0) + rainbow) * subtleGlint;

    // 10. DEPTH & TRANSPARENCY
    float leakageIntensity = 0.09;
    float3 leakedLight = screenColor * leakageIntensity;
    float3 backgroundWithShadow = mix(gbcPanelColor * 0.50 + leakedLight, gbcPanelColor + leakedLight, shadowMask);
    
    float pixelAlpha = saturate(rawColor.a) * 0.8;
    float3 activePixel = mix(backgroundWithShadow, screenColor, pixelAlpha);
    
    // 11. FINAL COMPOSITE
    float3 pixelWithGrid = mix(backgroundWithShadow, activePixel, gapMask);
    float3 baseMix = mix(activePixel, pixelWithGrid, u.dotOpacity);
    
    float3 finalRGB = baseMix + reflectionColor + (noise - 0.5) * 0.015;

    return float4(finalRGB, 1.0);
}

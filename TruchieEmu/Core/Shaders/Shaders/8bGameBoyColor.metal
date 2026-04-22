/*
 * TruchieEmu: 8bit Game Boy Color Hardware Simulation
 * * Signature updated for temporal feedback loops and dynamic hardware instability.
 */

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct GBCUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float physicalDepth;    // Controlled depth for parallax
    float ghostingWeight;   // Decay factor (0.6 for ~3 frames)
    uint  frameIndex;       // Used for temporal variance
};

// PCG Hash for stable hardware randomness
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

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> currentFrame [[texture(0)]],
                                texture2d<float> previousFrame [[texture(1)]],
                                constant GBCUniforms &u [[buffer(0)]]) {
    
    const float2 gbcRes = float2(160.0, 144.0);
    const float2 uv = in.texCoord;
    const float2 pixelIndex = floor(uv * gbcRes);
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    
    // 1. TEMPORAL FEEDBACK (3-FRAME GHOSTING)
    float4 now = currentFrame.sample(s, uv);
    float4 then = previousFrame.sample(s, uv);
    
    // Defaulting ghostingWeight to 0.6 if not provided
    float weight = (u.ghostingWeight > 0.0) ? u.ghostingWeight : 0.6;
    float3 ghostedRGB = mix(now.rgb, then.rgb, weight);
    float4 rawColor = float4(ghostedRGB, now.a);

    // 2. HARDWARE JITTER & NOISE (Breathes with frameIndex)
    float timeSeed = float(u.frameIndex % 60) * 0.01;
    float noise = pcg_hash(uv * 4000.0 + timeSeed);
    float2 jiggle = float2(pcg_hash(pixelIndex * 1.1 + timeSeed),
                           pcg_hash(pixelIndex * 2.2 + timeSeed)) * 0.0012;
    
    // 3. COLOR TRANSFORMATION
    // Standard GBC matrix + subtle boost
    const float3x3 gbcMatrix = float3x3(
        0.82, 0.15, 0.03,
        0.10, 0.75, 0.15,
        0.08, 0.10, 0.82
    );
    float3 screenColor = (rawColor.rgb * gbcMatrix) * u.colorBoost * 1.44;

    // 4. SUBPIXEL INSTABILITY
    float pVar = pcg_hash(pixelIndex * 3.3);
    float pVarColor = pcg_hash(pixelIndex * 4.4);
    screenColor *= (0.97 + pVar * 0.06); 
    screenColor.r *= (0.98 + pVarColor * 0.04);
    screenColor.b *= (0.98 + (1.0 - pVarColor) * 0.04);
    
    // 5. NEWTON'S RINGS (IRIDESCENCE)
    float2 ringCenter = float2(1.1, -0.1); 
    float distToCenter = distance(uv, ringCenter);
    float3 rainbow = float3(
        sin(distToCenter * 18.0 + 0.0),
        sin(distToCenter * 18.0 + 2.0),
        sin(distToCenter * 18.0 + 4.0)
    );
    rainbow = pow(saturate(rainbow * 0.5 + 0.5), 2.0) * 0.045;

    // 6. SUBSTRATE PANEL
    const float3 gbcPanelColor = float3(0.18, 0.19, 0.17); 
    screenColor = max(screenColor, gbcPanelColor * 0.16);

    // 7. DOT MATRIX & PARALLAX SHADOWS
    float luma = dot(rawColor.rgb, float3(0.299, 0.587, 0.114));
    float thickness = mix(0.24, 0.10, luma);
    float2 pixelCoord = uv * gbcRes;
    float2 fw = fwidth(pixelCoord);
    
    // Light is fixed Top-Right
    float2 lightOrigin = float2(1.0, 0.0);
    float2 lightToPixel = normalize(uv - lightOrigin);
    float2 dynamicShadowOffset = lightToPixel * (u.physicalDepth > 0.0 ? u.physicalDepth : 0.22);

    float2 shadowGridPos = fract(pixelCoord + dynamicShadowOffset);
    float shadowMask = smoothstep(thickness - fw, thickness, shadowGridPos.x) * (1.0 - smoothstep(1.0 - thickness, 1.0 - thickness + fw, shadowGridPos.x)) *
                       smoothstep(thickness - fw, thickness, shadowGridPos.y) * (1.0 - smoothstep(1.0 - thickness, 1.0 - thickness + fw, shadowGridPos.y));

    float2 gridPos = fract(pixelCoord + (noise * 0.015));
    float gapMask = smoothstep(thickness - fw, thickness, gridPos.x) * (1.0 - smoothstep(1.0 - thickness, 1.0 - thickness + fw, gridPos.x)) *
                    smoothstep(thickness - fw, thickness, gridPos.y) * (1.0 - smoothstep(1.0 - thickness, 1.0 - thickness + fw, gridPos.y));

    // 8. GLARE (Top-Right)
    float diffuseReflection = 1.0 - smoothstep(0.0, 0.79, distance(uv, lightOrigin));
    float3 reflectionColor = (float3(0.92, 0.96, 1.0) + rainbow) * (u.specularShininess * 0.038) * diffuseReflection;

    // 9. FINAL MIX
    float3 background = mix(gbcPanelColor * 0.50 + (screenColor * 0.09), gbcPanelColor + (screenColor * 0.09), shadowMask);
    float3 activePixel = mix(background, screenColor, saturate(rawColor.a) * 0.8);
    float3 pixelWithGrid = mix(background, activePixel, gapMask);
    
    float3 baseMix = mix(activePixel, pixelWithGrid, u.dotOpacity);
    float3 finalRGB = baseMix + reflectionColor + (noise - 0.5) * 0.015;

    return float4(finalRGB, 1.0);
}
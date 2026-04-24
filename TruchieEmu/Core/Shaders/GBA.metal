#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct GBAUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float ghostingWeight;
    uint frameIndex;
    float4 sourceSize; // xy: 240, 160
    float4 outputSize; // xy: Current Window Width/Height
};

fragment float4 fragmentGBAShader(VertexOut in [[stage_in]],
                                  texture2d<float> frame0 [[texture(0)]],
                                  texture2d<float> frame1 [[texture(1)]],
                                  texture2d<float> frame2 [[texture(2)]],
                                  constant GBAUniforms &u [[buffer(0)]]) {
    
    // 1. COORDINATE SETUP
    float2 uv = in.texCoord;
    float2 gbaRes = u.sourceSize.xy;
    
    // Determine the scaling ratio to keep grid lines consistent
    float2 pixelCoord = uv * gbaRes;
    
    // 2. TEMPORAL GHOSTING
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 f0 = frame0.sample(s, uv).rgb;
    float3 f1 = frame1.sample(s, uv).rgb;
    float3 f2 = frame2.sample(s, uv).rgb;
    float3 ghostedColor = mix(f0, f1, u.ghostingWeight);
    ghostedColor = mix(ghostedColor, f2, u.ghostingWeight * 0.5);

    // 3. COLOR CORRECTION (GBA Specific)
    const float3x3 gbaMatrix = float3x3(
        0.84, 0.16, 0.00,
        0.08, 0.76, 0.16,
        0.08, 0.08, 0.84
    );
    float3 screenColor = (ghostedColor * gbaMatrix) * u.colorBoost;

    // 4. ANTI-MOIRÉ GRID CALCULATION
    // We use fwidth to determine how many 'LCD pixels' fit into one 'screen pixel'
    float2 gridUV = fract(pixelCoord);
    float2 delta = fwidth(pixelCoord); 
    
    // Dynamic thickness based on luma
    float luma = dot(ghostedColor, float3(0.299, 0.587, 0.114));
    float thickness = mix(0.15, 0.05, luma);
    
    // Smoothstep using the derivative (delta) prevents Aliasing/Moiré
    // It creates a "box filter" that averages the grid line over the display pixel
    float2 grid = smoothstep(0.5 - thickness - delta, 0.5 - thickness, abs(gridUV - 0.5)) +
                  smoothstep(0.5 - thickness + delta, 0.5 - thickness, abs(gridUV - 0.5));
    float gapMask = saturate(grid.x * grid.y);

    // 5. SUBSTRATE & LIGHTING
    const float3 gbaPanelColor = float3(0.12, 0.13, 0.11);
    float3 activePixel = mix(gbaPanelColor, screenColor, gapMask);
    
    // 6. FINAL REFLECTION & GLARE
    float2 ringCenter = float2(1.1, -0.1);
    float distToCenter = distance(uv, ringCenter);
    float3 rainbow = float3(sin(distToCenter*22.0), sin(distToCenter*22.0+2.0), sin(distToCenter*22.0+4.0));
    rainbow = pow(saturate(rainbow * 0.5 + 0.5), 2.5) * 0.02;

    float glare = (1.0 - smoothstep(0.0, 0.9, distance(uv, float2(0.9, 0.1)))) * (u.specularShininess * 0.04);
    
    float3 finalRGB = mix(screenColor, activePixel, u.dotOpacity) + (float3(0.9, 0.95, 1.0) + rainbow) * glare;

    return float4(finalRGB, 1.0);
}
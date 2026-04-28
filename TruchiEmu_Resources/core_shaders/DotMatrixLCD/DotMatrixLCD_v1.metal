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

fragment float4 fragmentDotMatrixLCD(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     constant DotMatrixLCDUniforms &u [[buffer(0)]]) {
    
    // 1. GBC "Off" State
    const float3 gbcPanelColor = float3(0.12, 0.12, 0.14);

    // 2. Sampling
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    float4 rawColor = tex.sample(s, in.texCoord);
    
    // Keeping background colors at the previous 1.44 boost
    float3 screenColor = (rawColor.rgb * u.colorBoost) * 1.44;

    // 3. Grid Logic
    float2 pixelCoord = in.texCoord * u.sourceSize.zw;
    float2 gridPos = fract(pixelCoord);
    float dist = distance(gridPos, float2(0.5));
    float dotMask = smoothstep(0.5, 0.5 - u.metallicIntensity, dist);
    
    // 4. THE REFLECTION
    float2 lightDir = normalize(float2(1.0, -1.0));
    float2 viewDir = in.texCoord - float2(0.5);
    float reflection = saturate(dot(viewDir, lightDir));
    
    // UPDATED: Another 30% increase to light/glint
    // (Previous 0.173 * 1.3 = ~0.225 total intensity)
    float subtleGlint = pow(reflection, 6.0) * (u.specularShininess * 0.225);
    
    float3 reflectionColor = float3(0.9, 0.95, 1.0) * subtleGlint;

    // 5. Final Composite
    float3 pixelWithGrid = mix(gbcPanelColor, screenColor, dotMask);
    float3 baseMix = mix(screenColor, pixelWithGrid, u.dotOpacity);
    float3 finalRGB = baseMix + reflectionColor;

    return float4(finalRGB, rawColor.a);
}

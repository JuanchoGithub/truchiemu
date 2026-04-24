#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// LCD Grid Shader (Classic Handheld)
// Simulates sub-pixel layout and a clean grid.
// ============================================================
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
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float4 color = tex.sample(s, uv);
    
    // Position within the source pixel
    float2 pixelPos = fract(uv * u.sourceSize.xy);
    
    // Grid calculation
    float2 grid = smoothstep(0.5 - u.pixelSeparation, 0.5, abs(pixelPos - 0.5));
    float gridMask = 1.0 - max(grid.x, grid.y) * u.gridStrength;
    
    // Sub-pixel effect (RGB vertical stripes)
    float subpixelSub = fract(in.position.x / 3.0);
    float3 subpixelMask = float3(1.0);
    if (subpixelSub < 0.33) subpixelMask = float3(1.1, 0.8, 0.8);
    else if (subpixelSub < 0.66) subpixelMask = float3(0.8, 1.1, 0.8);
    else subpixelMask = float3(0.8, 0.8, 1.1);
    
    color.rgb *= gridMask;
    color.rgb *= subpixelMask;
    color.rgb *= u.brightnessBoost;
    color.rgb *= u.colorBoost;
    
    color.a = 1.0;
    return color;
}

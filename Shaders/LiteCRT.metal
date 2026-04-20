#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// Simple Scanlines + Phosphor (Lite CRT)
// Very lightweight, good for performance.
// ============================================================
struct LiteCRTUniforms {
    float scanlineIntensity;
    float phosphorStrength;
    float brightness;
    float colorBoost;
};

fragment float4 fragmentLiteCRT(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LiteCRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float4 color = tex.sample(s, uv);
    
    // Scanlines
    float scanline = sin(uv.y * 800.0) * 0.5 + 0.5;
    color.rgb *= 1.0 - u.scanlineIntensity * scanline;
    
    // Simple Phosphor Mask
    float phosphor = sin(in.position.x * 1.5) * 0.5 + 0.5;
    color.rgb *= 1.0 - u.phosphorStrength * phosphor;
    
    color.rgb *= u.brightness;
    color.rgb *= u.colorBoost;
    color.a = 1.0;
    return color;
}

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// ScaleSmooth Shader (Pixel-Art Upscaler)
// Smooths edges of pixel art using advanced interpolation.
// ============================================================
struct ScaleSmoothUniforms {
    float smoothness;
    float colorBoost;
    float4 sourceSize;
};

fragment float4 fragmentScaleSmooth(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     constant ScaleSmoothUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float2 texSize = u.sourceSize.xy;
    float2 invSize = u.sourceSize.zw;
    
    // Smooth pixel art interpolation logic
    float2 p = uv * texSize - 0.5;
    float2 i = floor(p);
    float2 f = p - i;
    
    // Cubic-like smoothing curve
    float2 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float2 smoothUV = (i + 0.5 + w) * invSize;
    
    float4 color = tex.sample(s, smoothUV);
    
    // Mix with sharp bilinear to control smoothness
    if (u.smoothness < 1.0) {
        float4 sharp = tex.sample(s, uv); // simplified sharp
        color = mix(sharp, color, u.smoothness);
    }
    
    color.rgb *= u.colorBoost;
    color.a = 1.0;
    return color;
}

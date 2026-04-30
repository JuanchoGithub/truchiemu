#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// Sharp Bilinear Shader
// Pre-scales the source to the largest possible integer size,
// then uses bilinear for the remaining fractional scale.
// This preserves sharp pixel edges while avoiding "shimmering".
// ============================================================
struct SharpBilinearUniforms {
    float sharpness;     // 0.0 - 1.0: 1.0 is sharpest
    float colorBoost;
    float scanlineOpacity;
    float _pad;
    float4 sourceSize;
    float4 outputSize;
};

fragment float4 fragmentSharpBilinear(VertexOut in [[stage_in]],
                                        texture2d<float> tex [[texture(0)]],
                                        constant SharpBilinearUniforms &u [[buffer(0)]]) {
    constexpr sampler s_linear(filter::linear, address::clamp_to_edge);
    
    float2 texSize = u.sourceSize.xy;
    float2 uv = in.texCoord;
    
    // Calculate the target pixel coordinate
    float2 texel = uv * texSize;
    float2 texel_floor = floor(texel);
    float2 texel_fract = texel - texel_floor;
    
    // Sharpening logic: adjust the fractional part
    float2 region = 0.5 - 0.5 / u.sharpness;
    texel_fract = saturate((texel_fract - region) / (1.0 - 2.0 * region));
    
    // Map back to UV
    float2 final_uv = (texel_floor + 0.5 + (texel_fract - 0.5)) / texSize;
    
    float4 color = tex.sample(s_linear, final_uv);
    
    // Optional: simple scanline overlay
    if (u.scanlineOpacity > 0.0) {
        float scanline = sin(uv.y * texSize.y * M_PI_F * 2.0) * 0.5 + 0.5;
        color.rgb *= 1.0 - u.scanlineOpacity * scanline;
    }
    
    color.rgb *= u.colorBoost;
    color.a = 1.0;
    return color;
}

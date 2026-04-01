#include <metal_stdlib>
#include "ShaderTypes.h.metal"
using namespace metal;

// MARK: - Passthrough Shader
// No post-processing. Integer-scaled raw pixels with nearest-neighbor filtering.
// Best for: Purist pixel-accurate rendering (NES, GB, SNES, Genesis)

// MARK: - Fragment Shader

fragment float4 fragmentPassthrough(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]]) {
    // Nearest-neighbor sampling (no filtering)
    constexpr sampler s(filter::nearest, address::clamp_to_edge, mip_filter::none);
    
    float4 color = tex.sample(s, in.texCoord);
    color.a = 1.0;
    
    return color;
}
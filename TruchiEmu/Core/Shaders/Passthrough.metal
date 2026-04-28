#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// MARK: - Passthrough Shader (No Filter)
fragment float4 fragmentPassthrough(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge, mip_filter::none);
    float4 color = tex.sample(s, in.texCoord);
    color.a = 1.0;
    return color;
}

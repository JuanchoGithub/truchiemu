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

// MARK: - Letterbox Blit (Bilinear, Force Alpha)
//
// Reads from a source-sized offscreen texture (typically the slang chain's
// output for PassFeedback chains) and writes to the destination at the
// viewer's letterbox rectangle. The viewport is set to the letterbox rect
// in the drawable by the caller, so the vertex shader's NDC quad covers
// exactly the visible portion of the chain output. Bilinear filtering
// smooths the upscale; alpha is forced to 1 to match the alpha fixup
// that the slang path applies when rendering directly to the drawable.
fragment float4 fragmentLetterboxBlit(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge, mip_filter::none);
    float4 color = tex.sample(s, in.texCoord);
    color.a = 1.0;
    return color;
}

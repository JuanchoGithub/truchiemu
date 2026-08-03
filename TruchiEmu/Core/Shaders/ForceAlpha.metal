#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// MARK: - Force-Alpha Fragment Pass
//
// Reads the bound input texture (the slang-rendered drawable) and writes back
// the same RGB values with alpha forced to 1.0. Used as a final pass after
// `slang_mtl_filter_chain_frame` to repair the alpha channel that librashader
// leaves at 0.0 (librashader clears each render pass to clearColor alpha=0;
// slang fragment shaders do not modify alpha; the result is a fully
// transparent drawable whose contents are dropped by the window compositor).
//
// The output color is identical to the existing `fragmentPassthrough` so a
// separate dedicated function is unnecessary; this file exists to make the
// post-slang fix-up pass self-documenting and discoverable in code search.
fragment float4 fragmentForceAlpha(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge, mip_filter::none);
    float4 color = tex.sample(s, in.texCoord);
    color.a = 1.0;
    return color;
}

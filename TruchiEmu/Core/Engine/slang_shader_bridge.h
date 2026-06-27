#ifndef slang_shader_bridge_h
#define slang_shader_bridge_h

#import <Metal/Metal.h>
#define LIBRA_RUNTIME_METAL 1
#import "../../lib/librashader.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Create a Metal filter chain from a shader preset.
/// The preset is invalidated after this call.
libra_error_t slang_mtl_filter_chain_create(libra_shader_preset_t *preset,
                                            id<MTLCommandQueue> queue,
                                            struct filter_chain_mtl_opt_t *options,
                                            libra_mtl_filter_chain_t *out);

/// Record filter chain rendering commands for a frame.
libra_error_t slang_mtl_filter_chain_frame(libra_mtl_filter_chain_t *chain,
                                           id<MTLCommandBuffer> command_buffer,
                                           size_t frame_count,
                                           id<MTLTexture> image,
                                           id<MTLTexture> output,
                                           const struct libra_viewport_t *viewport,
                                           const float *mvp,
                                           const struct frame_mtl_opt_t *opt);

/// Set a parameter on the filter chain.
libra_error_t slang_mtl_filter_chain_set_param(libra_mtl_filter_chain_t *chain,
                                               const char *param_name,
                                               float value);

/// Free a Metal filter chain.
libra_error_t slang_mtl_filter_chain_free(libra_mtl_filter_chain_t *chain);

#ifdef __cplusplus
}
#endif

#endif /* slang_shader_bridge_h */

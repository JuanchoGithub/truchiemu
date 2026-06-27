#define LIBRA_RUNTIME_METAL 1
#import "slang_shader_bridge.h"

libra_error_t slang_mtl_filter_chain_create(libra_shader_preset_t *preset,
                                            id<MTLCommandQueue> queue,
                                            struct filter_chain_mtl_opt_t *options,
                                            libra_mtl_filter_chain_t *out) {
    return libra_mtl_filter_chain_create(preset, queue, options, out);
}

libra_error_t slang_mtl_filter_chain_frame(libra_mtl_filter_chain_t *chain,
                                           id<MTLCommandBuffer> command_buffer,
                                           size_t frame_count,
                                           id<MTLTexture> image,
                                           id<MTLTexture> output,
                                           const struct libra_viewport_t *viewport,
                                           const float *mvp,
                                           const struct frame_mtl_opt_t *opt) {
    return libra_mtl_filter_chain_frame(chain, command_buffer, frame_count,
                                        image, output, viewport, mvp, opt);
}

libra_error_t slang_mtl_filter_chain_set_param(libra_mtl_filter_chain_t *chain,
                                               const char *param_name,
                                               float value) {
    return libra_mtl_filter_chain_set_param(chain, param_name, value);
}

libra_error_t slang_mtl_filter_chain_free(libra_mtl_filter_chain_t *chain) {
    return libra_mtl_filter_chain_free(chain);
}

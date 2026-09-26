// Resolves a Vulkan loader library for cores that create their own Vulkan
// instance (e.g. suyu, which renders headless to a CPU buffer). The core
// probes $LIBVULKAN_PATH first, then its host bundle Frameworks. This helper
// runs in both the app and the XPC service before a core loads, so a vendored
// MoltenVK in Application Support is found no matter which process hosts.
// See: src/video_core/vulkan_common/vulkan_library.cpp (OpenLibrary).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VulkanLibraryHelper : NSObject

/// First usable Vulkan library path, or nil when none is installed.
/// Order: $LIBVULKAN_PATH, vendored MoltenVK, host bundle Frameworks.
+ (nullable NSString *)resolveVulkanLibraryPath;

/// Points $LIBVULKAN_PATH at the resolved library when unset. No-op otherwise.
+ (void)ensureVulkanEnvironment;

@end

NS_ASSUME_NONNULL_END

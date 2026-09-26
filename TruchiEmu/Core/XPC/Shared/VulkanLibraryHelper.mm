#import "VulkanLibraryHelper.h"

@implementation VulkanLibraryHelper

+ (NSArray<NSString *> *)candidateFileNames {
    return @[@"libMoltenVK.dylib", @"libvulkan.1.dylib", @"libvulkan.dylib"];
}

+ (nullable NSString *)firstExistingIn:(NSURL *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [self candidateFileNames]) {
        NSString *path = [[dir URLByAppendingPathComponent:name] path];
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }
    // RetroArch-style framework layout.
    NSString *fw = [[[dir URLByAppendingPathComponent:@"MoltenVK.framework"]
                        URLByAppendingPathComponent:@"MoltenVK"] path];
    if ([fm fileExistsAtPath:fw]) {
        return fw;
    }
    return nil;
}

+ (nullable NSString *)resolveVulkanLibraryPath {
    NSFileManager *fm = [NSFileManager defaultManager];

    const char *env = getenv("LIBVULKAN_PATH");
    if (env && env[0] != '\0') {
        NSString *path = [NSString stringWithUTF8String:env];
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }

    NSURL *appSupport = [[fm URLsForDirectory:NSApplicationSupportDirectory
                                          inDomains:NSUserDomainMask] firstObject];
    if (appSupport) {
        NSURL *vendor = [[[appSupport URLByAppendingPathComponent:@"TruchiEmu"
                                                      isDirectory:YES]
                             URLByAppendingPathComponent:@"Vendor/MoltenVK"
                                            isDirectory:YES] URLByStandardizingPath];
        NSString *found = [self firstExistingIn:vendor];
        if (found) {
            return found;
        }
    }

    NSURL *frameworks = [[[[NSBundle mainBundle] bundleURL]
                             URLByAppendingPathComponent:@"Contents/Frameworks"
                                            isDirectory:YES] URLByStandardizingPath];
    NSString *bundled = [self firstExistingIn:frameworks];
    if (bundled) {
        return bundled;
    }

    return nil;
}

+ (void)ensureVulkanEnvironment {
    if (getenv("LIBVULKAN_PATH")) {
        return;
    }
    NSString *path = [self resolveVulkanLibraryPath];
    if (path) {
        setenv("LIBVULKAN_PATH", [path UTF8String], 1);
        NSLog(@"[Vulkan] LIBVULKAN_PATH=%@", path);
    } else {
        NSLog(@"[Vulkan] No Vulkan library found (checked $LIBVULKAN_PATH, "
              @"TruchiEmu/Vendor/MoltenVK, host bundle Frameworks)");
    }
}

@end

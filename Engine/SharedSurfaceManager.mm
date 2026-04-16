#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>

@interface SharedSurfaceManager : NSObject
+ (IOSurfaceRef)createSurfaceWithWidth:(int)w height:(int)h;
+ (void)writeToSurface:(IOSurfaceRef)surface data:(const void *)data pitch:(size_t)pitch width:(int)w height:(int)h;
@end

@implementation SharedSurfaceManager

+ (IOSurfaceRef)createSurfaceWithWidth:(int)w height:(int)h {
    NSDictionary *properties = @{
        (id)kIOSurfaceWidth: @(w),
        (id)kIOSurfaceHeight: @(h),
        (id)kIOSurfaceBytesPerElement: @(4),
        (id)kIOSurfacePixelFormat: @(1111970369), // 'BGRA'
        (id)kIOSurfaceIsGlobal: @YES
    };
    return IOSurfaceCreate((CFDictionaryRef)properties);
}

+ (void)writeToSurface:(IOSurfaceRef)surface data:(const void *)data pitch:(size_t)pitch width:(int)w height:(int)h {
    IOSurfaceLock(surface, 0, NULL);
    void *dest = IOSurfaceGetBaseAddress(surface);
    size_t destPitch = IOSurfaceGetBytesPerRow(surface);
    
    if (destPitch == pitch) {
        memcpy(dest, data, pitch * h);
    } else {
        // Row-by-row copy if pitches differ
        for (int y = 0; y < h; y++) {
            memcpy((uint8_t *)dest + (y * destPitch), (uint8_t *)data + (y * pitch), pitch);
        }
    }
    IOSurfaceUnlock(surface, 0, NULL);
}

@end

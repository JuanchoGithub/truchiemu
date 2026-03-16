#import <Foundation/Foundation.h>

@interface LibretroBridge : NSObject

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
              videoCallback:(void(^)(const void *data, int width, int height, int pitch))cb;

+ (void)stop;
+ (void)saveState;

@end

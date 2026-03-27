#import <Foundation/Foundation.h>

@interface LibretroBridge : NSObject

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
              videoCallback:(void(^)(const void *data, int width, int height, int pitch, int format))cb;

+ (void)stop;
+ (void)saveState;
+ (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
+ (void)setAnalogState:(int)index id:(int)id value:(int)value;
@end

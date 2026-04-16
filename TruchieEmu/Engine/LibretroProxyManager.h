#import <Foundation/Foundation.h>
#import "CoreRunnerProtocol.h"
#import <IOSurface/IOSurfaceObjC.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^VideoCallback)(const void *data, int width, int height, int pitch, int format);
typedef void(^AudioCallback)(const int16_t *data, size_t frames);
typedef void(^FailureCallback)(NSString *message);

@interface LibretroProxyManager : NSObject <TruchiCoreHostProtocol>

@property (nonatomic, copy, nullable) VideoCallback videoCallback;
@property (nonatomic, copy, nullable) AudioCallback audioCallback;
@property (nonatomic, copy, nullable) FailureCallback failureCallback;

+ (instancetype)sharedManager;

- (void)launchCore:(NSString *)dylibPath
           romPath:(NSString *)romPath
            coreID:(NSString *)coreID
          systemID:(nullable NSString *)systemID
         shaderDir:(nullable NSString *)shaderDir
             reply:(void(^)(BOOL success, NSDictionary * _Nullable avInfo))reply;

- (void)stopCore;
- (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
- (void)serializeStateWithReply:(void(^)(NSData * _Nullable data))reply;
- (void)unserializeState:(NSData *)data reply:(void(^)(BOOL success))reply;

@end

NS_ASSUME_NONNULL_END

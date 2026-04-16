#import <Foundation/Foundation.h>
#import "../Engine/libretro.h"
#import "LibretroProxyManager.h"
#import "LibretroBridge.h"

// We use the proxy manager heavily here.

#ifdef __cplusplus
extern "C" {
#endif
void RegisterCoreLogCallback(void(*)(const char *, int)) {}
#ifdef __cplusplus
}
#endif

@implementation LibretroBridge

+ (void)registerCoreLogger:(void(^)(const char *message, int level))logger {
    // Handled by Proxy Manager now (logs come via IPC)
    // We should ideally set this on the proxy manager so it can forward IPC logs.
}

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
                  shaderDir:(NSString *)shaderDir
              videoCallback:(void(^)(const void *data, int width, int height, int pitch, int format))videoCallback
                     coreID:(NSString *)coreID
            failureCallback:(void(^)(NSString *message))failureCallback {
    
    [[LibretroProxyManager sharedManager] setVideoCallback:videoCallback];
    [[LibretroProxyManager sharedManager] setFailureCallback:failureCallback];
    
    [[LibretroProxyManager sharedManager] launchCore:dylibPath
                                             romPath:romPath
                                              coreID:coreID
                                            systemID:nil
                                           shaderDir:shaderDir
                                               reply:^(BOOL success, NSDictionary * _Nullable avInfo) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (failureCallback) failureCallback(@"Failed to launch core via XPC.");
            });
        }
        // AV Info caching could be done here if needed.
    }];
}

+ (void)stop {
    [[LibretroProxyManager sharedManager] stopCore];
}

+ (void)waitForCompletion {
    // IPC is asynchronous; the stop command invalidates the connection.
}

+ (void)setLanguage:(int)language {}
+ (void)setLogLevel:(int)level {}

+ (void)setPaused:(BOOL)paused {}
+ (BOOL)isPaused { return NO; }

+ (void)saveState {
    // Will be bridged via Proxy
}

+ (NSData *)serializeState {
    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[LibretroProxyManager sharedManager] serializeStateWithReply:^(NSData * _Nullable data) {
        result = data;
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    return result;
}

+ (BOOL)unserializeState:(NSData *)data {
    __block BOOL result = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [[LibretroProxyManager sharedManager] unserializeState:data reply:^(BOOL success) {
        result = success;
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    return result;
}

+ (int)serializeSize { return 1024 * 1024; /* stub */ }

+ (void)setKeyState:(int)retroID pressed:(BOOL)pressed {
    [[LibretroProxyManager sharedManager] setKeyState:retroID pressed:pressed];
}

+ (void)setTurboState:(int)turboIdx active:(BOOL)active targetButton:(int)targetButton {}
+ (void)setAnalogState:(int)index id:(int)axisID value:(int)value {}

+ (int)currentRotation { return 0; }
+ (float)aspectRatio { return 1.33f; }

+ (NSString *)getOptionValueForKey:(NSString *)key { return @""; }
+ (void)setOptionValue:(NSString *)value forKey:(NSString *)key {}
+ (void)resetOptionToDefaultForKey:(NSString *)key {}
+ (void)resetAllOptionsToDefaults {}
+ (NSDictionary *)getOptionsDictionary { return @{}; }
+ (NSDictionary *)getCategoriesDictionary { return @{}; }

+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled {}
+ (void)resetCheats {}
+ (void)loadCoreForOptions:(NSString *)dylibPath coreID:(NSString *)coreID {}
+ (BOOL)isCoreLoadedForOptions { return NO; }

@end

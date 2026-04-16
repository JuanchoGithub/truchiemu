#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Protocol implemented by TruchiCoreRunner and called by the Main App (Host).
 */
@protocol TruchiCoreRunnerProtocol <NSObject>

/**
 * Initialize the core for a specific ROM.
 */
- (void)bootCoreWithPath:(NSString *)dylibPath
                 romPath:(NSString *)romPath
                  coreID:(NSString *)coreID
                systemID:(nullable NSString *)systemID
               shaderDir:(nullable NSString *)shaderDir
             withReply:(void (^)(BOOL success, NSDictionary * _Nullable avInfo))reply;

/**
 * Stop the emulation and unload the game.
 */
- (void)stopWithReply:(void (^)(void))reply;

/**
 * Set the state of a specific controller button.
 */
- (void)setKeyState:(int)retroID pressed:(BOOL)pressed;

/**
 * Set analog stick state.
 */
- (void)setAnalogStateWithIndex:(int)index id:(int)axisID value:(int)value;

/**
 * Trigger a save state and return the raw data.
 */
- (void)serializeWithReply:(void (^)(NSData * _Nullable data))reply;

/**
 * Load a save state from raw data.
 */
- (void)unserialize:(NSData *)data withReply:(void (^)(BOOL success))reply;

/**
 * Pause or resume the core.
 */
- (void)setPaused:(BOOL)paused;

/**
 * Update a core option.
 */
- (void)setOptionValue:(NSString *)value forKey:(NSString *)key;

@end

/**
 * Protocol implemented by the Main App (Host) and called by TruchiCoreRunner.
 */
@protocol TruchiCoreHostProtocol <NSObject>

/**
 * Notification that a new video frame is ready in the shared IOSurface.
 */
- (void)frameReadyWithSurface:(IOSurface *)surface 
                        width:(int)w 
                       height:(int)h 
                        pitch:(int)p 
                       format:(int)f 
                     rotation:(int)r;

/**
 * Audio samples are sent as raw data.
 * Note: For high-performance, we'll eventually move this to a shared memory ring buffer.
 */
- (void)audioSamplesReady:(NSData *)samples;

/**
 * Log a message from the core back to the Host.
 */
- (void)logMessage:(NSString *)message level:(int)level;

@end

NS_ASSUME_NONNULL_END

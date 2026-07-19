#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Define a type for the callback
typedef void (^CoreLoggerBlock)(const char *message, int level);
typedef void (^GameLoadedBlock)(const char *romPath);
typedef void (*FramePollCallbackType)(void);

@interface LibretroBridge : NSObject

// The function Swift will call
+ (void)registerCoreLogger:(CoreLoggerBlock)block;
+ (void)registerGameLoadedCallback:(GameLoadedBlock)block;
+ (void)setFramePollCallback:(nullable FramePollCallbackType)callback;

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
                  shaderDir:(nullable NSString *)shaderDir
              videoCallback:(void (^)(const void *data, int width, int height,
                                      int pitch, int format))cb
                     coreID:(NSString *)coreID
                   systemID:(nullable NSString *)systemID
                romFilename:(nullable NSString *)romFilename
           wiiControllerType:(int)wiiControllerType
            failureCallback:(nullable void (^)(NSString *message))failureCb;

+ (void)stop;
+ (void)waitForCompletion;
+ (void)cleanupInstance;
+ (void)saveState;
+ (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
+ (void)setKeyState:(int)retroID player:(int)port pressed:(BOOL)pressed;
+ (void)setTurboState:(int)turboIdx
               active:(BOOL)active
         targetButton:(int)targetButton;
+ (void)setAnalogState:(int)index id:(int)id value:(int)value;
+ (void)setAnalogStateForPlayer:(int)port stick:(int)index axis:(int)id value:(int)value;
+ (void)setAnalogButtonState:(int)retroID value:(int)value;
+ (void)setAnalogButtonState:(int)retroID player:(int)port value:(int)value;
+ (void)setLanguage:(int)language;
+ (void)setLogLevel:(int)level;
+ (void)setPaused:(BOOL)paused;
+ (BOOL)isPaused;

/* Save State Serialization — returns raw state data for slot-based saving */
+ (nullable NSData *)serializeState;
+ (BOOL)unserializeState:(NSData *)data;
+ (size_t)serializeSize;

/* Load a core (optionally with a ROM) to initialize its options */
+ (void)loadCoreForOptions:(NSString *)dylibPath coreID:(NSString *)coreID romPath:(nullable NSString *)romPath;
+ (BOOL)isCoreLoadedForOptions;

/* Core Options — called from Swift to get/set values */
+ (nullable NSString *)getOptionValueForKey:(NSString *)key;
+ (void)setOptionValue:(NSString *)value forKey:(NSString *)key;
+ (void)resetOptionToDefaultForKey:(NSString *)key;
+ (void)resetAllOptionsToDefaults;
+ (NSDictionary<NSString *, NSDictionary *> *_Nullable)getOptionsDictionary;
+ (NSDictionary<NSString *, NSDictionary *> *_Nullable)getCategoriesDictionary;

/* Input Descriptors — returns descriptors captured during core load */
+ (NSDictionary<NSString *, NSArray *> *_Nullable)getInputDescriptorsDictionary;

/* Rotation — returns 0, 1, 2, or 3 (0/90/180/270 degrees clockwise) */
+ (int)currentRotation;

/* Controller Port Device — set the device type for a controller port */
+ (void)setControllerPortDevice:(unsigned)port device:(unsigned)device;

/* Signal the core to re-read variables on the next retro_run() call */
+ (void)setVariablesUpdated;

/* Set the Genesis controller device type (0=auto, 513=3-button, 514=6-button) */
+ (void)setGenesisDeviceType:(unsigned)deviceType;

/* Set the Wii (Dolphin) controller device type for auto mode (0=auto, 513=Wiimote+Classic, 514=Wii U Pro) */
+ (void)setWiiControllerType:(unsigned)deviceType;

/* Geometry — returns the core-provided display aspect ratio from
 * retro_system_av_info */
+ (float)aspectRatio;

/* Audio — returns the core's audio sample rate from retro_system_av_info */
+ (double)audioSampleRate;

/* Cheat Management */
+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled;
+ (void)resetCheats;
+ (void)resetGame;
+ (void)applyCheats:
    (NSArray<NSDictionary *> *)cheats; // Array of {index, code, enabled}

/* Direct Memory Access for Cheats */
+ (nullable void *)getMemoryData:(unsigned)type
                        size:(size_t *_Nullable)
                          size; // type: RETRO_MEMORY_SYSTEM_RAM or
                                // RETRO_MEMORY_SAVE_RAM

+ (nullable void *)getMemoryDataUnsafe:(unsigned)type
                        size:(size_t *_Nullable)
                          size; // Lock-free variant for use inside retro_run callbacks

/* Save RAM Access - returns SAVE_RAM data as NSData for saving to disk */
+ (nullable NSData *)getSaveRAMData;
+ (BOOL)loadSaveRAMData:(nullable NSData *)data;

/* Save Directory Path - returns the configured save directory */
+ (NSString *)saveDirectoryPath;
+ (void)writeMemoryByte:(uint32_t)address value:(uint8_t)value;
+ (void)applyDirectMemoryCheats:
(NSArray<NSDictionary *> *)cheats; // Array of {address, value, enabled}

/* Keyboard Input — dispatches keyboard events to the core */
+ (void)dispatchKeyboardEvent:(unsigned)keycode
character:(unsigned)character
modifiers:(unsigned)modifiers
down:(BOOL)down;

/* Mouse Input — for RETRO_DEVICE_MOUSE */
+ (void)setMouseDeltaX:(int16_t)dx Y:(int16_t)dy;
+ (void)addMouseDelta:(int16_t)dx Y:(int16_t)dy; // Accumulates between frames
+ (void)setMouseButton:(int)button pressed:(BOOL)pressed;
+ (void)addMouseWheelDelta:(int16_t)delta;
+ (void)resetMouseDeltas;
+ (void)setAbsoluteMousePositionX:(int16_t)x Y:(int16_t)y override:(BOOL)override;

/* Pointer Input — for RETRO_DEVICE_POINTER (absolute coordinates) */
+ (void)setPointerX:(int16_t)x Y:(int16_t)y pressed:(BOOL)pressed;

/* Analog as Mouse — converts analog stick to mouse movement in bridge_input_poll */
+ (void)setAnalogAsMouseEnabled:(BOOL)enabled forPlayer:(int)player;
+ (void)setAnalogAsMouseSensitivity:(float)sensitivity forPlayer:(int)player;
+ (void)setAnalogAsMouseDeadzone:(float)deadzone forPlayer:(int)player;
+ (void)setAnalogAsMouseStick:(int)stickIndex forPlayer:(int)player;
+ (void)setAnalogMouseDeltaX:(int16_t)dx Y:(int16_t)dy;

/* Speed Control — multiplier applied to frame pacing (1.0 = normal) */
+ (void)setSpeedMultiplier:(float)multiplier;

/* Rewind — enable periodic state capture for time machine buffer */
+ (void)setRewindEnabled:(BOOL)enabled captureInterval:(unsigned)frames;

/* Rewind state capture callback — called from the emulation thread. Pass nil to clear. */
+ (void)setStateCaptureCallback:(nullable void (^)(NSData *state, uint64_t frameIndex))callback;

/* Audio — flush pending audio buffer after rewind state load */
+ (void)flushAudio;

    /* Time Machine — run exactly one retro_run() under the core lock while paused so the
       unserialized state gets rendered to the framebuffer. Safe to call while the run loop
       is parked in its paused branch (it sleeps without holding _coreLock). */
+ (void)runSingleFrame;

/* Time Machine — reset the internal frame counter (used for capture frame
   indexing) to `frameCount`. Called after scrubbing back so that future
   captures are indexed contiguously with the truncated buffer. Without this,
   resume from frame N keeps _frameCount at its pre-rewind value, and new
   captures are indexed at 1200+ even though the game state corresponds to
   the post-rewind "now" — making the timeline total appear to grow back to
   the pre-rewind duration instantly. */
+ (void)setFrameCount:(uint64_t)frameCount;
@end

NS_ASSUME_NONNULL_END

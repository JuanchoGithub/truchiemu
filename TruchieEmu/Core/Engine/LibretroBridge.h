#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Define a type for the callback
typedef void (^CoreLoggerBlock)(const char *message, int level);

@interface LibretroBridge : NSObject

// The function Swift will call
+ (void)registerCoreLogger:(CoreLoggerBlock)block;

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
                  shaderDir:(nullable NSString *)shaderDir
              videoCallback:(void (^)(const void *data, int width, int height,
                                      int pitch, int format))cb
                     coreID:(NSString *)coreID
            failureCallback:(nullable void (^)(NSString *message))failureCb;

+ (void)stop;
+ (void)waitForCompletion;
+ (void)saveState;
+ (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
+ (void)setTurboState:(int)turboIdx
               active:(BOOL)active
         targetButton:(int)targetButton;
+ (void)setAnalogState:(int)index id:(int)id value:(int)value;
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

/* Rotation — returns 0, 1, 2, or 3 (0/90/180/270 degrees clockwise) */
+ (int)currentRotation;

/* Geometry — returns the core-provided display aspect ratio from
 * retro_system_av_info */
+ (float)aspectRatio;

/* Cheat Management */
+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled;
+ (void)resetCheats;
+ (void)applyCheats:
    (NSArray<NSDictionary *> *)cheats; // Array of {index, code, enabled}

/* Direct Memory Access for Cheats */
+ (nullable void *)getMemoryData:(unsigned)type
                            size:(size_t *_Nullable)
                                     size; // type: RETRO_MEMORY_SYSTEM_RAM or
                                           // RETRO_MEMORY_SAVE_RAM
+ (void)writeMemoryByte:(uint32_t)address value:(uint8_t)value;
+ (void)applyDirectMemoryCheats:
    (NSArray<NSDictionary *> *)cheats; // Array of {address, value, enabled}
@end

NS_ASSUME_NONNULL_END

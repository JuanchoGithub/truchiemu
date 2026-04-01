#import <Foundation/Foundation.h>

@interface LibretroBridge : NSObject

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
              videoCallback:(void(^)(const void *data, int width, int height, int pitch, int format))cb
                     coreID:(NSString *)coreID;

+ (void)stop;
+ (void)saveState;
+ (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
+ (void)setAnalogState:(int)index id:(int)id value:(int)value;
+ (void)setLanguage:(int)language;
+ (void)setLogLevel:(int)level;
+ (void)setPaused:(BOOL)paused;
+ (BOOL)isPaused;

/* Save State Serialization — returns raw state data for slot-based saving */
+ (nullable NSData *)serializeState;
+ (BOOL)unserializeState:(NSData *)data;
+ (size_t)serializeSize;

/* Load a core without content to initialize its options (supports_no_game) */
+ (void)loadCoreForOptions:(NSString *)dylibPath coreID:(NSString *)coreID;
+ (BOOL)isCoreLoadedForOptions;

/* Core Options — called from Swift to get/set values */
+ (nullable NSString *)getOptionValueForKey:(NSString *)key;
+ (void)setOptionValue:(NSString *)value forKey:(NSString *)key;
+ (void)resetOptionToDefaultForKey:(NSString *)key;
+ (void)resetAllOptionsToDefaults;
+ (NSDictionary<NSString *, NSDictionary *> * _Nullable)getOptionsDictionary;
+ (NSDictionary<NSString *, NSDictionary *> * _Nullable)getCategoriesDictionary;

/* Rotation — returns 0, 1, 2, or 3 (0/90/180/270 degrees clockwise) */
+ (int)currentRotation;

/* Cheat Management */
+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled;
+ (void)resetCheats;
+ (void)applyCheats:(NSArray<NSDictionary *> * _Nonnull)cheats;  // Array of {index, code, enabled}

/* Direct Memory Access for Cheats */
+ (nullable void *)getMemoryData:(unsigned)type size:(size_t *_Nullable)size;  // type: RETRO_MEMORY_SYSTEM_RAM or RETRO_MEMORY_SAVE_RAM
+ (void)writeMemoryByte:(uint32_t)address value:(uint8_t)value;
+ (void)applyDirectMemoryCheats:(NSArray<NSDictionary *> * _Nonnull)cheats;  // Array of {address, value, enabled}
@end

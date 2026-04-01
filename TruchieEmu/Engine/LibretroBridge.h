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
@end

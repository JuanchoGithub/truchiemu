#import <Foundation/Foundation.h>
#import "LibretroBridge.h"
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>
#import "libretro.h"

// MARK: - LibretroBridge
// This Objective-C++ class dynamically loads and drives a libretro core dylib.

typedef void (^VideoFrameCallback)(const void *data, int width, int height, int pitch);

@interface LibretroBridgeImpl : NSObject {
    void *_dlHandle;
    fn_retro_init _retro_init;
    fn_retro_deinit _retro_deinit;
    fn_retro_set_environment _retro_set_environment;
    fn_retro_set_video_refresh _retro_set_video_refresh;
    fn_retro_set_audio_sample _retro_set_audio_sample;
    fn_retro_set_audio_sample_batch _retro_set_audio_sample_batch;
    fn_retro_set_input_poll _retro_set_input_poll;
    fn_retro_set_input_state _retro_set_input_state;
    fn_retro_load_game _retro_load_game;
    fn_retro_unload_game _retro_unload_game;
    fn_retro_run _retro_run;
    fn_retro_get_system_av_info _retro_get_system_av_info;
    fn_retro_serialize_size _retro_serialize_size;
    fn_retro_serialize _retro_serialize;
    fn_retro_unserialize _retro_unserialize;
    BOOL _running;
    VideoFrameCallback _videoCallback;
    NSString *_saveStatePath;
}
- (BOOL)loadDylib:(NSString *)path;
- (BOOL)launchROM:(NSString *)romPath videoCallback:(VideoFrameCallback)cb;
- (void)stop;
- (void)saveState;
- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch;
- (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
@end

static LibretroBridgeImpl *g_instance = nil;

// C logging callback
static void bridge_log_printf(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *format = [[NSString alloc] initWithUTF8String:fmt];
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *prefix = @"[Core]";
    switch (level) {
        case RETRO_LOG_DEBUG: prefix = @"[Core DEBUG]"; break;
        case RETRO_LOG_INFO:  prefix = @"[Core INFO]";  break;
        case RETRO_LOG_WARN:  prefix = @"[Core WARN]";  break;
        case RETRO_LOG_ERROR: prefix = @"[Core ERROR]"; break;
        default: break;
    }
    NSLog(@"%@ %@", prefix, message);
}

// C callbacks (forward to instance)
static bool bridge_environment(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if (data) *(bool*)data = true;
            return true;
            
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
            if (data) {
                struct retro_log_interface *log = (struct retro_log_interface *)data;
                log->log = bridge_log_printf;
            }
            return true;
        }
            
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
            NSString *emuDir = [appSupport stringByAppendingPathComponent:@"TruchieEmu"];
            [[NSFileManager defaultManager] createDirectoryAtPath:emuDir withIntermediateDirectories:YES attributes:nil error:nil];
            if (data) *(const char **)data = [emuDir UTF8String];
            return true;
        }
            
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            if (data) {
                enum retro_pixel_format fmt = *(const enum retro_pixel_format *)data;
                NSLog(@"[LibretroBridge] Core requested pixel format: %d", fmt);
                // We'll support whatever it wants and handle in shader/texture
                return true; 
            }
            return false;
        }

        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            if (data) {
                struct retro_variable *var = (struct retro_variable *)data;
                var->value = NULL;
            }
            return false; // Return false so core knows the variable isn't set
        }

        case RETRO_ENVIRONMENT_SET_GEOMETRY: {
            if (data) {
                struct retro_game_geometry *geom = (struct retro_game_geometry *)data;
                NSLog(@"[LibretroBridge] New geometry: %ux%u (Aspect: %f)", geom->base_width, geom->base_height, geom->aspect_ratio);
            }
            return true;
        }

        case RETRO_ENVIRONMENT_SET_ROTATION:
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
            return true;

        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            if (data) *(unsigned*)data = 1;
            return true;

        case RETRO_ENVIRONMENT_GET_LANGUAGE:
            if (data) *(unsigned*)data = RETRO_LANGUAGE_ENGLISH;
            return true;

        default:
            return false;
    }
}

static int16_t g_input_state[16];

static void bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (g_instance && data) {
        static int frameCount = 0;
        if (++frameCount % 120 == 0) {
            NSLog(@"[LibretroBridge] Periodic check: core is producing frames (%d)", frameCount);
        }
        [g_instance handleVideoData:data width:(int)width height:(int)height pitch:(int)pitch];
    }
}

static void bridge_audio_sample(int16_t left, int16_t right) {}
static size_t bridge_audio_sample_batch(const int16_t *data, size_t frames) { return frames; }
static void bridge_input_poll(void) {}
static int16_t bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port == 0 && device == RETRO_DEVICE_JOYPAD) {
        return (g_input_state[id & 0xF]) ? 32767 : 0;
    }
    return 0;
}

@implementation LibretroBridgeImpl

- (BOOL)loadDylib:(NSString *)path {
    _dlHandle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
    if (!_dlHandle) {
        NSLog(@"[LibretroBridge] dlopen failed: %s", dlerror());
        return NO;
    }

#define LOAD_SYM(name) \
    _##name = (fn_##name)dlsym(_dlHandle, #name); \
    if (!_##name) { NSLog(@"[LibretroBridge] Missing symbol: " #name); return NO; }

    LOAD_SYM(retro_init)
    LOAD_SYM(retro_deinit)
    LOAD_SYM(retro_set_environment)
    LOAD_SYM(retro_set_video_refresh)
    LOAD_SYM(retro_set_audio_sample)
    LOAD_SYM(retro_set_audio_sample_batch)
    LOAD_SYM(retro_set_input_poll)
    LOAD_SYM(retro_set_input_state)
    LOAD_SYM(retro_load_game)
    LOAD_SYM(retro_unload_game)
    LOAD_SYM(retro_run)
    LOAD_SYM(retro_get_system_av_info)
    LOAD_SYM(retro_serialize_size)
    LOAD_SYM(retro_serialize)
    LOAD_SYM(retro_unserialize)
#undef LOAD_SYM

    return YES;
}

- (BOOL)launchROM:(NSString *)romPath videoCallback:(VideoFrameCallback)cb {
    _videoCallback = cb;

    NSLog(@"[LibretroBridge] Initializing core callbacks...");
    if (_retro_set_environment) _retro_set_environment(bridge_environment);
    if (_retro_set_video_refresh) _retro_set_video_refresh(bridge_video_refresh);
    if (_retro_set_audio_sample) _retro_set_audio_sample(bridge_audio_sample);
    if (_retro_set_audio_sample_batch) _retro_set_audio_sample_batch(bridge_audio_sample_batch);
    if (_retro_set_input_poll) _retro_set_input_poll(bridge_input_poll);
    if (_retro_set_input_state) _retro_set_input_state(bridge_input_state);
    
    NSLog(@"[LibretroBridge] Calling retro_init...");
    if (_retro_init) _retro_init();

    NSLog(@"[LibretroBridge] Loading ROM from: %@", romPath);
    NSData *romData = [NSData dataWithContentsOfFile:romPath];
    if (!romData) {
        NSLog(@"[LibretroBridge] ROM not found or inaccessible: %@", romPath);
        return NO;
    }
    NSLog(@"[LibretroBridge] ROM loaded into memory (%lu bytes)", (unsigned long)romData.length);

    struct retro_game_info gi;
    gi.path = romPath.UTF8String;
    gi.data = romData.bytes;
    gi.size = romData.length;
    gi.meta = NULL;

    if (!_retro_load_game) {
        NSLog(@"[LibretroBridge] ERROR: retro_load_game symbol is NULL");
        return NO;
    }

    if (!_retro_load_game(&gi)) {
        NSLog(@"[LibretroBridge] retro_load_game failed for: %@", romPath);
        return NO;
    }
    NSLog(@"[LibretroBridge] retro_load_game succeeded");

    // Setup save state path
    _saveStatePath = [NSHomeDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"Library/Application Support/TruchieEmu/SaveStates/%@.state",
                       romPath.lastPathComponent]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_saveStatePath.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:nil];

    _running = YES;

    // Run loop at ~60fps (the emulation queue calls this)
    while (_running) {
        if (_retro_run) _retro_run();
        // Yield ~16ms
        [NSThread sleepForTimeInterval:1.0/60.0];
    }

    if (_retro_unload_game) _retro_unload_game();
    if (_retro_deinit) _retro_deinit();
    
    _running = NO;
    
    // Explicitly nullify callbacks to stop any pending handles
    _videoCallback = nil;
    
    return YES;
}

- (void)stop {
    _running = NO;
}

- (void)saveState {
    if (!_retro_serialize_size || !_retro_serialize) return;
    size_t sz = _retro_serialize_size();
    void *buf = malloc(sz);
    if (_retro_serialize(buf, sz)) {
        NSData *data = [NSData dataWithBytesNoCopy:buf length:sz];
        [data writeToFile:_saveStatePath atomically:YES];
        NSLog(@"[LibretroBridge] State saved to %@", _saveStatePath);
    } else {
        free(buf);
    }
}

- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch {
    if (_videoCallback) {
        _videoCallback(data, w, h, pitch);
    }
}

- (void)setKeyState:(int)retroID pressed:(BOOL)pressed {
    if (retroID >= 0 && retroID < 16) {
        g_input_state[retroID] = pressed ? 1 : 0;
    }
}

- (void)dealloc {
    if (_dlHandle) { dlclose(_dlHandle); }
    // No [super dealloc] needed for ARC
}
@end

@implementation LibretroBridge

+ (void)launchWithDylibPath:(NSString *)dylibPath romPath:(NSString *)romPath videoCallback:(void(^)(const void*, int, int, int))cb {
    if (g_instance) {
        [(LibretroBridgeImpl *)g_instance stop];
        [NSThread sleepForTimeInterval:0.1]; // Brief grace period
    }
    
    LibretroBridgeImpl *newInst = [[LibretroBridgeImpl alloc] init];
    g_instance = newInst;
    
    if ([newInst loadDylib:dylibPath]) {
        [newInst launchROM:romPath videoCallback:cb];
    }
}

+ (void)stop {
    if (g_instance) {
        [(LibretroBridgeImpl *)g_instance stop];
        g_instance = nil;
    }
}

+ (void)saveState {
    [(LibretroBridgeImpl *)g_instance saveState];
}

+ (void)setKeyState:(int)retroID pressed:(BOOL)pressed {
    if (g_instance) {
        [(LibretroBridgeImpl *)g_instance setKeyState:retroID pressed:pressed];
    }
}

@end


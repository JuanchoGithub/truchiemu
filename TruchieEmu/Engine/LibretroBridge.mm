#define GL_SILENCE_DEPRECATION
#import <Foundation/Foundation.h>
#import "LibretroBridge.h"
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import "libretro.h"
#include <atomic>
#include <algorithm>
#include <mach/mach_time.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>

// MARK: - Simple Ring Buffer for Audio
class AudioRingBuffer {
public:
    AudioRingBuffer(size_t capacity) : _capacity(capacity) {
        _buffer = (int16_t *)malloc(capacity * sizeof(int16_t));
        _readPtr = 0;
        _writePtr = 0;
        _fillCount = 0;
    }
    ~AudioRingBuffer() { free(_buffer); }

    size_t write(const int16_t *data, size_t count) {
        size_t written = 0;
        for (size_t i = 0; i < count; ++i) {
            if (_fillCount < _capacity) {
                _buffer[_writePtr] = data[i];
                _writePtr = (_writePtr + 1) % _capacity;
                _fillCount++;
                written++;
            } else {
                break; // Overflow
            }
        }
        return written;
    }

    size_t read(int16_t *data, size_t count) {
        size_t r = 0;
        for (size_t i = 0; i < count; ++i) {
            if (_fillCount > 0) {
                data[i] = _buffer[_readPtr];
                _readPtr = (_readPtr + 1) % _capacity;
                _fillCount--;
                r++;
            } else {
                break; // Underflow
            }
        }
        return r;
    }

    void clear() {
        _readPtr = 0;
        _writePtr = 0;
        _fillCount = 0;
    }

    size_t available() const { return _fillCount; }
    size_t capacity() const { return _capacity; }

private:
    int16_t *_buffer;
    size_t _capacity;
    size_t _readPtr;
    size_t _writePtr;
    std::atomic<size_t> _fillCount;
};

typedef void (^VideoFrameCallback)(const void *data, int width, int height, int pitch, int format);

@interface LibretroBridgeImpl : NSObject {
@public
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
    fn_retro_cheat_set _retro_cheat_set;
    fn_retro_cheat_reset _retro_cheat_reset;
    fn_retro_get_memory_data _retro_get_memory_data;
    fn_retro_get_memory_size _retro_get_memory_size;
    BOOL _running;
    VideoFrameCallback _videoCallback;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_audioSourceNode;
    AudioRingBuffer *_audioBuffer;
    
    // Scratch buffer for audio render block (avoiding malloc in real-time)
    int16_t *_audioRenderScratch;
    size_t _audioRenderScratchCapacity;
    
    CGLContextObj _glContext;
    struct retro_hw_render_callback _hw_callback;
    struct retro_system_av_info _avInfo;
    
    int _pixelFormat;
    BOOL _isMameLaunch;  // Enables MAME-specific timing/pixel-format fixes
    NSString *_saveStatePath;
    
    // Retain explicit resources so they outlive the emulation loop
    NSData *_retainedRomData;
    NSString *_retainedRomPath;
    
    void *_hwReadbackBuffer;
    size_t _hwReadbackBufferSize;
    BOOL _hwRenderEnabled;
    GLuint _hwFBO;        // The FBO the N64/HW core renders into
    GLuint _hwColorRB;    // Color renderbuffer backing the FBO
    GLuint _hwDepthRB;    // Depth renderbuffer backing the FBO
    int _fboWidth;
    int _fboHeight;
}
- (BOOL)loadDylib:(NSString *)path;
- (BOOL)launchROM:(NSString *)romPath videoCallback:(VideoFrameCallback)cb;
- (void)stop;
- (void)saveState;
- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch format:(int)format;
- (void)handleAudioSamples:(const int16_t *)data count:(size_t)count;
- (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
- (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx;
- (void)setAnalogState:(int)idx id:(int)id value:(int)v;
- (void)setPixelFormat:(int)format;
- (int)pixelFormat;
- (void)setupHWRender:(struct retro_hw_render_callback *)cb;
- (const void *)readHWRenderedPixels:(int)w height:(int)h;
@end

static LibretroBridgeImpl *g_instance = nil;
static int g_selectedLanguage = 0; // RETRO_LANGUAGE_ENGLISH
static int g_logLevel = 1; // 1 = Warn & Error
static NSString *g_coreID = nil;   // Core ID for options persistence
static NSString *g_shaderDir = nil; // Shader directory for libretro slang shaders
static BOOL g_isPaused = NO;    // Pause state
static int g_currentRotation = 0;   // Current rotation from core (0=0 deg, 1=90 deg CW, 2=180 deg, 3=270 deg CW)
// Shared with bridge_get_current_framebuffer — updated by setupHWRender
static GLuint g_hwFBO = 0;

/* ── Core Options Storage ──
 * Global mutable state so the C environment callback and Swift bridge methods
 * can both read/write option values without dispatching through libdispatch.
 * g_optValues: [optionKey: currentValue]  (NSString -> NSString)
 * g_optDefinitions: [optionKey: {desc, info, default, values[], category}]
 * g_optCategories: [categoryKey: {desc, info}]
 */
static NSMutableDictionary<NSString *, NSString *> *g_optValues = nil;
static NSDictionary<NSString *, NSDictionary *> *g_optDefinitions = nil;
static NSDictionary<NSString *, NSDictionary *> *g_optCategories = nil;

static void initOptStorage() {
    if (!g_optValues) {
        g_optValues = [NSMutableDictionary dictionary];
    }
}

/* Parse V2 definitions into the global dict.
 * Called from the C environment callback. */
__attribute__((unused)) static void parseCoreOptionsV2(struct retro_core_options_v2 *opts) {
    initOptStorage();
    [g_optValues removeAllObjects];
    
    NSMutableDictionary *defs = [NSMutableDictionary dictionary];
    NSMutableDictionary *cats = [NSMutableDictionary dictionary];
    
    /* Parse categories */
    if (opts && opts->categories) {
        struct retro_core_option_v2_category *cat = opts->categories;
        while (cat->key) {
            cats[[NSString stringWithUTF8String:cat->key]] = @{
                @"desc": cat->desc ? [NSString stringWithUTF8String:cat->desc] : @"",
                @"info": cat->info ? [NSString stringWithUTF8String:cat->info] : @""
            };
            cat++;
        }
    }
    g_optCategories = [cats copy];
    
    /* Parse definitions */
    if (opts && opts->definitions) {
        struct retro_core_option_v2_definition *def = opts->definitions;
        while (def->key) {
            NSString *key = [NSString stringWithUTF8String:def->key];
            NSString *desc = [NSString stringWithUTF8String:(def->desc_categorized ?: def->desc)];
            NSString *info = [NSString stringWithUTF8String:(def->info_categorized ?: def->info)];
            NSString *catKey = def->category_key ? [NSString stringWithUTF8String:def->category_key] : nil;
            NSString *defaultVal = def->default_value ? [NSString stringWithUTF8String:def->default_value] : @"";
            
            /* Parse possible values */
            NSMutableArray *vals = [NSMutableArray array];
            if (def->values) {
                struct retro_core_option_value *v = def->values;
                while (v->value) {
                    NSString *label = v->label ? [NSString stringWithUTF8String:v->label] : [NSString stringWithUTF8String:v->value];
                    [vals addObject:@{@"value": [NSString stringWithUTF8String:v->value], @"label": label}];
                    v++;
                }
            }
            
            defs[key] = @{
                @"desc": desc ?: @"",
                @"info": info ?: @"",
                @"defaultValue": defaultVal,
                @"category": catKey ?: @"",
                @"values": [vals copy]
            };
            
            /* Set initial value to default */
            g_optValues[key] = defaultVal;
            
            def++;
        }
    }
    g_optDefinitions = [defs copy];
}

/* Parse V1 definition (simpler, no categories) */
__attribute__((unused)) static void parseCoreOptionsV1(struct retro_core_options *opts) {
    initOptStorage();
    [g_optValues removeAllObjects];
    
    NSMutableDictionary *defs = [NSMutableDictionary dictionary];
    
    if (opts && opts->definitions) {
        struct retro_core_option_definition *def = opts->definitions;
        while (def && def->key) {
            NSString *key = [NSString stringWithUTF8String:def->key];
            NSString *desc = def->desc ? [NSString stringWithUTF8String:def->desc] : @"";
            NSString *info = def->info ? [NSString stringWithUTF8String:def->info] : @"";
            NSString *defaultVal = def->default_value ? [NSString stringWithUTF8String:def->default_value] : @"";
            
            NSMutableArray *vals = [NSMutableArray array];
            if (def->values) {
                struct retro_core_option_value *v = def->values;
                while (v->value) {
                    NSString *label = v->label ? [NSString stringWithUTF8String:v->label] : [NSString stringWithUTF8String:v->value];
                    [vals addObject:@{@"value": [NSString stringWithUTF8String:v->value], @"label": label}];
                    v++;
                }
            }
            
            defs[key] = @{
                @"desc": desc,
                @"info": info,
                @"defaultValue": defaultVal,
                @"category": @"",
                @"values": [vals copy]
            };
            
            g_optValues[key] = defaultVal;
            
            def++;
        }
    }
    g_optCategories = @{};
    g_optDefinitions = [defs copy];
}

/* Load persisted overrides from .cfg file into g_optValues.
 * File format: key = "value" (one per line).
 * Called after parseCoreOptionsV1/V2 to apply user overrides. */
static void applyPersistedOverrides() {
    if (!g_coreID) return;
    
    NSString *configName = [NSString stringWithFormat:@"%@.cfg", g_coreID];
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *optionsDir = [appSupport stringByAppendingPathComponent:@"TruchieEmu/CoreOptions"];
    NSString *configPath = [optionsDir stringByAppendingPathComponent:configName];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) return;
    
    NSString *fileContent = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
    if (!fileContent) return;
    
    NSArray<NSString *> *allLines = [fileContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    for (NSString *line in allLines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;
        
        // Parse: key = "value"
        NSRange eqRange = [trimmed rangeOfString:@"="];
        if (eqRange.location == NSNotFound) continue;
        
        NSString *key = [[trimmed substringToIndex:eqRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *val = [[trimmed substringFromIndex:NSMaxRange(eqRange)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        // Strip surrounding quotes
        if ([val hasPrefix:@"\""] && [val hasSuffix:@"\""]) {
            val = [val substringWithRange:NSMakeRange(1, val.length - 2)];
        }
        if (g_optValues && key.length > 0) {
            g_optValues[key] = val;
            NSLog(@"[Bridge-OPT] Override from .cfg: %@ = %@", key, val);
        }
    }
}

static uintptr_t bridge_get_current_framebuffer() {
    return (uintptr_t)g_hwFBO;
}

static dispatch_queue_t g_bridgeQueue = nil;
static dispatch_semaphore_t g_bridgeFinishedSemaphore = nil;

static uintptr_t bridge_get_proc_address(const char *sym) {
    if (!sym) return 0;
    static void *glHandle = NULL;
    if (!glHandle) glHandle = dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY);
    uintptr_t res = (uintptr_t)dlsym(glHandle ? glHandle : RTLD_DEFAULT, sym);
    if (!res && sym[0] != '_') {
        char buf[256];
        snprintf(buf, sizeof(buf), "_%s", sym);
        res = (uintptr_t)dlsym(glHandle ? glHandle : RTLD_DEFAULT, buf);
    }
    // Note: cores probe for many optional extensions (OES, ARB, GL4.2-4.5 DSA, etc.)
    // Missing symbols for optional probes is expected on macOS (GL capped at 4.1).
    // Only log if you need to debug a specific symbol.
    return res;
}

// MARK: - C Callbacks

// Core log callback mechanism: Swift sets this at startup to route libretro core logs
// (e.g. LibretroDB, Bridge, Identify) through LoggerService for file persistence.
typedef void (*CoreLogCallback)(const char *message, int level);
static CoreLogCallback g_coreLogCallback = NULL;

// Called from Swift at app startup to register the file logging callback.
#ifdef __cplusplus
extern "C" {
#endif
void RegisterCoreLogCallback(CoreLogCallback callback) {
    g_coreLogCallback = callback;
}
#ifdef __cplusplus
}
#endif

static void bridge_log_printf(enum retro_log_level level, const char *fmt, ...) {
    if (!fmt) return;
    va_list args;
    va_start(args, fmt);
    NSString *format = [[NSString alloc] initWithUTF8String:fmt];
    if (!format) {
        // Fallback for non-UTF8 or malformed strings
        format = [[NSString alloc] initWithCString:fmt encoding:NSASCIIStringEncoding];
    }
    if (format) {
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        if (message) {
            // Map retro_log_level to numeric: 0=INFO, 1=DEBUG, 2=WARN, 3=ERROR
            // Always forward to the Swift callback for file logging, regardless of g_logLevel
            if (g_coreLogCallback) {
                g_coreLogCallback(message.UTF8String, (int)level);
            }
            
            // Also emit to console/NSLog based on filter level
            if (level >= RETRO_LOG_ERROR && g_logLevel <= 2) NSLog(@"[Core-ERR] %@", message);
            else if (level == RETRO_LOG_WARN && g_logLevel <= 1) NSLog(@"[Core-WRN] %@", message);
            else if (level <= RETRO_LOG_INFO && g_logLevel == 0) NSLog(@"[Core-INF] %@", message);
        }
    }
    va_end(args);
}

static bool bridge_environment(unsigned cmd, void *data) {
    if (!g_instance) return false;
    
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            if (data) ((struct retro_log_interface *)data)->log = bridge_log_printf;
            return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if (data) *(unsigned char *)data = 1;
            return true;
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
            static char s_sysPath[1024];
            NSString *path = nil;
            if (g_instance && g_instance->_retainedRomPath) {
                path = [g_instance->_retainedRomPath stringByDeletingLastPathComponent];
            } else {
                path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
                path = [path stringByAppendingPathComponent:@"TruchieEmu/System"];
                [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
            }
            strncpy(s_sysPath, path.UTF8String, sizeof(s_sysPath) - 1);
            if (data) *(const char **)data = s_sysPath;
            return true;
        }
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            static char s_savePath[1024];
            NSString *path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
            path = [path stringByAppendingPathComponent:@"TruchieEmu"];
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
            
            strncpy(s_savePath, path.UTF8String, sizeof(s_savePath) - 1);
            if (data) *(const char **)data = s_savePath;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            if (data) {
                enum retro_pixel_format fmt = *(enum retro_pixel_format *)data;
                if (g_instance) {
                    [g_instance setPixelFormat:(int)fmt];
                }
            }
            return true;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            if (data) *(unsigned *)data = 1;
            return true;
        case RETRO_ENVIRONMENT_GET_LANGUAGE:
            if (data) *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            struct retro_variable *var = (struct retro_variable *)data;
            if (var && var->key) {
                // mupen64plus-next: force angrylion (software) RDP to avoid GL4.2+ DSA requirement
                // gliden64 requires glCreateTextures/glDispatchCompute etc. (GL4.5) not available on macOS
                
                // CPU core: pure interpreter is safest on ARM64 macOS (no JIT recompilation)
                if (strcmp(var->key, "mupen64plus-next-cpucore") == 0 ||
                    strcmp(var->key, "mupen64plus-cpucore") == 0)
                    { var->value = "pure_interpreter"; return true; }
                
                // Force software RDP — avoids all GL4.2+ DSA/compute shader calls
                if (strcmp(var->key, "mupen64plus-rdp-plugin") == 0 ||
                    strcmp(var->key, "mupen64plus-next-rdp-plugin") == 0)
                    { var->value = "angrylion"; return true; }
                
                // Disable threaded renderer (can cause race conditions on macOS)
                if (strcmp(var->key, "mupen64plus-next-ThreadedRenderer") == 0 ||
                    strcmp(var->key, "mupen64plus-next-parallel-rdp-synchronous") == 0)
                    { var->value = "Disabled"; return true; }
                
                if (strcmp(var->key, "mupen64plus-next-aspect") == 0)
                    { var->value = "4:3"; return true; }
                
                // ── MAME throttle/frame-limiting: enforce at the core level ──
                // These are queried by MAME cores to decide if they should throttle execution
                if (strcmp(var->key, "mame2003-plus-throttle") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame2003-plus-skip_disclaimer") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame2003-plus-skip_warnings") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame2010-throttle") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame2010-skip_disclaimer") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame2010-skip_warnings") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame-throttle") == 0)
                    { var->value = "enabled"; return true; }
                if (strcmp(var->key, "mame2000-throttle") == 0)
                    { var->value = "enabled"; return true; }
                
                // ── Read from g_optValues (populated by SET_CORE_OPTIONS handlers) ──
                // This is the critical link: cores query GET_VARIABLE to read option values,
                // and we must return the user's override (or the default from g_optValues).
                if (g_optValues) {
                    NSString *keyStr = [NSString stringWithUTF8String:var->key];
                    NSString *valStr = g_optValues[keyStr];
                    if (valStr) {
                        static __thread char g_varBuf[512];
                        strncpy(g_varBuf, valStr.UTF8String, sizeof(g_varBuf) - 1);
                        g_varBuf[sizeof(g_varBuf) - 1] = '\0';
                        var->value = g_varBuf;
                        return true;
                    }
                }
                
                var->value = NULL;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
            if (data && g_instance) {
                struct retro_game_geometry *geo = (struct retro_game_geometry *)data;
                g_instance->_avInfo.geometry = *geo;
                NSLog(@"[Bridge] Core updated geometry: %ux%u", geo->base_width, geo->base_height);
            }
            return true;
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
        case RETRO_ENVIRONMENT_SET_VARIABLES:          // core tells us what options exist — we acknowledge
            return true;
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
            if (data) parseCoreOptionsV1((struct retro_core_options *)data);
            applyPersistedOverrides();
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
            struct retro_core_options_intl *intl = (struct retro_core_options_intl *)data;
            if (intl) {
                // Use US English (fallback), or local if available
                parseCoreOptionsV1(intl->us ? intl->us : intl->local);
            }
            applyPersistedOverrides();
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
            if (data) parseCoreOptionsV2((struct retro_core_options_v2 *)data);
            applyPersistedOverrides();
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
            struct retro_core_options_v2_intl *intl = (struct retro_core_options_v2_intl *)data;
            if (intl) {
                parseCoreOptionsV2(intl->us ? intl->us : intl->local);
            }
            applyPersistedOverrides();
            return true;
        }
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
            return true;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
            if (data && g_instance) {
                struct retro_system_av_info *info = (struct retro_system_av_info *)data;
                // Validate timing values to prevent corruption/zero FPS causing speedup
                double fps = info->timing.fps;
                double sampleRate = info->timing.sample_rate;
                
                // Sanity check: FPS should be between 10 and 120, sample rate between 8000 and 192000
                if (fps > 10.0 && fps < 120.0) {
                    g_instance->_avInfo.timing.fps = fps;
                } else if (fps > 0.0) {
                    NSLog(@"[Bridge-WRN] Suspicious FPS value: %f, clamping to 60", fps);
                    g_instance->_avInfo.timing.fps = 60.0;
                } else {
                    NSLog(@"[Bridge-WRN] Invalid FPS value: %f, keeping current (was %f)", fps, g_instance->_avInfo.timing.fps);
                    // Keep existing FPS if it's valid, otherwise use 60
                    if (g_instance->_avInfo.timing.fps <= 0.0) {
                        g_instance->_avInfo.timing.fps = 60.0;
                    }
                }
                
                if (sampleRate > 8000.0 && sampleRate < 192000.0) {
                    g_instance->_avInfo.timing.sample_rate = sampleRate;
                } else if (sampleRate > 0.0) {
                    NSLog(@"[Bridge-WRN] Suspicious sample rate: %f, keeping current", sampleRate);
                } else {
                    NSLog(@"[Bridge-WRN] Invalid sample rate: %f, keeping current", sampleRate);
                }
                
                // Update geometry
                g_instance->_avInfo.geometry = info->geometry;
                
                NSLog(@"[Bridge] Core updated A/V info: FPS=%.2f SampleRate=%.1f", 
                      g_instance->_avInfo.timing.fps, g_instance->_avInfo.timing.sample_rate);
            }
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:    // has anything changed? → no, vars are stable
            if (data) *(bool *)data = false;
            return true;
        case RETRO_ENVIRONMENT_SET_HW_RENDER: {
            struct retro_hw_render_callback *cb = (struct retro_hw_render_callback *)data;
            if (g_instance && cb) {
                [g_instance setupHWRender:cb];
                return true;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_GET_PERF_INTERFACE:
        case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE:
        case RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE:
            return false;
        case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
            if (data) *(int*)data = 3; // Enable both
            return true;
        default: 
            return false;
    }
}

static void bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (g_instance) {
        if (g_instance->_hwRenderEnabled && g_instance->_glContext) CGLSetCurrentContext(g_instance->_glContext);
        const void *finalData = data;
        int format = [g_instance pixelFormat];
        if (data == RETRO_HW_FRAME_BUFFER_VALID) {
            finalData = [g_instance readHWRenderedPixels:width height:height];
            pitch = width * 4; // RGBA8888 for GL readback
            format = RETRO_PIXEL_FORMAT_XRGB8888; // glReadPixels with GL_BGRA + UNSIGNED_INT_8_8_8_8_REV produces 32-bit data
            NSLog(@"[Bridge-HW-R] HW frame %ux%u pitch=%zu format=XRGB8888", width, height, pitch);
        }
        [g_instance handleVideoData:finalData width:width height:height pitch:(int)pitch format:format];
    }
}

static void bridge_audio_sample(int16_t left, int16_t right) {
    int16_t samples[2] = {left, right};
    if (g_instance) [g_instance handleAudioSamples:samples count:2];
}

static size_t bridge_audio_sample_batch(const int16_t *data, size_t frames) {
    if (g_instance) [g_instance handleAudioSamples:data count:frames * 2];
    return frames;
}

// MARK: - Turbo Button State Machine
// Turbo is implemented by toggling button state at a configurable frequency
// Each turbo button has a counter that decrements each poll
// When counter reaches 0, the button state toggles
static int16_t g_input_state[32];
static int16_t g_analog_state[2][2]; // index, id
static BOOL g_turbo_state[32];       // Current turbo button on/off state
static int g_turbo_counter[32];      // Countdown counter for each turbo button
static BOOL g_turbo_active[32];      // Whether player is holding the turbo button
static const int g_turbo_rate = 6;   // Turbo fires 10 times per second at 60fps (60/10=6)
static int g_turbo_fireButton[32];   // Map from turbo button to actual RETRO button

static void bridge_handle_turbo(void) {
    for (int i = 0; i < 32; i++) {
        if (g_turbo_active[i]) {
            if (g_turbo_counter[i] <= 0) {
                g_turbo_counter[i] = g_turbo_rate;
                // Toggle turbo state
                g_turbo_state[i] = !g_turbo_state[i];
                // Apply to the underlying button
                int targetIdx = g_turbo_fireButton[i];
                if (targetIdx >= 0 && targetIdx < 32) {
                    g_input_state[targetIdx] = g_turbo_state[i] ? 1 : 0;
                }
            } else {
                g_turbo_counter[i]--;
            }
        }
    }
}

static void bridge_input_poll(void) {
    // Handle turbo button state machines each poll cycle
    bridge_handle_turbo();
}
static int16_t bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port == 0) {
        if (device == RETRO_DEVICE_JOYPAD) return g_input_state[id & 0x1F] ? 32767 : 0;
        if (device == RETRO_DEVICE_ANALOG && index < 2 && id < 2) return g_analog_state[index][id];
    }
    return 0;
}

@implementation LibretroBridgeImpl

- (instancetype)init {
    if (self = [super init]) {
        _audioBuffer = new AudioRingBuffer(44100 * 2 * 2); // 2 seconds buffer
        _audioRenderScratchCapacity = 4096; // Enough for standard frame counts
        _audioRenderScratch = (int16_t *)malloc(_audioRenderScratchCapacity * sizeof(int16_t));
        memset(&_avInfo, 0, sizeof(_avInfo));
        // Initialize with sensible defaults so the timing loop never sees 0 FPS
        _avInfo.timing.fps = 60.0;
        _avInfo.timing.sample_rate = 44100.0;
        _avInfo.geometry.base_width = 640;
        _avInfo.geometry.base_height = 480;
        _avInfo.geometry.max_width = 1920;
        _avInfo.geometry.max_height = 1080;
        _avInfo.geometry.aspect_ratio = 4.0f/3.0f;
        memset(g_input_state, 0, sizeof(g_input_state));
    }
    return self;
}

- (void)setupAudioWithSampleRate:(double)sampleRate {
    if (_audioEngine) {
        [_audioEngine stop];
        _audioEngine = nil;
    }
    
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sampleRate channels:2 interleaved:NO];
    
    // Reset ring buffer to avoid old samples causing noise/reverb
    _audioBuffer->clear();
    
    __unsafe_unretained LibretroBridgeImpl *weakSelf = self;
    _audioSourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL * _Nonnull silence, const AudioTimeStamp * _Nonnull timestamp, AVAudioFrameCount frameCount, AudioBufferList * _Nonnull outputData) {
        
        LibretroBridgeImpl *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_audioBuffer) return noErr;
        
        float *left = (float *)outputData->mBuffers[0].mData;
        float *right = (float *)outputData->mBuffers[1].mData;
        
        // Ensure scratch buffer is large enough (rarely happens if frameCount 1024)
        if (frameCount * 2 > strongSelf->_audioRenderScratchCapacity) {
             // In real-time threads this is bad, but this would only happen once or if frame size changes drastically
             // We'll just read what we can and skip rather than mallocing if possible.
             // For now, let's just use what we have.
        }
        
        size_t toRead = std::min((size_t)frameCount * 2, strongSelf->_audioRenderScratchCapacity);
        size_t readCount = strongSelf->_audioBuffer->read(strongSelf->_audioRenderScratch, toRead);
        
        for (size_t i = 0; i < frameCount; ++i) {
            if (i * 2 + 1 < readCount) {
                left[i] = (float)strongSelf->_audioRenderScratch[i*2] / 32768.0f;
                right[i] = (float)strongSelf->_audioRenderScratch[i*2+1] / 32768.0f;
            } else {
                left[i] = 0;
                right[i] = 0;
            }
        }
        
        return noErr;
    }];
    
    [_audioEngine attachNode:_audioSourceNode];
    [_audioEngine connect:_audioSourceNode to:_audioEngine.mainMixerNode format:format];
}

- (BOOL)loadDylib:(NSString *)path {
    _dlHandle = dlopen(path.UTF8String, RTLD_LAZY);
    if (!_dlHandle) {
        NSLog(@"[Bridge-ERR] Could not dlopen core at %@: %s", path, dlerror());
        return NO;
    }
    
#define LOAD_SYM(name) \
    _##name = (fn_##name)dlsym(_dlHandle, #name); \
    /* Only warn for critical symbols */ \
    if (!_##name && (strcmp(#name, "retro_init") == 0 || strcmp(#name, "retro_run") == 0 || strcmp(#name, "retro_load_game") == 0)) \
        NSLog(@"[Bridge-WRN] Could not find symbol %s", #name);
    
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
    LOAD_SYM(retro_cheat_set)
    LOAD_SYM(retro_cheat_reset)
    LOAD_SYM(retro_get_memory_data)
    LOAD_SYM(retro_get_memory_size)
#undef LOAD_SYM
    return YES;
}

- (BOOL)launchROM:(NSString *)romPath videoCallback:(VideoFrameCallback)cb {
    _videoCallback = cb;
    _retainedRomPath = [romPath copy];
    _retainedRomData = [[NSData alloc] initWithContentsOfFile:_retainedRomPath];
    NSLog(@"[Bridge] Loading ROM: %@ (Size: %lu bytes)", _retainedRomPath, (unsigned long)_retainedRomData.length);


    // ── MAME-only: detect MAME core for specific timing/pixel-format fixes ──
    _isMameLaunch = (g_coreID && [[g_coreID lowercaseString] containsString:@"mame"]);
    if (_isMameLaunch) {
        // MAME cores use XRGB8888 by default but rarely send SET_PIXEL_FORMAT.
        // Defaulting to 1 (XRGB8888) avoids the 0RGB1555 misinterpretation
        // that causes scrambled/garbage colors and broken pitch calculations.
        _pixelFormat = 1; // RETRO_PIXEL_FORMAT_XRGB8888
        NSLog(@"[Bridge] MAME core detected ('%@'): pixel format forced to XRGB8888 (1)", g_coreID);
    }
    _retro_set_environment(bridge_environment);
    _retro_set_video_refresh(bridge_video_refresh);
    _retro_set_audio_sample(bridge_audio_sample);
    _retro_set_audio_sample_batch(bridge_audio_sample_batch);
    _retro_set_input_poll(bridge_input_poll);
    _retro_set_input_state(bridge_input_state);
    
    _retro_init();
    
    struct retro_game_info gi = {0};
    gi.path = _retainedRomPath.UTF8String;
    gi.data = _retainedRomData.bytes;
    gi.size = _retainedRomData.length;
    gi.meta = NULL;
    
    if (!_retro_load_game) {
        NSLog(@"[Bridge-ERR] retro_load_game is NULL!");
        return NO;
    }
    
    if (!_retro_load_game(&gi)) return NO;
    
    // config A/V
    _retro_get_system_av_info(&_avInfo);
    double sampleRate = _avInfo.timing.sample_rate > 0 ? _avInfo.timing.sample_rate : 44100.0;
    double fps = _avInfo.timing.fps > 0 ? _avInfo.timing.fps : 60.0;
    NSLog(@"[Bridge] Core A/V Info: SampleRate=%.1f FPS=%.2f", sampleRate, fps);
    // MAME-specific: validate FPS to catch out-of-range values that cause speedup
    if (_isMameLaunch) {
        double mameFps = _avInfo.timing.fps;
        double mameSR = _avInfo.timing.sample_rate;
        if (mameFps > 10.0 && mameFps < 120.0) {
            NSLog(@"[Bridge] MAME A/V validated: FPS=%.4f SampleRate=%.1f", mameFps, mameSR);
        } else {
            NSLog(@"[Bridge-WRN] MAME FPS out of range: %.2f, clamping to 60", mameFps);
            _avInfo.timing.fps = 60.0;
        }
        // Clamp sample rate too
        if (mameSR < 8000.0 || mameSR > 192000.0) {
            NSLog(@"[Bridge-WRN] MAME sample rate out of range: %.1f, clamping to 44100", mameSR);
            _avInfo.timing.sample_rate = 44100.0;
        }
    }
    
    // Safety clamp for ALL cores: ensure FPS is never 0 or absurdly high
    if (_avInfo.timing.fps <= 0.0 || _avInfo.timing.fps > 120.0) {
        NSLog(@"[Bridge-WRN] Global FPS clamp: %.2f -> 60.0", _avInfo.timing.fps);
        _avInfo.timing.fps = 60.0;
    }
    
    [self setupAudioWithSampleRate:sampleRate];
    
    NSError *err;
    [_audioEngine startAndReturnError:&err];
    
    _saveStatePath = [romPath stringByAppendingString:@".state"];
    
    _running = YES;
    
    // MAIN GAME LOOP
    while (_running) {
        // Check pause state - skip emulation when paused
        if (g_isPaused) {
            [NSThread sleepForTimeInterval:0.05]; // Sleep briefly while paused
            continue;
        }
        
        if (_isMameLaunch) {
            // ── MAME-SPECIFIC FRAME LOOP: audio-driven fpsync + accumulator ──
            // Arcade cores are particularly sensitive to timing. This loop uses:
            //  1. Pre-run audio buffer throttling to prevent overflow (key fix!)
            //  2. Frame time accumulator for precise pacing
            //  3. Post-run buffer check as safety net
            //
            // Without pre-run throttling, retro_run() executes at maximum CPU speed
            // and the audio callback silently drops samples → 100x+ speedup.
            @autoreleasepool {
                // PRE-RUN: check audio buffer fill and wait if needed
                size_t availableSamples = _audioBuffer->available();
                size_t capacity = _audioBuffer->capacity();
                float fillRatio = (float)availableSamples / (float)capacity;

                // If buffer is >50% full (lowered from 70%), wait for it to drain before producing frames.
                // This is the key fpsync mechanism: audio buffer fill level is the
                // primary pacing signal. Without this, retro_run() runs unbounded at CPU speed.
                // A lower threshold (50%) gives more consistent pacing with less jitter.
                while (fillRatio > 0.50f && _running && !g_isPaused) {
                    [NSThread sleepForTimeInterval:0.0005];
                    availableSamples = _audioBuffer->available();
                    fillRatio = (float)availableSamples / (float)capacity;
                }
            }

            if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);
            uint64_t start = mach_absolute_time();
            _retro_run();
            uint64_t end = mach_absolute_time();

            static mach_timebase_info_data_t s_tb = {0, 0};
            if (s_tb.denom == 0) mach_timebase_info(&s_tb);
            uint64_t elapsed_ns = (end - start) * s_tb.numer / s_tb.denom;
            double elapsed = (double)elapsed_ns / 1e9;

            double targetFPS = _avInfo.timing.fps;
            if (targetFPS <= 0) targetFPS = 60.0;
            double idealFrameTime = 1.0 / targetFPS;

            // ACCUMULATOR: add any deficit, subtract excess
            static double mameFrameError = 0.0;
            mameFrameError += (idealFrameTime - elapsed);

            // POST-RUN: compensate for accumulated error
            if (mameFrameError > 0.001) {
                @autoreleasepool {
                    size_t avail = _audioBuffer->available();
                    size_t cap = _audioBuffer->capacity();
                    float fill = (float)avail / (float)cap;

                    if (fill > 0.10f) {
                        // Ahead of schedule and buffer draining — sleep to catch up
                        double sleepTime = mameFrameError > 0.008 ? 0.008 : mameFrameError;
                        [NSThread sleepForTimeInterval:sleepTime];
                        mameFrameError -= sleepTime;
                        if (mameFrameError < 0) mameFrameError = 0;
                    } else {
                        // Buffer nearly empty — skip sleep to catch up
                        mameFrameError = 0;
                    }
                }
            } else {
                // Behind schedule — don't sleep, try to recover
                mameFrameError = 0;
            }
        } else {
            // ── NON-MAME FRAME LOOP: unchanged original behavior ──
            uint64_t start = mach_absolute_time();

            // Use current FPS from _avInfo in case it changed mid-run
            double currentFps = _avInfo.timing.fps > 0 ? _avInfo.timing.fps : 60.0;
            // Clamp FPS to reasonable range (10-120 Hz) to prevent speedup/spin issues
            if (currentFps < 10.0) currentFps = 60.0;
            if (currentFps > 120.0) currentFps = 120.0;
            NSTimeInterval frameTime = 1.0 / currentFps;

            if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);
            _retro_run();

            uint64_t end = mach_absolute_time();

            // Convert to seconds
            static mach_timebase_info_data_t timebase;
            if (timebase.denom == 0) mach_timebase_info(&timebase);
            double elapsed = (double)(end - start) * timebase.numer / timebase.denom / 1e9;

            if (elapsed < frameTime) {
                // Adaptive sleep: check audio buffer fill level
                // If we have plenty of audio, we can sleep more precisely.
                // If we are running low, we run faster.
                size_t availableSamples = _audioBuffer->available();
                size_t capacity = _audioBuffer->capacity();
                float fillRatio = (float)availableSamples / capacity;

                double sleepTime = frameTime - elapsed;

                // If buffer is very full (>70%), we might want to slow down slightly more to avoid overflow
                // If buffer is very empty (<5%), we skip sleep to catch up
                if (fillRatio < 0.05f) {
                    // Buffer critical! No sleep.
                } else {
                    [NSThread sleepForTimeInterval:sleepTime];
                }
            }
        }
    }
    
    [_audioEngine stop];
    _retro_unload_game();
    _retro_deinit();
    return YES;
}

- (void)stop { _running = NO; }

- (NSData *)serializeState {
    if (!_retro_serialize_size || !_retro_serialize) return nil;
    size_t sz = _retro_serialize_size();
    if (sz == 0) return nil;
    
    void *buf = malloc(sz);
    if (!buf) return nil;
    
    if (_retro_serialize(buf, sz)) {
        return [NSData dataWithBytesNoCopy:buf length:sz freeWhenDone:YES];
    } else {
        free(buf);
        return nil;
    }
}

- (BOOL)unserializeState:(NSData *)data {
    if (!data || !_retro_unserialize) return NO;
    return _retro_unserialize(data.bytes, data.length);
}

- (void)saveState {
    if (!_retro_serialize_size || !_retro_serialize) return;
    size_t sz = _retro_serialize_size();
    void *buf = malloc(sz);
    if (_retro_serialize(buf, sz)) {
        NSData *data = [NSData dataWithBytesNoCopy:buf length:sz];
        [data writeToFile:_saveStatePath atomically:YES];
    } else {
        free(buf);
    }
}

- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch format:(int)format {
    if (_videoCallback) _videoCallback(data, w, h, pitch, format);
}

- (void)handleAudioSamples:(const int16_t *)data count:(size_t)count {
    if (_audioBuffer) _audioBuffer->write(data, count);
}

- (void)setKeyState:(int)idx pressed:(BOOL)p {
    if (idx >= 0 && idx < 32) g_input_state[idx] = p ? 1 : 0;
}

- (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx {
    if (idx >= 0 && idx < 32) {
        g_turbo_active[idx] = active;
        g_turbo_fireButton[idx] = targetIdx;
        if (!active) {
            // When turbo is released, ensure the target button is released
            g_turbo_state[idx] = NO;
            g_turbo_counter[idx] = 0;
            if (targetIdx >= 0 && targetIdx < 32) {
                g_input_state[targetIdx] = 0;
            }
        }
    }
}

- (void)setAnalogState:(int)idx id:(int)id value:(int)v {
    if (idx >= 0 && idx < 2 && id >= 0 && id < 2) g_analog_state[idx][id] = (int16_t)v;
}

- (void)setPixelFormat:(int)format { _pixelFormat = format; }
- (int)pixelFormat { return _pixelFormat; }

- (void)setupHWRender:(struct retro_hw_render_callback *)cb {
    _hwRenderEnabled = YES;
    memset(&_hw_callback, 0, sizeof(_hw_callback));
    memcpy(&_hw_callback, cb, sizeof(_hw_callback));
    
    // *** Write our callbacks back into the struct the core owns ***
    // The Libretro spec: the core passes its retro_hw_render_callback* and the
    // frontend FILLS IN get_proc_address + get_current_framebuffer in that same
    // struct. The core then reads the pointers from cb after this env call returns.
    // If we only set them on our local _hw_callback copy, the core still sees NULL
    // for get_proc_address → every GL lookup inside context_reset returns NULL →
    // crash at address 0x0 on the first GL call.
    cb->get_proc_address         = bridge_get_proc_address;
    cb->get_current_framebuffer  = bridge_get_current_framebuffer;
    _hw_callback.get_proc_address        = bridge_get_proc_address;
    _hw_callback.get_current_framebuffer = bridge_get_current_framebuffer;

    
    CGLPixelFormatAttribute profile = (CGLPixelFormatAttribute)kCGLOGLPVersion_Legacy;
    if (_hw_callback.context_type == RETRO_HW_CONTEXT_OPENGL_CORE) {
        profile = (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core;
    }
    
    NSLog(@"[Bridge] Creating OpenGL context type %d (Profile: %d, Depth: %d, Stencil: %d)", 
          _hw_callback.context_type, (int)profile, _hw_callback.depth, _hw_callback.stencil);

    CGLPixelFormatAttribute attrs[20];
    int i = 0;
    attrs[i++] = kCGLPFAOpenGLProfile; attrs[i++] = profile;
    attrs[i++] = kCGLPFAAccelerated;
    attrs[i++] = kCGLPFAColorSize;  attrs[i++] = (CGLPixelFormatAttribute)32;
    attrs[i++] = kCGLPFADepthSize;  attrs[i++] = (CGLPixelFormatAttribute)24;
    attrs[i++] = kCGLPFAStencilSize; attrs[i++] = (CGLPixelFormatAttribute)8;
    attrs[i++] = (CGLPixelFormatAttribute)0;
    
    CGLPixelFormatObj pix;
    GLint num;
    CGLError err = CGLChoosePixelFormat(attrs, &pix, &num);
    if (err != kCGLNoError || !pix) {
        NSLog(@"[Bridge] ERROR: Could not choose Pixel Format for GL (err=%d)", (int)err);
        return;
    }
    CGLCreateContext(pix, NULL, &_glContext);
    CGLDestroyPixelFormat(pix);
    
    if (!_glContext) {
        NSLog(@"[Bridge] ERROR: Could not create GL Context");
        return;
    }
    
    CGLSetCurrentContext(_glContext);

    // ── Create a real FBO for the core to render into ──────────────────────
    // Use 640x480 as a safe default; some cores will call SET_GEOMETRY later.
    _fboWidth  = 640;
    _fboHeight = 480;

    glGenFramebuffers(1, &_hwFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, _hwFBO);

    glGenRenderbuffers(1, &_hwColorRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _hwColorRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, _fboWidth, _fboHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _hwColorRB);

    glGenRenderbuffers(1, &_hwDepthRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _hwDepthRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, _fboWidth, _fboHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _hwDepthRB);

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"[Bridge] ERROR: FBO incomplete (status=0x%x)", status);
    } else {
        NSLog(@"[Bridge] FBO %u created (%dx%d) – ready for core", _hwFBO, _fboWidth, _fboHeight);
        g_hwFBO = _hwFBO; // expose to bridge_get_current_framebuffer
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    // ────────────────────────────────────────────────────────────────────────
    
    if (_hw_callback.context_reset) {
        NSLog(@"[Bridge] Calling Core's context_reset()");
        _hw_callback.context_reset();
    }
}

- (const void *)readHWRenderedPixels:(int)w height:(int)h {
    // Resize FBO if the core changed resolution
    if (w != _fboWidth || h != _fboHeight) {
        _fboWidth  = w;
        _fboHeight = h;
        
        CGLSetCurrentContext(_glContext);
        glBindFramebuffer(GL_FRAMEBUFFER, _hwFBO);
        
        glBindRenderbuffer(GL_RENDERBUFFER, _hwColorRB);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, w, h);
        
        glBindRenderbuffer(GL_RENDERBUFFER, _hwDepthRB);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
        
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        NSLog(@"[Bridge] FBO resized to %dx%d", w, h);
    }
    
    size_t needed = (size_t)w * (size_t)h * 4;
    if (needed > _hwReadbackBufferSize) {
        _hwReadbackBuffer = realloc(_hwReadbackBuffer, needed);
        _hwReadbackBufferSize = needed;
    }
    
    CGLSetCurrentContext(_glContext);
    
    // Ensure all GL rendering is complete before readback
    glFinish();
    
    // Bind the FBO for reading and explicitly specify the read buffer
    glBindFramebuffer(GL_READ_FRAMEBUFFER, _hwFBO);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    
    // Validate FBO before reading
    GLenum status = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"[Bridge-HW-R] FBO incomplete (status=0x%x), falling back to default FB", status);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
        glReadBuffer(GL_BACK);
    }
    
    glReadPixels(0, 0, w, h, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _hwReadbackBuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    
    return _hwReadbackBuffer;
}

- (void)dealloc {
    if (g_instance == self) g_instance = nil;
    if (_glContext) {
        CGLSetCurrentContext(_glContext);
        if (_hw_callback.context_destroy) _hw_callback.context_destroy();
        if (_hwFBO)     { glDeleteFramebuffers(1, &_hwFBO);     _hwFBO = 0; g_hwFBO = 0; }
        if (_hwColorRB) { glDeleteRenderbuffers(1, &_hwColorRB); _hwColorRB = 0; }
        if (_hwDepthRB) { glDeleteRenderbuffers(1, &_hwDepthRB); _hwDepthRB = 0; }
        CGLSetCurrentContext(NULL);
        CGLReleaseContext(_glContext);
        _glContext = nil;
    }
    if (_hwReadbackBuffer) free(_hwReadbackBuffer);
    if (_audioRenderScratch) free(_audioRenderScratch);
    delete _audioBuffer;
    _audioBuffer = nil;
    if (_dlHandle) dlclose(_dlHandle);
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

@end

@implementation LibretroBridge
+ (void)launchWithDylibPath:(NSString *)dylib romPath:(NSString *)rom shaderDir:(NSString *)shaderDir videoCallback:(void(^)(const void*, int, int, int, int))cb coreID:(NSString *)coreID {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_bridgeQueue = dispatch_queue_create("com.truchiemu.bridge", DISPATCH_QUEUE_SERIAL);
    });

    // Reset options storage for new core
    g_coreID = [coreID copy];
    g_shaderDir = [shaderDir copy];
    initOptStorage();
    // Preserve g_optCategories (not affected by core swap)
    // g_optDefinitions cleared when SET_CORE_OPTIONS fires
    // Pre-load persisted overrides NOW so GET_VARIABLE returns them even before
    // SET_CORE_OPTIONS_V2 fires (mGBA and other cores query early during load)
    applyPersistedOverrides();

    dispatch_async(g_bridgeQueue, ^{
        if (g_instance) {
            NSLog(@"[Bridge] Signalling previous instance to stop...");
            [g_instance stop];
        }
        
        LibretroBridgeImpl *newInst = [[LibretroBridgeImpl alloc] init];
        g_instance = newInst;
        
        NSLog(@"[Bridge] Starting new core session: %@", dylib.lastPathComponent);
        if ([newInst loadDylib:dylib]) {
            [newInst launchROM:rom videoCallback:cb];
        }
        
        if (g_instance == newInst) {
            g_instance = nil;
        }
        NSLog(@"[Bridge] Core session finished.");
    });
}

+ (void)stop { 
    if (g_instance) {
        [g_instance stop]; 
    }
}

+ (void)saveState { if (g_instance) [g_instance saveState]; }
+ (NSData *)serializeState { return g_instance ? [g_instance serializeState] : nil; }
+ (BOOL)unserializeState:(NSData *)data { return g_instance ? [g_instance unserializeState:data] : NO; }
+ (size_t)serializeSize { return g_instance && g_instance->_retro_serialize_size ? g_instance->_retro_serialize_size() : 0; }
+ (void)setKeyState:(int)rid pressed:(BOOL)p { if (g_instance) [g_instance setKeyState:rid pressed:p]; }
+ (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx { if (g_instance) [g_instance setTurboState:idx active:active targetButton:targetIdx]; }
+ (void)setAnalogState:(int)idx id:(int)id value:(int)v { if (g_instance) [g_instance setAnalogState:idx id:id value:v]; }
+ (void)setLanguage:(int)language { g_selectedLanguage = language; }
+ (void)setLogLevel:(int)level { g_logLevel = level; }
+ (void)setPaused:(BOOL)paused { g_isPaused = paused; }
+ (BOOL)isPaused { return g_isPaused; }

/* ── Load Core For Options (no content) ── */
static BOOL g_loadingForOptions = NO;
static NSString * _Nullable g_optionsDylibPath = nil;

+ (void)loadCoreForOptions:(NSString *)dylibPath coreID:(NSString *)coreID {
    g_loadingForOptions = YES;
    g_coreID = [coreID copy];
    g_optionsDylibPath = [dylibPath copy];
    g_optValues = nil;
    g_optDefinitions = nil;
    g_optCategories = nil;
    
    LibretroBridgeImpl *impl = [[LibretroBridgeImpl alloc] init];
    g_instance = impl;
    
    if (![impl loadDylib:dylibPath]) {
        NSLog(@"[Bridge] Failed to load core for options at %@", dylibPath);
        g_optCategories = @{};
        g_optDefinitions = @{};
        g_optValues = [NSMutableDictionary dictionary];
        g_instance = nil;
        g_loadingForOptions = NO;
        return;
    }
    
    // Setup minimal environment and init
    impl->_retro_set_environment(bridge_environment);
    impl->_retro_init();
    
    struct retro_system_av_info avInfo;
    avInfo.geometry.base_width = 640;
    avInfo.geometry.base_height = 480;
    avInfo.geometry.max_width = 640;
    avInfo.geometry.max_height = 480;
    avInfo.geometry.aspect_ratio = 4.0f/3.0f;
    avInfo.timing.fps = 60.0;
    avInfo.timing.sample_rate = 44100.0;
    impl->_avInfo = avInfo;
    
    // Check if core supports no-game
    BOOL supportsNoGame = NO;
    bridge_environment(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &supportsNoGame);
    
    if (supportsNoGame) {
        // Load with NULL game info (no content)
        struct retro_game_info gi;
        memset(&gi, 0, sizeof(gi));
        if (impl->_retro_load_game(&gi)) {
            NSLog(@"[Bridge] Core initialized with no content. Options available.");
        } else {
            NSLog(@"[Bridge] Core does not support no-game mode. Options will be empty.");
        }
    } else {
        NSLog(@"[Bridge] Core does not advertise no-game support. Attempting no-content init anyway...");
        struct retro_game_info gi;
        memset(&gi, 0, sizeof(gi));
        if (impl->_retro_load_game(&gi)) {
            NSLog(@"[Bridge] Core loaded with no content successfully.");
        } else {
            NSLog(@"[Bridge] Core rejected no-content load.");
        }
    }
    
    // Run one iteration to let the core fully init
    impl->_retro_run();
    
    // Save coreID for persistence
    [[NSUserDefaults standardUserDefaults] setObject:coreID forKey:@"lastLoadedCoreID"];
    
    // Unload and cleanup
    [impl stop];
    impl->_retro_unload_game();
    impl->_retro_deinit();
    
    g_instance = nil;
    g_loadingForOptions = NO;
    
    NSLog(@"[Bridge] Core options loaded: %lu definitions", (unsigned long)g_optDefinitions.count);
}

+ (BOOL)isCoreLoadedForOptions {
    return g_loadingForOptions;
}

+ (int)currentRotation {
    return g_currentRotation;
}

+ (float)aspectRatio {
    if (g_instance) {
        float ar = g_instance->_avInfo.geometry.aspect_ratio;
        // When aspect_ratio is <= 0, libretro expects the frontend to compute it from base_width/base_height
        if (ar <= 0.0f && g_instance->_avInfo.geometry.base_height > 0) {
            ar = (float)g_instance->_avInfo.geometry.base_width / (float)g_instance->_avInfo.geometry.base_height;
        }
        return ar;
    }
    return 0.0f; // 0 signals: fall back to pixel dimensions
}

/* ── Core Options Accessors ── */
static dispatch_queue_t g_optAccessQueue;
static dispatch_once_t g_optAccessQueueOnce;

+ (NSString *)getOptionValueForKey:(NSString *)key {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    __block NSString *result = nil;
    dispatch_sync(g_optAccessQueue, ^{
        if (g_optValues) {
            result = [g_optValues[key] copy];
        }
    });
    return result;
}

+ (void)setOptionValue:(NSString *)value forKey:(NSString *)key {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(g_optAccessQueue, ^{
        initOptStorage();
        if (key) {
            g_optValues[key] = value ?: @"";
        }
    });
}

+ (void)resetOptionToDefaultForKey:(NSString *)key {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(g_optAccessQueue, ^{
        if (g_optDefinitions && g_optDefinitions[key]) {
            NSString *defaultVal = g_optDefinitions[key][@"defaultValue"];
            if (defaultVal) {
                initOptStorage();
                g_optValues[key] = defaultVal;
            }
        }
    });
}

+ (void)resetAllOptionsToDefaults {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(g_optAccessQueue, ^{
        if (g_optDefinitions) {
            initOptStorage();
            [g_optValues removeAllObjects];
            for (NSString *key in g_optDefinitions) {
                NSString *defVal = g_optDefinitions[key][@"defaultValue"];
                if (defVal) {
                    g_optValues[key] = defVal;
                }
            }
        }
    });
}

+ (NSDictionary<NSString *, NSDictionary *> *)getOptionsDictionary {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    __block NSDictionary *result = nil;
    dispatch_sync(g_optAccessQueue, ^{
        if (g_optDefinitions && g_optValues) {
            NSMutableDictionary *combined = [NSMutableDictionary dictionary];
            for (NSString *key in g_optDefinitions) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:g_optDefinitions[key]];
                entry[@"currentValue"] = g_optValues[key] ?: g_optDefinitions[key][@"defaultValue"] ?: @"";
                combined[key] = [entry copy];
            }
            result = [combined copy];
        }
    });
    return result;
}

/* Expose categories to Swift */
+ (NSDictionary<NSString *, NSDictionary *> *)getCategoriesDictionary {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    __block NSDictionary *result = nil;
    dispatch_sync(g_optAccessQueue, ^{
        result = [g_optCategories copy] ?: @{};
    });
    return result;
}

/* ── Cheat Management ── */
+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled {
    if (!g_instance || !g_instance->_retro_cheat_set) {
        NSLog(@"[Bridge] Cheat not supported by this core");
        return;
    }
    const char *codeStr = code.UTF8String;
    g_instance->_retro_cheat_set(index, enabled, codeStr);
    NSLog(@"[Bridge] Cheat %d %s: %@", index, enabled ? "enabled" : "disabled", code);
}

+ (void)resetCheats {
    if (!g_instance || !g_instance->_retro_cheat_reset) {
        return;
    }
    g_instance->_retro_cheat_reset();
    NSLog(@"[Bridge] Cheats reset");
}

+ (void)applyCheats:(NSArray<NSDictionary *> *)cheats {
    if (!g_instance) return;
    
    // Reset all cheats first
    [self resetCheats];
    
    // Apply each enabled cheat
    for (NSDictionary *cheat in cheats) {
        NSNumber *indexNum = cheat[@"index"];
        NSString *code = cheat[@"code"];
        BOOL enabled = [cheat[@"enabled"] boolValue];
        
        if (indexNum && code && enabled) {
            [self setCheatEnabled:[indexNum intValue] code:code enabled:YES];
        }
    }
}

/* ── Direct Memory Access for Cheats ── */
+ (void *)getMemoryData:(unsigned)type size:(size_t *)size {
    if (!g_instance || !g_instance->_retro_get_memory_data) {
        return NULL;
    }
    void *data = g_instance->_retro_get_memory_data(type);
    if (size && g_instance->_retro_get_memory_size) {
        *size = g_instance->_retro_get_memory_size(type);
    }
    return data;
}

+ (void)writeMemoryByte:(uint32_t)address value:(uint8_t)value {
    size_t memSize = 0;
    uint8_t *ram = (uint8_t *)[self getMemoryData:RETRO_MEMORY_SYSTEM_RAM size:&memSize];
    if (ram && address < memSize) {
        ram[address] = value;
    }
}

+ (void)applyDirectMemoryCheats:(NSArray<NSDictionary *> *)cheats {
    size_t memSize = 0;
    uint8_t *ram = (uint8_t *)[self getMemoryData:RETRO_MEMORY_SYSTEM_RAM size:&memSize];
    if (!ram) {
        // Try save RAM as fallback
        ram = (uint8_t *)[self getMemoryData:RETRO_MEMORY_SAVE_RAM size:&memSize];
    }
    if (!ram) {
        NSLog(@"[Bridge] No memory available for direct cheat injection");
        return;
    }
    
    for (NSDictionary *cheat in cheats) {
        BOOL enabled = [cheat[@"enabled"] boolValue];
        if (!enabled) continue;
        
        NSNumber *addressNum = cheat[@"address"];
        NSNumber *valueNum = cheat[@"value"];
        
        if (addressNum && valueNum) {
            uint32_t address = [addressNum unsignedIntValue];
            uint8_t value = [valueNum unsignedCharValue];
            
            if (address < memSize) {
                ram[address] = value;
                NSLog(@"[Bridge] Direct memory write: 0x%06X = 0x%02X", address, value);
            } else {
                NSLog(@"[Bridge] Direct memory write: address 0x%06X out of range (size: %zu)", address, memSize);
            }
        }
    }
}
@end
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
- (void)setPixelFormat:(int)format;
- (int)pixelFormat;
- (void)setupHWRender:(struct retro_hw_render_callback *)cb;
- (const void *)readHWRenderedPixels:(int)w height:(int)h;
@end

static LibretroBridgeImpl *g_instance = nil;
static int g_selectedLanguage = 0; // RETRO_LANGUAGE_ENGLISH
static int g_logLevel = 1; // 1 = Warn & Error
// Shared with bridge_get_current_framebuffer — updated by setupHWRender
static GLuint g_hwFBO = 0;

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
            // Mapping retro_log_level to our internal g_logLevel (0:Info, 1:Warn, 2:Error, 3:None)
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
            if (data) *(unsigned *)data = (unsigned)g_selectedLanguage;
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            struct retro_variable *var = (struct retro_variable *)data;
            if (var && var->key) {
                // NSLog(@"[Bridge] Core requested variable: %s", var->key);

                // Common language keys for various cores
                if (strcmp(var->key, "beetle_psx_hw_initial_vram_buffer_size") == 0) {
                     // This is NOT a language key, but just testing I can intercept. 
                     // Wait, I should find the real language keys.
                }

                // Generic language mapping for cores that use a "language" or "system_language" key
                const char* langStr = "English";
                const char* langShort = "en";
                switch (g_selectedLanguage) {
                    case RETRO_LANGUAGE_JAPANESE: langStr = "Japanese"; langShort = "jp"; break;
                    case RETRO_LANGUAGE_FRENCH:   langStr = "French";   langShort = "fr"; break;
                    case RETRO_LANGUAGE_GERMAN:   langStr = "German";   langShort = "de"; break;
                    case RETRO_LANGUAGE_SPANISH:  langStr = "Spanish";  langShort = "es"; break;
                    case RETRO_LANGUAGE_ITALIAN:  langStr = "Italian";  langShort = "it"; break;
                    case RETRO_LANGUAGE_DUTCH:    langStr = "Dutch";    langShort = "nl"; break;
                    case RETRO_LANGUAGE_PORTUGUESE: langStr = "Portuguese"; langShort = "pt"; break;
                    case RETRO_LANGUAGE_RUSSIAN:  langStr = "Russian";  langShort = "ru"; break;
                    case RETRO_LANGUAGE_KOREAN:   langStr = "Korean";   langShort = "ko"; break;
                    default: langStr = "English"; langShort = "en"; break;
                }

                if (strstr(var->key, "language") != NULL || strstr(var->key, "Language") != NULL) {
                    // Some cores might expect lowercase language names
                    static char s_langLower[32];
                    strncpy(s_langLower, langStr, sizeof(s_langLower)-1);
                    for(int i=0; s_langLower[i]; i++) s_langLower[i] = tolower(s_langLower[i]);

                    // Common overrides for specific cores
                    if (strcmp(var->key, "vba_next_language") == 0) { var->value = langStr; return true; }
                    if (strcmp(var->key, "mgba_language") == 0) { var->value = langStr; return true; }
                    if (strstr(var->key, "beetle_psx") != NULL) { var->value = langStr; return true; }

                    var->value = langStr; // Default to capitalized word
                    NSLog(@"[Bridge] Intercepted variable %s -> %s", var->key, var->value);
                    return true;
                }
                
                // Also handle region variables which sometimes affect language
                if (strstr(var->key, "region") != NULL || strstr(var->key, "Region") != NULL) {
                    if (g_selectedLanguage == RETRO_LANGUAGE_JAPANESE) {
                        var->value = "Japan";
                    } else if (g_selectedLanguage == RETRO_LANGUAGE_ENGLISH) {
                        var->value = "North America"; // Or Europe, but NA is safer for English
                    } else {
                        var->value = "Europe"; // Most other European languages
                    }
                    return true;
                }

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
                
                var->value = NULL;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
        case RETRO_ENVIRONMENT_SET_ROTATION:
        case RETRO_ENVIRONMENT_SET_VARIABLES:          // core tells us what options exist — we acknowledge
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
            if (data && g_instance) {
                struct retro_system_av_info *info = (struct retro_system_av_info *)data;
                g_instance->_avInfo = *info;
                NSLog(@"[Bridge] Core updated A/V info: FPS=%f SampleRate=%f", info->timing.fps, info->timing.sample_rate);
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
        if (data == RETRO_HW_FRAME_BUFFER_VALID) {
            finalData = [g_instance readHWRenderedPixels:width height:height];
            pitch = width * 4; // Assuming RGBA8888 for GL readback
        }
        [g_instance handleVideoData:finalData width:width height:height pitch:(int)pitch format:[g_instance pixelFormat]];
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

static void bridge_input_poll(void) {}
static int16_t g_input_state[32];
static int16_t g_analog_state[2][2]; // index, id
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
    if (!_##name) NSLog(@"[Bridge-WRN] Could not find symbol %s", #name);
    
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
    _retainedRomPath = [romPath copy];
    _retainedRomData = [[NSData alloc] initWithContentsOfFile:_retainedRomPath];
    NSLog(@"[Bridge] Loading ROM: %@ (Size: %lu bytes)", _retainedRomPath, (unsigned long)_retainedRomData.length);

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
    
    [self setupAudioWithSampleRate:sampleRate];
    
    NSError *err;
    [_audioEngine startAndReturnError:&err];
    
    _saveStatePath = [romPath stringByAppendingString:@".state"];
    
    _running = YES;
    
    // Timing loop using Mach Absolute Time for high precision
    while (_running) {
        uint64_t start = mach_absolute_time();
        
        // Use current FPS from _avInfo in case it changed mid-run
        double currentFps = _avInfo.timing.fps > 0 ? _avInfo.timing.fps : 60.0;
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
    
    [_audioEngine stop];
    _retro_unload_game();
    _retro_deinit();
    return YES;
}

- (void)stop { _running = NO; }

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
    glBindFramebuffer(GL_READ_FRAMEBUFFER, _hwFBO);
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
+ (void)launchWithDylibPath:(NSString *)dylib romPath:(NSString *)rom videoCallback:(void(^)(const void*, int, int, int, int))cb {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_bridgeQueue = dispatch_queue_create("com.truchiemu.bridge", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(g_bridgeQueue, ^{
        if (g_instance) {
            NSLog(@"[Bridge] Signalling previous instance to stop...");
            [g_instance stop];
            // Wait for it to finish its loop. We can use a small delay or a more robust signal.
            // Since this is a serial queue, and we are on the background, we can sleep-wait briefly
            // but the previous block on this queue would have finished if it was also async.
            // WAIT - the previous launch was also async on this queue! 
            // So if we use a serial queue, this block won't start until the previous one finishes.
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
+ (void)setKeyState:(int)rid pressed:(BOOL)p { if (g_instance) [g_instance setKeyState:rid pressed:p]; }
+ (void)setAnalogState:(int)idx id:(int)id value:(int)v { if (g_instance) [g_instance setAnalogState:idx id:id value:v]; }
+ (void)setLanguage:(int)language { g_selectedLanguage = language; }
+ (void)setLogLevel:(int)level { g_logLevel = level; }
@end

#import <Foundation/Foundation.h>
#import "LibretroBridge.h"
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import "libretro.h"
#include <atomic>

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

    size_t available() const { return _fillCount; }

private:
    int16_t *_buffer;
    size_t _capacity;
    size_t _readPtr;
    size_t _writePtr;
    std::atomic<size_t> _fillCount;
};

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
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_audioSourceNode;
    AudioRingBuffer *_audioBuffer;
    
    NSString *_saveStatePath;
    
    // Retain explicit resources so they outlive the emulation loop
    NSData *_retainedRomData;
    NSString *_retainedRomPath;
}
- (BOOL)loadDylib:(NSString *)path;
- (BOOL)launchROM:(NSString *)romPath videoCallback:(VideoFrameCallback)cb;
- (void)stop;
- (void)saveState;
- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch;
- (void)handleAudioSamples:(const int16_t *)data count:(size_t)count;
- (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
@end

static LibretroBridgeImpl *g_instance = nil;

// MARK: - C Callbacks
static void bridge_log_printf(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *format = [[NSString alloc] initWithUTF8String:fmt];
    if (format) {
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        NSLog(@"[Core] %@", message);
    }
    va_end(args);
}

static bool bridge_environment(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            if (data) ((struct retro_log_interface *)data)->log = bridge_log_printf;
            return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            if (data) *(bool*)data = true;
            return true;
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
            NSString *path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
            path = [path stringByAppendingPathComponent:@"TruchieEmu"];
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
            
            static char s_sysPath[1024];
            strncpy(s_sysPath, path.UTF8String, sizeof(s_sysPath) - 1);
            if (data) *(const char **)data = s_sysPath;
            return true;
        }
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: return true;
        default: return false;
    }
}

static void bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (g_instance) [g_instance handleVideoData:data width:width height:height pitch:(int)pitch];
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
static int16_t g_input_state[16];
static int16_t bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port == 0 && device == RETRO_DEVICE_JOYPAD) return g_input_state[id & 0xF] ? 32767 : 0;
    return 0;
}

@implementation LibretroBridgeImpl

- (instancetype)init {
    if (self = [super init]) {
        _audioBuffer = new AudioRingBuffer(44100 * 2 * 2); // 2 seconds buffer
        [self setupAudio];
    }
    return self;
}

- (void)setupAudio {
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:44100 channels:2 interleaved:NO];
    
    // We use __unsafe_unretained to avoid capturing cycles without requiring ARC weak references
    __unsafe_unretained LibretroBridgeImpl *weakSelf = self;
    _audioSourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL * _Nonnull silence, const AudioTimeStamp * _Nonnull timestamp, AVAudioFrameCount frameCount, AudioBufferList * _Nonnull outputData) {
        
        LibretroBridgeImpl *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_audioBuffer) return noErr;
        
        float *left = (float *)outputData->mBuffers[0].mData;
        float *right = (float *)outputData->mBuffers[1].mData;
        
        int16_t *temp = (int16_t *)malloc(frameCount * 2 * sizeof(int16_t));
        size_t readCount = strongSelf->_audioBuffer->read(temp, frameCount * 2);
        
        for (size_t i = 0; i < frameCount; ++i) {
            if (i * 2 < readCount) {
                left[i] = (float)temp[i*2] / 32768.0f;
                right[i] = (float)temp[i*2+1] / 32768.0f;
            } else {
                left[i] = 0;
                right[i] = 0;
            }
        }
        
        free(temp);
        return noErr;
    }];
    
    [_audioEngine attachNode:_audioSourceNode];
    [_audioEngine connect:_audioSourceNode to:_audioEngine.mainMixerNode format:format];
}

- (BOOL)loadDylib:(NSString *)path {
    _dlHandle = dlopen(path.UTF8String, RTLD_LAZY);
    if (!_dlHandle) return NO;
    
#define LOAD_SYM(name) _##name = (fn_##name)dlsym(_dlHandle, #name);
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
    _retro_set_environment(bridge_environment);
    _retro_set_video_refresh(bridge_video_refresh);
    _retro_set_audio_sample(bridge_audio_sample);
    _retro_set_audio_sample_batch(bridge_audio_sample_batch);
    _retro_set_input_poll(bridge_input_poll);
    _retro_set_input_state(bridge_input_state);
    
    _retro_init();
    
    _retainedRomPath = [romPath copy];
    _retainedRomData = [[NSData alloc] initWithContentsOfFile:_retainedRomPath];
    struct retro_game_info gi = {_retainedRomPath.UTF8String, _retainedRomData.bytes, _retainedRomData.length, NULL};
    if (!_retro_load_game(&gi)) return NO;
    
    NSError *err;
    [_audioEngine startAndReturnError:&err];
    
    _saveStatePath = [romPath stringByAppendingString:@".state"];
    
    _running = YES;
    while (_running) {
        _retro_run();
        [NSThread sleepForTimeInterval:1.0/60.0];
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

- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch {
    if (_videoCallback) _videoCallback(data, w, h, pitch);
}

- (void)handleAudioSamples:(const int16_t *)data count:(size_t)count {
    if (_audioBuffer) _audioBuffer->write(data, count);
}

- (void)setKeyState:(int)idx pressed:(BOOL)p {
    if (idx >= 0 && idx < 16) g_input_state[idx] = p ? 1 : 0;
}

- (void)dealloc {
    delete _audioBuffer;
    _audioBuffer = nil;
    if (_dlHandle) dlclose(_dlHandle);
}

@end

@implementation LibretroBridge
+ (void)launchWithDylibPath:(NSString *)dylib romPath:(NSString *)rom videoCallback:(void(^)(const void*, int, int, int))cb {
    if (g_instance) [g_instance stop];
    
    LibretroBridgeImpl *newInst = [[LibretroBridgeImpl alloc] init];
    g_instance = newInst;
    
    if ([newInst loadDylib:dylib]) {
        [newInst launchROM:rom videoCallback:cb];
    }
    
    // Once launchROM unblocks (after game ends), we can safely release.
    if (g_instance == newInst) {
        g_instance = nil;
    }
    
}

+ (void)stop { 
    if (g_instance) {
        [g_instance stop]; 
    }
}

+ (void)saveState { if (g_instance) [g_instance saveState]; }
+ (void)setKeyState:(int)rid pressed:(BOOL)p { if (g_instance) [g_instance setKeyState:rid pressed:p]; }
@end

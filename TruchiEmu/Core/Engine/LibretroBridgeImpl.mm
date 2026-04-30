#define GL_SILENCE_DEPRECATION
#import "LibretroBridgeImpl.h"
#import "LibretroGlobals.h"
#import "LibretroCallbacks.h"
#import <dlfcn.h>
#include <mach/mach_time.h>

@implementation LibretroBridgeImpl

- (instancetype)init {
  if (self = [super init]) {
    _coreLock = [[NSLock alloc] init];
    _audioBuffer = new AudioRingBuffer(32768); 
    _audioRenderScratchCapacity = 16384;
    _audioRenderScratch = (int16_t *)malloc(_audioRenderScratchCapacity * sizeof(int16_t));
    memset(&_avInfo, 0, sizeof(_avInfo));
    _avInfo.timing.fps = 60.0;
    _avInfo.timing.sample_rate = 44100.0;
    _avInfo.geometry.base_width = 640;
    _avInfo.geometry.base_height = 480;
    _avInfo.geometry.max_width = 1920;
    _avInfo.geometry.max_height = 1080;
    _avInfo.geometry.aspect_ratio = 4.0f / 3.0f;
    memset(g_input_state, 0, sizeof(g_input_state));
  }
  return self;
}

- (void)setControllerPortDevice:(unsigned)port device:(unsigned)device {
  if (_retro_set_controller_port_device) {
    _retro_set_controller_port_device(port, device);
    bridge_log_printf(RETRO_LOG_INFO, "Set port %u to device %u", port, device);
  }
}

- (void)setupAudioWithSampleRate:(double)sampleRate {
  if (_audioEngine) {[_audioEngine stop];
    _audioEngine = nil;
  }

  _audioEngine = [[AVAudioEngine alloc] init];
  AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sampleRate channels:2 interleaved:NO];

  _audioBuffer->clear();

  __unsafe_unretained LibretroBridgeImpl *weakSelf = self;
  _audioSourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL *_Nonnull silence, const AudioTimeStamp *_Nonnull timestamp, AVAudioFrameCount frameCount, AudioBufferList *_Nonnull outputData) {
        LibretroBridgeImpl *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_audioBuffer) return noErr;

        float *left = (float *)outputData->mBuffers[0].mData;
        float *right = (float *)outputData->mBuffers[1].mData;

        size_t toRead = std::min((size_t)frameCount * 2, strongSelf->_audioRenderScratchCapacity);
        size_t readCount = strongSelf->_audioBuffer->read(strongSelf->_audioRenderScratch, toRead);

        for (size_t i = 0; i < frameCount; ++i) {
          if (i * 2 + 1 < readCount) {
            left[i] = (float)strongSelf->_audioRenderScratch[i * 2] / 32768.0f;
            right[i] = (float)strongSelf->_audioRenderScratch[i * 2 + 1] / 32768.0f;
          } else {
            left[i] = 0;
            right[i] = 0;
          }
        }
        return noErr;
      }];

  [_audioEngine attachNode:_audioSourceNode];[_audioEngine connect:_audioSourceNode to:_audioEngine.mainMixerNode format:format];
}

- (BOOL)loadDylib:(NSString *)path {
  _dlHandle = dlopen(path.UTF8String, RTLD_LAZY);
  if (!_dlHandle) {
    bridge_log_printf(RETRO_LOG_ERROR, "Could not dlopen core at %s: %s", path.UTF8String, dlerror());
    return NO;
  }

#define LOAD_SYM(name)                                                         \
  _##name = (fn_##name)dlsym(_dlHandle, #name);                                \
  if (!_##name && (strcmp(#name, "retro_init") == 0 || strcmp(#name, "retro_run") == 0 || strcmp(#name, "retro_load_game") == 0)) \
    bridge_log_printf(RETRO_LOG_WARN, "Could not find symbol %s", #name);

  LOAD_SYM(retro_set_controller_port_device)
  LOAD_SYM(retro_init)
  LOAD_SYM(retro_deinit)
  LOAD_SYM(retro_set_environment)
  LOAD_SYM(retro_set_video_refresh)
  LOAD_SYM(retro_set_audio_sample)
  LOAD_SYM(retro_set_audio_sample_batch)
  LOAD_SYM(retro_set_input_poll)
  LOAD_SYM(retro_set_input_state)
  LOAD_SYM(retro_get_system_info)
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
  _retainedRomData = nil;

  _retro_set_environment(bridge_environment);
  _retro_set_video_refresh(bridge_video_refresh);
  _retro_set_audio_sample(bridge_audio_sample);
  _retro_set_audio_sample_batch(bridge_audio_sample_batch);
  _retro_set_input_poll(bridge_input_poll);
  _retro_set_input_state(bridge_input_state);

  _isMameLaunch = (g_coreID && [[g_coreID lowercaseString] containsString:@"mame"]);
  if (_isMameLaunch) {
    _pixelFormat = 1; 
  }

  BOOL didInit = NO;
  double frameError = 0.0;
  bool needsFullPath = false;
  unsigned device_type = 1;
  double sampleRate = 44100.0;
  double fps = 60.0;
  NSError *err = nil;
  struct retro_system_info sysInfo = {0};
  struct retro_game_info gi = {0};

  memset(&sysInfo, 0, sizeof(sysInfo));
  needsFullPath = false;
  if (_retro_get_system_info) {
    _retro_get_system_info(&sysInfo);
    needsFullPath = sysInfo.need_fullpath;
  }

  if (!needsFullPath) {
    _retainedRomData = [[NSData alloc] initWithContentsOfFile:_retainedRomPath];
  }

  @try {
      if (_retro_init) {
          _retro_init();
          didInit = YES;
      }
  } @catch (NSException *e) {
      goto shutdown;
  } @catch (...) {
      goto shutdown;
  }

  memset(&gi, 0, sizeof(gi));
  gi.path = _retainedRomPath.UTF8String;

  if (needsFullPath) {
    gi.data = NULL;
    gi.size = 0;
  } else {
    gi.data = _retainedRomData.bytes;
    gi.size = _retainedRomData.length;
  }
  gi.meta = NULL;

  device_type = 1; 

  if (g_coreID && [[g_coreID lowercaseString] containsString:@"dolphin"]) {
    NSString *ext = [_retainedRomPath.pathExtension lowercaseString];
    if ([ext isEqualToString:@"wbfs"] || [ext isEqualToString:@"wad"] || [ext isEqualToString:@"wia"] ||[ext isEqualToString:@"rvz"]) {
      device_type = 513;
    }
  } else if (g_coreID && ([[g_coreID lowercaseString] containsString:@"swanstation"]) ||
             (g_coreID && [[g_coreID lowercaseString] containsString:@"mednafen_psx"]) ||
             (g_coreID && [[g_coreID lowercaseString] containsString:@"pcsx"])) {
      device_type = 1;
  } else if (g_coreID && ([[g_coreID lowercaseString] containsString:@"mame"]) ||
             (g_coreID && [[g_coreID lowercaseString] containsString:@"dosbox"])) {
      device_type = 3; // RETRO_DEVICE_KEYBOARD
  }

  if (!_retro_load_game) {
    return NO;
  }

  @try {
    if (!g_instance->_retro_load_game(&gi)) {
      goto shutdown;
    }
  } @catch (NSException *exception) {
    goto shutdown;
  } @catch (...) {
    goto shutdown;
  }[self setControllerPortDevice:0 device:device_type];

  [_coreLock lock];
  if (_hwRenderEnabled && _hw_callback.context_reset) {
    if (_glContext) CGLSetCurrentContext(_glContext);
    _hw_callback.context_reset();
  }

  _cachedSerializeSize = 0;

  if (_hwRenderEnabled && _glContext)
    CGLSetCurrentContext(NULL);[_coreLock unlock];

  _retro_get_system_av_info(&_avInfo);
  sampleRate = _avInfo.timing.sample_rate > 0 ? _avInfo.timing.sample_rate : 44100.0;
  fps = _avInfo.timing.fps > 0 ? _avInfo.timing.fps : 60.0;

  if (sampleRate < 8000.0 || sampleRate > 192000.0) {
    sampleRate = 44100.0;
    _avInfo.timing.sample_rate = sampleRate;
  }

  if (_avInfo.timing.fps <= 0.0 || _avInfo.timing.fps > 120.0) {
    _avInfo.timing.fps = 60.0;
  }
  [self setupAudioWithSampleRate:sampleRate];

  err = nil;
  [_audioEngine startAndReturnError:&err];

  _saveStatePath =[romPath stringByAppendingString:@".state"];

  // Notify Swift that game is loaded - it will handle SRAM loading
  if (g_gameLoadedCallback) {
    g_gameLoadedCallback(_retainedRomPath.UTF8String);
  }

  _running = YES;

  while (_running) {
    if (g_isPaused) {
      [NSThread sleepForTimeInterval:0.05]; 
      continue;
    }

    @autoreleasepool {
      size_t availableSamples = _audioBuffer->available();
      size_t capacity = _audioBuffer->capacity();
      float fillRatio = (float)availableSamples / (float)capacity;

      while (fillRatio > 0.50f && _running && !g_isPaused) {
        [NSThread sleepForTimeInterval:0.001];
        availableSamples = _audioBuffer->available();
        fillRatio = (float)availableSamples / (float)capacity;
      }
    }

    [_coreLock lock];
    uint64_t start = 0;
    uint64_t end = 0;
    @try {
      if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);
      start = mach_absolute_time();
      if (_retro_run) {
          _retro_run();
      }
      end = mach_absolute_time();
      if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
    } @catch (NSException *exception) {
      _running = NO;
    } @catch (...) {
      _running = NO;
    }
    [_coreLock unlock];

    static mach_timebase_info_data_t s_tb = {0, 0};
    if (s_tb.denom == 0) mach_timebase_info(&s_tb);
    uint64_t elapsed_ns = (end - start) * s_tb.numer / s_tb.denom;
    double elapsed = (double)elapsed_ns / 1e9;

    double targetFPS = _avInfo.timing.fps;
    if (targetFPS <= 0.0 || targetFPS > 120.0) targetFPS = 60.0;
    double idealFrameTime = 1.0 / targetFPS;

    frameError += (idealFrameTime - elapsed);

    if (frameError > 0.001) {
      @autoreleasepool {
        size_t avail = _audioBuffer->available();
        size_t cap = _audioBuffer->capacity();
        float fill = (float)avail / (float)cap;

        if (fill > 0.10f) {
          double sleepTime = frameError > 0.008 ? 0.008 : frameError;[NSThread sleepForTimeInterval:sleepTime];
          frameError -= sleepTime;
          if (frameError < 0) frameError = 0;
        } else {
          frameError = 0;
        }
      }
    } else {
      frameError = 0;
    }
  }

shutdown:
  if ([_audioEngine isRunning]) {[_audioEngine stop];}[_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  BOOL isBuggyShutdown = (g_coreID && [[g_coreID lowercaseString] containsString:@"ppsspp"]) ||
                         (g_coreID && [[g_coreID lowercaseString] containsString:@"swanstation"]) ||
                         (g_coreID && [[g_coreID lowercaseString] containsString:@"duckstation"]);

  if (isBuggyShutdown && _hwRenderEnabled && _hw_callback.context_destroy) {
      @try {
          _hw_callback.context_destroy();
      } @catch (...) {}
      _hw_callback.context_destroy = NULL;
  }

  if (didInit) {
      @try {
          if (_retro_unload_game) _retro_unload_game();
      } @catch (...) {}
  }

  if (_hwRenderEnabled && _hw_callback.context_destroy) {
      @try {
          _hw_callback.context_destroy();
      } @catch (...) {}
      _hw_callback.context_destroy = NULL;
  }

  if (didInit) {
      @try {
          if (_retro_deinit) _retro_deinit();
      } @catch (...) {}
  }

  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
  [_coreLock unlock];

  if (g_bridgeCompletionSemaphore) {
    dispatch_semaphore_signal(g_bridgeCompletionSemaphore);
  }

  return didInit;
}

- (void)stop {
  _running = NO;
  // Reset keyboard callback to prevent dangling pointer crashes when core is unloaded
  g_keyboard_callback_registered = NO;
  g_keyboard_callback.callback = NULL;
}

- (NSData *)serializeState {
  if (_cachedSerializeSize == 0 && _retro_serialize_size) {
    _cachedSerializeSize = _retro_serialize_size();
  }

  if (!_cachedSerializeSize || !_retro_serialize) return nil;

  [_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  void *buf = malloc(_cachedSerializeSize);
  NSData *data = nil;
  if (buf) {
    @try {
        if (_retro_serialize(buf, _cachedSerializeSize)) {
          data =[NSData dataWithBytesNoCopy:buf length:_cachedSerializeSize freeWhenDone:YES];
        } else {
          free(buf);
        }
    } @catch (...) {
        free(buf);
    }
  }

  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
  [_coreLock unlock];
  return data;
}

- (BOOL)unserializeState:(NSData *)data {
  if (!data || !_retro_unserialize) return NO;
  [_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  BOOL success = NO;
  @try {
      success = _retro_unserialize(data.bytes, data.length);
  } @catch (...) {}

  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);[_coreLock unlock];

  return success;
}

- (void)saveState {
  if (_cachedSerializeSize == 0 && _retro_serialize_size) {
    _cachedSerializeSize = _retro_serialize_size();
  }

  if (!_cachedSerializeSize || !_retro_serialize) return;[_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  void *buf = malloc(_cachedSerializeSize);
  if (buf) {
    if (_retro_serialize(buf, _cachedSerializeSize)) {
      NSData *data =[NSData dataWithBytesNoCopy:buf length:_cachedSerializeSize];[data writeToFile:_saveStatePath atomically:YES];
    } else {
      free(buf);
    }
  }

  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
  [_coreLock unlock];
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

  cb->get_proc_address = bridge_get_proc_address;
  cb->get_current_framebuffer = bridge_get_current_framebuffer;
  _hw_callback.get_proc_address = bridge_get_proc_address;
  _hw_callback.get_current_framebuffer = bridge_get_current_framebuffer;

  CGLPixelFormatAttribute profile = (CGLPixelFormatAttribute)kCGLOGLPVersion_Legacy;
  if (_hw_callback.context_type == RETRO_HW_CONTEXT_OPENGL_CORE || _hw_callback.version_major >= 3) {
    profile = (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core;
  }

  CGLPixelFormatAttribute attrs[20];
  int i = 0;
  attrs[i++] = kCGLPFAOpenGLProfile;
  attrs[i++] = profile;
  attrs[i++] = kCGLPFAAccelerated;
  attrs[i++] = kCGLPFAColorSize;
  attrs[i++] = (CGLPixelFormatAttribute)32;
  attrs[i++] = kCGLPFADepthSize;
  attrs[i++] = (CGLPixelFormatAttribute)24;
  attrs[i++] = kCGLPFAStencilSize;
  attrs[i++] = (CGLPixelFormatAttribute)8;
  attrs[i++] = (CGLPixelFormatAttribute)0;

  CGLPixelFormatObj pix;
  GLint num;
  CGLError err = CGLChoosePixelFormat(attrs, &pix, &num);
  if (err != kCGLNoError || !pix) return;
  
  CGLCreateContext(pix, NULL, &_glContext);
  CGLDestroyPixelFormat(pix);
  if (!_glContext) return;

  CGLSetCurrentContext(_glContext);

  _fboWidth = 640;
  _fboHeight = 480;

  glGenFramebuffers(1, &_hwFBO);
  glBindFramebuffer(GL_FRAMEBUFFER, _hwFBO);
  g_hwFBO = _hwFBO; // SYNC WITH GLOBAL FOR CALLBACKS

  glGenRenderbuffers(1, &_hwColorRB);
  glBindRenderbuffer(GL_RENDERBUFFER, _hwColorRB);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, _fboWidth, _fboHeight);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _hwColorRB);
  
  glFlush(); // Ensure state is synchronized before core uses it

  glGenRenderbuffers(1, &_hwDepthRB);
  glBindRenderbuffer(GL_RENDERBUFFER, _hwDepthRB);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, _fboWidth, _fboHeight);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _hwDepthRB);

  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status == GL_FRAMEBUFFER_COMPLETE) {
    g_hwFBO = _hwFBO;
  }
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

- (const void *)readHWRenderedPixels:(int)w height:(int)h {
    if (w != _fboWidth || h != _fboHeight) {
        _fboWidth = w;
        _fboHeight = h;

        CGLSetCurrentContext(_glContext);
        glBindFramebuffer(GL_FRAMEBUFFER, _hwFBO);
        
        // Resize and RE-ATTACH color renderbuffer
        glBindRenderbuffer(GL_RENDERBUFFER, _hwColorRB);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, w, h);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _hwColorRB);
        
        // Resize and RE-ATTACH depth renderbuffer
        glBindRenderbuffer(GL_RENDERBUFFER, _hwDepthRB);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _hwDepthRB);
        
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }

  size_t needed = (size_t)w * (size_t)h * 4;
  if (needed > _hwReadbackBufferSize) {
    _hwReadbackBuffer = realloc(_hwReadbackBuffer, needed);
    _hwReadbackBufferSize = needed;
  }

    CGLSetCurrentContext(_glContext);
    glFinish();

    // Debug: Check framebuffer binding BEFORE we change anything
    GLint boundReadFBOBefore, boundDrawFBOBefore;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &boundReadFBOBefore);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &boundDrawFBOBefore);
    
    // Always bind our FBO for readback
    glBindFramebuffer(GL_READ_FRAMEBUFFER, _hwFBO);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    
    // Log debug info
    GLenum status = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        //NSLog(@"[Core-ERR] FBO incomplete: 0x%X (FBO ID: %d, width: %d, height: %d), falling back to FBO 0", status, _hwFBO, w, h);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
        glReadBuffer(GL_BACK);
    } else {
        //NSLog(@"[Core-DGB] FBO is complete (ID: %d, size: %dx%d, wasRead=%d, wasDraw=%d)", _hwFBO, w, h, boundReadFBOBefore, boundDrawFBOBefore);
    }

    glReadPixels(0, 0, w, h, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _hwReadbackBuffer);
    
    // Debug: Check if we got any non-zero pixels
    uint32_t firstPixel = ((uint32_t *)_hwReadbackBuffer)[0];
    uint32_t lastPixel = ((uint32_t *)_hwReadbackBuffer)[w*h - 1];
    //NSLog(@"[Core-DGB] Readback pixels - first: 0x%08X, last: 0x%08X", firstPixel, lastPixel);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);

  uint32_t *pixels = (uint32_t *)_hwReadbackBuffer;
  BOOL isPSP = (g_coreID && [[g_coreID lowercaseString] containsString:@"ppsspp"]);
  BOOL isPS1_swanstation = (g_coreID && [[g_coreID lowercaseString] containsString:@"swanstation"]);
  BOOL isPS2_play = (g_coreID && [[g_coreID lowercaseString] containsString:@"play_libretro"]);
  BOOL isDolphin = (g_coreID && [[g_coreID lowercaseString] containsString:@"dolphin"]);
  BOOL isDOSBox = (g_coreID && [[g_coreID lowercaseString] containsString:@"dosbox"]);
  BOOL isDreamcast = (g_coreID && [[g_coreID lowercaseString] containsString:@"flycast"]);
  BOOL is3DS = (g_coreID && [[g_coreID lowercaseString] containsString:@"panda3ds"]);
  BOOL isN64 = NO;
  if (g_coreID) {
      NSString *cid = [(id)g_coreID lowercaseString];
      if ([cid containsString:@"mupen64plus"]) isN64 = YES;
  }

  if (isPSP || 
      isPS2_play || 
      isDolphin || 
      isDOSBox || 
      isDreamcast || 
      isPS1_swanstation || 
      isN64 ||
      is3DS) {
    for (int y = 0; y < h / 2; y++) {
      uint32_t *rowTop = pixels + (y * w);
      uint32_t *rowBottom = pixels + ((h - 1 - y) * w);
      for (int x = 0; x < w; x++) {
        uint32_t tmp = rowTop[x];
        rowTop[x] = rowBottom[x];
        rowBottom[x] = tmp;
      }
    }
  } else if (!_hw_callback.bottom_left_origin) {
    for (int y = 0; y < h / 2; y++) {
      uint32_t *rowTop = pixels + (y * w);
      uint32_t *rowBottom = pixels + ((h - 1 - y) * w);
      for (int x = 0; x < w; x++) {
        uint32_t tmp = rowTop[x];
        rowTop[x] = rowBottom[x];
        rowBottom[x] = tmp;
      }
    }
  }

  return _hwReadbackBuffer;
}

- (void)dealloc {
  if (g_instance == self) g_instance = nil;
  if (_glContext) {
    CGLSetCurrentContext(_glContext);
    if (_hw_callback.context_destroy) {
      _hw_callback.context_destroy();
      _hw_callback.context_destroy = NULL;
    }
    if (_hwFBO) {
      glDeleteFramebuffers(1, &_hwFBO);
      _hwFBO = 0; g_hwFBO = 0;
    }
    if (_hwColorRB) {
      glDeleteRenderbuffers(1, &_hwColorRB);
      _hwColorRB = 0;
    }
    if (_hwDepthRB) {
      glDeleteRenderbuffers(1, &_hwDepthRB);
      _hwDepthRB = 0;
    }
    CGLSetCurrentContext(NULL);
    CGLReleaseContext(_glContext);
    _glContext = nil;
  }
  if (_hwReadbackBuffer) free(_hwReadbackBuffer);
  if (_audioRenderScratch) free(_audioRenderScratch);
  if (_audioBuffer) { delete _audioBuffer; _audioBuffer = nil; }
  if (_dlHandle) dlclose(_dlHandle);
}

@end
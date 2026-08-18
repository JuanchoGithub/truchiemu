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
    bridge_log_printf(RETRO_LOG_DEBUG, "Set port %u to device %u", port, device);
  }
}

- (void)setupAudioWithSampleRate:(double)sampleRate {
    if (_audioEngine) {[_audioEngine stop]; _audioEngine = nil; }

    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sampleRate channels:2 interleaved:NO];

    _audioBuffer->clear();
    _audioFadeInComplete = NO;

    __unsafe_unretained LibretroBridgeImpl *weakSelf = self;
    _audioSourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL *_Nonnull silence, const AudioTimeStamp *_Nonnull timestamp, AVAudioFrameCount frameCount, AudioBufferList *_Nonnull outputData) {
        LibretroBridgeImpl *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_audioBuffer) return noErr;

        float *left = (float *)outputData->mBuffers[0].mData;
        float *right = (float *)outputData->mBuffers[1].mData;

        size_t toRead = std::min((size_t)frameCount * 2, strongSelf->_audioRenderScratchCapacity);
        size_t readCount = strongSelf->_audioBuffer->read(strongSelf->_audioRenderScratch, toRead);

        float gain = 1.0f;
        if (!strongSelf->_audioFadeInComplete) {
            uint64_t now = mach_absolute_time();
            static mach_timebase_info_data_t s_audioTb = {0, 0};
            if (s_audioTb.denom == 0) mach_timebase_info(&s_audioTb);
            double elapsedSec = (double)(now - strongSelf->_audioStartTimeMach) * s_audioTb.numer / s_audioTb.denom / 1e9;
            if (elapsedSec < 0.5) {
                gain = (float)(elapsedSec / 0.5);
            } else {
                strongSelf->_audioFadeInComplete = YES;
            }
        }

        for (size_t i = 0; i < frameCount; ++i) {
            if (i * 2 + 1 < readCount) {
                left[i] = (float)strongSelf->_audioRenderScratch[i * 2] / 32768.0f * gain;
                right[i] = (float)strongSelf->_audioRenderScratch[i * 2 + 1] / 32768.0f * gain;
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
LOAD_SYM(retro_reset)
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

  _isMameLaunch = g_coreCapabilities.isMame;
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

    // Default to XRGB8888 (32-bit BGRA). Must be set BEFORE retro_init so that
    // cores which call SET_PIXEL_FORMAT during init can override it. If set only
    // before retro_load_game (as was previously the case), any SET_PIXEL_FORMAT
    // call made during retro_init gets clobbered — leaving XRGB8888 even for
    // cores that explicitly requested RGB565.
    _pixelFormat = RETRO_PIXEL_FORMAT_XRGB8888;

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

  // Apply controller port device types *between* retro_init and retro_load_game
  // ONLY for DOSBox-Pure, which seeds `dbp_port_mode` here so that
  // retro_load_game's SetInputDescriptors(true) picks it up and the initial
  // JOYSTICK_Enable reflects the correct joystick state.
  //
  // Calling retro_set_controller_port_device before retro_load_game is unsafe
  // for cores that lazily initialize the structures the call touches inside
  // retro_load_game:
  //   - Dolphin dereferences Config::Layer (only created during boot) -> crash
  //     in Config::Layer::Set
  //   - Mednafen_PSX / pcsx_rearmed instantiate pad objects during
  //     retro_load_game -> null deref
  // The libretro spec publishes RETRO_ENVIRONMENT_SET_CONTROLLER_INFO in
  // retro_load_game; RetroArch itself only calls retro_set_controller_port_device
  // after retro_load_game. All non-DOSBox cores get the post-load call below.
  if (didInit) {
BOOL isDOSBox = g_coreCapabilities.isDOSBox;
      if (isDOSBox) {
          [self setControllerPortDevice:0 device:1];
          [self setControllerPortDevice:1 device:1];
          [self setControllerPortDevice:2 device:1];
          [self setControllerPortDevice:3 device:1];
      }
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

  bridge_log_printf(RETRO_LOG_INFO, "[Bridge] WiiDeviceProbe coreID=%s systemID=%s ext=%s g_wiiControllerType=%d path=%s",
                    g_coreID ? g_coreID.UTF8String : "(null)",
                    g_systemID ? g_systemID.UTF8String : "(null)",
                    _retainedRomPath ? _retainedRomPath.pathExtension.UTF8String : "(null)",
                    g_wiiControllerType,
                    _retainedRomPath ? _retainedRomPath.UTF8String : "(null)");

  if (g_coreCapabilities.isDolphin) {
    NSString *ext = [_retainedRomPath.pathExtension lowercaseString];
    if ([ext isEqualToString:@"wbfs"] || [ext isEqualToString:@"wad"] || [ext isEqualToString:@"wia"] ||[ext isEqualToString:@"rvz"]) {
      // 0 = auto (Swift resolves to Wiimote+Classic when a controller is connected,
      // otherwise plain Wiimote); non-zero = explicit override device value.
      device_type = (g_wiiControllerType != 0) ? (unsigned)g_wiiControllerType : 1;
    }
} else if (g_coreCapabilities.isSwanStation ||
              g_coreCapabilities.isMednafenPSX ||
              g_coreCapabilities.isPCSX) {
       device_type = 1;
} else if (g_coreCapabilities.isMame ||
               g_coreCapabilities.isDOSBox) {
         device_type = (g_dosDeviceType != 0) ? g_dosDeviceType : 1; // RETRO_DEVICE_JOYPAD — DOSBox-Pure exposes a guest joystick only when a joystick subclass is set (0 keeps the Generic Keyboard default)
         bridge_log_printf(RETRO_LOG_INFO, "[Bridge] DOSDeviceProbe coreID=%s g_dosDeviceType=%u device_type=%u",
                           g_coreID ? g_coreID.UTF8String : "(null)",
                           g_dosDeviceType, device_type);
     } else if (g_coreCapabilities.isMupen64 ||
              g_coreCapabilities.isParallelN64) {
        device_type = 5; // RETRO_DEVICE_ANALOG for proper N64 analog + digital input
  } else if (g_coreCapabilities.isGenesisPlusGX ||
                          g_coreCapabilities.isPicodrive) {
    if (g_genesisDeviceType != 0) {
      device_type = g_genesisDeviceType;
    }
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
  } @try {
      [self setControllerPortDevice:0 device:device_type];
      [self setControllerPortDevice:1 device:device_type];
      [self setControllerPortDevice:2 device:device_type];
      [self setControllerPortDevice:3 device:device_type];
  } @catch (NSException *portDeviceException) {
      bridge_log_printf(RETRO_LOG_ERROR,
          "[Bridge] retro_set_controller_port_device threw post-load (coreID=%s device_type=%u): %@",
          g_coreID ? g_coreID.UTF8String : "(null)",
          device_type,
          portDeviceException.reason ?: @"(no reason)");
  }
    NSLog(@"[Bridge] WiiDeviceApply device_type=%u for dolphin ports 0-3", device_type);

    // Signal variables updated for Flycast cores so retro_run() triggers
    // update_variables() with first_startup=false, which processes device
    // port options (reicast_device_port*_slot*) that are skipped on first init
    if (g_coreCapabilities.isFlycast) {
        g_variablesUpdated = YES;
        bridge_log_printf(RETRO_LOG_INFO, "[LibretroCore] Set g_variablesUpdated=YES for Flycast device port override");
    }

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
    _audioStartTimeMach = mach_absolute_time();

    _saveStatePath =[romPath stringByAppendingString:@".state"];

  // Notify Swift that game is loaded - it will handle SRAM loading
  if (g_gameLoadedCallback) {
    g_gameLoadedCallback(_retainedRomPath.UTF8String);
  }

  _running = YES;
  _speedMultiplier = 1.0f;
  _frameCount = 0;
  _lastCaptureFrame = 0;

  while (_running) {
    if (g_isPaused) {
      [NSThread sleepForTimeInterval:0.05];
      continue;
    }

    // Audio back-pressure: wait if buffer is too full. Disabled entirely in
    // fast-forward — we want emulation to outrun audio output (excess samples
    // are dropped at the ring buffer's write head), matching RetroArch's
    // fast-forward behavior. Keeping back-pressure on at >1x would throttle
    // emulation to the audio consumer's real-time rate, making the speed-up
    // inaudible (the original 2x-sounds-normal bug).
    @autoreleasepool {
      if (_speedMultiplier <= 1.0f) {
        size_t availableSamples = _audioBuffer->available();
        size_t capacity = _audioBuffer->capacity();
        float fillRatio = (float)availableSamples / (float)capacity;

        while (fillRatio > 0.50f && _running && !g_isPaused) {
          [NSThread sleepForTimeInterval:0.001];
          availableSamples = _audioBuffer->available();
          fillRatio = (float)availableSamples / (float)capacity;
        }
      }
    }

    int runCount = 1;
    if (_speedMultiplier > 1.5f) {
      // Multi-step per loop iter so game time actually advances N times.
      // 2x -> 2 retro_runs per iter, 4x -> 4, 8x -> 8.
      int target = (int)(_speedMultiplier + 0.5f);
      runCount = target > 8 ? 8 : target;
    }

    uint64_t start = 0;
    uint64_t end = 0;
    for (int rc = 0; rc < runCount && _running && !g_isPaused; rc++) {
      // Wrap each frame iteration in an autoreleasepool: serializeState returns
      // an autoreleased NSData (dataWithBytesNoCopy:freeWhenDone:YES) that the
      // state-capture callback marshals to Swift. Without a pool here the
      // autoreleased NSData from every capture (~20/sec when rewind is on)
      // accumulates against the emulation thread's stack-allocator until the
      // run loop exits — unbounded growth that jetsam kills. The pool drains
      // at end of iteration after the callback has captured its own copy.
      @autoreleasepool {
        [_coreLock lock];
        @try {
          if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);
          if (rc == 0) start = mach_absolute_time();
          if (_retro_run) {
              _retro_run();
          }
          if (rc == runCount - 1) end = mach_absolute_time();
          if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
        } @catch (NSException *exception) {
          _running = NO;
        } @catch (...) {
          _running = NO;
        }
        [_coreLock unlock];

        _frameCount++;

        if (_stateCaptureCallback && _rewindEnabled && _speedMultiplier == 1.0f) {
          if (_frameCount - _lastCaptureFrame >= 3) {
            _lastCaptureFrame = _frameCount;
            NSData *state = [self serializeState];
            if (state) _stateCaptureCallback(state, _frameCount);
          }
        }
      }
    }

    // Frame pacing
    static mach_timebase_info_data_t s_tb = {0, 0};
    if (s_tb.denom == 0) mach_timebase_info(&s_tb);
    uint64_t elapsed_ns = (end - start) * s_tb.numer / s_tb.denom;
    double elapsed = (double)elapsed_ns / 1e9;

    float mult = (_speedMultiplier < 0.01f) ? 0.01f : _speedMultiplier;
    double targetFPS = _avInfo.timing.fps * mult;
    if (targetFPS <= 0.0 || targetFPS > 120.0 * mult) targetFPS = 60.0 * mult;
    double idealFrameTime = 1.0 / targetFPS;

    // One loop iteration produces runCount frames of game time. The pacing
    // budget must scale with runCount or fast-forward accumulates negative
    // frameError every iteration and effectively runs unbounded — making
    // 2x/4x indistinguishable and only 8x noticing because runCount caps the
    // frame production rate.
    double idealIterTime = idealFrameTime * (double)runCount;

    frameError += (idealIterTime - elapsed);

    if (frameError > 0.001) {
      // Drain accumulated frame error with measured-actual-time sleeps so we
      // don't accumulate oversleep error across chunks. At 1.0x the audio
      // back-pressure block above is the wall-clock master — by the time we
      // get here the buffer is at ~50% and the audio consumer is keeping up,
      // so we only need a minor top-up. At <1.0x (slow-mo) we produce samples
      // slower than the hardware consumes them, so the buffer is near-empty
      // and the fill gate would defeat slow-mo — bypass it then. At >1.0x
      // there's no audio back-pressure (disabled above), so we always gate on
      // fill unless fast-forwarding.
      BOOL gateOnAudioFill = (_speedMultiplier == 1.0f);
      @autoreleasepool {
        size_t avail = _audioBuffer->available();
        size_t cap = _audioBuffer->capacity();
        float fill = (float)avail / (float)cap;
        if (gateOnAudioFill && fill <= 0.10f) {
          // Audio consumer caught up — no need to pad pacing further.
          frameError = 0;
        } else {
          while (frameError > 0.001 && _running && !g_isPaused) {
            double sleepTime = frameError > 0.008 ? 0.008 : frameError;
            if (sleepTime <= 0.0) break;
            uint64_t sleepStart = mach_absolute_time();
            [NSThread sleepForTimeInterval:sleepTime];
            uint64_t sleepEnd = mach_absolute_time();
            double actualNs = (double)(sleepEnd - sleepStart) * s_tb.numer / s_tb.denom;
            frameError -= actualNs / 1e9;
            if (frameError < 0) frameError = 0;
          }
        }
      }
    } else {
      frameError = 0;
    }
  }

shutdown:
  if ([_audioEngine isRunning]) {[_audioEngine stop];}[_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  BOOL isBuggyShutdown = g_coreCapabilities.isPSP ||
                       g_coreCapabilities.isSwanStation ||
                       g_coreCapabilities.isDuckStation;

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

    _retainedRomData = nil;
    _retainedRomPath = nil;

    _videoCallback = nil;

    if (_hwReadbackBuffer) {
        free(_hwReadbackBuffer);
		_hwReadbackBuffer = NULL;
		_hwReadbackBufferSize = 0;
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
  if (g_instance == self) g_instance = nil;
  [_coreLock unlock];

  if (_audioEngine) {
      [_audioEngine stop];
      _audioEngine = nil;
      _audioSourceNode = nil;
  }
  if (_audioBuffer) {
      delete _audioBuffer;
      _audioBuffer = nil;
  }
  if (_audioRenderScratch) {
      free(_audioRenderScratch);
      _audioRenderScratch = NULL;
      _audioRenderScratchCapacity = 0;
  }
  if (_glContext) {
      CGLSetCurrentContext(_glContext);
      if (_hw_callback.context_destroy) {
          @try { _hw_callback.context_destroy(); } @catch (...) {}
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
  _videoCallback = nil;

  if (_dlHandle) {
      int rc = dlclose(_dlHandle);
      if (rc != 0) {
          bridge_log_printf(RETRO_LOG_WARN, "[Shutdown] dlclose(%p) returned %d — %s", _dlHandle, rc, dlerror() ?: "unknown");
      } else {
          bridge_log_printf(RETRO_LOG_INFO, "[Shutdown] dlclose(%p) succeeded — core dylib unmapped", _dlHandle);
      }
      _dlHandle = NULL;
  }

  if (g_bridgeCompletionSemaphore) {
    dispatch_semaphore_signal(g_bridgeCompletionSemaphore);
  }

  return didInit;
}

- (void)stop {
    _running = NO;
    if (_audioEngine && [_audioEngine isRunning]) {
        [_audioEngine stop];
    }
    g_keyboard_callback_registered = NO;
    g_keyboard_callback.callback = NULL;
}

- (void)cleanup {
	if (_audioEngine && [_audioEngine isRunning]) {
		[_audioEngine stop];
	}
	_audioEngine = nil;
	_audioSourceNode = nil;

    if (_audioBuffer) {
        delete _audioBuffer;
        _audioBuffer = nil;
    }

    if (_audioRenderScratch) {
        free(_audioRenderScratch);
        _audioRenderScratch = NULL;
        _audioRenderScratchCapacity = 0;
    }

	if (_glContext) {
		CGLSetCurrentContext(_glContext);
		if (_hw_callback.context_destroy) {
			@try { _hw_callback.context_destroy(); } @catch (...) {}
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

	if (_hwReadbackBuffer) {
		free(_hwReadbackBuffer);
		_hwReadbackBuffer = NULL;
		_hwReadbackBufferSize = 0;
	}

    _videoCallback = nil;

    _retainedRomData = nil;
    _retainedRomPath = nil;
    _hwRenderEnabled = NO;

    if (_dlHandle) {
        int rc = dlclose(_dlHandle);
        if (rc != 0) {
            bridge_log_printf(RETRO_LOG_WARN, "[Cleanup] dlclose(%p) returned %d — %s", _dlHandle, rc, dlerror() ?: "unknown");
        } else {
            bridge_log_printf(RETRO_LOG_INFO, "[Cleanup] dlclose(%p) succeeded — core dylib unmapped", _dlHandle);
        }
        _dlHandle = NULL;
    }
}

- (NSData *)serializeState {
  // Some cores (PPSSPP, Dolphin) report a different serialize size mid-session
  // than at startup because decoder state (e.g. MpegContext map) is allocated
  // lazily. Always re-query and don't trust a previously cached value — a too-
  // small buffer makes retro_serialize overrun it during PointerWrap::DoVoid.
  [_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  size_t serializeSize = 0;
  if (_retro_serialize_size) {
    serializeSize = _retro_serialize_size();
  }
  _cachedSerializeSize = serializeSize;

  if (!serializeSize || !_retro_serialize) {
    if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
    [_coreLock unlock];
    return nil;
  }

  void *buf = malloc(serializeSize);
  NSData *data = nil;
  if (buf) {
    @try {
        if (_retro_serialize(buf, serializeSize)) {
          data =[NSData dataWithBytesNoCopy:buf length:serializeSize freeWhenDone:YES];
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
  // Same rationale as serializeState: serialize size can grow mid-session
  // (e.g. PPSSPP allocating MpegContext during FMVs), so re-query each call.
  [_coreLock lock];
  if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);

  size_t serializeSize = 0;
  if (_retro_serialize_size) {
    serializeSize = _retro_serialize_size();
  }
  _cachedSerializeSize = serializeSize;

  if (!serializeSize || !_retro_serialize) {
    if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
    [_coreLock unlock];
    return;
  }

  void *buf = malloc(serializeSize);
  if (buf) {
    if (_retro_serialize(buf, serializeSize)) {
      NSData *data =[NSData dataWithBytesNoCopy:buf length:serializeSize];[data writeToFile:_saveStatePath atomically:YES];
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
#ifdef XPC_SERVICE
  if (g_xpc_shm) {
    xpc_shm_write_audio(g_xpc_shm, data, count);
  }
#endif
}

- (void)setKeyState:(int)idx pressed:(BOOL)p {
  [self setKeyStateForPlayer:0 button:idx pressed:p];
}

- (void)setKeyStateForPlayer:(int)port button:(int)idx pressed:(BOOL)p {
  if (port >= 0 && port < MAX_PLAYERS && idx >= 0 && idx < 32) {
    g_input_state[port][idx] = p ? 1 : 0;
  }
}

- (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx {
  [self setTurboStateForPlayer:0 index:idx active:active targetButton:targetIdx];
}

- (void)setTurboStateForPlayer:(int)port index:(int)idx active:(BOOL)active targetButton:(int)targetIdx {
  if (port >= 0 && port < MAX_PLAYERS && idx >= 0 && idx < 32) {
    g_turbo_active[port][idx] = active;
    g_turbo_fireButton[port][idx] = targetIdx;
    if (!active) {
      g_turbo_state[port][idx] = NO;
      g_turbo_counter[port][idx] = 0;
      if (targetIdx >= 0 && targetIdx < 32) {
        g_input_state[port][targetIdx] = 0;
      }
    }
  }
}

- (void)setAnalogState:(int)idx id:(int)id value:(int)v {
  [self setAnalogStateForPlayer:0 stick:idx axis:id value:v];
}

- (void)setAnalogStateForPlayer:(int)port stick:(int)idx axis:(int)id value:(int)v {
  if (port >= 0 && port < MAX_PLAYERS && idx >= 0 && idx < 2 && id >= 0 && id < 2) g_analog_state[port][idx][id] = (int16_t)v;
}

- (void)setAnalogButtonState:(int)retroID value:(int)v {
  [self setAnalogButtonStateForPlayer:0 button:retroID value:v];
}

- (void)setAnalogButtonStateForPlayer:(int)port button:(int)retroID value:(int)v {
  if (port >= 0 && port < MAX_PLAYERS && retroID >= 0 && retroID < 32) g_analog_button_state[port][retroID] = (int16_t)v;
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

    // Unbind PBO to ensure we read into CPU memory, not an offset into a core's PBO
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glReadPixels(0, 0, w, h, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _hwReadbackBuffer);
    
    //NSLog(@"[Core-DGB] Readback pixels - first: 0x%08X, last: 0x%08X", firstPixel, lastPixel);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);

  uint32_t *pixels = (uint32_t *)_hwReadbackBuffer;
  BOOL isPSP = g_coreCapabilities.isPSP;
  BOOL isPS1_swanstation = g_coreCapabilities.isSwanStation;
  BOOL isPS2_play = g_coreCapabilities.isPS2Play;
  BOOL isDolphin = g_coreCapabilities.isDolphin;
  BOOL isDOSBox = g_coreCapabilities.isDOSBox;
  BOOL isDreamcast = g_coreCapabilities.isFlycast;
  BOOL is3DS = g_coreCapabilities.is3DS;
  BOOL isN64 = g_coreCapabilities.isMupen64;

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

// MARK: - Speed & Rewind Control

- (void)setSpeedMultiplier:(float)multiplier {
    _speedMultiplier = multiplier;
}

- (void)setRewindEnabled:(BOOL)enabled captureInterval:(unsigned)frames {
    _rewindEnabled = enabled;
}

- (void)setStateCaptureCallback:(void (^)(NSData *state, uint64_t frameIndex))callback {
    @synchronized (self) {
        _stateCaptureCallback = callback;
    }
}

- (void)flushAudio {
    if (_audioBuffer) {
        _audioBuffer->clear();
    }
}

- (void)runSingleFrame {
    // Render one frame under the core lock so an unserialized snapshot
    // becomes visible. Safe while the run loop is parked in its paused
    // branch (it sleeps outside the core lock).
    [_coreLock lock];
    @try {
        if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(_glContext);
        if (_retro_run) {
            _retro_run();
        }
        if (_hwRenderEnabled && _glContext) CGLSetCurrentContext(NULL);
    } @catch (...) {}
    [_coreLock unlock];
}

- (void)setFrameCount:(uint64_t)frameCount {
    // Reset the internal capture-indexing clock so post-scrub captures are
    // indexed contiguously with the truncated buffer. Grab the core lock
    // briefly so we don't race with the run loop bumping _frameCount.
    [_coreLock lock];
    _frameCount = frameCount;
    _lastCaptureFrame = frameCount;
    [_coreLock unlock];
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

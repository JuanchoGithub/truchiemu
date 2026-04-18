#import "LibretroBridge.h"
#import "LibretroBridgeImpl.h"
#import "LibretroGlobals.h"
#import "LibretroCallbacks.h" // <-- ADD THIS LINE

static dispatch_queue_t g_bridgeQueue = nil;
static dispatch_queue_t g_optAccessQueue = nil;
static dispatch_once_t g_optAccessQueueOnce;
static BOOL g_loadingForOptions = NO;
static NSString *_Nullable g_optionsDylibPath = nil;


@implementation LibretroBridge

+ (void)registerCoreLogger:(CoreLoggerBlock)block {
  // Just store the block. 
  // LibretroGlobals.mm handles the actual execution safely!
  g_swiftLoggerBlock = block;
}

+ (void)launchWithDylibPath:(NSString *)dylibPath
                    romPath:(NSString *)romPath
                  shaderDir:(nullable NSString *)shaderDir
              videoCallback:(void (^)(const void *, int, int, int, int))cb
                     coreID:(NSString *)coreID
            failureCallback:(nullable void (^)(NSString *))failureCb {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    g_bridgeQueue = dispatch_queue_create("com.truchiemu.bridge", DISPATCH_QUEUE_SERIAL);
  });

  g_bridgeCompletionSemaphore = dispatch_semaphore_create(0);
  dispatch_semaphore_t semToSignal = g_bridgeCompletionSemaphore;

  g_coreID =[coreID copy];
  g_shaderDir = [shaderDir copy];
  initOptStorage();
  [g_optValues removeAllObjects];
  g_optDefinitions = nil;
  g_optCategories = nil;

  dispatch_async(g_bridgeQueue, ^{
    LibretroBridgeImpl *oldInst = g_instance;
    LibretroBridgeImpl *newInst = [[LibretroBridgeImpl alloc] init];
    g_instance = newInst;

    if (oldInst) {
      bridge_log_printf(RETRO_LOG_INFO, "Signalling previous instance to stop...");
      [oldInst stop];
    }

    bridge_log_printf(RETRO_LOG_INFO, "Starting new core session: %@", dylibPath.lastPathComponent);

    BOOL loadSuccess = NO;
    @try {
        if ([newInst loadDylib:dylibPath]) {
          loadSuccess =[newInst launchROM:romPath videoCallback:cb];
        } else {
          if (failureCb) failureCb(@"Failed to load core dylib.");
        }
    } @catch (NSException *e) {
        if (failureCb) failureCb([NSString stringWithFormat:@"Core crashed during launch: %@", e.reason]);
    }

    if (!loadSuccess && failureCb) {
        failureCb(@"Failed to launch game. Check core compatibility or BIOS files.");
    }

    if (g_instance == newInst) {
      g_instance = nil;
    }

    dispatch_semaphore_signal(semToSignal);
  });
}

+ (void)stop {
  if (g_instance) {
    [g_instance stop];
  }
}

+ (void)waitForCompletion {
  if (g_bridgeCompletionSemaphore) {
    if (dispatch_semaphore_wait(g_bridgeCompletionSemaphore, dispatch_time(DISPATCH_TIME_NOW, 0)) == 0) {
      return;
    }
    dispatch_time_t mediumTimeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC));
    long result = dispatch_semaphore_wait(g_bridgeCompletionSemaphore, mediumTimeout);
    
    if (result != 0) {
      dispatch_time_t finalTimeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC));
      dispatch_semaphore_wait(g_bridgeCompletionSemaphore, finalTimeout);
    }
  }
}

+ (void)saveState { if (g_instance) [g_instance saveState]; }
+ (NSData *)serializeState { return g_instance ? [g_instance serializeState] : nil; }
+ (BOOL)unserializeState:(NSData *)data { return g_instance ?[g_instance unserializeState:data] : NO; }
+ (size_t)serializeSize {
  if (g_instance) {
    if (g_instance->_cachedSerializeSize == 0 && g_instance->_retro_serialize_size) {
      g_instance->_cachedSerializeSize = g_instance->_retro_serialize_size();
    }
    return g_instance->_cachedSerializeSize;
  }
  return 0;
}
+ (void)setKeyState:(int)rid pressed:(BOOL)p { if (g_instance)[g_instance setKeyState:rid pressed:p]; }
+ (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx {
  if (g_instance)[g_instance setTurboState:idx active:active targetButton:targetIdx];
}
+ (void)setAnalogState:(int)idx id:(int)id value:(int)v {
  if (g_instance)[g_instance setAnalogState:idx id:id value:v];
}
+ (void)setLanguage:(int)language { g_selectedLanguage = language; }
+ (void)setLogLevel:(int)level { g_logLevel = level; }
+ (void)setPaused:(BOOL)paused { g_isPaused = paused; }
+ (BOOL)isPaused { return g_isPaused; }

// Load a core (optionally with a ROM) to initialize its options
+ (void)loadCoreForOptions:(NSString *)dylibPath coreID:(NSString *)coreID romPath:(nullable NSString *)romPath {
  g_loadingForOptions = YES;
  g_coreID = [coreID copy];
  g_optionsDylibPath = [dylibPath copy];
  g_optValues = nil;
  g_optDefinitions = nil;
  g_optCategories = nil;

  LibretroBridgeImpl *impl = [[LibretroBridgeImpl alloc] init];
  g_instance = impl;

  if (![impl loadDylib:dylibPath]) {
    g_optCategories = @{}; g_optDefinitions = @{}; g_optValues = [NSMutableDictionary dictionary];
    g_instance = nil; g_loadingForOptions = NO;
    return;
  }

  impl->_retro_set_environment(bridge_environment);
  impl->_retro_init();

  struct retro_system_av_info avInfo;
  avInfo.geometry.base_width = 640; avInfo.geometry.base_height = 480;
  avInfo.geometry.max_width = 640; avInfo.geometry.max_height = 480;
  avInfo.geometry.aspect_ratio = 4.0f / 3.0f;
  avInfo.timing.fps = 60.0; avInfo.timing.sample_rate = 44100.0;
  impl->_avInfo = avInfo;

  BOOL supportsNoGame = NO;
  bridge_environment(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &supportsNoGame);

  struct retro_game_info gi;
  memset(&gi, 0, sizeof(gi));

  BOOL gameLoaded = impl->_retro_load_game(&gi);
  if (gameLoaded) {
    [impl->_coreLock lock];
    if (impl->_hwRenderEnabled && impl->_hw_callback.context_reset) {
      if (impl->_glContext) CGLSetCurrentContext(impl->_glContext);
      impl->_hw_callback.context_reset();
    }
    if (impl->_hwRenderEnabled && impl->_glContext) CGLSetCurrentContext(NULL);
    [impl->_coreLock unlock];

    [impl->_coreLock lock];
    if (impl->_hwRenderEnabled && impl->_glContext) CGLSetCurrentContext(impl->_glContext);
    if (impl->_retro_run) impl->_retro_run();
    if (impl->_hwRenderEnabled && impl->_glContext) CGLSetCurrentContext(NULL);
    [impl->_coreLock unlock];
  }

  [[NSUserDefaults standardUserDefaults] setObject:coreID forKey:@"lastLoadedCoreID"];

  [impl->_coreLock lock];
  if (impl->_hwRenderEnabled && impl->_glContext) CGLSetCurrentContext(impl->_glContext);
  
  if (gameLoaded) {
    impl->_retro_unload_game();
  }
  
  if (impl->_hwRenderEnabled && impl->_hw_callback.context_destroy) {
    impl->_hw_callback.context_destroy();
    impl->_hw_callback.context_destroy = NULL;
  }
  
  impl->_retro_deinit();
  
  if (impl->_hwRenderEnabled && impl->_glContext) CGLSetCurrentContext(NULL);
  [impl->_coreLock unlock];

  g_instance = nil;
  g_loadingForOptions = NO;
}

+ (BOOL)isCoreLoadedForOptions { return g_loadingForOptions; }
+ (int)currentRotation { return g_currentRotation; }
+ (float)aspectRatio {
  if (g_instance) {
    float ar = g_instance->_avInfo.geometry.aspect_ratio;
    if (ar <= 0.0f && g_instance->_avInfo.geometry.base_height > 0) {
      ar = (float)g_instance->_avInfo.geometry.base_width / (float)g_instance->_avInfo.geometry.base_height;
    }
    return ar;
  }
  return 0.0f;
}

+ (NSString *)getOptionValueForKey:(NSString *)key {
  dispatch_once(&g_optAccessQueueOnce, ^{
    g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
  });
  __block NSString *result = nil;
  dispatch_sync(g_optAccessQueue, ^{
    if (g_optValues) result = [g_optValues[key] copy];
  });
  return result;
}

+ (void)setOptionValue:(NSString *)value forKey:(NSString *)key {
  dispatch_once(&g_optAccessQueueOnce, ^{
    g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
  });
  dispatch_async(g_optAccessQueue, ^{
    initOptStorage();
    if (key) g_optValues[key] = value ?: @"";
  });
}

+ (void)resetOptionToDefaultForKey:(NSString *)key {
  dispatch_once(&g_optAccessQueueOnce, ^{
    g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
  });
  dispatch_async(g_optAccessQueue, ^{
    if (g_optDefinitions && g_optDefinitions[key]) {
      NSString *defaultVal = g_optDefinitions[key][@"defaultValue"];
      if (defaultVal) { initOptStorage(); g_optValues[key] = defaultVal; }
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
        if (defVal) g_optValues[key] = defVal;
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
        NSMutableDictionary *entry =[NSMutableDictionary dictionaryWithDictionary:g_optDefinitions[key]];
        entry[@"currentValue"] = g_optValues[key] ?: g_optDefinitions[key][@"defaultValue"] ?: @"";
        combined[key] = [entry copy];
      }
      result = [combined copy];
    }
  });
  return result;
}

+ (NSDictionary<NSString *, NSDictionary *> *)getCategoriesDictionary {
  dispatch_once(&g_optAccessQueueOnce, ^{
    g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
  });
  __block NSDictionary *result = nil;
  dispatch_sync(g_optAccessQueue, ^{ result = [g_optCategories copy] ?: @{}; });
  return result;
}

+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled {
  if (!g_instance || !g_instance->_retro_cheat_set) return;
  const char *codeStr = code.UTF8String;
  [g_instance->_coreLock lock];
  g_instance->_retro_cheat_set(index, enabled, codeStr);[g_instance->_coreLock unlock];
}

+ (void)resetCheats {
  if (!g_instance || !g_instance->_retro_cheat_reset) return;
  [g_instance->_coreLock lock];
  g_instance->_retro_cheat_reset();
  [g_instance->_coreLock unlock];
}

+ (void)applyCheats:(NSArray<NSDictionary *> *)cheats {
  if (!g_instance) return;
  [self resetCheats];
  for (NSDictionary *cheat in cheats) {
    NSNumber *indexNum = cheat[@"index"];
    NSString *code = cheat[@"code"];
    BOOL enabled = [cheat[@"enabled"] boolValue];
    if (indexNum && code && enabled) {
      [self setCheatEnabled:[indexNum intValue] code:code enabled:YES];
    }
  }
}

+ (void *)getMemoryData:(unsigned)type size:(size_t *)size {
  if (!g_instance || !g_instance->_retro_get_memory_data) return NULL;
  [g_instance->_coreLock lock];
  void *data = g_instance->_retro_get_memory_data(type);
  if (size && g_instance->_retro_get_memory_size) {
    *size = g_instance->_retro_get_memory_size(type);
  }
  [g_instance->_coreLock unlock];
  return data;
}

+ (void)writeMemoryByte:(uint32_t)address value:(uint8_t)value {
  if (!g_instance) return;
  [g_instance->_coreLock lock];
  if (g_instance->_retro_get_memory_data) {
    size_t memSize = 0;
    uint8_t *ram = (uint8_t *)g_instance->_retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM);
    if (ram && g_instance->_retro_get_memory_size) {
      memSize = g_instance->_retro_get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
    }
    if (ram && address < memSize) ram[address] = value;
  }
  [g_instance->_coreLock unlock];
}

+ (void)applyDirectMemoryCheats:(NSArray<NSDictionary *> *)cheats {
  if (!g_instance) return;
  [g_instance->_coreLock lock];

  size_t memSize = 0;
  uint8_t *ram = NULL;
  if (g_instance->_retro_get_memory_data) {
    ram = (uint8_t *)g_instance->_retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM);
    if (ram && g_instance->_retro_get_memory_size) {
      memSize = g_instance->_retro_get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
    }
    if (!ram) {
      ram = (uint8_t *)g_instance->_retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
      if (ram && g_instance->_retro_get_memory_size) {
        memSize = g_instance->_retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
      }
    }
  }

  if (ram) {
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
        }
      }
    }
  }[g_instance->_coreLock unlock];
}

@end
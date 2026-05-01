#import "LibretroBridge.h"
#import "LibretroBridgeImpl.h"
#import "LibretroGlobals.h"
#import "LibretroCallbacks.h"
#import "SaveDirectoryBridge.h"

// --- Global State ---
static dispatch_queue_t g_bridgeQueue = nil;
static dispatch_queue_t g_optAccessQueue = nil;
static dispatch_once_t g_optAccessQueueOnce;
static NSString *_Nullable g_optionsDylibPath = nil;

// --- Callback Stubs for Headless Mode ---
// These are critical. They provide valid memory addresses for the core to call
// during option discovery, preventing the 0x0 null pointer crash.
static void video_stub(const void *data, unsigned width, unsigned height, size_t pitch) {}
static void audio_stub(int16_t left, int16_t right) {}
static size_t audio_batch_stub(const int16_t *data, size_t frames) { return frames; }
static void input_poll_stub(void) {}
static int16_t input_state_stub(unsigned port, unsigned device, unsigned index, unsigned id) { return 0; }

@implementation LibretroBridge

+ (void)registerCoreLogger:(CoreLoggerBlock)block {
    // Just store the block. LibretroGlobals handles execution safety.
    g_swiftLoggerBlock = block;
}

+ (void)registerGameLoadedCallback:(GameLoadedBlock)block {
    g_gameLoadedCallback = block;
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

    NSString *cleanCoreID = coreID;
    if ([cleanCoreID hasSuffix:@".dylib"]) {
        cleanCoreID = [cleanCoreID stringByDeletingPathExtension];
    }
    g_coreID = [cleanCoreID copy];
    NSLog(@"[Bridge] Active CoreID set to: '%@'", g_coreID);
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
                loadSuccess = [newInst launchROM:romPath videoCallback:cb];
            } else {
                if (failureCb) failureCb(@"Failed to load core dylib.");
            }
        } @catch (NSException *e) {
            if (failureCb) failureCb([@"Core crashed during launch: " stringByAppendingString:e.reason]);
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
+ (BOOL)unserializeState:(NSData *)data { return g_instance ? [g_instance unserializeState:data] : NO; }
+ (size_t)serializeSize {
    if (g_instance) {
        if (g_instance->_cachedSerializeSize == 0 && g_instance->_retro_serialize_size) {
            g_instance->_cachedSerializeSize = g_instance->_retro_serialize_size();
        }
        return g_instance->_cachedSerializeSize;
    }
    return 0;
}
+ (void)setKeyState:(int)rid pressed:(BOOL)p { if (g_instance) [g_instance setKeyState:rid pressed:p]; }
+ (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx {
    if (g_instance) [g_instance setTurboState:idx active:active targetButton:targetIdx];
}
+ (void)setAnalogState:(int)idx id:(int)id value:(int)v {
    if (g_instance) [g_instance setAnalogState:idx id:id value:v];
}
+ (void)setLanguage:(int)language { g_selectedLanguage = language; }
+ (void)setLogLevel:(int)level { g_logLevel = level; }
+ (void)setPaused:(BOOL)paused { g_isPaused = paused; }
+ (BOOL)isPaused { return g_isPaused; }

// --- Load a core to initialize its options (Headless Mode) ---
+ (void)loadCoreForOptions:(NSString *)dylibPath coreID:(NSString *)coreID romPath:(nullable NSString *)romPath {
    // Guard against concurrent calls - only one discovery session at a time
    static BOOL discoveryInProgress = NO;
    if (discoveryInProgress) {
        bridge_log_printf(RETRO_LOG_WARN, "Discovery: Skipping - another discovery is already in progress");
        return;
    }
    discoveryInProgress = YES;

    bridge_log_printf(RETRO_LOG_INFO, "Discovery: Starting headless session for %@", coreID);

    g_loadingForOptions = YES;
    NSString *cleanCoreID = coreID;
    if ([cleanCoreID hasSuffix:@".dylib"]) {
        cleanCoreID = [cleanCoreID stringByDeletingPathExtension];
    }
    g_coreID = [cleanCoreID copy];
    g_optionsDylibPath = [dylibPath copy];
    g_optValues = nil;
    g_optDefinitions = nil;
    g_optCategories = nil;
    g_inputDescriptors = nil;

    LibretroBridgeImpl *impl = [[LibretroBridgeImpl alloc] init];
    g_instance = impl;

    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Loading dylib: %@", dylibPath.lastPathComponent);
    if (![impl loadDylib:dylibPath]) {
        bridge_log_printf(RETRO_LOG_ERROR, "Discovery: Failed to load dylib for %@", coreID);
        g_optCategories = @{};
        g_optDefinitions = @{};
        g_optValues = [NSMutableDictionary dictionary];
        g_instance = nil;
        g_loadingForOptions = NO;
        return;
    }

    // Registering stubs prevents crashes if the core tries to call video/audio during discovery
    impl->_retro_set_environment(bridge_environment);
    impl->_retro_set_video_refresh(video_stub);
    impl->_retro_set_audio_sample(audio_stub);
    impl->_retro_set_audio_sample_batch(audio_batch_stub);
    impl->_retro_set_input_poll(input_poll_stub);
    impl->_retro_set_input_state(input_state_stub);

    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Calling retro_init...");
    impl->_retro_init();
    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: retro_init complete.");

    struct retro_system_av_info avInfo;
    avInfo.geometry.base_width = 640; avInfo.geometry.base_height = 480;
    avInfo.geometry.max_width = 640; avInfo.geometry.max_height = 480;
    avInfo.geometry.aspect_ratio = 4.0f / 3.0f;
    avInfo.timing.fps = 60.0; avInfo.timing.sample_rate = 44100.0;
    impl->_avInfo = avInfo;

    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Setting SUPPORT_NO_GAME...");
    BOOL supportsNoGame = NO;
    bridge_environment(RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &supportsNoGame);
    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: SUPPORT_NO_GAME=%d", supportsNoGame);

    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Checking input descriptors captured so far: %lu", (unsigned long)g_inputDescriptors.count);

    // Try loading a fake ROM path to trigger SET_INPUT_DESCRIPTORS during load
    // Use a minimal path that the core can reject quickly
    const char *fakePath = "/tmp/TruchiEmu_discovery_rom";
    bridge_log_printf(RETRO_LOG_INFO, "Discovery: Attempting retro_load_game with fake path: %s", fakePath);

    struct retro_game_info gi;
    memset(&gi, 0, sizeof(gi));
    gi.path = (char *)fakePath;
    gi.data = NULL;
    gi.size = 0;
    gi.meta = NULL;

    BOOL gameLoaded = impl->_retro_load_game(&gi);
    bridge_log_printf(RETRO_LOG_INFO, "Discovery: retro_load_game returned %d", gameLoaded);

    // Check input descriptors after load attempt
    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Input descriptors after load attempt: %lu", (unsigned long)g_inputDescriptors.count);

    if (gameLoaded) {
        bridge_log_printf(RETRO_LOG_INFO, "Discovery: Game unexpectedly loaded (should not happen with fake path).");
    } else {
        bridge_log_printf(RETRO_LOG_INFO, "Discovery: Game load failed as expected (no valid ROM).");
    }

    // --- TEARDOWN SEQUENCE ---
    bridge_log_printf(RETRO_LOG_INFO, "Discovery: Beginning safe teardown for %@", coreID);
    [[NSUserDefaults standardUserDefaults] setObject:coreID forKey:@"lastLoadedCoreID"];

    [impl->_coreLock lock];

    if (impl->_hwRenderEnabled && impl->_glContext) {
        CGLSetCurrentContext(impl->_glContext);
    }

    // Only call retro_unload_game if game was actually loaded (not with fake path)
    if (gameLoaded) {
        bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Unloading game...");
        impl->_retro_unload_game();
        [NSThread sleepForTimeInterval:0.2];
    } else {
        bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Skipping retro_unload_game (no game loaded).");
    }

    bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Calling retro_deinit with timeout...");

    __block BOOL deinitCompleted = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        impl->_retro_deinit();
        deinitCompleted = YES;
        bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: retro_deinit completed normally");
    });

    // Wait for deinit with timeout
    for (int i = 0; i < 20; i++) {
        [NSThread sleepForTimeInterval:0.25];
        if (deinitCompleted) break;
        bridge_log_printf(RETRO_LOG_DEBUG, "Discovery: Waiting for retro_deinit... %d/5s", (i+1)*25/100);
    }

    if (!deinitCompleted) {
        bridge_log_printf(RETRO_LOG_WARN, "Discovery: retro_deinit timed out after 5s, forcing cleanup");
    }

    if (impl->_hwRenderEnabled && impl->_glContext) {
        CGLSetCurrentContext(NULL);
    }

    [impl->_coreLock unlock];

    // CRITICAL: Neutralize the hardware callback struct so that
    // impl's dealloc doesn't try to call context_destroy()
    memset(&(impl->_hw_callback), 0, sizeof(struct retro_hw_render_callback));

    g_instance = nil;
    g_loadingForOptions = NO;
    bridge_log_printf(RETRO_LOG_INFO, "Discovery: Headless session complete for %@.", coreID);
    discoveryInProgress = NO;
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
                NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:g_optDefinitions[key]];
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

+ (NSDictionary<NSString *, NSArray *> *)getInputDescriptorsDictionary {
    dispatch_once(&g_optAccessQueueOnce, ^{
        g_optAccessQueue = dispatch_queue_create("com.truchiemu.bridge.options", DISPATCH_QUEUE_SERIAL);
    });
    __block NSDictionary *result = nil;
    dispatch_sync(g_optAccessQueue, ^{
        result = [g_inputDescriptors copy];
    });
    return result;
}

+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled {
    if (!g_instance || !g_instance->_retro_cheat_set) return;
    const char *codeStr = code.UTF8String;
    [g_instance->_coreLock lock];
    g_instance->_retro_cheat_set(index, enabled, codeStr); 
    [g_instance->_coreLock unlock];
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

+ (NSData *)getSaveRAMData {
    if (!g_instance || !g_instance->_retro_get_memory_data || !g_instance->_retro_get_memory_size) {
        bridge_log_printf(RETRO_LOG_WARN, "SRAM: No instance or memory functions available");
        return nil;
    }
    [g_instance->_coreLock lock];

    // Find the first memory type with non-zero data
    unsigned memoryTypes[] = {0, 1, 2, 3, 4}; // SYSTEM_RAM, SAVE_RAM, VIDEO_RAM, RTC, SYSTEM_RAM_B
    const char *typeNames[] = {"SYSTEM_RAM", "SAVE_RAM", "VIDEO_RAM", "RTC", "SYSTEM_RAM_B"};
    NSData *foundData = nil;
    NSString *foundType = nil;
    unsigned foundTypeId = 0;

    for (int i = 0; i < 5; i++) {
        size_t size = g_instance->_retro_get_memory_size(memoryTypes[i]);
        if (size > 0 && size < 10*1024*1024) { // Reasonable size limit
            uint8_t *data = (uint8_t *)g_instance->_retro_get_memory_data(memoryTypes[i]);
            if (data) {
                bridge_log_printf(RETRO_LOG_INFO, "SRAM: Found %s with %zu bytes", typeNames[i], size);
                // Save the first one with data (prefer SYSTEM_RAM for GBA)
                if (!foundData) {
                    foundData = [NSData dataWithBytes:data length:size];
                    foundType = [NSString stringWithUTF8String:typeNames[i]];
                    foundTypeId = memoryTypes[i];
                }
            }
        }
    }

    [g_instance->_coreLock unlock];

    if (foundData) {
        // Store the type for later load
        g_currentSaveRAMType = foundTypeId;
        bridge_log_printf(RETRO_LOG_INFO, "SRAM: Using %@ with %zu bytes (type %u)", foundType, foundData.length, foundTypeId);
    } else {
        bridge_log_printf(RETRO_LOG_WARN, "SRAM: No memory data available from any type");
    }
    return foundData;
}

+ (NSString *)saveDirectoryPath {
    return [SaveDirectoryBridge libretroSaveDirectoryPath];
}

+ (BOOL)loadSaveRAMData:(NSData *)data {
    if (!g_instance || !g_instance->_retro_get_memory_data || !data) return NO;
    [g_instance->_coreLock lock];

    unsigned memType = g_currentSaveRAMType > 0 ? g_currentSaveRAMType : RETRO_MEMORY_SYSTEM_RAM;
    size_t memSize = g_instance->_retro_get_memory_size(memType);
    if (memSize == 0) {
        bridge_log_printf(RETRO_LOG_WARN, "SRAM load: No memory at type %u", memType);
        [g_instance->_coreLock unlock];
        return NO;
    }
    uint8_t *ram = (uint8_t *)g_instance->_retro_get_memory_data(memType);
    if (!ram) {
        bridge_log_printf(RETRO_LOG_WARN, "SRAM load: No pointer at type %u", memType);
        [g_instance->_coreLock unlock];
        return NO;
    }
    // Don't write more than the core's save RAM size
    size_t copySize = MIN(memSize, data.length);
    memcpy(ram, data.bytes, copySize);
    bridge_log_printf(RETRO_LOG_INFO, "SRAM load: Wrote %zu bytes to type %u", copySize, memType);
    [g_instance->_coreLock unlock];
    return YES;
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
    }
    [g_instance->_coreLock unlock];
}

#pragma mark - Keyboard Input

+ (void)dispatchKeyboardEvent:(unsigned)keycode
character:(unsigned)character
modifiers:(unsigned)modifiers
down:(BOOL)down {
    unsigned device = 0; // Default to None/Any
    device = 0;
    bridge_keyboard_event(down, keycode, character, modifiers, device);
}

#pragma mark - Mouse Input

+ (void)setMouseDeltaX:(int16_t)dx Y:(int16_t)dy {
    g_mouse_state.delta_x = dx;
    g_mouse_state.delta_y = dy;
}

+ (void)addMouseDelta:(int16_t)dx Y:(int16_t)dy {
    // Accumulate deltas — multiple mouse events fire between core frames.
    // Clamping prevents Int16 overflow from rapid mouse movement.
    int32_t newX = (int32_t)g_mouse_state.delta_x + (int32_t)dx;
    int32_t newY = (int32_t)g_mouse_state.delta_y + (int32_t)dy;
    g_mouse_state.delta_x = (int16_t)MAX(-32767, MIN(32767, newX));
    g_mouse_state.delta_y = (int16_t)MAX(-32767, MIN(32767, newY));
}

+ (void)setMouseButton:(int)button pressed:(BOOL)pressed {
    if (button == 0) {
        if (pressed) g_mouse_state.buttons |= 1;       // LEFT
        else g_mouse_state.buttons &= ~1;
    } else if (button == 1) {
        if (pressed) g_mouse_state.buttons |= 2;       // RIGHT
        else g_mouse_state.buttons &= ~2;
    } else if (button == 2) {
        if (pressed) g_mouse_state.buttons |= 4;       // MIDDLE
        else g_mouse_state.buttons &= ~4;
    }
}

+ (void)addMouseWheelDelta:(int16_t)delta {
    g_mouse_state.wheel_delta += delta;
}

+ (void)resetMouseDeltas {
    g_mouse_state.delta_x = 0;
    g_mouse_state.delta_y = 0;
    g_mouse_state.wheel_delta = 0;
}

#pragma mark - Pointer Input

+ (void)setPointerX:(int16_t)x Y:(int16_t)y pressed:(BOOL)pressed {
    g_pointer_x = x;
    g_pointer_y = y;
    g_pointer_pressed = pressed;
}

@end
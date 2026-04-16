#import <Foundation/Foundation.h>
#import "CoreRunnerProtocol.h"
#import "../Engine/libretro.h"
#import <IOSurface/IOSurface.h>
#import <dlfcn.h>
#import <Metal/Metal.h>
@interface SharedSurfaceManager : NSObject
+ (IOSurfaceRef)createSurfaceWithWidth:(int)width height:(int)height;
+ (void)destroySurface:(IOSurfaceRef)surface;
+ (void)writeToSurface:(IOSurfaceRef)surface data:(const void *)data pitch:(size_t)pitch width:(int)width height:(int)height;
@end
#import "../Engine/SharedAudioBuffer.h"

// Define a unique name for the audio buffer
#define AUDIO_SHM_NAME "truchiemu_audio_shm"

/**
 * The CoreRunner class implements the actual Libretro core execution.
 * It runs in the TruchiCoreRunner process.
 */
@interface CoreRunner : NSObject <TruchiCoreRunnerProtocol, NSXPCListenerDelegate>
@end

@implementation CoreRunner {
    NSXPCConnection *_connection;
    void *_dlHandle;
    
    // Libretro Functions
    void (*_retro_init)(void);
    void (*_retro_deinit)(void);
    void (*_retro_run)(void);
    void (*_retro_get_system_info)(struct retro_system_info *);
    void (*_retro_get_system_av_info)(struct retro_system_av_info *);
    void (*_retro_set_environment)(retro_environment_t);
    void (*_retro_set_video_refresh)(retro_video_refresh_t);
    void (*_retro_set_audio_sample)(retro_audio_sample_t);
    void (*_retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*_retro_set_input_poll)(retro_input_poll_t);
    void (*_retro_set_input_state)(retro_input_state_t);
    bool (*_retro_load_game)(const struct retro_game_info *);
    void (*_retro_unload_game)(void);
    size_t (*_retro_serialize_size)(void);
    bool (*_retro_serialize)(void *, size_t);
    bool (*_retro_unserialize)(const void *, size_t);
    
    BOOL _running;
    BOOL _paused;
    struct retro_system_av_info _avInfo;
    int16_t _joypad_state[16];
    
    IOSurfaceRef _surface;
    uint32_t _surfaceID;
    int _width;
    int _height;
    
    SharedAudioBuffer *_audioBuffer;
}

#pragma mark - XPC Listener Delegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TruchiCoreRunnerProtocol)];
    newConnection.exportedObject = self;
    
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TruchiCoreHostProtocol)];
    
    _connection = newConnection;
    [newConnection resume];
    return YES;
}

#pragma mark - Libretro Callbacks (Static)

static CoreRunner *g_runner = nil;


#include <stdarg.h>
static void runner_log_printf(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    NSLog(@"[CoreRunner] %s", buf);
}

static int g_selectedLanguage = 0; // RETRO_LANGUAGE_ENGLISH
static int g_logLevel = 1;         // 1 = Warn & Error
static NSString *g_coreID = nil;   // Core ID for options persistence
static NSString *g_shaderDir =
    nil;                          // Shader directory for libretro slang shaders
static BOOL g_isPaused = NO;      // Pause state
static int g_currentRotation = 0; // Current rotation from core (0=0 deg, 1=90
                                  // deg CW, 2=180 deg, 3=270 deg CW)
// Shared with bridge_get_current_framebuffer — updated by setupHWRender
static unsigned int g_hwFBO = 0;

/* ── Core Options Storage ──
 * Global mutable state so the C environment callback and Swift bridge methods
 * can both read/write option values without dispatching through libdispatch.
 * g_optValues: [optionKey: currentValue]  (NSString -> NSString)
 * g_optDefinitions: [optionKey: {desc, info, default, values[], category}]
 * g_optCategories:[categoryKey: {desc, info}]
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
static void parseCoreOptionsV2(struct retro_core_options_v2 *opts) {
  initOptStorage();
  [g_optValues removeAllObjects];

  NSMutableDictionary *defs = [NSMutableDictionary dictionary];
  NSMutableDictionary *cats = [NSMutableDictionary dictionary];

  /* Parse categories */
  if (opts && opts->categories) {
    struct retro_core_option_v2_category *cat = opts->categories;
    int catCount = 0;
    while (cat->key && catCount < 256) {
      @try {
        cats[[NSString stringWithUTF8String:cat->key]] = @{
          @"desc" : cat->desc ? [NSString stringWithUTF8String:cat->desc] : @"",
          @"info" : cat->info ? [NSString stringWithUTF8String:cat->info] : @""
        };
      } @catch (NSException *exception) {
        runner_log_printf(RETRO_LOG_WARN, " Failed to parse category: %s",
                          exception.reason);
      }
      cat++;
      catCount++;
    }
  }
  g_optCategories = [cats copy];

  /* Parse definitions */
  if (opts && opts->definitions) {
    struct retro_core_option_v2_definition *def = opts->definitions;
    /* Safety limit to prevent infinite loops from corrupted data */
    int defCount = 0;
    while (def && def->key && defCount < 512) {
      @try {
        NSString *key = [NSString stringWithUTF8String:def->key];
        NSString *desc = [NSString
            stringWithUTF8String:(def->desc_categorized ?: def->desc)];
        NSString *info = [NSString
            stringWithUTF8String:(def->info_categorized ?: def->info)];
        NSString *catKey =
            def->category_key
                ? [NSString stringWithUTF8String:def->category_key]
                : nil;
        NSString *defaultVal =
            def->default_value
                ? [NSString stringWithUTF8String:def->default_value]
                : @"";

        /* Parse possible values - fixed-size array with safety check */
        NSMutableArray *vals = [NSMutableArray array];
        for (int vi = 0; vi < RETRO_NUM_CORE_OPTION_VALUES_MAX; vi++) {
          const char *valStr = def->values[vi].value;
          if (!valStr)
            break;

          @try {
            NSString *vval = [NSString stringWithUTF8String:valStr];
            NSString *vlabel =
                def->values[vi].label
                    ? [NSString stringWithUTF8String:def->values[vi].label]
                    : vval;
            [vals addObject:@{@"value" : vval, @"label" : vlabel}];
          } @catch (NSException *exception) {
            runner_log_printf(RETRO_LOG_ERROR,
                              "Failed to parse option value: %s",
                              exception.reason);
            break;
          }
        }

        defs[key] = @{
          @"desc" : desc ?: @"",
          @"info" : info ?: @"",
          @"defaultValue" : defaultVal,
          @"category" : catKey ?: @"",
          @"values" : [vals copy]
        };

        /* Set initial value to default */
        g_optValues[key] = defaultVal;
      } @catch (NSException *exception) {
        runner_log_printf(RETRO_LOG_ERROR,
                          "Failed to parse option definition: %s",
                          exception.reason);
      }
      def++;
      defCount++;
    }
  }
  g_optDefinitions = [defs copy];
}

/* Parse V1 definition (simpler, no categories) */
__attribute__((unused)) static void
parseCoreOptionsV1(struct retro_core_options *opts) {
  initOptStorage();
  [g_optValues removeAllObjects];

  NSMutableDictionary *defs = [NSMutableDictionary dictionary];

  if (opts && opts->definitions) {
    struct retro_core_option_definition *def = opts->definitions;
    /* Safety limit to prevent infinite loops from corrupted data */
    int defCount = 0;
    while (def && def->key && defCount < 512) {
      @try {
        NSString *key = [NSString stringWithUTF8String:def->key];
        NSString *desc =
            def->desc ? [NSString stringWithUTF8String:def->desc] : @"";
        NSString *info =
            def->info ? [NSString stringWithUTF8String:def->info] : @"";
        NSString *defaultVal =
            def->default_value
                ? [NSString stringWithUTF8String:def->default_value]
                : @"";

        NSMutableArray *vals = [NSMutableArray array];
        /* Parse possible values from fixed-size array with safety check */
        for (int vi = 0; vi < RETRO_NUM_CORE_OPTION_VALUES_MAX; vi++) {
          const char *valStr = def->values[vi].value;
          if (!valStr)
            break;

          @try {
            NSString *vval = [NSString stringWithUTF8String:valStr];
            NSString *vlabel =
                def->values[vi].label
                    ? [NSString stringWithUTF8String:def->values[vi].label]
                    : vval;
            [vals addObject:@{@"value" : vval, @"label" : vlabel}];
          } @catch (NSException *exception) {
            runner_log_printf(RETRO_LOG_ERROR,
                              "Failed to parse option value: %s",
                              exception.reason);
            break;
          }
        }

        defs[key] = @{
          @"desc" : desc,
          @"info" : info,
          @"defaultValue" : defaultVal,
          @"category" : @"",
          @"values" : [vals copy]
        };

        g_optValues[key] = defaultVal;
      } @catch (NSException *exception) {
        runner_log_printf(RETRO_LOG_ERROR,
                          "Failed to parse option definition: %s",
                          exception.reason);
      }
      def++;
      defCount++;
    }
  }
  g_optCategories = @{};
  g_optDefinitions = [defs copy];
}

/* Load persisted overrides from .cfg file into g_optValues.
 * File format: key = "value" (one per line).
 * Called after parseCoreOptionsV1/V2 to apply user overrides. */
static void applyPersistedOverrides() {
  if (!g_coreID)
    return;

  NSString *configName = [NSString stringWithFormat:@"%@.cfg", g_coreID];
  NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString *optionsDir =
      [appSupport stringByAppendingPathComponent:@"TruchieEmu/CoreOptions"];
  NSString *configPath = [optionsDir stringByAppendingPathComponent:configName];

  if (![[NSFileManager defaultManager] fileExistsAtPath:configPath])
    return;

  NSString *fileContent =
      [NSString stringWithContentsOfFile:configPath
                                encoding:NSUTF8StringEncoding
                                   error:nil];
  if (!fileContent)
    return;

  NSArray<NSString *> *allLines = [fileContent
      componentsSeparatedByCharactersInSet:[NSCharacterSet
                                               newlineCharacterSet]];

  for (NSString *line in allLines) {
    NSString *trimmed = [line
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || [trimmed hasPrefix:@"#"])
      continue;

    // Parse: key = "value"
    NSRange eqRange = [trimmed rangeOfString:@"="];
    if (eqRange.location == NSNotFound)
      continue;

    NSString *key = [[trimmed substringToIndex:eqRange.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceCharacterSet]];
    NSString *val = [[trimmed substringFromIndex:NSMaxRange(eqRange)]
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceCharacterSet]];

    // Strip surrounding quotes
    if ([val hasPrefix:@"\""] && [val hasSuffix:@"\""]) {
      val = [val substringWithRange:NSMakeRange(1, val.length - 2)];
    }
    if (g_optValues && key.length > 0) {
      g_optValues[key] = val;
      runner_log_printf(RETRO_LOG_INFO, "Override from .cfg: %s = %s",
                        key.UTF8String, val.UTF8String);
    }
  }
}

static uintptr_t bridge_get_current_framebuffer() { return (uintptr_t)g_hwFBO; }

static dispatch_queue_t g_bridgeQueue = nil;
static dispatch_semaphore_t g_bridgeFinishedSemaphore = nil;

// Shared completion signal: signalled when emulation loop fully completes
// (after retro_unload_game and retro_deinit)
static dispatch_semaphore_t _bridgeCompletionSemaphore = nil;

static uintptr_t bridge_get_proc_address(const char *sym) {
  if (!sym)
    return 0;
  static void *glHandle = NULL;
  if (!glHandle)
    glHandle = dlopen(
        "/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL",
        RTLD_LAZY);
  uintptr_t res = (uintptr_t)dlsym(glHandle ? glHandle : RTLD_DEFAULT, sym);
  if (!res && sym[0] != '_') {
    char buf[256];
    snprintf(buf, sizeof(buf), "_%s", sym);
    res = (uintptr_t)dlsym(glHandle ? glHandle : RTLD_DEFAULT, buf);
  }
  // Note: cores probe for many optional extensions (OES, ARB, GL4.2-4.5 DSA,
  // etc.) Missing symbols for optional probes is expected on macOS (GL capped
  // at 4.1). Only log if you need to debug a specific symbol.
  return res;
}

// MARK: - C Callbacks

// Core log callback mechanism: Swift sets this at startup to route libretro
// core logs (e.g. LibretroDB, Bridge, Identify) through LoggerService for file
// persistence.
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

static bool bridge_environment(unsigned cmd, void *data) {
  if (!g_runner)
    return false;

  switch (cmd) {

  // Add case 1: RETRO_ENVIRONMENT_SET_ROTATION
  // To Fix Dreamcast issues
  case RETRO_ENVIRONMENT_SET_ROTATION:
    if (data)
      g_currentRotation = *(const unsigned *)data;
    return true;

  case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
    if (data)
      ((struct retro_log_interface *)data)->log = runner_log_printf;
    return true;

  case RETRO_ENVIRONMENT_GET_CAN_DUPE:
    if (data)
      *(unsigned char *)data = 1;
    return true;

  case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
    static char s_sysPath[1024];
    NSString *path = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    path = [path stringByAppendingPathComponent:@"TruchieEmu/System"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    strncpy(s_sysPath, path.UTF8String, sizeof(s_sysPath) - 1);
    if (data)
      *(const char **)data = s_sysPath;
    return true;
  }
  case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
    static char s_savePath[1024];
    NSString *path = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    path = [path stringByAppendingPathComponent:@"TruchieEmu"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    strncpy(s_savePath, path.UTF8String, sizeof(s_savePath) - 1);
    if (data)
      *(const char **)data = s_savePath;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
    if (data) {
      enum retro_pixel_format fmt = *(enum retro_pixel_format *)data;
      if (g_runner) {
        
      }
    }
    return true;

  case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
    if (data)
      *(unsigned *)data = 2;
    return true;

  case RETRO_ENVIRONMENT_GET_LANGUAGE:
    if (data)
      *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
    return true;

  case RETRO_ENVIRONMENT_GET_VARIABLE: {
    struct retro_variable *var = (struct retro_variable *)data;
    if (var && var->key) {

      // ─── HIGH PRIORITY FLYCAST OVERRIDES ───
      // Check for both modern "flycast_" and legacy "reicast_" prefixes
      if (strstr(var->key, "flycast_") || strstr(var->key, "reicast_")) {

        // 1. DISABLE THREADED RENDERING (Fixes OpenGL Context Race Crash)
        if (strstr(var->key, "threaded_rendering") != NULL) {
          var->value = "disabled";
          runner_log_printf(RETRO_LOG_INFO, "Flycast Override: %s = %s",
                            var->key, var->value);
          return true;
        }

        // 2. FORCE INTERPRETER (Fixes Apple Silicon ARM64 JIT Crash)
        // Check for BOTH "cpu_core" and "cpu_mode" to cover all Flycast
        // versions!
        if (strstr(var->key, "cpu_core") != NULL ||
            strstr(var->key, "cpu_mode") != NULL) {
          var->value = "interpreter";
          runner_log_printf(RETRO_LOG_INFO, "Flycast Override: %s = %s",
                            var->key, var->value);
          return true;
        }

        // 3. ENABLE MMU (Required for WinCE games like Sega Rally 2)
        if (strstr(var->key, "mmu") != NULL) {
          var->value = "enabled";
          runner_log_printf(RETRO_LOG_INFO, "Flycast Override: %s = %s",
                            var->key, var->value);
          return true;
        }

        // 4. ALPHA SORTING (Disables OIT / Per-Pixel which crashes Apple
        // OpenGL 4.1)
        if (strstr(var->key, "alpha_sorting") != NULL) {
          var->value = "per-triangle";
          runner_log_printf(RETRO_LOG_INFO, "Flycast Override: %s = %s",
                            var->key, var->value);
          return true;
        }
      }
      // dolphin_libretro
      if (strcmp(var->key, "dolphin_gfx_backend") == 0) {
        var->value = "OGL";
        return true;
      }

      // These are known Dolphin core options that control buffer behavior
      if (strcmp(var->key, "dolphin_vertex_rounding") == 0) {
        var->value = "disabled";
        return true;
      }

      // Force basic uniform management in Dolphin
      if (strcmp(var->key, "dolphin_fastmem") == 0) {
        var->value = "enabled";
        return true;
      }

      // mupen64plus-next: force angrylion (software) RDP to avoid GL4.2+ DSA
      // requirement gliden64 requires glCreateTextures/glDispatchCompute etc.
      // (GL4.5) not available on macOS

      // CPU core: pure interpreter is safest on ARM64 macOS (no JIT
      // recompilation)
      // --- MUPEN64 FIXES (Existing) ---
      if (strcmp(var->key, "mupen64plus-next-cpucore") == 0 ||
          strcmp(var->key, "mupen64plus-cpucore") == 0) {
        var->value = "pure_interpreter";
        return true;
      }

      // Force software RDP — avoids all GL4.2+ DSA/compute shader calls
      if (strcmp(var->key, "mupen64plus-rdp-plugin") == 0 ||
          strcmp(var->key, "mupen64plus-next-rdp-plugin") == 0) {
        var->value = "angrylion";
        return true;
      }

      // Disable threaded renderer (can cause race conditions on macOS)
      if (strcmp(var->key, "mupen64plus-next-ThreadedRenderer") == 0 ||
          strcmp(var->key, "mupen64plus-next-parallel-rdp-synchronous") == 0) {
        var->value = "Disabled";
        return true;
      }

      if (strcmp(var->key, "mupen64plus-next-aspect") == 0) {
        var->value = "4:3";
        return true;
      }

      // ── MAME throttle/frame-limiting: enforce at the core level ──
      // These are queried by MAME cores to decide if they should throttle
      // execution
      if (strcmp(var->key, "mame2003-plus-throttle") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame2003-plus-skip_disclaimer") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame2003-plus-skip_warnings") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame2010-throttle") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame2010-skip_disclaimer") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame2010-skip_warnings") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame-throttle") == 0) {
        var->value = "enabled";
        return true;
      }
      if (strcmp(var->key, "mame2000-throttle") == 0) {
        var->value = "enabled";
        return true;
      }

      // ── Read from g_optValues (populated by SET_CORE_OPTIONS handlers) ──
      static __thread char g_varBuf[512];
      if (g_optValues && g_optValues.count > 0) {
        NSString *keyStr = [NSString stringWithUTF8String:var->key];
        NSString *valStr = g_optValues[keyStr];
        if (valStr && valStr.length > 0) {
          strncpy(g_varBuf, valStr.UTF8String, sizeof(g_varBuf) - 1);
          g_varBuf[sizeof(g_varBuf) - 1] = '\0';
          var->value = g_varBuf;
          return true;
        }
      }

      // Unknown variable: return false so the core uses its own internal
      // defaults. Returning true with empty string causes crashes (e.g.
      // picodrive_input: '').
      var->value = NULL;
    }
    return false;
  }
  case RETRO_ENVIRONMENT_SET_GEOMETRY:
    if (data && g_runner) {
      struct retro_game_geometry *geo = (struct retro_game_geometry *)data;
      g_runner->_avInfo.geometry = *geo;
      runner_log_printf(RETRO_LOG_DEBUG, "Core updated geometry: %ux%u",
                        geo->base_width, geo->base_height);
    }
    return true;
  case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
  case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
  case RETRO_ENVIRONMENT_SET_VARIABLES: // core tells us what options exist — we
                                        // acknowledge
  case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
  case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
  case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
  case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
  case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
  case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK: // 12
    return true;
  case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION: // 57
    if (data)
      *(unsigned *)data = 1;
    return true;
  case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER: // 56
    if (data)
      *(unsigned *)data =
          RETRO_HW_CONTEXT_OPENGL_CORE; // <-- Tell Dolphin to use modern GL
    return true;
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
    if (data)
      parseCoreOptionsV1((struct retro_core_options *)data);
    applyPersistedOverrides();
    return true;
  }
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
    struct retro_core_options_intl *intl =
        (struct retro_core_options_intl *)data;
    if (intl) {
      // Use US English (fallback), or local if available
      parseCoreOptionsV1(intl->us ? intl->us : intl->local);
    }
    applyPersistedOverrides();
    return true;
  }
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
    // Parse V2 options into g_optValues for core option persistence.
    if (data)
      parseCoreOptionsV2((struct retro_core_options_v2 *)data);
    applyPersistedOverrides();
    return true;
  }
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
    struct retro_core_options_v2_intl *intl =
        (struct retro_core_options_v2_intl *)data;
    if (intl) {
      parseCoreOptionsV2(intl->us ? intl->us : intl->local);
    }
    applyPersistedOverrides();
    return true;
  }
  case RETRO_ENVIRONMENT_GET_GAME_INFO_EXT:
    // We don't support extended game info — return false so core
    // falls back to the standard retro_game_info path.
    return false;
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
    return true;
  case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    return true;
  case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
    if (data && g_runner) {
      struct retro_system_av_info *info = (struct retro_system_av_info *)data;
      // Validate timing values to prevent corruption/zero FPS causing speedup
      double fps = info->timing.fps;
      double sampleRate = info->timing.sample_rate;

      // Sanity check: FPS should be between 10 and 120, sample rate between
      // 8000 and 192000
      if (fps > 10.0 && fps < 120.0) {
        g_runner->_avInfo.timing.fps = fps;
      } else if (fps > 0.0) {
        runner_log_printf(RETRO_LOG_WARN,
                          "Suspicious FPS value: %f, clamping to 60", fps);
        g_runner->_avInfo.timing.fps = 60.0;
      } else {
        runner_log_printf(RETRO_LOG_WARN,
                          "Invalid FPS value: %f, keeping current (was %f)",
                          fps, g_runner->_avInfo.timing.fps);
        // Keep existing FPS if it's valid, otherwise use 60
        if (g_runner->_avInfo.timing.fps <= 0.0) {
          g_runner->_avInfo.timing.fps = 60.0;
        }
      }

      if (sampleRate > 8000.0 && sampleRate < 192000.0) {
        g_runner->_avInfo.timing.sample_rate = sampleRate;
      } else if (sampleRate > 0.0) {
        runner_log_printf(RETRO_LOG_WARN,
                          "Suspicious sample rate: %f, keeping current",
                          sampleRate);
      } else {
        runner_log_printf(RETRO_LOG_WARN,
                          "Invalid sample rate: %f, keeping current",
                          sampleRate);
      }

      // Update geometry
      g_runner->_avInfo.geometry = info->geometry;

      runner_log_printf(RETRO_LOG_DEBUG,
                        "Core updated A/V info: FPS=%.2f SampleRate=%.1f",
                        g_runner->_avInfo.timing.fps,
                        g_runner->_avInfo.timing.sample_rate);
    }
    return true;
  case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: // has anything changed? → no,
                                              // vars are stable
    if (data)
      *(bool *)data = false;
    return true;
  case RETRO_ENVIRONMENT_SET_HW_RENDER: {
    struct retro_hw_render_callback *cb =
        (struct retro_hw_render_callback *)data;
    if (g_runner && cb) {
      
      return true;
    }
    return false;
  }
  case RETRO_ENVIRONMENT_GET_PERF_INTERFACE:
  case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE:
  case RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE:
  // Update case 58: RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE
  // Fixes Dreamcast issues
  case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE: {
    return false;
  }
  case RETRO_ENVIRONMENT_GET_LED_INTERFACE:
  case RETRO_ENVIRONMENT_GET_MIDI_INTERFACE:
  case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
    return false;
  case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
    if (data)
      *(int *)data = 3; // Enable both
    return true;
  default:
    if (cmd < 1000) { // Avoid logging internal/private values unless needed
      runner_log_printf(RETRO_LOG_ERROR, "Unhandled environment command: %u",
                        cmd);
    }
    return false;
  }
}






static void video_refresh_callback(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (!g_runner || !data) return;
    [g_runner handleVideoFrame:data width:width height:height pitch:pitch];
}

static void audio_sample_callback(int16_t left, int16_t right) {
    int16_t samples[2] = {left, right};
    [g_runner handleAudioSamples:samples count:2];
}

static size_t audio_sample_batch_callback(const int16_t *data, size_t frames) {
    [g_runner handleAudioSamples:data count:frames * 2];
    return frames;
}

static void input_poll_callback(void) {}

static int16_t input_state_callback(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port == 0 && device == RETRO_DEVICE_JOYPAD && g_runner) {
        return g_runner->_joypad_state[id & 0xF];
    }
    return 0;
}

#pragma mark - Implementation

- (void)bootCoreWithPath:(NSString *)dylibPath
                 romPath:(NSString *)romPath
                  coreID:(NSString *)coreID
                systemID:(NSString *)systemID
               shaderDir:(NSString *)shaderDir
             withReply:(void (^)(BOOL, NSDictionary *))reply {
    
    g_runner = self;
    _dlHandle = dlopen(dylibPath.UTF8String, RTLD_LAZY);
    if (!_dlHandle) {
        reply(NO, nil);
        return;
    }
    
    #define LOAD_SYM(name) _##name = (typeof(_##name))dlsym(_dlHandle, #name);
    LOAD_SYM(retro_init);
    LOAD_SYM(retro_deinit);
    LOAD_SYM(retro_run);
    LOAD_SYM(retro_get_system_info);
    LOAD_SYM(retro_get_system_av_info);
    LOAD_SYM(retro_set_environment);
    LOAD_SYM(retro_set_video_refresh);
    LOAD_SYM(retro_set_audio_sample);
    LOAD_SYM(retro_set_audio_sample_batch);
    LOAD_SYM(retro_set_input_poll);
    LOAD_SYM(retro_set_input_state);
    LOAD_SYM(retro_load_game);
    LOAD_SYM(retro_unload_game);
    LOAD_SYM(retro_serialize_size);
    LOAD_SYM(retro_serialize);
    LOAD_SYM(retro_unserialize);
    #undef LOAD_SYM
    
    _retro_set_environment(bridge_environment);
    _retro_init();
    
    _retro_set_video_refresh(video_refresh_callback);
    _retro_set_audio_sample(audio_sample_callback);
    _retro_set_audio_sample_batch(audio_sample_batch_callback);
    _retro_set_input_poll(input_poll_callback);
    _retro_set_input_state(input_state_callback);
    
    struct retro_game_info gi = { romPath.UTF8String, NULL, 0, NULL };
    // In a real implementation, we'd load the ROM into memory if needed, 
    // but many cores support path-based loading.
    
    if (!_retro_load_game(&gi)) {
        reply(NO, nil);
        return;
    }
    
    _retro_get_system_av_info(&_avInfo);
    _running = YES;
    
    // Start the emulation thread
    [NSThread detachNewThreadSelector:@selector(emulationLoop) toTarget:self withObject:nil];
    
    // Initialize audio buffer as guest
    _audioBuffer = [[SharedAudioBuffer alloc] initAsGuestWithName:@(AUDIO_SHM_NAME)];
    
    reply(YES, @{
        @"fps": @(_avInfo.timing.fps),
        @"width": @(_avInfo.geometry.base_width),
        @"height": @(_avInfo.geometry.base_height),
        @"aspect": @(_avInfo.geometry.aspect_ratio)
    });
}

- (void)emulationLoop {
    @autoreleasepool {
        while (_running) {
            if (!_paused) {
                _retro_run();
            } else {
                [NSThread sleepForTimeInterval:0.01];
            }
        }
    }
}

- (void)handleVideoFrame:(const void *)data width:(int)w height:(int)h pitch:(size_t)pitch {
    if (!_surface || _width != w || _height != h) {
        if (_surface) CFRelease(_surface);
        _surface = [SharedSurfaceManager createSurfaceWithWidth:w height:h];
        _width = w;
        _height = h;
    }
    
    [SharedSurfaceManager writeToSurface:_surface data:data pitch:pitch width:w height:h];
    
    // Notify host
    [(id<TruchiCoreHostProtocol>)_connection.remoteObjectProxy frameReadyWithSurface:(__bridge IOSurface *)_surface 
                                                                             width:w 
                                                                            height:h 
                                                                             pitch:(int)pitch 
                                                                            format:1 // Need to map format
                                                                          rotation:0];
}

- (void)handleAudioSamples:(const int16_t *)data count:(size_t)count {
    if (_audioBuffer) {
        [_audioBuffer writeSamples:data count:count];
    } else {
        // Fallback or early samples before connection
        NSData *samples = [NSData dataWithBytes:data length:count * sizeof(int16_t)];
        [((id<TruchiCoreHostProtocol>)_connection.remoteObjectProxy) audioSamplesReady:samples];
    }
}

- (void)setKeyState:(int)retroID pressed:(BOOL)pressed {
    if (retroID >= 0 && retroID < 16) {
        _joypad_state[retroID] = pressed ? 1 : 0;
    }
}

- (void)setAnalogStateWithIndex:(int)index id:(int)axisID value:(int)value {}
- (void)stopWithReply:(void (^)(void))reply { 
    _running = NO; 
    _retro_unload_game();
    _retro_deinit();
    reply(); 
}
- (void)serializeWithReply:(void (^)(NSData *))reply { 
    size_t size = _retro_serialize_size();
    void *buf = malloc(size);
    if (_retro_serialize(buf, size)) {
        reply([NSData dataWithBytesNoCopy:buf length:size freeWhenDone:YES]);
    } else {
        free(buf);
        reply(nil);
    }
}
- (void)unserialize:(NSData *)data withReply:(void (^)(BOOL))reply {
    reply(_retro_unserialize(data.bytes, data.length));
}
- (void)setPaused:(BOOL)paused { _paused = paused; }
- (void)setOptionValue:(NSString *)value forKey:(NSString *)key {}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSXPCListener *listener = [NSXPCListener serviceListener];
        CoreRunner *runner = [[CoreRunner alloc] init];
        listener.delegate = (id<NSXPCListenerDelegate>)runner;
        NSLog(@"[Runner] TruchiCoreRunner starting...");
        [listener resume];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}

#import "LibretroGlobals.h"
#import "CoreOverrideBridge.h"
#import "XPCSharedMemory.h"

CoreLoggerBlock g_swiftLoggerBlock = nil;
GameLoadedBlock g_gameLoadedCallback = nil;
unsigned g_currentSaveRAMType = 0;
LibretroBridgeImpl *g_instance = nil;
int g_selectedLanguage = 0; // RETRO_LANGUAGE_ENGLISH
int g_logLevel = 1;         // 1 = Warn & Error
NSString *g_coreID = nil;
NSString *g_systemID = nil;
NSString *g_romFilename = nil;
NSString *g_shaderDir = nil;
BOOL g_isPaused = NO;
BOOL g_variablesUpdated = NO;
unsigned g_genesisDeviceType = 0;
unsigned g_dosDeviceType = 0; // 0=auto (Generic Keyboard), else DOSBox-Pure device subclass
int g_wiiControllerType = 0; // 0=auto, 1=Wiimote, 513=Sideways, 1025=Wiimote+Classic
int g_currentRotation = 0; 
GLuint g_hwFBO = 0;

CoreCapabilities g_coreCapabilities = {0};

void updateCoreCapabilities(NSString *coreID) {
    NSString *lower = [coreID lowercaseString];
    g_coreCapabilities.isMame          = [lower containsString:@"mame"];
    g_coreCapabilities.isDOSBox        = [lower containsString:@"dosbox"];
    g_coreCapabilities.isDolphin       = [lower containsString:@"dolphin"];
    g_coreCapabilities.isSwanStation   = [lower containsString:@"swanstation"];
    g_coreCapabilities.isMednafenPSX   = [lower containsString:@"mednafen_psx"];
    g_coreCapabilities.isPCSX          = [lower containsString:@"pcsx"];
    g_coreCapabilities.isMupen64       = [lower containsString:@"mupen64"];
    g_coreCapabilities.isParallelN64   = [lower containsString:@"parallel_n64"];
    g_coreCapabilities.isGenesisPlusGX = [lower containsString:@"genesis_plus_gx"];
    g_coreCapabilities.isPicodrive     = [lower containsString:@"picodrive"];
    g_coreCapabilities.isFlycast       = [lower containsString:@"flycast"];
    g_coreCapabilities.isPSP           = [lower containsString:@"ppsspp"];
    g_coreCapabilities.isPS2Play       = [lower containsString:@"play_libretro"];
    g_coreCapabilities.is3DS           = [lower containsString:@"panda3ds"];
    g_coreCapabilities.isDuckStation   = [lower containsString:@"duckstation"];
}

NSMutableDictionary<NSString *, NSString *> *g_optValues = nil;
NSDictionary<NSString *, NSDictionary *> *g_optDefinitions = nil;
NSDictionary<NSString *, NSDictionary *> *g_optCategories = nil;
NSDictionary<NSString *, NSArray *> *g_inputDescriptors = nil;
BOOL g_loadingForOptions = NO;
BOOL g_instancePersisted = NO;

dispatch_semaphore_t g_bridgeCompletionSemaphore = nil;
CoreLogCallback g_coreLogCallback = NULL;

// Keyboard state (RETRO_DEVICE_KEYBOARD)
BOOL g_keyboard_state[512] = {NO};

// Mouse state (RETRO_DEVICE_MOUSE)
MouseState g_mouse_state = {0, 0, 0, 0};

// Pointer state (RETRO_DEVICE_POINTER)
int16_t g_pointer_x = 0;
int16_t g_pointer_y = 0;
BOOL g_pointer_pressed = NO;

#ifdef XPC_SERVICE
XPCSharedMemory *g_xpc_shm = NULL;
#endif

extern "C" void xpc_shm_set_global(XPCSharedMemory *shm) {
#ifdef XPC_SERVICE
    g_xpc_shm = shm;
#endif
}

static void no_op_log(const char *msg, int level) {}

LogFunc g_active_log_func = no_op_log;

void bridge_log_printf(enum retro_log_level level, const char *fmt, ...) {
  if (!fmt)
    return;
  va_list args;
  va_start(args, fmt);

  NSString *format = [[NSString alloc] initWithUTF8String:fmt];
  if (!format)
    format = [[NSString alloc] initWithCString:fmt encoding:NSASCIIStringEncoding];

  if (format) {
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    if (message) {
      if (g_swiftLoggerBlock) {
        g_swiftLoggerBlock(message.UTF8String, (int)level);
      }
    }
  }
  va_end(args);
}

void RegisterCoreLogCallback(CoreLogCallback callback) {
  g_coreLogCallback = callback;
}

// Converts a C string to an NSString, never returning nil and never throwing.
// `stringWithUTF8String:` returns nil (and historically can raise) on invalid
// UTF-8; callers must not insert nil into NSDictionary, so we normalize here.
static NSString *SafeCString(const char *cstr) {
    if (!cstr) return @"";
    NSString *s = [NSString stringWithUTF8String:cstr];
    return s ?: @"";
}

void initOptStorage(void) {
    if (!g_optValues) {
        g_optValues = [NSMutableDictionary dictionary];
    }
}

void parseCoreOptionsV2(struct retro_core_options_v2 *opts) {
  initOptStorage();
  [g_optValues removeAllObjects];

  NSMutableDictionary *defs = [NSMutableDictionary dictionary];
  NSMutableDictionary *cats = [NSMutableDictionary dictionary];

  if (opts && opts->categories) {
    struct retro_core_option_v2_category *cat = opts->categories;
    int catCount = 0;
    while (cat->key && catCount < 256) {
      NSString *key = SafeCString(cat->key);
      if (key.length > 0) {
        cats[key] = @{
          @"desc" : SafeCString(cat->desc),
          @"info" : SafeCString(cat->info)
        };
      }
      cat++;
      catCount++;
    }
  }
  g_optCategories =[cats copy];

  if (opts && opts->definitions) {
    struct retro_core_option_v2_definition *def = opts->definitions;
    int defCount = 0;
    while (def && def->key && defCount < 512) {
      NSString *key = SafeCString(def->key);
      // Skip entries with no usable key rather than inserting a degenerate key.
      if (key.length == 0) {
        def++;
        defCount++;
        continue;
      }

      NSString *desc = SafeCString(def->desc_categorized ?: def->desc);
      NSString *info = SafeCString(def->info_categorized ?: def->info);
      NSString *catKey = SafeCString(def->category_key);
      NSString *defaultVal = SafeCString(def->default_value);

      NSMutableArray *vals = [NSMutableArray array];
      for (int vi = 0; vi < RETRO_NUM_CORE_OPTION_VALUES_MAX; vi++) {
        const char *valStr = def->values[vi].value;
        if (!valStr) break;
        NSString *vval = SafeCString(valStr);
        NSString *vlabel = def->values[vi].label ? SafeCString(def->values[vi].label) : vval;
        [vals addObject:@{@"value" : vval, @"label" : vlabel}];
      }
      defs[key] = @{
        @"desc" : desc,
        @"info" : info,
        @"defaultValue" : defaultVal,
        @"category" : catKey,
        @"values" : [vals copy]
      };
      // `defaultVal` is always a non-nil NSString from SafeCString, so this
      // subscript assignment can never raise or store a dangling pointer.
      g_optValues[key] = defaultVal;
      def++;
      defCount++;
    }
  }
  g_optDefinitions = [defs copy];
}

void parseCoreOptionsV1(struct retro_core_options *opts) {
  initOptStorage();
  [g_optValues removeAllObjects];

  NSMutableDictionary *defs = [NSMutableDictionary dictionary];

  if (opts && opts->definitions) {
    struct retro_core_option_definition *def = opts->definitions;
    int defCount = 0;
    while (def && def->key && defCount < 512) {
      NSString *key = SafeCString(def->key);
      if (key.length == 0) {
        def++;
        defCount++;
        continue;
      }

      NSString *desc = SafeCString(def->desc);
      NSString *info = SafeCString(def->info);
      NSString *defaultVal = SafeCString(def->default_value);

      NSMutableArray *vals = [NSMutableArray array];
      for (int vi = 0; vi < RETRO_NUM_CORE_OPTION_VALUES_MAX; vi++) {
        const char *valStr = def->values[vi].value;
        if (!valStr) break;
        NSString *vval = SafeCString(valStr);
        NSString *vlabel = def->values[vi].label ? SafeCString(def->values[vi].label) : vval;
        [vals addObject:@{@"value" : vval, @"label" : vlabel}];
      }
      defs[key] = @{
        @"desc" : desc,
        @"info" : info,
        @"defaultValue" : defaultVal,
        @"category" : @"",
        @"values" : [vals copy]
      };
      g_optValues[key] = defaultVal;
      def++;
      defCount++;
    }
  }
  g_optCategories = @{};
  g_optDefinitions = [defs copy];
}

void parseInputDescriptors(const struct retro_input_descriptor *descriptors) {
  if (!descriptors) return;
  
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  const struct retro_input_descriptor *desc = descriptors;
  
  while (desc->port != 0 || desc->device != 0 || desc->index != 0 || desc->id != 0 || desc->description != NULL) {
    NSString *portKey = [NSString stringWithFormat:@"%u", desc->port];
    NSMutableArray *buttons = result[portKey];
    if (!buttons) {
      buttons = [NSMutableArray array];
      result[portKey] = buttons;
    }

    // Handle RETRO_DEVICE_JOYPAD (standard buttons)
    if (desc->device == RETRO_DEVICE_JOYPAD) {
      NSDictionary *buttonInfo = @{
        @"id" : @(desc->id),
        @"description" : desc->description ? [NSString stringWithUTF8String:desc->description] : @"",
        @"device" : @"joypad"
      };
      [buttons addObject:buttonInfo];
    }
    // Handle RETRO_DEVICE_ANALOG (analog sticks or digital buttons via ANALOG device)
    else if (desc->device == RETRO_DEVICE_ANALOG) {
      // True analog axes use index < 2 && id < 2
      if (desc->index < 2 && desc->id < 2) {
        // Map analog index/id to a unique ID range (16-23)
        // index 0 = left stick, index 1 = right stick
        // id 0 = X axis, id 1 = Y axis
        // We create two entries per axis: positive and negative direction
        unsigned int analogId = 16 + (desc->index * 4) + (desc->id * 2);

        // Positive direction (right/up)
        NSDictionary *posButtonInfo = @{
          @"id" : @(analogId),
          @"description" : desc->description ? [NSString stringWithUTF8String:desc->description] : @"",
          @"device" : @"analog",
          @"index" : @(desc->index),
          @"axis" : @(desc->id),
          @"direction" : @"positive"
        };
        [buttons addObject:posButtonInfo];

        // Negative direction (left/down)
        NSDictionary *negButtonInfo = @{
          @"id" : @(analogId + 1),
          @"description" : @"",
          @"device" : @"analog",
          @"index" : @(desc->index),
          @"axis" : @(desc->id),
          @"direction" : @"negative"
        };
        [buttons addObject:negButtonInfo];
      } else {
        // Digital buttons queried through ANALOG device type (Mupen64Plus-Next, etc.)
        // Store as JOYPAD descriptors using original IDs so convertToRetroButtons maps correctly
        NSDictionary *buttonInfo = @{
          @"id" : @(desc->id),
          @"description" : desc->description ? [NSString stringWithUTF8String:desc->description] : @"",
          @"device" : @"joypad"
        };
        [buttons addObject:buttonInfo];
      }
    }
    desc++;
  }
  
  g_inputDescriptors = [result copy];
  bridge_log_printf(RETRO_LOG_INFO, "Parsed %lu input descriptors", (unsigned long)result.count);
}

static void loadBundledOverrideJSON(const char* coreID, const char* scopeName) {
    if (!coreID || !scopeName) return;
    NSString *coreStr = [NSString stringWithUTF8String:coreID];
    NSString *scopeStr = [NSString stringWithUTF8String:scopeName];

    NSString *fileName = [NSString stringWithFormat:@"%@_%@", coreStr, scopeStr];

    // Look in Application Support CoreOverrides directory (works for both in-process and XPC),
    // then fall back to main bundle (in-process only).
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *coreOverrideDir = [appSupport stringByAppendingPathComponent:@"TruchiEmu/CoreOverrides"];
    NSString *coreDir = [coreOverrideDir stringByAppendingPathComponent:coreStr];
    NSString *filePath = [coreDir stringByAppendingPathComponent:[scopeStr stringByAppendingPathExtension:@"json"]];

    NSData *data = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        data = [NSData dataWithContentsOfFile:filePath];
    }
    if (!data) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:fileName withExtension:@"json" subdirectory:@"CoreOverrides"];
        if (!url) {
            url = [[NSBundle mainBundle] URLForResource:fileName withExtension:@"json"];
        }
        if (url) data = [NSData dataWithContentsOfURL:url];
    }
    if (!data) return;

    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json || ![json isKindOfClass:[NSDictionary class]]) return;

    for (NSString *key in json) {
        NSString *value = json[key];
        if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) continue;
        NSString *valueStr = [value isKindOfClass:[NSString class]] ? value : [value description];
            if (g_optValues && key.length > 0 && valueStr.length > 0) {
                g_optValues[key] = valueStr;
                bridge_log_printf(RETRO_LOG_DEBUG, "[Override-Bundled-JSON] %s/%s: %s = %s", coreID, scopeName, key.UTF8String, valueStr.UTF8String);
            }
    }
}

static void loadUserOverrideCFG(const char* coreID, const char* systemID, const char* gameFilename) {
    if (!coreID || !systemID) return;
    NSString *coreStr = [NSString stringWithUTF8String:coreID];
    NSString *systemStr = [NSString stringWithUTF8String:systemID];

    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *baseDir = [appSupport stringByAppendingPathComponent:@"TruchiEmu/CoreOverrides"];
    NSString *coreDir = [baseDir stringByAppendingPathComponent:coreStr];
    NSString *systemDir = [coreDir stringByAppendingPathComponent:systemStr];

    NSString *configPath;
    NSString *logScope;

    if (gameFilename && strlen(gameFilename) > 0) {
        NSString *gameStr = [NSString stringWithUTF8String:gameFilename];
        configPath = [systemDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.cfg", gameStr]];
        logScope = [[NSString stringWithFormat:@"%s/%s/%s", coreID, systemID, gameFilename] copy];
    } else {
        configPath = [systemDir stringByAppendingPathComponent:@"overrides.cfg"];
        logScope = [[NSString stringWithFormat:@"%s/%s", coreID, systemID] copy];
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) return;

    NSString *fileContent = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
    if (!fileContent) return;

    NSArray<NSString *> *allLines = [fileContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in allLines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;

        NSRange eqRange = [trimmed rangeOfString:@"="];
        if (eqRange.location == NSNotFound) continue;

        NSString *key = [[trimmed substringToIndex:eqRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *val = [[trimmed substringFromIndex:NSMaxRange(eqRange)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        if ([val hasPrefix:@"\""] && [val hasSuffix:@"\""]) {
            val = [val substringWithRange:NSMakeRange(1, val.length - 2)];
        }
        if (g_optValues && key.length > 0) {
            g_optValues[key] = val;
            bridge_log_printf(RETRO_LOG_DEBUG, "[Override-User-CFG] %s: %s = %s", logScope.UTF8String, key.UTF8String, val.UTF8String);
        }
    }
}

void applyPersistedOverrides(void) {
    if (!g_coreID) return;

    // Layer 1: Bundled default.json (core defaults, applies to all systems)
    loadBundledOverrideJSON(g_coreID.UTF8String, "default");

    // Layer 2: Bundled <systemID>.json (system-specific defaults)
    if (g_systemID && g_systemID.length > 0) {
        loadBundledOverrideJSON(g_coreID.UTF8String, g_systemID.UTF8String);
    }

    // Layer 3: User system-level .cfg (CoreOverrides/<coreID>/<systemID>.cfg)
    if (g_systemID && g_systemID.length > 0) {
        loadUserOverrideCFG(g_coreID.UTF8String, g_systemID.UTF8String, NULL);
    }

    // Layer 4: User game-level .cfg (CoreOverrides/<coreID>/<systemID>/<game>.cfg)
    if (g_systemID && g_systemID.length > 0 && g_romFilename && g_romFilename.length > 0) {
        loadUserOverrideCFG(g_coreID.UTF8String, g_systemID.UTF8String, g_romFilename.UTF8String);
    }
}

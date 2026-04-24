#import "LibretroGlobals.h"

CoreLoggerBlock g_swiftLoggerBlock = nil;
LibretroBridgeImpl *g_instance = nil;
int g_selectedLanguage = 0; // RETRO_LANGUAGE_ENGLISH
int g_logLevel = 1;         // 1 = Warn & Error
NSString *g_coreID = nil;   
NSString *g_shaderDir = nil;                          
BOOL g_isPaused = NO;      
int g_currentRotation = 0; 
GLuint g_hwFBO = 0;

NSMutableDictionary<NSString *, NSString *> *g_optValues = nil;
NSDictionary<NSString *, NSDictionary *> *g_optDefinitions = nil;
NSDictionary<NSString *, NSDictionary *> *g_optCategories = nil;

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

static void no_op_log(const char *msg, int level) {}

static void swift_logger_wrapper(const char *msg, int level) {
  if (g_swiftLoggerBlock) {
    g_swiftLoggerBlock(msg, level);
  }
}

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
      @try {
        cats[[NSString stringWithUTF8String:cat->key]] = @{
          @"desc" : cat->desc ? [NSString stringWithUTF8String:cat->desc] : @"",
          @"info" : cat->info ? [NSString stringWithUTF8String:cat->info] : @""
        };
      } @catch (NSException *exception) {
        bridge_log_printf(RETRO_LOG_WARN, " Failed to parse category: %s", exception.reason);
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
      @try {
        NSString *key =[NSString stringWithUTF8String:def->key];
        NSString *desc =[NSString stringWithUTF8String:(def->desc_categorized ?: def->desc)];
        NSString *info =[NSString stringWithUTF8String:(def->info_categorized ?: def->info)];
        NSString *catKey = def->category_key ?[NSString stringWithUTF8String:def->category_key] : nil;
        NSString *defaultVal = def->default_value ? [NSString stringWithUTF8String:def->default_value] : @"";

        NSMutableArray *vals = [NSMutableArray array];
        for (int vi = 0; vi < RETRO_NUM_CORE_OPTION_VALUES_MAX; vi++) {
          const char *valStr = def->values[vi].value;
          if (!valStr) break;
          @try {
            NSString *vval =[NSString stringWithUTF8String:valStr];
            NSString *vlabel = def->values[vi].label ? [NSString stringWithUTF8String:def->values[vi].label] : vval;[vals addObject:@{@"value" : vval, @"label" : vlabel}];
          } @catch (NSException *exception) {
            bridge_log_printf(RETRO_LOG_ERROR, "Failed to parse option value: %s", exception.reason);
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
        g_optValues[key] = defaultVal;
      } @catch (NSException *exception) {
        bridge_log_printf(RETRO_LOG_ERROR, "Failed to parse option definition: %s", exception.reason);
      }
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
      @try {
        NSString *key =[NSString stringWithUTF8String:def->key];
        NSString *desc = def->desc ? [NSString stringWithUTF8String:def->desc] : @"";
        NSString *info = def->info ? [NSString stringWithUTF8String:def->info] : @"";
        NSString *defaultVal = def->default_value ?[NSString stringWithUTF8String:def->default_value] : @"";

        NSMutableArray *vals = [NSMutableArray array];
        for (int vi = 0; vi < RETRO_NUM_CORE_OPTION_VALUES_MAX; vi++) {
          const char *valStr = def->values[vi].value;
          if (!valStr) break;
          @try {
            NSString *vval = [NSString stringWithUTF8String:valStr];
            NSString *vlabel = def->values[vi].label ? [NSString stringWithUTF8String:def->values[vi].label] : vval;[vals addObject:@{@"value" : vval, @"label" : vlabel}];
          } @catch (NSException *exception) {
            bridge_log_printf(RETRO_LOG_ERROR, "Failed to parse option value: %s", exception.reason);
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
        bridge_log_printf(RETRO_LOG_ERROR, "Failed to parse option definition: %s", exception.reason);
      }
      def++;
      defCount++;
    }
  }
  g_optCategories = @{};
  g_optDefinitions = [defs copy];
}

void applyPersistedOverrides(void) {
  if (!g_coreID) return;

  NSString *configName =[NSString stringWithFormat:@"%@.cfg", g_coreID];
  NSString *appSupport =[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString *optionsDir =[appSupport stringByAppendingPathComponent:@"TruchieEmu/CoreOptions"];
  NSString *configPath =[optionsDir stringByAppendingPathComponent:configName];

  if (![[NSFileManager defaultManager] fileExistsAtPath:configPath]) return;

  NSString *fileContent =[NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
  if (!fileContent) return;

  NSArray<NSString *> *allLines =[fileContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

  for (NSString *line in allLines) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;

    NSRange eqRange = [trimmed rangeOfString:@"="];
    if (eqRange.location == NSNotFound) continue;

    NSString *key = [[trimmed substringToIndex:eqRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *val = [[trimmed substringFromIndex:NSMaxRange(eqRange)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if ([val hasPrefix:@"\""] && [val hasSuffix:@"\""]) {
      val =[val substringWithRange:NSMakeRange(1, val.length - 2)];
    }
    if (g_optValues && key.length > 0) {
      g_optValues[key] = val;
      bridge_log_printf(RETRO_LOG_INFO, "Override from .cfg: %s = %s", key.UTF8String, val.UTF8String);
    }
  }
}
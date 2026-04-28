#import "LibretroCallbacks.h"
#import "LibretroGlobals.h"
#import "LibretroBridgeImpl.h"
#import "SaveDirectoryBridge.h"
#import "CoreOverrideBridge.h"
#import <dlfcn.h>

int16_t g_input_state[32] = {0};
int16_t g_analog_state[2][2] = {0};
BOOL g_turbo_state[32] = {NO};
int g_turbo_counter[32] = {0};
BOOL g_turbo_active[32] = {NO};
const int g_turbo_rate = 6;
int g_turbo_fireButton[32] = {0};

// Keyboard callback storage (set by RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK)
struct retro_keyboard_callback g_keyboard_callback = {NULL};
BOOL g_keyboard_callback_registered = NO;

uintptr_t bridge_get_proc_address(const char *sym) {
  if (!sym) return 0;
  static void *glHandle = NULL;
  if (!glHandle)
    glHandle = dlopen("/System/Library/Frameworks/OpenGL.framework/Versions/Current/OpenGL", RTLD_LAZY);
  uintptr_t res = (uintptr_t)dlsym(glHandle ? glHandle : RTLD_DEFAULT, sym);
  if (!res && sym[0] != '_') {
    char buf[256];
    snprintf(buf, sizeof(buf), "_%s", sym);
    res = (uintptr_t)dlsym(glHandle ? glHandle : RTLD_DEFAULT, buf);
  }
  return res;
}

uintptr_t bridge_get_current_framebuffer(void) {
  return (uintptr_t)g_hwFBO;
}

bool bridge_environment(unsigned cmd, void *data) {
  if (!g_instance) return false;

  switch (cmd) {
  case RETRO_ENVIRONMENT_SET_ROTATION:
    if (data) g_currentRotation = *(const unsigned *)data;
    return true;

  case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
    if (data) ((struct retro_log_interface *)data)->log = bridge_log_printf;
    return true;

  case RETRO_ENVIRONMENT_GET_CAN_DUPE:
    if (data) *(unsigned char *)data = 1;
    return true;

  case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
    static char s_sysPath[1024];
    // Use dynamic path from SaveDirectoryManager
    NSString *path = [SaveDirectoryBridge libretroSystemDirectoryPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    strncpy(s_sysPath, path.UTF8String, sizeof(s_sysPath) - 1);
    if (data) *(const char **)data = s_sysPath;
    return true;
  }
  case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
    static char s_savePath[1024];
    // Use dynamic path from SaveDirectoryManager
    NSString *path = [SaveDirectoryBridge libretroSaveDirectoryPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    strncpy(s_savePath, path.UTF8String, sizeof(s_savePath) - 1);
    if (data) *(const char **)data = s_savePath;
    return true;
  }

  case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
    if (data) {
      enum retro_pixel_format fmt = *(enum retro_pixel_format *)data;
      if (g_instance) {[g_instance setPixelFormat:(int)fmt];
      }
    }
    return true;

  case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
    if (data) *(unsigned *)data = 2;
    return true;

  case RETRO_ENVIRONMENT_GET_LANGUAGE:
    if (data) *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
    return true;

  case RETRO_ENVIRONMENT_GET_VARIABLE: {
    struct retro_variable *var = (struct retro_variable *)data;
    if (var && var->key) {

    // Apply core-specific overrides from CoreOverrideService
    if (var && var->key && g_coreID) {
        // --- HARDCODED SANITY OVERRIDES (Diagnostic Fallback) ---
        // These ensure N64 works even if CoreOverrides.json fails to load
        if (strcmp(var->key, "mupen64plus-next-cpucore") == 0 || strcmp(var->key, "mupen64plus-cpucore") == 0) {
            var->value = "pure_interpreter";
            return true;
        }
        if (strcmp(var->key, "mupen64plus-rdp-plugin") == 0 || strcmp(var->key, "mupen64plus-next-rdp-plugin") == 0) {
            var->value = "angrylion";
            return true;
        }
        if (strcmp(var->key, "mupen64plus-next-ThreadedRenderer") == 0) {
            var->value = "Disabled";
            return true;
        }

        const char* overrideValue = core_override_get_value([((NSString *)g_coreID) UTF8String], var->key);
        if (overrideValue) {
            static __thread char g_overrideBuf[512];
            strncpy(g_overrideBuf, overrideValue, sizeof(g_overrideBuf) - 1);
            g_overrideBuf[sizeof(g_overrideBuf) - 1] = '\0';
            var->value = g_overrideBuf;
            bridge_log_printf(RETRO_LOG_INFO, "Override: %s = %s", var->key, var->value);
            return true;
        }
    }
    
    // Apply registered option values from Swift layer
    static __thread char g_varBuf[512];
    if (g_optValues && g_optValues.count > 0) {
        NSString *keyStr =[NSString stringWithUTF8String:var->key];
        NSString *valStr = g_optValues[keyStr];
        if (valStr && valStr.length > 0) {
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
    }
    return true;
case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
case RETRO_ENVIRONMENT_SET_VARIABLES:
case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO: {
    return true;
}
case RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK: {
    struct retro_keyboard_callback *cb = (struct retro_keyboard_callback *)data;
    if (cb) {
        // Store the keyboard callback for event-based keyboard input
        // The callback will be invoked via bridge_keyboard_event()
        g_keyboard_callback = *cb;
        g_keyboard_callback_registered = YES;
        bridge_log_printf(RETRO_LOG_DEBUG, "Keyboard callback registered");
    }
    return true;
}
  case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
    if (data) *(unsigned *)data = 1;
    return true;
  case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER: {
    // If the core is already hardware-aware, let it decide. 
    // Otherwise, suggest Core Profile for modern macOS support.
    if (data) {
        if (g_instance && g_instance->_hwRenderEnabled) {
            *(unsigned *)data = g_instance->_hw_callback.context_type;
        } else {
            *(unsigned *)data = RETRO_HW_CONTEXT_OPENGL_CORE;
        }
    }
    return true;
  }
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
    if (data) parseCoreOptionsV1((struct retro_core_options *)data);
    applyPersistedOverrides();
    return true;
  }
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
    struct retro_core_options_intl *intl = (struct retro_core_options_intl *)data;
    if (intl) parseCoreOptionsV1(intl->us ? intl->us : intl->local);
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
    if (intl) parseCoreOptionsV2(intl->us ? intl->us : intl->local);
    applyPersistedOverrides();
    return true;
  }
  case RETRO_ENVIRONMENT_GET_GAME_INFO_EXT:
    return false;
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
  case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
    return true;
  case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    return true;
  case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
    if (data && g_instance) {
      struct retro_system_av_info *info = (struct retro_system_av_info *)data;
      double fps = info->timing.fps;
      double sampleRate = info->timing.sample_rate;

      if (fps > 10.0 && fps < 120.0) {
        g_instance->_avInfo.timing.fps = fps;
      } else if (fps > 0.0) {
        g_instance->_avInfo.timing.fps = 60.0;
      } else {
        if (g_instance->_avInfo.timing.fps <= 0.0) g_instance->_avInfo.timing.fps = 60.0;
      }

      if (sampleRate > 8000.0 && sampleRate < 192000.0) {
        g_instance->_avInfo.timing.sample_rate = sampleRate;
      }
      g_instance->_avInfo.geometry = info->geometry;
    }
    return true;
  case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
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
  case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE:
  case RETRO_ENVIRONMENT_GET_LED_INTERFACE:
  case RETRO_ENVIRONMENT_GET_MIDI_INTERFACE:
  case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE: {
      // This is used by some cores (like Mupen64Plus-Next) to negotiate context versions
      return true; 
  }
  case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
    return false;
  case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
    if (data) *(int *)data = 3;
    return true;
  default:
    return false;
  }
}

void bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
  if (g_instance) {
    if (g_instance->_hwRenderEnabled && g_instance->_glContext)
      CGLSetCurrentContext(g_instance->_glContext);
    const void *finalData = data;
    int format = [g_instance pixelFormat];
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
      finalData =[g_instance readHWRenderedPixels:width height:height];
      pitch = width * 4;
      format = RETRO_PIXEL_FORMAT_XRGB8888;
    }[g_instance handleVideoData:finalData width:width height:height pitch:(int)pitch format:format];
  }
}

void bridge_audio_sample(int16_t left, int16_t right) {
  int16_t samples[2] = {left, right};
  if (g_instance) [g_instance handleAudioSamples:samples count:2];
}

size_t bridge_audio_sample_batch(const int16_t *data, size_t frames) {
  if (g_instance) [g_instance handleAudioSamples:data count:frames * 2];
  return frames;
}

static void bridge_handle_turbo(void) {
  for (int i = 0; i < 32; i++) {
    if (g_turbo_active[i]) {
      if (g_turbo_counter[i] <= 0) {
        g_turbo_counter[i] = g_turbo_rate;
        g_turbo_state[i] = !g_turbo_state[i];
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

void bridge_input_poll(void) {
  bridge_handle_turbo();
}

int16_t bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port == 0) {
        if (device == RETRO_DEVICE_JOYPAD)
            return g_input_state[id & 0x1F] ? 1 : 0;
        if (device == RETRO_DEVICE_ANALOG && index < 2 && id < 2)
            return g_analog_state[index][id];

        // RETRO_DEVICE_KEYBOARD - raw keycode polling
        if (device == RETRO_DEVICE_KEYBOARD || device == 0) {
            if (id < 512) {
                return g_keyboard_state[id] ? 1 : 0;
            }
            return 0;
        }

        // RETRO_DEVICE_MOUSE - relative mouse movement + buttons
        if (device == RETRO_DEVICE_MOUSE) {
            switch (id) {
                case RETRO_DEVICE_ID_MOUSE_X:
                    return g_mouse_state.delta_x;
                case RETRO_DEVICE_ID_MOUSE_Y:
                    return g_mouse_state.delta_y;
                case RETRO_DEVICE_ID_MOUSE_LEFT:
                    return (g_mouse_state.buttons & 1) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_RIGHT:
                    return (g_mouse_state.buttons & 2) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_MIDDLE:
                    return (g_mouse_state.buttons & 4) ? 1 : 0;
                case RETRO_DEVICE_ID_MOUSE_WHEELUP: {
                    int16_t w = g_mouse_state.wheel_delta;
                    g_mouse_state.wheel_delta = 0;
                    return (w > 0) ? 1 : 0;
                }
                case RETRO_DEVICE_ID_MOUSE_WHEELDOWN: {
                    int16_t w = g_mouse_state.wheel_delta;
                    g_mouse_state.wheel_delta = 0;
                    return (w < 0) ? 1 : 0;
                }
                default:
                    return 0;
            }
        }

        // RETRO_DEVICE_POINTER - absolute pointer position
        if (device == RETRO_DEVICE_POINTER) {
            switch (id) {
                case RETRO_DEVICE_ID_POINTER_X:
                    return g_pointer_x;
                case RETRO_DEVICE_ID_POINTER_Y:
                    return g_pointer_y;
                case RETRO_DEVICE_ID_POINTER_PRESSED:
                    return g_pointer_pressed ? 1 : 0;
                default:
                    return 0;
            }
        }
    }
    return 0;
}

// Called from Swift to dispatch keyboard events to the core
// This invokes the callback-based keyboard input if registered
// and also updates the polling state for cores that use bridge_input_state
void bridge_keyboard_event(bool down, unsigned keycode, uint32_t character, uint32_t mod, unsigned device) {
    if (g_keyboard_callback_registered && g_keyboard_callback.callback) {
        g_keyboard_callback.callback(down, keycode, character, mod, device);
    }
    if (keycode < 512) {
        g_keyboard_state[keycode] = down ? YES : NO;
    }
}

void bridge_reset_keyboard_callback(void) {
    g_keyboard_callback_registered = NO;
    g_keyboard_callback.callback = NULL;
}

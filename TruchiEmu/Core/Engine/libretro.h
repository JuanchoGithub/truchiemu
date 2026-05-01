#pragma once
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RETRO_API_VERSION 1

/* Experimental/private flags for environment commands */
#define RETRO_ENVIRONMENT_EXPERIMENTAL 0x10000
#define RETRO_ENVIRONMENT_PRIVATE 0x20000

#define RETRO_ENVIRONMENT_SET_ROTATION 1
#define RETRO_ENVIRONMENT_GET_CAN_DUPE 3
#define RETRO_ENVIRONMENT_SET_MESSAGE 6
#define RETRO_ENVIRONMENT_SHUTDOWN 7
#define RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL 8
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY 9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 10
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS 11
#define RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK 12
#define RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE 13
#define RETRO_ENVIRONMENT_SET_HW_RENDER 14
#define RETRO_ENVIRONMENT_GET_VARIABLE 15
#define RETRO_ENVIRONMENT_SET_VARIABLES 16
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE 17
#define RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME 18
#define RETRO_ENVIRONMENT_GET_LIBRETRO_PATH 19
#define RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK 21
#define RETRO_ENVIRONMENT_SET_AUDIO_CALLBACK 22
#define RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE 23
#define RETRO_ENVIRONMENT_GET_INPUT_DEVICE_CAPABILITIES 24
#define RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE                                 \
  (25 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 27
#define RETRO_ENVIRONMENT_GET_PERF_INTERFACE 28
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY 31
#define RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO 32
#define RETRO_ENVIRONMENT_SET_PROC_ADDRESS_CALLBACK 33
#define RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO 34
#define RETRO_ENVIRONMENT_SET_CONTROLLER_INFO 35
#define RETRO_ENVIRONMENT_SET_MEMORY_MAPS (36 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_SET_GEOMETRY 37
#define RETRO_ENVIRONMENT_GET_USERNAME 38
#define RETRO_ENVIRONMENT_GET_LANGUAGE 39
#define RETRO_ENVIRONMENT_GET_CURRENT_SOFTWARE_FRAMEBUFFER                     \
  (40 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE                              \
  (41 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS                             \
  (42 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE          \
  (43 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS 44
#define RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT                                \
  (44 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_VFS_INTERFACE                                    \
  (45 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_LED_INTERFACE                                    \
  (46 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE                               \
  (47 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_MIDI_INTERFACE                                   \
  (48 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_FASTFORWARDING                                   \
  (49 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_TARGET_REFRESH_RATE                              \
  (50 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_INPUT_BITMASKS                                   \
  (51 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION 52

/* Core options V1 */
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS 53
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL 54
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY 55
#define RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER 56
#define RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION 57
#define RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE 58
#define RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION 59
#define RETRO_ENVIRONMENT_SET_MESSAGE_EXT 60
#define RETRO_ENVIRONMENT_GET_INPUT_MAX_USERS 61
#define RETRO_ENVIRONMENT_SET_AUDIO_BUFFER_STATUS_CALLBACK 62
#define RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY 63
#define RETRO_ENVIRONMENT_SET_FASTFORWARDING_OVERRIDE 64
#define RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE 65
#define RETRO_ENVIRONMENT_GET_GAME_INFO_EXT 66

/* Core options V2 — the modern standard */
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 67
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL 68
#define RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK 69
#define RETRO_ENVIRONMENT_SET_VARIABLE 70
#define RETRO_ENVIRONMENT_GET_THROTTLE_STATE                                   \
  (71 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_SAVESTATE_CONTEXT                                \
  (72 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_GET_JIT_CAPABLE 74
#define RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE                             \
  (75 | RETRO_ENVIRONMENT_EXPERIMENTAL)
#define RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE 78
#define RETRO_ENVIRONMENT_GET_PLAYLIST_DIRECTORY 79

#define RETRO_DEVICE_NONE 0
#define RETRO_DEVICE_JOYPAD 1
#define RETRO_DEVICE_MOUSE 2
#define RETRO_DEVICE_KEYBOARD 3
#define RETRO_DEVICE_LIGHTGUN 4
#define RETRO_DEVICE_ANALOG 5
#define RETRO_DEVICE_POINTER 6

/* Memory constants */
#define RETRO_MEMORY_SYSTEM_RAM 0
#define RETRO_MEMORY_SAVE_RAM 1

#define RETRO_DEVICE_ID_JOYPAD_B 0
#define RETRO_DEVICE_ID_JOYPAD_Y 1
#define RETRO_DEVICE_ID_JOYPAD_SELECT 2
#define RETRO_DEVICE_ID_JOYPAD_START 3
#define RETRO_DEVICE_ID_JOYPAD_UP 4
#define RETRO_DEVICE_ID_JOYPAD_DOWN 5
#define RETRO_DEVICE_ID_JOYPAD_LEFT 6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT 7
#define RETRO_DEVICE_ID_JOYPAD_A 8
#define RETRO_DEVICE_ID_JOYPAD_X 9
#define RETRO_DEVICE_ID_JOYPAD_L 10
#define RETRO_DEVICE_ID_JOYPAD_R 11
#define RETRO_DEVICE_ID_JOYPAD_L2 12
#define RETRO_DEVICE_ID_JOYPAD_R2 13
#define RETRO_DEVICE_ID_JOYPAD_L3 14
#define RETRO_DEVICE_ID_JOYPAD_R3 15

#define RETRO_DEVICE_ID_MOUSE_X 0
#define RETRO_DEVICE_ID_MOUSE_Y 1
#define RETRO_DEVICE_ID_MOUSE_LEFT 2
#define RETRO_DEVICE_ID_MOUSE_RIGHT 3
#define RETRO_DEVICE_ID_MOUSE_WHEELUP 4
#define RETRO_DEVICE_ID_MOUSE_WHEELDOWN 5
#define RETRO_DEVICE_ID_MOUSE_MIDDLE 6

#define RETRO_DEVICE_ID_POINTER_X 0
#define RETRO_DEVICE_ID_POINTER_Y 1
#define RETRO_DEVICE_ID_POINTER_PRESSED 2

#define RETRO_DEVICE_INDEX_ANALOG_LEFT 0
#define RETRO_DEVICE_INDEX_ANALOG_RIGHT 1
#define RETRO_DEVICE_ID_ANALOG_X 0
#define RETRO_DEVICE_ID_ANALOG_Y 1

struct retro_variable {
  const char *key;
  const char *value;
};

struct retro_game_geometry {
  unsigned base_width;
  unsigned base_height;
  unsigned max_width;
  unsigned max_height;
  float aspect_ratio;
};

enum retro_language {
  RETRO_LANGUAGE_ENGLISH = 0,
  RETRO_LANGUAGE_JAPANESE = 1,
  RETRO_LANGUAGE_FRENCH = 2,
  RETRO_LANGUAGE_GERMAN = 3,
  RETRO_LANGUAGE_SPANISH = 4,
  RETRO_LANGUAGE_ITALIAN = 5,
  RETRO_LANGUAGE_DUTCH = 6,
  RETRO_LANGUAGE_PORTUGUESE = 7,
  RETRO_LANGUAGE_RUSSIAN = 8,
  RETRO_LANGUAGE_KOREAN = 9,
  RETRO_LANGUAGE_CHINESE_TRADITIONAL = 10,
  RETRO_LANGUAGE_CHINESE_SIMPLIFIED = 11,
  RETRO_LANGUAGE_ESPERANTO = 12,
  RETRO_LANGUAGE_POLISH = 13,
  RETRO_LANGUAGE_VIETNAMESE = 14,
  RETRO_LANGUAGE_ARABIC = 15,
  RETRO_LANGUAGE_GREEK = 16,
  RETRO_LANGUAGE_TURKISH = 17,
  RETRO_LANGUAGE_BRITISH_ENGLISH = 28
};

enum retro_pixel_format {
  RETRO_PIXEL_FORMAT_0RGB1555 = 0,
  RETRO_PIXEL_FORMAT_XRGB8888 = 1,
  RETRO_PIXEL_FORMAT_RGB565 = 2,
  RETRO_PIXEL_FORMAT_UNKNOWN = 0xffffffff
};

typedef bool (*retro_environment_t)(unsigned cmd, void *data);
typedef void (*retro_video_refresh_t)(const void *data, unsigned width,
                                      unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data,
                                             size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device,
unsigned index, unsigned id);

struct retro_keyboard_callback {
   void (*callback)(bool down, unsigned keycode, uint32_t character,
                    uint16_t mod, unsigned device);
};

struct retro_system_info {
  const char *library_name;
  const char *library_version;
  const char *valid_extensions;
  bool need_fullpath;
  bool block_extract;
};

struct retro_game_info {
  const char *path;
  const void *data;
  size_t size;
  const char *meta;
};

enum retro_log_level {
  RETRO_LOG_DEBUG = 0,
  RETRO_LOG_INFO,
  RETRO_LOG_WARN,
  RETRO_LOG_ERROR,
  RETRO_LOG_DUMMY = 255
};

typedef void (*retro_log_printf_t)(enum retro_log_level level, const char *fmt,
                                   ...);

struct retro_log_interface {
  retro_log_printf_t log;
};

struct retro_system_av_info {
  struct retro_game_geometry geometry;
  struct {
    double fps, sample_rate;
  } timing;
};

typedef void (*fn_retro_set_controller_port_device)(unsigned port,
                                                    unsigned device);
typedef void (*fn_retro_init)(void);
typedef void (*fn_retro_deinit)(void);
typedef unsigned (*fn_retro_api_version)(void);
typedef void (*fn_retro_set_environment)(retro_environment_t);
typedef void (*fn_retro_set_video_refresh)(retro_video_refresh_t);
typedef void (*fn_retro_set_audio_sample)(retro_audio_sample_t);
typedef void (*fn_retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
typedef void (*fn_retro_set_input_poll)(retro_input_poll_t);
typedef void (*fn_retro_set_input_state)(retro_input_state_t);
typedef bool (*fn_retro_load_game)(const struct retro_game_info *game);
typedef void (*fn_retro_unload_game)(void);
typedef void (*fn_retro_run)(void);
typedef void (*fn_retro_get_system_info)(struct retro_system_info *info);
typedef void (*fn_retro_get_system_av_info)(struct retro_system_av_info *info);
typedef size_t (*fn_retro_serialize_size)(void);
typedef bool (*fn_retro_serialize)(void *data, size_t size);
typedef bool (*fn_retro_unserialize)(const void *data, size_t size);
typedef void (*fn_retro_cheat_set)(unsigned index, bool enabled,
                                   const char *code);
typedef void (*fn_retro_cheat_reset)(void);
typedef void *(*fn_retro_get_memory_data)(unsigned id);
typedef size_t (*fn_retro_get_memory_size)(unsigned id);

enum retro_hw_context_type {
  RETRO_HW_CONTEXT_NONE = 0,
  RETRO_HW_CONTEXT_OPENGL = 1,
  RETRO_HW_CONTEXT_OPENGLES2 = 2,
  RETRO_HW_CONTEXT_OPENGL_CORE = 3,
  RETRO_HW_CONTEXT_OPENGLES3 = 4,
  RETRO_HW_CONTEXT_OPENGLES_ANY = 5,
  RETRO_HW_CONTEXT_VULKAN = 6,
  RETRO_HW_CONTEXT_DIRECT3D11 = 7,
  RETRO_HW_CONTEXT_DUMMY = 255
};

typedef void (*retro_hw_context_reset_t)(void);
typedef uintptr_t (*retro_hw_get_proc_address_t)(const char *sym);
typedef uintptr_t (*retro_hw_get_current_framebuffer_t)(void);

struct retro_hw_render_callback {
  enum retro_hw_context_type context_type;
  retro_hw_context_reset_t context_reset;
  retro_hw_get_current_framebuffer_t get_current_framebuffer;
  retro_hw_get_proc_address_t get_proc_address;
  bool depth;
  bool stencil;
  bool bottom_left_origin;
  unsigned version_major;
  unsigned version_minor;
  bool cache_context;
  retro_hw_context_reset_t context_destroy;
  bool debug_context;
};

#define RETRO_HW_FRAME_BUFFER_VALID ((void *)-1)

/* ========================================================================
 * Core Options V1 (legacy but still used by older cores)
 * ======================================================================== */

#define RETRO_NUM_CORE_OPTION_VALUES_MAX 128

struct retro_core_option_value {
  const char *value;
  const char *label; /* label in UI; NULL → use value as label */
};

struct retro_core_option_definition {
  const char *key;  /* Unique key, e.g. "genesis_plus_gx_blargg"          */
  const char *desc; /* Short human-readable name                          */
  const char *info; /* Detailed description                               */
  struct retro_core_option_value
      values[RETRO_NUM_CORE_OPTION_VALUES_MAX]; /* Fixed-size array  */
  const char *default_value; /* Default value; NULL or "disabled" */
};

struct retro_core_options {
  struct retro_core_option_definition *definitions;
};

struct retro_core_options_intl {
  struct retro_core_options *us;    /* US English (fallback)    */
  struct retro_core_options *local; /* Local language (can be NULL) */
};

/* ========================================================================
 * Core Options V2 (the standard — almost all maintained cores use this)
 * ======================================================================== */

struct retro_core_option_v2_category {
  const char *key;  /* Unique category key, e.g. "hacks", "video"         */
  const char *desc; /* Display name, e.g. "Speed Hacks"                   */
  const char *info; /* Optional description                                */
};

struct retro_core_option_v2_definition {
  const char *key;  /* Unique option key                                  */
  const char *desc; /* Short name (used if desc_categorized is NULL)     */
  const char
      *desc_categorized; /* Short name shown when in a category (can be NULL) */
  const char *info; /* Detailed description                               */
  const char
      *info_categorized;    /* Description shown in category (can be NULL)    */
  const char *category_key; /* Category this option belongs to (can be NULL) */
  struct retro_core_option_value
      values[RETRO_NUM_CORE_OPTION_VALUES_MAX]; /* Fixed-size array  */
  const char *default_value; /* Default value (must be one of the values[]) */
};

struct retro_core_options_v2 {
  struct retro_core_option_v2_category
      *categories; /* NULL-terminated array (can be NULL)  */
  struct retro_core_option_v2_definition
      *definitions; /* NULL-terminated array                */
};

struct retro_core_options_v2_intl {
  struct retro_core_options_v2 *us;    /* US English (fallback)    */
  struct retro_core_options_v2 *local; /* Local language (can be NULL) */
};

/* ========================================================================
 * Core Options Displayed (V2) — core can selectively hide options
 * ======================================================================== */

struct retro_core_options_display {
  const char *key; /* Option key to show/hide                            */
  bool visible;    /* true = show, false = hide                          */
};

/* ========================================================================
 * Input Descriptors — describes the input layout exposed by a core
 * ======================================================================== */

struct retro_input_descriptor {
  unsigned port;
  unsigned device;
  unsigned index;
  unsigned id;
  const char *description;
};

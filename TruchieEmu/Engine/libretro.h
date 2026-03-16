#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>

// Minimal libretro.h subset for our bridge
#define RETRO_API_VERSION 1

#define RETRO_ENVIRONMENT_SET_ROTATION 1
#define RETRO_ENVIRONMENT_GET_CAN_DUPE 3
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY 9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 10
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS 11
#define RETRO_ENVIRONMENT_GET_VARIABLE 15
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE 17
#define RETRO_ENVIRONMENT_GET_LOG_INTERFACE 27
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY 31
#define RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO 34
#define RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME 36
#define RETRO_ENVIRONMENT_GET_LIBRETRO_PATH 37
#define RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK 38
#define RETRO_ENVIRONMENT_SET_AUDIO_CALLBACK 39
#define RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION 45

enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,
    RETRO_PIXEL_FORMAT_RGB565   = 2,
    RETRO_PIXEL_FORMAT_UNKNOWN  = 0xffffffff
};

typedef bool (*retro_environment_t)(unsigned cmd, void *data);
typedef void (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);

struct retro_game_info {
    const char *path;
    const void *data;
    size_t size;
    const char *meta;
};

// Logging interface
enum retro_log_level {
    RETRO_LOG_DEBUG = 0,
    RETRO_LOG_INFO,
    RETRO_LOG_WARN,
    RETRO_LOG_ERROR,
    RETRO_LOG_DUMMY = 255
};

typedef void (*retro_log_printf_t)(enum retro_log_level level, const char *fmt, ...);

struct retro_log_interface {
    retro_log_printf_t log;
};

struct retro_system_av_info {
    struct { unsigned base_width, base_height, max_width, max_height; double aspect_ratio; } geometry;
    struct { double fps, sample_rate; } timing;
};

// Function pointer typedefs for core symbols
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
typedef void (*fn_retro_get_system_av_info)(struct retro_system_av_info *info);
typedef size_t (*fn_retro_serialize_size)(void);
typedef bool (*fn_retro_serialize)(void *data, size_t size);
typedef bool (*fn_retro_unserialize)(const void *data, size_t size);

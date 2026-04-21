#pragma once

#import <Foundation/Foundation.h> // <-- Added this to fix the 'BOOL' error
#include "libretro.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool bridge_environment(unsigned cmd, void *data);
void bridge_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch);
void bridge_audio_sample(int16_t left, int16_t right);
size_t bridge_audio_sample_batch(const int16_t *data, size_t frames);
void bridge_input_poll(void);
int16_t bridge_input_state(unsigned port, unsigned device, unsigned index, unsigned id);
uintptr_t bridge_get_proc_address(const char *sym);
uintptr_t bridge_get_current_framebuffer(void);

extern int16_t g_input_state[32];
extern int16_t g_analog_state[2][2];
extern BOOL g_turbo_state[32];
extern int g_turbo_counter[32];
extern BOOL g_turbo_active[32];
extern const int g_turbo_rate;
extern int g_turbo_fireButton[32];

#ifdef __cplusplus
}
#endif
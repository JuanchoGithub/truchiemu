#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
#include <atomic>
extern "C" {
typedef std::atomic<int> atomic_int_shm;
typedef std::atomic<long> atomic_long_shm;
#else
#include <stdatomic.h>
typedef atomic_int atomic_int_shm;
typedef atomic_long atomic_long_shm;
#endif

#define XPC_SHM_NAME_PREFIX "/te_shm_"

#define MAX_PLAYERS 4
#define XPC_INPUT_STATE_COUNT 32
#define XPC_ANALOG_STICKS 2
#define XPC_ANALOG_AXES 2
#define XPC_ANALOG_BUTTON_COUNT 32
#define XPC_TURBO_COUNT 32
#define XPC_KEYBOARD_STATE_COUNT 512

#define XPC_AUDIO_RING_CAPACITY 32768

typedef struct {
    int16_t delta_x;
    int16_t delta_y;
    int16_t wheel_delta;
    uint32_t buttons;
    int16_t analog_mouse_delta_x;
    int16_t analog_mouse_delta_y;
    bool absolute_position_override;
    int16_t absolute_x;
    int16_t absolute_y;
    uint8_t _pad[3];
} XPCMouseState;

typedef struct {
    int16_t pointer_x;
    int16_t pointer_y;
    bool pointer_pressed;
    uint8_t _pad[5];
} XPCPointerState;

typedef struct {
    atomic_int_shm frameReady;
    int _pad0;

    int16_t input_state[MAX_PLAYERS][XPC_INPUT_STATE_COUNT];
    int16_t analog_state[MAX_PLAYERS][XPC_ANALOG_STICKS][XPC_ANALOG_AXES];
    int16_t analog_button_state[MAX_PLAYERS][XPC_ANALOG_BUTTON_COUNT];
    bool turbo_active[MAX_PLAYERS][XPC_TURBO_COUNT];
    int turbo_counter[MAX_PLAYERS][XPC_TURBO_COUNT];
    bool turbo_state[MAX_PLAYERS][XPC_TURBO_COUNT];
    int turbo_fireButton[MAX_PLAYERS][XPC_TURBO_COUNT];
    bool keyboard_state[XPC_KEYBOARD_STATE_COUNT];

    XPCMouseState mouse;
    XPCPointerState pointer;

    int16_t analog_mouse_config[MAX_PLAYERS][4]; // [p][0]=enabled, [1]=sensitivity*100, [2]=deadzone*100, [3]=stick_index

    bool isPaused;
    bool variablesUpdated;
    int currentRotation;

    int videoWidth;
    int videoHeight;
    int videoPitch;
    int videoFormat;

    atomic_long_shm audioWritePos;
    atomic_long_shm audioReadPos;
    int16_t audioBuffer[XPC_AUDIO_RING_CAPACITY];
} XPCSharedMemory;

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
static inline int xpc_shm_load_frameReady(XPCSharedMemory *shm) {
    return shm->frameReady.load();
}
static inline void xpc_shm_store_frameReady(XPCSharedMemory *shm, int value) {
    shm->frameReady.store(value);
}
static inline long xpc_shm_load_audioWritePos(XPCSharedMemory *shm) {
    return shm->audioWritePos.load();
}
static inline void xpc_shm_store_audioWritePos(XPCSharedMemory *shm, long value) {
    shm->audioWritePos.store(value);
}
static inline long xpc_shm_load_audioReadPos(XPCSharedMemory *shm) {
    return shm->audioReadPos.load();
}
static inline void xpc_shm_store_audioReadPos(XPCSharedMemory *shm, long value) {
    shm->audioReadPos.store(value);
}
static inline long xpc_shm_load_audioWritePos_relaxed(XPCSharedMemory *shm) {
    return shm->audioWritePos.load(std::memory_order_relaxed);
}
static inline void xpc_shm_store_audioWritePos_relaxed(XPCSharedMemory *shm, long value) {
    shm->audioWritePos.store(value, std::memory_order_relaxed);
}
static inline long xpc_shm_load_audioReadPos_relaxed(XPCSharedMemory *shm) {
    return shm->audioReadPos.load(std::memory_order_relaxed);
}
#else
static inline int xpc_shm_load_frameReady(XPCSharedMemory *shm) {
    return atomic_load(&shm->frameReady);
}
static inline void xpc_shm_store_frameReady(XPCSharedMemory *shm, int value) {
    atomic_store(&shm->frameReady, value);
}
static inline long xpc_shm_load_audioWritePos(XPCSharedMemory *shm) {
    return atomic_load(&shm->audioWritePos);
}
static inline void xpc_shm_store_audioWritePos(XPCSharedMemory *shm, long value) {
    atomic_store(&shm->audioWritePos, value);
}
static inline long xpc_shm_load_audioReadPos(XPCSharedMemory *shm) {
    return atomic_load(&shm->audioReadPos);
}
static inline void xpc_shm_store_audioReadPos(XPCSharedMemory *shm, long value) {
    atomic_store(&shm->audioReadPos, value);
}
static inline long xpc_shm_load_audioWritePos_relaxed(XPCSharedMemory *shm) {
    return atomic_load_explicit(&shm->audioWritePos, memory_order_relaxed);
}
static inline void xpc_shm_store_audioWritePos_relaxed(XPCSharedMemory *shm, long value) {
    atomic_store_explicit(&shm->audioWritePos, value, memory_order_relaxed);
}
static inline long xpc_shm_load_audioReadPos_relaxed(XPCSharedMemory *shm) {
    return atomic_load_explicit(&shm->audioReadPos, memory_order_relaxed);
}
#endif

static inline void xpc_shm_set_input_state(XPCSharedMemory *shm, int player, int idx, int16_t val) {
    if (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_INPUT_STATE_COUNT) shm->input_state[player][idx] = val;
}
static inline int16_t xpc_shm_get_input_state(XPCSharedMemory *shm, int player, int idx) {
    return (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_INPUT_STATE_COUNT) ? shm->input_state[player][idx] : 0;
}

static inline void xpc_shm_set_analog_state(XPCSharedMemory *shm, int player, int stick, int axis, int16_t val) {
    if (player >= 0 && player < MAX_PLAYERS && stick >= 0 && stick < XPC_ANALOG_STICKS && axis >= 0 && axis < XPC_ANALOG_AXES)
        shm->analog_state[player][stick][axis] = val;
}

static inline void xpc_shm_set_analog_button(XPCSharedMemory *shm, int player, int idx, int16_t val) {
    if (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_ANALOG_BUTTON_COUNT) shm->analog_button_state[player][idx] = val;
}

static inline void xpc_shm_set_turbo_active(XPCSharedMemory *shm, int player, int idx, bool val) {
    if (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_TURBO_COUNT) shm->turbo_active[player][idx] = val;
}
static inline void xpc_shm_set_turbo_fireButton(XPCSharedMemory *shm, int player, int idx, int val) {
    if (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_TURBO_COUNT) shm->turbo_fireButton[player][idx] = val;
}

static inline void xpc_shm_set_keyboard_state(XPCSharedMemory *shm, int idx, bool val) {
    if (idx >= 0 && idx < XPC_KEYBOARD_STATE_COUNT) shm->keyboard_state[idx] = val;
}

static inline void xpc_shm_write_audio(XPCSharedMemory *shm, const int16_t *samples, size_t count) {
    long writePos = xpc_shm_load_audioWritePos_relaxed(shm);
    long readPos = xpc_shm_load_audioReadPos_relaxed(shm);
    for (size_t i = 0; i < count; i++) {
        long nextWrite = (writePos + 1) % XPC_AUDIO_RING_CAPACITY;
        if (nextWrite != readPos) {
            shm->audioBuffer[writePos] = samples[i];
            writePos = nextWrite;
        }
    }
    xpc_shm_store_audioWritePos_relaxed(shm, writePos);
}

static inline int xpc_shm_open(const char *name, int oflag, mode_t mode) {
    return shm_open(name, oflag, mode);
}

static inline int16_t xpc_shm_get_analog_state(XPCSharedMemory *shm, int player, int stick, int axis) {
    if (player >= 0 && player < MAX_PLAYERS && stick >= 0 && stick < XPC_ANALOG_STICKS && axis >= 0 && axis < XPC_ANALOG_AXES)
        return shm->analog_state[player][stick][axis];
    return 0;
}

static inline int16_t xpc_shm_get_analog_button(XPCSharedMemory *shm, int player, int idx) {
    return (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_ANALOG_BUTTON_COUNT) ? shm->analog_button_state[player][idx] : 0;
}

static inline bool xpc_shm_get_turbo_active(XPCSharedMemory *shm, int player, int idx) {
    return (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_TURBO_COUNT) ? shm->turbo_active[player][idx] : false;
}

static inline int xpc_shm_get_turbo_counter(XPCSharedMemory *shm, int player, int idx) {
    return (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_TURBO_COUNT) ? shm->turbo_counter[player][idx] : 0;
}

static inline bool xpc_shm_get_turbo_state(XPCSharedMemory *shm, int player, int idx) {
    return (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_TURBO_COUNT) ? shm->turbo_state[player][idx] : false;
}

static inline int xpc_shm_get_turbo_fireButton(XPCSharedMemory *shm, int player, int idx) {
    return (player >= 0 && player < MAX_PLAYERS && idx >= 0 && idx < XPC_TURBO_COUNT) ? shm->turbo_fireButton[player][idx] : 0;
}

static inline bool xpc_shm_get_keyboard_state(XPCSharedMemory *shm, int idx) {
    return (idx >= 0 && idx < XPC_KEYBOARD_STATE_COUNT) ? shm->keyboard_state[idx] : false;
}

static inline void xpc_shm_set_analog_mouse_config(XPCSharedMemory *shm, int player, bool enabled, float sensitivity, float deadzone, int stickIndex) {
    if (player >= 0 && player < MAX_PLAYERS) {
        shm->analog_mouse_config[player][0] = enabled ? 1 : 0;
        shm->analog_mouse_config[player][1] = (int16_t)(sensitivity * 100.0f);
        shm->analog_mouse_config[player][2] = (int16_t)(deadzone * 100.0f);
        shm->analog_mouse_config[player][3] = (int16_t)stickIndex;
    }
}
static inline bool xpc_shm_get_analog_mouse_enabled(XPCSharedMemory *shm, int player) {
    return (player >= 0 && player < MAX_PLAYERS) ? (shm->analog_mouse_config[player][0] != 0) : false;
}
static inline float xpc_shm_get_analog_mouse_sensitivity(XPCSharedMemory *shm, int player) {
    return (player >= 0 && player < MAX_PLAYERS) ? (float)shm->analog_mouse_config[player][1] / 100.0f : 0.8f;
}
static inline float xpc_shm_get_analog_mouse_deadzone(XPCSharedMemory *shm, int player) {
    return (player >= 0 && player < MAX_PLAYERS) ? (float)shm->analog_mouse_config[player][2] / 100.0f : 0.15f;
}
static inline int xpc_shm_get_analog_mouse_stick_index(XPCSharedMemory *shm, int player) {
    return (player >= 0 && player < MAX_PLAYERS) ? shm->analog_mouse_config[player][3] : 0;
}

static inline void xpc_shm_read_audio(XPCSharedMemory *shm, long idx, int16_t *out) {
    if (idx >= 0 && idx < XPC_AUDIO_RING_CAPACITY) *out = shm->audioBuffer[idx];
}

#ifdef __cplusplus
extern "C" {
#endif
void xpc_shm_set_global(XPCSharedMemory *shm);
#ifdef __cplusplus
}
#endif

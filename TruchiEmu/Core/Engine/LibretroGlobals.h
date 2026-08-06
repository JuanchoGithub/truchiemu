#pragma once

#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>
#include "libretro.h"
#import "LibretroBridge.h"
#ifdef XPC_SERVICE
#include "XPCSharedMemory.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration
@class LibretroBridgeImpl;

typedef void (*LogFunc)(const char *, int);

extern CoreLoggerBlock g_swiftLoggerBlock;
extern GameLoadedBlock g_gameLoadedCallback;
extern unsigned g_currentSaveRAMType;
extern LogFunc g_active_log_func;

extern LibretroBridgeImpl *g_instance;
extern int g_selectedLanguage;
extern int g_logLevel;
extern NSString *g_coreID;
extern NSString *g_systemID;
extern NSString *g_romFilename;
extern NSString *g_shaderDir;
extern BOOL g_isPaused;
extern int g_currentRotation;
extern GLuint g_hwFBO;

extern NSMutableDictionary<NSString *, NSString *> *g_optValues;
extern NSDictionary<NSString *, NSDictionary *> *g_optDefinitions;
extern NSDictionary<NSString *, NSDictionary *> *g_optCategories;
extern BOOL g_loadingForOptions;
// YES when the bridge kept a libretro core loaded after a headless options
// discovery probe so a subsequent game launch can take over the same instance
// instead of re-dlopen'ing the dylib (which crashes PPSSPP's ThreadManager on
// the second retro_init inside the same XPC service process).
extern BOOL g_instancePersisted;

// Input descriptors (RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS)
extern NSDictionary<NSString *, NSArray *> *g_inputDescriptors;

void parseInputDescriptors(const struct retro_input_descriptor *descriptors);

extern BOOL g_variablesUpdated;
extern unsigned g_genesisDeviceType;
extern unsigned g_dosDeviceType;
extern int g_wiiControllerType;

#ifndef XPC_SERVICE
extern BOOL g_xpcModeActive;
#endif

extern dispatch_semaphore_t g_bridgeCompletionSemaphore;

// Keyboard state (RETRO_DEVICE_KEYBOARD)
extern BOOL g_keyboard_state[512];

// Mouse state (RETRO_DEVICE_MOUSE)
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
} MouseState;
extern MouseState g_mouse_state;

// Pointer state (RETRO_DEVICE_POINTER)
extern int16_t g_pointer_x;
extern int16_t g_pointer_y;
extern BOOL g_pointer_pressed;

#ifdef XPC_SERVICE
extern XPCSharedMemory *g_xpc_shm;
#endif

void bridge_log_printf(enum retro_log_level level, const char *fmt, ...);
void initOptStorage(void);
void parseCoreOptionsV1(struct retro_core_options *opts);
void parseCoreOptionsV2(struct retro_core_options_v2 *opts);
void applyPersistedOverrides(void);

// Core log callback mechanism
typedef void (*CoreLogCallback)(const char *message, int level);
extern CoreLogCallback g_coreLogCallback;
void RegisterCoreLogCallback(CoreLogCallback callback);

#ifdef __cplusplus
}
#endif
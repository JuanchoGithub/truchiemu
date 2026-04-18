#pragma once

#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>
#include "libretro.h"
#import "LibretroBridge.h" // <-- ADD THIS

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration
@class LibretroBridgeImpl;

typedef void (*LogFunc)(const char *, int);

extern CoreLoggerBlock g_swiftLoggerBlock;
extern LogFunc g_active_log_func;

extern LibretroBridgeImpl *g_instance;
extern int g_selectedLanguage;
extern int g_logLevel;
extern NSString *g_coreID;
extern NSString *g_shaderDir;
extern BOOL g_isPaused;
extern int g_currentRotation;
extern GLuint g_hwFBO;

extern NSMutableDictionary<NSString *, NSString *> *g_optValues;
extern NSDictionary<NSString *, NSDictionary *> *g_optDefinitions;
extern NSDictionary<NSString *, NSDictionary *> *g_optCategories;

extern dispatch_semaphore_t g_bridgeCompletionSemaphore;

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
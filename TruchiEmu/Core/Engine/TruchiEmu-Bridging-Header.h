#import <Cocoa/Cocoa.h>
#import "LibretroBridge.h"
#import "XPCSharedMemory.h"

@class LibretroBridgeImpl;

typedef void (*CoreLogCallback)(const char *message, int level);

void RegisterCoreLogCallback(CoreLogCallback callback);

extern BOOL g_xpcModeActive;

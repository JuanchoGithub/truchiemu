#import <Cocoa/Cocoa.h>
#import "LibretroBridge.h"

// Callback type for routing libretro core logs from C into Swift
typedef void (*CoreLogCallback)(const char *message, int level);

// Called by Swift at startup to register the core log callback
void RegisterCoreLogCallback(CoreLogCallback callback);

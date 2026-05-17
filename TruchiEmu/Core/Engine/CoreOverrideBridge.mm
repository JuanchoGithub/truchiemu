//
// CoreOverrideBridge.m
// TruchiEmu
//
// Objective-C implementation bridging CoreOverrideService to C functions for use in Objective-C++
// This bridges Swift to C, avoiding circular header dependencies
//

#import "CoreOverrideBridge.h"
#import "LibretroGlobals.h"
#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <MetalKit/MetalKit.h>

// Forward declarations to avoid importing full Swift bridging header
@protocol NSApplicationDelegate;
@protocol UNUserNotificationCenterDelegate;

#import "TruchiEmu-Swift.h"

#include <string.h>
#include <stdlib.h>

bool core_override_has_override(const char* coreID, const char* optionKey) {
    if (!coreID || !optionKey) return false;
    
    NSString* coreStr = [NSString stringWithUTF8String:coreID];
    NSString* keyStr = [NSString stringWithUTF8String:optionKey];
    BOOL hasOverride = [CoreOverrideBridge hasOverrideFor:coreStr optionKey:keyStr];
    return hasOverride;
}

const char* core_override_get_value(const char* coreID, const char* optionKey) {
    if (!coreID || !optionKey) return NULL;
    
    NSString* coreStr = [NSString stringWithUTF8String:coreID];
    NSString* keyStr = [NSString stringWithUTF8String:optionKey];
    NSString* result = [CoreOverrideBridge getOverrideFor:coreStr optionKey:keyStr];
    
    if (!result) return NULL;
    
    // Note: This pointer is valid only for this call. Do not store it!
    return result.UTF8String;
}

void core_override_log_overrides(const char* coreID) {
    if (!coreID) return;

    NSString* coreStr = [NSString stringWithUTF8String:coreID];
    [CoreOverrideBridge logOverridesFor:coreStr];
}

void core_override_apply_all_to_optvalues(const char* coreID) {
    if (!coreID || !g_optValues) return;

    NSString* coreStr = [NSString stringWithUTF8String:coreID];
    NSDictionary* allOverrides = [CoreOverrideBridge getAllOverridesFor:coreStr];

    if (!allOverrides || allOverrides.count == 0) return;

    for (NSString* key in allOverrides) {
        NSString* value = allOverrides[key];
        if (key.length > 0 && value.length > 0) {
            g_optValues[key] = value;
            bridge_log_printf(RETRO_LOG_INFO, "[Override-JSON-Preload] %s = %s", key.UTF8String, value.UTF8String);
        }
    }
}

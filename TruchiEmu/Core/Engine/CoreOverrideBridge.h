//
//  CoreOverrideBridge.h
//  TruchiEmu
//
//  C-style bridge for accessing CoreOverrideService from Objective-C++ without circular dependencies
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Checks if an override exists for a core option
bool core_override_has_override(const char* coreID, const char* optionKey);

/// Gets the override value for a core option (returns NULL if no override)
const char* core_override_get_value(const char* coreID, const char* optionKey);

/// Logs all overrides for a core (for debugging)
void core_override_log_overrides(const char* coreID);

#ifdef __cplusplus
}
#endif

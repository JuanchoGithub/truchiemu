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

/// Applies all JSON overrides for a core directly into g_optValues (so cores that read options
/// internally without RETRO_ENVIRONMENT_GET_VARIABLE still see the override values)
void core_override_apply_all_to_optvalues(const char* coreID);

#ifdef __cplusplus
}
#endif

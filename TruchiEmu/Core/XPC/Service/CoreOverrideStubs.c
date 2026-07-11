#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

bool core_override_has_override(const char* coreID, const char* optionKey) {
    return false;
}

const char* core_override_get_value(const char* coreID, const char* optionKey) {
    return NULL;
}

void core_override_log_overrides(const char* coreID) {
}

void core_override_apply_all_to_optvalues(const char* coreID) {
}

#ifdef __cplusplus
}
#endif

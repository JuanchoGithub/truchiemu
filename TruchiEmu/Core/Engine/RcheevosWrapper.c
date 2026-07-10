#include "RcheevosWrapper.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "rc_runtime.h"
#include "rc_runtime_types.h"
#include "rc_error.h"
#include "rc_api_runtime.h"
#include "rc_api_request.h"
#include "rc_api_user.h"
#include "rc_hash.h"
#include "RcheevosCDReader.h"

// The event handler in rcheevos v12.3.0 does not pass userdata.
// Use thread-local storage to route events back to the Swift caller,
// since rc_runtime_do_frame calls the handler synchronously on the same thread.
static _Thread_local RcheevosEventHandler s_current_handler = NULL;
static _Thread_local void* s_current_userdata = NULL;

static void internal_event_handler(const rc_runtime_event_t* event) {
RcheevosEvent wrapped;
wrapped.id = event->id;
wrapped.value = event->value;
wrapped.type = event->type;
if (s_current_handler) {
s_current_handler(&wrapped, s_current_userdata);
}
}

RcheevosRuntimeRef rcheevos_create(void) {
rc_runtime_t* runtime = (rc_runtime_t*)malloc(sizeof(rc_runtime_t));
if (runtime) {
rc_runtime_init(runtime);
}
return runtime;
}

void rcheevos_destroy(RcheevosRuntimeRef runtime) {
if (runtime) {
rc_runtime_destroy((rc_runtime_t*)runtime);
free(runtime);
}
}

int rcheevos_activate_achievement(RcheevosRuntimeRef runtime, unsigned id, const char* trigger, int unused_funcs_idx) {
return rc_runtime_activate_achievement((rc_runtime_t*)runtime, id, trigger, NULL, unused_funcs_idx);
}

void rcheevos_process_frame(RcheevosRuntimeRef runtime, RcheevosEventHandler handler, RcheevosPeekCallback peek, void* userdata) {
s_current_handler = handler;
s_current_userdata = userdata;
rc_runtime_do_frame((rc_runtime_t*)runtime, internal_event_handler, (rc_runtime_peek_t)peek, userdata, NULL);
s_current_handler = NULL;
s_current_userdata = NULL;
}

void rcheevos_reset(RcheevosRuntimeRef runtime) {
rc_runtime_reset((rc_runtime_t*)runtime);
}

uint32_t rcheevos_progress_size(RcheevosRuntimeRef runtime) {
return (uint32_t)rc_runtime_progress_size((rc_runtime_t*)runtime, NULL);
}

int rcheevos_serialize_progress(RcheevosRuntimeRef runtime, uint8_t* buffer, uint32_t buffer_size) {
return rc_runtime_serialize_progress_sized(buffer, buffer_size, (rc_runtime_t*)runtime, NULL);
}

int rcheevos_deserialize_progress(RcheevosRuntimeRef runtime, const uint8_t* buffer, uint32_t buffer_size) {
return rc_runtime_deserialize_progress_sized((rc_runtime_t*)runtime, buffer, buffer_size, NULL);
}

const char* rcheevos_error_str(int error_code) {
  return rc_error_str(error_code);
}

int rcheevos_activate_richpresence(RcheevosRuntimeRef runtime, const char* script) {
  return rc_runtime_activate_richpresence((rc_runtime_t*)runtime, script, NULL, 0);
}

int rcheevos_get_richpresence(RcheevosRuntimeRef runtime, char* buffer, uint32_t buffer_size, RcheevosPeekCallback peek, void* userdata) {
  return rc_runtime_get_richpresence((rc_runtime_t*)runtime, buffer, buffer_size, (rc_runtime_peek_t)peek, userdata, NULL);
}

void rcheevos_deactivate_achievement(RcheevosRuntimeRef runtime, uint32_t id) {
  rc_runtime_deactivate_achievement((rc_runtime_t*)runtime, id);
}

// --- API layer: fetch game patch data ---

int rcheevos_api_init_fetch_game_data(const char* username, const char* api_token, uint32_t game_id, char** out_url, char** out_post_data, char** out_content_type) {
rc_api_fetch_game_data_request_t params;
memset(&params, 0, sizeof(params));
params.username = username;
params.api_token = api_token;
params.game_id = game_id;
params.game_hash = NULL;

rc_api_request_t request;
memset(&request, 0, sizeof(request));

int result = rc_api_init_fetch_game_data_request(&request, &params);
if (result != RC_OK) {
return result;
}

*out_url = request.url ? strdup(request.url) : NULL;
*out_post_data = request.post_data ? strdup(request.post_data) : NULL;
*out_content_type = request.content_type ? strdup(request.content_type) : NULL;

rc_api_destroy_request(&request);
return RC_OK;
}

RcheevosPatchResponse rcheevos_api_process_patch_response(const char* json_body, size_t body_length) {
RcheevosPatchResponse patch_resp;
memset(&patch_resp, 0, sizeof(patch_resp));

rc_api_server_response_t server_resp;
server_resp.body = json_body;
server_resp.body_length = body_length;
server_resp.http_status_code = 200;

rc_api_fetch_game_data_response_t resp;
memset(&resp, 0, sizeof(resp));

int result = rc_api_process_fetch_game_data_server_response(&resp, &server_resp);
if (result != RC_OK || !resp.response.succeeded) {
patch_resp.succeeded = 0;
patch_resp.error_message = resp.response.error_message ? strdup(resp.response.error_message) : strdup("Unknown error");
patch_resp.achievements = NULL;
patch_resp.num_achievements = 0;
rc_api_destroy_fetch_game_data_response(&resp);
return patch_resp;
}

patch_resp.succeeded = 1;
patch_resp.error_message = NULL;
patch_resp.rich_presence_script = resp.rich_presence_script ? strdup(resp.rich_presence_script) : NULL;

if (resp.num_achievements > 0) {
patch_resp.achievements = (RcheevosAchievementDef*)malloc(resp.num_achievements * sizeof(RcheevosAchievementDef));
patch_resp.num_achievements = resp.num_achievements;

for (uint32_t i = 0; i < resp.num_achievements; i++) {
patch_resp.achievements[i].id = resp.achievements[i].id;
patch_resp.achievements[i].definition = resp.achievements[i].definition ? strdup(resp.achievements[i].definition) : NULL;
patch_resp.achievements[i].points = resp.achievements[i].points;
patch_resp.achievements[i].category = resp.achievements[i].category;
}
} else {
patch_resp.achievements = NULL;
patch_resp.num_achievements = 0;
}

rc_api_destroy_fetch_game_data_response(&resp);
return patch_resp;
}

void rcheevos_api_destroy_patch_response(RcheevosPatchResponse* response) {
if (!response) return;

if (response->achievements) {
for (uint32_t i = 0; i < response->num_achievements; i++) {
free((void*)response->achievements[i].definition);
}
free(response->achievements);
response->achievements = NULL;
}
free((void*)response->rich_presence_script);
response->rich_presence_script = NULL;
free((void*)response->error_message);
response->error_message = NULL;
response->num_achievements = 0;
}

void rcheevos_api_destroy_request_strings(char* url, char* post_data, char* content_type) {
    free(url);
    free(post_data);
    free(content_type);
}

int rcheevos_api_init_login(const char* username, const char* password, char** out_url, char** out_post_data, char** out_content_type) {
    rc_api_login_request_t params;
    memset(&params, 0, sizeof(params));
    params.username = username;
    params.password = password;

    rc_api_request_t request;
    memset(&request, 0, sizeof(request));

    int result = rc_api_init_login_request(&request, &params);
    if (result != RC_OK) {
        return result;
    }

    *out_url = request.url ? strdup(request.url) : NULL;
    *out_post_data = request.post_data ? strdup(request.post_data) : NULL;
    *out_content_type = request.content_type ? strdup(request.content_type) : NULL;

    rc_api_destroy_request(&request);
    return RC_OK;
}

int rcheevos_api_process_login_response(const char* json_body, size_t body_length, char** out_api_token) {
    rc_api_server_response_t server_resp;
    server_resp.body = json_body;
    server_resp.body_length = body_length;
    server_resp.http_status_code = 200;

    rc_api_login_response_t resp;
    memset(&resp, 0, sizeof(resp));

    int result = rc_api_process_login_server_response(&resp, &server_resp);
    if (result != RC_OK || !resp.response.succeeded) {
        *out_api_token = NULL;
        rc_api_destroy_login_response(&resp);
        return result != RC_OK ? result : -1;
    }

    *out_api_token = resp.api_token ? strdup(resp.api_token) : NULL;
    rc_api_destroy_login_response(&resp);
    return (*out_api_token != NULL) ? RC_OK : -1;
}

// --- API layer: award achievement ---

int rcheevos_api_init_award_achievement(const char* username, const char* api_token, uint32_t achievement_id, uint32_t hardcore, char** out_url, char** out_post_data, char** out_content_type) {
    rc_api_award_achievement_request_t params;
    memset(&params, 0, sizeof(params));
    params.username = username;
    params.api_token = api_token;
    params.achievement_id = achievement_id;
    params.hardcore = hardcore;
    params.game_hash = NULL;
    params.seconds_since_unlock = 0;

    rc_api_request_t request;
    memset(&request, 0, sizeof(request));

    int result = rc_api_init_award_achievement_request(&request, &params);
    if (result != RC_OK) {
        return result;
    }

    *out_url = request.url ? strdup(request.url) : NULL;
    *out_post_data = request.post_data ? strdup(request.post_data) : NULL;
    *out_content_type = request.content_type ? strdup(request.content_type) : NULL;

    rc_api_destroy_request(&request);
    return RC_OK;
}

RcheevosAwardResponse rcheevos_api_process_award_response(const char* json_body, size_t body_length, int http_status_code) {
    RcheevosAwardResponse award_resp;
    memset(&award_resp, 0, sizeof(award_resp));

    rc_api_server_response_t server_resp;
    server_resp.body = json_body;
    server_resp.body_length = body_length;
    server_resp.http_status_code = http_status_code;

    rc_api_award_achievement_response_t resp;
    memset(&resp, 0, sizeof(resp));

    int result = rc_api_process_award_achievement_server_response(&resp, &server_resp);
    if (result != RC_OK || !resp.response.succeeded) {
        award_resp.succeeded = 0;
        award_resp.error_message = resp.response.error_message ? strdup(resp.response.error_message) : strdup("Unknown error");
        rc_api_destroy_award_achievement_response(&resp);
        return award_resp;
    }

    award_resp.succeeded = 1;
    award_resp.awarded_achievement_id = resp.awarded_achievement_id;
    award_resp.new_player_score = resp.new_player_score;
    award_resp.new_player_score_softcore = resp.new_player_score_softcore;
    award_resp.achievements_remaining = resp.achievements_remaining;
    award_resp.error_message = NULL;

    rc_api_destroy_award_achievement_response(&resp);
    return award_resp;
}

// --- Hash generation ---

int rcheevos_hash_generate(const char* path, uint32_t console_id, char* out_hash, size_t out_hash_size) {
    if (!path || !out_hash || out_hash_size < 33) return 0;

    // Check if this is a .cdi file that needs the custom CD reader
    const char* dot = strrchr(path, '.');
    int is_cdi = (dot && strcasecmp(dot, ".cdi") == 0);

    if (is_cdi)
        rcheevos_cdreader_register();

    int result = (rc_hash_generate_from_file(out_hash, console_id, path) != 0) ? 1 : 0;

    if (is_cdi)
        rc_hash_init_custom_cdreader(NULL);

    return result;
}

void rcheevos_api_destroy_award_response(RcheevosAwardResponse* response) {
    if (!response) return;
    free((void*)response->error_message);
    response->error_message = NULL;
}

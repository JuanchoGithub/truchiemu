#ifndef RcheevosWrapper_h
#define RcheevosWrapper_h

#include <stdint.h>
#include <stdbool.h>

typedef void* RcheevosRuntimeRef;

typedef struct {
unsigned id;
int value;
char type;
} RcheevosEvent;

#define RCHEEVOS_EVENT_ACHIEVEMENT_TRIGGERED 0
#define RCHEEVOS_EVENT_ACHIEVEMENT_PRIMED 1
#define RCHEEVOS_EVENT_ACHIEVEMENT_UNPRIMED 2
#define RCHEEVOS_EVENT_ACHIEVEMENT_PROGRESS_UPDATED 3

typedef uint32_t (*RcheevosPeekCallback)(uint32_t address, uint32_t num_bytes, void* userdata);
typedef void (*RcheevosEventHandler)(const RcheevosEvent* event, void* userdata);

RcheevosRuntimeRef rcheevos_create(void);
void rcheevos_destroy(RcheevosRuntimeRef runtime);
int rcheevos_activate_achievement(RcheevosRuntimeRef runtime, unsigned id, const char* trigger, int unused_funcs_idx);
void rcheevos_process_frame(RcheevosRuntimeRef runtime, RcheevosEventHandler handler, RcheevosPeekCallback peek, void* userdata);
void rcheevos_reset(RcheevosRuntimeRef runtime);
uint32_t rcheevos_progress_size(RcheevosRuntimeRef runtime);
int rcheevos_serialize_progress(RcheevosRuntimeRef runtime, uint8_t* buffer, uint32_t buffer_size);
int rcheevos_deserialize_progress(RcheevosRuntimeRef runtime, const uint8_t* buffer, uint32_t buffer_size);
const char* rcheevos_error_str(int error_code);

// --- API layer: fetch game patch data (unhashed triggers) ---

typedef struct {
uint32_t id;
const char* definition;
uint32_t points;
uint32_t category;
} RcheevosAchievementDef;

typedef struct {
RcheevosAchievementDef* achievements;
uint32_t num_achievements;
const char* rich_presence_script;
int succeeded;
const char* error_message;
} RcheevosPatchResponse;

// Build the dorequest.php?r=patch URL and POST body.
// Returns 0 on success. Caller must free url/post_data via rcheevos_api_destroy_request.
int rcheevos_api_init_fetch_game_data(const char* username, const char* api_token, uint32_t game_id, char** out_url, char** out_post_data, char** out_content_type);

// Parse the server response from dorequest.php?r=patch.
// Returns a RcheevosPatchResponse with achievement definitions (unhashed triggers).
// Caller must free via rcheevos_api_destroy_patch_response.
RcheevosPatchResponse rcheevos_api_process_patch_response(const char* json_body, size_t body_length);

// Free the response allocated by rcheevos_api_process_patch_response.
void rcheevos_api_destroy_patch_response(RcheevosPatchResponse* response);

// Free strings allocated by rcheevos_api_init_fetch_game_data.
void rcheevos_api_destroy_request_strings(char* url, char* post_data, char* content_type);

// --- API layer: login2 ---

// Build the dorequest.php?r=login2 request.
// password is the user's RA account password (sent as p= param).
// Returns 0 on success. Caller must free strings via rcheevos_api_destroy_request_strings.
int rcheevos_api_init_login(const char* username, const char* password, char** out_url, char** out_post_data, char** out_content_type);

// Parse the login2 server response.
// On success, out_api_token is set to a strdup'd string that the caller must free.
// Returns 0 on success, non-zero on failure.
int rcheevos_api_process_login_response(const char* json_body, size_t body_length, char** out_api_token);

// --- API layer: award achievement ---

typedef struct {
    uint32_t awarded_achievement_id;
    uint32_t new_player_score;
    uint32_t new_player_score_softcore;
    uint32_t achievements_remaining;
    int succeeded;
    const char* error_message;
} RcheevosAwardResponse;

// Build the dorequest.php?r=awardachievement request.
// api_token is the login token from login2.
// Returns 0 on success. Caller must free strings via rcheevos_api_destroy_request_strings.
int rcheevos_api_init_award_achievement(const char* username, const char* api_token, uint32_t achievement_id, uint32_t hardcore, char** out_url, char** out_post_data, char** out_content_type);

// Parse the award achievement server response.
// Returns a RcheevosAwardResponse. Caller must free via rcheevos_api_destroy_award_response.
RcheevosAwardResponse rcheevos_api_process_award_response(const char* json_body, size_t body_length, int http_status_code);

// Free the response allocated by rcheevos_api_process_award_response.
void rcheevos_api_destroy_award_response(RcheevosAwardResponse* response);

#endif /* RcheevosWrapper_h */

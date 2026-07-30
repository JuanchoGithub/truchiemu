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

#define RCHEEVOS_EVENT_ACHIEVEMENT_ACTIVATED 0
#define RCHEEVOS_EVENT_ACHIEVEMENT_PAUSED 1
#define RCHEEVOS_EVENT_ACHIEVEMENT_RESET 2
#define RCHEEVOS_EVENT_ACHIEVEMENT_TRIGGERED 3
#define RCHEEVOS_EVENT_ACHIEVEMENT_PRIMED 4
#define RCHEEVOS_EVENT_ACHIEVEMENT_DISABLED 5
#define RCHEEVOS_EVENT_ACHIEVEMENT_UNPRIMED 6
#define RCHEEVOS_EVENT_ACHIEVEMENT_PROGRESS_UPDATED 7

typedef uint32_t (*RcheevosPeekCallback)(uint32_t address, uint32_t num_bytes, void* userdata);
typedef void (*RcheevosEventHandler)(const RcheevosEvent* event, void* userdata);

// Wire-friendly achievement trigger descriptor. Strings are UTF-8, owned by the
// caller and must remain valid for the duration of rcheevos_activate_achievement.
typedef struct {
    uint32_t id;
    const char* title;
    const char* trigger;
    int is_unlocked;
} RcheevosAchievementTrigger;

RcheevosRuntimeRef rcheevos_create(void);
void rcheevos_destroy(RcheevosRuntimeRef runtime);
int rcheevos_activate_achievement(RcheevosRuntimeRef runtime, unsigned id, const char* trigger, int unused_funcs_idx);
void rcheevos_process_frame(RcheevosRuntimeRef runtime, RcheevosEventHandler handler, RcheevosPeekCallback peek, void* userdata);
void rcheevos_reset(RcheevosRuntimeRef runtime);
uint32_t rcheevos_progress_size(RcheevosRuntimeRef runtime);
int rcheevos_serialize_progress(RcheevosRuntimeRef runtime, uint8_t* buffer, uint32_t buffer_size);
int rcheevos_deserialize_progress(RcheevosRuntimeRef runtime, const uint8_t* buffer, uint32_t buffer_size);
const char* rcheevos_error_str(int error_code);
int rcheevos_activate_richpresence(RcheevosRuntimeRef runtime, const char* script);
int rcheevos_get_richpresence(RcheevosRuntimeRef runtime, char* buffer, uint32_t buffer_size, RcheevosPeekCallback peek, void* userdata);
void rcheevos_deactivate_achievement(RcheevosRuntimeRef runtime, uint32_t id);

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

// --- API layer: ping (rich presence / "now playing") ---

// Response for ping request. succeeded is 1 on success, 0 on failure.
// On failure, error_message is a strdup'd string the caller must free via
// rcheevos_api_destroy_ping_response.
typedef struct {
    int succeeded;
    const char* error_message;
} RcheevosPingResponse;

// Build the dorequest.php?r=ping POST request.
// api_token is the login token from login2 (NOT the web API key).
// rich_presence is the human-readable "now playing" string, may be NULL.
// game_hash is the ROM hash, may be NULL (recommended).
// hardcore is 1 if hardcore mode is enabled, 0 otherwise (ignored if game_hash is NULL).
// Returns 0 on success. Caller must free strings via rcheevos_api_destroy_request_strings.
int rcheevos_api_init_ping(const char* username, const char* api_token, uint32_t game_id,
                           const char* rich_presence, const char* game_hash, uint32_t hardcore,
                           char** out_url, char** out_post_data, char** out_content_type);

// Parse the ping server response. Caller must free via rcheevos_api_destroy_ping_response.
RcheevosPingResponse rcheevos_api_process_ping_response(const char* json_body, size_t body_length, int http_status_code);

// Free the response allocated by rcheevos_api_process_ping_response.
void rcheevos_api_destroy_ping_response(RcheevosPingResponse* response);

// --- API layer: start session ---

// Response for start session request. succeeded is 1 on success, 0 on failure.
// unlocks/hardcore_unlocks are arrays of achievement IDs already unlocked
// by the user server-side (so the client can suppress redundant award calls).
// Caller must free via rcheevos_api_destroy_start_session_response.
typedef struct {
    int succeeded;
    const char* error_message;
    uint32_t* unlocks;
    uint32_t num_unlocks;
    uint32_t* hardcore_unlocks;
    uint32_t num_hardcore_unlocks;
    int64_t server_now;
} RcheevosStartSessionResponse;

// Build the dorequest.php?r=startsession POST request.
// api_token is the login token from login2 (NOT the web API key).
// game_hash is the ROM hash, may be NULL (recommended).
// hardcore is 1 if hardcore mode is enabled, 0 otherwise (ignored if game_hash is NULL).
// Returns 0 on success. Caller must free strings via rcheevos_api_destroy_request_strings.
int rcheevos_api_init_start_session(const char* username, const char* api_token, uint32_t game_id,
                                    const char* game_hash, uint32_t hardcore,
                                    char** out_url, char** out_post_data, char** out_content_type);

// Parse the start session server response. Caller must free via rcheevos_api_destroy_start_session_response.
RcheevosStartSessionResponse rcheevos_api_process_start_session_response(const char* json_body, size_t body_length, int http_status_code);

// Free the response allocated by rcheevos_api_process_start_session_response.
void rcheevos_api_destroy_start_session_response(RcheevosStartSessionResponse* response);

// --- API layer: login2 with token (token refresh) ---

// Build a dorequest.php?r=login2 POST request using the existing api_token
// instead of a password. RA's login2 endpoint accepts either p=<password>
// OR t=<token>. If the token is still valid, RA returns a fresh token.
// If expired, RA returns an invalid_credentials error.
// Returns 0 on success. Caller must free strings via rcheevos_api_destroy_request_strings.
int rcheevos_api_init_login_with_token(const char* username, const char* api_token,
                                       char** out_url, char** out_post_data, char** out_content_type);

// --- Hash generation (delegates to rcheevos rc_hash) ---

// Generates a RetroAchievements hash for a given file path and console ID.
// out_hash must be at least 33 bytes (32 hex chars + null terminator).
// Returns 1 on success, 0 on failure.
int rcheevos_hash_generate(const char* path, uint32_t console_id, char* out_hash, size_t out_hash_size);

#endif /* RcheevosWrapper_h */

# TASK-004: Migrate All Settings to SQLite

## Dependencies
- Requires: TASK-001 (SQLite Infrastructure)
- Requires: TASK-002 (Game Database Migration)
- Requires: TASK-003 (Metadata Store Migration)

## Blocking
- TASK-005 (Cleanup & Testing)

## Objective
Migrate every remaining UserDefaults.standard usage for application data into the appropriate SQLite tables. This eliminates all UserDefaults-based app data persistence.

## Data Categories to Migrate

### Table: settings (key/value general store)
Keys: has_completed_onboarding, has_completed_full_setup, logging_enabled, display_default_shader_preset, showBiosFiles, systemLanguage, coreLogLevel, autoLoadCheats, applyCheatsOnLaunch, showCheatNotifications, log_level, selected_save_slot

### Table: installed_cores / available_cores
Keys: installed_cores_v2, available_cores_v1 (CoreManager)

### Table: controller_mappings
Keys: controller_mappings_v2, keyboard_mapping_v1, controller_saved_configs

### Table: achievements_config
Keys: ra_username, ra_token, ra_hardcore, ra_enabled

### Table: core_options
Keys: lastLoadedCoreID, coreopt_{coreID}_{key}

### Table: cheats_store
Keys: cheats_v2, cheatLastDownloadDate

### Table: bezel_preferences
Keys: bezel_storage_mode, bezel_custom_folder, bezel_library_folder, bezel_initial_setup, bezel_last_prompted_count, bezel_download_log

### Table: box_art_preferences
Keys: thumbnail_use_libretro, thumbnail_use_head_check, thumbnail_fallback_filename

### Table: shader_presets
Keys: shaderWindowPosition

### Table: categories
Keys: game_categories_v1

### Table: app_settings (runtime prefs)
Keys: auto_load_on_start, auto_save_on_exit, achievements_enabled, cheats_enabled, dosbox_pure_cycles, dosbox_pure_start_menu, dosbox_pure_mouse, compress_save_states, preferredCore_{systemID}, boxType_{systemID}

## Migration Strategy
1. Each service gets a DatabaseManager helper for its table
2. On first access, read from UserDefaults, write to SQLite, remove UserDefaults key
3. All subsequent reads/writes go through DatabaseManager
4. Services keep their public API - only internal storage changes

## Files to Modify (approx 22 files)
CoreManager, ControllerService, CheatManagerService, CheatDownloadService, RetroAchievementsService, CategoryManager, BoxArtService, LoggerService, LogManager, BezelStorageManager, BezelAPIService, SystemInfo, SetupWizardState, CoreOptionsManager, BaseRunner, DOSRunner, GameLauncher, SharedPlayerComponents, SlotPickerSheet, SettingsView, ShaderPresetPickerView, DatabaseManager (add all helper methods)

## Test Plan
### Tests in TruchieEmuTests/Services/Database/:
1. SettingsMigrationTests: Each category migrates, idempotent, handles missing data
2. CoreManagerSqliteTests: Installed cores persist, available cores cached
3. ControllerServiceSqliteTests: Controller/keyboard mappings persist
4. AchievementsSqliteTests: Username/token persist, hardcore/enabled state persist
5. CheatSqliteTests: Custom cheats persist, download date persists
6. BezelSqliteTests: Storage mode and paths persist, download log persists

## Success Criteria
- Zero UserDefaults usage for application data (grep returns 0 results for app data keys)
- All settings persist across launches
- All tests pass
- No regression in behavior
# UserDefaults → SQLite Configuration Database Migration

## Overview
All configuration and state storage has been migrated from `UserDefaults` to the SQLite-backed configuration database via `AppSettings` and dedicated database tables.

## Migration Status

### ✅ COMPLETED - Core Infrastructure
1. **AppSettings.swift** - Enhanced with Data, Date, JSON helpers
2. **DatabaseManager.swift** - Extended migration to include all remaining keys
3. **DatabaseMigrator.swift** - Updated migration patterns

### ✅ COMPLETED - Simple Settings (via AppSettings)
4. **LoggerService.swift** - `log_level` → AppSettings
5. **LogManager.swift** - `custom_log_folder_url` → AppSettings  
6. **GameLauncher.swift** - `achievements_enabled`, `cheats_enabled`, `auto_load_on_start`, `auto_save_on_exit` → AppSettings
7. **BaseRunner.swift** - `compress_save_states`, `lastLoadedCoreID` → AppSettings
8. **DOSRunner.swift** - `dosbox_pure_cycles`, `dosbox_pure_mouse`, `dosbox_pure_start_menu` → AppSettings
9. **CheatDownloadService.swift** - `cheatLastDownloadDate` → AppSettings
10. **BoxArtService.swift** - `screenscraper_credentials`, `thumbnail_server_url`, `thumbnail_priority_type`, `thumbnail_use_crc_matching`, `thumbnail_use_head_check`, `thumbnail_fallback_filename` → AppSettings
11. **LaunchBoxGamesDBService.swift** - `useLaunchBox`, `downloadAfterScan`, `launchbox_last_sync` → AppSettings
12. **SystemInfo.swift** - Removed UserDefaults fallbacks
13. **ROMIdentifierService.swift** - Uses SystemPreferences instead of UserDefaults

### ✅ COMPLETED - Specialized Tables
14. **CheatManagerService.swift** - `cheats_v2` → DatabaseManager `cheats_store` table
15. **BezelStorageManager.swift** - bezel settings → `bezel_preferences` table
16. **BezelAPIService.swift** - download log → `bezel_preferences.download_log_json`

### ✅ COMPLETED - @AppStorage Replacements
17. **SettingsView.swift** - All @AppStorage → @State + AppSettings
18. **LibraryGridView.swift** - `gridColumns` → AppSettings

## Remaining Items
- CoreManager.swift - Complex JSON serialization for installed/available cores (high priority)
- CategoryManager.swift - Complex JSON for categories (high priority)  
- ControllerService.swift - Complex JSON for controller mappings (high priority)

These three require dedicated table migration and are tracked for subsequent phases.

## Migration Flow
```
UserDefaults (startup) → DatabaseManager._migrateUserDefaultsOnOpen() → SQLite settings table (remove from UserDefaults)
```

All services now read/write exclusively from SQLite. On first run after migration, UserDefaults values are removed.

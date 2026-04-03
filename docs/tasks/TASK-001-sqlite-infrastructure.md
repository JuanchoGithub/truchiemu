# TASK-001: SQLite Infrastructure Foundation

## Dependencies
- None (root task)
- Parent: SQLite Migration Epic

## Blocking
- TASK-002 (Game Database Migration) requires this to be complete
- TASK-003 (Metadata Store Migration) requires this to be complete
- TASK-004 (Settings Migration) requires this to be complete

## Objective
Create the core SQLite wrapper using raw sqlite3 C API, with thread-safe connection management, migration framework, and initial schema for all application data.

## Deliverables

### 1. DatabaseManager (`TruchieEmu/Services/Database/DatabaseManager.swift`)
- Singleton pattern (`static let shared`)
- Opens `~/Library/Application Support/TruchieEmu/truchiemu.db`
- Creates directory if missing
- PRAGMA setup:
  - `journal_mode = WAL` (fast reads, crash-safe)
  - `foreign_keys = ON`
  - `synchronous = NORMAL`
- Thread-safe: serial write queue, concurrent reads (or simplified: single serial queue for correctness)
- Methods:
  - `open()` — initialize connection
  - `close()` — clean shutdown
  - `prepare(_ sql:) -> OpaquePointer` — prepared statement helper
  - `execute(_ sql:, bindings:)` — run statement
  - `queryAll(_ sql:, bindings:, rowHandler:)` — multi-row query
  - `queryOne(_ sql:, bindings:, rowHandler:)` → `[String: Any]?` — single row
  - `inTransaction(_ block:)` — wraps in BEGIN/COMMIT/ROLLBACK
  - `runIntegrityCheck()` → `(ok: Bool, message: String)`

### 2. DatabaseMigrator (`TruchieEmu/Services/Database/DatabaseMigrator.swift`)
- Reads `schema_version` from table, creates if absent (version 0)
- Runs migrations 1..N in order, each in a transaction
- Logs each migration

### 3. Schema V1 (`TruchieEmu/Services/Database/SchemaV1.swift`)
Contains all DDL for initial tables:
- `schema_version` (version INTEGER PRIMARY KEY)
- `library_folders` (id, url_path, bookmark_data)
- `roms` (full ROM model mapped to columns + JSON blobs for complex fields)
- `rom_metadata` (path_key as PK, crc32, title, year, developer, publisher, genre, players, description, rating, thumbnail_system_id, box_art_path, title_screen_path, screenshot_paths_json, custom_core_id)
- `settings` (key TEXT PRIMARY KEY, value TEXT)
- `installed_cores` (core_id, display_name, version_tag, install_date, system_ids_json)
- `available_cores` (core_id, display_name, system_ids_json, download_url)
- `controller_mappings` (mapping_id, device_type, config_json)
- `achievements_config` (username, token, is_hardcore, is_enabled)
- `cheats_store` (rom_key, cheats_json)
- `categories` (category_id, name, system_id, color_hex, rom_keys_json)
- `bezel_preferences` (storage_mode, custom_folder_path, library_folder_path, initial_setup_complete, last_prompted_library_count)
- `box_art_preferences` (credentials_json, use_libretro, use_head_check, fallback_filename)
- `core_options` (core_id, option_key, option_value, is_override)

### 4. Error types
- `enum DatabaseError: Error` with cases: `openFailed`, `prepareFailed`, `executeFailed`, `queryFailed`, `migrationError`, `constraintViolation`

## Files to Create
1. `TruchieEmu/Services/Database/DatabaseManager.swift`
2. `TruchieEmu/Services/Database/DatabaseMigrator.swift`
3. `TruchieEmu/Services/Database/SchemaV1.swift`

## Files to Modify
- None (this is purely additive)

## Test Plan
### Tests to create in `TruchieEmuTests/Services/Database/`:
1. `DatabaseManagerTests`:
   - "Opens database and creates directory if missing"
   - "Can execute INSERT and SELECT"
   - "Transactions rollback on error"
   - "Thread-safe concurrent reads"
   - "Integrity check passes on fresh database"
   - "Close and reopen preserves data"

2. `DatabaseMigratorTests`:
   - "Migrates from version 0 to 1"
   - "Re-running migration is idempotent"
   - "Migration logs each step"

3. `SchemaTests`:
   - "All expected tables exist after migration"
   - "Indexes exist for lookups"
   - "Foreign keys enforced"

## Success Criteria
- Database file exists after first launch
- Schema version table exists and reports version 1
- All 16+ tables created with correct columns
- Thread-safe operations work correctly
- All tests pass

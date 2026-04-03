# TASK-002: Game Database Migration (ROMs + Library Folders)

## Dependencies
- Requires: TASK-001 (SQLite Infrastructure)
- Blocked until TASK-001 is complete

## Blocking
- TASK-003 (Metadata Store Migration)

## Objective
Migrate the ROM library and library folder persistence from `UserDefaults.standard` to SQLite. This directly fixes the game database disappearing bug.

## Current State (Broken)
- `ROMLibrary.swift` stores ROMs as JSON blob in UserDefaults key `saved_roms`
- Library folder bookmarks in UserDefaults key `library_folders_bookmarks_v2`
- File index in UserDefaults key `rom_file_index_v1`
- Onboarding state in UserDefaults key `has_completed_onboarding`

## Changes

### 1. Update `ROMLibrary.swift`
- Replace `defaults.data(forKey: romsKey)` / `defaults.set(data, forKey: romsKey)` with:
  - `DatabaseManager.loadROMs()` -> `[ROM]`
  - `DatabaseManager.saveROMs(_ roms:)`
- Replace bookmark storage with:
  - `DatabaseManager.saveLibraryFolders(_ folders:)`
  - `DatabaseManager.loadLibraryFolders()` -> `[URL]`
- Replace file index storage with:
  - `DatabaseManager.saveFileIndex(_ index:)`
  - `DatabaseManager.loadFileIndex()` -> `[String: FileSignature]`
- Replace onboarding check with:
  - `DatabaseManager.getSetting(has_completed_onboarding)` / \.setSetting(...)

### 2. Add UserDefaults -> SQLite one-time migration (inside SchemaV2 or separate migrator step)
- Attempt to read `saved_roms` from UserDefaults
- Decode as `[ROM]` and bulk-insert into SQLite
- Attempt to read `library_folders_bookmarks_v2` and insert into `library_folders`
- Attempt to read legacy `rom_folder_bookmark` (migration from v1)
- After successful migration, remove the UserDefaults keys
- Log migration result (count of ROMs migrated)

### 3. DatabaseManager additions
- `func saveROMs(_ roms: [ROM]) throws`
- `func loadROMs() throws -> [ROM]`
- `func saveROM(_ rom: ROM) throws` - upsert single ROM
- `func deleteROM(atPath: String) throws`
- `func saveLibraryFolders(_ folders: [URL]) throws`
- `func loadLibraryFolders() throws -> [URL]`
- `func saveFileIndex(_ index: [String: FileSignature]) throws`
- `func loadFileIndex() throws -> [String: FileSignature]`
- `func getSetting(_ key: String) -> String?`
- `func setSetting(_ key: String, value: String)`
- `func removeSetting(_ key: String)`
- `func getBoolSetting(_ key: String, defaultValue: Bool) -> Bool`
- `func setBoolSetting(_ key: String, value: Bool)`

## Files to Modify
1. `TruchieEmu/Services/ROMLibrary.swift`
2. `TruchieEmu/Services/Database/DatabaseManager.swift` (add ROM methods)
3. `TruchieEmu/Services/Database/SchemaV1.swift` (if table adjustments needed)

## Test Plan
### Tests in `TruchieEmuTests/Services/Database/`:
1. `ROMDatabaseTests`:
   - Save and load ROM preserves all fields
   - Update existing ROM
   - Delete ROM
   - Load empty database returns empty array
   - ROM with optional fields (nil metadata, nil boxArtPath) round-trips
   - ROM with complex settings round-trips

2. `LibraryFolderDatabaseTests`:
   - Save and load library folders preserves URLs
   - Security bookmark data preserved and can be resolved
   - Multiple folders saved and restored

3. `UserDefaultsMigrationTests`:
   - Migrates saved_roms from UserDefaults to SQLite
   - Migrates library_folders from UserDefaults to SQLite
   - Removes UserDefaults keys after migration
   - Handles corrupted UserDefaults data gracefully (does not crash)
   - Idempotent - running migration twice does not duplicate data

4. `IntegrationTests`:
   - ROMLibrary init loads data from SQLite
   - ROMLibrary.addLibraryFolder persists to SQLite
   - ROMLibrary.updateROM persists to SQLite
   - Full rescan works with SQLite persistence
   - CLI headless exit preserves all data

## Success Criteria
- ROM list persists across app launches
- Library folder bookmarks persist across app launches
- Running --launch via CLI then closing preserves the database
- Old UserDefaults data is migrated without loss
- All tests pass
- Game database no longer disappears
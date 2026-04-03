# TASK-003: LibraryMetadataStore Migration to SQLite

## Dependencies
- Requires: TASK-001 (SQLite Infrastructure)
- Requires: TASK-002 (Game Database Migration)

## Blocking
- TASK-004 (Settings Migration)

## Objective
Replace `LibraryMetadataStore` JSON file (`library_metadata.json`) with the SQLite `rom_metadata` table. Unify all ROM-related data into one database.

## Current State
- `LibraryMetadataStore.swift` reads/writes JSON to `~/Library/Application Support/TruchieEmu/library_metadata.json`
- Already implements good patterns (atomic writes, temp file swap)
- Merges data via `ROMMetadataRecord` struct with `applying(to:)` method

## Changes

### 1. Update `LibraryMetadataStore.swift`
- Replace `loadFromDisk()` with SQL query on `rom_metadata` table
- Replace `saveToDisk()` with upsert into `rom_metadata` table
- Replace `persist(rom:)` with `DatabaseManager.upsertMetadata(rom:)`
- Replace `mergedROM(rom:)` with SQL JOIN or direct lookup
- Replace `migrateLegacySidecarsIfStoreEmpty(roms:)` with migration from legacy `_info.json` files

### 2. DatabaseManager additions
- `func upsertMetadata(for rom: ROM) throws`
- `func loadMetadata(forPath: String) -> ROMMetadataRecord?`
- `func loadAllMetadata() throws -> [String: ROMMetadataRecord]`
- `func customCore(for rom: ROM) -> String?` - convenience
- `func setCustomCore(_ coreID: String, for rom: ROM) throws`
- `func clearCustomCore(for rom: ROM) throws`

### 3. JSON file migration
- On first run with SQLite, read `library_metadata.json`
- Import all entries into `rom_metadata` table
- Rename file to `library_metadata.json.migrated`
- Log count of migrated records

## Files to Modify
1. `TruchieEmu/Models/LibraryMetadataStore.swift`
2. `TruchieEmu/Services/Database/DatabaseManager.swift`

## Test Plan
### Tests in `TruchieEmuTests/Services/Database/`:
1. `MetadataStoreTests`:
   - Upsert metadata for a ROM
   - Load metadata returns nil for missing ROM
   - mergedROM applies stored metadata correctly
   - Custom core ID persists and loads
   - Clear custom core removes assignment
   - Screenshot paths are preserved on update

2. `JSONMigrationTests`:
   - Migrates library_metadata.json to SQLite
   - Renames migrated file
   - Idempotent migration
   - Handles missing JSON file gracefully
   - Handles corrupted JSON gracefully

## Success Criteria
- All metadata operations work through SQLite
- JSON file is migrated without data loss
- Custom core assignments persist
- All tests pass
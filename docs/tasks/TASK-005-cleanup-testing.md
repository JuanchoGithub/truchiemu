# TASK-005: Cleanup, Verification & Final Testing

## Dependencies
- Requires: TASK-001 (SQLite Infrastructure)
- Requires: TASK-002 (Game Database Migration)
- Requires: TASK-003 (Metadata Store Migration)
- Requires: TASK-004 (Settings Migration)

## Blocking
- None (final task)

## Objective
Complete cleanup of legacy code, write comprehensive tests, verify all persistence works correctly, especially CLI scenarios.

## Tasks

### 1. Remove Legacy UserDefaults Keys
- `grep -rn "UserDefaults.standard" --include="*.swift"` and verify zero hits for app data
- Remove old UserDefaults keys: `saved_roms`, `library_folders_bookmarks_v2`, `rom_file_index_v1`, etc.
- Verify no dead code referencing old persistence paths

### 2. Database Corruption Recovery
- Implement auto backup system:
  - Before any major write, copy `truchiemu.db` to `truchiemu.db.backup`
  - On open failure, attempt to open `.backup`
  - `DatabaseManager.runIntegrityCheck()` diagnostic method
- Handle corrupt database gracefully with clear error messages

### 3. CLI Headless Verification
- Ensure data persists after headless launch with timeout
- Verify no race conditions between CLI exit and database flush
- Test rapid successive CLI launches

### 4. Full Integration Test Suite
- End-to-end test: add ROM → scan library → update metadata → restart → verify all data present
- Edge cases: empty database, large library (1000+ ROMs), special characters in paths

### 5. Performance Verification
- Load time for 1000 ROMs should be < 100ms from SQLite
- Verify WAL mode is active (`PRAGMA journal_mode`)
- Index all lookup columns

### 6. Documentation
- Update README with new database architecture
- Document migration path for users with existing installations

## Test Plan
### Comprehensive Tests:
1. `DatabaseRecoveryTests`:
   - "Auto-recovery from backup when primary database is corrupt"
   - "Integrity check detects corruption"
   - "Fresh database creates on missing file"

2. `CLIIntegrationTests`:
   - "Data persists after headless launch"
   - "Rapid successive CLI launches do not corrupt database"
   - "CLI launch with --launch does not lose library data"

3. `LoadPerformanceTests`:
   - "Load 1000 ROMs in < 100ms"
   - "WAL mode is active"

4. `FullIntegrationTests`:
   - "Complete lifecycle: create, update, delete, restart, verify"
   - "Special characters in ROM paths handled correctly"
   - "Empty library handled gracefully"

## Success Criteria
- All 100+ tests pass
- Zero `UserDefaults.standard` usage for app data
- Database corruption recovery works
- CLI scenarios work reliably
- Performance within acceptable bounds
- Clean codebase with no dead legacy code

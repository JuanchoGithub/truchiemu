# Implementation Plan: Isolated Folder Refresh

[Overview]
Refactor the `refreshFolder` function in `ROMLibrary.swift` to be truly isolated — only adding new games and removing deleted ones without re-identifying existing games, downloading DATs, triggering automation, or touching games from other folders.

The current `refreshFolder` calls `ROMScanner.scan()` which performs full system identification on **every** file in the folder, including games already in the library. This causes unnecessary MAME lookups, DAT downloads for all detected systems, boxart preloading for the entire library, and identification of games from other folders. The fix requires creating a new lightweight scanning approach that compares file paths first and only identifies genuinely new files.

[Types]
No new types are required. The existing `ROM`, `ROMScanner`, and `ROMLibrary` types will be used with modified method signatures.

New method signature to add to `ROMScanner`:
```swift
/// Returns file paths in a folder that look like ROM files (skips non-ROM extensions).
/// Lightweight scan for refresh operations — no system identification performed.
func getROMFiles(in folder: URL, progress: @escaping (Double) -> Void) async -> [URL]
```

[Files]
**New files:**
- None

**Modified files:**
- `TruchieEmu/Services/ROMLibrary.swift` — Rewrite `refreshFolder(at:)` to path-first comparison
- `TruchieEmu/Services/ROMScanner.swift` — Add `getROMFiles()` lightweight method
- `TruchieEmu/Views/Settings/SettingsView.swift` — Verify Refresh button calls correct function (already correct for subfolders)

**Deleted files:**
- None

**Configuration file updates:**
- None

[Functions]
**New functions:**

1. `ROMScanner.getROMFiles(in:progress:)` 
   - File: `TruchieEmu/Services/ROMScanner.swift`
   - Purpose: Lightweight file enumeration that only checks if files look like ROMs (extension-based filtering), returning just the URLs without any system identification, MAME lookups, or metadata loading
   - Signature: `func getROMFiles(in folder: URL, progress: @escaping (Double) -> Void) async -> [URL]`

**Modified functions:**

1. `ROMLibrary.refreshFolder(at:)` — Complete rewrite
   - File: `TruchieEmu/Services/ROMLibrary.swift` (lines 1140-1214)
   - Current behavior: Calls `ROMScanner.scan()` which identifies EVERY file, then compares paths
   - New behavior:
     1. Get existing ROMs for target folder (by path)
     2. Call new `ROMScanner.getROMFiles()` to get just file paths (no identification)
     3. Compare paths: find new files (not in library) and deleted files (in library but not on disk)
     4. For NEW files only: call `ROMScanner.scan(urls:)` to identify them, then add to library
     5. For DELETED files only: remove from library, SwiftData, and metadata store
     6. NO DAT downloads, NO automation, NO re-persisting all ROMs, NO boxart preloading

2. `ROMScanner.scan(urls:)` — Already exists, keep as-is
   - File: `TruchieEmu/Services/ROMScanner.swift` (line 810)
   - Purpose: Used to identify only genuinely new files during refresh

**Removed functions:**
- None

[Classes]
No class modifications required. The `ROMLibrary` and `ROMScanner` classes remain the same; only method implementations change.

[Dependencies]
No new dependencies or version changes.

[Testing]
Manual testing required:
1. Add a folder with 2 games to library
2. Delete one game from disk
3. Add a new game file to disk
4. Click REFRESH on the folder
5. Verify: only 1 game removed, only 1 game added, no DAT downloads logged, no identification logs for existing games, no boxart preloading for other folders

Existing test files that may need updates:
- `TruchieEmuTests/Services/ROMIdentifierServiceTests.swift` — No changes needed (refresh doesn't touch this)
- No new unit test files required at this time

[Implementation Order]
1. Add `ROMScanner.getROMFiles()` method to `ROMScanner.swift`
2. Rewrite `ROMLibrary.refreshFolder(at:)` to use path-first comparison
3. Verify build compiles
4. Test with user-provided scenario (2-game DOS folder
# Implementation Plan: RetroAchievements, Cheats, ZIP Routing & BIOS Management

## Project Overview

This plan covers the implementation of four major feature sets for TruchieEmu:

1. **Smart ZIP Identification & Routing** (Doc #11) - Fix ZIP file detection for MAME, DOSBox, ScummVM
2. **MAME BIOS Management & UI Filtering** (Doc #12) - Hide BIOS files from game lists
3. **RetroAchievements Integration** (Doc #07) - Achievement tracking system
4. **Cheat Code Subsystem** (Doc #08) - Cheat code parsing and injection

The plan is organized into 5 milestones with incremental development, compilation verification, and testing at each stage.

---

## Sprint Overview

| Sprint | Milestone | Focus Area | Estimated Complexity | Status |
|--------|-----------|------------|---------------------|--------|
| S1 | M1 | BIOS Management & UI Filtering | Medium | ✅ COMPLETE |
| S2 | M2 | Smart ZIP Identification & Routing | High | ✅ COMPLETE |
| S3 | M3 | Cheat Code Subsystem (Basic) | Medium | ✅ COMPLETE |
| S4 | M4 | Cheat Code Subsystem (Advanced) | Medium | ✅ COMPLETE |
| S5 | M5 | RetroAchievements Core Integration | High | ✅ COMPLETE |
| S6 | M6 | RetroAchievements Settings UI | Medium | ✅ COMPLETE |
| S7 | M7 | Achievement Toast + List Views | High | ⏳ PENDING |
| S8 | M8 | Hardcore Mode + Cheat Integration | High | ⏳ PENDING |
| S9 | M9 | Missing Pieces & Polish | Medium | ⏳ PENDING |

---

## MILESTONE 1: MAME BIOS Management & UI Filtering

**Goal:** Prevent BIOS files from appearing as playable games while ensuring emulators can still find them.

### Task 1.1: Known BIOS Database

**File**: `TruchieEmu/Models/SystemInfo.swift`

Add a hardcoded BIOS list to `SystemDatabase`:

```swift
static let knownMameBiosFiles: Set<String> = [
    "neogeo", "cpzn1", "cpzn2", "cvs", "decocass", "konamigx",
    "nmk004", "pgm", "playch10", "skns", "stvbios", "vmax3",
    "eeprom", "f355dlx", "gaelco", "gaelco2", "gq863", "isgsm",
    "itoch3", "midssio", "nba99hsk", "nscd15", "ssv", "ym2608",
    "coh1000c", "coh3002c", "ym2413", "cchip", "sprc2kb", "segas16b",
    "skimaxx", "cworld", "k054539", "n64sound"
]
```

### Task 1.2: Update ROM Model with BIOS Flag

**File**: `TruchieEmu/Models/ROM.swift`

Add fields to `ROM` struct:
```swift
var isBios: Bool = false
var isHidden: Bool = false
var category: String = "game"  // "game", "bios", "system"
```

### Task 1.3: BIOS Detection in ROMScanner

**File**: `TruchieEmu/Services/ROMScanner.swift`

Add BIOS detection method in `identifySystem`:
```swift
private func isKnownBios(filename: String) -> Bool {
    let nameWithoutExt = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent.lowercased()
    return SystemDatabase.knownMameBiosFiles.contains(nameWithoutExt)
}
```

Update scan loop to mark BIOS files:
- Check `isKnownBios(filename)` for ZIP files
- Set `rom.isBios = true`, `rom.isHidden = true`, `rom.category = "bios"`

### Task 1.4: UI Filtering for BIOS Files

**Files**: 
- `TruchieEmu/Views/Library/LibraryGridView.swift`
- `TruchieEmu/Views/Library/SystemSidebarView.swift`

- Filter out `isHidden == true` ROMs from game list
- Add setting: `showBiosFiles` in `SystemPreferences`
- Add toggle in Settings: "Show BIOS Files in Game List" (Default: Off)

### Task 1.5: BIOS Path Resolution for Cores

**File**: `TruchieEmu/Engine/LibretroBridge.mm`

Update `RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY` to return proper BIOS path:
- Default: `~/Library/Application Support/TruchieEmu/System/`
- Ensure directory exists and is accessible

### Task 1.6: Skip BoxArt for BIOS Files

**File**: `TruchieEmu/Services/BoxArtService.swift`

- Skip thumbnail resolution for ROMs where `isBios == true`

### Milestone 1 Verification

- [ ] Compile project - resolve any warnings
- [ ] Test: Known BIOS files (neogeo.zip, pgm.zip) are hidden from game list
- [ ] Test: Toggle "Show BIOS Files" reveals them
- [ ] Test: ROMs that are NOT BIOS still appear normally
- [ ] Test: Parent/clone games (e.g., pacman_japanese.zip) are NOT hidden

---

## MILESTONE 2: Smart ZIP Identification & Routing

**Goal:** Correctly route ZIP files to MAME, DOSBox, ScummVM based on content and context.

### Task 2.1: Sega 32X System Addition

**File**: `TruchieEmu/Models/SystemInfo.swift`

Add 32X to SystemDatabase:
```swift
SystemInfo(id: "32x", name: "Sega 32X", manufacturer: "Sega", 
    extensions: ["32x", "smd", "bin", "md"], 
    defaultCoreID: "picodrive_libretro",
    iconName: "gamecontroller.fill", emuIconName: "32X",
    year: "1994", sortOrder: 15, defaultBoxType: .vertical),
```

### Task 2.2: Improved 32X ROM Detection

**File**: `TruchieEmu/Services/ROMScanner.swift`

32X ROMs have specific signatures:
- 32X header at offset 0x100: "SEGA 32X" 
- Standard Genesis header may also be present (fallback check needed)

Update `peekHeader` method:
```swift
// Check Sega 32X (at 0x100) - "SEGA 32X"
let _32xMagic = "SEGA 32X"
if data.count >= 0x100 + _32xMagic.count {
    let slice = data[0x100..<0x100 + _32xMagic.count]
    if let str = String(data: slice, encoding: .ascii), str == _32xMagic {
        return "32x"
    }
}
```

### Task 2.3: Multi-Tier Detection Strategy

**File**: `TruchieEmu/Services/ROMScanner.swift`

Implement priority-based identification in `identifyArchive`:

```
Priority Order:
1. Path-Based Context (folder name)
2. Content Fingerprinting (ZIP header inspection)
3. Known BIOS Database (exclusion)
4. Extension-based fallback
```

Update `identifyArchive` method with tiered approach:

```swift
private func identifyArchive(url: URL) -> SystemInfo? {
    // TIER 1: Path-based context
    let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
    
    if parentName.contains("mame") || parentName.contains("arcade") || parentName.contains("fba") || parentName.contains("fbneo") {
        return SystemDatabase.system(forID: "mame")
    }
    if parentName.contains("dos") || parentName.contains("dosbox") || parentName.contains("pc") {
        return SystemDatabase.system(forID: "dos")
    }
    if parentName.contains("scummvm") || parentName.contains("scumm") {
        return SystemDatabase.system(forID: "scummvm")
    }
    if parentName.contains("32x") {
        return SystemDatabase.system(forID: "32x")
    }

    // TIER 2: Check BIOS first (exclusion)
    if isKnownBios(filename: url.lastPathComponent) {
        return nil  // BIOS - will be handled separately
    }

    // TIER 3: Content fingerprinting
    if let detected = fingerprintArchive(url: url) {
        return detected
    }

    // TIER 4: Default to MAME for ambiguous ZIPs
    return SystemDatabase.system(forID: "mame")
}
```

### Task 2.4: Content Fingerprinting

**File**: `TruchieEmu/Services/ROMScanner.swift`

Add `fingerprintArchive` method for deep inspection:

```swift
private func fingerprintArchive(url: URL) -> SystemInfo? {
    guard let files = peekInsideZipFiles(url: url) else { return nil }
    
    // Check for console ROM extensions inside ZIP
    let consoleExts = ["nes", "sfc", "smc", "md", "gen", "smd", "gb", "gbc", "gba", "sms", "gg", "32x"]
    for file in files {
        let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
        if consoleExts.contains(ext) {
            return SystemDatabase.system(forExtension: ext)
        }
    }
    
    // Check for DOS executables
    let dosExts = ["exe", "com", "bat", "conf", "ins"]
    if files.contains(where: { dosExts.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
        return SystemDatabase.system(forID: "dos")
    }
    
    // Check for ScummVM indicators
    let scummExts = ["sou", "000", "001", "flac", "wav"]  // Common ScummVM data files
    let scummIndicators = ["HE", "MI", "SAM", "DAY", "DIG", "TENTACLE", "COMI"]
    for file in files {
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent.uppercased()
        if scummIndicators.contains(where: { name.contains($0) }) {
            return SystemDatabase.system(forID: "scummvm")
        }
        if scummExts.contains(URL(fileURLWithPath: file).pathExtension.lowercased()) {
            return SystemDatabase.system(forID: "scummvm")
        }
    }
    
    // Check for MAME-style naming (short cryptic 8-char filenames, .bin files)
    let isMameStyle = files.allSatisfy { file in
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
        return (name.count <= 15 && ext.isEmpty) || ext == "bin" || ext == "rom"
    }
    if isMameStyle && files.count > 1 {
        return SystemDatabase.system(forID: "mame")
    }
    
    return nil
}
```

### Task 2.5: Enhanced ZIP Header Parser

**File**: `TruchieEmu/Services/ROMScanner.swift`

Update `peekInsideZipAllExtensions` to return full file list instead of just extensions:

```swift
private func peekInsideZipFiles(url: URL) -> [String]? {
    // Similar to peekInsideZipAllExtensions but returns filenames
    // Limit to first 50 entries to avoid scanning huge ZIPs
}
```

### Task 2.6: Add ScummVM System Definition

**File**: `TruchieEmu/Models/SystemInfo.swift`

Add ScummVM to SystemDatabase:
```swift
SystemInfo(id: "scummvm", name: "ScummVM", manufacturer: "Various", 
    extensions: ["zip", "scummvm"], 
    defaultCoreID: "scummvm_libretro",
    iconName: "gamecontroller", emuIconName: "SCUMMVM",
    year: nil, sortOrder: 75, defaultBoxType: .landscape),
```

### Task 2.7: Ambiguity Resolver UI

**File**: `TruchieEmu/Views/Detail/GameDetailView.swift`

- Add "Change Default Core" option in game context menu
- Store core overrides in `LibraryMetadataStore`
- Add prompt for ambiguous ZIPs (one-time)

### Task 2.8: ISO/CUE File System Verification

**File**: `TruchieEmu/Services/ROMScanner.swift`

For `.iso`, `.cue`, `.img` files, verify what system they belong to BEFORE distributing to systems:

```swift
private func identifyISOFile(url: URL) -> SystemInfo? {
    let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
    
    // Path context takes priority
    if parentName.contains("psx") || parentName.contains("playstation") {
        return SystemDatabase.system(forID: "psx")
    }
    if parentName.contains("saturn") {
        return SystemDatabase.system(forID: "saturn")
    }
    if parentName.contains("ps2") {
        return SystemDatabase.system(forID: "ps2")
    }
    if parentName.contains("psp") {
        return SystemDatabase.system(forID: "psp")
    }
    
    // Header detection for ISO files
    if url.pathExtension.lowercased() == "iso" || url.pathExtension.lowercased() == "bin" {
        if let systemID = peekSystemID(url: url) {
            return SystemDatabase.system(forID: systemID)
        }
    }
    
    // CUE file detection
    if url.pathExtension.lowercased() == "cue" {
        if let referenced = getReferencedFiles(in: url).first {
            if let systemID = peekSystemID(url: referenced) {
                return SystemDatabase.system(forID: systemID)
            }
        }
        // Fallback to folder context
        return nil
    }
    
    // CUE tracks always belong to the system determined by context
    if url.pathExtension.lowercased() == "bin" {
        let folder = url.deletingLastPathComponent()
        let hasCue = FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .contains { $0.pathExtension.lowercased() == "cue" }
        if hasCue {
            // BIN files referenced by CUE should be skipped (handled by peekSystemID via CUE)
            return nil
        }
        // Standalone BIN - try header detection
        if let systemID = peekSystemID(url: url) {
            return SystemDatabase.system(forID: systemID)
        }
        // Fallback context-based
        if parentName.contains("psx") || parentName.contains("playstation") {
            return SystemDatabase.system(forID: "psx")
        }
    }
    
    // Default: use extension matching
    return SystemDatabase.system(forExtension: url.pathExtension.lowercased())
}
```

### Task 2.9: Update scan loop to use ISO identification

**File**: `TruchieEmu/Services/ROMScanner.swift`

In the `scan` method, update system identification call:

```swift
// For ISO/bin/cue/img files, use special identification
if ["iso", "cue", "img", "bin"].contains(ext) {
    system = identifyISOFile(url: url)
} else {
    system = identifySystem(url: url, extension: ext)
}
```

### Milestone 2 Verification

- [ ] Compile project - resolve any warnings
- [ ] Test: ZIP in `/dos/` folder → assigned to DOSBox-Pure
- [ ] Test: ZIP containing `.exe` → assigned to DOS
- [ ] Test: ZIP containing ScummVM data files → assigned to ScummVM
- [ ] Test: ZIP with standard console ROM inside → assigned to correct console
- [ ] Test: 32X ROMs correctly identified (header check + folder context + .32x extension)
- [ ] Test: ISO/CUE files assigned to correct system by header inspection
- [ ] Test: `neogeo.zip` is HIDDEN (not assigned as playable game)
- [ ] Test: ISO/CUE in `/psx/` folder → assigned to PlayStation
- [ ] Test: ISO/CUE in `/saturn/` folder → assigned to Saturn
- [ ] Test: BIN files referenced by CUE are skipped (not double-counted)

---

## MILESTONE 3: Cheat Code Subsystem (Basic)

**Goal:** Implement basic cheat code loading, parsing, and injection.

### Task 3.1: Cheat Data Structures

**New File**: `TruchieEmu/Models/Cheat.swift`

```swift
struct Cheat: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var index: Int
    var description: String
    var code: String
    var enabled: Bool = false
    var format: CheatFormat = .raw
}

enum CheatFormat: String, Codable {
    case raw         // Raw hex (7E0DBE05)
    case gameGenie   // Game Genie (for NES, SNES)
    case par         // Pro Action Replay (SNES/Genesis)
    case gameshark   // GameShark (PS1/N64)
}
```

### Task 3.2: Cheat Parser

**New File**: `TruchieEmu/Services/CheatParser.swift`

Parse `.cht` files (RetroArch format):
```swift
class CheatParser {
    static func parseChtFile(url: URL) -> [Cheat] {
        // Parse key-value format
        // Extract cheat0_desc, cheat0_code, cheat0_enable, etc.
    }
    
    static func parseChtContent(_ content: String) -> [Cheat] {
        // Handle multi-cheat files
    }
}
```

### Task 3.3: Cheat File Auto-Loading

**File**: `TruchieEmu/Services/ROMLibrary.swift`

- Auto-load cheat files matching ROM filename
- Search directories:
  - Same folder as ROM
  - `assets/cheats/[SystemName]/`
  - `system/cheats/`

### Task 3.4: Core Integration - Direct Memory Injection

**File**: `TruchieEmu/Engine/LibretroBridge.mm`

Add cheat management to bridge:
```objc
+ (void)setCheatEnabled:(int)index code:(NSString *)code enabled:(BOOL)enabled {
    // Store cheat state
    // Call retro_cheat_set if available
}

+ (void)resetCheats {
    // Call retro_cheat_reset
}

// For direct memory access:
+ (void *)getMemoryData:(enum retro_memory_type)type {
    // Call retro_get_memory_data
}
```

### Task 3.5: Cheat Manager UI

**New File**: `TruchieEmu/Views/Player/CheatManagerView.swift`

- List of cheats with toggle switches
- "Apply Cheats" button
- "Add Custom Code" text input
- Search/filter functionality
- Load from `.cht` file option

### Task 3.6: Persistent Cheat State

**File**: `TruchieEmu/Services/LibraryMetadataStore.swift`

- Save enabled cheats per ROM
- Load on game restart

### Milestone 3 Verification

- [ ] Compile project - resolve any warnings  
- [ ] Test: .cht file parsed correctly
- [ ] Test: Cheat toggles appear in game menu
- [ ] Test: "Apply Cheats" sends codes to core
- [ ] Test: Cheat state persists after relaunch

---

## MILESTONE 4: Cheat Advanced + RetroAchievements Core

**Goal:** Complete cheat system with format converters and begin RetroAchievements integration.

### Task 4.1: Cheat Format Converters

**File**: `TruchieEmu/Services/CheatParser.swift`

Add decoders for:
- Game Genie (NES): 6-character codes with check digit
- Game Genie (SNES): 8-character codes
- Pro Action Replay: 8-digit hex format
- GameShark: 8-digit hex with device code

### Task 4.2: RetroAchievements rcheevos Integration

**New File**: `TruchieEmu/Engine/RetroAchievementsBridge.h`
**New File**: `TruchieEmu/Engine/RetroAchievementsBridge.mm`

Bridge for rcheevos library:
```objc
@interface RetroAchievementsBridge : NSObject
+ (void)initialize;
+ (BOOL)loginWithUser:(NSString *)user token:(NSString *)token;
+ (BOOL)identifyGameWithHash:(NSString *)hash;
+ (void)processFrame;
+ (NSString *)getRichPresence;
@end
```

### Task 4.3: Memory Access Callback

**File**: `TruchieEmu/Engine/RetroAchievementsBridge.mm`

Implement `rc_client_read_memory` callback:
- Bridge to `retro_get_memory_data` for RAM access
- Support both SYSTEM_RAM and SAVE_RAM

### Task 4.4: Game Hash Generation

**File**: `TruchieEmu/Services/ROMIdentifierService.swift`

Add RetroAchievements-specific hash generation:
```swift
func generateRAHash(for url: URL, systemID: String) -> String? {
    // RA uses specific hashing rules per system
    // Different from No-Intro CRC32
    // Use libretro-common's rc_hash_generate equivalent
}
```

### Task 4.5: Settings UI for RetroAchievements

**File**: `TruchieEmu/Views/Settings/SettingsView.swift`

Add section:
- Username field
- API Token field (never store password)
- Hardcore Mode toggle
- Enable/Disable toggle

### Task 4.6: Achievement Event Handling

**File**: `TruchieEmu/Engine/LibretroBridge.mm`

Update runtime loop to call `rc_client_do_frame()`:
- Integrate with `retro_run()` calls

### Milestone 4 Verification

- [ ] Compile project - resolve any warnings
- [ ] Test: Game Genie codes correctly converted
- [ ] Test: Login to RetroAchievements API
- [ ] Test: Game hash identifies correctly
- [ ] Test: Hardcore mode toggle enables/disables save states

---

## MILESTONE 5: RetroAchievements UI + Leaderboards

**Goal:** Complete achievement tracking with visual feedback and leaderboard support.

### Task 5.1: Achievement Data Models

**New File**: `TruchieEmu/Models/Achievement.swift`

```swift
struct Achievement: Identifiable, Codable, Hashable {
    var id: Int          // RA achievement ID
    var title: String
    var description: String
    var points: Int
    var badgeUrl: URL
    var isUnlocked: Bool
    var unlockDate: Date?
    var isHardcore: Bool
}

struct LeaderboardEntry: Identifiable {
    var id: UUID = UUID()
    var title: String
    var format: String
    var lowerIsBetter: Bool
}
```

### Task 5.2: Achievement Toast Notifications

**New File**: `TruchieEmu/Views/Player/AchievementToastView.swift`

- Slide-in notification (bottom-center or top-right)
- Display: Icon, Title, Points value
- Play iconic unlock sound

### Task 5.3: Achievement List Menu

**New File**: `TruchieEmu/Views/Player/AchievementListView.swift`

- Accessible while game is paused
- List all achievements
- Grey out locked, full color unlocked
- Show Hardcore Mode status

### Task 5.4: Rich Presence Integration

**File**: `TruchieEmu/Services/RetroAchievementsBridge.mm`

- Implement `rc_client_get_rich_presence()`
- Update frontend activity status
- Optional: Discord Rich Presence

### Task 5.5: Offline Mode & Caching

**File**: `TruchieEmu/Services/RetroAchievementsCache.swift`

- Cache achievement definitions locally
- Queue pending unlocks for offline play
- Sync on next online launch

### Task 5.6: Hardcore Mode Enforcement

**File**: `TruchieEmu/Engine/LibretroBridge.mm`

When Hardcore Mode is enabled:
- Block Save States
- Block Rewind
- Block Slow Motion
- Block Cheats
- If user uses any forbidden feature, drop to Softcore

### Task 5.7: Leaderboard Implementation

**New File**: `TruchieEmu/Views/Player/LeaderboardView.swift`

- Display active leaderboards
- Show rank and submission notification
- Track start/end conditions

### Milestone 5 Verification

- [ ] Compile project - resolve any warnings
- [ ] Test: Achievement toast appears on unlock
- [ ] Test: Achievement list shows correct state
- [ ] Test: Offline queue works
- [ ] Test: Hardcore mode blocks save states
- [ ] Test: Leaderboard submission displays rank
- [ ] Test: Rich Presence updates correctly

---

## File Changes Summary

### New Files to Create

| File | Milestone | Purpose |
|------|-----------|---------|
| `TruchieEmu/Models/Cheat.swift` | M3 | Cheat data structures |
| `TruchieEmu/Services/CheatParser.swift` | M3 | Parse .cht files |
| `TruchieEmu/Views/Player/CheatManagerView.swift` | M3 | Cheat UI |
| `TruchieEmu/Models/Achievement.swift` | M5 | Achievement data structures |
| `TruchieEmu/Engine/RetroAchievementsBridge.h` | M4 | rcheevos bridge header |
| `TruchieEmu/Engine/RetroAchievementsBridge.mm` | M4 | rcheevos bridge impl |
| `TruchieEmu/Views/Player/AchievementToastView.swift` | M5 | Unlock notification |
| `TruchieEmu/Views/Player/AchievementListView.swift` | M5 | Achievement list |
| `TruchieEmu/Views/Player/LeaderboardView.swift` | M5 | Leaderboard UI |
| `TruchieEmu/Services/RetroAchievementsCache.swift` | M5 | Offline caching |

### Files to Modify

| File | Milestone | Changes |
|------|-----------|---------|
| `TruchieEmu/Models/SystemInfo.swift` | M1, M2 | Add BIOS list, 32X system, ScummVM system |
| `TruchieEmu/Models/ROM.swift` | M1 | Add isBios, isHidden, category fields |
| `TruchieEmu/Services/ROMScanner.swift` | M1, M2 | BIOS detection, improved ZIP routing, 32X detection, ISO verification |
| `TruchieEmu/Views/Library/LibraryGridView.swift` | M1 | Filter BIOS files |
| `TruchieEmu/Views/Library/SystemSidebarView.swift` | M1 | BIOS toggle |
| `TruchieEmu/Views/Detail/GameDetailView.swift` | M2 | Core picker, override menu |
| `TruchieEmu/Views/Settings/SettingsView.swift` | M4 | RetroAchievements credentials |
| `TruchieEmu/Engine/LibretroBridge.mm` | M1, M3, M4 | BIOS path, cheats, RA frame processing |
| `TruchieEmu/Services/ROMLibrary.swift` | M3 | Cheat auto-loading |
| `TruchieEmu/Services/LibraryMetadataStore.swift` | M2, M3 | Core overrides, cheat persistence |

---

## Dependencies & Prerequisites

### External Libraries Needed

1. **rcheevos** - RetroAchievements client library
   - Clone from: https://github.com/RetroAchievements/rcheevos
   - Compile as static library or include source files
   
2. **libzip or miniz** - ZIP header reading (optional, current peekInsideZip may suffice)

3. **RetroAchievement unlock sound** - .wav file for toast notification

### Existing Code Dependencies

- CRC32 computation (already implemented in ROMIdentifierService)
- Game hash generation (need RA-specific variant)

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| 32X header detection false positives | Medium | Use multiple verification points |
| ZIP fingerprinting performance | Medium | Limit entries scanned, use caching |
| rcheevos library integration | High | Start with mock, test incrementally |
| Cheat memory injection crashes | High | Validate addresses, use try-catch |
| RetroAchievements API rate limiting | Low | Cache definitions, implement retry logic |

---

## Success Criteria

1. **ZIP Routing**: 
   - 95%+ accuracy for ZIP classification
   - No BIOS files appearing as playable games
   
2. **32X Detection**:
   - All valid 32X ROMs correctly identified
   - No false positives for Genesis ROMs
   
3. **ISO/CUE Verification**:
   - ISO files assigned to correct system by header detection
   - CUE/BIN pairs handled without duplication
   
4. **Cheats**:
   - .cht files parsed correctly
   - Codes applied successfully in supported cores
   
5. **RetroAchievements**:
   - Successful login and game identification
   - Achievement unlocks trigger toast notification
   - Hardcore mode blocks forbidden features

---

## MILESTONE 7: Missing Pieces & Polish

**Goal:** Address items identified during review that were not covered in earlier milestones.

### Task 7.1: ISO/CUE Path-Based Context Enhancement

**File**: `TruchieEmu/Services/ROMScanner.swift`

The current `peekSystemID` handles header detection for ISO/CUE files. However, we need to add explicit path-based context for CD-based systems:

```swift
// Add to identifySystem() for CD-based extensions
if ["iso", "cue", "img", "bin", "chd"].contains(ext) {
    let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
    let grandParentName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent.lowercased()
    
    // Check parent and grandparent folder names
    for folderName in [parentName, grandParentName] {
        if folderName.contains("psx") || folderName.contains("playstation") || folderName.contains("ps1") {
            return SystemDatabase.system(forID: "psx")
        }
        if folderName.contains("saturn") {
            return SystemDatabase.system(forID: "saturn")
        }
        if folderName.contains("ps2") || folderName.contains("playstation2") {
            return SystemDatabase.system(forID: "ps2")
        }
        if folderName.contains("psp") {
            return SystemDatabase.system(forID: "psp")
        }
        if folderName.contains("dreamcast") || folderName.contains("dc") {
            return SystemDatabase.system(forID: "dreamcast")
        }
        if folderName.contains("3do") {
            return SystemDatabase.system(forID: "3do")
        }
    }
}
```

### Task 7.2: Add 3DO System Definition

**File**: `TruchieEmu/Models/SystemInfo.swift`

```swift
SystemInfo(id: "3do", name: "3DO", manufacturer: "Panasonic/Sanyo/Goldstar", 
    extensions: ["iso", "bin", "cue", "chd"], 
    defaultCoreID: "opera_libretro",
    iconName: "opticaldisc", emuIconName: "3DO",
    year: "1993", sortOrder: 25, defaultBoxType: .landscape),
```

### Task 7.3: Core Picker UI for Ambiguous Files

**File**: `TruchieEmu/Views/Detail/GameDetailView.swift`

- Add "Change Core" option in context menu
- Show available cores for the ROM's system
- Store selection in `ROM.useCustomCore` and `ROM.selectedCoreID`

### Task 7.4: Cheat Auto-Loading from ROM Folder

**File**: `TruchieEmu/Services/ROMLibrary.swift` or `CheatManager.swift`

- On ROM load, check for `.cht` file with same name in ROM folder
- Auto-load if found
- Check `system/cheats/[SystemName]/` folder

### Task 7.5: ScummVM .scummvm File Auto-Generation

**File**: `TruchieEmu/Services/ROMScanner.swift`

When a ZIP is identified as ScummVM:
- Check if `.scummvm` file exists inside
- If not, auto-generate a temporary one
- Pass correct path to core

### Task 7.6: BIOS System Directory Configuration

**File**: `TruchieEmu/Views/Settings/SettingsView.swift`

- Add setting for custom BIOS/system directory
- Default: `~/Library/Application Support/TruchieEmu/System/`
- Pass to core via `RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY`

### Task 7.7: Integration of CheatManager into Game Flow

**File**: `TruchieEmu/Views/Player/EmulatorView.swift` or HUD

- Add "Cheats" button to in-game HUD
- Open `CheatManagerView` as sheet
- Auto-apply cheats when game launches (if any enabled)

### Milestone 7 Verification

- [ ] Compile project - resolve any warnings
- [ ] Test: ISO in `/psx/` folder → assigned to PlayStation
- [ ] Test: ISO in `/saturn/` folder → assigned to Saturn
- [ ] Test: CUE/BIN pairs correctly handled
- [ ] Test: 3DO system appears and works
- [ ] Test: Core picker changes core for a game
- [ ] Test: Cheats auto-load from ROM folder
- [ ] Test: Cheats accessible from in-game HUD

---

## Post-Implementation Review

After all milestones complete:

1. Review code for any compiler warnings
2. Test all feature combinations (cheats + hardcore mode, etc.)
3. Verify no regressions in existing functionality
4. Check performance impact of ZIP fingerprinting
5. Validate BIOS filtering doesn't accidentally hide games
6. Test edge cases: corrupted ZIPs, invalid .cht files, offline RA mode

---

## Implementation Status Summary

### Completed (Milestones 1-6)
- ✅ BIOS detection and filtering (60+ known BIOS files)
- ✅ Sega 32X system and ROM detection
- ✅ ScummVM system definition
- ✅ Multi-tier ZIP identification (path, content, BIOS exclusion, fallback)
- ✅ ZIP content fingerprinting (DOS, ScummVM, MAME, console ROMs)
- ✅ CUE/BIN pair handling (skip referenced BIN files)
- ✅ ISO header detection (Saturn, PS1, 32X, Genesis)
- ✅ Cheat code parser (.cht files)
- ✅ Cheat manager UI
- ✅ Cheat persistence
- ✅ Libretro bridge for cheat injection
- ✅ Cheat format converters (Game Genie NES/SNES, PAR, GameShark)
- ✅ Direct memory injection for cheats
- ✅ Memory access bridge (getMemoryData, writeMemoryByte)
- ✅ RetroAchievements Service (API integration, authentication, game identification)
- ✅ Achievement data models (Achievement, RAGameInfo, Leaderboard, RAUserInfo)
- ✅ RetroAchievements Settings UI (login, hardcore toggle, status display)

### Pending (Milestones 7-9)
- ⏳ Achievement toast notifications
- ⏳ Achievement list view
- ⏳ Leaderboard support
- ⏳ Hardcore mode enforcement (block save states/rewind/cheats)
- ⏳ Cheat auto-loading from ROM folder
- ⏳ Cheat integration in in-game HUD
- ⏳ Core picker UI
- ⏳ 3DO system support
- ⏳ ISO/CUE path-based context enhancement
- ⏳ ScummVM .scummvm file auto-generation
- ⏳ BIOS system directory configuration

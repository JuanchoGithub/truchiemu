# Save Directory Configuration Feature

## Overview
This implementation allows users to configure custom save directories for TruchiEmu, with automatic migration support when changing paths.

## Architecture

### Core Components

1. **SaveDirectoryManager** (`TruchieEmu/Services/SaveDirectoryManager.swift`)
   - Centralized manager for all save and system directory paths
   - Provides dynamic path resolution (default vs user-customized)
   - Tracks migration state
   - Observable via Combine for real-time updates

2. **SaveMigrationService** (`TruchieEmu/Services/SaveMigrationService.swift`)
   - Handles safe file migration between directories
   - Copy-then-delete strategy with verification
   - Progress tracking and error handling
   - Atomic operations with rollback capability

3. **Directory Bridge** (`TruchieEmu/Core/Engine/SaveDirectoryBridge`)
   - Objective-C bridge for accessing Swift directory manager from C/ObjC code
   - Provides paths to libretro cores via environment callbacks

4. **Settings Extensions** (`TruchieEmu/Shared/Utilities/Utilities/AppSettings.swift`)
   - Persistent storage for custom directory paths
   - Notification support for change detection

5. **UI Component** (`TruchieEmu/Views/Settings/SaveDirectorySettingsView.swift`)
   - User interface for directory configuration
   - Migration prompts and progress display
   - Directory picker using NSOpenPanel

### Modified Files

- `TruchieEmu/Core/Engine/LibretroCallbacks.mm` - Updated to use SaveDirectoryBridge for dynamic paths
- `TruchieEmu/Services/SaveStateManager.swift` - Updated to use SaveDirectoryManager for state paths
- `TruchieEmu/Core/Engine/Runners/Runners/BaseRunner.swift` - Added directory setup on launch

## Directory Structure

Application creates the following hierarchy:
```
~/Library/Application Support/TruchieEmu/saves/
├── states/          # Save states (managed by frontend)
│   └── <system>/    # System-specific subdirectories
│       └── *.state  # State files with thumbnails
└── savefiles/       # Core-managed saves (SRAM, EEPROM, etc)
    └── <system>/    # System-specific subdirectories
        └── *.sram *.eep *.save  # Core save files

~/Library/Application Support/TruchieEmu/System/
└── *.rom *.bin      # BIOS and system files
```

## User Flow

1. **Initial State**
   - Uses default locations in Application Support
   - No migration needed

2. **Change Directory**
   - User selects new directory via NSOpenPanel
   - Directory is validated for write access
   - Settings are persisted

3. **Migration Prompt**
   - If old location has files, user is prompted to migrate
   - Migration copies files then verifies
   - On success, old files are removed
   - On failure, changes are rolled back

4. **Core Access**
   - Libretro cores receive paths via RETRO_ENVIRONMENT_GET_* callbacks
   - Paths are dynamically resolved from SaveDirectoryManager

## Integration

To integrate the SaveDirectorySettingsView into the Library:

```swift
import SwiftUI

struct LibrarySettingsView: View {
    var body: some View {
        TabView {
            // ... existing tabs ...
            SaveDirectorySettingsView()
                .tabItem {
                    Label("Save Directories", systemImage: "externaldrive")
                }
        }
    }
}
```

Or add it to an existing settings form:

```swift
Form {
    // ... other settings ...
    NavigationLink("Save Directories") {
        SaveDirectorySettingsView()
    }
}
```

## Testing

To test the feature:

1. **Build Verification**
   ```bash
   xcodebuild -project TruchiEmu.xcodeproj -scheme TruchieEmu -destination 'platform=macOS' build
   ```

2. **Manual Testing**
   - Launch the app
   - Create some save states for a game
   - Go to Library Settings > Save Directories
   - Change save directory to a custom location
   - Verify migration prompt appears
   - Complete migration
   - Verify files exist in new location
   - Play game and create new save state
   - Verify new state saves to custom location

3. **Core Save Testing**
   - Load a game that creates SRAM/EEPROM saves (e.g., NES, SNES)
   - Play to generate save data
   - Navigate to custom savefiles directory
   - Verify .sram file exists

## Verification Checklist

- [ ] SaveDirectoryManager implemented
- [ ] SaveMigrationService implemented
- [ ] SaveDirectoryBridge compiles and links
- [ ] Libretro callbacks use dynamic paths
- [ ] SaveStateManager uses SaveDirectoryManager
- [ ] Settings persistence works
- [ ] UI code written
- [ ] Build passes
- [ ] UI integrated into Library settings (manual)
- [ ] Migration tested (manual)
- [ ] Core saves tested (manual)

## Future Enhancements

- Disk usage analytics
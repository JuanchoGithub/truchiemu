# Windows 98 SE Support for DOSBox Pure

## Overview

Two-phase feature that lets TruchiEmu users install and use Windows 98 SE inside DOSBox Pure, enabling Win32 game playback.

- **Phase 1 (One-time setup):** Download Win98 SE ISO + boot floppy from archive.org, create `Install_Win98SE.zip`, launch it with DOSBox Pure to run the OS installer. Provide a hybrid "Type Product Key" button in the toolbar that displays the OEM key and auto-types it when pressed.
- **Phase 2 (Ongoing):** Detect `Windows 98.img` in system directory. When launching Win32 games, DOSBox Pure auto-detects the installed OS and offers "Run Installed Operating System".

---

## New File: `TruchiEmu/Services/Win98SetupManager.swift`

**Purpose:** Singleton service managing the download, ZIP creation, and installation state tracking.

**Key properties:**

- `@Published var downloadPhase: Win98DownloadPhase` (idle/downloading/creatingZip/ready/installing/installed/error)
- `@Published var downloadProgress: Double`
- `@Published var oemKey: String` — the key to display/autotype
- `static let shared = Win98SetupManager()`

**Key methods:**

### `isWin98Installed() -> Bool`

- Checks `SaveDirectoryManager.shared.systemDirectory` for `Windows 98.img`
- Simple `FileManager.fileExists` check

### `downloadAndPrepareInstaller(completion:)`

- Downloads ISO from: `https://archive.org/download/microsoft-windows-98-second-edition-oem-x05-29232/Microsoft%20Windows%2098%20Second%20Edition%20OEM%20%5BX05-29232%5D.iso` (625MB)
- Downloads boot floppy from: `https://archive.org/download/microsoft-windows-98-second-edition-oem-x05-29232/Microsoft%20Windows%2098%20Second%20Edition%20Boot%20Disk%20%5BX04-80322%5D.img` (1.4MB)
- Uses `URLSession.downloadTask` with progress observation (same pattern as `CoreManager.downloadCore()`)
- Verifies SHA256 checksums after download (from archive.org metadata):
  - ISO SHA256: `2adfb46df8a9c7bbd2f67bff07461cc2f9d9ec8e01f0e112cb044c9e3e62f607`
  - IMG SHA256: `7e98fc82295bd2a6030fc1af297d42beca181dd8d5ad96b6fda8a01a0b9f7904`
- Creates `Install_Win98SE.zip` containing both files at root level using `/usr/bin/zip` (same pattern as `BiosDownloader` uses `/usr/bin/unzip`)
- Saves ZIP to `SaveDirectoryManager.shared.systemDirectory/Install_Win98SE.zip`
- Updates `downloadPhase` through the pipeline

### `autoTypeProductKey()`

- Iterates over each character of the OEM key string
- For each character: looks up the RETROK keycode from `RetroKeycodeMapper`, dispatches key-down then key-up with 50ms delay between characters
- Handles: uppercase letters (A-Z → RETROK_a + shift modifier), digits (0-9), dash (RETROK_MINUS)
- Uses `LibretroBridgeSwift.dispatchKeyboardEvent(keycode:character:modifiers:down:)` for each keypress
- Key: `D8M2X-93TTX-6JVD3-DGF78-J67V8`

### `createInstallerROM() -> ROM?`

- Creates a synthetic `ROM` struct pointing to the `Install_Win98SE.zip` path with `systemID: "dos"`, for launching via `GameLauncher`

**Constants:**

```swift
static let oemKeyPrimary = "D8M2X-93TTX-6JVD3-DGF78-J67V8"
static let oemKeyFallback = "B8MFR-CFTGQ-C9PBW-VHG3J-3R3YW"
static let installerZipName = "Install_Win98SE.zip"
static let installedImageName = "Windows 98.img" // Created by DOSBox Pure after setup
```

---

## Modified File: `TruchiEmu/Core/Engine/Runners/Runners/DOSRunner.swift`

**Changes:**

1. Add `@MainActor @Published var isWin98InstallMode: Bool = false`
   - Set to `true` when launching the Win98 installer ZIP (Phase 1)

2. Add `@MainActor @Published var showProductKeyBanner: Bool = false`
   - Set to `true` during Win98 install so the toolbar shows the banner

3. Add computed property:

   ```swift
   var isWin98Installed: Bool {
       Win98SetupManager.shared.isWin98Installed()
   }
   ```

4. Modify `configureCoreOptions()`:
   - When `isWin98InstallMode` is true, set `dosbox_pure_memory_size` to `64 MB` (Win98 needs more than default 16MB)
   - Keep `dosbox_pure_start_menu` enabled (DOSBox Pure will show "Boot and Install New Operating System" option)

5. Modify `launch()`:
   - After `super.launch()`, if `isWin98InstallMode`, set `showProductKeyBanner = true`
   - For Phase 2 (normal Win32 game launch when Win98 is installed): DOSBox Pure auto-detects `Windows 98.img` in the system directory and adds "Run Installed Operating System" to its start menu — no special code needed from our side

---

## Modified File: `TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/GameOverlayToolbar.swift`

**Changes:**

1. Add a `Win98ProductKeyBanner` view that appears when `runner` is a `DOSRunner` with `showProductKeyBanner == true`:
   - Positioned above the toolbar (like the input capture banner)
   - Shows: "Windows 98 Setup" label + the OEM key in a monospace text field (selectable/copyable) + a "Type Key" button
   - The "Type Key" button calls `Win98SetupManager.shared.autoTypeProductKey()`
   - Also includes a "Dismiss" button to hide the banner once the key has been entered
   - Styled consistently with the existing input capture banner (dark rounded rectangle, white text)

---

## Modified File: `TruchiEmu/Features/Player/Services/GameLauncher.swift`

**Changes:**

1. In `launchGame()`, before creating the runner for `systemID == "dos"`:
   - Check if Win98 is installed via `Win98SetupManager.shared.isWin98Installed()`
   - If not installed, this is just a regular DOS game — proceed normally
   - If the user explicitly triggers "Install Windows 98" from settings (Phase 1 entry point), call `Win98SetupManager.shared.downloadAndPrepareInstaller()` then launch the installer ZIP

2. Add a Phase 1 launch path:
   - After download completes, create the installer ROM via `Win98SetupManager.shared.createInstallerROM()`
   - Set `DOSRunner.isWin98InstallMode = true` before launch
   - Launch with DOSBox Pure core

---

## Phase 2 Behavior (No Additional Code Needed)

When `Windows 98.img` exists in the system directory:

- DOSBox Pure automatically detects it and adds `[ Run Installed Operating System ]` to its start menu
- When the user loads a Win32 game ZIP, this option appears at the top of DOSBox Pure's menu
- No TruchiEmu code changes are needed for Phase 2 — it's DOSBox Pure's built-in behavior

The one useful addition: if `isWin98Installed` is true and a DOS game is launched, we could set `dosbox_pure_memory_size` to `64 MB` and `dosbox_pure_machine` to `SVGA` to ensure proper Win98 compatibility. This can be a simple check in `DOSRunner.configureCoreOptions()`.

---

## Localization Keys to Add

Add to all translation files (`en.json`, `es.json`, etc.):

```json
"win98.setupTitle": "Windows 98 Setup",
"win98.productKey": "Product Key",
"win98.typeKey": "Type Key",
"win98.dismiss": "Dismiss",
"win98.downloading": "Downloading Windows 98 SE...",
"win98.creatingInstaller": "Creating installer ZIP...",
"win98.installComplete": "Windows 98 installation complete",
"win98.notInstalled": "Windows 98 not installed"
```

---

## Execution Order

1. Create `Win98SetupManager.swift` — the core service
2. Modify `DOSRunner.swift` — add Win98 install mode + core options
3. Modify `GameOverlayToolbar.swift` — add product key banner with "Type Key" button
4. Modify `GameLauncher.swift` — add Phase 1 launch path
5. Add localization keys
6. Run `xcodegen generate` to regenerate the project

---

## Verification

1. Build: `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`
2. Test Phase 1: Trigger Win98 download → verify ZIP creation in system dir → launch installer → verify product key banner appears → click "Type Key" → verify key is dispatched to the emulated screen
3. Test Phase 2: After Win98 install + shutdown → verify `Windows 98.img` exists → launch a Win32 game ZIP → verify DOSBox Pure shows "Run Installed Operating System"

---

## Key Reference Files

| Area | File |
|---|---|
| DOS Runner | `TruchiEmu/Core/Engine/Runners/Runners/DOSRunner.swift` |
| Base Runner | `TruchiEmu/Core/Engine/Runners/Runners/BaseRunner.swift` |
| Game Launcher | `TruchiEmu/Features/Player/Services/GameLauncher.swift` |
| Overlay Toolbar | `TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/GameOverlayToolbar.swift` |
| Window Controller | `TruchiEmu/Features/Player/Views/Player/ShaderPlayerComponents/StandaloneGameWindowController.swift` |
| Bridge (Swift) | `TruchiEmu/Core/Engine/LibretroBridgeSwift.swift` |
| Bridge (Callbacks) | `TruchiEmu/Core/Engine/LibretroCallbacks.mm` |
| Save Directory | `TruchiEmu/Services/SaveDirectoryManager.swift` |
| Core Manager (download pattern) | `TruchiEmu/Services/CoreManager.swift` |
| RetroKeycodeMapper | `TruchiEmu/Core/InputCapture/RetroKeycodeMapper.swift` |
| Core Options | `TruchiEmu/Features/Settings/Services/CoreOptionsManager.swift` |
| AppSettings | `TruchiEmu/Shared/Utilities/Utilities/AppSettings.swift` |
| DOSBox Pure defaults | `TruchiEmu/Resources/CoreOverrides/dosbox_pure_libretro_default.json` |
| System Database | `TruchiEmu/Resources/Data/SystemDatabase.json` |
| Localization files | `TruchiEmu/Resources/Translations/en.json`, `es.json`, etc. |

## DOSBox Pure OS Install Flow (for reference)

### Phase 1: One-Time Windows 98 Installation

1. Create the Installer ZIP: Take the downloaded Windows 98 SE .iso file and the .img boot disk floppy file, put them together into a new zip archive named `Install_Win98SE.zip`.
2. Run the Installer: Load `Install_Win98SE.zip` as content, choose DOSBox Pure as the core.
3. Initialize the OS Creation: DOSBox Pure will detect the installer files and display `[ Boot and Install New Operating System ]`. Select it, choose a hard drive size (2GB to 4GB is ideal), and proceed.
4. Complete the Setup Wizard: The classic blue Windows 98 setup will start. Type in the product key when asked, and let it finish. Once at the desktop, shut down Windows safely (Start -> Shut Down).
5. Result: DOSBox Pure generates a standalone hard drive image file named `Windows 98.img` in the RetroArch system directory (our `SaveDirectoryManager.shared.systemDirectory`).

### Phase 2: How to Play Win32 Games From Now On

1. Keep the game zipped: Leave Windows 32 game files inside their .zip or .7z archive.
2. Load Content: Select that game's zip file.
3. DOSBox Pure sees the Win98 installation in the system folder and dynamically adds `[ Run Installed Operating System ]` to its start menu.

## Download URLs

| File | URL | Size | SHA256 |
|---|---|---|---|
| Win98 SE ISO | `https://archive.org/download/microsoft-windows-98-second-edition-oem-x05-29232/Microsoft%20Windows%2098%20Second%20Edition%20OEM%20%5BX05-29232%5D.iso` | ~625 MB | `2adfb46df8a9c7bbd2f67bff07461cc2f9d9ec8e01f0e112cb044c9e3e62f607` |
| Boot Floppy IMG | `https://archive.org/download/microsoft-windows-98-second-edition-oem-x05-29232/Microsoft%20Windows%2098%20Second%20Edition%20Boot%20Disk%20%5BX04-80322%5D.img` | ~1.4 MB | `7e98fc82295bd2a6030fc1af297d42beca181dd8d5ad96b6fda8a01a0b9f7904` |

## OEM Product Keys

- Primary: `D8M2X-93TTX-6JVD3-DGF78-J67V8`
- Fallback: `B8MFR-CFTGQ-C9PBW-VHG3J-3R3YW`

# AGENTS.md

Behavioral guidelines and project-specific instructions for working on TruchiEmu.
Report to me in ASD-STE100 Simplified Technical English.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Researching topics
When you need to research a topic or a solution, *never* try to go to URLs directly, the nature of the web today is one of shifting URLs so you will have little success doing that. Always start by searching online about the topics first and once you get the results, investigate the URLs that you find in order to research.

## Localization method

The app uses a **JSON‑based UI localization system**:
- Translation files in `Resources/Translations/`: `en.json`, `es.json`, `pt.json`
- `LocalizationManager` loads all JSON files at launch, auto-detects device language, supports runtime changes via `setLanguage(_:)`
- **IMPORTANT:** `setLanguage()` persists to `AppSettings.set("systemLanguage", value: lang)`. Without this, language resets on next app launch

### How to use localization in SwiftUI views

**For SwiftUI Section/Picker/Button titles (String parameter):**
```swift
loc.localized("settings.saveStates") // Returns String
Section(loc.localized("settings.saveStates")) { ... }
Picker(loc.localized("settings.selectLanguage"), selection: $binding) { ... }
```

**For SwiftUI Text (SwiftUI Text view):**
```swift
Text("settings.title") // Uses the Text extension, returns localized Text
```

**For confirmation dialog messages:**
```swift
.confirmationDialog(loc.localized("settings.syncAllGamesTitle"), ...) { ... }
```

**Key pattern:** Always use `loc.localized("key")` for String arguments, `Text("key")` for Text arguments.

**Footgun:** The `Text` extension overrides `init(_ localizationKey: String)`, which intercepts ALL `Text(String)` calls, not just localization keys. If you need a literal string in a Text view that isn't a localization key, use `Text(verbatim: "literal")` instead.

### Adding new translations

1. Add key to ALL language JSON files (`en.json`, `es.json`, `pt.json`) with the same key
2. Use consistent naming: `section.action` (e.g., `settings.saveStates`, `game.launch`)
3. Update views to use `loc.localized("key")` instead of hardcoded strings
4. Debug/internal messages are not translated

### Common bug to avoid

When adding a language picker that calls `setLanguage()`:
- Ensure `setLanguage()` saves to `AppSettings`, otherwise the selection is lost when the view re-renders
- The picker binding must read from `loc.currentLanguage` to show the current selection

### Dual language system

The codebase has **two separate language systems**. Do not confuse them:

| System | Class | Storage | Purpose |
|---|---|---|---|
| UI Localization | `LocalizationManager.shared` | `AppSettings["systemLanguage"]` (String: `"en"`, `"es"`, `"pt"`) | UI string translations |
| Core Language | `SystemPreferences.systemLanguage` | `AppSettings` (Int: `EmulatorLanguage` raw value) | Language passed to libretro cores via `LibretroBridge.setLanguage(Int32)` |

Changing one does NOT affect the other. `Notification.Name.languageChanged` is defined in `TruchiEmuApp.swift:17` and is posted from two sites: `LocalizationManager.setLanguage()` at `Shared/Localization/LocalizationManager.swift:106` (primary path when the settings UI calls `setLanguage` directly) and `TruchiEmuApp.swift:365` (the legacy/system-triggered path). Both must fire for SwiftUI views observing the change to refresh.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

# TruchiEmu Developer Guide

## Build System

- **XcodeGen**: Run `xcodegen generate` after any `project.yml` change to regenerate `TruchiEmu.xcodeproj`. Do not edit the `.xcodeproj` directly.
- **No project.yml edits for new files**: Sources under `TruchiEmu/` and resources under `TruchiEmu/Resources/` are auto-included via recursive paths in `project.yml`. Only edit `project.yml` if you're adding a directory that should be **excluded** from the build.
- **Build command**: `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build` for a Debug build. Use `-configuration Release` for a Release build (no `DEBUG`/`LOG_DEBUG`/`LOG_EXTREME` flags — see "Compile-time flags" below). (Or open the xcodeproj in Xcode.)
- **macOS 14.0+ and Swift 5.9** required

### Source exclusions in project.yml

The `TruchiEmu` source target excludes (matches `project.yml:88-96`):
- `TruchiEmu/Library/` (empty placeholder)
- `TruchiEmu/Resources/` (handled by resources build phase, not sources)
- `TruchiEmu/lib/` (librashader dylib lives here at runtime, not built)
- `Core/Engine/internal/**`
- `Core/Shaders/internal/**`
- `Core/Shaders/all_shaders.metal`
- `Core/XPC/Service/**` (compiled into `TruchiEmuCoreHost` target, not the app)

The `TruchiEmuCoreHost` XPC target additionally excludes (`project.yml:165-178`):
- `slang/`, `slang_shader_bridge.*`, `Runners/**`, `LibretroBridgeSwift.swift`, `Hashing/**`, `CoreOverrideBridge.mm`

### Resource build phases

- `TruchiEmu/Resources/`: includes all resources recursively, excluding `slang-shaders/**` (copied by postBuildScript instead), `Info.plist`, `TruchiEmu.entitlements`
- `scripts/mame_lookup/`: included as resources, excluding `mame_unified.json` (loaded at runtime, not bundled)

### Post-build scripts

- Copies `librashader.dylib` and `libSDL2-2.0.0.dylib` into `Contents/Frameworks` and re-signs them ad-hoc
- Copies `Resources/slang-shaders/` into the bundle preserving directory structure (necessary because the build phase flattens resources, but slang presets depend on path layout)
- Re-signs the app bundle after script copies

## Architecture

- **App entrypoint**: `TruchiEmu/App/TruchiEmuApp.swift` + `ContentView.swift`
- **Emulation engine**: `TruchiEmu/Core/Engine/` (mixed Objective-C++/C with a Swift bridging header `TruchiEmu-Bridging-Header.h`). Hosts libretro core integration.
- **Swift<->ObjC bridge**: `LibretroBridge.mm` / `LibretroBridgeSwift.swift` for calling libretro from Swift
- **XPC service layer**: `TruchiEmu/Core/XPC/Service/` (target `TruchiEmuCoreHost`, embedded into the app via `embed: true` in `project.yml`). `TruchiEmu/Core/XPC/Shared/` holds code shared between host and app. Used for sandboxed libretro hosting.
- **Data layer**: SwiftData models in `TruchiEmu/Core/Models/`, with additional shared models in `TruchiEmu/Shared/Models/SwiftDataModels.swift`
- **libarchive linkage**: `TruchiEmu/Core/LibArchive/` (linked via `-larchive` for ROM/asset extraction)
- **Metal shaders**: `TruchiEmu/Core/Shaders/` (runtime shaders, excludes `slang/**`, `internal/**`, `all_shaders.metal` from build)
- **Save/state management**: `SaveDirectoryManager` and `SaveMigrationService` in `TruchiEmu/Services/`
- **System-specific runners**: `TruchiEmu/Core/Engine/Runners/Runners/` with `EmulatorRunner` base class and subclasses: `NESRunner`, `SNESRunner`, `N64Runner`, `DOSRunner`, `ScummVMRunner`, `SaturnRunner`

### Feature module architecture

`Features/` is the primary organizational pattern for feature-scoped code. Each feature follows `Models/Services/Views/` structure:

| Feature | Path | Responsibility |
|---|---|---|
| Library | `Features/Library/` | ROM library management, scanning, categories, genres |
| MAME | `Features/MAME/` | MAME-specific ROM handling, dependency management, verification |
| Player | `Features/Player/` | Game launching, shaders, cheats, bezels, achievements, input |
| Settings | `Features/Settings/` | Controller config, core options, input descriptors, all settings UI |
| Help | `Features/Help/` | In-app help sheet and quick-reference content |

`Views/` at the top level contains shared/reusable views not tied to a single feature (e.g., `CoreDownload/`, `Detail/`, `NotificationCenter/`, `Shaders/`, `Settings/` shared components). When adding feature-specific code, place it in the appropriate `Features/` subdirectory, not in `Views/`.

### Concurrency model

| Pattern | Used by | Notes |
|---|---|---|
| `@MainActor` singleton `ObservableObject` | Most services/managers | Dominant pattern; access only from main thread |
| Swift `actor` | `ImageCache`, `ROMScanner`, `ProgressTracker` | Concurrency-safe without `@MainActor` |
| `nonisolated(unsafe)` | `ShaderParameterStore`, MAME lookup tables | Data accessed from non-MainActor threads (renderer, background loading). Do not add MainActor-only state |
| `@unchecked Sendable` | `EmulatorRunner`, `SaveStateManager` | Manually managed thread safety; rendering runs on dedicated queue |
| `@Observable` | `SystemDatabaseWrapper` | **Only class using** modern Observation framework; everything else uses `ObservableObject` + `@Published` |
| `NSHostingView<AnyView>` | Game toolbar, bezel selector | SwiftUI content embedded in AppKit windows |

**Key rule:** New services should default to `@MainActor ObservableObject`. Only use `actor` for services with heavy background I/O. Only use `nonisolated(unsafe)` when data must be read from a renderer or background thread.

## Service Registry

| Service | File | Purpose |
|---|---|---|
| `GameLauncher.shared` | `Features/Player/Services/` | Unified game launch entry point; resolves `LaunchConfig` |
| `CoreManager.shared` | `Services/` | Core download/install lifecycle, BIOS download |
| `ControllerService.shared` | `Features/Settings/Services/` | GCController connect/disconnect, per-vendor mapping, 4 players |
| `ShaderManager.shared` | `Features/Player/Services/` | Metal pipeline state cache, dynamic shader switching, uniforms |
| `ShaderPresetStorageService.shared` | `Services/` | CRUD for custom `.truchishader` presets |
| `CheatManagerService.shared` | `Features/Player/Services/` | Per-ROM cheat load/toggle, persists enabled state to AppSettings |
| `CheatDownloadService.shared` | `Services/` | Downloads `.cht` from libretro-database GitHub repo |
| `RetroAchievementsService.shared` | `Services/` | RA auth, achievement tracking/unlocking, rich presence, disk caching |
| `HardcoreModeManager.shared` | `Services/` | Enforces hardcore restrictions (blocks save states, rewind, cheats) |
| `RunningGamesTracker.shared` | `Features/Player/Services/` | Tracks running ROMs; prevents double-launch; signals gameplay to pause background work |
| `InputCaptureManager.shared` | `Core/InputCapture/` | Keyboard/mouse capture for game windows; requires Accessibility permissions |
| `InputDescriptorsManager.shared` | `Features/Settings/Services/` | Per-core button descriptors persisted as JSON |
| `CoreOptionsManager.shared` | `Features/Settings/Services/` | Core option lifecycle: parse from cores, persist overrides as `.cfg` files |
| `BezelManager.shared` | `Features/Player/Services/Bezels/` | Bezel resolution cascade (user > auto-match > system default) |
| `MAMEUnifiedService.shared` | `Features/MAME/Services/` | Loads bundled `mame_unified.json`; per-core compatibility/dependency info |
| `LibraryAutomationCoordinator.shared` | `Features/Library/Services/` | Post-scan pipeline: identify ROMs → enrich metadata → download art |
| `MetadataSyncCoordinator.shared` | `Services/` | Background LaunchBox metadata sync; 1-at-a-time concurrency |
| `BoxArtService.shared` | `Services/` | Multi-source box art (ScreenScraper + Libretro CDN), configurable priority |
| `SaveDirectoryManager.shared` | `Services/` | Centralized save/state/system directory configuration with migration |
| `ImageCache.shared` | `Shared/Services/` | Swift `actor`; NSCache with 12-concurrent-load limit, in-flight dedup, thumbnails |
| `ResourceCacheInterceptor.shared` | `Shared/Services/` | HTTP cache with ETag/Last-Modified revalidation, 404 caching, SwiftData-backed |
| `LoggerService.shared` | `Shared/Services/` | 4 levels (none/info/debug/extreme), async file-based, C callback for libretro cores |
| `LogManager.shared` | `Shared/Services/` | Log file path/storage management, custom folder support |
| `CLIManager.shared` | `Services/` | CLI argument parsing at startup (headless mode, ROM launch, help/version) |
| `SwiftDataContainer.shared` | `Shared/Infrastructure/Persistence/` | SwiftData `ModelContainer` lifecycle; schema registration for all models |
| `AppSettingsCache.shared` | `Shared/Utilities/` | In-memory `[String: Data]` cache backed by SwiftData `SettingsEntry` |
| `LocalizationManager.shared` | `Shared/Localization/` | JSON-based UI translations; `setLanguage()` for runtime changes |
| `ThemeManager.shared` | `Shared/UI/` | Theme/appearance management (see Themes section) |
| `StreamRecordingService.shared` | `Features/Player/Services/` | Local recording (AVAssetWriter) + live RTMP streaming entry point; owns `RTMPStreamingService` instance for non-`.localFile` modes |
| `RTMPStreamingService` | `Features/Player/Services/` | In-process RTMP publishing via HaishinKit's `RTMPConnection`/`RTMPStream` actors; VideoToolbox H.264/HEVC encode + AAC + FLV/RTMP mux |

`AppSettings` is an `enum` (not a class) with static convenience methods wrapping `AppSettingsCache.shared`. Uses `MainActor.assumeIsolated` for thread safety.

## Themes & Appearance

- **ThemeManager** (`TruchiEmu/Shared/UI/ThemeManager.swift`): Singleton `@MainActor ObservableObject` that owns current theme, appearance mode, custom accent color, toolbar accent, and tinted surfaces. Persists all state via `AppSettings` (SwiftData).
- **AccentColorTheme** (`TruchiEmu/Shared/UI/AccentColorTheme.swift`): Enum with 17 cases. Each defines accent/dimmed/dark/secondary colors for light and dark modes. Includes migration logic for renamed themes (`cyan`/`aquatic` → `samus`, `amber`/`solar` → `chocobo`, `pokemon` → `pikachu`).
- **AppearanceMode** (`TruchiEmu/Shared/UI/AppearanceMode.swift`): Enum with 3 cases: `automatic`, `light`, `dark`. Controls `NSApp.appearance`.
- **DesignSystem** (`TruchiEmu/Shared/UI/DesignSystem.swift`): `AppColors` struct with static color tokens that views consume. ThemeManager sets these at init and on theme change.

### Persistence keys (via `AppSettings`)

| Key | Type | Default | Purpose |
|---|---|---|---|
| `accentTheme` | `AccentColorTheme` raw value | `.megaMan` | Current theme |
| `customAccentColor` | `Data` (NSKeyedArchiver) | Samus teal | Custom accent when theme is `.custom` |
| `appearanceMode` | `AppearanceMode` raw value | `.automatic` | Light/Dark/Auto |
| `toolbarAccent` | `Bool` | `true` | Accent-colored toolbar icons |
| `tintedSurfaces` | `Bool` | `true` | Accent tint on window/sidebar/toolbar backgrounds |

### App restart required

Theme and appearance changes require `ThemeManager.relaunchApp()` (spawns new process, terminates current). The settings UI enforces this with confirmation dialogs and unsaved-change interception.

### How to add a new theme

1. Add a case to the `AccentColorTheme` enum with a raw value matching the case name
2. Define `accent`, `accentDimmed`, `accentDark`, `secondaryAccent` (and optional `*ForLightMode`/`*ForDarkMode` variants)
3. Add icon asset to `Assets.xcassets/ThemeIcons/Theme<Name>.imageset/` (PNG + SVG)
4. Add localization keys to ALL language JSON files: `settings.theme.<name>` (display name)
5. If renaming an existing theme, add a migration mapping in `migratedRawValue()`

### Theming considerations for new UI code

**Always use `AppColors` semantic tokens; never hardcode colors.** `AppColors` (in `DesignSystem.swift`) provides light/dark-adaptive tokens that automatically blend the current theme's accent into surfaces, text, and borders.

| Token | Purpose | Example |
|---|---|---|
| `AppColors.brandAccent` | Current accent (auto-resolves light/dark) | Tinted icons, highlights |
| `AppColors.accentForScheme(_:)` | Accent for a specific `ColorScheme` | SwiftUI previews/canvas |
| `AppColors.cardBackground(_:)` | Card/panel bg with subtle accent tint | Game cards, settings sections |
| `AppColors.windowBackground(_:tinted:)` | Main window bg | Top-level backgrounds |
| `AppColors.sidebarBackground(_:tinted:)` | Sidebar bg | Navigation sidebars |
| `AppColors.toolbarBackground(_:tinted:)` | Toolbar/chrome bg | Window toolbars |
| `AppColors.textPrimary/Secondary/Tertiary(_:)` | Warm-tinted text | Labels, descriptions, meta |
| `AppColors.cardBorder(_:)` / `.divider(_:)` | Subtle borders/dividers | Card outlines, separators |

**Respect user preferences for toolbar accent and tinted surfaces:**

- **Toolbar icons**: Check `ThemeManager.shared.toolbarAccentEnabled`. When `true`, use `AppColors.brandAccent`; when `false`, use `.primary`:
```swift
.foregroundStyle(ThemeManager.shared.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
```
- **Tinted backgrounds**: Pass the `tinted` parameter to surface functions based on `ThemeManager.shared.tintedSurfacesEnabled`. When `false`, pass `tinted: false` to fall back to system defaults:
```swift
.background(AppColors.windowBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
```

**For SwiftUI previews that need correct colors:** Views that use `AppColors.brandAccent` rely on `NSApp.effectiveAppearance` at runtime, which isn't available in previews. Use the `*ForScheme` variants instead:
```swift
AppColors.accentForScheme(colorScheme) // instead of AppColors.brandAccent
AppColors.accentDimmedForScheme(colorScheme)
AppColors.accentDarkForScheme(colorScheme)
AppColors.accentSecondaryForScheme(colorScheme)
```

**Light/dark mode resolution:** `AppColors.brandAccent` auto-resolves via `NSApp.effectiveAppearance` (not `@Environment \.colorScheme`). This works at runtime but NOT in previews, so use `*ForScheme` variants for previews.

**Custom theme handling:** When `currentTheme == .custom`, `ThemeManager` derives all variants algorithmically from `customAccentColor` (dimmed at 84%, dark at 70%). Code using `AppColors` tokens automatically gets the correct derived colors, so no special-casing is needed.

## SwiftData & Persistence

- **SwiftDataContainer** (`Shared/Infrastructure/Persistence/`): Singleton owning the `ModelContainer`; registers 25+ model types at init; store at `~/Library/Application Support/TruchiEmu/TruchiEmu.sqlite`
- **Repository pattern**: Structured data access through repositories:
  - `ROMRepository`: ROM CRUD, system queries, library folder management
  - `GameDBRepository`: ROM identification DB lookups
  - `CoreOptionsRepository`: Core option persistence with override hierarchy
  - `ResourceCacheRepository`: HTTP cache with expiry/access tracking
- **AppSettings**: `enum` with static convenience methods (`get`/`set`/`remove`) wrapping `AppSettingsCache.shared` (in-memory `[String: Data]` dictionary backed by SwiftData `SettingsEntry`). Uses `MainActor.assumeIsolated`.
- **Registered model types** (in `SwiftDataContainer`): `ROMEntry`, `ROMMetadataEntry`, `GameDBEntry`, `LibraryFolder`, `InstalledCore`, `AvailableCore`, `ControllerMapping`, `AchievementConfig`, `CheatStore`, `GameCategoryEntry`, `BezelPreferences`, `BoxArtPreferences`, `CoreOptionEntry`, `ShaderPresetEntry`, `ResourceCacheEntryModel`, `DATIngestionEntry`, `BoxArtResolutionEntry`, `MAMERomEntry`, `MAMEDatabaseInfo`, `MAMEVerificationRecord`, `SettingsEntry`, `RAGameCacheEntry`, `NotificationEntry`, `MoveListEntry`, `CustomGameDataEntry`
- **`PersistenceMigrationFlag`**: Tracks whether migration from old SQLite schema has completed.

## Pipelines

### Game Launch Pipeline

ALL launch paths (double-click, button, save state, CLI) go through `GameLauncher.shared.launch()`:

1. **`GameLauncher.shared.launch()`**: Unified entry point
2. **`LaunchConfig`**: Resolves all settings at launch time (core ID, shader preset, core options overrides, achievements/hardcore, cheats, auto-save/load, bezel)
3. **`EmulatorRunner.forSystem(_:)`**: Factory method returning system-specific subclass (`NESRunner`, `SNESRunner`, `N64Runner`, `DOSRunner`, `ScummVMRunner`, `SaturnRunner`, or base `EmulatorRunner`)
4. **`EmulatorRunner.launch()`**: Finds core dylib, configures libretro bridge, starts emulation on dedicated `DispatchQueue` (qos: `.userInteractive`)
5. **`StandaloneGameWindowController`**: NSWindowController owning game window; creates `FocusableMTKView`, manages input capture, bezels, toolbar auto-hide, playtime tracking, save state slot UI
6. **`RunningGamesTracker`**: Registers running ROM; prevents double-launch with `UNUserNotificationCenter` alert

### ROM Scanning Pipeline

1. **`ROMScanner`**: Swift `actor`; scans directories, filters by extension, bulk MAME identification, throttled progress (50ms)
2. **`ROMIdentifierService`**: CRC32 via zlib with `DispatchSemaphore(4)` for I/O throttling; hardware-accelerated hashing
3. **`ROMIdentifier`**: Weighted scoring enum (magic headers > unique extensions > filename patterns > path context)
4. **`LibraryAutomationCoordinator`**: Post-scan pipeline (identify, enrich with LaunchBox metadata, download art). Respects `RunningGamesTracker` to pause during gameplay. 2-second warm-up delay.
5. **`MetadataSyncCoordinator`**: Background LaunchBox metadata sync; 1-at-a-time concurrency; respects `RunningGamesTracker`

### Live Streaming Pipeline

Owned by `StreamRecordingService` when its `mode != .localFile`. Live RTMP publish via HaishinKit's in-process `RTMPConnection`/`RTMPStream` actors (replaces the older ffmpeg-subprocess + raw-BGRA-pipe path that suffered from silent frame drops under backpressure):

1. **`MetalCoordinator.performFrameCapture`** — already runs on every render frame. For streaming it selects the post-shader drawable (or raw core frame) per `recordWithShaders`, blits/copies into an IOSurface-backed CVPixelBuffer from the active `pixelBufferPool` (sized to the user-selected `StreamResolution`).
2. **`CVPixelBufferPool`** — created at session start with the user-selected resolution (e.g. 1920×1080). When the source frame is smaller (NES 256×224 → 1080p), the existing GPU blit/passthrough stretches source UVs [0,1] to fill the destination; VideoToolbox then handles final upscale via `scalingMode = .letterbox` in `VideoCodecSettings`.
3. **`RTMPStreamingService.submitVideoFrame(_:presentationTime:)`** — wraps the CVPixelBuffer in a `CMSampleBuffer`, calls `RTMPStream.append(_:)` on its actor.
4. **Audio** — same `SharedMemoryManager.readAudioSamples()` → resample to AAC rate → build s16le `CMSampleBuffer` → `RTMPStreamingService.submitAudio(<sampleBuffer>)`.
5. **HaishinKit (`RTMPConnection` + `RTMPStream`)** — performs real RTMP handshake, AMF0 messaging, FLV mux, VideoToolbox hardware H.264/HEVC encode, AAC encode, then publishes over TCP. `RTMPStatus` events flow through `AsyncStream<RTMPStatus>` to `RTMPStreamingService.handleConnectionStatus`/`.handleStreamStatus`, which translate to `StreamRecordingService.streamStatus` (`.connecting` → `.streaming`, or `.failed("...")` with localized reason).
6. **`StreamResolution`** — picker in Streaming settings (`native` / `720p` / `1080p` / `1440p` / `4K`) persisted at `AppSettings["streaming_resolution"]`, default `.p1080`. ProRes encoders are demoted to H.264 for streaming (FLV/RTMP doesn't support ProRes).
7. **No external processes, no pipes, no FIFOs** — entire pipeline runs in-process. Backpressure flows synchronously through `RTMPStream.append()` without silent frame drops.

## Core Options System

- **`CoreOptionsManager`**: Parses options from cores via `LibretroBridgeSwift.loadCoreForOptions()`, stores definitions as JSON in `TruchiEmu/CoreOptionDefinitions/`, persists user overrides as `.cfg` files in `TruchiEmu/CoreOptions/`.
- **Override hierarchy** (lower overridden by higher):
  1. `coreDefault`: value from the libretro core itself
  2. `appDefault`: app-wide default
  3. `appSystemDefault`: app default for a specific system
  4. `systemOverride`: user override for a system
  5. `gameOverride`: user override for a specific game
- Each override layer stores `previousLayerValue` for restore.
- **`CoreOptionVersion`**: Handles libretro option versioning with `_V1` suffix keys.
- **`CoreOverrideService`**: Additional per-core/per-system override logic in `TruchiEmu/CoreOverrides/`.

## Input System

- **`InputCaptureManager`**: Singleton; captures keyboard + mouse for game windows. Hides cursor, calls `CGAssociateMouseAndMouseCursorPosition(0)` to decouple mouse deltas, monitors Escape key and click-outside to release capture. **Requires macOS Accessibility permissions** (`AXIsProcessTrusted()`).
- **`ControllerService`**: Monitors `GCController` connect/disconnect via Combine; supports up to 4 players; per-vendor gamepad mappings; handedness (left/right); mapping version migration.
- **`InputDescriptorsManager`**: Per-core button descriptor definitions persisted as JSON in `TruchiEmu/InputDescriptors/<coreID>.json`; converts `InputButtonDescriptor` to `RetroButton` for UI binding.
- **`RetroKeycodeMapper`**: Pure `enum` (no instances); static mapping from macOS virtual keycodes (`kVK_*`) to libretro `RETROK_*` values; also maps `NSEvent.ModifierFlags` to `RETROKMOD` bitmask.
- **`KeyboardMapping`** / **`ControllerGamepadMapping`**: Model structs for per-game keyboard and gamepad bindings.

## RetroAchievements & Hardcore Mode

- **`RetroAchievementsService`**: Full RA integration with auth (login/credentials), game identification (hash matching), achievement tracking/unlocking, rich presence polling, hardcore mode toggle, game data caching to disk.
- **`HardcoreModeManager`**: Singleton enforcing hardcore restrictions. When hardcore is active, the following are blocked:
  - Save states (check `attemptSaveState()` before allowing)
  - Rewind
  - Slow motion
  - Cheats (check `attemptCheat()` before allowing)
- **`RAGameCacheCoordinator`** + **`RABadgeCacheService`**: Caching layers for RA game data and achievement badge images.

## Cheat System

- **`CheatManagerService`**: Per-ROM cheat management (load, toggle, enable/disable). Persists enabled state to `AppSettings`; loads cheat definitions on-demand from disk.
- **`CheatDownloadService`**: Downloads `.cht` files from `libretro-database/cht` GitHub repo per-system with progress tracking.
- **`CheatAutoLoader`**: Automatically loads cheats for the currently running game.
- **`CheatParser`**: Parses `.cht` files (libretro format) into `Cheat` structs.
- **Supported formats**: raw hex, Game Genie, Pro Action Replay, GameShark.

## CLI Support

- **`CLIManager.shared`**: Parses CLI arguments at app startup.
- **`CLILauncher`**: Routes to actions including headless ROM launch, version output, help text.
- Used for launching games directly from terminal: `TruchiEmu <rom-path>`

## Logging

- **`LoggerService.shared`**: 4 log levels (`none`, `info`, `debug`, `extreme`). Async file-based logging via serial `DispatchQueue`. C-callable callback for routing libretro core logs to the same system.
- **`LogManager.shared`**: Manages log file paths, storage, custom folder support.
- **Usage**: `LoggerService.info("message")`, `LoggerService.debug("message")`, etc.
- Many services use private enum wrappers (e.g., `ROMScannerLog`, `containerLog`) to route through `LoggerService` with category prefixes.

### Compile-time flags: `LOG_DEBUG`, `LOG_EXTREME`, `DEBUG`

The three Swift active compilation conditions are scoped **Debug-only** in `project.yml` (target-level `settings.configs.Debug`). They are **not** defined in Release builds:

| Flag | Debug | Release | Purpose |
|---|---|---|---|
| `DEBUG` | yes | no | Standard Swift debug flag; third-party/stdlib `#if DEBUG` branches |
| `LOG_DEBUG` | yes | no | Gates ~500 debug-logging call sites (`LoggerService.debug` bodies and `#if LOG_DEBUG` blocks) |
| `LOG_EXTREME` | yes | no | Gates per-frame/extreme-verbosity logging (`LoggerService.extreme` bodies and `#if LOG_EXTREME` blocks) |
| `XPC_SERVICE` | yes (TruchiEmuCoreHost only) | yes (TruchiEmuCoreHost only) | Marks the XPC target; not a debug toggle — always set for that target |

`LoggerService.debug(_:)` and `LoggerService.extreme(_:)` are **always defined** (in all build configurations) so call sites compile regardless of build type, but their bodies compile to no-ops when `LOG_DEBUG`/`LOG_EXTREME` are off. **Every single call site is wrapped in `#if LOG_DEBUG ... #endif`** (or `#if LOG_EXTREME ... #endif` for `.extreme`), so no debug-level message — including its string interpolation — reaches a Release build. When adding a new `LoggerService.debug`/`.extreme` call, always wrap it in the matching guard so the same invariant holds.

**Footgun:** `#if LOG_DEBUG` blocks compile only in Debug builds — do not use them to gate production runtime behavior (state changes, control flow, business logic), or that behavior will silently disappear in Release. They are for debug-only branches: logging, dev test hooks, dev presets. Use standard `#if DEBUG` for the same purpose when interfacing with third-party/stdlib conventions.

## Project Structure

| Directory | Purpose |
|---|---|
| `TruchiEmu/App/` | App entrypoint, ContentView |
| `TruchiEmu/Core/Engine/` | Libretro bridge, callbacks, runners |
| `TruchiEmu/Core/Engine/Runners/Runners/` | System-specific emulator runners (NES, SNES, N64, DOS, ScummVM, Saturn) |
| `TruchiEmu/Core/InputCapture/` | Keyboard/mouse capture for game windows, keycode mapping |
| `TruchiEmu/Core/LibArchive/` | libarchive linkage (`-larchive`) for ROM/asset extraction |
| `TruchiEmu/Core/Models/` | SwiftData models |
| `TruchiEmu/Core/Shaders/` | Metal shader files |
| `TruchiEmu/Core/XPC/Service/` | XPC service target source (sandboxed libretro hosting) |
| `TruchiEmu/Core/XPC/Shared/` | XPC service shared code (between service and app) |
| `TruchiEmu/Features/Library/` | ROM library management, scanning, categories, genres (`Models/Services/Views/`) |
| `TruchiEmu/Features/MAME/` | MAME-specific ROM handling, dependency/verification services (`Models/Services/Views/`) |
| `TruchiEmu/Features/Player/` | Game launching, shaders, cheats, bezels, achievements, game window (`Models/Services/Views/`) |
| `TruchiEmu/Features/Settings/` | Controller config, core options, input descriptors, all settings UI (`Models/Services/Views/`) |
| `TruchiEmu/Features/Help/` | In-app help sheet, quick-reference UI (`Models/Views/`). |
| `TruchiEmu/Services/` | Cross-cutting business logic (core management, save dirs, achievements, cheats, metadata sync, box art, CLI) |
| `TruchiEmu/Views/` | Shared/reusable SwiftUI views not tied to a single feature |
| `TruchiEmu/Shared/Infrastructure/` | SwiftData container, persistence, repositories |
| `TruchiEmu/Shared/Localization/` | LocalizationManager, translation loading |
| `TruchiEmu/Shared/Models/` | Shared models (SystemInfo, SystemDatabaseWrapper, SystemPreferences, **and the consolidated `SwiftDataModels.swift` file**) |
| `TruchiEmu/Shared/Services/` | Shared services (ImageCache, ResourceCacheInterceptor, LoggerService, LogManager) |
| `TruchiEmu/Shared/UI/` | ThemeManager, AccentColorTheme, AppearanceMode, DesignSystem, AppColors |
| `TruchiEmu/Shared/Utilities/` | AppSettings enum, AppSettingsCache, utility extensions |
| `TruchiEmu/Resources/` | Assets, Info.plist, entitlements, app icons, translations |
| `TruchiEmu_Resources/` | Runtime-only resources (core_shaders, retroarch_images), NOT in Xcode build |
| `TruchiEmu/Library/` | Empty placeholder, excluded from build |
| `scripts/` | Standalone Python tools (ROM lookup, DAT downloads), not part of the app build |

> **Note:** `TruchiEmu/Shared/Protocols/` does not currently exist. The `SettingsSearchable` protocol lives at `Features/Settings/Models/SettingsSearchable.swift`, not under Shared.

## Runtime vs Bundled Resources

**`TruchiEmu_Resources/`**: Runtime-only resources (loaded at runtime, NOT in xcode project):
- `core_shaders/`: Metal shaders loaded dynamically
- `retroarch_images/`: system icons loaded at runtime
- These are loaded from bundle path (not bundled into Xcode target)

**Bundled resources are flattened**. When app is built, all resources in `Resources/` are flattened to a single folder. Subdirectories are lost. Code fetching resources must use filenames only (e.g., `Bundle.main.path(forResource: "sega_101", ofType: "bin")`), not rely on folder paths.

**Unzipping bundled resources**. If a zip expects specific subfolders (e.g., cheats/cheats.zip contains folders), you must create those directories manually in the sandboxed app container. The flat bundle structure won't preserve the zip's internal folder hierarchy.

## Key Constraints

- `build/` is gitignored. Do not commit build artifacts
- `.xcodeproj` is NOT in gitignore. It is committed and tracked
- `xcuserdata/` and `*.xcuserdatad/` are gitignored. User-specific Xcode data excluded
- Entitlements file is minimal/empty. No sandboxing initially; if adding capabilities, update entitlements
- C++ standard: **gnu17/gnu++17** (not LLVM default)
- `NSAllowsArbitraryLoads: true` set in Info.plist for network access
- No lint/typecheck tools configured. Build the project with `xcodebuild` to verify changes
- `TruchiEmu/Library/` is empty and excluded from build. Do not add files there
- App and core dylibs (`librashader`, `libSDL2`) are linked via `OTHER_LDFLAGS`/`LD_RUNPATH_SEARCH_PATHS` and copied into `Contents/Frameworks` by postBuildScripts (`project.yml:108`). If linking against a new third-party dylib, add a parallel script + ad-hoc re-sign.

## Release Process

See `RELEASE_PROCESS.md` at the project root for the complete guide. It documents both:
- the **nightly preview** channel (single `TruchiEmu-nightly.zip` asset on the `nightly` pre-release tag, no version bump, no merge — for in-flight test builds), and
- the **tagged stable release** workflow (version bump + changelog + git tag + push + `gh release create v<version>` — for shipping).

When asked to "release", "cut a release", or "bump version", follow the tagged-stable-release steps in `RELEASE_PROCESS.md`.

When asked to "build the current state and upload it for testing", "upload to the nightly", "let other Macs download it", or "ship a test build" without bumping versions / merging anything, follow the nightly-preview-build steps in `RELEASE_PROCESS.md`.

### TCC Permissions & Version Bumps

TCC (Transparency, Consent, and Control) keys security-scoped bookmark grants on **bundle identity + `CFBundleVersion` + code-signature**. TruchiEmu is currently Development-signed (`CODE_SIGN_IDENTITY = "-"`, ad-hoc), so each `CFBundleVersion` bump invalidates TCC grants for user-selected folders (custom log folder, ROM library folders under `~/Downloads`, etc.).

Symptom: the app re-prompts for Downloads access on every launch, and boxart reads under `~/Downloads/roms/...` fail with `err=1 (Operation not permitted)`.

Rule: **Do not bump `CFBundleVersion` during active development.** Bump it only when cutting a release (see `RELEASE_PROCESS.md` and the tagged-stable-release workflow). Holding the version constant across Debug rebuilds keeps the prior TCC grant valid, so the app does not re-prompt.

If a grant has already been invalidated: System Settings → Privacy & Security → Files and Folders → TruchiEmu → remove the entries, relaunch the current build, grant access once. The grant persists across rebuilds as long as `CFBundleVersion` is unchanged.


## When Adding Source Files

1. **No project.yml edits for new files**: Sources under `TruchiEmu/` and resources under `TruchiEmu/Resources/` are auto-included via recursive paths. See "Build System" above.
2. Run `xcodegen generate` to regenerate the xcodeproj
3. If adding ObjC++ to the Engine, ensure symbols are exposed through the bridging header
4. Place feature-specific code in the appropriate `Features/` subdirectory (`Models/Services/Views/`), not in top-level `Views/`

## Slang Shader System

The app supports RetroArch `.slangp` shader presets via **librashader** (Rust library with C API, embedded as dynamic library).

### Architecture

| Component | Path | Responsibility |
|---|---|---|
| `librashader.dylib` | `TruchiEmu/lib/` | Runtime GLSL→SPIR-V→MSL compilation, multi-pass filter chain execution |
| `slang_shader_bridge.mm` | `Core/Engine/` | ObjC++ bridge exposing Metal-specific librashader calls |
| `SlangCompilerService` | `Features/Player/Services/` | Preset loading, filter chain lifecycle, thread-safe frame rendering |
| `SlangPresetDiscoveryService` | `Services/` | Scans bundled + user `.slangp` preset directories |
| `SlangPreset` | `Features/Player/Models/` | Swift model wrapping `libra_shader_preset` and its `#pragma parameter` metadata |

### How it works

1. `ShaderManager.activateSlangPreset()` → `SlangCompilerService.loadAndActivatePreset()` calls `libra_preset_create_with_options()` to load `.slangp`
2. `libra_preset_get_runtime_params()` reflects `#pragma parameter` into `ShaderUniform` array
3. `slang_mtl_filter_chain_create()` creates a Metal filter chain handling all passes internally
4. `MetalCoordinator.draw()` detects `fragmentName == "slang"` and calls `SlangCompilerService.renderFrame()` instead of single-pass pipeline
5. `renderFrame()` is `nonisolated` with NSLock-protected chain pointer (same threading model as `ShaderParameterStore`)

### Key constraints

- Built-in `.metal` shaders (14 presets) are **unaffected** — they use the original single-pass pipeline
- Slang shaders bypass `ShaderUniforms.swift` hardcoded structs — librashader owns uniform binding via SPIR-V reflection
- Only one preset type active at a time (built-in or slang)
- librashader handles temporal feedback internally; MetalCoordinator's `temporalTextures` array is only for built-in shaders

### Build dependencies

- `librashader.dylib` built from https://github.com/SnowflakePowered/librashader; requires Rust toolchain
- `Resources/slang-shaders/` is a git submodule for `https://github.com/libretro/slang-shaders`
- Offline shader cache: `scripts/compile_slang_cache.py` needs `glslangValidator` + `spirv-cross` (`brew install glslang spirv-cross`)

## Testing

**No test target exists currently.** The `TruchiEmuTests/` directory and scheme referenced in previous versions of this doc have been removed. When adding tests:
1. Create a test target in `project.yml` and run `xcodegen generate`
2. Add test files under `TruchiEmuTests/`
3. Link `SwiftData` framework in the test target
4. Some tests may require network access (LaunchBox, thumbnail services)

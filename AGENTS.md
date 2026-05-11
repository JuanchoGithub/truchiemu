# TruchiEmu Developer Guide

## Build System

- **XcodeGen**: Run `xcodegen generate` after any `project.yml` change to regenerate `TruchiEmu.xcodeproj`. Do not edit the `.xcodeproj` directly.
- **Build command**: `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build` (or open the xcodeproj in Xcode)
- **Test command**: `xcodebuild test -scheme TruchiEmuTests -destination 'platform=macOS'`
- **macOS 14.0+ and Swift 5.9** required

## Architecture

- **App entrypoint**: `TruchiEmu/App/TruchiEmuApp.swift` + `ContentView.swift`
- **Emulation engine**: `TruchiEmu/Core/Engine/` — mixed Objective-C++/C with a Swift bridging header (`TruchiEmu-Bridging-Header.h`). Hosts libretro core integration.
- **Swift<->ObjC bridge**: `LibretroBridge.mm` / `LibretroBridgeSwift.swift` for calling libretro from Swift
- **Data layer**: SwiftData models in `TruchiEmu/Core/Models/`
- **Metal shaders**: `TruchiEmu/Core/Shaders/` — runtime shaders, excludes `slang/**`, `internal/**`, `all_shaders.metal` from build
- **Save/state management**: `SaveDirectoryManager` and `SaveMigrationService` in `TruchiEmu/Services/`

## Project Structure

| Directory | Purpose |
|---|---|
| `TruchiEmu/App/` | App entrypoint, ContentView |
| `TruchiEmu/Core/Engine/` | Libretro bridge, callbacks, runners |
| `TruchiEmu/Core/Models/` | SwiftData models |
| `TruchiEmu/Core/Shaders/` | Metal shader files |
| `TruchiEmu/Services/` | Business logic (save management, DB, thumbnails) |
| `TruchiEmu/Views/` | SwiftUI views |
| `TruchiEmu/Features/` | Feature-specific views |
| `TruchiEmu/Shared/` | Shared utilities |
| `TruchiEmu/Resources/` | Assets, Info.plist, entitlements, app icons |
| `TruchiEmu_Resources/` | Shader and image resources (core_shaders, retroarch_images) |
| `TruchiEmuTests/` | Unit tests (DATPrepopulationService, LaunchBoxGamesDB, ROMIdentifier, etc.) |
| `scripts/` | Standalone Python tools (ROM lookup, DAT downloads) — not part of the app build |

## Resources Included in Build (project.yml)

These paths are explicitly added to the Xcode build via `project.yml`:
- `TruchiEmu/Resources/Config`
- `TruchiEmu/Resources/Data` (SystemDatabase.json, LibretroDats, mame_unified.json)
- `TruchiEmu/Resources/EmulatorIcons`
- `TruchiEmu/Resources/ThumbnailManifests`
- `TruchiEmu/Resources/System/` (BIOS files: sega_101.bin, mpr-17933.bin, PPSSPP_assets.zip, dreamcast.zip)
- `TruchiEmu/Resources/cheats/` (all cheat zip files — critical for RetroAchievements)
- `TruchiEmu/Resources/AppIcons/` — app icons
- `TruchiEmu/Resources/Assets.xcassets/` — app icon set

## Runtime vs Bundled Resources

**`TruchiEmu_Resources/`** — Runtime-only resources (loaded at runtime, NOT in xcode project):
- `core_shaders/` — Metal shaders loaded dynamically
- `retroarch_images/` — system icons loaded at runtime
- These are loaded from bundle path (not bundled into Xcode target)

**Bundled resources are flattened** — When app is built, all resources in `Resources/` are flattened to a single folder. Subdirectories are lost. Code fetching resources must use filenames only (e.g., `Bundle.main.path(forResource: "sega_101", ofType: "bin")`), not rely on folder paths.

**Unzipping bundled resources** — If a zip expects specific subfolders (e.g., cheats/cheats.zip contains folders), you must create those directories manually in the sandboxed app container. The flat bundle structure won't preserve the zip's internal folder hierarchy.

## Key Constraints

- `build/` is gitignored — do not commit build artifacts
- `.xcodeproj` is NOT in gitignore — it is committed and tracked
- `xcuserdata/` and `*.xcuserdatad/` are gitignored — user-specific Xcode data excluded
- Entitlements file is minimal/empty — no sandboxing initially; if adding capabilities, update entitlements
- C++ standard: **gnu17/gnu++17** (not LLVM default)
- `NSAllowsArbitraryLoads: true` set in Info.plist for network access
- No lint/typecheck tools configured — rely on Xcode's built-in checks

## When Adding Source Files

1. Edit `project.yml` to add new paths under the appropriate target's `sources`
2. Run `xcodegen generate` to regenerate the xcodeproj
3. If adding ObjC++ to the Engine, ensure symbols are exposed through the bridging header
4. After adding new resources (e.g., new cheats, assets), ensure they're added to project.yml BEFORE running xcodegen

## Testing

- Tests live in `TruchiEmuTests/` and reference services in `TruchiEmuTests/Services/`
- Test target links `SwiftData` framework
- Some tests may require network access (LaunchBox, thumbnail services)
# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

## Localization method

The app uses a **JSON‑based UI localization system**:
- Translation files in `Resources/Translations/` (e.g., `en.json`, `es.json`)
- `LocalizationManager` loads all JSON files at launch, auto-detects device language, supports runtime changes via `setLanguage(_:)`
- **IMPORTANT:** `setLanguage()` persists to `AppSettings.set("systemLanguage", value: lang)` — without this, language resets on next app launch

### How to use localization in SwiftUI views

**For SwiftUI Section/Picker/Button titles (String parameter):**
```swift
loc.localized("settings.saveStates")  // Returns String
Section(loc.localized("settings.saveStates")) { ... }
Picker(loc.localized("settings.selectLanguage"), selection: $binding) { ... }
```

**For SwiftUI Text (SwiftUI Text view):**
```swift
Text("settings.title")  // Uses the Text extension, returns localized Text
```

**For confirmation dialog messages:**
```swift
.confirmationDialog(loc.localized("settings.syncAllGamesTitle"), ...) { ... }
```

**Key pattern:** Always use `loc.localized("key")` for String arguments, `Text("key")` for Text arguments.

### Adding new translations

1. Add key to ALL language JSON files (e.g., `en.json`, `es.json`) with the same key
2. Use consistent naming: `section.action` (e.g., `settings.saveStates`, `game.launch`)
3. Update views to use `loc.localized("key")` instead of hardcoded strings
4. Debug/internal messages are not translated

### Common bug to avoid

When adding a language picker that calls `setLanguage()`:
- Ensure `setLanguage()` saves to `AppSettings` — otherwise the selection is lost when the view re-renders
- The picker binding must read from `loc.currentLanguage` to show the current selection


**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

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
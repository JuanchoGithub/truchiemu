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
- **No project.yml edits for new files**: Sources under `TruchiEmu/` and resources under `TruchiEmu/Resources/` are auto-included via recursive paths in `project.yml`. Only edit `project.yml` if you're adding a directory that should be **excluded** from the build.
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

## Themes & Appearance

- **ThemeManager** (`TruchiEmu/Shared/UI/ThemeManager.swift`): Singleton `@MainActor ObservableObject` that owns current theme, appearance mode, custom accent color, toolbar accent, and tinted surfaces. Persists all state via `AppSettings` (SwiftData).
- **AccentColorTheme** (`TruchiEmu/Shared/UI/AccentColorTheme.swift`): Enum with 17 cases. Each defines accent/dimmed/dark/secondary colors for light and dark modes. Includes migration logic for renamed themes (e.g., `cyan` → `samus`, `amber` → `chocobo`, `pokemon` → `pikachu`).
- **AppearanceMode** (`TruchiEmu/Shared/UI/AppearanceMode.swift`): Enum with 3 cases: `automatic`, `light`, `dark`. Controls `NSApp.appearance`.
- **DesignSystem** (`TruchiEmu/Shared/UI/DesignSystem.swift`): `AppColors` struct with static color tokens that views consume. ThemeManager sets these at init and on theme change.

### Persistence keys (via `AppSettings`)

| Key | Type | Default | Purpose |
|---|---|---|---|
| `accentTheme` | `AccentColorTheme` raw value | `.samus` | Current theme |
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
6. Set `isGaming = true` if the theme belongs in the Gaming category

### Theme categories

- **Standard** (`isGaming == false`): Samus, Chocobo, Protoss, Joker, Geralt, Mega Man, Custom
- **Gaming** (`isGaming == true`): Mario, Luigi, Sonic, Half-Life, Kratos, Kirby, Zelda, Pikachu, Doom, Master Chief

### Theming considerations for new UI code

**Always use `AppColors` semantic tokens — never hardcode colors.** `AppColors` (in `DesignSystem.swift`) provides light/dark-adaptive tokens that automatically blend the current theme's accent into surfaces, text, and borders.

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
AppColors.accentForScheme(colorScheme)      // instead of AppColors.brandAccent
AppColors.accentDimmedForScheme(colorScheme)
AppColors.accentDarkForScheme(colorScheme)
AppColors.accentSecondaryForScheme(colorScheme)
```

**Light/dark mode resolution:** `AppColors.brandAccent` auto-resolves via `NSApp.effectiveAppearance` (not `@Environment \.colorScheme`). This works at runtime but NOT in previews — use `*ForScheme` variants for previews.

**Custom theme handling:** When `currentTheme == .custom`, `ThemeManager` derives all variants algorithmically from `customAccentColor` (dimmed at 84%, dark at 70%). Code using `AppColors` tokens automatically gets the correct derived colors — no special-casing needed.

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

`TruchiEmu/Resources/` is included recursively as resources — any file added anywhere under it is automatically bundled. No `project.yml` changes needed.

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

1. **No project.yml edits for new files**: Sources under `TruchiEmu/` and resources under `TruchiEmu/Resources/` are auto-included via recursive paths. See "Build System" above.
2. Run `xcodegen generate` to regenerate the xcodeproj
3. If adding ObjC++ to the Engine, ensure symbols are exposed through the bridging header

## Testing

- Tests live in `TruchiEmuTests/` and reference services in `TruchiEmuTests/Services/`
- Test target links `SwiftData` framework
- Some tests may require network access (LaunchBox, thumbnail services)
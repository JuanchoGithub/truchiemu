# Game Info View Redesign Proposal

## Scope

The main section (hero with cover art, title, launch button, stat deck) is already redesigned. The Overview section is already redesigned. This proposal covers the remaining 11 sections:

1. Shader
2. Bezels
3. Controls
4. Analog Mouse
5. DOS Joystick
6. Core Options (currently Game Boy Colorization only)
7. Saved States
8. Cheats
9. Core
10. Achievements
11. OpenCritic
12. Technical

All sections live inside `GameDetailView.swift` and its section files under `TruchiEmu/Views/Detail/Sections/`.

## Design Inspiration (8 Sites)

| Site | What we take |
|---|---|
| **Bencho** | Stat blocks, clean section cards, grid layouts, hover-active tiles |
| **60fps** | Micro-interactions: hover lift, spring press, liquid-glass sheen on buttons |
| **regards.design** | Section curation: each section is a self-contained card with icon, title, badge |
| **Ripplix** | Micro-interactions on every tappable row, subtle scale on press |
| **recent.design** | Category chips and tag pills for filtering and status |
| **Details.so** | Weekly-updated section feel: clear headers, count badges, trailing actions |
| **posts.design** | Social-style cards with counts, avatar-like icons, compact metadata rows |
| **Spotted in Prod** | iOS-native liquid glass: translucency, backdrop blur, vibrant accent washes |

## Design Principles

1. **One card per section.** Each section is its own `ModernSectionCard` with a header (icon + title + badge) and a content body. No section shares a card with another.
2. **Stat deck at section top.** Each section shows only the stats it owns (like the hero deck but smaller). If a section has no native stats, fall back to play history or a status chip.
3. **Micro-interactions on every row.** Hover lifts the row, press springs the button, toggle has a spring feel. `reduceMotion` disables all motion.
4. **Liquid glass surfaces.** Cards use `AppColors.cardBackground` with a 1pt border. Primary buttons use solid accent fills. Secondary buttons use outlined or glass fills.
5. **Category chips.** Section groups in the sidebar keep their uppercase chip labels. Status pills (custom, auto, off, matched) use capsule chips.
6. **Progressive disclosure.** Rarely used actions hide behind a "More" menu or a secondary button row. Common actions stay visible.
7. **Data first, chrome second.** Values are large and monospaced where appropriate. Labels are tiny, uppercase, tracked. Dividers are hairlines.

## Shared Components to Add

### 1. `DetailStatBadge` — small stat pill

A pill with icon + value + unit, used at the top of each section card instead of the full hero deck.

```swift
struct DetailStatBadge: View {
    let icon: String
    let value: String
    let unit: String
    var tint: Color = AppColors.brandAccent
}
```

### 2. `SectionHeaderBar` — card header replacement

Replaces the inline `HStack` header in `ModernSectionCard` with a consistent pattern: icon plate, title, optional badge, trailing action. All sections use the same header so the view reads as one system.

### 3. `AppDataRow` (exists) — used more widely

The existing `AppDataRow` in `DesignSystem.swift` is already a label/value row. Use it in Technical and Core sections instead of ad-hoc `HStack` rows.

## Section-by-Section Redesign

### Shader

**Current:** `ModernSectionCard` with current shader label, two action buttons, a horizontal preset list (4 items), and a reset row. Dividers separate every block.

**Redesign:**
- Header: icon `display`, title "Shader", badge "Custom" if customized.
- Row 1: Current shader value (large) + "Customize" primary button + "Live Edit" secondary button.
- Row 2: Preset gallery as a horizontal scroll of chips. Each chip shows icon + name + description. Selected chip has solid accent fill. Unselected chips are glass with hover lift.
- Row 3: System default row (label + "Reset to default" button, disabled when not customized).

**Inspiration:** Bencho preset cards, 60fps hover lift on chips, Details.so section curation.

### Bezels

**Current:** Card with bezel preview image (or empty state), current bezel label row, enable toggle, auto-match and clear buttons, "pre-downloaded" hint.

**Redesign:**
- Header: icon `picture.inset.filled`, title "Bezels", badge = status (Off / Auto / Custom).
- Row 1: Preview area. If an image exists, show it with a soft border and corner radius. If not, show an empty state with icon + "No preview available" + "Browse bezels" button.
- Row 2: Current bezel name + "Browse" button.
- Row 3: Enable toggle (switch).
- Row 4: Two full-width buttons: "Auto-match" and "Clear bezel".
- Row 5: Hint text: "Bezels pre-downloaded".

**Inspiration:** Details.so preloaders section, posts.design preview cards, Spotted in Prod glass buttons.

### Controls

**Current:** Card with controller mapping label + edit button, controller icon + default mapping label, reset controls row.

**Redesign:**
- Header: icon `gamecontroller`, title "Controls", badge = system name.
- Row 1: "Controller mapping" + description + "Edit mapping" primary button (opens settings).
- Row 2: Controller icon (system artwork) + "Default mapping" label + description. The icon sits in a rounded square with a subtle glow.
- Row 3: "System default controls" + "Reset" button.

**Inspiration:** Spotted in Prod iOS controller settings, Bencho clean rows.

### Analog Mouse

**Current:** Card with enable toggle and reset-to-default row.

**Redesign:**
- Header: icon `computermouse.fill`, title "Analog Mouse", badge "Custom" if overridden.
- Row 1: "Enable for this game" + description + toggle switch.
- Row 2: "System default" + current value + "Use default" button (disabled when not customized).

**Inspiration:** Bencho toggle rows, 60fps spring toggle.

### DOS Joystick

**Current:** Card with preset picker and reset button.

**Redesign:**
- Header: icon `gamecontroller.fill`, title "DOS Joystick", badge "Custom" if overridden.
- Row 1: "Per-game preset" + description + menu picker (preset name).
- Row 2: "System default" + current preset name + "Use default" button (disabled when not customized).

**Inspiration:** Details.so preset rows, posts.design menu chips.

### Core Options (GB Colorization)

**Current:** Card with enable toggle, palette mode picker, internal palette picker, SGB borders toggle, color correction picker, info text.

**Redesign:**
- Header: icon `paintpalette`, title "Game Boy Colorization".
- Row 1: "Enable colorization" + toggle.
- When enabled:
  - Row 2: "Palette mode" + menu picker (Auto / GBC / SGB / Internal / Custom).
  - Row 3: "Internal palette" + menu picker (GB sections, GBC sections, SGB sections, Special). Disabled unless Gambatte core.
  - Row 4: "Super Game Boy borders" + toggle. Shows "mGBA core" hint when not Gambatte.
  - Row 5: "Color correction" + menu picker (GBC only / Always / Disabled). Disabled unless Gambatte.
- When disabled: info text "Games will display in classic Game Boy monochrome."

**Inspiration:** Details.so settings section, settings-style rows.

### Saved States

**Current:** Card with auto slot (centered), user slots in a 5-column grid, progressive slot stacks, count + total size footer.

**Redesign:**
- Header: icon `externaldrive`, title "Saved States", badge = existing slot count.
- Empty state: icon + "No saved states" + "Saved states are created during gameplay."
- Auto slot row: large centered slot chip with thumbnail + "Continue" button.
- User slots: grid of slot chips (3 columns on narrow, 5 on wide). Each chip shows thumbnail, slot number, date, size. Progressive slots stack with offset thumbnails. Tap to expand progressive versions.
- Footer: count + total size.

**Inspiration:** Bencho grid tiles, 60fps hover lift on chips, posts.design social cards.

### Cheats

**Current:** Card with enable toggle + `CheatBrowserList` (fixed height 400).

**Redesign:**
- Header: icon `wand.and.stars`, title "Cheats", badge = "enabled/total".
- Row 1: "Enable cheats" + toggle.
- Row 2: Cheat browser list (categories, download, import, add, apply buttons). The list is scrollable within the card, no fixed height.
- When no cheats: empty state with "No cheats found" + "Download cheats" button.

**Inspiration:** Details.so lists, posts.design category chips.

### Core

**Current:** Card with core picker (or "no cores installed"), apply-to-system toggle, info text, "Core options" button + "Set for this game / Set system default" button.

**Redesign:**
- Header: icon `cpu`, title "Core".
- Row 1: "Emulation core" + picker (installed cores) or "No cores installed" empty state.
- Row 2: "Apply to system default" + toggle. Info text below explains the effect.
- Row 3: Action row: "Core options" button (opens core options window) + "Apply" button (solid accent). Disabled when no core selected.

**Inspiration:** Spotted in Prod system settings, Bencho action rows.

### Achievements

**Current:** Card with hardcore toggle, verification status, loading/mismatch/not_supported/empty states, then stat row (unlocked/total, points, progress bar), view mode picker, then grid or list of achievements.

**Redesign:**
- Header: icon `trophy`, title "Achievements", badge = "unlocked/total".
- When RA enabled and matched:
  - Row 1: "Hardcore mode" + toggle + description.
- Verification status row (working/result).
- States:
  - Loading: spinner + text.
  - Mismatch: warning icon + "Version mismatch" + info + "View on RetroAchievements" link + "Find different version" button.
  - Not supported: trophy icon + "No achievements" + "Search RetroAchievements" button.
  - Matched, zero achievements: trophy icon + "Game matched, no achievements" + "Check for new achievements" button.
  - No achievements available: trophy icon + "No achievements available" + "Search RetroAchievements" button.
- When achievements exist:
  - Stat row: "X/Y achievements" (large) + "X/Y pts" (large) + progress ring.
  - View mode picker (grid / list) as segmented control.
  - Grid: achievement badges in adaptive grid. Tap expands detail below the badge.
  - List: achievement rows with title, points, description, unlocked badge.

**Inspiration:** Bencho stat blocks, 60fps progress animation, recent.design feeds, Spotted in Prod game center style.

### OpenCritic

**Current:** Card with three states: no API key (settings button), fetching (spinner), has data (score + tier + recommended % + review count + link), error/no data (fetch button).

**Redesign:**
- Header: icon `star.fill`, title "OpenCritic".
- No API key: "OpenCritic is not configured" + "Open in Settings" button.
- Fetching: spinner + "Fetching score…"
- Has data:
  - Large score (44pt) + "Score" label.
  - Tier badge (colored capsule) + "Recommended X%" + "X reviews".
  - "View on OpenCritic" link.
- Error/no data: error message + "Fetch" button.

**Inspiration:** Details.so score cards, posts.design metric cards.

### Technical

**Current:** Card (no header) with system picker, match source row, metadata rows (file name, path, size, CRC32, RA hash, RA supported, original name, developer, publisher, genre, players, coop, ESRB), plus action buttons (Identify, Match Game, Fetch Metadata, Fetch Art) above the card.

**Redesign:**
- Header: icon `doc.text.magnifyingglass`, title "Technical".
- Row 1: Action buttons (Identify Game, Match Game, Fetch Metadata, Fetch Art) as a row of secondary buttons.
- Row 2: System picker (system name + chevron).
- Row 3: Match source (when manual match).
- Metadata block: `AppDataRow` rows for File Name, Path, File Size, CRC32, RA Hash. Each value is monospaced with a copy button.
- RA Supported badge (when matched).
- Original Name, Developer, Publisher, Genre, Players, Coop, ESRB rows. ESRB shows as a colored badge.

**Inspiration:** Details.so metadata sections, posts.design data rows.

## Localization Keys to Add

All keys go in `en.json`, `es.json`, `pt.json`, `ja.json` under the `gameDetail.` or `gameInfo.` prefix.

| Key | English | Section |
|---|---|---|
| `gameDetail.shaderCustomize` | Customize | Shader |
| `gameDetail.shaderLiveEdit` | Live Shader Edit | Shader |
| `gameDetail.shaderSystemDefault` | System Default | Shader |
| `gameDetail.shaderResetToDefault` | Reset to default shader | Shader |
| `gameDetail.bezelsBrowse` | Browse Bezels | Bezels |
| `gameDetail.bezelsAutoMatch` | Auto-match Bezel | Bezels |
| `gameDetail.bezelsClear` | Clear Bezel | Bezels |
| `gameDetail.bezelsPreDownloaded` | Bezels pre-downloaded | Bezels |
| `gameDetail.controlsEdit` | Edit Mapping | Controls |
| `gameDetail.controlsDefaultMapping` | Default Mapping | Controls |
| `gameDetail.controlsSystemDefaultControls` | System Default Controls | Controls |
| `gameDetail.controlsReset` | Reset Controls | Controls |
| `gameDetail.coreNoCoresInstalled` | No Cores Installed | Core |
| `gameDetail.coreEmulationCore` | Emulation Core | Core |
| `gameDetail.coreApplyToSystemDefault` | Apply to System Default | Core |
| `gameDetail.coreChangeSystemCoreWarning` | Changing this sets {0} as the default core for all games on this system. | Core |
| `gameDetail.coreOnlyThisGameUsesSelectedCore` | Only this game uses the selected core. | Core |
| `gameDetail.coreSetForThisGame` | Set for This Game | Core |
| `gameDetail.coreSetSystemDefault` | Set System Default | Core |
| `gameDetail.coreCoreOptions` | Core Options | Core |
| `gameDetail.technicalIdentifyGame` | Identify Game | Technical |
| `gameDetail.technicalMatchGame` | Match Game… | Technical |
| `gameDetail.technicalFetchMetadata` | Fetch Metadata | Technical |
| `gameDetail.technicalFetchArt` | Fetch Art | Technical |
| `gameDetail.technicalFileName` | File Name | Technical |
| `gameDetail.technicalFilePath` | Path | Technical |
| `gameDetail.technicalCRC32` | CRC32 | Technical |
| `gameDetail.technicalRAHash` | RA Hash | Technical |
| `gameDetail.openCriticConfigure` | OpenCritic is not configured | OpenCritic |
| `gameDetail.openCriticConfigureInSettings` | Configure your API key in Settings. | OpenCritic |
| `gameDetail.openCriticFetching` | Fetching score… | OpenCritic |
| `gameDetail.openCriticScore` | Score | OpenCritic |
| `gameDetail.openCriticRecommended` | Recommended | OpenCritic |
| `gameDetail.openCriticReviews` | reviews | OpenCritic |
| `gameDetail.openCriticViewOnOpenCritic` | View on OpenCritic | OpenCritic |
| `gameDetail.openCriticNoData` | No OpenCritic data available. | OpenCritic |
| `gameDetail.openCriticFetch` | Fetch Score | OpenCritic |
| `gameDetail.achievementsHardcore` | Hardcore Mode | Achievements |
| `gameDetail.achievementsHardcoreDesc` | Blocks save states, rewind, slow motion, and cheats for this game. | Achievements |
| `gameDetail.achievementsCheckForNew` | Check for New Achievements | Achievements |
| `gameDetail.achievementsFindDifferentVersion` | Find Different Version | Achievements |
| `gameDetail.achievementsViewOnRetroAchievements` | View on RetroAchievements | Achievements |
| `gameDetail.achievementsSearchRetroAchievements` | Search RetroAchievements | Achievements |
| `gameDetail.achievementsNoAchievements` | No Achievements | Achievements |
| `gameDetail.achievementsGameNotSupported` | This game is not supported by RetroAchievements. | Achievements |
| `gameDetail.achievementsGameMatchedNoAchievements` | Game matched, but no achievements found. | Achievements |
| `gameDetail.achievementsZeroAchievementsExplanation` | The server has no achievements for this game yet. | Achievements |
| `gameDetail.achievementsNoAchievementsAvailable` | No achievements available for this game. | Achievements |
| `gameDetail.achievementsGameMayNotHaveRAData` | This game may not have RetroAchievements data. | Achievements |
| `gameDetail.savedStatesNoSavedStates` | No Saved States | Saved States |
| `gameDetail.savedStatesCreatedDuringGameplay` | Saved states are created during gameplay. | Saved States |
| `gameDetail.savedStatesSaveStateCount` | save states | Saved States |
| `gameDetail.savedStatesRecentSaveHint` | Resume from your most recent save. | Saved States |
| `gameDetail.savedStatesLastSavedAt` | Last saved {date} | Saved States |
| `gameDetail.savedStatesManageAllSaves` | Manage All Saves → | Saved States |
| `gameDetail.cheatsEnableCheats` | Enable Cheats | Cheats |
| `gameDetail.cheatsNoCheatsFound` | No Cheats Found | Cheats |
| `gameDetail.cheatsDownloadCheats` | Download Cheats | Cheats |

## Implementation Plan

### Step 1 — Add shared components
- Create `DetailStatBadge.swift` in `TruchiEmu/Views/Detail/Sections/`
- Verify `ModernSectionCard` supports all needed header variants (badge, headerTrailing)

### Step 2 — Redesign sections (one file at a time)
Rewrite each section's `some View` property in its file. Keep the same property names so `GameDetailView.sectionContent` switch does not change. Keep all state variables and action functions in `GameDetailView.swift` unchanged.

### Step 3 — Add localization keys
Add all new keys to `en.json`, then `es.json`, `pt.json`, `ja.json`.

### Step 4 — Build and verify
- `xcodegen generate` (if project.yml changed — it should not, since we only edit existing files)
- `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`
- Run the app, open a game info window, navigate through all sections

### Step 5 — Polish
- Verify `reduceMotion` disables all animations
- Verify hover states work with trackpad and mouse
- Verify dark/light mode adaptation via `AppColors` tokens

## Notes

- Do not change `DetailSection` enum or `sidebarNavigation` — the sidebar groups (Game / Setup / Advanced) stay the same.
- Do not change `Overview` — it is already redesigned.
- Do not change the hero header — it is already redesigned.
- Keep all existing state variables (`selectedCoreID`, `gbColorizationEnabled`, `slotInfoList`, `gameAchievements`, etc.) and all action functions unchanged. Only the `body` of each section changes.
- Use `AppColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `SettingsActionButton`, `AppIconButton`, `ModernSectionCard` from the existing design system. Do not introduce new color hardcoding.

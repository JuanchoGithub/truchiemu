# Collapsible Library Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let users collapse the main library Hero to a compact section-name row and disable the Hero from General settings.

**Architecture:** Keep the Hero collapse state local to `LibraryCollectionHero`. Keep the persistent visibility choice in `SystemPreferences`, which both the main library and General settings already observe. Use the existing `AppSettings`, `AppColors`, `AppMotion`, localization, and settings-search patterns.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, JSON localization files, XcodeGen project.

**Spec:** User request dated 2026-11-24: make the main-view Hero collapsible; the collapsed state shows only the section name; reduce the height substantially; animate both directions; add a General settings control to enable or disable the Hero.

## Global Constraints

- The expanded Hero keeps its current 108-point height and content.
- The collapsed Hero is 38 points high and shows only the section name.
- The collapsed name keeps the expanded title font and size.
- The collapsed name is the control that expands the Hero.
- The collapse control is in the expanded Hero's top-left corner.
- The persistent visibility setting defaults to enabled.
- The visibility setting changes the main window without a restart.
- All animations respect Reduce Motion.
- UI text uses localization keys in `en.json`, `es.json`, `pt.json`, and `ja.json`.

## Review Focus

- A disabled Hero must remove the entire Hero, not only its decoration.
- A collapsed Hero must not retain the icon, eyebrow, count, resume action, statistics, or recent shelf.
- The collapsed title must remain operable by mouse, keyboard, and VoiceOver.
- General settings and the main window must stay synchronized across separate windows.
- Translation files must remain valid JSON with identical key sets.

---

### Task 1: Persist and expose the Hero visibility setting

**Files:**
- Modify: `TruchiEmu/Shared/Models/SystemInfo.swift`
- Modify: `TruchiEmu/Features/Settings/Views/Settings/GeneralSettingsView.swift`
- Modify: `TruchiEmu/Features/Settings/Search/SettingsCatalog.swift`
- Modify: `TruchiEmu/Resources/Translations/en.json`
- Modify: `TruchiEmu/Resources/Translations/es.json`
- Modify: `TruchiEmu/Resources/Translations/pt.json`
- Modify: `TruchiEmu/Resources/Translations/ja.json`

**Interfaces:**
- Consumes: `AppSettings.getBool(_:defaultValue:)`, `AppSettings.setBool(_:value:)`.
- Produces: `SystemPreferences.shared.showLibraryHero: Bool`, persisted under `showLibraryHero`.

- [x] Add `showLibraryHero` to `SystemPreferences`, load its saved value during initialization, and persist each change.
- [x] Add a General settings section with a toggle and explanatory text.
- [x] Add the option to General settings search matching and the settings catalog.
- [x] Add the same localization keys to all four translation files.
- [x] Verify all translation files parse as JSON and contain the new keys.

### Task 2: Add the animated collapsed Hero state

**Files:**
- Modify: `TruchiEmu/Features/Library/Views/Library/LibraryDeckComponents.swift`
- Modify: `TruchiEmu/Features/Library/Views/Library/LibraryGridView.swift`

**Interfaces:**
- Consumes: `SystemPreferences.shared.showLibraryHero`, `AppMotion.stateChange`, and the existing localization manager.
- Produces: `LibraryCollectionHero` with a local collapsed state and a 38-point collapsed layout that contains only `title`.

- [x] Add local collapsed state and a labeled collapse control to the expanded Hero.
- [x] Render a title-only 38-point row when collapsed and make the title expand the Hero.
- [x] Animate the height and content transition, or remove animation when Reduce Motion is enabled.
- [x] Remove the complete Hero from `LibraryGridView` when `showLibraryHero` is false.
- [x] Verify that filtering still updates the collapsed title.

### Task 3: Build and review

**Files:**
- Verify only; no planned source changes.

- [x] Run `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`.
- [x] Confirm the build succeeds without new warnings caused by this change.
- [x] Review the final diff for unrelated changes and verify the JSON key sets match.

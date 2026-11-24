# Collapsible Sidebar Quick Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let users collapse the library sidebar Quick Access section to its title and disable the complete section from General settings.

**Architecture:** Keep the collapse state local to `SystemSidebarView`. Keep the persistent visibility choice in `SystemPreferences`, which both the sidebar and General settings observe. Use the existing `AppSettings`, `AppMotion`, localization, settings-search, sidebar-section-header, and gamepad-navigation patterns.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, JSON localization files, XcodeGen project.

**Spec:** User request dated 2026-11-24: make the Quick Access section in the library sidebar collapsible; add a General settings control to enable or disable it; match the main-area Hero design decisions.

## Global Constraints

- The Quick Access section is expanded when it first appears.
- The collapsed state keeps only the Quick Access section header and title.
- The collapsed state is local and is not persisted.
- The persistent visibility setting defaults to enabled.
- The visibility setting changes the library sidebar without a restart.
- The visibility setting and the collapse state remain separate.
- All animations respect Reduce Motion.
- Gamepad navigation does not select Quick Access filters while the section is collapsed or hidden.
- UI text uses localization keys in `en.json`, `es.json`, `pt.json`, and `ja.json`.
- Do not change the `CFBundleVersion`.

## Review Focus

- A hidden Quick Access section must remove its header and all tiles.
- A collapsed Quick Access section must not retain any tile.
- The section title must remain operable by mouse, keyboard, and VoiceOver.
- General settings and the library sidebar must stay synchronized across separate windows.
- Gamepad navigation must not select a hidden or collapsed Quick Access filter.
- Translation files must remain valid JSON and contain every new key.

---

### Task 1: Persist and expose the Quick Access visibility setting

**Files:**
- Modify: `TruchiEmu/Shared/Models/SystemInfo.swift`
- Modify: `TruchiEmu/Features/Settings/Views/Settings/GeneralSettingsView.swift`
- Modify: `TruchiEmu/Features/Settings/Search/SettingsCatalog.swift`
- Modify: `TruchiEmu/Features/Settings/Views/Settings/SettingsView.swift`
- Modify: `TruchiEmu/Resources/Translations/en.json`
- Modify: `TruchiEmu/Resources/Translations/es.json`
- Modify: `TruchiEmu/Resources/Translations/pt.json`
- Modify: `TruchiEmu/Resources/Translations/ja.json`

**Interfaces:**
- Consumes: `AppSettings.getBool(_:defaultValue:)`, `AppSettings.setBool(_:value:)`.
- Produces: `SystemPreferences.shared.showSidebarQuickAccess: Bool`, persisted under `showSidebarQuickAccess`.

- [x] Add `showSidebarQuickAccess` to `SystemPreferences`, load its saved value during initialization, and persist each change.
- [x] Add a General settings section with a toggle and explanatory text.
- [x] Add the option to General settings matching and the settings catalog.
- [x] Add the same localization keys to all four translation files.
- [x] Verify all translation files parse as JSON and contain the new keys.

### Task 2: Add the animated collapsed Quick Access state

**Files:**
- Modify: `TruchiEmu/Features/Library/Views/Library/SystemSidebarView.swift`

**Interfaces:**
- Consumes: `SystemPreferences.shared.showSidebarQuickAccess`, `AppMotion.stateChange`, and the existing localization manager.
- Produces: A Quick Access section with a local collapsed state and a title-only collapsed layout.

- [x] Observe `SystemPreferences.shared` in the sidebar.
- [x] Add a Quick Access section header above the current tiles.
- [x] Add local expanded state and hide the tiles when the section is collapsed.
- [x] Animate the collapse and visibility changes, or remove animation when Reduce Motion is enabled.
- [x] Remove the complete section from the sidebar when `showSidebarQuickAccess` is false.

### Task 3: Keep gamepad navigation synchronized

**Files:**
- Modify: `TruchiEmu/Features/Library/Services/GamepadNavCoordinator.swift`
- Modify: `TruchiEmu/Features/Library/Views/Library/SystemSidebarView.swift`

**Interfaces:**
- Consumes: Quick Access visibility and expanded state.
- Produces: `GamepadNavCoordinator.visibleSidebarFilters` without `.all`, `.favorites`, `.recent`, or `.retroAchievements` when Quick Access is collapsed or hidden.

- [x] Add Quick Access visibility and expansion state to the gamepad coordinator.
- [x] Filter hidden or collapsed Quick Access filters from the visible gamepad list.
- [x] Update the coordinator when the user collapses or expands the section or changes its visibility setting.

### Task 4: Build and review

**Files:**
- Verify only; no planned source changes.

- [x] Run `git diff --check`.
- [x] Validate all four translation JSON files.
- [x] Run `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`.
- [x] Confirm the build succeeds without new warnings caused by this change.
- [x] Review the final diff for unrelated changes.

# Promote Pills Selected from Other Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Show a filter or sort selected from the “Other” popover in the main library chip row, and show the normal Clear control beside it.

**Architecture:** Derive filter visibility from the existing active-filter state. Keep session-local promotion state only for sorts selected in “Other”, because a sort has no active-filter entry. Make active filters and promoted sorts required in the width-aware layout, and exclude a promoted sort from the popover. Clear removes active filters, selected genres, and promoted sorts.

**Tech Stack:** Swift 5.9, SwiftUI, XcodeGen project.

**Spec:** `docs/superpowers/plans/2026-11-24-promote-active-filter-pills.md`

## Global Constraints

- An active filter selected from “Other” must appear outside the “Other” popover.
- A disabled filter must return to “Other” when space allows.
- A sort selected from “Other” must appear outside the “Other” popover.
- A promoted sort must stay in the main row until it is cycled off or cleared.
- The Clear control must use the existing main-row appearance.
- Clear must appear only for active filters, selected genres, or an active promoted sort.
- Clear must remove active filters, selected genres, and promoted sorts.
- Clear must return a promoted active sort to the default sort.
- The user’s configured pill order must remain intact.
- Disabled filter pills must remain hidden.
- The chip row must not add horizontal scrolling.

## Review Focus

- A sort selected from “Other”, including “Último añadido”, must move to the main row.
- A promoted pill must not remain in the “Other” popover.
- The “Other” badge must not count a promoted active item.
- The Clear control must remain visible while an active promoted sort exists.
- Clear must disappear after the last active filter and the promoted sort are disabled.
- A filter that does not fit must move another optional pill into “Other”.
- A promoted pill must retain its active visual state in the main row.

---

### Task 1: Promote active filter pills in the responsive chip layout

**Files:**
- Modify: `TruchiEmu/Features/Library/Views/Library/LibraryGridView.swift`

**Interfaces:**
- Consumes: `activeFilters: Set<String>`, `pillWidths: [String: CGFloat]`, and `FilterPill`.
- Produces: a responsive visible-pill selection that always includes active filter pills.

- [x] Replace the visible-prefix count with a visible-pill calculation.
- [x] Reserve the measured width of active filter pills and the Clear control.
- [x] Select optional pills in the configured order while keeping active filter pills visible.
- [x] Render the calculated visible pills and send all remaining pills to “Other”.
- [x] Keep the existing Clear control condition and appearance.
- [x] Review the diff for changes outside the chip-layout code.

### Task 2: Promote sorts selected from Other

**Files:**
- Modify: `TruchiEmu/Features/Library/Views/Library/LibraryGridView.swift`
- Modify: `TruchiEmu/Features/Library/Views/Library/LibrarySortPicker.swift`
- Modify: `TruchiEmu/Features/Library/Views/Library/OtherFiltersPopover.swift`

**Interfaces:**
- Consumes: filter and sort actions from `OtherFiltersPopover`.
- Produces: `promotedSorts: Set<LibrarySortOrder>` and a main-row Clear action that removes promotions.

- [x] Add session-local promotion state for sorts selected in “Other”.
- [x] Promote sort pills selected in “Other”.
- [x] Measure and render the special “Último añadir” sort in the main row.
- [x] Exclude a promoted sort from the “Other” popover.
- [x] Show Clear when a promoted sort is active.
- [x] Make Clear remove promotions and reset a promoted active sort.

### Task 3: Remove stale filter promotion state

**Files:**
- Modify: `TruchiEmu/Features/Library/Views/Library/LibraryGridView.swift`

**Interfaces:**
- Consumes: active-filter and promoted-sort state.
- Produces: a Clear condition that depends only on active choices.

- [x] Derive filter promotion from `activeFilters` instead of separate promotion state.
- [x] Remove promoted sort state when the sort is cycled off.
- [x] Keep Clear visible while the promoted sort remains active.
- [x] Hide Clear after the last filter and promoted sort are disabled.

### Task 4: Build and verify

**Files:**
- Verify only; no planned source changes.

- [x] Run `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`.
- [x] Confirm the build succeeds without new warnings caused by this change.
- [x] Confirm the final diff contains only the plan and the targeted chip-layout change.

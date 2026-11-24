# Box Art Undo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let the user undo a successful box art replacement from the Game Info Technical section.

**Architecture:** Capture the previous art file before a replacement. After a successful replacement, keep the capture in the detail view and show an Undo button beside the success result. Undo restores the file, updates the ROM record, and clears the image and thumbnail caches.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Foundation, Xcode

**Spec:** User request from 2026-11-24: a successful box art search must offer an undo action.

## Global Constraints

- Add the undo action only when the downloaded art changes the file.
- Preserve the previous art if the search fails.
- Use `AppColors` and the existing localization system.
- Add every new translation key to `en.json`, `es.json`, `pt.json`, and `ja.json`.
- Do not change the `CFBundleVersion`.

## Review Focus

- A failed replacement must not remove the previous art.
- Undo must restore the exact previous file bytes.
- Undo must refresh the detail view, library cards, thumbnails, and image caches.
- A successful search that does not change the file must not show Undo.
- The Undo result must remain visible until the user acts on it.

---

### Task 1: Capture and restore box art

**Files:**
- Modify: `TruchiEmu/Services/BoxArtService.swift`

**Interfaces:**
- Produces: `BoxArtUndoSnapshot`
- Produces: `BoxArtService.replaceBoxArt(for:preferredTitle:) async -> BoxArtReplacementOutcome`
- Produces: `BoxArtService.restoreBoxArt(_:replacing:) async -> BoxArtRestoreResult`

- [x] Add a snapshot type that stores the previous art URL and file data.
- [x] Add capture and restore methods.
- [x] Clear the image cache and thumbnail files for the replaced art.
- [x] Verify the methods compile with `xcodebuild`.

### Task 2: Add the Undo action to the detail view

**Files:**
- Modify: `TruchiEmu/Views/Detail/GameDetailView.swift`
- Modify: `TruchiEmu/Views/Detail/Sections/Technical.swift`
- Modify: `TruchiEmu/Views/Detail/Sections/ManualStatusController.swift`

**Interfaces:**
- Consumes: `BoxArtService.replaceBoxArt(for:preferredTitle:)`
- Consumes: `BoxArtService.restoreBoxArt(_:replacing:)`

- [x] Add detail view state for the pending box art undo.
- [x] Capture the previous art before the search.
- [x] Restore the previous art when the search fails.
- [x] Store the undo snapshot after a successful replacement.
- [x] Show an Undo button beside the success result.
- [x] Restore the ROM state, refresh the views, and clear the undo state when Undo runs.
- [x] Allow the success result to remain visible until the user acts on it.

### Task 3: Add localized result messages

**Files:**
- Modify: `TruchiEmu/Resources/Translations/en.json`
- Modify: `TruchiEmu/Resources/Translations/es.json`
- Modify: `TruchiEmu/Resources/Translations/pt.json`
- Modify: `TruchiEmu/Resources/Translations/ja.json`

**Interfaces:**
- Produces: `gameInfo.restoringArt`
- Produces: `gameInfo.artRestored`
- Produces: `gameInfo.artRestoreFailed`
- Produces: `gameInfo.artRestorePartial`
- Produces: `gameInfo.artReplaceFailed`
- Produces: `gameInfo.artUndoUnavailable`
- Produces: `gameInfo.artSearchFailedPreviousKept`

- [x] Add the same keys to all four translation files.
- [x] Validate each JSON file with `plutil -lint` or `python -m json.tool`.

### Task 4: Harden the replacement operation

**Files:**
- Modify: `TruchiEmu/Services/BoxArtService.swift`
- Modify: `TruchiEmu/Features/Library/Services/ROMLibrary.swift`
- Modify: `TruchiEmu/Shared/Services/ImageCache.swift`
- Modify: `TruchiEmu/Services/BoxArtThumbnailService.swift`
- Modify: `TruchiEmu/Views/Detail/GameDetailView.swift`
- Modify: `TruchiEmu/Views/Detail/Sections/Technical.swift`

- [x] Download to a temporary file and replace the destination atomically.
- [x] Keep the old file present until the new file is valid.
- [x] Cancel and roll back an operation when the selected game changes.
- [x] Store the ROM ID with the undo state.
- [x] Update only the latest in-memory box-art fields.
- [x] Prevent Fetch and Undo from running at the same time.
- [x] Remove an old duplicate file after a successful replacement.
- [x] Stop when the old file cannot be captured safely.
- [x] Invalidate caches even when a restore is only partly complete.
- [x] Prevent in-flight image loads from restoring stale cached images.
- [x] Keep the Undo action when the result message is dismissed.

### Task 5: Verify the complete flow

**Files:**
- Verify: `TruchiEmu/Services/BoxArtService.swift`
- Verify: `TruchiEmu/Views/Detail/GameDetailView.swift`
- Verify: `TruchiEmu/Views/Detail/Sections/Technical.swift`
- Verify: `TruchiEmu/Shared/Services/ImageCache.swift`
- Verify: `TruchiEmu/Services/BoxArtThumbnailService.swift`

- [x] Run `git diff --check`.
- [x] Validate all four translation JSON files.
- [x] Run the Debug build command.
- [x] Confirm the build succeeds without new errors.

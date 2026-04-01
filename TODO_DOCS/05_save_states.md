# Design Document: Save State Subsystem

## 1. Objective

To implement a high-performance, slot-based **Save State** system that allows users to capture the exact moment of gameplay and resume it instantly. This includes support for visual previews (thumbnails) and "undo" functionality to prevent accidental data loss.

---

## 2. The Libretro API Workflow

Libretro handles save states through **Serialization**. The frontend is responsible for allocating memory and writing it to disk; the core is responsible for filling that memory with its internal state.

### A. The Serialization Sequence

To save a state, your frontend must follow these three steps in order:

1. **Query Size:** Call `retro_serialize_size()`. The core returns the exact number of bytes required for the state.
2. **Allocate Buffer:** Create a memory buffer (or byte array) of that size.
3. **Serialize:** Call `retro_serialize(void *data, size_t size)`. The core populates the buffer.

To load a state:

1. **Unserialize:** Call `retro_unserialize(const void *data, size_t size)`. The core instantly reverts its internal registers and RAM to that state.

---

## 3. Storage Strategy & File Naming

### A. Directory Structure

Keep save states separate from ROMs to keep the game folders clean.

```text
/saves/
    /states/
        /Sony - PlayStation/
            FF7.state      (Auto-save)
            FF7.state1     (Slot 1)
            FF7.state2     (Slot 2)
            FF7.state1.png (Thumbnail for Slot 1)
```

### B. The "Slot" System

Users expect multiple slots.

* **Slot 0-9:** Standard user-selectable slots.
* **Slot -1 (Auto):** Used for "Save on Exit" and "Load on Startup" features.
* **Undo Slot:** A hidden buffer that stores the state *immediately before* a load operation, allowing the user to "Undo Load State."

---

## 4. Visual Previews (Thumbnails)

A save state system is much more usable if the user can see a screenshot of the moment they saved.

1. **Capture:** When the "Save State" command is triggered, grab the current frame buffer from the GPU (or the `video_refresh` callback).
2. **Downscale:** Resize the frame to a small thumbnail (e.g., 320x240) to save disk space.
3. **Sync:** Save the image with the exact same filename as the state file but with a `.png` or `.jpg` extension.
4. **UI:** When the user scrolls through slots in your menu, asynchronously load and display the corresponding thumbnail.

---

## 5. UI/UX Features

### A. Hotkeys

A frontend should support configurable global hotkeys:

* `F5`: Quick Save (current slot)
* `F7`: Quick Load (current slot)
* `0-9`: Select Slot
* `H`: Increment Slot / `G`: Decrement Slot

### B. On-Screen Notifications (OSD)

Since save states happen instantly, the user needs feedback. Use your font rendering system to display a brief overlay:

* *"Saved to Slot 1"*
* *"Loaded Slot 1"*
* *"Error: State size mismatch"* (Happens if the user updates the core version and the old state is no longer compatible).

### C. The "Undo" Safety Net

Accidentally hitting "Load" instead of "Save" can ruin hours of progress.

1. User hits **Load**.
2. Frontend calls `retro_serialize()` into a `temporary_undo_buffer`.
3. Frontend calls `retro_unserialize()` from the requested slot.
4. If the user realizes they made a mistake, they hit **Undo Load**, and the frontend restores the `temporary_undo_buffer`.

---

## 6. Technical Implementation Checklist (C++/Pseudocode)

```cpp
// Logic for Saving a State
void save_state(int slot) {
    size_t size = retro_serialize_size();
    if (size == 0) return; // Core doesn't support save states

    void* buffer = malloc(size);
    if (retro_serialize(buffer, size)) {
        string path = get_state_path(current_game, slot);
        write_file_to_disk(path, buffer, size);
        
        // Also save a screenshot
        save_screenshot(path + ".png");
        show_osd_message("Saved State: Slot " + to_string(slot));
    }
    free(buffer);
}

// Logic for Loading a State
void load_state(int slot) {
    string path = get_state_path(current_game, slot);
    size_t size;
    void* buffer = read_file_from_disk(path, &size);
    
    if (buffer) {
        // Optional: Perform 'Undo' backup here
        retro_unserialize(buffer, size);
        show_osd_message("Loaded State: Slot " + to_string(slot));
        free(buffer);
    }
}
```

---

## 7. Advanced: RAM States vs. Disk States

* **Rewind Support:** If you want to implement "Rewind," you simply run the `save_state` logic into a circular buffer in RAM every few frames. This is very CPU/RAM intensive.
* **Compression:** Some states (like for N64 or PS1) can be 20MB+. Consider using `zlib` or `lz4` to compress the buffer before writing it to disk to save space and reduce SSD wear.

## 8. Warning: Core Compatibility

Note that some Libretro cores have "Deterministic" states and some don't.

* **Deterministic:** Loading a state works 100% of the time (SNES, NES, Genesis).
* **Non-Deterministic:** Loading a state might cause audio crackling for a split second (some 3D systems like Saturn or complex PC emulators).
* **No Support:** Some cores (rare) return `0` for `retro_serialize_size`. Your UI should grey out the "Save State" button in these cases.

---

## 9. Implementation Plan — Sequential Feature Checklist

> **Rule:** Build one feature at a time, verify compilation, then proceed to the next.

### Phase 1: Core Infrastructure
- [x] **Feature 1: SaveStateManager Service** — Create `SaveStateManager.swift`
  - [x] `@MainActor class SaveStateManager: ObservableObject`
  - [x] Directory management: `~/Library/Application Support/TruchieEmu/saves/states/<System>/`
  - [x] Path resolution: `statePath(for gameName: String, systemID: String, slot: Int) -> URL`
  - [x] Thumbnail path: `thumbnailPath(for gameName: String, systemID: String, slot: Int) -> URL`
  - [x] Slot enumeration: `allSlotInfo(for gameName: String, systemID: String) -> [SlotInfo]`
  - [x] `SlotInfo` struct: `id: Int, exists: Bool, fileSize: Int64?, modificationDate: Date?`
  - [x] Auto-create directories on first access

- [x] **Feature 2: Libretro Bridge Extensions** — Extend `LibretroBridge` (`LibretroBridge.h` + `LibretroBridge.mm`)
  - [x] `+ (NSData *)serializeState;` — Returns serialized state as NSData (or nil)
  - [x] `+ (BOOL)unserializeState:(NSData *)data;` — Returns true on success
  - [x] `+ (size_t)serializeSize;` — Returns `retro_serialize_size()`
  - [x] Keep existing `saveState()` for backward compatibility

- [x] **Feature 3: EmulatorRunner Save/Load** — Extend `EmulatorRunner.swift`
  - [x] `@Published var currentSlot: Int = 0`
  - [x] `@Published var osdMessage: String?` (for OSD)
  - [x] `func saveState(slot: Int) -> Bool` — Uses SaveStateManager + LibretroBridge
  - [x] `func loadState(slot: Int) -> Bool` — Uses SaveStateManager + LibretroBridge
  - [x] `var undoBuffer: Data?` — Stores state before load for undo
  - [x] `func undoLoadState() -> Bool` — Restores from undoBuffer
  - [x] Check core support: `var supportsSaveStates: Bool { LibretroBridge.serializeSize() > 0 }`
  - [x] `func nextSlot()` / `func previousSlot()` — Slot cycling helpers

### Phase 2: User Interface
- [x] **Feature 4: HUD Slot Selection** — Modify `EmulatorView.swift` HUD
  - [x] Add slot indicator display: `"Slot: \(currentSlot)"`
  - [x] Add slot +/- buttons in HUD
  - [x] Add slot picker sheet/grid showing slots 0-9 (`SlotPickerSheet.swift`)
  - [x] Visual indicator for which slots have saved states (checkmark + thumbnail)
  - [x] Replace existing `runner.saveState()` call with slot-aware version

- [x] **Feature 5: Thumbnails** — Integrate with save/load flow
  - [x] Capture `currentFrameTexture` during save, convert to CGImage via `NSImageFromMTLTexture`
  - [x] Save as PNG alongside `.state` file with `.png` extension
  - [x] Load and display thumbnail in slot picker
  - [x] Thumbnail loading in slot picker with 320x240 downscaling

- [x] **Feature 6: OSD Notifications** — Add overlay messages
  - [x] `@Published var osdMessage: String?` in EmulatorRunner
  - [x] Auto-dismiss after 2 seconds with `Task.sleep`
  - [x] Messages: "Saved Slot X", "Loaded Slot X", "Error: State file not found", "Error: Core doesn't support save states"
  - [x] Display in EmulatorView HUD area

- [x] **Feature 7: Undo Load State** — Safety net implementation
  - [x] Before `loadState`, serialize current state into `undoBuffer`
  - [x] Add "Undo" button in HUD (visible briefly after load)
  - [x] `undoLoadState()` function restores from `undoBuffer`
  - [x] OSD: "Undo successful" / "Nothing to undo"

### Phase 3: Input & Automation
- [x] **Feature 8: Hotkeys** — Keyboard shortcuts in `FocusableMTKView`
  - [x] `F5` — Quick Save (current slot)
  - [x] `F7` — Quick Load (current slot)
  - [x] `F6` — Slot +1 (cycle 0-9)
  - [x] `F4` — Slot -1 (cycle 0-9)
  - [x] `Cmd+Z` — Undo Load
  - [x] OSD feedback for each hotkey action (via runner's osdMessage)

- [x] **Feature 9: Compression** — LZ4 compression for state files
  - [x] Use `compression` framework (Apple's built-in)
  - [x] Compress before writing to disk
  - [x] Decompress when reading from disk
  - [x] Magic header to distinguish compressed vs uncompressed (backward compat)
  - [x] OSD: "Compressed: 15.2 MB -> 4.8 MB"
  - [x] UI toggle in SlotPickerSheet: "Compress Save States"

### Phase 4: Automation
- [x] **Feature 10: Auto-Save / Auto-Load**
  - [x] Auto-save to slot `-1` on `onDisappear` / app quit
  - [x] Auto-load from slot `-1` on launch (if exists)
  - [x] User preference toggles in Settings > General: "Auto-save on game exit", "Auto-load on game start", "Compress save states"
  - [x] OSD on launch: "Auto-loaded last session"

---

## 10. Current Progress Tracker

**Next up:** Feature 1 — SaveStateManager Service
**Status:** Ready to implement

### Implementation Order
1. ✅ This plan document
2. ⬜ SaveStateManager.swift (Feature 1)
3. ⬜ LibretroBridge extensions (Feature 2)
4. ⬜ EmulatorRunner save/load (Feature 3)
5. ⬜ HUD updates (Features 4-8)
6. ⬜ Compression (Feature 9)
7. ⬜ Auto-save/load (Feature 10)

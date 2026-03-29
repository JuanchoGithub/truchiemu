# Design Document: Cheat Code Subsystem

## 1. Objective

To implement a cheat code system compatible with the standard **Libretro Cheat Database (`.cht` files)**. The frontend will be responsible for parsing these files, managing a list of active cheats, and injecting them into the emulator core's memory.

---

## 2. The Cheat Database Strategy

Rather than making users type codes manually, your frontend should leverage the existing [libretro-database/cheats](https://github.com/libretro/libretro-database/tree/master/cht) repository.

### A. Directory Structure

```text
/assets/cheats/
    /Nintendo - Super Nintendo Entertainment System/
        Super Mario World (USA).cht
        The Legend of Zelda - A Link to the Past (USA).cht
```

### B. The `.cht` File Format

RetroArch cheats use a simple key-value format. You will need a parser for this:

```ini
cheats = 2
cheat0_desc = "Infinite Lives"
cheat0_code = "7E0DBE05"
cheat0_enable = false

cheat1_desc = "Invincibility"
cheat1_code = "7E1490FF"
cheat1_enable = false
```

---

## 3. Core Interaction (The API)

There are two ways Libretro handles cheats. Your frontend should support both:

### Method A: The Core-Side Approach (Standard)

The core handles the logic. You simply pass the code string to the core.

* **Function:** `retro_cheat_reset()` — Clears all active cheats in the core.
* **Function:** `retro_cheat_set(unsigned index, bool enabled, const char *code)` — Tells the core to activate a specific code.
* **Limitation:** Not all cores implement this.

### Method B: The Frontend-Side Approach (Direct Memory Access)

If the core doesn't support `retro_cheat_set`, the frontend "patches" the RAM directly.

1. **Identify Memory:** Call `retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM)`.
2. **Parse Code:** Translate a Game Genie/Pro Action Replay code into a **Memory Address** and a **Value**.
    * *Example:* `7E0DBE05` -> Address `0x0DBE`, Value `05`.
3. **Inject:** Every frame (or every few frames), your frontend writes `05` to the offset `0x0DBE` in the RAM buffer.

---

## 4. Cheat Type Support

You should implement decoders for the most common retro formats:

* **Raw/Memory Address:** (e.g., `7E0DBE05`) Direct Hex address and value.
* **Game Genie:** (e.g., `G0X-Y1Z`) Requires a mathematical conversion to find the address/value.
* **Pro Action Replay (PAR):** Very common for SNES/Genesis.
* **GameShark:** Common for PS1/N64.

---

## 5. UI/UX Requirements

### A. The Cheat Manager Menu

A sub-menu in your "Quick Menu" while a game is running:

* **Load Cheat File:** Automatically looks for a `.cht` file matching the game's filename.
* **Cheat List:** A list of toggles (On/Off) for every code found in the file.
* **Add Custom Code:** A text input field for users to paste codes from the internet.

### B. "Apply Changes" Logic

To avoid crashing the core, cheats should be applied in a specific order:

1. User toggles three cheats in the UI.
2. User selects "Apply Cheats."
3. Frontend calls `retro_cheat_reset()`.
4. Frontend loops through enabled cheats and calls `retro_cheat_set()` for each.

---

## 6. Conflict Management: RetroAchievements

**Important:** Cheat codes and RetroAchievements "Hardcore Mode" are incompatible.

* **Logic:** If RetroAchievements Hardcore Mode is enabled, the "Cheats" menu must be **disabled** or hidden.
* **Logic:** If the user activates a cheat, the frontend must notify the `rcheevos` library to drop the session into "Softcore" (non-hardcore) mode immediately.

---

## 7. Technical Implementation Checklist

### [ ] The Cheat Parser

Create a class to ingest `.cht` files and store them in an array of `Cheat` objects:

```cpp
struct Cheat {
    int index;
    string description;
    string code;
    bool enabled;
};
```

### [ ] Search Functionality

Since some cheat files contain hundreds of codes (e.g., for *Final Fantasy*), add a simple text filter in your UI to find "Gold" or "Health" quickly.

### [ ] Persistent State

When a user enables a cheat, save that state. Create a "Global User Cheats" file so that when they reload the game tomorrow, their "Infinite Lives" toggle is still `true`.

### [ ] Format Converters

Include a utility library (like `libretro-common`'s cheat utilities) to translate Game Genie strings into raw hex addresses that the Libretro memory map can understand.

---

## 8. Summary of Flow

1. **Load Game:** Frontend identifies `SuperMario.sfc`.
2. **Auto-Load:** Frontend checks `cheats/SNES/SuperMario.cht`.
3. **Menu:** User opens Overlay -> Cheats -> Toggles "Infinite Time."
4. **Execution:** Frontend sends code to `retro_cheat_set` OR writes to the `RETRO_MEMORY_SYSTEM_RAM` pointer every frame.
5. **Save:** Frontend writes the `enabled=true` state to its local config.

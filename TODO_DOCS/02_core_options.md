Designing a "Core Options" system for a custom Libretro frontend requires building a bridge between the **Emulator Core** (which defines the logic) and your **Frontend UI/Storage** (which manages user choices).

Here is a design document for implementing this feature.

---

# Design Document: Core Options Subsystem

## 1. Objective

To allow users to modify emulator-specific internal settings (e.g., PS1 load speeds, internal resolution) via the frontend UI and persist these settings to disk at a Global, Core, or Game level.

---

## 2. Core Communication (The API)

Libretro cores communicate their available options through "Environment Callbacks." Your frontend must implement a handler for these specific `libretro.h` environment constants:

### A. Discovery Phase

When a core is loaded (`retro_load_game`), it will send one of two callbacks to the frontend:

1. **`RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2` (Modern/Priority):** Provides grouped categories (e.g., "Video," "System"), localized names, and detailed descriptions.
2. **`RETRO_ENVIRONMENT_SET_VARIABLES` (Legacy):** Provides a simple array of `retro_variable` structs (Key/Value pairs with a string of choices).

**Requirement:** Your frontend must parse these structures and build an internal **Option Map** for the current session.

### B. Retrieval Phase

During runtime, the core will call:

* **`RETRO_ENVIRONMENT_GET_VARIABLE`**: The core passes a "Key" (e.g., `beetle_psx_hw_cd_speed`), and your frontend must return the "Value" currently selected by the user.

---

## 3. Data Model & Storage Strategy

To handle the "Per-Game/Per-Core" requirement you encountered with PS1 loading, use a **Layered Configuration** model.

### Storage Hierarchy (The "Override" Stack)

When a core asks for a value, the frontend should check these locations in order:

1. **Game-Specific File:** `config/options/{CoreName}/{GameName}.opt`
2. **Core-Specific File:** `config/options/{CoreName}/{CoreName}.opt`
3. **Global File:** `config/options/global.opt`
4. **Core Default:** The first option in the list provided by the core.

### File Format (Recommended: `.opt` or `.ini`)

Keep it simple key-value:

```ini
# SwanStation PS1 Options
swanstation_CDROM_Read_Speed = "8x"
swanstation_CDROM_Seek_Speed = "Instant"
swanstation_GPU_Internal_Resolution = "4x"
```

---

## 4. UI/UX Flow

### Step 1: Menu Generation

* **Dynamic Parsing:** Do not hardcode menus. When the core sends `SET_CORE_OPTIONS_V2`, iterate through the `retro_core_option_v2_category` list to create sub-menus.
* **Input Types:** Most options are "Cycles" (Left/Right to change). Some modern cores support booleans or integers, but treat almost everything as a "String List" for maximum compatibility.

### Step 2: The "Variable Update" Loop

If a user changes an option in your UI while the game is running:

1. Update your internal **Option Map**.
2. Set a boolean flag `variables_updated = true`.
3. When the core calls the environment callback for `RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE`, return `true` to the core. This signals the core to re-read all settings immediately.

---

## 5. Technical Implementation Checklist

### [ ] Handle `retro_variable` Structs

You need a data structure to store the metadata provided by the core:

```cpp
struct CoreOption {
    string key;
    string label;
    string description;
    vector<string> values;
    int current_index;
    string category_key;
};
```

### [ ] Implement the Env Callback

In your `retro_environment_t` handler:

```cpp
bool environment_callback(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
            // 1. Parse categories
            // 2. Parse options and store labels/descriptions
            // 3. Compare against saved .opt files to set 'current_index'
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE:
            // 1. Cast data to retro_variable*
            // 2. Lookup key in your Option Map
            // 3. Return the string value
            return true;
    }
}
```

### [ ] Config Management UI

Add a "Manage Options" submenu to your In-Game Overlay:

* **Option:** "Save Game Options" (Writes current Map to `{GameName}.opt`)
* **Option:** "Save Core Options" (Writes current Map to `{CoreName}.opt`)
* **Option:** "Reset to Defaults" (Deletes the `.opt` file)

---

## 6. Edge Cases to Consider

* **Restarts Required:** Some cores cannot change settings (like BIOS type) mid-session. The `SET_CORE_OPTIONS` struct often includes a `reboot_required` flag. Your UI should display a "Restart Core to Apply" message if this is true.
* **Core Updates:** Sometimes core developers change a "Key" name. If your frontend finds a saved value for a key that no longer exists in the core, it should ignore it and clean the file.
* **Invisible Options:** Some options are marked as "Visible: false" by the core depending on other settings (e.g., "Resolution" might be hidden if "Software Rendering" is selected). Your UI needs to respect the visibility flags.

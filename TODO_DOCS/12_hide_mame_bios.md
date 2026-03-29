# Design Document: MAME BIOS Management & UI Filtering

## 1. Objective

To clean up the Arcade/MAME game list by preventing BIOS files (e.g., `neogeo.zip`, `qsound.zip`) from appearing as playable games, while ensuring the emulator can still find them to launch actual games.

---

## 2. Strategy A: The "Centralized BIOS" Approach (Cleanest)

Most modern Libretro MAME cores (MAME Current, FBNeo) are programmed to look in the **Libretro System Directory** if a BIOS isn't found in the game folder.

### Implementation

1. **Define a System Path:** In your frontend settings, set a global `system_directory` (e.g., `/userdata/system/`).
2. **Create a MAME BIOS Subfolder:** Instruct the user (or automate the move) to place BIOS files in `system/mame/` or `system/fbneo/`.
3. **Core Configuration:** When launching the core, the frontend passes the system path. The core will automatically search this secondary location for missing dependencies like `neogeo.zip`.

---

## 3. Strategy B: The "UI Filter" Approach (Most Compatible)

Some MAME versions are strict and prefer BIOS files to be in the *same* folder as the ROMs. In this case, we keep the files together but "mask" them in the UI.

### Implementation: The "Is_BIOS" Flag

Your game scanner should check every ZIP against a **Known BIOS Database**.

#### 1. The Hardcoded Blacklist (Simple)

Maintain a JSON list of the ~60 most common MAME BIOS filenames.

```json
{
  "mame_bios": ["neogeo", "cpzn1", "cpzn2", "cvs", "decocass", "konamigx", "nmk004", "pgm", "playch10", "skns", "stvbios", "vmax3"]
}
```

* **Logic:** If `filename_without_ext(zip_file)` matches an entry in this list, set `metadata.is_hidden = true`.

#### 2. The MAME XML/DAT Parser (Robust)

The "Official" way to do this is to parse a MAME metadata file (`mame.xml`).

* **Source of Truth:** In a MAME DAT file, BIOS entries are explicitly tagged:

    ```xml
    <game name="neogeo" isbios="yes">
        <description>Neo-Geo BIOS</description>
    </game>
    ```

* **Logic:** During the folder scan, if the XML entry for a ZIP has `isbios="yes"`, exclude it from the "All Games" view.

---

## 4. Technical Workflow for the Scanner

1. **Scan Loop:** Iterate through all `.zip` files in the Arcade directory.
2. **Identity Check:**
    * Query the local database/blacklist: *Is this `neogeo.zip`?*
    * If **Yes**:
        * Add to database with `is_playable = false` and `category = "BIOS"`.
    * If **No**:
        * Add to database with `is_playable = true`.
3. **UI Filter:** When populating the game list menu, only `SELECT * FROM games WHERE is_playable = true`.

---

## 5. UI/UX: The "Show BIOS" Toggle

To help power users troubleshoot, add a hidden setting:

* **Setting:** `Settings > Library > Show BIOS Files in Game List` (Default: Off).
* **Function:** If toggled ON, the UI ignores the `is_playable` flag and shows everything. This is useful for users to verify they actually *have* the `neogeo.zip` in the right place.

---

## 6. Edge Case: Parent/Clone Relationships

In MAME, a "Parent" ROM (e.g., `pacman.zip`) is required to play a "Clone" (e.g., `pacman_japanese.zip`).

* **Warning:** Do not treat "Parent" ROMs as BIOS. Parents are playable games. Only files tagged `isbios="yes"` in the MAME XML should be hidden.

---

## 7. Technical Implementation Checklist

### [ ] Integrated Blacklist

Embed a list of common BIOS names into your frontend's binary so it works "out of the box" without extra XML files.

### [ ] Metadata Flagging

Add an `is_bios` boolean field to your SQLite/JSON game database.

### [ ] Search Path Injection

Ensure your Libretro environment callback for `RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY` returns the path where you’ve instructed users to put BIOS files.

### [ ] Asset Cleanup

If a file is identified as a BIOS, the **Boxart Search (Design Doc #2)** should be skipped for that file to save bandwidth and prevent "No Image Found" icons for BIOS files.

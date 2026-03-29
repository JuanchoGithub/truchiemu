# Design Document: Smart ZIP Identification & Routing

## 1. Objective

To solve "ZIP Confusion" where the frontend defaults all compressed files to MAME. The goal is to implement a multi-tiered detection system that correctly routes ZIP files to **MAME**, **DOSBox**, **ScummVM**, or **BIOS/System** folders based on content and context.

---

## 2. The "Multi-Tier" Detection Strategy

Instead of relying solely on the `.zip` extension, the frontend will use a priority-based identification flow.

### Tier 1: Path-Based Context (Primary)

The simplest and most effective method. Assign cores based on the parent directory name.

* `roms/mame/` -> Map to **MAME Core**
* `roms/dos/` -> Map to **DOSBox-Pure Core**
* `roms/scummvm/` -> Map to **ScummVM Core**
* `roms/bios/` or `system/` -> **Ignore** (Mark as non-playable)

### Tier 2: Content "Fingerprinting" (Deep Inspection)

If a ZIP is in a generic folder or "Downloads," the frontend must peek inside the ZIP (without extracting the whole thing) to identify its purpose.

| If ZIP contains... | Identify As |
| :--- | :--- |
| `.exe`, `.com`, `.bat`, or `config.sys` | **DOS Game** |
| `.scummvm` file or engine-specific data (`.sou`, `.000`) | **ScummVM** |
| Only `.bin` or `.rom` files with cryptic 8-character names | **MAME/Arcade** |
| `.sfc`, `.nes`, `.md`, `.gba` | **Console ROM** |

### Tier 3: Known BIOS Database (Exclusion List)

Prevent BIOS files (like `neogeo.zip` or `pgm.zip`) from showing up in the game list as playable titles.

* **Implementation:** Maintain a hardcoded array of known Arcade BIOS filenames.
* **Logic:** If `filename` is in `Arcade_BIOS_List`, hide it from the UI but keep it in the folder for the emulator to find.

---

## 3. Technical Implementation: The "Router"

### A. The ZIP Manifest Parser

When scanning a directory, use a "light" ZIP header reader (like `libzip` or `miniz`) to list files without decompressing.

```cpp
struct GameIdentity {
    string platform; // "dos", "mame", "scummvm", "bios"
    string core_path;
};

GameIdentity identify_zip(string zip_path) {
    auto files = get_zip_file_list(zip_path);
    
    // Check for DOS
    if (contains_any(files, {".exe", ".bat", ".com"})) 
        return {"dos", "dosbox_pure_libretro.so"};
        
    // Check for ScummVM
    if (contains_ext(files, ".scummvm")) 
        return {"scummvm", "scummvm_libretro.so"};

    // Check against BIOS list
    if (is_known_bios(zip_path))
        return {"bios", ""}; // Mark as hidden
        
    // Default to Arcade if names look like MAME (short, cryptic)
    if (is_mame_naming_convention(files))
        return {"mame", "mame_libretro.so"};

    return {"unknown", ""};
}
```

---

## 4. UI/UX: The "Ambiguity Resolver"

If the identification logic is unsure (e.g., a ZIP contains both an `.exe` and a `.bin`), the frontend should prompt the user **once**.

1. **The Prompt:** "We found a new ZIP file. Is this a DOS game or an Arcade game?"
2. **The Memory:** Save this choice in your metadata database (`games.db`) so the user never has to choose again for that file.
3. **Manual Override:** Add a "Change Default Core" option in the game's context menu (Right-click/Long-press).

---

## 5. Handling ScummVM Specifically

ScummVM is unique because it often requires a `.scummvm` file to tell the core which engine to use.

* **The Problem:** Many users just have a folder or ZIP of data files.
* **The Fix:** If your frontend identifies a ZIP as ScummVM, it should **auto-generate** a temporary `.scummvm` file or pass the directory path to the core using the `RETRO_ENVIRONMENT_SET_VARIABLES` API to ensure the core knows how to boot it.

---

## 6. Workflow for the Frontend Scanner

1. **Scan Folder:** Find all `.zip` files.
2. **Filter BIOS:** If `neogeo.zip`, move to internal "System/BIOS" category (hidden from main UI).
3. **Check Directory:** If in `/dos/`, assign `DOSBox-Pure`.
4. **Inspect Internal Header:**
    * If `AUTOEXEC.BAT` exists -> Category: DOS.
    * If `TENTACLE.001` exists -> Category: ScummVM.
5. **Database Update:** Store the path, the identified system, and the recommended core.
6. **Display:** The user sees "Prince of Persia" (DOS) and "Metal Slug" (MAME) correctly categorized, even though both are just `.zip` files.

---

## 7. Summary Checklist

- [ ] Implement path-aware core assignment (Folder = System).
* [ ] Add a "Lightweight ZIP Header Reader" to the scanner.
* [ ] Create a `Known_BIOS_List` to prevent `neogeo.zip` from cluttering the game list.
* [ ] Add an "Association" table to your local DB to store manual core overrides.
* [ ] Implement a "Core Picker" UI for when identification fails.

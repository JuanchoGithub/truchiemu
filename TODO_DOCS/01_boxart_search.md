# Design Document: Libretro Thumbnail Integration (V2)

## 1. Objective
To implement an automated boxart and metadata visual system by leveraging the **libretro-thumbnails** ecosystem. This system will prioritize **data integrity via CRC matching** over fragile filename matching, ensuring the correct artwork is displayed even if the user's ROM files are poorly named.

---

## 2. Technical Architecture

### A. Resource Discovery (The CDN)
* **Base URL:** `https://thumbnails.libretro.com/`
* **Structure:** `{System_Name}/{Type}/{Game_Name}.png`

### B. Directory & Type Mapping
1. **`Named_Boxarts`**: Physical packaging (Priority 1).
2. **`Named_Snaps`**: Gameplay screenshots (Priority 2).
3. **`Named_Titles`**: Game title screens (Priority 3).

---

## 3. The "Matching" Logic (Source of Truth)

Unlike traditional scrapers that guess based on filenames, this implementation uses a three-tier identification strategy.

### Tier 1: CRC-to-DAT (The Gold Standard)
The frontend will not rely on the ROM filename. Instead:
1.  **Calculate CRC32** of the ROM file.
2.  **Lookup CRC** in the official Libretro/No-Intro DAT file for that system.
3.  **Extract the `<machine name>`** attribute. This is the "Clean Name" used by the thumbnail server.

### Tier 2: Filename Sanitization (Fallback)
If the CRC is not found in the DAT, sanitize the ROM filename:
1.  **Strip Tags:** Remove common tags (e.g., `[!]`, `(USA)`, `(En,Fr)`).
2.  **Clean Whitespace:** Trim leading/trailing spaces.

### Tier 3: Character Replacement Algorithm
Once a "Clean Name" is obtained (from DAT or Sanitization), it must be transformed to match Libretro’s filesystem-safe naming convention:

| Forbidden Character | Replacement |
| :--- | :--- |
| `&` | `_` |
| `*`, `:`, `?`, `"`, `<`, `>`, `\|` | `_` |
| `/`, `\` | `_` |

*Note: Libretro replaces almost all special punctuation with a literal underscore `_` to ensure cross-platform compatibility.*

---

## 4. Implementation Workflow

### Step 1: System Mapping
Map internal system keys to Libretro’s official folder names:
* `nes` $\rightarrow$ `Nintendo - Nintendo Entertainment System`
* `megadrive` $\rightarrow$ `Sega - Mega Drive - Genesis`

### Step 2: URL Construction
For a file `adv-aba.nes` with CRC `67123456`:
1. **DAT Lookup:** `67123456` $\rightarrow$ `Abadox: The Deadly Inner War (USA)`
2. **Sanitize:** `Abadox_ The Deadly Inner War (USA)`
3. **URL:** `.../Named_Boxarts/Abadox_The_Deadly_Inner_War_(USA).png`

### Step 3: Handling Local Variants
If the user provides a local directory of images containing multiple variants (e.g., `Game (USA).png`, `Game (USA) [b1].png`):
1.  **Strict Match:** Look for the sanitized name exactly.
2.  **Shortest-Match Heuristic:** If multiple files start with the sanitized name, select the one with the **shortest string length**. This effectively filters out "bad dump" `[b]` or "hacked" `[h]` versions in favor of the clean original.



---

## 5. UI/UX Requirements

### A. Bulk Downloader (Background Task)
* **Asynchronous Queue:** Process 3–5 concurrent downloads.
* **Smart Skip:** Do not request files that already exist in the local cache.

### B. Fallback Chain
If a request returns a **404**:
1. Try `Named_Boxarts` (Sanitized Name)
2. Try `Named_Titles` (Sanitized Name)
3. Try `Named_Snaps` (Sanitized Name)
4. **Fuzzy Fallback:** Strip parentheses `( )` from the name and try `Named_Boxarts` again (e.g., `Game Name.png` instead of `Game Name (USA).png`).

---

## 6. Optimization & "Pro" Features

* **URL Encoding:** Ensure the final URL is percent-encoded (e.g., spaces to `%20`).
* **Head Requests:** Optionally use HTTP `HEAD` to check for image existence before full download.
* **User-Agent:** Use `[FrontendName]/[Version] (ContactInfo)` to assist Libretro server admins.
* **Pre-computed DAT Hashmap:** Load system DAT files into a Dictionary/Hashmap at startup for $O(1)$ CRC lookups.

---

## 7. Configuration Variables
* `thumbnail_server_url`: `https://thumbnails.libretro.com/`
* `priority_type`: (Boxart, Snap, or Title)
* `use_crc_matching`: (Default: True)
* `fallback_to_filename`: (Default: True)
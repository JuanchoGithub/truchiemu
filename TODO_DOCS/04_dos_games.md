Libretro is actually the **preferred** way to play DOS games on a modern frontend because of a specific core called **DOSBox-Pure**.

While standalone DOSBox is a "command line first" experience, **DOSBox-Pure** was built specifically for Libretro frontends to make DOS games feel like console games.

# Design Document: DOS Emulation Subsystem

## 1. Objective

To integrate DOS emulation that supports "Console-style" features: loading from ZIP files, automatic controller mapping, save states, and a simplified "Start Menu" for game executables.

---

## 2. Core Selection: Why DOSBox-Pure?

While there are other cores (`DOSBox-SVN`, `DOSBox-core`), your frontend should prioritize **DOSBox-Pure** for these reasons:

* **ZIP Support:** You can load a `.zip` file containing the game directly. The core mounts it as a C: drive automatically.
* **Save States:** Unlike standard DOSBox, Pure supports full Libretro save states.
* **Rewind:** Supports the Libretro rewind API.
* **Auto-Mapping:** It automatically maps common DOS keyboard controls (Arrow keys, Space, Ctrl) to a standard game controller.
* **On-Screen Keyboard:** Built-in for when you need to type a character name.

---

## 3. Game Discovery & Loading Logic

Unlike a PS1 game (one file), a DOS game is a folder full of `.EXE`, `.COM`, and `.BAT` files.

### A. The "ZIP as a Game" Pattern (Recommended)

Encourage users to keep each DOS game in a single `.zip` file.

1. Frontend passes `GameName.zip` to the Libretro Core.
2. DOSBox-Pure detects multiple executables.
3. **The "Start Menu" Feature:** Instead of a command prompt, the core displays a graphical menu inside the emulator asking the user which file to run (e.g., `SETUP.EXE` vs `PLAY.EXE`).

### B. The `.conf` Pattern (Power Users)

If a user has a specific setup, they can provide a `.conf` file. Your frontend should recognize `.conf` as a valid "ROM" extension for the DOS system.

---

## 4. Input Mapping Strategy

DOS games use three distinct input types. Your frontend needs to tell the user which mode is active via your UI:

1. **Gamepad Mode (Default):** Maps the D-Pad to Arrow Keys and Buttons to Enter/Space/Alt.
2. **Mouse Mode:** The Left Analog stick moves the PC mouse cursor. Trigger buttons act as Left/Right Click.
3. **Keyboard Passthrough:** For games that require actual typing.

**Implementation Tip:** Use the Libretro `environ` call `RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS` to allow the core to tell your frontend what the buttons currently do so you can display a "Controller Overlay" to the user.

---

## 5. Performance: The "Cycles" Problem

DOS games don't have a fixed frame rate; they run based on "CPU Cycles."

* **The Issue:** An 80s game runs too fast on a 90s CPU setting.
* **The Solution:** DOSBox-Pure has an "Auto" cycle setting.
* **Frontend Integration:** In your **Core Options** menu (from the previous design doc), make sure to expose the `dosbox_pure_cycles` variable.
  * *Values:* `Auto`, `3000` (8088/XT), `8000` (286), `25000` (386), `Max` (Pentium).

---

## 6. Boxart & Metadata Matching

Since DOS games don't have a standard "Serial Number" (like PS1's SLUS-00001), matching boxart is harder.

**The Solution:**

* Use the **Clean Name** of the ZIP file or the Folder.
* Cross-reference with the [Libretro Thumbnails: DOS repository](https://github.com/libretro-thumbnails/DOS).
* *Example:* If the file is `Prince of Persia (1989).zip`, your scraper should search for `Prince of Persia (1989).png`.

---

## 7. Technical Workflow for the Frontend

### Step 1: System Config

Define the DOS system in your frontend:

* **Core:** `dosbox_pure_libretro.so` (or `.dll`/`.dylib`)
* **Extensions:** `.zip`, `.dosz`, `.conf`, `.exe`, `.bat`

### Step 2: The "BIOS" (Standardization)

DOSBox does not require a BIOS file (it emulates DOS itself), but for high-end games, users might want **Gravis Ultrasound** support.

* Direct the user to place `ultrasnd` folder in your frontend's `system/` directory.

### Step 3: Handling Multi-Disc Games

DOSBox-Pure handles multi-disc games (like *Monkey Island 2*) by allowing the user to "Load Disc" from the Libretro Disk Control API.

* **Design Task:** Ensure your frontend UI has a "Disk Control" menu that triggers the Libretro Disk Swap functions.

---

## Summary Checklist for your Frontend

* [ ] Support `.zip` files as the primary ROM format for DOS.

* [ ] Implement the **Core Options** UI to allow cycle speed adjustment.
* [ ] Add **Disk Control** UI for swapping floppy disks/CDs.
* [ ] Map the "Mouse Toggle" (usually a specific button combo) so users can play point-and-click adventures.

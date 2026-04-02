# TruchieEmu Controller Configuration

## Overview

TruchieEmu provides comprehensive controller and keyboard configuration for all supported libretro systems. Each system has its own set of available buttons, default mappings for both right-handed and left-handed users, and system-specific features.

## Controller Configuration

### Handedness

TruchieEmu supports both **left-handed** and **right-handed** controller configurations:

- **Right-handed (default)**: Primary buttons (A, B) are mapped to the right side of the controller face buttons
- **Left-handed**: Primary buttons are swapped so A/B are on the left side (X/Y positions)

**To change handedness:** Go to Settings → Controller → Handedness preference.

### Turbo Buttons

Turbo buttons auto-rapidly press their associated button while held (about 10 presses/second), useful for games that require button mashing.

**Supported Turbo Systems:**
- **NES**: Turbo A, Turbo B
- **SNES**: Turbo A, Turbo B, Turbo X, Turbo Y
- **Genesis/Mega Drive**: Turbo A, Turbo B, Turbo X, Turbo Y
- **ScummVM**: Turbo A (for rapid clicking)

**Default Turbo Mapping (Right-handed NES):**
- Turbo A → X button
- Turbo B → Y button

**Default Turbo Mapping (Left-handed NES):**
- Turbo A → A button
- Turbo B → B button

---

## System Reference

### Nintendo Entertainment System (NES)

**Available Buttons:** D-Pad, A, B, Turbo A, Turbo B, Start, Select

| Function   | Right-Handed | Left-Handed |
|------------|--------------|-------------|
| D-Pad      | D-Pad        | D-Pad       |
| A Button   | Button A     | Button X    |
| B Button   | Button B     | Button Y    |
| Turbo A    | Button X     | Button A    |
| Turbo B    | Button Y     | Button B    |
| Start      | Menu Button  | Menu Button |
| Select     | Options Btn  | Options Btn |

**Keyboard Defaults:**
| Function   | Key |
|------------|-----|
| D-Pad      | Arrow Keys |
| A          | A   |
| B          | B   |
| Turbo A    | X   |
| Turbo B    | Y   |
| Start      | Return |
| Select     | Tab |

---

### Super Nintendo (SNES)

**Available Buttons:** D-Pad, A, B, X, Y, L, R, Start, Select

| Function   | Right-Handed | Left-Handed |
|------------|--------------|-------------|
| D-Pad      | D-Pad        | D-Pad       |
| A Button   | Button A     | Button X    |
| B Button   | Button B     | Button Y    |
| X Button   | Button X     | Button A    |
| Y Button   | Button Y     | Button B    |
| L Shoulder | Left Shoulder| Left Shoulder|
| R Shoulder | Right Shoulder| Right Shoulder|
| Start      | Menu Button  | Menu Button |
| Select     | Options Btn  | Options Btn |

**Keyboard Defaults:**
| Function | Key |
|----------|-----|
| D-Pad    | Arrow Keys |
| A, B, X, Y | A, B, X, Y |
| L        | Q   |
| R        | W   |
| Start    | Return |
| Select   | Tab |

---

### Nintendo 64 (N64)

**Available Buttons:** D-Pad, A, B, Z, L, R, Start, Left Stick, C-Up, C-Down, C-Left, C-Right

| Function   | Right-Handed | Left-Handed |
|------------|--------------|-------------|
| D-Pad      | D-Pad        | D-Pad       |
| A Button   | Button A     | Button A    |
| B Button   | Button B     | Button B    |
| Z          | Button Y     | Button Y    |
| L          | Left Shoulder| Left Shoulder|
| R          | Left Trigger | Left Trigger|
| Start      | Menu Button  | Menu Button |
| C-Buttons  | Right Stick  | D-Pad       |
| Analog     | Left Stick   | Left Stick  |

**Keyboard Defaults:**
| Function | Key |
|----------|-----|
| D-Pad    | Arrow Keys |
| A        | A   |
| B        | B   |
| Z        | W   |
| L        | Q   |
| R        | E   |
| Start    | Return |
| C-Buttons| I, J, K, L |

---

### Sega Genesis / Mega Drive

**Available Buttons:** D-Pad, A, B, C, X, Y, Z, Start, Select (Mode)

| Function   | Mapping |
|------------|---------|
| D-Pad      | D-Pad   |
| A Button   | Button A |
| B Button   | Button B |
| C Button   | Button X |
| X Button   | Left Shoulder |
| Y Button   | Right Shoulder |
| Z Button   | Button Y |
| Start      | Menu Button |
| Select/Mode| Options Button |

**Keyboard Defaults:**
| Function | Key |
|----------|-----|
| D-Pad    | Arrow Keys |
| A, B     | A, B |
| C        | X   |
| X, Y, Z  | Q, E, W |
| Start    | Return |
| Mode     | Tab |

---

### PlayStation (PS1/PS2)

**Available Buttons:** D-Pad, Cross(X), Circle(O), Square(□), Triangle(△), L1, R1, L2, R2, L3, R3, Start, Select, Left Stick, Right Stick

**Layout Note:** PlayStation uses a rotated face button layout compared to Nintendo systems.

| PlayStation | Maps To |
|-------------|---------|
| Cross (X)   | A Button |
| Circle (O)  | B Button |
| Square (□)  | X Button |
| Triangle (△) | Y Button |
| L1          | Left Shoulder |
| R1          | Right Shoulder |
| L2          | Left Trigger |
| R2          | Right Trigger |
| L3          | Left Stick Click |
| R3          | Right Stick Click |

---

### ScummVM (Adventure Games)

ScummVM requires special handling for point-and-click adventure games.

**Available Buttons:** D-Pad, Left Click, Right Click, Space, Escape, L1-L2, R1-R2, Select, Start, Mouse X, Mouse Y

| Function       | Controller | Keyboard |
|----------------|------------|----------|
| Movement       | D-Pad/Left Stick | Arrow Keys / WASD |
| Left Click     | A Button   | Space |
| Right Click    | B Button   | Escape |
| Inventory      | L1/L2      | Q/E |
| Actions        | R1/R2      | W/1-3 |
| Menu           | Start      | Return |
| Hotspots       | Select     | Tab |

**Mouse Navigation:** The left stick or D-Pad controls the game cursor movement. Right stick can also be used for finer cursor control.

---

### DOS (DOSBox-Pure)

DOS games require full keyboard access. All keys are mapped for DOSBox-Pure's keyboard input.

**Available Buttons:** Full keyboard + D-Pad + Mouse

| Function   | Controller | Keyboard |
|------------|------------|----------|
| Movement   | D-Pad/Left Stick | Arrow Keys |
| WASD       | Face buttons | W, A, S, D |
| Action     | A/B buttons | Any key |
| Mouse      | Right Stick / L1+Right Stick | Actual mouse |
| Enter      | Start      | Return |
| Escape     | Select     | Escape |
| Space      | L3/R3      | Space |
| Full keyboard | N/A    | All keys |

**Keyboard passthrough:** All keyboard keys are passed through directly to DOSBox-Pure when using keyboard input mode.

---

## Complete System Matrix

| System        | Buttons Available | Special Features |
|---------------|-------------------|------------------|
| NES           | 8 buttons + Turbo | Turbo A, B |
| SNES          | 12 buttons        | L, R shoulders |
| N64           | 16 buttons        | Analog stick, C-buttons |
| GB/GBC        | 6 buttons         | Standard gamepad |
| GBA           | 8 buttons         | L, R shoulders |
| NDS           | 12 buttons + Touch| Dual screen |
| Genesis       | 10 buttons        | 6-button mode |
| Master System | 5 buttons         | Simple pad |
| Game Gear     | 5 buttons         | Portable-style |
| Sega Saturn   | 14 buttons        | L, R, A-Z |
| 32X           | 10 buttons        | 6-button mode |
| Dreamcast     | 14+ buttons       | Analog triggers |
| PS1/PSX       | 18+ buttons       | Dual analog |
| PS2           | 18+ buttons       | Dual analog |
| PSP           | 14 buttons        | Analog stick |
| Switch        | 18+ buttons       | HD rumble |
| Wii           | 12 buttons        | Pointer |
| MAME/Arcade   | 14 buttons        | Coin, Start 1-2 |
| Atari 2600    | 4 buttons         | Joystick + action |
| Atari 5200    | 8 buttons         | Keypad style |
| Atari 7800    | 5 buttons         | Joystick style |
| Atari Lynx    | 5 buttons         | Portable |
| PC Engine     | 5 buttons         | 2+2 run |
| Neo Geo Pocket| 5 buttons         | Portable |
| 3DO           | 11 buttons        | Multi-button |
| ScummVM       | 12+ mouse         | Point & click |
| DOS           | Full keyboard     | Keyboard passthrough |

---

## Hand Mapping

### Controller Name Reference

| Button Name        | Physical Location |
|--------------------|-------------------|
| Button A           | Right face (standard Xbox) / Right face (PS) |
| Button B           | Bottom face (standard Xbox) / Bottom face (PS) |
| Button X           | Left face (standard Xbox) / Top face (PS) |
| Button Y           | Top face (standard Xbox) / Left face (PS) |
| D-pad Up/Down/L/R  | D-pad directional |
| Left/Right Shoulder| Top bumpers |
| Left/Right Trigger | Analog triggers |
| Button Menu/Start  | Center right |
| Button Options/Select| Center left |
| Left Stick X/Y     | Left analog axis |
| Right Stick X/Y    | Right analog axis |

---

## RetroAchievements Note

When **Hardcore Mode** is enabled for RetroAchievements:
- Turbo buttons are **automatically disabled**
- Save states are disabled
- Rewind is disabled
- Only in-game saves are allowed

This ensures compatibility with RetroAchievements' anti-cheat requirements. When Hardcore Mode is off, turbo functionality works normally.

---

## Troubleshooting

### Controller Not Detected
1. Ensure controller is connected before launching TruchieEmu
2. Go to Settings → Controller and click "Refresh Controllers"
3. Check macOS System Settings → Privacy → Input Monitoring for TruchieEmu

### Wrong Button Mappings
1. Go to Settings → Controller → [Your Controller] → [System]
2. Each button can be remapped individually
3. Hold the button on your controller when prompted to map
4. Reset to defaults by clicking "Reset to Default"

### Turbo Not Working
1. Ensure you're playing a system that supports turbo (NES, SNES, Genesis)
2. Check that turbo mapping is not the same as the base button
3. Turbo fires at approximately 10 presses/second

### N64 C-Buttons Not Working
1. C-buttons can be mapped to either the right stick (recommended) or the D-pad
2. For left-handed layouts, C-buttons are mapped to the D-pad
3. For right-handed layouts, they use the right analog stick
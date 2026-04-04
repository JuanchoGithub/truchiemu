# TruchieEmu

A macOS emulator built with SwiftUI that supports multiple retro gaming systems using libretro cores.

## Features

- **Multi-System Support**: NES, SNES, N64, GBA, Genesis, DOS, ScummVM, and more
- **Modern UI**: Clean SwiftUI interface with box art, game details, and library management
- **Save States**: Slot-based save/load with auto-save on exit
- **Shader System**: CRT, LCD, and custom Metal shaders
- **Controller Support**: Full gamepad mapping with per-system configurations
- **RetroAchievements**: Optional achievement tracking
- **CLI Launching**: Launch games from terminal or scripts

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/JuanchoGithub/truchiemu.git
   cd truchiemu
   ```

2. Generate the Xcode project (requires xcodegen):
   ```bash
   xcodegen generate
   ```

3. Open and build in Xcode:
   ```bash
   open TruchieEmu.xcodeproj
   ```

4. Download cores via the app's Core Download sheet

## CLI Usage

TruchieEmu can be launched and controlled via command-line arguments. This enables launching games from terminal, automated testing, and integration with external launchers.

### Launch a Game

```bash
# Launch with auto-detected core
open -a TruchieEmu --args --launch "/path/to/game.nes"

# Launch with specific core
open -a TruchieEmu --args --launch "/path/to/game.nes" --core fceumm

# Launch and load from save slot 3
open -a TruchieEmu --args --launch "/path/to/game.nes" --slot 3

# Launch with shader preset
open -a TruchieEmu --args --launch "/path/to/game.nes" --shader builtin-crt-classic

# Launch with custom shader uniforms
open -a TruchieEmu --args --launch "/path/to/game.nes" --shader builtin-crt-classic --shader-uniform "barrelAmount=0.25" --shader-uniform "scanlineIntensity=0.5"

# Launch with RetroAchievements (hardcore mode)
open -a TruchieEmu --args --launch "/path/to/game.nes" --achievements --hardcore

# Launch with cheats enabled
open -a TruchieEmu --args --launch "/path/to/game.nes" --cheats

# Launch with custom bezel
open -a TruchieEmu --args --launch "/path/to/game.nes" --bezel "crt-curved.png"

# Disable bezel
open -a TruchieEmu --args --launch "/path/to/game.nes" --bezel none

# Launch with core options
open -a TruchieEmu --args --launch "/path/to/game.nes" --core-option "mupen64plus-cpucore=dynamic"

# Launch with auto-load/save
open -a TruchieEmu --args --launch "/path/to/game.nes" --auto-load --auto-save


### Info Commands

```bash
# List all available cores
open -a TruchieEmu --args --list-cores

# List supported systems
open -a TruchieEmu --args --list-systems

# Show help
open -a TruchieEmu --args --help

# Show version
open -a TruchieEmu --args --version
```

### Headless Mode (for Testing)

```bash
# Launch without UI, auto-exit after rendering frames
open -a TruchieEmu --args --launch "/path/to/game.nes" --headless --timeout 10

# Returns exit code 0 if frames rendered, 1 if timeout
```

### CLI Arguments Reference

| Argument | Description | Example |
|----------|-------------|---------|
| `--launch <path>` | Path to ROM file | `--launch ~/Roms/Mario.nes` |
| `--core <id>` | Core to use | `--core fceumm` |
| `--slot <0-9>` | Save slot to load | `--slot 3` |
| `--shader <preset>` | Shader preset | `--shader builtin-crt-classic` |
| `--shader-uniform <k=v>` | Shader uniform override | `--shader-uniform "barrelAmount=0.25"` |
| `--achievements` | Enable RetroAchievements | `--achievements` |
| `--hardcore` | Hardcore mode (with --achievements) | `--hardcore` |
| `--cheats` | Load cheat files | `--cheats` |
| `--bezel <file>` | Bezel image or "none" | `--bezel "crt.png"` |
| `--core-option <k=v>` | Core option override | `--core-option "key=value"` |
| `--auto-load` | Auto-load last save state | `--auto-load` |
| `--auto-save` | Auto-save on exit | `--auto-save` |
| `--headless` | Run without UI | `--headless` |
| `--timeout <sec>` | Headless timeout | `--timeout 15` |
| `--list-cores` | List available cores | |
| `--list-systems` | List supported systems | |
| `--help` | Show help message | |
| `--version` | Show version | |

### Test Script

A test script is included for automated game testing:

```bash
# Make executable (first time only)
chmod +x scripts/test_game.sh

# Test a game
./scripts/test_game.sh ~/Roms/Mario.nes

# Test with specific core
./scripts/test_game.sh ~/Roms/Mario.nes fceumm

# Test with custom timeout
./scripts/test_game.sh ~/Roms/Mario.nes fceumm 15
```

### Programmatic Usage (Swift)

```swift
// Launch a game from within your Swift code
CLILauncher.shared.launchGame(
    romPath: "/path/to/game.nes",
    coreID: "fceumm",
    slot: 3
)

// Launch headless for testing
let process = CLILauncher.shared.launchGameDirect(
    romPath: "/path/to/game.nes",
    coreID: "fceumm",
    headless: true
)
```

## Supported Systems

| System | Extensions | Default Core |
|--------|------------|--------------|
| NES | nes, fds, unf, unif | nestopia_libretro |
| SNES | snes, smc, sfc, fig, bs | snes9x_libretro |
| N64 | n64, v64, z64, ndd | mupen64plus_next_libretro |
| GBA | gba | mgba_libretro |
| Genesis | md, gen, bin, smd | genesis_plus_gx_libretro |
| DOS | zip, dosz, conf, exe, bat, iso, img | dosbox_pure_libretro |
| ScummVM | zip, scummvm | scummvm_libretro |

## Project Structure

```
TruchieEmu/
├── App/                    # App entry point and main views
├── Engine/                 # Libretro bridge and emulation runners
│   ├── Runners/           # System-specific runners (NES, SNES, N64, etc.)
│   └── LibretroBridge.mm  # Objective-C++ bridge to libretro API
├── Models/                 # Data models (ROM, Core, etc.)
├── Services/               # Business logic services
│   ├── CLILauncher.swift  # CLI game launching utility
│   ├── CLIManager.swift   # CLI command routing and parsing
│   ├── CoreManager.swift  # Core download and management
│   └── ROMLibrary.swift   # ROM scanning and library management
├── Views/                  # SwiftUI views
├── Shaders/                # Metal shaders
└── Resources/              # Assets and entitlements
```

## Troubleshooting

### Game doesn't launch
- Verify ROM file exists and is accessible
- Check that the core is installed: `--list-cores`
- Ensure core is downloaded via the app's Core Download sheet

### Headless mode times out
- Increase timeout: `--timeout 30`
- Verify core is properly installed
- Check console logs for errors

### Wrong core selected
- Specify core explicitly: `--core <core_id>`
- Check available cores: `--list-cores`

## License

© 2026 TruchieEmu
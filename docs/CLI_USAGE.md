# TruchieEmu CLI Usage Guide

## Overview

TruchieEmu can be launched and controlled via command-line arguments. This enables:
- Launching games directly from terminal
- Automated testing scripts
- Integration with external launchers (Steam, LaunchBox, etc.)
- Full control over all game settings via CLI

## Basic Usage

### Launch a Game

```bash
# Launch with auto-detected core
open -a TruchieEmu --args --launch "/path/to/game.nes"

# Launch with specific core
open -a TruchieEmu --args --launch "/path/to/game.nes" --core fceumm

# Launch and load from save slot 3
open -a TruchieEmu --args --launch "/path/to/game.nes" --slot 3
```

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

## CLI Arguments Reference

### Core Launch Options

| Argument | Description | Example |
|----------|-------------|---------|
| `--launch <path>` | Path to ROM file | `--launch ~/Roms/Mario.nes` |
| `--core <id>` | Core to use | `--core fceumm` |
| `--slot <0-9>` | Save slot to load on start | `--slot 3` |
| `--headless` | Run without UI | `--headless` |
| `--timeout <sec>` | Headless timeout | `--timeout 15` |

### Shader Options

| Argument | Description | Example |
|----------|-------------|---------|
| `--shader <preset_id>` | Shader preset to use | `--shader builtin-crt-classic` |

### Achievement Options

| Argument | Description | Example |
|----------|-------------|---------|
| `--achievements` | Enable RetroAchievements | `--achievements` |
| `--hardcore` | Enable hardcore mode (with --achievements) | `--hardcore` |

### Cheat Options

| Argument | Description | Example |
|----------|-------------|---------|
| `--cheats` | Load cheat files for the game | `--cheats` |

### Core Options

| Argument | Description | Example |
|----------|-------------|---------|
| `--core-option <key=value>` | Set core option (can be used multiple times) | `--core-option "mupen64plus-cpucore=dynamic"` |

### Auto Save/Load Options

| Argument | Description | Example |
|----------|-------------|---------|
| `--auto-load` | Auto-load last save state on start | `--auto-load` |
| `--auto-save` | Auto-save on exit | `--auto-save` |

### Info Commands

| Argument | Description |
|----------|-------------|
| `--list-cores` | List available cores |
| `--list-systems` | List supported systems |
| `--help` | Show help message |
| `--version` | Show version |

## Supported Systems & Extensions

| System | ID | Extensions | Default Core |
|--------|-----|------------|--------------|
| NES | nes | nes, fds, unf, unif | nestopia_libretro |
| SNES | snes | snes, smc, sfc, fig, bs | snes9x_libretro |
| N64 | n64 | n64, v64, z64, ndd | mupen64plus_next_libretro |
| GBA | gba | gba | mgba_libretro |
| Genesis | genesis | md, gen, bin, smd | genesis_plus_gx_libretro |
| DOS | dos | zip, dosz, conf, exe, bat, iso, img | dosbox_pure_libretro |
| ScummVM | scummvm | zip, scummvm | scummvm_libretro |
| ...and more | | | |

## Using the Test Script

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

## Integration with External Launchers

### Steam

1. Add TruchieEmu as a non-Steam game
2. Set launch options to: `--launch "%rompath%" --core %core%`
3. Or use a batch/shell script per game

### LaunchBox/Retropie-style

Create a script per system:
```bash
#!/bin/bash
# launch_nes.sh
open -a TruchieEmu --args --launch "$1" --core fceumm
```

## Programmatic Usage (Swift)

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
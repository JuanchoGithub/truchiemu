# Libretro Database Naming Dictionary

> **Comprehensive mapping of all naming conventions used across libretro-database sources.**
> Generated: 2026-05-04

## Overview

The libretro-database repository has **4 distinct database formats** with **inconsistent naming conventions**:

| Directory | Format | Purpose |
|-----------|--------|---------|
| `metadat/no-intro/` | `.dat` (ClrMamePro XML) | No-Intro verified ROM sets — primary source |
| `metadat/redump/` | `.dat` | Redump verified disc images |
| `metadat/mame/` | `.dat` | MAME arcade database |
| `metadat/fbneo-split/` | `.dat` | FinalBurn Neo arcade database |
| `rdb/` | `.rdb` (RARCHDB + MessagePack) | Compiled RetroArch databases |
| `dat/` | `.dat` | Miscellaneous other sources (DOOM, Quake, ScummVM, etc.) |

## Internal System ID

The codebase uses an **internal system ID** (defined in `SystemDatabase.systems` / `SystemInfo.id`) as the canonical reference. Every other naming variant maps to this.

---

## Cheat Folder Names (libretro-database `cht/`)

> **Source:** https://github.com/libretro/libretro-database/tree/master/cht
> 
> Cheat folders use the **full No-Intro canonical name** for each system.

| Internal ID | Cheat Folder Name |
|-------------|------------------|
| `nes` | Nintendo - Nintendo Entertainment System |
| `fds` | Nintendo - Family Computer Disk System |
| `snes` | Nintendo - Super Nintendo Entertainment System |
| `satellaview` | Nintendo - Satellaview |
| `n64` | Nintendo - Nintendo 64 |
| `nds` | Nintendo - Nintendo DS |
| `gb` | Nintendo - Game Boy |
| `gba` | Nintendo - Game Boy Advance |
| `gbc` | Nintendo - Game Boy Color |
| `genesis` | Sega - Mega Drive - Genesis |
| `32x` | Sega - 32X |
| `sms` | Sega - Master System - Mark III |
| `gamegear` | Sega - Game Gear |
| `segacd` | Sega - Mega-CD - Sega CD |
| `saturn` | Sega - Saturn |
| `dreamcast` | Sega - Dreamcast |
| `psx` | Sony - PlayStation |
| `psp` | Sony - PlayStation Portable |
| `fbneo` / `fba` | FBNeo - Arcade Games |
| `mame` | *(MAME cheats are in FBNeo or other folders)* |
| `atari2600` | Atari - 2600 |
| `atari5200` | Atari - 5200 |
| `atari7800` | Atari - 7800 |
| `atari8` | Atari - 8-bit Family |
| `jaguar` | Atari - Jaguar |
| `lynx` | Atari - Lynx |
| `pce` | NEC - PC Engine - TurboGrafx 16 |
| `pcecd` | NEC - PC Engine CD - TurboGrafx-CD |
| `supergrafx` | NEC - PC Engine SuperGrafx |
| `msx` | Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R |
| `zx_spectrum` | Sinclair - ZX Spectrum +3 |
| `dos` | DOS |
| `scummvm` | *(via FBNeo)* |
| `3do` | *(Not in cht — no official cheats)* |
| `ngp` | *(Not in cht — use Game Boy folders)* |
| `vb` | *(Not in cht)* |
| `sg1000` | *(Not in cht)* |
| `colecovision` | Coleco - ColecoVision |
| `intellivision` | Mattel - Intellivision |

---

## Bezel Project Names (TheBezelProject)

> **Source:** https://github.com/thebezelproject (repositories named `bezelproject-XXX`)
>
> Bezel project names are **abbreviated** versions of the system name.

| Internal ID | Bezel Project Name | Repo Name |
|-------------|-------------------|-----------|
| `nes` | NES | bezelproject-NES |
| `snes` | SNES | bezelproject-SNES |
| `sufami` | SNES (via SNES) | bezelproject-SNES |
| `fds` | FDS | bezelprojectSA-FDS |
| `n64` | N64 | bezelproject-N64 |
| `nds` | NDS | bezelproject-NDS |
| `vb` | Virtualboy | bezelprojectSA-Virtualboy |
| `gb` | GB | bezelproject-GB |
| `gba` | GBA | bezelproject-GBA |
| `gbc` | GBC | bezelprojectSA-GBC |
| `genesis` | MegaDrive | bezelproject-MegaDrive |
| `sms` | MasterSystem | bezelproject-MasterSystem |
| `gamegear` | GameGear | bezelproject-GameGear |
| `32x` | Sega32X | bezelproject-Sega32X |
| `segacd` | SegaCD | bezelproject-SegaCD |
| `saturn` | Saturn | bezelproject-Saturn |
| `dreamcast` | Dreamcast | bezelproject-Dreamcast |
| `naomi` | Naomi | bezelproject-Naomi |
| `psx` | PSX | bezelproject-PSX |
| `ps2` | PS2 | bezelprojectSA-PS2 |
| `psp` | PSP | bezelprojectSA-PSP |
| `3do` | 3DO | bezelprojectSA-3DO |
| `atari2600` | Atari2600 | bezelproject-Atari2600 |
| `atari5200` | Atari5200 | bezelproject-Atari5200 |
| `atari7800` | Atari7800 | bezelproject-Atari7800 |
| `lynx` | AtariLynx | bezelprojectSA-AtariLynx |
| `jaguar` | AtariJaguar | bezelproject-AtariJaguar |
| `atarist` | AtariST | bezelproject-AtariST |
| `pce` | PCEngine | bezelproject-PCEngine |
| `pcecd` | PCE-CD | bezelproject-PCE-CD |
| `supergrafx` | SuperGrafx | bezelproject-SuperGrafx |
| `pcfx` | *(No bezel project found)* | — |
| `ngp` | NGP | bezelprojectSA-NGP |
| `ngc` | NGPC | bezelprojectSA-NGPC |
| `sg1000` | SG-1000 | bezelproject-SG-1000 |
| `colecovision` | ColecoVision | bezelproject-ColecoVision |
| `intellivision` | *(No bezel project found)* | — |
| `mame` | MAME | bezelproject-MAME |
| `atomiswave` | Atomiswave | bezelproject-Atomiswave |
| `fba` / `fbneo` | *(No dedicated bezel project)* | — |
| `amiga` | Amiga | bezelproject-Amiga |
| `msx` | MSX | bezelprojectSA-MSX |
| `msx2` | MSX2 | bezelprojectSA-MSX2 |
| `zx_spectrum` | ZXSpectrum | bezelprojectSA-ZXSpectrum |
| `x68000` | X68000 | bezelprojectSA-X68000 |
| `wonderswan` | WonderSwan | bezelproject-WonderSwan |
| `wswanc` | WonderSwan (shared) | bezelproject-WonderSwan |
| `scummvm` | ScummVM | bezelprojectSA-ScummVM |
| `wii` | Wii | bezelprojectSA-Wii |
| `n3ds` | N3DS | bezelproject-N3DS |

### Bezel Alternate ID Mappings

| Input ID | Maps To | Bezel Project | Note |
|----------|---------|---------------|------|
| `md` | `genesis` | MegaDrive | Mega Drive shorthand |
| `gg` | `gamegear` | GameGear | Game Gear shorthand |
| `fc` | `nes` | NES | Famicom |
| `sfc` | `snes` | SNES | Super Famicom |
| `32x` | `genesis` | Sega32X (or `genesis` fallback) | 32X has own bezels |
| `megadrive` | `genesis` | MegaDrive | Full alternate |

---

## Complete System Naming Dictionary

### Nintendo Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `nes` | Nintendo Entertainment System | `Nintendo - Nintendo Entertainment System.dat` | — | `Nintendo - Nintendo Entertainment System.rdb` | NES | Nintendo - Nintendo Entertainment System | `nestopia_libretro` |
| `snes` | Super Nintendo | `Nintendo - Super Nintendo Entertainment System.dat` | — | `Nintendo - Super Nintendo Entertainment System.rdb` | SNES | Nintendo - Super Nintendo Entertainment System | `snes9x_libretro` |
| `n64` | Nintendo 64 | `Nintendo - Nintendo 64.dat` | — | `Nintendo - Nintendo 64.rdb` | N64 | Nintendo - Nintendo 64 | `mupen64plus_next_libretro` |
| `gb` | Game Boy | `Nintendo - Game Boy.dat` | — | `Nintendo - Game Boy.rdb` | GB | Nintendo - Game Boy | `mgba_libretro` |
| `gbc` | Game Boy Color | `Nintendo - Game Boy Color.dat` | — | `Nintendo - Game Boy Color.rdb` | GBC | Nintendo - Game Boy Color | `mgba_libretro` |
| `gba` | Game Boy Advance | `Nintendo - Game Boy Advance.dat` | — | `Nintendo - Game Boy Advance.rdb` | GBA | Nintendo - Game Boy Advance | `mgba_libretro` |
| `nds` | Nintendo DS | `Nintendo - Nintendo DS.dat` | — | `Nintendo - Nintendo DS.rdb` | NDS | Nintendo - Nintendo DS | `desmume_libretro` |
| `ndsi` | Nintendo DSi | `Nintendo - Nintendo DSi.dat` | — | `Nintendo - Nintendo DSi.rdb` | — | — | `melonds_libretro` |
| `3ds` | Nintendo 3DS | `Nintendo - Nintendo 3DS.dat` | — | `Nintendo - Nintendo 3DS.rdb` | N3DS | — | — |
| `vb` | Virtual Boy | `Nintendo - Virtual Boy.dat` | — | `Nintendo - Virtual Boy.rdb` | Virtualboy | — | — |
| `fds` | Famicom Disk System | `Nintendo - Family Computer Disk System.dat` | — | `Nintendo - Family Computer Disk System.rdb` | FDS | Nintendo - Family Computer Disk System | — |
| `sufami` | Sufami Turbo | `Nintendo - Sufami Turbo.dat` | — | `Nintendo - Sufami Turbo.rdb` | SNES | — | — |
| `satellaview` | Satellaview | `Nintendo - Satellaview.dat` | — | `Nintendo - Satellaview.rdb` | — | Nintendo - Satellaview | — |
| `n64dd` | Nintendo 64DD | `Nintendo - Nintendo 64DD.dat` | — | `Nintendo - Nintendo 64DD.rdb` | — | — | — |
| `pokemon_mini` | Pokemon Mini | `Nintendo - Pokemon Mini.dat` | — | `Nintendo - Pokemon Mini.rdb` | — | — | — |
| `ereader` | e-Reader | `Nintendo - e-Reader.dat` | — | `Nintendo - e-Reader.rdb` | — | — | — |
| `wii` | Wii | `Nintendo - Wii (Digital).dat` | `Nintendo - Wii.dat` | `Nintendo - Wii.rdb` | Wii | — | — |
| `wiiu` | Wii U | — | — | — | — | — | — |
| `gcn` | GameCube | — | `Nintendo - GameCube.dat` | `Nintendo - GameCube.rdb` | GC | — | — |

### Sega Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `genesis` | Sega Genesis / Mega Drive | `Sega - Mega Drive - Genesis.dat` | — | `Sega - Mega Drive - Genesis.rdb` | MegaDrive | Sega - Mega Drive - Genesis | `genesis_plus_gx_libretro` |
| `sms` | Sega Master System | `Sega - Master System - Mark III.dat` | — | `Sega - Master System - Mark III.rdb` | MasterSystem | Sega - Master System - Mark III | `genesis_plus_gx_libretro` |
| `gamegear` | Sega Game Gear | `Sega - Game Gear.dat` | — | `Sega - Game Gear.rdb` | GameGear | Sega - Game Gear | `genesis_plus_gx_libretro` |
| `32x` | Sega 32X | `Sega - 32X.dat` | — | `Sega - 32X.rdb` | Sega32X | Sega - 32X | `picodrive_libretro` |
| `saturn` | Sega Saturn | `Sega - Saturn.dat` | `Sega - Saturn.dat` | `Sega - Saturn.rdb` | Saturn | Sega - Saturn | `mednafen_saturn_libretro` |
| `dreamcast` | Sega Dreamcast | `Sega - Dreamcast.dat` | `Sega - Dreamcast.dat` | `Sega - Dreamcast.rdb` | Dreamcast | Sega - Dreamcast | `flycast_libretro` |
| `segacd` | Sega CD | — | `Sega - Mega-CD - Sega CD.dat` | `Sega - Mega-CD - Sega CD.rdb` | SegaCD | Sega - Mega-CD - Sega CD | — |
| `sg1000` | Sega SG-1000 | `Sega - SG-1000.dat` | — | `Sega - SG-1000.rdb` | SG-1000 | — | — |
| `pico` | Sega PICO | `Sega - PICO.dat` | — | `Sega - PICO.rdb` | Pico | — | — |
| `naomi` | Sega Naomi | — | `Sega - Naomi.dat` | `Sega - Naomi.rdb` | Naomi | — | — |
| `naomi2` | Sega Naomi 2 | — | `Sega - Naomi 2.dat` | `Sega - Naomi 2.rdb` | Naomi | — | — |
| `atomiswave` | Atomiswave | — | — | `Atomiswave.rdb` | Atomiswave | — | — |
| `beenab` | Sega Beena | `Sega - Beena.dat` | — | — | — | — | — |

### Sony Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `psx` | PlayStation | — | `Sony - PlayStation.dat` | `Sony - PlayStation.rdb` | PSX | Sony - PlayStation | `mednafen_psx_libretro` |
| `ps2` | PlayStation 2 | — | `Sony - PlayStation 2.dat` | `Sony - PlayStation 2.rdb` | PS2 | — | `pcsx2_libretro` |
| `ps3` | PlayStation 3 | `Sony - PlayStation 3 (PSN).dat` | `Sony - PlayStation 3.dat` | `Sony - PlayStation 3.rdb` | — | — | — |
| `psp` | PlayStation Portable | `Sony - PlayStation Portable.dat` | `Sony - PlayStation Portable.dat` | `Sony - PlayStation Portable.rdb` | PSP | Sony - PlayStation Portable | `ppsspp_libretro` |
| `psvita` | PlayStation Vita | `Sony - PlayStation Vita (PSN).dat` | `Sony - PlayStation Vita.dat` | `Sony - PlayStation Vita.rdb` | — | — | — |

### Atari Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `atari2600` | Atari 2600 | `Atari - 2600.dat` | — | `Atari - 2600.rdb` | Atari2600 | Atari - 2600 | `stella_libretro` |
| `atari5200` | Atari 5200 | `Atari - 5200.dat` | — | `Atari - 5200.rdb` | Atari5200 | Atari - 5200 | `a5200_libretro` |
| `atari7800` | Atari 7800 | `Atari - 7800.dat` | — | `Atari - 7800.rdb` | Atari7800 | Atari - 7800 | `prosystem_libretro` |
| `lynx` | Atari Lynx | `Atari - Lynx.dat` | — | `Atari - Lynx.rdb` | AtariLynx | Atari - Lynx | `handy_libretro` |
| `jaguar` | Atari Jaguar | `Atari - Jaguar.dat` | `Atari - Jaguar CD.dat` | `Atari - Jaguar.rdb` | AtariJaguar | Atari - Jaguar | — |
| `jaguar_cd` | Atari Jaguar CD | — | `Atari - Jaguar CD.dat` | — | — | — | — |
| `atari8` | Atari 8-bit | `Atari - 8-bit Family.dat` | — | `Atari - 8-bit Family.rdb` | Atari800 | Atari - 8-bit Family | — |
| `atarist` | Atari ST | `Atari - ST.dat` | — | `Atari - ST.rdb` | AtariST | — | — |
| `atarixe` | Atari XEGS | — | — | — | AtariXEGS | — | — |

### Arcade

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `mame` | Arcade (MAME) | — | — | `MAME.rdb`, `MAME 2000.rdb`, `MAME 2003.rdb`, `MAME 2003-Plus.rdb`, `MAME 2010.rdb`, `MAME 2015.rdb`, `MAME 2016.rdb` | MAME | *(none — use FBNeo)* | `mame2003_plus_libretro` |
| `fba` / `fbneo` | Arcade (FinalBurn Neo) | — | — | `FBNeo - Arcade Games.rdb` | — | FBNeo - Arcade Games | `fbneo_libretro` |
| `neogeo` | Neo Geo | — | `SNK - Neo Geo CD.dat` | `SNK - Neo Geo.rdb` | — | — | — |
| `atomiswave` | Atomiswave | — | — | `Atomiswave.rdb` | Atomiswave | — | — |
| `naomi` | Sega Naomi | — | — | `Sega - Naomi.rdb` | Naomi | — | — |

### SNK / Neo Geo

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `ngp` | Neo Geo Pocket | `SNK - Neo Geo Pocket.dat` | — | `SNK - Neo Geo Pocket.rdb` | NGP | — | `mednafen_ngp_libretro` |
| `ngc` | Neo Geo Pocket Color | `SNK - Neo Geo Pocket Color.dat` | — | `SNK - Neo Geo Pocket Color.rdb` | NGPC | — | `mednafen_ngp_libretro` |
| `neogeo_cd` | Neo Geo CD | — | `SNK - Neo Geo CD.dat` | — | — | — | — |

### NEC Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `pce` | PC Engine / TurboGrafx-16 | `NEC - PC Engine - TurboGrafx 16.dat` | — | `NEC - PC Engine - TurboGrafx 16.rdb` | PCEngine | NEC - PC Engine - TurboGrafx 16 | `mednafen_pce_libretro` |
| `pcecd` | PC Engine CD | — | `NEC - PC Engine CD - TurboGrafx-CD.dat` | `NEC - PC Engine CD - TurboGrafx-CD.rdb` | PCE-CD | NEC - PC Engine CD - TurboGrafx-CD | `mednafen_pce_libretro` |
| `pcfx` | PC-FX | — | `NEC - PC-FX.dat` | `NEC - PC-FX.rdb` | — | — | `mednafen_pcfx_libretro` |
| `pc98` | PC-98 | — | `NEC - PC-98.dat` | `NEC - PC-98.rdb` | — | — | — |
| `pc88` | PC-8001 / PC-8801 | — | — | `NEC - PC-8001 - PC-8801.rdb` | — | — | — |
| `supergrafx` | PC Engine SuperGrafx | `NEC - PC Engine SuperGrafx.dat` | — | `NEC - PC Engine SuperGrafx.rdb` | SuperGrafx | NEC - PC Engine SuperGrafx | `mednafen_supergrafx_libretro` |

### Other Console Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `3do` | 3DO | — | `The 3DO Company - 3DO.dat` | `The 3DO Company - 3DO.rdb` | 3DO | — | `opera_libretro` |
| `wonderswan` | WonderSwan | `Bandai - WonderSwan.dat` | — | `Bandai - WonderSwan.rdb` | WonderSwan | — | `mednafen_wswan_libretro` |
| `wswanc` | WonderSwan Color | `Bandai - WonderSwan Color.dat` | — | `Bandai - WonderSwan Color.rdb` | WonderSwan | — | `mednafen_wswan_libretro` |
| `ngage` | Nokia N-Gage | — | — | — | — | — | — |
| `colecovision` | ColecoVision | `Coleco - ColecoVision.dat` | — | `Coleco - ColecoVision.rdb` | ColecoVision | Coleco - ColecoVision | — |
| `intellivision` | Intellivision | `Mattel - Intellivision.dat` | — | `Mattel - Intellivision.rdb` | — | Mattel - Intellivision | — |
| `videopac` | Videopac ( Odyssey² ) | `Philips - Videopac.dat` | — | — | Videopac | — | — |
| `channel_f` | Fairchild Channel F | `Fairchild - Channel F.dat` | — | `Fairchild - Channel F.rdb` | — | — | — |
| `vectrex` | GCE Vectrex | `GCE - Vectrex.dat` | — | `GCE - Vectrex.rdb` | GCEVectrex | — | — |
| `supervision` | Supervision | `Watara - Supervision.dat` | — | — | Supervision | — | — |

### Computer Systems

| Internal ID | Display Name | No-Intro DAT Filename | Redump DAT Filename | RDB Filename | Bezel Project | Cheat Folder | Core Default |
|-------------|-------------|----------------------|---------------------|--------------|---------------|--------------|--------------|
| `dos` | MS-DOS | — | — | `DOS.rdb` | — | DOS | `dosbox_pure_libretro` |
| `scummvm` | ScummVM | — | — | `ScummVM.rdb` | ScummVM | — | `scummvm_libretro` |
| `amiga` | Commodore Amiga | `Commodore - Amiga.dat` | — | `Commodore - Amiga.rdb` | Amiga | — | `puae_libretro` |
| `c64` | Commodore 64 | `Commodore - 64.dat` | — | `Commodore - 64.rdb` | C64 | — | `vice_x64_libretro` |
| `cd32` | Commodore CD32 | — | `Commodore - CD32.dat` | `Commodore - CD32.rdb` | CD32 | — | `puae_libretro` |
| `cdtv` | Commodore CDTV | — | `Commodore - CDTV.dat` | `Commodore - CDTV.rdb` | CDTV | — | `puae_libretro` |
| `msx` | MSX | `Microsoft - MSX.dat` | — | `Microsoft - MSX.rdb` | MSX | Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R | `fmsx_libretro` |
| `msx2` | MSX2 | `Microsoft - MSX2.dat` | — | `Microsoft - MSX2.rdb` | MSX2 | Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R | `fmsx_libretro` |
| `x68000` | Sharp X68000 | `Sharp - X68000.dat` | — | `Sharp - X68000.rdb` | X68000 | — | `px68k_libretro` |
| `zx_spectrum` | ZX Spectrum | `Sinclair - ZX Spectrum +3.dat` | — | `Sinclair - ZX Spectrum.rdb` | ZXSpectrum | Sinclair - ZX Spectrum +3 | `fuse_libretro` |
| `zx81` | ZX81 | — | — | — | ZX81 | — | — |
| `x1` | Sharp X1 | `Sharp - X1.dat` | — | `Sharp - X1.rdb` | — | — | — |

---

## CRITICAL INCONSISTENCIES FOUND

### 1. Genesis / Mega Drive Naming Chaos

| Context | Name Used |
|---------|-----------|
| **Internal ID** | `genesis` |
| **No-Intro DAT** | `Sega - Mega Drive - Genesis.dat` |
| **RDB** | `Sega - Mega Drive - Genesis.rdb` |
| **Bezel Project** | `MegaDrive` |
| **Cheat Folder** | `Sega - Mega Drive - Genesis` |
| **ROM Extensions** | `.md`, `.gen`, `.bin`, `.smd` |

### 2. Master System vs Mark III

| Context | Name Used |
|---------|-----------|
| **Internal ID** | `sms` |
| **No-Intro DAT** | `Sega - Master System - Mark III.dat` |
| **RDB** | `Sega - Master System - Mark III.rdb` |
| **Bezel Project** | `MasterSystem` |
| **Cheat Folder** | `Sega - Master System - Mark III` |

### 3. PlayStation Naming

| Context | Name Used |
|---------|-----------|
| **Internal ID** | `psx` |
| **Redump DAT** | `Sony - PlayStation.dat` |
| **RDB** | `Sony - PlayStation.rdb` |
| **Bezel Project** | `PSX` |
| **Cheat Folder** | `Sony - PlayStation` |

### 4. Game Boy + Game Boy Color Merging

The codebase **merges GB and GBC** into a single database (`gb+gbc` cache key) because:
- ROMs from both systems overlap
- No-Intro has separate DATs but they're merged for lookup
- Thumbnails must use the correct folder (`gb` vs `gbc`)

### 5. MAME Database Fragmentation

#### In `metadat/mame/` (DAT/XML format):

| Filename | Format | Purpose |
|----------|--------|---------|
| `MAME.dat` | ClrMamePro | Latest MAME — standard set |
| `MAME BIOS.dat` | ClrMamePro | Latest MAME BIOS files only |
| `MAME 2000 BIOS.dat` | ClrMamePro | MAME 2000 core BIOS files |
| `MAME 2003 XML.xml` | XML | MAME 2003 core — for MAME 2003-Plus |
| `MAME 2003-Plus XML.xml` | XML | MAME 2003-Plus core |
| `MAME 2010 XML.xml` | XML | MAME 2010 core |
| `MAME 2015 XML.zip` | ZIP | MAME 2015 core |
| `MAME 2016 XML (Arcade Only).xml` | XML | MAME 2016 core — Arcade subset |

#### In `rdb/` (RDB format):

| Filename | Core It Supports |
|----------|------------------|
| `MAME.rdb` | Current/Default MAME core |
| `MAME 2000.rdb` | mame2000_libretro |
| `MAME 2003.rdb` | mame2003_libretro |
| `MAME 2003-Plus.rdb` | mame2003_plus_libretro |
| `MAME 2010.rdb` | mame2010_libretro |
| `MAME 2015.rdb` | mame2015_libretro |
| `MAME 2016.rdb` | mame2016_libretro |

#### FBNeo DAT format:

| Location | Filename(s) |
|----------|-------------|
| `metadat/fbneo-split/` | `FBNeo - Arcade Games.dat`, `FinalBurn Neo (ClrMame Pro XML, Arcade only).dat` |
| `rdb/` | `FBNeo - Arcade Games.rdb` |
| `cht/` | `FBNeo - Arcade Games` (cheat folder) |

### 6. Neo Geo Fragmentation

| Context | Name Used |
|---------|-----------|
| **Neo Geo Arcade** | `SNK - Neo Geo.rdb` |
| **Neo Geo CD** | Redump: `SNK - Neo Geo CD.dat`, RDB: `SNK - Neo Geo CD.rdb` |
| **Neo Geo Pocket** | `SNK - Neo Geo Pocket.dat` / `.rdb` |
| **Neo Geo Pocket Color** | `SNK - Neo Geo Pocket Color.dat` / `.rdb` |
| **Internal ID for handheld** | `ngp` (combines both) |

### 7. Sega CD / Mega-CD Naming

| Context | Name Used |
|---------|-----------|
| **Redump DAT** | `Sega - Mega-CD - Sega CD.dat` |
| **RDB** | `Sega - Mega-CD - Sega CD.rdb` |
| **Internal ID** | `segacd` |
| **Bezel Project** | `SegaCD` |
| **Cheat Folder** | `Sega - Mega-CD - Sega CD` |

---

## Codebase Mapping References

### In `ROMIdentifierService.swift` (`libretroDatBasenameOverrides`)

```
"snes"       → "Nintendo - Super Nintendo Entertainment System.dat"
"genesis"    → "Sega - Mega Drive - Genesis.dat"
"pce"        → "NEC - PC Engine - TurboGrafx 16.dat"
"sms"        → "Sega - Master System - Mark III.dat"
"gamegear"   → "Sega - Game Gear.dat"
"saturn"     → "Sega - Saturn.dat"
"32x"        → "Sega - 32X.dat"
"dreamcast"  → "Sega - Dreamcast.dat"
"atari2600"  → "Atari - 2600.dat"
"atari5200"  → "Atari - 5200.dat"
"atari7800"  → "Atari - 7800.dat"
"lynx"       → "Atari - Lynx.dat"
"gb"         → "Nintendo - Game Boy.dat"
"gbc"        → "Nintendo - Game Boy Color.dat"
"gba"        → "Nintendo - Game Boy Advance.dat"
"mame"       → "MAME.dat"
```

### In `BezelSystemMapping.swift`

```
"vb"        → Bezel: "Virtualboy"
"genesis"   → Bezel: "MegaDrive"
"megadrive" → Bezel: "MegaDrive" (alias)
"md"        → Bezel: "MegaDrive" (alias, maps to "genesis")
"gg"        → Bezel: "GameGear" (alias, maps to "gamegear")
"32x"       → Bezel: "Sega32X"
"fc"        → Bezel: "NES" (alias, maps to "nes")
"sfc"       → Bezel: "SNES" (alias, maps to "snes")
"psx"       → Bezel: "PSX"
```

### In `CheatDownloadService.swift` (`mapSystemIDToFolderName`)

```
"nes"        → "Nintendo - Nintendo Entertainment System"
"fds"        → "Nintendo - Family Computer Disk System"
"snes"       → "Nintendo - Super Nintendo Entertainment System"
"satellaview"→ "Nintendo - Satellaview"
"n64"        → "Nintendo - Nintendo 64"
"nds"        → "Nintendo - Nintendo DS"
"gb"         → "Nintendo - Game Boy"
"gba"        → "Nintendo - Game Boy Advance"
"gbc"        → "Nintendo - Game Boy Color"
"genesis"    → "Sega - Mega Drive - Genesis"
"32x"        → "Sega - 32X"
"megadrive"  → "Sega - Mega Drive - Genesis"
"sms"        → "Sega - Master System - Mark III"
"gg"         → "Sega - Game Gear"
"saturn"     → "Sega - Saturn"
"segacd"     → "Sega - Mega-CD - Sega CD"
"dreamcast"  → "Sega - Dreamcast"
"psx"        → "Sony - PlayStation"
"psone"      → "Sony - PlayStation"
"psp"        → "Sony - PlayStation Portable"
"fbneo"      → "FBNeo - Arcade Games"
"arcade"     → "FBNeo - Arcade Games"
"mame"       → "MAME"
"atari2600"  → "Atari - 2600"
"atari5200"  → "Atari - 5200"
"atari7800"  → "Atari - 7800"
"atari800"   → "Atari - 8-bit Family"
"jaguar"     → "Atari - Jaguar"
"atarilynx"  → "Atari - Lynx"
"colecovision"→ "Coleco - ColecoVision"
"intellivision"→ "Mattel - Intellivision"
"msx"        → "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R"
"msx2"       → "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R"
"pce"        → "NEC - PC Engine - TurboGrafx 16"
"turbografx16"→ "NEC - PC Engine - TurboGrafx 16"
"tg16"       → "NEC - PC Engine - TurboGrafx 16"
"turbografxcd"→ "NEC - PC Engine CD - TurboGrafx-CD"
"pcecd"      → "NEC - PC Engine CD - TurboGrafx-CD"
"supergrafx" → "NEC - PC Engine SuperGrafx"
"sgfx"       → "NEC - PC Engine SuperGrafx"
"zxspectrum" → "Sinclair - ZX Spectrum +3"
"spectrum"   → "Sinclair - ZX Spectrum +3"
"dos"        → "DOS"
```

### In `CoreManager.swift` (`supportedSystems`)

```
"mgba"           → ["gba", "gb", "gbc"]
"mesen"          → ["nes", "snes", "gb", "gbc"]
"genesis_plus_gx" → ["genesis", "sms", "gamegear"]
"snes9x"         → ["snes"]
"mupen64plus"    → ["n64"]
"parallel_n64"   → ["n64"]
"picodrive"      → ["genesis", "sms", "gamegear", "32x"]
"mednafen_psx"   → ["psx"]
"dosbox_pure"    → ["dos"]
"mame*"           → ["mame"] (all MAME variants)
```

---

## DAT Download Priority (in code)

1. **Local DAT files** (cached in `~/Library/Application Support/TruchieEmu/Dats/`)
2. **No-Intro DAT** from `metadat/no-intro/` on GitHub
3. **Other DAT trees**: `metadat/redump/`, `metadat/mame/`, `metadat/fbneo-split/`, `dat/`
4. **RDB files**: local cache, then `rdb/` on GitHub

---

## Notes for Development

1. **Always use internal ID** as the canonical reference — never DAT filenames or bezel names directly
2. **The `libretroDatBasenameOverrides` dictionary MUST match No-Intro official names exactly** as they appear on GitHub
3. **GB/GBC merge logic** is unique — no other system pair is merged
4. **MAME RDB files** are the fallback source (not DAT), since MAME DATs follow ClrMamePro format differently
5. **Region tags in filenames** matter for matching: `(USA)`, `(Europe)`, `(Japan)`, etc.
6. **CRC32 endian swapping** is done automatically — both byte-order variants are indexed
7. **Cheat folder names** always match the **full No-Intro canonical name** (e.g., `Nintendo - Nintendo Entertainment System`)
8. **Bezel project names** are abbreviated — check `BezelSystemMapping.swift` for the current mapping
9. **Some systems have multiple variant folders** in the cheat database (e.g., N64 has `Nintendo - Nintendo 64 (Aleck64)`, `Nintendo - Nintendo 64 (iQue)`, etc.)
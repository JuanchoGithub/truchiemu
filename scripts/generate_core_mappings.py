#!/usr/bin/env python3
"""
Scrape ALL libretro docs with RetroPad tables and generate:
- coreLabels: per-core button labels from every doc row (digital + analog)
- systemLabels: per-system labels (from defaultCoreID's core, or first mapped core)
- coreOverrides: only where a button's retroID ≠ identity retroID

Outputs split JSON files to TruchiEmu/Resources/Data/CoreButtonSplit/

Usage:
    python3 scripts/generate_core_mappings.py
    python3 scripts/generate_core_mappings.py --cores flycast mupen64plus  # specific cores
    python3 scripts/generate_core_mappings.py --no-fetch  # use cached docs
"""

import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

LIBRETRO_DOCS_API = "https://api.github.com/repos/libretro/docs/contents/docs/library"
LIBRETRO_RAW = "https://raw.githubusercontent.com/libretro/docs/master/docs/library"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.join(SCRIPT_DIR, "..")
DB_PATH = os.path.join(REPO_DIR, "TruchiEmu/Resources/Data/SystemDatabase.json")
CORE_MAPPINGS_PATH = os.path.expanduser(
    "~/Library/Application Support/TruchiEmu/CoreInfo/CoreSystemMappings.json"
)
CACHE_DIR = os.path.join(SCRIPT_DIR, ".docs_cache")

SPLIT_DIR = os.path.join(
    REPO_DIR, "TruchiEmu/Resources/Data/CoreButtonSplit"
)
CORE_LABELS_DIR = os.path.join(SPLIT_DIR, "coreLabels")
SYSTEM_LABELS_DIR = os.path.join(SPLIT_DIR, "systemLabels")
CORE_OVERRIDES_DIR = os.path.join(SPLIT_DIR, "coreOverrides")

RETROPAD_DIGITAL = {
    "retro_b": 0, "retro_y": 1, "retro_select": 2, "retro_start": 3,
    "retro_dpad_up": 4, "retro_dpad_down": 5,
    "retro_dpad_left": 6, "retro_dpad_right": 7,
    "retro_a": 8, "retro_x": 9,
    "retro_l1": 10, "retro_r1": 11,
    "retro_l2": 12, "retro_r2": 13,
    "retro_l3": 14, "retro_r3": 15,
}

RETROPAD_ANALOG_IMAGES = {
    "retro_left_stick": "left",
    "retro_right_stick": "right",
}

IDENTITY = {
    "a": 8, "b": 0, "x": 9, "y": 1, "select": 2, "start": 3,
    "up": 4, "down": 5, "left": 6, "right": 7,
    "l1": 10, "r1": 11, "l2": 12, "r2": 13, "l3": 14, "r3": 15,
}
REV_IDENTITY = {v: k for k, v in IDENTITY.items()}

ANALOG_AXIS_TO_BUTTONS = {
    ("left", "X"): [("lStickLeft", 17), ("lStickRight", 16)],
    ("left", "Y"): [("lStickUp", 18), ("lStickDown", 19)],
    ("right", "X"): [("rStickLeft", 21), ("rStickRight", 20)],
    ("right", "Y"): [("rStickUp", 22), ("rStickDown", 23)],
}

TURBO_BUTTONS_MAP = {
    "nes": ["a", "b"],
    "nes_turbo": ["a", "b"],
    "snes": ["a", "b", "x", "y"],
    "sfc": ["a", "b", "x", "y"],
    "genesis": ["a", "b", "x", "y"],
    "megadrive": ["a", "b", "x", "y"],
    "mame": ["a", "b"],
    "scummvm": ["a"],
}

SYSTEM_CATEGORY_MAP = {
    "nes": "NES (8-bit Nintendo)",
    "snes": "SNES (16-bit Nintendo)", "sfc": "SNES (16-bit Nintendo)",
    "n64": "Nintendo 64",
    "gb": "Game Boy Family", "gbc": "Game Boy Family", "gba": "Game Boy Family",
    "nds": "Nintendo Handhelds", "3ds": "Nintendo Handhelds",
    "genesis": "Genesis / Mega Drive", "megadrive": "Genesis / Mega Drive",
    "sms": "Sega 8-bit", "gamegear": "Sega 8-bit",
    "saturn": "Sega Saturn",
    "dreamcast": "Sega Dreamcast",
    "psx": "PlayStation Family", "ps1": "PlayStation Family",
    "ps2": "PlayStation Family", "psp": "PlayStation Family",
    "switch": "Modern Nintendo", "wii": "Modern Nintendo", "wiiu": "Modern Nintendo",
    "gc": "Modern Nintendo", "gamecube": "Modern Nintendo",
    "mame": "Arcade", "fba": "Arcade", "arcade": "Arcade",
    "atari2600": "Atari Family", "atari5200": "Atari Family",
    "atari7800": "Atari Family", "lynx": "Atari Family",
    "pce": "NEC Family", "tg16": "NEC Family", "pcfx": "NEC Family",
    "ngp": "SNK Neo Geo Pocket", "ngc": "SNK Neo Geo Pocket",
    "3do": "3DO",
    "scummvm": "ScummVM (Adventure Games)",
    "dos": "DOS (MS-DOS Games)",
}


def fetch(url, cache_name=None, use_cache=True):
    if cache_name and use_cache:
        cache_path = os.path.join(CACHE_DIR, cache_name)
        if os.path.exists(cache_path):
            with open(cache_path) as f:
                return f.read()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "TruchiEmu/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read().decode("utf-8")
        if cache_name:
            os.makedirs(CACHE_DIR, exist_ok=True)
            cache_path = os.path.join(CACHE_DIR, cache_name)
            with open(cache_path, "w") as f:
                f.write(data)
        return data
    except Exception as e:
        print(f"  FETCH ERROR: {url}: {e}", file=sys.stderr)
        return None


def build_core_system_map():
    with open(DB_PATH) as f:
        db = json.load(f)

    core_map = {}
    for entry in db:
        sys_id = entry.get("id")
        default_core = entry.get("defaultCoreID", "")
        if sys_id and default_core:
            core_base = default_core.replace("_libretro", "")
            core_map[core_base] = sys_id

    extras = {
        "beetle_psx": "psx", "beetle_psx_hw": "psx",
        "pcsx_rearmed": "psx", "swanstation": "psx", "duckstation": "psx",
        "rustation": "psx", "pcsx1": "psx",
        "pcsx_rearmed_neon": "psx", "pcsx_rearmed_interpreter": "psx",
        "desmume_2015": "nds", "melonds": "nds", "melonds_ds": "nds",
        "noods": "nds",
        "citra": "3ds", "citra_canary": "3ds", "panda3ds": "3ds",
        "azahar": "3ds",
        "mupen64plus_next": "n64", "mupen64plus": "n64", "parallel_n64": "n64",
        "parallel_n64_debug": "n64", "mupen64plus_next_gles2": "n64",
        "mupen64plus_next_gles3": "n64", "mupen64plus_next_develop": "n64",
        "genesis_plus_gx": "genesis", "genesis_plus_gx_wide": "genesis",
        "blastem": "genesis", "clownmdemu": "genesis",
        "picodrive": "genesis",
        "kronos": "saturn", "yabause": "saturn", "beetle_saturn": "saturn",
        "yabasanshiro": "saturn", "mednafen_saturn": "saturn",
        "beetle_bsnes": "snes", "beetle_snes": "snes",
        "bsnes": "snes", "bsnes_accuracy": "snes", "bsnes_balanced": "snes",
        "bsnes_performance": "snes", "bsnes_jg": "snes",
        "bsnes_mercury_accuracy": "snes", "bsnes_mercury_balanced": "snes",
        "bsnes_mercury_performance": "snes", "bsnes_cplusplus98": "snes",
        "bsnes_hd_beta": "snes", "bsnes2014_accuracy": "snes",
        "bsnes2014_balanced": "snes", "bsnes2014_performance": "snes",
        "higan_accuracy": "snes", "higan_sfc": "snes",
        "higan_sfc_balanced": "snes", "nside_balanced": "snes",
        "mednafen_snes": "snes", "mednafen_supafaust": "snes",
        "snes9x": "snes", "snes9x_2002": "snes", "snes9x_2005": "snes",
        "snes9x_2010": "snes", "snes9x_2005_plus": "snes",
        "snes9x2010": "snes", "snes9x2002": "snes", "snes9x2005": "snes",
        "chimerasnes": "snes",
        "fceumm": "nes", "nestopia": "nes", "nestopia_ue": "nes",
        "bnes": "nes", "quicknes": "nes",
        "mesen": "nes", "mesen_s": "nes", "emux_nes": "nes",
        "fixnes": "nes", "nes_libretro": "nes",
        "gpsp": "gba", "beetle_gba": "gba", "mednafen_gba": "gba",
        "vba_next": "gba", "vba_m": "gba", "vbam": "gba",
        "tempgba": "gba", "meteor": "gba", "mgba": "gba",
        "gambatte": "gbc", "emux_gb": "gb", "gearboy": "gb", "sameboy": "gb",
        "tgb_dual": "gb", "tgbdual": "gb",
        "fixgb": "gb", "boytacean": "gb", "doublecherrygb": "gbc",
        "lrps2": "ps2", "play": "ps2", "pcsx2": "ps2",
        "stella_2014": "atari2600", "stella": "atari2600",
        "stella2023": "atari2600",
        "dolphin": "gc", "dolphin_launcher": "gc", "ishiiruka": "gc",
        "beetle_pce_fast": "pce", "beetle_sgx": "pce",
        "mednafen_pce": "pce", "mednafen_pce_fast": "pce",
        "mednafen_supergrafx": "pce", "geargrafx": "pce",
        "geolith": "ngc", "neocd": "ngc",
        "opera": "3do", "4do": "3do",
        "gearsystem": "sms", "smsplus": "sms", "emux_sms": "sms",
        "bluemsx": "msx", "fmsx": "msx",
        "atari800": "atari5200",
        "handy": "lynx", "beetle_lynx": "lynx", "gearlynx": "lynx",
        "holani": "lynx", "mednafen_lynx": "lynx",
        "fuse": "zxspectrum", "hatari": "atarist",
        "scummvm": "scummvm", "fbneo": "arcade", "mame": "arcade",
        "mame2000": "arcade", "mame2003": "arcade", "mame2003_plus": "arcade",
        "mame_2000": "arcade", "mame_2003": "arcade", "mame_2003_plus": "arcade",
        "mame2003_midway": "arcade", "mame2009": "arcade",
        "mame2010": "arcade", "mame2015": "arcade", "mame2016": "arcade",
        "mame_2010": "arcade", "mame_2015": "arcade", "mame_2016": "arcade",
        "mamearcade": "arcade", "mamemess": "arcade", "mess2015": "arcade",
        "ume2015": "arcade", "hbmame": "arcade",
        "fbalpha2012": "arcade", "fbalpha2012_cps1": "arcade",
        "fbalpha2012_cps2": "arcade", "fbalpha2012_cps3": "arcade",
        "fbalpha2012_neogeo": "arcade", "fbneo_cps12": "arcade",
        "fbneo_neogeo": "arcade",
        "redream": "dreamcast", "flycast_gles2": "dreamcast",
        "retrodream": "dreamcast",
        "dosbox": "dos", "dosbox_pure": "dos", "dosbox_svn": "dos",
        "dosbox_svn_ce": "dos", "dosbox_core": "dos",
        "vice": "c64", "vice_x64": "c64", "vice_x64sc": "c64",
        "vice_x64dtv": "c64", "vice_xscpu64": "commodore_c64_supercpu",
        "vice_x128": "commodore_c128", "vice_xvic": "commodore_vic20",
        "vice_xpet": "commodore_pet", "vice_xplus4": "commodore_plus4",
        "vice_xcbm2": "commodore_cbm2", "vice_xcbm5x0": "commodore_cbm5x0",
        "x64sdl": "c64", "frodo": "c64",
        "puae": "amiga", "puae2021": "amiga", "fsuae": "amiga",
        "uae4arm": "amiga",
        "virtualjaguar": "jaguar", "virtual_jaguar": "jaguar",
        "nxengine": "cave_story", "doukutsu_rs": "cave_story", "doukutsu-rs": "cave_story",
        "flycast": "dreamcast", "ppsspp": "psp", "remotejoy": "psp",
        "prosystem": "atari7800",
        "beetle_pc_fx": "pcfx", "mednafen_pcfx": "pcfx",
        "mednafen_ngp": "ngp", "race": "ngp",
        "mednafen_wswan": "wonderswan",
        "mednafen_vb": "virtual_boy",
        "beetle_vb": "virtual_boy",
        "mednafen_psx": "psx", "mednafen_psx_hw": "psx",
        "beetle_neopop": "ngp",
        "beetle_cygne": "wonderswan",
        "beetle_gba": "gba",
        "beetle_saturn": "saturn",
        "caprice32": "cpc", "crocods": "cpc",
        "freeintv": "intellivision", "freeintvts": "intellivision",
        "same_cdi": "cdi",
        "virtualxt": "pcxt",
        "potator": "supervision",
        "o2em": "odyssey2",
        "vecx": "vectrex",
        "81": "zx81", "eightyone": "zx81",
        "px68k": "sharp_x68000",
        "np2kai": "pc_98", "nekop2": "pc_98", "neko_project_ii_kai": "pc_98",
        "quasi88": "pc_88",
        "minivmac": "mac68k",
        "applewin": "apple_ii",
        "b2": "bbcmicro",
        "ep128emu_core": "ep128",
        "a5200": "atari5200",
        "amiarcadia": "arcadia",
        "mrboom": "bomberman", "mr_boom": "bomberman",
        "prboom": "doom", "theodore": "doom",
        "stone_soup": "dungeon_crawl",
        "mkxp-z": "mkxp",
        "tyrquake": "quake_1", "vitaquake2": "quake_2",
        "vitaquake2_xatrix": "quake_2", "vitaquake2_zaero": "quake_2",
        "vitaquake2_rogue": "quake_2",
        "vitaquake3": "quake_3", "vitavoyager": "quake_3",
        "boom3": "doom_3", "boom3_xp": "doom_3",
        "ecwolf": "wolfenstein3d",
        "openlara": "openlara",
        "craft": "craft",
        "tic80": "tic80",
        "lowresnx": "lowresnx", "lowres_nx": "lowresnx",
        "wasm4": "wasm4", "wasm_4": "wasm4", "wasm-4": "wasm4",
        "easyrpg": "rpg_maker",
        "cannonball": "cannonball",
        "squirreljme": "J2ME",
        "puzzlescript": "puzzlescript",
        "uzem": "uzebox",
        "retro8": "pico8", "fake08": "pico8",
        "sameduck": "mega_duck",
        "game_music_emu": "game_music", "gme": "game_music",
        "mpv": "movie",
        "redbook": "redbook",
        "pocketcdg": "music",
        "dirksimple": "laserdisc",
        "daphne": "daphne",
        "tamalibretro": "tamagotchi",
        "pokemini": "pokemon_mini",
        "jollycv": "jollycv",
        "gearcoleco": "colecovision",
        "onscripter": "onscripter", "onsyuri": "onsyuri",
        "sdlpal": "sdlpal",
        "mojozork": "zmachine",
        "numero": "ti_83",
        "m2000": "p2000t",
        "x1": "sharp_x1",
        "gong": "gong",
        "syobonaction": "syobonaction",
        "dinothawr": "dinothawr",
        "jumpnbump": "jumpnbump",
        "2048": "2048",
        "anarch": "anarch",
        "dice": "dice",
        "gam4980": "gam4980",
        "bennugd": "bgdi",
        "pd777": "epochcv",
        "vircon32": "vircon32",
        "vaporspec": "vaporspec",
        "cruzes": "cruzes",
        "ep128emu_core": "ep128", "ep128emu": "ep128",
        "superbroswar": "superbroswar",
        "uxn": "uxn",
        "ardens": "arduboy", "arduous": "arduboy",
        "clownmdemu": "segacd",
        "mednafen_supergrafx": "pce",
        "lowresnx": "lowresnx",
        "rvvm": "rvvm",
        "ishiiiruka": "wii",
        "ishiruka": "wii",
    }
    core_map.update(extras)

    sys_to_cores = {}
    if os.path.exists(CORE_MAPPINGS_PATH):
        try:
            with open(CORE_MAPPINGS_PATH) as f:
                mappings = json.load(f)
            c2s = mappings.get("coreToSystemMap", {})
            for core_id, sys_list in c2s.items():
                base = core_id.replace("_libretro", "")
                for sid in sys_list:
                    sys_to_cores.setdefault(sid, []).append(base)
                    if base not in core_map:
                        core_map[base] = sid
        except Exception as e:
            print(f"  Warning: Could not load CoreSystemMappings: {e}", file=sys.stderr)

    return core_map, db, sys_to_cores


def extract_h1_title(md_text):
    for line in md_text.split("\n"):
        if line.startswith("# ") and not line.startswith("## "):
            return line[2:].strip()
    return ""


def match_title_to_system(title, core_map):
    if not title:
        return None
    m = re.search(r"\(([^)]+)\)\s*$", title)
    if m:
        core_slug = m.group(1).strip().lower().replace(" ", "_").replace("-", "_")
        return core_map.get(core_slug)
    return None


def is_image_cell(cell):
    return bool(re.search(r"!\[.*?\]\(.*?retro_\w+\.png.*?\)", cell))


def extract_digital_retroid(cell):
    m = re.search(r"(retro_\w+)\.png", cell)
    if m:
        name = m.group(1)
        if name in RETROPAD_DIGITAL:
            return RETROPAD_DIGITAL[name]
    return None


def extract_analog_info(cell):
    m = re.search(r"(retro_(left|right)_stick)\.png\)?\s*([XY])", cell)
    if m:
        img_name = m.group(1)
        stick = RETROPAD_ANALOG_IMAGES.get(img_name)
        axis = m.group(3)
        if stick and axis:
            return (stick, axis)
    return None


def is_plain_label(c):
    if not c:
        return False
    if c.startswith("!["):
        return False
    if c.startswith("-"):
        return False
    if c in ("RetroPad Inputs", "RetroPad", "|"):
        return False
    if re.search(r"^User\s+\d", c):
        return False
    if re.match(r"^[A-Z][a-z]+ [A-Z][a-z]+ [A-Z][a-z]+", c):
        return False
    if c.startswith("RetroPad") or c.startswith("Device type"):
        return False
    if re.match(r"^Joypad", c, re.IGNORECASE):
        return False
    return True


def parse_joypad_table(md_text):
    """
    Parse the Joypad/Controller table from libretro docs markdown.

    Handles two table formats:
    - Format A: | RetroPad Inputs | User 1 input descriptors |  (image first)
    - Format B: | User 1 Remap descriptors | RetroPad Inputs |  (descriptor first)
    - Multi-column: | RetroPad Inputs | User 1 descriptors | MD 3-Button | MD 6-Button | ...

    Returns list of (label, retro_id) for digital,
            and list of (label, stick, axis) for analog.
    """
    lines = md_text.split("\n")

    in_joypad_section = False
    table_lines = []

    for i, line in enumerate(lines):
        stripped = line.strip()
        heading_match = re.match(r"^#+\s*(?:Joypad|Controller|Controls)", stripped, re.IGNORECASE)
        if heading_match:
            in_joypad_section = True
            table_lines = []
            continue
        if in_joypad_section:
            if stripped.startswith("|"):
                table_lines.append(stripped)
            elif table_lines and not stripped.startswith("|"):
                break

    if not table_lines:
        return [], []

    desc_col_idx = None
    for tl in table_lines[:3]:
        cells = [c.strip() for c in tl.split("|")]
        for idx, cell in enumerate(cells):
            cl = cell.lower()
            if re.search(r"user\s+\d", cl) or "input descriptor" in cl:
                desc_col_idx = idx
                break
            if "remap descriptor" in cl:
                desc_col_idx = idx
                break
            if re.search(r"player\s+\d", cl):
                desc_col_idx = idx
                break
        if desc_col_idx is not None:
            break

    digital_rows = []
    analog_rows = []

    for line in table_lines:
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 4:
            continue

        all_separator = all(re.match(r"^[-:]+$", c) for c in cells if c)
        if all_separator:
            continue

        img_idx = None
        for idx, cell in enumerate(cells):
            if is_image_cell(cell):
                img_idx = idx
                break

        if img_idx is None:
            continue

        img_cell = cells[img_idx]

        digital_id = extract_digital_retroid(img_cell)
        if digital_id is not None:
            label = None
            if desc_col_idx is not None and desc_col_idx < len(cells):
                candidate = cells[desc_col_idx]
                if is_plain_label(candidate):
                    label = candidate

            if not label:
                if img_idx + 1 < len(cells) and is_plain_label(cells[img_idx + 1]):
                    label = cells[img_idx + 1]
                elif img_idx > 0 and is_plain_label(cells[img_idx - 1]):
                    label = cells[img_idx - 1]

            if label:
                digital_rows.append((label.strip(), digital_id))
            continue

        analog_info = extract_analog_info(img_cell)
        if analog_info:
            stick, axis = analog_info
            label = None
            if desc_col_idx is not None and desc_col_idx < len(cells):
                candidate = cells[desc_col_idx]
                if is_plain_label(candidate):
                    label = candidate

            if not label:
                if img_idx + 1 < len(cells) and is_plain_label(cells[img_idx + 1]):
                    label = cells[img_idx + 1]
                elif img_idx > 0 and is_plain_label(cells[img_idx - 1]):
                    label = cells[img_idx - 1]

            if label:
                analog_rows.append((label.strip(), stick, axis))

    return digital_rows, analog_rows


def find_md_files(use_cache=True):
    cache_name = "doc_listing.json"
    text = fetch(LIBRETRO_DOCS_API, cache_name=cache_name, use_cache=use_cache)
    if not text:
        print("ERROR: Could not fetch doc listing", file=sys.stderr)
        sys.exit(1)
    try:
        files = json.loads(text)
        return sorted([f["name"] for f in files if f["name"].endswith(".md")])
    except json.JSONDecodeError:
        print("ERROR: Could not parse directory listing", file=sys.stderr)
        sys.exit(1)


def clean_label(s):
    return re.sub(r"\s*\(.*?\)\s*", "", s).strip().lower()


def strip_markdown_links(s):
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s).strip()


LABEL_TO_BTN = {
    "a": "a", "b": "b", "x": "x", "y": "y", "c": "c", "z": "z",
    "start": "start", "select": "select", "back": "select", "mode": "select",
    "d-pad up": "up", "d-pad down": "down",
    "d-pad left": "left", "d-pad right": "right",
    "up": "up", "down": "down", "left": "left", "right": "right",
    "l": "l1", "r": "r1", "l1": "l1", "r1": "r1",
    "l2": "l2", "r2": "r2", "l3": "l3", "r3": "r3",
    "l (fierce)": "l1", "r (fierce)": "r1",
    "l (weak)": "l2", "r (weak)": "r2",
    "cross": "a", "circle": "b", "square": "x", "triangle": "y",
    "button 1": "a", "button 2": "b",
    "button a": "a", "button b": "b",
    "button x": "x", "button y": "y",
    "fire": "b", "fire1": "b", "fire2": "a",
    "pause": "pause", "reset": "reset",
    "coin": "coin1", "coin 1": "coin1",
    "coin2": "coin2", "coin 2": "coin2",
    "start1": "start1", "start 1": "start1",
    "start2": "start2", "start 2": "start2",
    "l-analog": "l3", "r-analog": "r3",
    "z-trigger": "l2",
    "c buttons mode": "r2",
    "nunchuk stick x": "lStickLeft",
    "nunchuk stick y": "lStickUp",
    "c-stick x": "rStickLeft",
    "c-stick y": "rStickUp",
}

NONSTANDARD_BTNS = {
    "c", "z", "coin1", "coin2", "start1", "start2",
    "pause", "reset", "space",
    "mouseLeft", "mouseRight", "mouseMiddle",
    "mouseX", "mouseY", "mouseScrollUp", "mouseScrollDown",
    "cUp", "cDown", "cLeft", "cRight",
}


def determine_btn_from_label(label, retro_id):
    clabel = clean_label(label)

    btn = LABEL_TO_BTN.get(clabel)
    if btn:
        return btn

    base = re.sub(r"\s*\(.*?\)\s*", "", label).strip().lower()
    btn = LABEL_TO_BTN.get(base)
    if btn:
        return btn

    if retro_id in REV_IDENTITY:
        return REV_IDENTITY[retro_id]

    return None



STICK_KEYWORDS_L = {"left analog", "left stick", "l-analog", "circle pad", "control stick", "paddle x", "paddle 1"}
STICK_KEYWORDS_R = {"right analog", "right stick", "r-analog", "c-stick", "c button", "right d-pad", "right analog function", "paddle y", "paddle 2"}
STICK_PREFIX = {"lStick": "Left Stick", "rStick": "Right Stick"}
DIR_ARROW = {"Left": "\u2190", "Right": "\u2192", "Up": "\u2191", "Down": "\u2193"}

def _dir_suffix(direction):
    return f" {DIR_ARROW[direction]}"

def make_analog_label(label, btn_name):
    stick_key = "lStick" if btn_name.startswith("lStick") else "rStick" if btn_name.startswith("rStick") else None
    direction = None
    for d in ("Left", "Right", "Up", "Down"):
        if btn_name.endswith(d):
            direction = d
            break

    cl = label.lower()

    stick_already = any(kw in cl for kw in (STICK_KEYWORDS_L | STICK_KEYWORDS_R))

    slash_match = re.match(r"^(.+?)\s*/\s*(.+)$", label)
    if slash_match:
        first, second = slash_match.group(1).strip(), slash_match.group(2).strip()
        base = first if direction in ("Left", "Up") else second
        if stick_already:
            return base + _dir_suffix(direction)
        return f"{STICK_PREFIX[stick_key]} {base}{_dir_suffix(direction)}"

    and_match = re.match(r"^(.+?)\s+and\s+(.+)$", label)
    if and_match:
        first, second = and_match.group(1).strip(), and_match.group(2).strip()
        base = first if direction in ("Left", "Up") else second
        if stick_already:
            return base + _dir_suffix(direction)
        return f"{STICK_PREFIX[stick_key]} {base}{_dir_suffix(direction)}"

    axis_match = re.match(r"^(.+?\s*[XY])\s*(?:\(Right\))?\s*$", label, re.IGNORECASE)
    if axis_match:
        axis_name = axis_match.group(1).strip()
        if "(Right)" in label:
            return f"Right Stick {axis_name}{_dir_suffix(direction)}"
        if stick_already:
            return f"{axis_name}{_dir_suffix(direction)}"
        return f"{STICK_PREFIX[stick_key]} {axis_name}{_dir_suffix(direction)}"

    if stick_already:
        return label + _dir_suffix(direction)
    prefix = STICK_PREFIX.get(stick_key, "")
    return f"{prefix} {label}{_dir_suffix(direction)}"


def determine_analog_btns(label, stick, axis):
    key = (stick, axis)
    result = ANALOG_AXIS_TO_BUTTONS.get(key)
    if result:
        return result

    clabel = clean_label(label)
    if "left" in clabel or "l" in clabel or "control" in clabel or "nunchuk" in clabel:
        if axis == "X":
            return ANALOG_AXIS_TO_BUTTONS[("left", "X")]
        elif axis == "Y":
            return ANALOG_AXIS_TO_BUTTONS[("left", "Y")]
    elif "right" in clabel or "r" in clabel or "c-stick" in clabel or "c button" in clabel:
        if axis == "X":
            return ANALOG_AXIS_TO_BUTTONS[("right", "X")]
        elif axis == "Y":
            return ANALOG_AXIS_TO_BUTTONS[("right", "Y")]

    if stick == "left":
        if axis == "X":
            return ANALOG_AXIS_TO_BUTTONS[("left", "X")]
        elif axis == "Y":
            return ANALOG_AXIS_TO_BUTTONS[("left", "Y")]
    elif stick == "right":
        if axis == "X":
            return ANALOG_AXIS_TO_BUTTONS[("right", "X")]
        elif axis == "Y":
            return ANALOG_AXIS_TO_BUTTONS[("right", "Y")]

    return None


RUNTIME_ID_TO_BTN = {}
for _btn, _rid in IDENTITY.items():
    RUNTIME_ID_TO_BTN[_rid] = _btn
RUNTIME_ID_TO_BTN.update({
    16: "lStickRight", 17: "lStickLeft",
    18: "lStickUp", 19: "lStickDown",
    20: "rStickRight", 21: "rStickLeft",
    22: "rStickUp", 23: "rStickDown",
})

ARCADE_LABEL_OVERRIDES = {
    "select": "Insert Coin",
    "a": "Button 1", "b": "Button 2",
    "x": "Button 3", "y": "Button 4",
    "l1": "Button 5", "r1": "Button 6",
    "l2": "Button 7", "r2": "Button 8",
    "l3": "Service", "r3": "MAME UI",
}

CORE_ARCADE_OVERRIDES = {"mame", "mame2010", "mame2003_plus", "mame_2003"}

INPUT_DESCRIPTORS_DIR = os.path.join(
    os.path.dirname(__file__), "..",
    "TruchiEmu", "Resources", "InputDescriptors"
)


def convert_runtime_descriptors(core_base, label_overrides=None):
    path = os.path.join(INPUT_DESCRIPTORS_DIR, f"{core_base}_libretro.json")
    if not os.path.exists(path):
        return None, None

    with open(path) as f:
        descriptors = json.load(f)

    seen = {}
    for d in descriptors:
        rid = d.get("id")
        desc = d.get("description", "")
        if rid is not None and rid not in seen and desc:
            seen[rid] = desc

    cl = {}
    co = {}

    for rid, desc in sorted(seen.items()):
        btn = RUNTIME_ID_TO_BTN.get(rid)
        if not btn:
            continue

        if btn.startswith("lStick") or btn.startswith("rStick"):
            cl[btn] = {"label": make_analog_label(desc, btn)}
            co[btn] = {"id": rid}
        else:
            label = desc
            if label_overrides and btn in label_overrides:
                label = label_overrides[btn]
            cl[btn] = {"label": label}

            identity_id = IDENTITY.get(btn)
            if btn in NONSTANDARD_BTNS:
                if identity_id is None or rid != identity_id:
                    co[btn] = {"id": rid}
            elif identity_id is not None and rid != identity_id:
                co[btn] = {"id": rid}
                print(f" OVERRIDE: {core_base}.{btn} -> {rid} (identity={identity_id})", file=sys.stderr)

    return cl, co


def build_default_core_map(db, sys_to_cores):
    """For systems without defaultCoreID, pick the first available core."""
    updates = {}
    for entry in db:
        sys_id = entry.get("id")
        if not sys_id:
            continue
        if entry.get("defaultCoreID"):
            continue
        cores = sys_to_cores.get(sys_id, [])
        if cores:
            core_id = cores[0] + "_libretro"
            updates[sys_id] = core_id
    return updates


def write_split_files(core_labels, core_overrides, system_labels):
    for d in [CORE_LABELS_DIR, SYSTEM_LABELS_DIR, CORE_OVERRIDES_DIR]:
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            if f.endswith(".json"):
                os.remove(os.path.join(d, f))

    for core_base, data in sorted(core_labels.items()):
        path = os.path.join(CORE_LABELS_DIR, f"input_coreLabels_{core_base}.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")

    for core_base, data in sorted(core_overrides.items()):
        path = os.path.join(CORE_OVERRIDES_DIR, f"input_coreOverrides_{core_base}.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")

    for sys_id, data in sorted(system_labels.items()):
        path = os.path.join(SYSTEM_LABELS_DIR, f"input_systemLabels_{sys_id}.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")


def main():
    args = sys.argv[1:]
    filter_cores = None
    use_cache = False
    if "--no-fetch" in args:
        use_cache = True
        args.remove("--no-fetch")
    if "--cores" in args:
        idx = args.index("--cores")
        filter_cores = [a.replace("_libretro", "") for a in args[idx + 1:]]
        args = args[:idx]

    md_files = find_md_files(use_cache=use_cache)
    core_map, db, sys_to_cores = build_core_system_map()
    print(f"Found {len(md_files)} docs, {len(core_map)} known cores, use_cache={use_cache}", file=sys.stderr)

    core_labels = {}
    core_overrides = {}
    system_labels = {}

    processed = 0
    errors = 0

    for fname in md_files:
        core_base = fname.replace(".md", "")
        if filter_cores and core_base not in filter_cores:
            continue

        system_id = core_map.get(core_base)

        md_text = fetch(
            f"{LIBRETRO_RAW}/{fname}",
            cache_name=fname,
            use_cache=use_cache,
        )
        if not md_text:
            errors += 1
            continue

        digital_rows, analog_rows = parse_joypad_table(md_text)
        if not digital_rows and not analog_rows:
            continue

        if not system_id:
            title = extract_h1_title(md_text)
            if title:
                system_id = match_title_to_system(title, core_map)

        processed += 1
        cl = {}
        co = {}

        for label, retro_id in digital_rows:
            btn = determine_btn_from_label(label, retro_id)
            if not btn:
                continue

            cl[btn] = {"label": strip_markdown_links(label)}

            identity_id = IDENTITY.get(btn)
            if btn in NONSTANDARD_BTNS:
                if identity_id is None or retro_id != identity_id:
                    co[btn] = {"id": retro_id}
            elif identity_id is not None and retro_id != identity_id:
                co[btn] = {"id": retro_id}
                print(f" OVERRIDE: {core_base}.{btn} -> {retro_id} (identity={identity_id})", file=sys.stderr)

        for label, stick, axis in analog_rows:
            analog_btns = determine_analog_btns(label, stick, axis)
            if not analog_btns:
                print(f" SKIP analog: {core_base} label='{label}' stick={stick} axis={axis}", file=sys.stderr)
                continue

            for btn_name, analog_retro_id in analog_btns:
                cl[btn_name] = {"label": make_analog_label(strip_markdown_links(label), btn_name)}
                co[btn_name] = {"id": analog_retro_id}

        if cl:
            if core_base in CORE_ARCADE_OVERRIDES:
                for btn, override_label in ARCADE_LABEL_OVERRIDES.items():
                    if btn in cl:
                        cl[btn] = {"label": override_label}
            core_labels[core_base] = cl
        if co:
            core_overrides[core_base] = co

    for core_base in CORE_ARCADE_OVERRIDES:
        if core_base in core_labels:
            continue
        overrides = ARCADE_LABEL_OVERRIDES if core_base in ("mame", "mame2010") else None
        cl, co = convert_runtime_descriptors(core_base, label_overrides=overrides)
        if cl:
            core_labels[core_base] = cl
            print(f" RUNTIME: {core_base} -> {len(cl)} labels", file=sys.stderr)
        if co:
            core_overrides[core_base] = co

    default_core_map = {}
    for entry in db:
        sys_id = entry.get("id")
        dc = entry.get("defaultCoreID", "")
        if sys_id and dc:
            default_core_map[sys_id] = dc.replace("_libretro", "")

    for entry in db:
        sys_id = entry.get("id")
        if not sys_id:
            continue
        dc = entry.get("defaultCoreID", "")
        core_base = dc.replace("_libretro", "") if dc else None

        label_key = core_base if core_base and core_base in core_labels else None
        if not label_key:
            for ck, cv in core_labels.items():
                if core_map.get(ck) == sys_id:
                    label_key = ck
                    break

        if not label_key:
            cores = sys_to_cores.get(sys_id, [])
            for c in cores:
                if c in core_labels:
                    label_key = c
                    break

        if label_key:
            system_labels[sys_id] = {"buttons": dict(core_labels[label_key])}
            sys_lower = sys_id.lower()
            if sys_lower in TURBO_BUTTONS_MAP:
                system_labels[sys_id]["turboButtons"] = TURBO_BUTTONS_MAP[sys_lower]
            if sys_lower in SYSTEM_CATEGORY_MAP:
                system_labels[sys_id]["systemCategory"] = SYSTEM_CATEGORY_MAP[sys_lower]

    write_split_files(core_labels, core_overrides, system_labels)

    print(f"\nProcessed: {processed} docs with tables, {errors} fetch errors", file=sys.stderr)
    print(f"Core labels: {len(core_labels)} cores", file=sys.stderr)
    print(f"Core overrides: {len(core_overrides)} cores", file=sys.stderr)
    print(f"System labels: {len(system_labels)} systems", file=sys.stderr)
    print(f"\nOutput written to {SPLIT_DIR}", file=sys.stderr)


if __name__ == "__main__":
    main()

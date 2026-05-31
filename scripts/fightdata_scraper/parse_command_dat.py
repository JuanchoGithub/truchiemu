#!/usr/bin/env python3
"""
Parse MAME command.dat into per-game JSON files for TruchiEmu.

Usage:
    python3 parse_command_dat.py /path/to/command.dat --output-dir /path/to/FightData [--all]

The command.dat file is from Progetto-SNAPS:
https://www.progettosnaps.net/support/
https://github.com/AntoPISA/MAME_SupportFiles/blob/main/command.dat

Output files are named: fightdata_<parent_rom>.json
e.g., fightdata_sf2.json, fightdata_kof98.json

Also generates fightdata_index.json for cross-system name-based lookup.

By default only fighting games (with characters) are output. Use --all to include all games.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path


FIGHTING_GAME_ROMS = {
    "3countb",
    "64street",
    "aodk",
    "aof", "aof2", "aof3",
    "aliencha",
    "arabianm",
    "armwar",
    "asurabld", "asurabus",
    "asterix",
    "avengrgs",
    "avsp",
    "blandia",
    "batcir",
    "breakers", "breakrev",
    "brival",
    "btlkroad",
    "captcomm",
    "capsnk", "capsnka", "capsnkb",
    "cvs2", "cvsgd",
    "cybots",
    "daraku",
    "dbz", "dbz2",
    "ddsom",
    "denjinmk",
    "dino",
    "doubledr",
    "doa", "doapp", "doa2", "doa2m",
    "drgnmst",
    "dragoona", "dragoonj",
    "dstlk",
    "fatfury1", "fatfury2", "fatfursp", "fatfury3", "fatfurwa",
    "ffight", "ffreveng",
    "fightfev",
    "fghtfn",
    "fghthist",
    "fgtlayer",
    "fotns",
    "fvipers",
    "ga2",
    "galaxyfg",
    "garou",
    "gaxeduel",
    "ggx", "ggx15", "ggxx", "ggxxrl", "ggxxsla", "ggxxac", "ggisuka",
    "gowcaizr",
    "grdians",
    "groovef",
    "hook",
    "hsf2",
    "jchan", "jchan2",
    "kabukikl",
    "kaiserkn", "dankuga",
    "karatblz",
    "karatour",
    "karnovr",
    "kbash",
    "killbld",
    "kinst", "kinst2",
    "kizuna",
    "knckhead",
    "knights",
    "kof94", "kof95", "kof96", "kof97", "kof98", "kof98um",
    "kof99", "kof2000", "kof2001", "kof2002", "kof2003",
    "kofxi", "kofnw",
    "kov", "kovplus", "kov2p",
    "lastblad", "lastbld2",
    "mace",
    "martmast",
    "matrim",
    "mk", "mk2", "mk3", "mk4", "mk2r11", "mk3p40", "mk4a",
    "msh", "mshvsf", "mvsc", "mvsc2",
    "mtlchamp",
    "ngbc",
    "ninjamas",
    "nwarr",
    "plsmaswd", "starglad",
    "powerins", "pwrinst2", "plegends",
    "primrage", "primrag2",
    "pjustic",
    "rbff1", "rbffspec", "rbff2",
    "redearth",
    "rotd",
    "rumblef",
    "rvschool",
    "sams64", "sams64_2",
    "samsho", "samsho2", "samsho3", "samsho4", "samsho5", "samsh5sp", "samsptk",
    "savagere",
    "schamp",
    "sgemf",
    "slammast", "mbombrd", "ringdest",
    "souledge", "soulclbr",
    "ssf2", "ssf2t",
    "suikoenb",
    "svc",
    "svg",
    "tattass",
    "tkdensho",
    "tekken", "tekken2", "tekken3", "tektagt",
    "timekill",
    "tophuntr",
    "ts2",
    "umk3",
    "vf", "vf2",
    "vsav", "vsav2", "vhunt2",
    "wakuwak7",
    "wargods",
    "wh1", "wh2", "wh2j", "whp",
    "wof",
    "xmvsf", "xmcota",
    "jojo", "jojoba",
    "sf", "sf2", "sf2ce", "sf2hf",
    "sfa", "sfa2", "sfz2al", "sfa3", "sfz3ugd",
    "sfiii", "sfiii2", "sfiii3",
    "sfex", "sfexp", "sfex2", "sfex2p",
    "sftm",
    "survarts", "ssoldier",
    "beastrzr", "bldyror2",
    "ragnagrd",
    "bloodstm", "bloodwar",
    "ehrgeiz",
    "holo",
    "astrass",
    "hvnsgate",
    "bigfight",
}

ROM_TO_SYSTEM = {}

NEOGEO_ROMS = {
    "3countb", "aodk", "aof", "aof2", "aof3", "breakers", "breakrev",
    "doubledr", "fatfury1", "fatfury2", "fatfursp", "fatfury3",
    "fightfev", "galaxyfg", "garou", "ggx", "kizuna",
    "kof94", "kof95", "kof96", "kof97", "kof98", "kof98um",
    "kof99", "kof2000", "kof2001", "kof2002", "kof2003",
    "kofxi", "kofnw", "kov", "kovplus", "kov2p",
    "lastblad", "lastbld2", "martmast",
    "matrim", "mtlchamp", "ngbc", "ninjamas",
    "rbff1", "rbffspec", "rbff2", "rotd", "rumblef",
    "samsho", "samsho2", "samsho3", "samsho4", "samsho5", "samsh5sp", "samsptk",
    "savagere", "sgemf", "svc", "wakuwak7",
    "wh1", "wh2", "wh2j", "whp",
}

NAMCO_ROMS = {
    "tekken", "tekken2", "tekken3", "tektagt",
    "souledge", "soulclbr",
}

SEGA_ROMS = {
    "vf", "vf2", "fvipers", "brival",
}

CAPCOM_HARDWARE_ROMS = {
    "sf", "sf2", "sf2ce", "sf2hf", "ssf2", "ssf2t", "hsf2",
    "sfa", "sfa2", "sfz2al", "sfa3", "sfz3ugd",
    "sfiii", "sfiii2", "sfiii3",
    "sfex", "sfexp", "sfex2", "sfex2p",
    "dstlk", "nwarr", "vsav", "vsav2", "vhunt2",
    "xmvsf", "msh", "mshvsf", "mvsc", "mvsc2",
    "capsnk", "cvsgd", "cvs2",
    "xmcota", "jojo", "jojoba",
    "cybots", "sgemf",
    "redearth",
    "rvschool", "pjustic",
    "sftm",
}

MIDWAY_ROMS = {
    "mk", "mk2", "mk3", "umk3", "mk4",
    "kinst", "kinst2",
    "wargods",
    "timekill", "bloodstm", "primrage",
}

IGS_ROMS = {
    "killbld", "martmast", "kov", "kovplus", "kov2p",
}

def get_system(parent_rom: str) -> str:
    if parent_rom in NEOGEO_ROMS:
        return "neogeo"
    if parent_rom in NAMCO_ROMS:
        return "namco"
    if parent_rom in SEGA_ROMS:
        return "sega"
    if parent_rom in CAPCOM_HARDWARE_ROMS:
        return "cps"
    if parent_rom in MIDWAY_ROMS:
        return "midway"
    if parent_rom in IGS_ROMS:
        return "igs"
    return "mame"


def split_game_blocks(text: str) -> list[dict]:
    """Split command.dat into individual game blocks."""
    blocks = []
    current_lines = []
    in_block = False

    for line in text.splitlines():
        if line.startswith("$info="):
            in_block = True
            current_lines = [line]
        elif line.strip() == "$end":
            if in_block:
                current_lines.append(line)
                blocks.append(current_lines)
                current_lines = []
                in_block = False
        elif in_block:
            current_lines.append(line)

    return blocks


def parse_info_line(line: str) -> list[str]:
    """Parse $info=rom1,rom2,... into list of ROM IDs."""
    line = line.strip()
    if not line.startswith("$info="):
        return []
    roms_str = line[6:]
    return [r.strip() for r in roms_str.split(",") if r.strip()]


MOVE_CATEGORIES = {
    "_(": "throw",
    "_)": "command",
    "_@": "special",
    "_*": "super",
    "_&": "hidden",
    "_#": "top",
    "_`": "note",
}

CATEGORY_SYMBOLS = set(MOVE_CATEGORIES.keys())

SECTION_RE = re.compile(r"^─+$")

DASH_HEADER_RE = re.compile(r"^\s*-\s+(.+?)\s+-\s*(.*?)\s*$")

KNOWN_SECTIONS = {
    "CONTROLS",
    "HOW TO PLAY",
    "COMMON COMMANDS",
    "COMMON",
    "CHEATS",
    "CHARACTERS",
    "VEHICLE COMMON COMMANDS",
    "WEAPON COMMON COMMANDS",
    "CHARACTERS SPECIAL ABILITY",
    "PASSWORDS",
    "HIDDEN CARS",
    "HIDDEN CARS 1",
    "HIDDEN CARS 2",
    "SECRET CHARACTERS",
    "SECRET WEAPONS",
    "COMBO INFO",
    "ITEM LIST",
    "PLANES",
    "MODES",
    "MODES OF PLAY",
    "ISMS",
    "GROOVE SYSTEM",
    "RATIO SYSTEM",
    "STRIKER SYSTEM / RATIO SYSTEM",
    "INFINITY GEM POWER",
    "BUTTONS",
    "6-BUTTONS LAYOUT",
    "PNEUMATIC BUTTONS LAYOUT",
    "JOYSTICK 1",
    "JOYSTICK 2",
    "OFFENSE MOVES",
    "DEFENSE MOVES",
    "OFFENSE-",
    "WEAPON LIST-",
    "CPS CHANGER",
    "BATTLE AXE",
    "BLACK DRAGON SWORD",
    "BOMB MOVES",
    "BOOMERANG",
    "BOWIE KNIFE",
    "CHAINSAW MOVES",
    "CLAYMORE",
    "CROSSBOW",
    "FLAMBERGE SWORD",
    "GUN MOVES",
    "GHURKA KNIFE",
    "ICE SCEPTER",
    "KNIFES MOVES",
    "MACE STAFF",
    "NAGIMAKI",
    "SPIKED CLUB",
    "STICKS MOVES",
    "STUN GUN MOVES",
    "SWORDS MOVES",
    "WARHAMMER",
    "WINDBLADE",
    "GEARS",
    "MOVES",
    "STEERING WHEEL AND PEDALS",
    "KNOCKDOWNS ---",
    "AIR COMBO FINISHERS ---",
    "AIR LAUNCHERS ---",
    "GROUND CHAIN-COMBO ---",
    "JUMP CHAIN-COMBO ---",
    "LAUNCHERS ---",
    "STRIKES ---",
    "CONDOR HEADS",
    "DEFENSE",
}

CHARACTER_SUBSECTIONS = {
    "AIR COMBO FINISHERS",
    "AIR LAUNCHERS",
    "GROUND CHAIN-COMBO",
    "JUMP CHAIN-COMBO",
    "LAUNCHERS",
    "STRIKES",
    "KNOCKDOWNS",
    "COMBO INFO",
}

MOVE_LINE_RE = re.compile(
    r"^\s*(_\(|_\)|_@|_\*|_&|_#|_`)\s+(.*)"
)

FOLLOWUP_RE = re.compile(r"^\^!")


def parse_controls_section(lines: list[str]) -> tuple[dict, dict, list[str]]:
    """Parse CONTROLS section into button labels, groups, and raw lines."""
    controls = {}
    groups = {}
    raw_lines = []

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("-") or SECTION_RE.match(stripped):
            continue
        raw_lines.append(stripped)

        m = re.match(r"^\s*(\^[A-Z])\s*:\s*(.+?)(?:\s+\((_[A-Z])\))?\s*$", stripped)
        if m:
            btn_id = m.group(1)
            label = m.group(2).strip()
            group = m.group(3)
            controls[btn_id] = label
            if group:
                groups.setdefault(group, []).append(btn_id)
            continue

        m = re.match(r"^\s*(_[A-Z])\s*:\s*(.+?)(?:\s+\((_[A-Z])\))?\s*$", stripped)
        if m:
            btn_id = m.group(1)
            label = m.group(2).strip()
            group = m.group(3)
            controls[btn_id] = label
            if group:
                groups.setdefault(group, []).append(btn_id)

    return controls, groups, raw_lines


def parse_howto_section(lines: list[str]) -> tuple[dict, list[str]]:
    """Parse HOW TO PLAY section for category definitions and notes."""
    categories = {}
    notes = []

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("-") or SECTION_RE.match(stripped):
            continue

        if stripped.startswith("CONTROLS"):
            continue

        for symbol, name in MOVE_CATEGORIES.items():
            display = symbol.replace("_(", "(").replace("_)", ")")
            if stripped.startswith(symbol) and len(stripped) > len(symbol):
                rest = stripped[len(symbol):].strip()
                if rest and not rest[0].isdigit() and not rest.startswith("^"):
                    categories[symbol] = rest
                    break
        else:
            if stripped and not stripped.startswith("$"):
                notes.append(stripped)

    return categories, notes


NOTATION_START_RE = re.compile(
    r'(?:_[0-9a-zA-Z\+\^#?!>]|'
    r'\^[A-Za-z0-9\*!]|'
    r'@\w+-button|'
    r'\(_\^\))'
)

NOTATION_TOKEN_RE = re.compile(
    r'(?:_[0-9a-zA-Z]+[#]*[c]*[j]*[P]*|'
    r'_[\+\^#?!>]|'
    r'\^[A-Za-z0-9\*!][a-z]*|'
    r'@\w+-button|'
    r'\(_\^\)|'
    r'[+/~]|'
    r'\([^)]*\))'
)

HIT_LEVEL_RE = re.compile(r'^([hmHMglGL!\-]+)\s*')


def find_notation_start(text: str) -> int | None:
    for m in NOTATION_START_RE.finditer(text):
        pos = m.start()
        if pos == 0:
            return 0
        prev = text[pos - 1]
        if prev in (" ", "/"):
            return pos
    return None


def scan_notation_end(text: str, start: int) -> int:
    pos = start
    while pos < len(text):
        m = NOTATION_TOKEN_RE.match(text, pos)
        if m:
            pos = m.end()
            continue
        if text[pos] == " ":
            rest = text[pos + 1:]
            if rest and (NOTATION_START_RE.match(rest) or rest[0] == "/"):
                pos += 1
                continue
            break
        break
    return pos


def promote_note_to_move(note: str) -> dict | None:
    stripped = note.strip()
    if not stripped:
        return None

    notation_pos = find_notation_start(stripped)
    if notation_pos is None:
        return None

    prefix = stripped[:notation_pos].strip().rstrip(":-").strip()
    if prefix.startswith("-"):
        prefix = prefix[1:].strip()

    notation_end = scan_notation_end(stripped, notation_pos)
    input_str = stripped[notation_pos:notation_end].strip()
    suffix = stripped[notation_end:].strip()

    if not input_str:
        return None

    hit_levels = None
    condition = None

    if suffix:
        hl_match = HIT_LEVEL_RE.match(suffix)
        if hl_match:
            hit_levels = hl_match.group(1)
            suffix = suffix[hl_match.end():].strip()

        parens = re.findall(r"\(([^)]+)\)", suffix)
        remaining = suffix
        for p in parens:
            remaining = remaining.replace(f"({p})", "").strip()
        if parens:
            if remaining:
                condition = f"{remaining} {' '.join(parens)}"
            else:
                condition = " ".join(parens)
        elif remaining:
            condition = remaining

    move = {
        "category": "_`",
        "name": prefix,
    }
    move["input"] = input_str
    if hit_levels:
        move["hitLevels"] = hit_levels
    if condition:
        move["condition"] = condition

    return move


def parse_move_line(line: str) -> dict | None:
    """Parse a single move line like '_@ Hadou Ken _2_3_6_+_P'."""
    stripped = line.strip()
    if not stripped:
        return None

    category = None
    for symbol in ["_(", "_)", "_@", "_*", "_&", "_#", "_`"]:
        if stripped.startswith(symbol):
            category = symbol
            stripped = stripped[len(symbol):].strip()
            break

    if category is None:
        return None

    if stripped.startswith("^!"):
        stripped = stripped[2:].strip()

    condition_match = re.match(r"^\(([^)]+)\)\s*", stripped)
    condition = None
    if condition_match:
        condition = condition_match.group(1)
        stripped = stripped[condition_match.end():]

    notation_pos = find_notation_start(stripped)
    if notation_pos is not None:
        name = stripped[:notation_pos].strip()
        notation_end = scan_notation_end(stripped, notation_pos)
        input_str = stripped[notation_pos:notation_end].strip()
    else:
        name = stripped
        input_str = ""

    name = re.sub(r"\s+", " ", name).strip()
    if not name and not input_str:
        return None

    move = {
        "category": category,
        "name": name,
    }
    if input_str:
        move["input"] = input_str
    if condition:
        move["condition"] = condition

    return move


def _flush_character(character_name, character_moves, character_notes, character_combos, characters):
    if character_name:
        promoted_moves = []
        remaining_notes = []
        for note in character_notes:
            promoted = promote_note_to_move(note)
            if promoted:
                promoted_moves.append(promoted)
            else:
                remaining_notes.append(note)

        all_moves = character_moves + promoted_moves

        entry = {"name": character_name, "moves": all_moves}
        if remaining_notes:
            entry["notes"] = remaining_notes
        if character_combos:
            entry["combos"] = character_combos
        characters.append(entry)


def parse_game_block(lines: list[str]) -> dict | None:
    """Parse a complete game block into structured data."""
    if not lines:
        return None

    rom_ids = parse_info_line(lines[0])
    if not rom_ids:
        return None

    parent_rom = rom_ids[0]

    content_lines = lines[1:]
    if content_lines and content_lines[-1].strip() == "$end":
        content_lines = content_lines[:-1]

    if not content_lines:
        return None

    first_content = content_lines[0].strip()
    if first_content == "$cmd":
        content_lines = content_lines[1:]
        if not content_lines:
            return None
        first_content = content_lines[0].strip()
    elif first_content.startswith("$cmd"):
        first_content = first_content[4:].strip()
        content_lines[0] = first_content

    title = ""
    year = None
    manufacturer = None
    credits = None

    title_match = re.match(r"^(.+?)(?:\s+©\s+(\d{4})\s+(\S+))?\s*$", first_content)
    if title_match:
        title = title_match.group(1).strip() if title_match.group(1) else first_content
        year = int(title_match.group(2)) if title_match.group(2) else None
        manufacturer = title_match.group(3) if title_match.group(3) else None

    scan_start = 1
    for idx, line in enumerate(content_lines[1:], 1):
        s = line.strip()
        if not s:
            scan_start = idx + 1
            continue
        m = re.match(r"^Created by:\s*(.+)$", s)
        if m:
            credits = m.group(1).strip()
            break
        m = re.match(r"^Rebuilt (.+)$", s)
        if m:
            credits = m.group(1).strip()
            break
        break

    controls_lines = []
    howto_lines = []
    common_lines = []
    cheat_lines = []
    characters = []

    current_section = None
    character_name = None
    character_moves = []
    character_notes = []
    character_combos = []

    SECTION_MAP = {
        "CONTROLS": "controls",
        "HOW TO PLAY": "howto",
        "COMMON COMMANDS": "common",
        "COMMON": "common",
        "CHEATS": "cheats",
        "VEHICLE COMMON COMMANDS": "common",
        "WEAPON COMMON COMMANDS": "common",
    }

    def flush_current_character():
        nonlocal character_name, character_moves, character_notes, character_combos
        _flush_character(character_name, character_moves, character_notes, character_combos, characters)
        character_name = None
        character_moves = []
        character_notes = []
        character_combos = []

    for line in content_lines[scan_start:]:
        stripped = line.strip()

        if SECTION_RE.match(stripped):
            continue
        if not stripped:
            continue

        dash_match = DASH_HEADER_RE.match(stripped)
        if dash_match:
            header_text = dash_match.group(1).strip()

            if header_text.upper() in KNOWN_SECTIONS:
                flush_current_character()
                mapped = SECTION_MAP.get(header_text.upper())
                if mapped:
                    current_section = mapped
                else:
                    current_section = "ignored"
                continue

            if header_text.upper() in CHARACTER_SUBSECTIONS:
                if current_section == "characters" and character_name:
                    extra = dash_match.group(2).strip() if dash_match.group(2) else None
                    note = header_text
                    if extra:
                        note += f" {extra}"
                    character_notes.append(note)
                continue

            if current_section == "cheats":
                continue

            if current_section == "ignored":
                if re.match(r'^[\d\s]+$', header_text) or '=' in (dash_match.group(2) or ''):
                    continue
                current_section = "characters"

            flush_current_character()
            current_section = "characters"
            character_name = header_text
            extra_info = dash_match.group(2).strip() if dash_match.group(2) else None
            character_moves = []
            character_notes = []
            character_combos = []
            if extra_info:
                character_notes.append(extra_info)
            continue

        if current_section == "controls":
            controls_lines.append(line)
        elif current_section == "howto":
            howto_lines.append(line)
        elif current_section == "common":
            common_lines.append(line)
        elif current_section == "cheats":
            cheat_lines.append(line)
        elif current_section == "characters" and character_name:
            move = parse_move_line(line)
            if move:
                character_moves.append(move)
            else:
                stripped2 = line.strip()
                if not stripped2 or SECTION_RE.match(stripped2):
                    continue
                elif stripped2.startswith(("Target Combo", "Super Bar:", "Personal Action", "Combos")):
                    character_combos.append(stripped2)
                elif MOVE_LINE_RE.match(stripped2):
                    move = parse_move_line(stripped2)
                    if move:
                        character_moves.append(move)
                    else:
                        character_notes.append(stripped2)
                else:
                    character_notes.append(stripped2)

    flush_current_character()

    controls, control_groups, _ = parse_controls_section(controls_lines)
    categories, howto_notes = parse_howto_section(howto_lines)

    common_moves = []
    common_notes = []
    for line in common_lines:
        move = parse_move_line(line)
        if move:
            common_moves.append(move)
        else:
            s = line.strip()
            if s and not SECTION_RE.match(s) and not DASH_HEADER_RE.match(s):
                promoted = promote_note_to_move(s)
                if promoted:
                    common_moves.append(promoted)
                else:
                    common_notes.append(s)

    cheat_notes = []
    for line in cheat_lines:
        s = line.strip()
        if s and not SECTION_RE.match(s) and not DASH_HEADER_RE.match(s):
            cheat_notes.append(s)

    characters = [c for c in characters if c.get("moves") or c.get("notes") or c.get("combos")]

    game = {
        "schemaVersion": 2,
        "romIds": rom_ids,
        "parentRom": parent_rom,
        "name": title,
        "year": year,
        "manufacturer": manufacturer,
        "credits": credits,
        "controls": controls,
        "controlGroups": control_groups,
        "categories": categories,
        "commonCommands": common_moves,
        "commonNotes": common_notes,
        "characters": characters,
    }

    if cheat_notes:
        game["cheatNotes"] = cheat_notes
    if howto_notes:
        game["howToPlayNotes"] = howto_notes

    game = {k: v for k, v in game.items()
            if v is not None and v != [] and v != {} and v != ""}

    return game


DEDUP_MERGE = {
    "mk2": ["mk2r11"],
    "mk3": ["mk3p40"],
    "mk4": ["mk4a"],
}

DEDUP_PREFER_DATA_FROM = {
    "mk4": "mk4a",
}

ARABIC_TO_ROMAN = {
    1: "I", 2: "II", 3: "III", 4: "IV", 5: "V",
    6: "VI", 7: "VII", 8: "VIII", 9: "IX", 10: "X",
    11: "XI", 12: "XII", 13: "XIII", 14: "XIV", 15: "XV",
    16: "XVI", 17: "XVII", 18: "XVIII", 19: "XIX",
}
ARABIC_TO_TEXT = {
    1: "one", 2: "two", 3: "three", 4: "four", 5: "five",
    6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten",
    11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen", 15: "fifteen",
    16: "sixteen", 17: "seventeen", 18: "eighteen", 19: "nineteen",
}
ROMAN_TO_ARABIC = {v: k for k, v in ARABIC_TO_ROMAN.items()}

REGIONAL_ALIASES = {
    "Street Fighter Alpha": ["Street Fighter Zero"],
    "Street Fighter Alpha 2": ["Street Fighter Zero 2"],
    "Street Fighter Alpha 3": ["Street Fighter Zero 3"],
    "Street Fighter Alpha: Warriors' Dreams": ["Street Fighter Zero: Warriors' Dreams"],
    "Darkstalkers: The Night Warriors": ["Vampire: The Night Warriors"],
    "Night Warriors: Darkstalkers' Revenge": ["Vampire Hunter: Darkstalkers' Revenge"],
    "Vampire Savior: The Lord of Vampire": ["Darkstalkers 3", "Vampire Savior"],
    "Vampire Savior 2: The Lord of Vampire": ["Darkstalkers 3", "Vampire Savior 2"],
    "Vampire Hunter 2: Darkstalkers Revenge": ["Night Warriors 2: Darkstalkers Revenge"],
}


def clean_game_name(name: str) -> str:
    name = re.sub(r'\s*©.*$', '', name).strip()
    name = re.sub(r'\s*\((?:Rev|version)[^)]*\)', '', name, flags=re.IGNORECASE).strip()
    name = re.sub(r'\s*\([^)]*\)', '', name).strip()
    name = re.sub(r'\s*\[[^\]]*\]', '', name).strip()
    name = re.sub(r'\s+', ' ', name).strip()
    return name


def normalize_name(name: str) -> str:
    cleaned = clean_game_name(name)
    return re.sub(r'\s+', '', cleaned).lower()


def generate_roman_variants(name: str) -> list[str]:
    variants = set()
    clean = clean_game_name(name)
    norm = normalize_name(name)

    for arabic, roman in ARABIC_TO_ROMAN.items():
        pattern = r'(?<![a-zA-Z])\b' + str(arabic) + r'\b(?![a-zA-Z0-9])'
        replaced = re.sub(pattern, roman, clean)
        if replaced != clean:
            variants.add(normalize_name(replaced))
        text_word = ARABIC_TO_TEXT[arabic]
        replaced = re.sub(pattern, text_word.capitalize(), clean)
        if replaced != clean:
            variants.add(normalize_name(replaced))

    for roman, arabic in ROMAN_TO_ARABIC.items():
        esc = re.escape(roman)
        if len(roman) == 1:
            pattern = r'(?<![a-zA-Z])\b' + esc + r'\b(?![-\'a-zA-Z0-9])'
        else:
            pattern = r'(?<![a-zA-Z])\b' + esc + r'\b(?![a-zA-Z0-9])'
        replaced = re.sub(pattern, str(arabic), clean, flags=re.IGNORECASE)
        if replaced != clean:
            variants.add(normalize_name(replaced))

    stripped = clean.strip()
    for pat in [r' 1$', r' (?i:I)$', r' (?i:one)$']:
        replaced = re.sub(pat, '', stripped, flags=re.IGNORECASE).strip()
        if replaced != stripped and len(replaced) >= 2:
            variants.add(normalize_name(replaced))

    return [v for v in variants if v != norm]


def generate_aliases(name: str) -> list[str]:
    clean = clean_game_name(name)
    aliases = set()

    for regional_name, regional_alts in REGIONAL_ALIASES.items():
        if clean.lower() == regional_name.lower():
            for alt in regional_alts:
                aliases.add(alt)
                aliases.add(normalize_name(alt))
        for alt in regional_alts:
            if clean.lower() == alt.lower():
                aliases.add(regional_name)
                aliases.add(normalize_name(regional_name))
                for other_alt in regional_alts:
                    if other_alt.lower() != alt.lower():
                        aliases.add(other_alt)
                        aliases.add(normalize_name(other_alt))

    for variant in generate_roman_variants(name):
        aliases.add(variant)

    norm = normalize_name(name)
    return sorted(a for a in aliases if a != norm)


def process_command_dat(dat_path: str, output_dir: str, all_games: bool = False) -> None:
    """Main entry point: parse command.dat and write JSON files."""
    print(f"Reading {dat_path}...")

    with open(dat_path, "r", encoding="utf-8-sig") as f:
        text = f.read()

    blocks = split_game_blocks(text)
    print(f"Found {len(blocks)} game blocks")

    os.makedirs(output_dir, exist_ok=True)

    all_games_data: dict[str, dict] = {}
    error_count = 0

    for block_lines in blocks:
        rom_ids = parse_info_line(block_lines[0])
        if not rom_ids:
            continue

        parent_rom = rom_ids[0]

        is_fighting = parent_rom in FIGHTING_GAME_ROMS
        if not all_games and not is_fighting:
            continue

        try:
            game = parse_game_block(block_lines)
        except Exception as e:
            print(f" ERROR parsing {parent_rom}: {e}", file=sys.stderr)
            error_count += 1
            continue

        if not game:
            continue

        all_games_data[parent_rom] = game

    for canonical, revisions in DEDUP_MERGE.items():
        if canonical not in all_games_data:
            for rev in revisions:
                if rev in all_games_data:
                    all_games_data[canonical] = all_games_data.pop(rev)
                    print(f" DEDUP: {rev} -> {canonical} (canonical not found, promoting revision)")
            continue
        canonical_game = all_games_data[canonical]
        prefer_rev = DEDUP_PREFER_DATA_FROM.get(canonical)
        for rev in revisions:
            if rev in all_games_data:
                rev_game = all_games_data[rev]
                if prefer_rev == rev:
                    canonical_game["characters"] = rev_game.get("characters", [])
                    for k in ["commonCommands", "commonNotes", "categories", "controls", "controlGroups"]:
                        if k in rev_game:
                            canonical_game[k] = rev_game[k]
                    print(f" DEDUP: merging {rev} data into {canonical} (preferred data source)")
                canonical_game["romIds"] = canonical_game.get("romIds", []) + rev_game.get("romIds", [])
                del all_games_data[rev]
                print(f" DEDUP: merged {rev} romIds into {canonical}")

    for parent_rom, game in list(all_games_data.items()):
        rom_ids = game.get("romIds", [])
        if len(rom_ids) > 1:
            seen = set()
            unique = []
            for rid in rom_ids:
                if rid not in seen:
                    seen.add(rid)
                    unique.append(rid)
            game["romIds"] = unique

    index_entries = []
    fighting_count = 0
    skipped_zero_char = 0

    for parent_rom in sorted(all_games_data.keys()):
        game = all_games_data[parent_rom]
        char_count = len(game.get("characters", []))

        if not all_games and char_count == 0:
            skipped_zero_char += 1
            continue

        game.pop("parentRom", None)

        raw_name = game.get("name", "")
        game["name"] = clean_game_name(raw_name)

        filename = f"fightdata_{parent_rom}.json"
        filepath = os.path.join(output_dir, filename)

        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(game, f, separators=(',', ':'), ensure_ascii=False)

        move_count = sum(len(c.get("moves", [])) for c in game.get("characters", []))
        print(f" {parent_rom:20s} -> {filename:35s} ({char_count} chars, {move_count} moves)")
        fighting_count += 1

        clean = clean_game_name(raw_name)
        aliases = generate_aliases(raw_name)
        index_entries.append({
            "name": clean,
            "cleanName": clean,
            "normalizedName": normalize_name(raw_name),
            "file": filename,
            "romIds": game.get("romIds", []),
            "aliases": aliases,
            "year": game.get("year"),
            "manufacturer": game.get("manufacturer"),
        })

    index = {
        "schemaVersion": 2,
        "games": index_entries,
    }
    index_path = os.path.join(output_dir, "fightdata_index.json")
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(index, f, separators=(',', ':'), ensure_ascii=False)
    print(f"\nIndex written: {index_path} ({len(index_entries)} games)")

    print(f"\nDone! {fighting_count} games written, {skipped_zero_char} zero-char skipped, {error_count} errors")
    print(f"Output: {output_dir}")


def main():
    parser = argparse.ArgumentParser(description="Parse MAME command.dat into JSON for TruchiEmu")
    parser.add_argument("command_dat", help="Path to command.dat file")
    parser.add_argument("--output-dir", "-o",
                        default=os.path.join(os.path.dirname(__file__), "..", "..", "TruchiEmu", "Resources", "FightData"),
                        help="Output directory for JSON files")
    parser.add_argument("--all", action="store_true",
                        help="Include all games, not just fighting games")

    args = parser.parse_args()

    if not os.path.exists(args.command_dat):
        print(f"Error: {args.command_dat} not found", file=sys.stderr)
        sys.exit(1)

    output_dir = os.path.abspath(args.output_dir)
    process_command_dat(args.command_dat, output_dir, args.all)


if __name__ == "__main__":
    main()

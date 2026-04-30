#!/usr/bin/env python3
"""
Build mame_2003_plus.json from libretro-database sources.

Downloads and merges:
  1. MAME 2003-Plus XML.xml — full game metadata with runnable status, dependencies, video/input/chip info
  2. MAME.dat — master game list with descriptions, types, year, manufacturer
  3. MAME BIOS.dat — list of BIOS entries

Outputs a unified JSON with per-game metadata including:
  - description, year, manufacturer
  - runnable status, isBIOS flag
  - cloneOf, romOf, sampleOf, mergedROMs (dependencies)
  - players, control, coins
  - orientation, screenType, width, height, aspectX, aspectY, refreshRate
  - cpu, cpuClock, audio chips
  - driverStatus, driverColor, driverSound
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
from urllib.request import urlopen, urlretrieve, Request
from urllib.error import URLError
import re

# URLs
XML_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202003-Plus%20XML.xml"
DAT_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME.dat"
BIOS_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%20BIOS.dat"


def download_file(url, desc="file"):
    """Download a file from URL with user-agent header."""
    print(f"  Downloading {desc}...")
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req) as response:
            data = response.read()
        print(f"  Downloaded {len(data):,} bytes")
        return data
    except URLError as e:
        print(f"  ERROR: Failed to download {desc}: {e}")
        return None


def parse_xml(data):
    """Parse MAME 2003-Plus XML and return games dict."""
    print("  Parsing XML...")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        print(f"  ERROR: XML parse failed: {e}")
        return {}

    games = {}
    total = 0

    for game_elem in root.findall("game"):
        total += 1
        short_name = game_elem.get("name")
        if not short_name:
            continue

        runnable = game_elem.get("runnable", "yes") != "no"
        clone_of = game_elem.get("cloneof")
        rom_of = game_elem.get("romof")
        sample_of = game_elem.get("sampleof")

        # Extract child elements
        description = get_text(game_elem, "description")
        year = get_text(game_elem, "year")
        manufacturer = get_text(game_elem, "manufacturer")

        # Video info
        video_elem = game_elem.find("video")
        orientation = video_elem.get("orientation") if video_elem is not None else None
        screen_type = video_elem.get("screen") if video_elem is not None else None
        width = safe_int(get_attr(video_elem, "width"))
        height = safe_int(get_attr(video_elem, "height"))
        aspect_x = safe_int(get_attr(video_elem, "aspectx"))
        aspect_y = safe_int(get_attr(video_elem, "aspecty"))
        refresh_rate = safe_float(get_attr(video_elem, "refresh"))

        # Input info
        input_elem = game_elem.find("input")
        players = safe_int(get_attr(input_elem, "players"))
        control = get_attr(input_elem, "control")
        coins = safe_int(get_attr(input_elem, "coins"))

        # Chip info
        cpus = []
        audio_chips = []
        for chip_elem in game_elem.findall("chip"):
            chip_type = chip_elem.get("type")
            chip_name = chip_elem.get("name")
            chip_clock = safe_float(get_attr(chip_elem, "clock"))
            if chip_type == "cpu" and chip_name:
                cpus.append({"name": chip_name, "clock": chip_clock})
            elif chip_type == "audio" and chip_name:
                audio_chips.append({"name": chip_name, "clock": chip_clock})

        # Driver info
        driver_elem = game_elem.find("driver")
        driver_status = get_attr(driver_elem, "status")
        driver_color = get_attr(driver_elem, "color")
        driver_sound = get_attr(driver_elem, "sound")

        # Sound channels
        sound_elem = game_elem.find("sound")
        sound_channels = safe_int(get_attr(sound_elem, "channels"))

        # ROM entries with merge info
        merged_roms = []
        for rom_elem in game_elem.findall("rom"):
            merge = rom_elem.get("merge")
            if merge:
                merged_roms.append(merge)

        # Sound info (from chip list)
        cpu_name = cpus[0]["name"] if cpus else None
        cpu_clock = cpus[0]["clock"] if cpus else None
        audio_names = [a["name"] for a in audio_chips]

        games[short_name] = {
            "description": description or short_name,
            "year": year,
            "manufacturer": manufacturer,
            "runnable": runnable,
            "isBIOS": False,  # Will be updated from BIOS.dat
            "cloneOf": clone_of,
            "romOf": rom_of if rom_of else (clone_of if clone_of else None),
            "sampleOf": sample_of,
            "mergedROMs": list(set(merged_roms)) if merged_roms else [],
            "players": players,
            "control": control,
            "coins": coins,
            "orientation": orientation,
            "screenType": screen_type,
            "width": width,
            "height": height,
            "aspectX": aspect_x,
            "aspectY": aspect_y,
            "refreshRate": refresh_rate,
            "cpu": cpu_name,
            "cpuClock": cpu_clock,
            "audio": audio_names if audio_names else None,
            "soundChannels": sound_channels,
            "driverStatus": driver_status,
            "driverColor": driver_color,
            "driverSound": driver_sound
        }

    print(f"  Parsed {len(games):,} games from XML ({total} total elements)")
    return games


def parse_dat(data):
    """Parse MAME.dat format and return dict of short_name -> {description, year, manufacturer, type}."""
    print("  Parsing MAME.dat...")
    text = data.decode("utf-8", errors="replace")
    games = {}

    # DAT format: game ( name "..." description "..." year "..." manufacturer "..." )
    # Use regex to find game blocks with quoted fields
    game_pattern = re.compile(
        r'game\s*\(\s*\n'
        r'\s*name\s+"([^"]+)"\s*\n'
        r'(?:\s*(?:release)?year\s+"([^"]+)"\s*\n)?'
        r'(?:\s*developer\s+"([^"]+)"\s*\n)?'
        r'(?:\s*manufacturer\s+"([^"]+)"\s*\n)?'
        r'(?:\s*description\s+"([^"]+)"\s*\n)?'
        r'(?:\s*type\s+"([^"]+)"\s*\n)?'
        r'(?:\s*rom\s*\([^)]*\)\s*\n)*'
        r'\s*\)',
        re.MULTILINE
    )

    for match in game_pattern.finditer(text):
        name = match.group(1)
        year = match.group(2)
        developer = match.group(3)
        manufacturer = match.group(4)
        description = match.group(5)
        game_type = match.group(6)

        games[name] = {
            "description": description if description else name,
            "year": year,
            "manufacturer": manufacturer or developer,
            "type": game_type or "unknown"
        }

    print(f"  Parsed {len(games):,} entries from MAME.dat")
    return games


def parse_bios_dat(data):
    """Parse MAME BIOS.dat and return set of BIOS short names."""
    print("  Parsing MAME BIOS.dat...")
    text = data.decode("utf-8", errors="replace")
    bios_names = set()

    # Same format as DAT but with BIOS entries
    game_pattern = re.compile(
        r'game\s*\(\s*\n'
        r'\s*name\s+"([^"]+)"\s*\n',
        re.MULTILINE
    )

    for match in game_pattern.finditer(text):
        name = match.group(1)
        bios_names.add(name)

    print(f"  Found {len(bios_names):,} BIOS entries")
    return bios_names


def merge_data(xml_games, dat_games, bios_names):
    """Merge XML data with DAT descriptions and BIOS flags."""
    print("  Merging data...")
    merged = {}

    for short_name, game_data in xml_games.items():
        # Override with DAT info if available
        if short_name in dat_games:
            dat_entry = dat_games[short_name]
            if dat_entry["description"] != short_name:
                game_data["description"] = dat_entry["description"]
            if dat_entry["year"] and not game_data["year"]:
                game_data["year"] = dat_entry["year"]
            if dat_entry["manufacturer"] and not game_data["manufacturer"]:
                game_data["manufacturer"] = dat_entry["manufacturer"]

        # Mark BIOS entries
        if short_name in bios_names:
            game_data["isBIOS"] = True

        merged[short_name] = game_data

    # Also add any entries from DAT that aren't in XML (with unknown status)
    for short_name, dat_entry in dat_games.items():
        if short_name not in merged:
            # Check if it's a BIOS
            is_bios = short_name in bios_names

            merged[short_name] = {
                "description": dat_entry["description"],
                "year": dat_entry["year"],
                "manufacturer": dat_entry["manufacturer"],
                "runnable": not is_bios,
                "isBIOS": is_bios,
                "cloneOf": None,
                "romOf": None,
                "sampleOf": None,
                "mergedROMs": [],
                "players": None,
                "control": None,
                "coins": None,
                "orientation": None,
                "screenType": None,
                "width": None,
                "height": None,
                "aspectX": None,
                "aspectY": None,
                "refreshRate": None,
                "cpu": None,
                "cpuClock": None,
                "audio": None,
                "soundChannels": None,
                "driverStatus": None,
                "driverColor": None,
                "driverSound": None
            }

    print(f"  Merged: {len(merged):,} total entries")
    return merged


def get_text(elem, tag):
    """Get text content of a child element."""
    child = elem.find(tag)
    return child.text.strip() if child is not None and child.text else None


def get_attr(elem, attr):
    """Get attribute from element, handling None."""
    if elem is None:
        return None
    return elem.get(attr)


def safe_int(val):
    """Convert to int safely."""
    if val is None:
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


def safe_float(val):
    """Convert to float safely."""
    if val is None:
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def main():
    print("=" * 60)
    print("Building MAME 2003-Plus Unified Database")
    print("=" * 60)

    # Step 1: Download sources
    print("\n[1/4] Downloading sources...")
    xml_data = download_file(XML_URL, "MAME 2003-Plus XML")
    dat_data = download_file(DAT_URL, "MAME.dat")
    bios_data = download_file(BIOS_URL, "MAME BIOS.dat")

    if xml_data is None:
        print("ERROR: Failed to download XML source")
        sys.exit(1)

    # Step 2: Parse XML
    print("\n[2/4] Parsing MAME 2003-Plus XML...")
    xml_games = parse_xml(xml_data)

    if not xml_games:
        print("ERROR: No games parsed from XML")
        sys.exit(1)

    # Step 3: Parse DAT files (optional, for enrichment)
    print("\n[3/4] Parsing DAT files...")
    dat_games = {}
    bios_names = set()

    if dat_data:
        dat_games = parse_dat(dat_data)

    if bios_data:
        bios_names = parse_bios_dat(bios_data)

    # Step 4: Merge and output
    print("\n[4/4] Merging and generating JSON...")
    merged = merge_data(xml_games, dat_games, bios_names)

    # Count stats
    runnable_count = sum(1 for g in merged.values() if g["runnable"])
    bios_count = sum(1 for g in merged.values() if g["isBIOS"])
    unplayable_count = sum(1 for g in merged.values() if not g["runnable"] and not g["isBIOS"])

    output = {
        "metadata": {
            "core": "mame2003_plus",
            "coreDisplayName": "MAME 2003-Plus",
            "generatedAt": __import__("datetime").datetime.now().isoformat(),
            "totalEntries": len(merged),
            "runnableGames": runnable_count,
            "biosEntries": bios_count,
            "unplayableEntries": unplayable_count,
            "sources": {
                "xml": "MAME 2003-Plus XML.xml",
                "dat": "MAME.dat",
                "bios": "MAME BIOS.dat"
            }
        },
        "games": merged
    }

    # Write to output file
    output_path = os.path.join(os.path.dirname(__file__), "mame_2003_plus.json")

    # Also copy to Resources if the script is being run from the project root
    resources_path = os.path.join(os.path.dirname(__file__), "..", "..", "TruchiEmu", "Resources", "mame_2003_plus.json")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"\n  Written: {output_path}")

    # Copy to Resources if it's a different location
    if os.path.abspath(output_path) != os.path.abspath(resources_path):
        import shutil
        try:
            os.makedirs(os.path.dirname(resources_path), exist_ok=True)
            shutil.copy2(output_path, resources_path)
            print(f"  Copied to: {resources_path}")
        except Exception as e:
            print(f"  Note: Could not copy to Resources: {e}")

    # Print summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Total entries: {len(merged):,}")
    print(f"  Runnable games: {runnable_count:,}")
    print(f"  BIOS entries:   {bios_count:,}")
    print(f"  Unplayable:     {unplayable_count:,}")
    print(f"  File size:      {os.path.getsize(output_path):,} bytes")
    print("=" * 60)


if __name__ == "__main__":
    main()
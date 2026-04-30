#!/usr/bin/env python3
"""
Build mame_unified.json from all libretro-database MAME sources.

Downloads and merges:
  - MAME.dat (master game list)
  - MAME BIOS.dat (BIOS entries)
  - MAME 2000 XML.dat
  - MAME 2003 XML.xml
  - MAME 2003-Plus XML.xml
  - MAME 2010 XML.xml
  - MAME 2015 XML.zip
  - MAME 2016 XML (Arcade Only).xml
  - MAME 0.287 (from 7z archive)

Outputs a unified JSON where each zip maps to:
  - description, year, manufacturer
  - isBIOS flag
  - compatibleCores: list of cores that can run this game
  - Per-core dependencies: cloneOf, romOf, sampleOf, mergedROMs
  - Video/input/chip metadata (from the most complete source)
"""

import json
import os
import sys
import xml.etree.ElementTree as ET
from urllib.request import urlopen, Request
from urllib.error import URLError
import re
import zipfile
import io
import tempfile
import subprocess
import shutil

# Core definitions: each core maps to its XML/DAT source URL
CORE_SOURCES = {
    "mame2000": {
        "url": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202000%20XML.dat",
        "format": "dat",  # Actually XML despite the .dat extension
        "displayName": "MAME 2000"
    },
    "mame2003": {
        "url": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202003%20XML.xml",
        "format": "xml",
        "displayName": "MAME 2003"
    },
    "mame2003_plus": {
        "url": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202003-Plus%20XML.xml",
        "format": "xml",
        "displayName": "MAME 2003-Plus"
    },
    "mame2010": {
        "url": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202010%20XML.xml",
        "format": "xml",
        "displayName": "MAME 2010"
    },
    "mame2015": {
        "url": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202015%20XML.zip",
        "format": "xml_zip",
        "displayName": "MAME 2015"
    },
    "mame2016_arcade": {
        "url": "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202016%20XML%20%28Arcade%20Only%29.xml",
        "format": "xml",
        "displayName": "MAME 2016 (Arcade)"
    },
    "mame287": {
        "url": "https://www.progettosnaps.net/download/?tipo=dat_mame&file=/dats/MAME/packs/MAME_Dats_287.7z",
        "format": "7z",
        "displayName": "MAME 0.287",
        "local_path": "scripts/mame_lookup/MAME_Dats_287/DATs/MAME 0.287.dat"
    }
}

# Additional reference files
MAME_DAT_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME.dat"
MAME_BIOS_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%20BIOS.dat"

# Constants for 7z handling
MAME_287_7Z_URL = "https://www.progettosnaps.net/download/?tipo=dat_mame&file=/dats/MAME/packs/MAME_Dats_287.7z"
MAME_287_DIR = "scripts/mame_lookup/MAME_Dats_287"


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
        print(f"  WARNING: Failed to download {desc}: {e}")
        return None


def download_and_extract_7z(url, target_dir):
    """Download a 7z file and extract it using system 7z."""
    print(f"  Downloading and extracting 7z: {url}")
    archive_path = os.path.join(target_dir, "mame_287_temp.7z")
    
    try:
        os.makedirs(target_dir, exist_ok=True)
        # Download
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req) as response:
            with open(archive_path, 'wb') as f:
                shutil.copyfileobj(response, f)
        
        # Extract
        print(f"  Extracting to {target_dir}...")
        # Using '7z x' to extract with full paths
        result = subprocess.run(['7z', 'x', archive_path, f'-o{target_dir}', '-y'], 
                                capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"  ERROR: 7z extraction failed: {result.stderr}")
            return False
            
        # Cleanup archive
        os.remove(archive_path)
        return True
    except Exception as e:
        print(f"  ERROR: Failed during 7z download/extraction: {e}")
        return False


def parse_xml_data(file_path_or_data, core_id):
    """
    Parse MAME XML and return dict of short_name -> game data.
    Supports both raw bytes (data) and file paths for memory efficiency.
    """
    games = {}
    
    def process_element(game_elem):
        short_name = game_elem.get("name")
        if not short_name:
            return

        runnable = game_elem.get("runnable", "yes") != "no"
        clone_of = game_elem.get("cloneof")
        rom_of = game_elem.get("romof")
        sample_of = game_elem.get("sampleof")

        description = _get_text(game_elem, "description")
        year = _get_text(game_elem, "year")
        manufacturer = _get_text(game_elem, "manufacturer")

        # Video info
        video_elem = game_elem.find("video")
        orientation = _get_attr(video_elem, "orientation")
        screen_type = _get_attr(video_elem, "screen")
        width = _safe_int(_get_attr(video_elem, "width"))
        height = _safe_int(_get_attr(video_elem, "height"))
        aspect_x = _safe_int(_get_attr(video_elem, "aspectx"))
        aspect_y = _safe_int(_get_attr(video_elem, "aspecty"))
        refresh_rate = _safe_float(_get_attr(video_elem, "refresh"))

        # Input info
        input_elem = game_elem.find("input")
        players = _safe_int(_get_attr(input_elem, "players"))
        control = _get_attr(input_elem, "control")

        # Chip info
        cpus = []
        audio_chips = []
        for chip_elem in game_elem.findall("chip"):
            chip_type = chip_elem.get("type")
            chip_name = chip_elem.get("name")
            if chip_type == "cpu" and chip_name:
                cpus.append(chip_name)
            elif chip_type == "audio" and chip_name:
                audio_chips.append(chip_name)

        # Driver info
        driver_elem = game_elem.find("driver")
        driver_status = _get_attr(driver_elem, "status")

        # ROM merge info
        merged_roms = []
        for rom_elem in game_elem.findall("rom"):
            merge = rom_elem.get("merge")
            if merge:
                merged_roms.append(merge)

        games[short_name] = {
            "description": description or short_name,
            "year": year,
            "manufacturer": manufacturer,
            "runnable": runnable,
            "cloneOf": clone_of,
            "romOf": rom_of if rom_of else (clone_of if clone_of else None),
            "sampleOf": sample_of,
            "mergedROMs": list(set(merged_roms)) if merged_roms else [],
            "players": players,
            "control": control,
            "orientation": orientation,
            "screenType": screen_type,
            "width": width,
            "height": height,
            "aspectX": aspect_x,
            "aspectY": aspect_y,
            "refreshRate": refresh_rate,
            "cpu": cpus[0] if cpus else None,
            "audio": audio_chips if audio_chips else None,
            "driverStatus": driver_status
        }

    try:
        if isinstance(file_path_or_data, str):
            # It's a file path, use iterparse for memory efficiency
            context = ET.iterparse(file_path_or_data, events=("end",))
            for event, elem in context:
                if elem.tag in ("game", "machine"):
                    process_element(elem)
                    elem.clear() # Free memory
        else:
            # It's raw bytes, use fromstring (less efficient but unavoidable for small chunks)
            root = ET.fromstring(file_path_or_data)
            for game_elem in root.findall("game") + root.findall("machine"):
                process_element(game_elem)
    except Exception as e:
        print(f"  WARNING: XML parse failed for {core_id}: {e}")
        return {}

    print(f"  Parsed {len(games):,} games from {core_id}")
    return games


def parse_dat_format(data):
    """Parse MAME.dat format and return dict of short_name -> {description, year, manufacturer}."""
    text = data.decode("utf-8", errors="replace")
    games = {}

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
    text = data.decode("utf-8", errors="replace")
    bios_names = set()

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


def build_unified_database():
    """Build the unified MAME database from all sources."""
    print("=" * 60)
    print("Building MAME Unified Database")
    print("=" * 60)

    # Step 1: Download reference files
    print("\n[1/4] Downloading reference files...")
    dat_data = download_file(MAME_DAT_URL, "MAME.dat")
    bios_data = download_file(MAME_BIOS_URL, "MAME BIOS.dat")

    dat_games = {}
    bios_names = set()
    if dat_data:
        dat_games = parse_dat_format(dat_data)
    if bios_data:
        bios_names = parse_bios_dat(bios_data)

    # Step 2: Download and parse each core's XML
    print("\n[2/4] Downloading and parsing core XML files...")
    core_data = {}
    for core_id, source in CORE_SOURCES.items():
        # Check if it's a local file first (for MAME 0.287)
        local_path = source.get("local_path")
        if local_path and os.path.exists(local_path):
            print(f"  Using local file for {source['displayName']}...")
            games = parse_xml_data(local_path, core_id)
            core_data[core_id] = {
                "displayName": source["displayName"],
                "games": games
            }
            continue
        
        # If it's MAME 287 and not local, try downloading and extracting 7z
        if core_id == "mame287" and source["format"] == "7z":
            if not download_and_extract_7z(source["url"], MAME_287_DIR):
                print(f"  Skipping {core_id} - download/extraction failed")
                continue
            # Re-check local path after extraction
            if os.path.exists(local_path):
                games = parse_xml_data(local_path, core_id)
            else:
                print(f"  WARNING: Local file {local_path} not found after extraction")
                continue
        elif source["format"] == "xml_zip":
            # Handle ZIP format (MAME 2015)
            data = download_file(source["url"], source["displayName"])
            if data is None:
                print(f"  Skipping {core_id} - download failed")
                continue

            try:
                with zipfile.ZipFile(io.BytesIO(data)) as zf:
                    xml_files = [f for f in zf.namelist() if f.endswith(('.xml', '.dat'))]
                    if xml_files:
                        data = zf.read(xml_files[0])
                    else:
                        print(f"  WARNING: No XML found in ZIP for {core_id}")
                        continue
            except Exception as e:
                print(f"  WARNING: Failed to extract ZIP for {core_id}: {e}")
                continue

            games = parse_xml_data(data, core_id)
            core_data[core_id] = {
                "displayName": source["displayName"],
                "games": games
            }
        else:
            data = download_file(source["url"], source["displayName"])
            if data is None:
                print(f"  Skipping {core_id} - download failed")
                continue

            games = parse_xml_data(data, core_id)
            core_data[core_id] = {
                "displayName": source["displayName"],
                "games": games
            }

    # Step 3: Merge all data
    print("\n[3/4] Merging data from all sources...")
    all_short_names = set()
    for core_id, core_info in core_data.items():
        all_short_names.update(core_info["games"].keys())
    all_short_names.update(dat_games.keys())

    unified_games = {}
    for short_name in sorted(all_short_names):
        # Collect per-core data
        core_deps = {}
        compatible_cores = []
        is_bios = short_name in bios_names

        # Best metadata (from most complete source)
        best_description = short_name
        best_year = None
        best_manufacturer = None
        best_orientation = None
        best_screen_type = None
        best_width = None
        best_height = None
        best_aspect_x = None
        best_aspect_y = None
        best_refresh_rate = None
        best_cpu = None
        best_audio = None
        best_players = None
        best_control = None
        best_driver_status = None

        for core_id, core_info in core_data.items():
            if short_name in core_info["games"]:
                game = core_info["games"][short_name]
                compatible_cores.append(core_id)

                core_deps[core_id] = {
                    "runnable": game["runnable"],
                    "cloneOf": game["cloneOf"],
                    "romOf": game["romOf"],
                    "sampleOf": game["sampleOf"],
                    "mergedROMs": game["mergedROMs"]
                }

                # Update best metadata if this entry has more info
                if game["description"] and game["description"] != short_name:
                    best_description = game["description"]
                if game["year"] and not best_year:
                    best_year = game["year"]
                if game["manufacturer"] and not best_manufacturer:
                    best_manufacturer = game["manufacturer"]
                if game["orientation"] and not best_orientation:
                    best_orientation = game["orientation"]
                if game["screenType"] and not best_screen_type:
                    best_screen_type = game["screenType"]
                if game["width"] and not best_width:
                    best_width = game["width"]
                if game["height"] and not best_height:
                    best_height = game["height"]
                if game["aspectX"] and not best_aspect_x:
                    best_aspect_x = game["aspectX"]
                if game["aspectY"] and not best_aspect_y:
                    best_aspect_y = game["aspectY"]
                if game["refreshRate"] and not best_refresh_rate:
                    best_refresh_rate = game["refreshRate"]
                if game["cpu"] and not best_cpu:
                    best_cpu = game["cpu"]
                if game["audio"] and not best_audio:
                    best_audio = game["audio"]
                if game["players"] and not best_players:
                    best_players = game["players"]
                if game["control"] and not best_control:
                    best_control = game["control"]
                if game["driverStatus"] and not best_driver_status:
                    best_driver_status = game["driverStatus"]

        # Enrich with DAT data if available
        if short_name in dat_games:
            dat_entry = dat_games[short_name]
            if dat_entry["description"] != short_name and best_description == short_name:
                best_description = dat_entry["description"]
            if dat_entry["year"] and not best_year:
                best_year = dat_entry["year"]
            if dat_entry["manufacturer"] and not best_manufacturer:
                best_manufacturer = dat_entry["manufacturer"]

        # Determine if BIOS from core data (runnable=false often means BIOS/device)
        if not compatible_cores:
            # Not in any core - check if it's a known BIOS
            is_bios = short_name in bios_names

        # Check if any core has this as runnable
        is_runnable_in_any_core = any(
            core_deps[c].get("runnable", True)
            for c in compatible_cores
        ) if compatible_cores else False

        # If not runnable in any core and not explicitly a BIOS, mark as unplayable
        if not is_runnable_in_any_core and not is_bios and compatible_cores:
            # It's in cores but not runnable - likely a device or system ROM
            pass  # Keep as-is, will be filtered by runnable status

        unified_games[short_name] = {
            "description": best_description,
            "year": best_year,
            "manufacturer": best_manufacturer,
            "isBIOS": is_bios,
            "compatibleCores": compatible_cores,
            "coreDeps": core_deps if core_deps else None,
            "players": best_players,
            "control": best_control,
            "orientation": best_orientation,
            "screenType": best_screen_type,
            "width": best_width,
            "height": best_height,
            "aspectX": best_aspect_x,
            "aspectY": best_aspect_y,
            "refreshRate": best_refresh_rate,
            "cpu": best_cpu,
            "audio": best_audio,
            "driverStatus": best_driver_status
        }

    # Step 4: Generate output
    print("\n[4/4] Generating unified JSON...")

    # Count stats
    total = len(unified_games)
    in_any_core = sum(1 for g in unified_games.values() if g["compatibleCores"])
    not_in_any_core = total - in_any_core
    bios_count = sum(1 for g in unified_games.values() if g["isBIOS"])

    # Count runnable in each core
    core_runnable_counts = {}
    for core_id in CORE_SOURCES.keys():
        count = sum(
            1 for g in unified_games.values()
            if core_id in g["compatibleCores"]
            and g["coreDeps"]
            and g["coreDeps"].get(core_id, {}).get("runnable", True)
        )
        core_runnable_counts[core_id] = count

    output = {
        "metadata": {
            "generatedAt": __import__("datetime").datetime.now().isoformat(),
            "totalEntries": total,
            "entriesInAtLeastOneCore": in_any_core,
            "entriesNotInAnyCore": not_in_any_core,
            "biosEntries": bios_count,
            "coreRunnableCounts": core_runnable_counts,
            "cores": {cid: info["displayName"] for cid, info in core_data.items()},
            "sources": {
                "dat": "MAME.dat",
                "bios": "MAME BIOS.dat",
                **{cid: f"{info['displayName']} XML" for cid, info in core_data.items()}
            }
        },
        "games": unified_games
    }

    # Write output
    output_path = os.path.join(os.path.dirname(__file__), "mame_unified.json")
    resources_path = os.path.join(os.path.dirname(__file__), "..", "..", "TruchiEmu", "Resources", "mame_unified.json")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"\n  Written: {output_path}")

    # Copy to Resources
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
    print(f"  Total unique entries:     {total:,}")
    print(f"  In at least one core:     {in_any_core:,}")
    print(f"  Not in any core:          {not_in_any_core:,}")
    print(f"  BIOS entries:             {bios_count:,}")
    print()
    print("  Runnable per core:")
    for core_id, count in core_runnable_counts.items():
        display = core_data[core_id]["displayName"] if core_id in core_data else core_id
        print(f"    {display}: {count:,}")
    print(f"  File size:                {os.path.getsize(output_path):,} bytes")
    print("=" * 60)


def _get_text(elem, tag):
    child = elem.find(tag)
    return child.text.strip() if child is not None and child.text else None


def _get_attr(elem, attr):
    if elem is None:
        return None
    return elem.get(attr)


def _safe_int(val):
    if val is None:
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


def _safe_float(val):
    if val is None:
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


if __name__ == "__main__":
    build_unified_database()
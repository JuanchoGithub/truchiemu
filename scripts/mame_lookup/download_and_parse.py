#!/usr/bin/env python3
"""
MAME ROM Database Downloader

Downloads MAME.dat (games) and MAME BIOS.dat from libretro-database,
then produces a combined JSON database for use in TruchiEmu.
"""

import json
import os
import re
import urllib.request
import ssl
import sys
import zipfile
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime

# SSL context for requests
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# Output directory
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "mame_rom_data.json")

# Source URLs - libretro-database metadat/mame/
MAME_GAMES_DAT_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME.dat"
MAME_BIOS_DAT_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%20BIOS.dat"
MAME_2015_XML_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/mame/MAME%202015%20XML.zip"
MAME_LST_URL = "https://raw.githubusercontent.com/mamedev/mame/master/src/mame/mame.lst"


def download_file(url: str, label: str) -> str:
    """Download a file and return its content."""
    print(f"  Downloading {label}...")
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)')
        with urllib.request.urlopen(req, context=ssl_context, timeout=120) as response:
            content = response.read().decode('utf-8', errors='replace')
            print(f"    Downloaded {len(content):,} bytes")
            return content
    except Exception as e:
        print(f"    ERROR: Failed to download {label}: {e}")
        return ""


def download_binary(url: str, label: str) -> bytes:
    """Download a binary file and return its content as bytes."""
    print(f"  Downloading {label}...")
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)')
        with urllib.request.urlopen(req, context=ssl_context, timeout=180) as response:
            content = response.read()
            print(f"    Downloaded {len(content):,} bytes")
            return content
    except Exception as e:
        print(f"    ERROR: Failed to download {label}: {e}")
        return b""


def parse_mame_2015_xml(zip_data: bytes) -> dict:
    """
    Parse MAME 2015 XML.zip to extract ALL machines including devices.
    
    This is the most comprehensive source - it includes:
    - Arcade games
    - BIOS sets
    - Device ROMs (isdevice="yes")
    - Mechanical machines (ismechanical="yes")
    - Non-runnable machines (runnable="no")
    
    Returns dict: {shortname: {metadata}}
    """
    roms = {}
    
    # Write zip data to temp file
    tmp_path = tempfile.mktemp(suffix='.zip')
    try:
        with open(tmp_path, 'wb') as f:
            f.write(zip_data)
        
        with zipfile.ZipFile(tmp_path, 'r') as zip_ref:
            # Find the XML file inside
            xml_names = [n for n in zip_ref.namelist() if n.endswith('.xml')]
            if not xml_names:
                print("    ERROR: No XML file found in zip")
                return roms
            
            xml_name = xml_names[0]
            print(f"    Extracting {xml_name}...")
            
            with zip_ref.open(xml_name) as xml_file:
                # Parse XML incrementally
                context = ET.iterparse(xml_file, events=('end',))
                
                count = 0
                device_count = 0
                bios_count = 0
                game_count = 0
                mech_count = 0
                
                for event, elem in context:
                    if elem.tag == 'game':
                        # Extract attributes
                        name = elem.get('name', '')
                        is_bios = elem.get('isbios', 'no') == 'yes'
                        is_device = elem.get('isdevice', 'no') == 'yes'
                        is_mechanical = elem.get('ismechanical', 'no') == 'yes'
                        is_runnable = elem.get('runnable', 'yes') == 'yes'
                        cloneof = elem.get('cloneof')
                        
                        # Extract child elements
                        description = ''
                        year = None
                        manufacturer = None
                        
                        for child in elem:
                            if child.tag == 'description':
                                description = child.text or ''
                            elif child.tag == 'year':
                                year = child.text
                            elif child.tag == 'manufacturer':
                                manufacturer = child.text
                        
                        # Determine type
                        if is_mechanical:
                            rom_type = "mechanical"
                        elif is_device:
                            rom_type = "device"
                        elif is_bios:
                            rom_type = "bios"
                        else:
                            rom_type = "game"
                        
                        # The machine name IS the ROM shortname (zip filename)
                        if name:
                            entry = {
                                "name": name,
                                "description": description or name,
                                "type": rom_type,
                                "isRunnable": is_runnable if rom_type == "game" else False,
                                "year": year,
                                "manufacturer": manufacturer or "",
                                "parent": cloneof,
                                "players": None
                            }
                            
                            roms[name] = entry
                            count += 1
                            
                            if is_device:
                                device_count += 1
                            elif is_bios:
                                bios_count += 1
                            elif is_mechanical:
                                mech_count += 1
                            else:
                                game_count += 1
                        
                        # Clear element to free memory
                        elem.clear()
                
                print(f"    Parsed {count:,} total entries")
                print(f"      Games: {game_count:,}")
                print(f"      BIOS: {bios_count:,}")
                print(f"      Devices: {device_count:,}")
                print(f"      Mechanical: {mech_count:,}")
    
    except zipfile.BadZipFile:
        print(f"    ERROR: Downloaded file is not a valid zip")
        print(f"    First 200 bytes: {zip_data[:200]}")
    except Exception as e:
        print(f"    ERROR parsing XML: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Cleanup temp file
        try:
            os.unlink(tmp_path)
        except:
            pass
    
    return roms


def parse_mame_lst(content: str) -> dict:
    """
    Parse MAME's official mame.lst file to extract ALL machine names.
    
    This is the most up-to-date source for machine names, but it only
    contains shortnames without descriptions. We use it to fill gaps
    for devices/software that aren't in the XML.
    
    Format:
    @source:path/file.cpp
    machinename
    machineclone (cloneof=parent)
    
    Returns dict: {shortname: {metadata}}
    """
    roms = {}
    current_source = ""
    
    for line in content.split('\n'):
        line = line.strip()
        
        # Skip empty lines and comments
        if not line or line.startswith('//'):
            continue
        
        # Track source file
        if line.startswith('@source:'):
            current_source = line[8:]
            continue
        
        # Skip other directives
        if line.startswith('@'):
            continue
        
        # Parse machine name
        # Format: name or name (cloneof=parent)
        match = re.match(r'^([a-zA-Z0-9_]+)', line)
        if match:
            name = match.group(1)
            
            # Determine if it's a clone
            clone_match = re.search(r'\(cloneof=([a-zA-Z0-9_]+)\)', line)
            parent = clone_match.group(1) if clone_match else None
            
            # Try to infer type from source path
            rom_type = "unknown"
            source_lower = current_source.lower()
            if 'machine' in source_lower or 'video' in source_lower or 'audio' in source_lower:
                rom_type = "device"
            elif 'bus' in source_lower:
                rom_type = "device"
            elif 'imagedev' in source_lower:
                rom_type = "device"
            
            roms[name] = {
                "name": name,
                "description": name,
                "type": rom_type,
                "isRunnable": False,  # Conservative - assume not runnable
                "year": None,
                "manufacturer": "",
                "parent": parent,
                "players": None,
                "source": current_source
            }
    
    return roms


def parse_dat_block(content: str, default_type: str = "game") -> dict:
    """
    Parse a MAME DAT file into a dictionary.
    
    The DAT format from libretro uses the game's DISPLAY TITLE as the game name,
    not the ROM shortname. The actual ROM shortname/zip filename is inside
    the first rom() block's name attribute.
    
    Example:
    game (
        name "10-Yard Fight (World, set 1)"     <-- display title, NOT the zip name
        year "1983"
        developer "Irem"
        rom ( name 10yard.zip size 62708 ... )  <-- actual ROM shortname!
    )
    
    Returns dict: {shortname: {metadata}}
    """
    roms = {}
    
    # Find all "game (" blocks, handling nested parentheses
    game_pattern = re.compile(r'^\s*game\s*\(', re.MULTILINE)
    starts = [m.start() for m in game_pattern.finditer(content)]
    
    for start_pos in starts:
        # Find the opening/closing parens
        paren_pos = content.index('(', start_pos)
        paren_depth = 0
        pos = paren_pos
        
        while pos < len(content):
            char = content[pos]
            if char == '(':
                paren_depth += 1
            elif char == ')':
                paren_depth -= 1
                if paren_depth == 0:
                    break
            pos += 1
        
        block = content[paren_pos+1:pos]
        
        # Extract display title (the "name" field at game level)
        display_name_match = re.search(r'name\s+"([^"]*)"', block)
        display_name = display_name_match.group(1) if display_name_match else ""
        
        # Extract ROM shortnames from rom() blocks
        # Each game can have multiple rom entries (parent + clones share ROMs)
        # We want to capture ALL of them
        rom_name_pattern = re.compile(r'rom\s*\(\s*name\s+([^\s)]+)')
        shortnames = []
        for rom_match in rom_name_pattern.finditer(block):
            sn = rom_match.group(1).replace('.zip', '')
            if sn and sn not in shortnames:
                shortnames.append(sn)
        
        # If no rom blocks found, try to derive shortname from display name
        if not shortnames:
            # Try to infer from the display name
            shortnames = [re.sub(r'[^a-zA-Z0-9_]', '', display_name.lower())]
            if not shortnames[0]:
                continue
        
        # Extract year (check both "year" and "releaseyear")
        year_match = re.search(r'(?:year|releaseyear)\s+"([^"]*)"', block)
        year = year_match.group(1) if year_match else None
        
        # Extract developer
        dev_match = re.search(r'developer\s+"([^"]*)"', block)
        developer = dev_match.group(1) if dev_match else None
        
        # Extract manufacturer
        mfr_match = re.search(r'manufacturer\s+"([^"]*)"', block)
        manufacturer = mfr_match.group(1) if mfr_match else None
        
        if not manufacturer:
            manufacturer = developer
        
        # Extract parent (clone_of)
        parent_match = re.search(r'clone_of\s+"([^"]*)"', block)
        parent = parent_match.group(1) if parent_match else None
        
        # Extract players
        players_match = re.search(r'players\s+"?(\d+)"?', block)
        players = int(players_match.group(1)) if players_match else None
        
        # Check for bios/device/mechanical/parent flags
        is_bios = bool(re.search(r'is bios', block))
        is_device = bool(re.search(r'is device', block))
        is_mechanical = bool(re.search(r'is mechanical', block))
        is_parent = bool(re.search(r'is parent', block))
        
        is_runnable_match = re.search(r'runnable\s+"?(\d+)"?', block)
        is_runnable = int(is_runnable_match.group(1)) == 1 if is_runnable_match else not is_bios and not is_device
        
        # Determine type
        if is_mechanical:
            rom_type = "mechanical"
        elif is_device:
            rom_type = "device"
        elif is_bios:
            rom_type = "bios"
        elif default_type == "bios":
            rom_type = "bios"
        else:
            rom_type = default_type
        
        # Add entry for each shortname found
        for shortname in shortnames:
            entry = {
                "name": shortname,
                "description": display_name,
                "type": rom_type,
                "isRunnable": is_runnable if rom_type == "game" else False,
                "year": year,
                "manufacturer": manufacturer or "",
                "parent": parent,
                "players": players
            }
            
            # If there are multiple shortnames, the primary one gets the main entry
            # and others are aliases
            roms[shortname] = entry
    
    return roms


def main():
    print("=" * 60)
    print("MAME ROM Database Downloader")
    print("=" * 60)
    print()
    
    # Step 1: Download MAME games database
    print("[1/3] Downloading MAME games database...")
    games_content = download_file(MAME_GAMES_DAT_URL, "MAME.dat (games)")
    games_data = {}
    
    if games_content:
        games_data = parse_dat_block(games_content, default_type="game")
        print(f"  Parsed {len(games_data):,} game entries")
    else:
        print("  WARNING: Could not download MAME games database")
    
    print()
    
    # Step 2: Download MAME BIOS database
    print("[2/3] Downloading MAME BIOS database...")
    bios_content = download_file(MAME_BIOS_DAT_URL, "MAME BIOS.dat")
    bios_data = {}
    
    if bios_content:
        bios_data = parse_dat_block(bios_content, default_type="bios")
        print(f"  Parsed {len(bios_data):,} BIOS/device entries")
    else:
        print("  WARNING: Could not download MAME BIOS database")
    
    print()
    
    # Step 3: Download and parse MAME 2015 XML (comprehensive - includes devices)
    print("[3/4] Downloading MAME 2015 XML (includes all machines + devices)...")
    xml_zip_data = download_binary(MAME_2015_XML_URL, "MAME 2015 XML.zip")
    xml_data = {}
    
    if xml_zip_data:
        xml_data = parse_mame_2015_xml(xml_zip_data)
        print(f"  Parsed {len(xml_data):,} entries from XML")
    else:
        print("  WARNING: Could not download MAME 2015 XML")
    
    print()
    
    # Step 3b: Download and parse MAME mame.lst (latest machine names)
    print("[3b/4] Downloading MAME mame.lst (latest machine names)...")
    lst_content = download_file(MAME_LST_URL, "mame.lst")
    lst_data = {}
    
    if lst_content:
        lst_data = parse_mame_lst(lst_content)
        print(f"  Parsed {len(lst_data):,} entries from mame.lst")
    else:
        print("  WARNING: Could not download MAME mame.lst")
    
    print()
    
    # Step 4: Merge all databases
    print("[4/4] Merging databases...")
    final_roms = {}
    
    # Start with XML data (most comprehensive, has device flags)
    final_roms.update(xml_data)
    
    # Override with games data (may have better descriptions)
    for rom_name, game_entry in games_data.items():
        if rom_name in final_roms:
            # Update description if XML has a generic one
            existing = final_roms[rom_name]
            if not existing.get("description") or existing["description"] == rom_name:
                existing["description"] = game_entry["description"]
            # Fill in missing fields
            if not existing.get("year") and game_entry.get("year"):
                existing["year"] = game_entry["year"]
            if not existing.get("manufacturer") and game_entry.get("manufacturer"):
                existing["manufacturer"] = game_entry["manufacturer"]
            if not existing.get("players") and game_entry.get("players"):
                existing["players"] = game_entry["players"]
        else:
            final_roms[rom_name] = game_entry
    
    # Override/add BIOS entries
    for rom_name, bios_entry in bios_data.items():
        if rom_name in final_roms:
            existing = final_roms[rom_name]
            if bios_entry["type"] in ("bios", "device", "mechanical"):
                existing["type"] = bios_entry["type"]
                existing["isRunnable"] = bios_entry["isRunnable"]
            if not existing.get("year") and bios_entry.get("year"):
                existing["year"] = bios_entry["year"]
            if not existing.get("manufacturer") and bios_entry.get("manufacturer"):
                existing["manufacturer"] = bios_entry["manufacturer"]
            if not existing.get("parent") and bios_entry.get("parent"):
                existing["parent"] = bios_entry["parent"]
        else:
            final_roms[rom_name] = bios_entry
    
    # Add entries from mame.lst that aren't already present
    # These are typically newer devices/software not in the 2015 XML
    lst_added = 0
    for rom_name, lst_entry in lst_data.items():
        if rom_name not in final_roms:
            final_roms[rom_name] = lst_entry
            lst_added += 1
        else:
            # If already exists but type is "unknown", try to update from lst source info
            existing = final_roms[rom_name]
            if existing["type"] == "unknown" and lst_entry["type"] != "unknown":
                existing["type"] = lst_entry["type"]
                existing["source"] = lst_entry.get("source", "")
    
    print(f"  Added {lst_added:,} new entries from mame.lst")
    
    output = {
        "metadata": {
            "source": "libretro-database MAME.dat + MAME BIOS.dat + MAME 2015 XML + mame.lst",
            "generatedAt": datetime.now().isoformat(),
            "totalEntries": len(final_roms),
            "gamesUrl": MAME_GAMES_DAT_URL,
            "biosUrl": MAME_BIOS_DAT_URL,
            "xmlUrl": MAME_2015_XML_URL
        },
        "roms": final_roms
    }
    
    # Write output
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    
    file_size = os.path.getsize(OUTPUT_FILE)
    print(f"\n  Output: {OUTPUT_FILE}")
    print(f"  File size: {file_size:,} bytes ({file_size / 1024 / 1024:.1f} MB)")
    print(f"  Total ROM entries: {len(final_roms):,}")
    
    # Stats
    type_counts = {}
    runnable_count = 0
    non_runnable_count = 0
    
    for entry in final_roms.values():
        rom_type = entry["type"]
        type_counts[rom_type] = type_counts.get(rom_type, 0) + 1
        if entry["isRunnable"]:
            runnable_count += 1
        else:
            non_runnable_count += 1
    
    print(f"\n  ROM Types:")
    for rom_type, count in sorted(type_counts.items()):
        print(f"    {rom_type:15s}: {count:,} ({count/len(final_roms)*100:.1f}%)")
    
    print(f"\n  Runnable: {runnable_count:,} ({runnable_count/len(final_roms)*100:.1f}%)")
    print(f"  Non-runnable (BIOS/Device): {non_runnable_count:,} ({non_runnable_count/len(final_roms)*100:.1f}%)")
    
    print(f"\n  Done! Database ready for import.")


if __name__ == '__main__':
    main()
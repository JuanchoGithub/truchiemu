#!/usr/bin/env python3
"""Add missing ROM entries to mame_rom_data.json based on analysis."""

import json
import os
import zipfile
import re
from datetime import datetime

ROMS_DIR = "/Users/jayjay/Downloads/roms/mame"
JSON_FILE = "/Users/jayjay/gitrepos/truchiemu/scripts/mame_lookup/mame_rom_data.json"

# Known mappings from analysis
PERIPHERAL_PATTERNS = ['kbd', 'keyboard', 'fdc', 'hdc', 'ide', 'scsi', 'bus', 'slot',
                       'cartridge', 'cart', 'eth', 'serial', 'rs232', 'modem', 'network',
                       'centronics', 'vdu', 'vga', 'hires', 'video', 'gfx', 'paddle',
                       'bios-devices', 'jcart', '_msx2', 'pcm', 'sound', 'econet', 'vib']

GAME_VARIANT_PATTERNS = [' (1)', ' (2)']

def classify_rom_name(name):
    """Classify a ROM name and return type and description."""
    lower = name.lower()

    # Game variants (name parsing issues)
    if any(p in name for p in GAME_VARIANT_PATTERNS):
        # Extract base name: "sf2 (1)" -> "sf2"
        base = name.split(' (')[0]
        return "game", f"{base} (variant)"

    # Keyboards
    if any(p in lower for p in ['kbd', 'keyboard']):
        return "peripheral", "Keyboard"

    # Storage controllers
    if any(p in lower for p in ['fdc', 'hdc', 'ide', 'scsi', '_dis']):
        return "peripheral", "Storage controller"

    # Bus/EXP cards
    if any(p in lower for p in ['bus', 'slot', 'cart', 'cartridge', 'msx_cart', '_econet', '_vib']):
        return "peripheral", "Expansion card/device"

    # Communication
    if any(p in lower for p in ['eth', 'serial', 'rs232', 'modem', 'centronics', '2ndserial']):
        return "peripheral", "Communication device"

    # Video
    if any(p in lower for p in ['vdu', 'vga', 'hires', 'lcd', 'cms_']):
        return "peripheral", "Video/display device"

    # Input devices
    if any(p in lower for p in ['paddle', 'diypaddle']):
        return "peripheral", "Input device"

    # Audio
    if any(p in lower for p in ['pcm', 'sound', 'audio', 'option_sound']):
        return "peripheral", "Audio device"

    # MAME system metadata
    if 'bios-devices' in lower or name == 'MAME (bios-devices)':
        return "bios", "MAME BIOS/Device metadata"

    # Small ROM dumps / MCU / single chips
    if name in ['Minivader', 'neogs', 'nlq401', 'pa7234', 'ks0066_f00', 'namco_de_pcb',
                'mps1200', 'mps1250', 'mvme327a', 'sfd1001', 'sn74s263', 'a2diskiing',
                'a2grafex', 'a2mockbd', 'abc80kb', 'arkanoid68705p3', 'arkanoid68705p5',
                'dragon_msx2', 'f4431_kbd', 'mg1_kbd_device', 'microtan_kbd_mt009',
                'nabu_keyboard', 'pc8801_23', 'pc88va2_fd_if', 'st_kbd', 'sv601',
                'tp881v', 'tanbus_ra32krom', 'ssideki4 (1)', 'bbc_lcd', 'sambus',
                'md_jcart', 'kok'] or len(name) <= 5:
        return "game", name  # Could be a game or small ROM

    # CPU/memory boards
    if any(p in lower for p in ['cpu', 'ram', 'rom', '8086', 'i82', 'ioc', 'mvme']):
        return "peripheral", "CPU/Memory board"

    # Unknown - default to game for safety (better to show than hide)
    return "game", name

def main():
    print("Loading mame_rom_data.json...")
    with open(JSON_FILE, 'r') as f:
        data = json.load(f)

    existing = set(data.get('roms', {}).keys())
    added = 0
    skipped = 0

    for filename in sorted(os.listdir(ROMS_DIR)):
        if not filename.lower().endswith('.zip'):
            continue
        rom_name = filename[:-4]
        if rom_name not in existing:
            rom_type, description = classify_rom_name(rom_name)

            # Analyze zip for more info
            filepath = os.path.join(ROMS_DIR, filename)
            file_count = 0
            try:
                with zipfile.ZipFile(filepath, 'r') as zf:
                    file_count = len(zf.namelist())
            except:
                pass

            entry = {
                "name": rom_name,
                "description": description,
                "type": rom_type,
                "isRunnable": rom_type == "game",
                "year": None,
                "manufacturer": None,
                "parent": None,
                "players": None,
                "fileCount": file_count
            }
            data['roms'][rom_name] = entry
            added += 1
        else:
            skipped += 1

    # Update metadata
    data['metadata']['generatedAt'] = datetime.now().isoformat()
    data['metadata']['totalEntries'] = len(data['roms'])
    data['metadata']['source'] += " + analyzed_unknowns"

    print(f"Added {added} entries")
    print(f"Total entries: {len(data['roms'])}")

    with open(JSON_FILE, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"Saved to {JSON_FILE}")

if __name__ == "__main__":
    main()
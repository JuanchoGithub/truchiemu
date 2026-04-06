#!/usr/bin/env python3
"""Analyze unknown zip files by examining their contents."""

import json
import os
import sys
import zipfile
import re

ROMS_DIR = "/Users/jayjay/Downloads/roms/mame"
JSON_FILE = "/Users/jayjay/gitrepos/truchiemu/scripts/mame_lookup/mame_rom_data.json"

def get_unknown_zips():
    """Get list of zip files not found in JSON."""
    with open(JSON_FILE, 'r') as f:
        rom_data = json.load(f)
    existing = set(rom_data.get('roms', {}).keys())

    unknown = []
    for f in sorted(os.listdir(ROMS_DIR)):
        if f.lower().endswith('.zip'):
            name = f[:-4]
            if name not in existing:
                unknown.append(f)
    return unknown

def analyze_zip(filepath, zip_name):
    """Analyze a zip file and return classification."""
    rom_name = zip_name[:-4]
    info = {'name': rom_name, 'type': 'unknown', 'details': '', 'chips': []}

    try:
        with zipfile.ZipFile(filepath, 'r') as zf:
            files = zf.namelist()

            # Check for MAME metadata files
            has_run_flag = any(f.endswith('.run_flag') for f in files)
            has_software_list = any('hash' in f.lower() or 'softlist' in f.lower() for f in files)
            has_roms = any(f.endswith(('.rom', '.bin', '.epr', '.ic', '.a0', '.a1')) for f in files)

            # Check for text/info files
            info_files = [f for f in files if f.endswith(('.txt', '.xml', '.lst'))]

            # Check file patterns
            rom_files = [f for f in files if '.' in f and len(f.split('.')[-1]) <= 4 and not f.startswith('.')]

            # Analyze name patterns
            lower_name = rom_name.lower()

            # Keyboard patterns
            if any(k in lower_name for k in ['kbd', 'keyboard']):
                info['type'] = 'peripheral'
                info['details'] = 'Keyboard'

            # BIOS/hardware device patterns
            elif any(p in lower_name for p in ['fdc', 'hdc', 'ide', 'scsi', 'bus', 'slot', 'cartridge', 'cart', 'bios']):
                info['type'] = 'peripheral'
                info['details'] = 'Hardware device/expansion'

            # Sound/audio patterns
            elif any(p in lower_name for p in ['pcm', 'sound', 'audio', 'ym', 'fm', 'opn']):
                info['type'] = 'peripheral'
                info['details'] = 'Sound/audio hardware'

            # Video/graphics patterns
            elif any(p in lower_name for p in ['vdu', 'vga', 'hires', 'video', 'gfx']):
                info['type'] = 'peripheral'
                info['details'] = 'Video/graphics hardware'

            # Serial/communication patterns
            elif any(p in lower_name for p in ['eth', 'serial', 'rs232', 'modem', 'network', 'centronics']):
                info['type'] = 'peripheral'
                info['details'] = 'Communication hardware'

            # Memory patterns
            elif any(p in lower_name for p in ['ram', 'rom', 'eeprom', 'flash']):
                info['type'] = 'peripheral'
                info['details'] = 'Memory hardware'

            # Controller patterns
            elif any(p in lower_name for p in ['ctrl', 'paddle', 'joystick', 'gamepad', 'mouse']):
                info['type'] = 'peripheral'
                info['details'] = 'Input device'

            # Special patterns
            elif any(p in lower_name for p in ['bios-devices', 'software list', 'softlist', 'hash']):
                info['type'] = 'system'
                info['details'] = 'MAME system/software list'

            # Numbered/lettered ROM chips (like coh1000a, coh1002e)
            elif re.match(r'^coh\d+[a-z]$', rom_name):
                info['type'] = 'game_rom'
                info['details'] = 'CH game ROM (likely Sega Model 3 or similar)'

            # Patterns with numbers in parentheses (variants)
            elif '(' in rom_name and ')' in rom_name:
                info['type'] = 'game_variant'
                info['details'] = 'Game variant/revision (name parsing issue)'

            # Check if it's a software list entry
            elif any(p in lower_name for p in ['smd', 'megadrive', 'snes', 'nes', 'gba', 'gg', 'sms', 'pce', 'tg16', 'ngp', 'psx', 'cd']):
                info['type'] = 'software'
                info['details'] = 'Console/game software'

            # If it has actual ROM files, likely a game
            elif len(rom_files) > 2:
                info['type'] = 'game_rom'
                info['details'] = f'Contains {len(rom_files)} ROM files'

            # Check number of files to guess
            elif len(files) <= 3:
                info['type'] = 'peripheral'
                info['details'] = f'Small file count ({len(files)}), likely device ROM'
            else:
                info['type'] = 'unknown'
                info['details'] = f'{len(files)} files, needs manual review'
                if rom_files[:5]:
                    info['chips'] = rom_files[:3]

    except Exception as e:
        info['type'] = 'error'
        info['details'] = str(e)

    return info

def main():
    unknown_zips = get_unknown_zips()
    print(f"Found {len(unknown_zips)} unknown zip files\n")

    results = {'game_rom': [], 'game_variant': [], 'peripheral': [], 'software': [], 'system': [], 'error': [], 'unknown': []}

    for zip_name in unknown_zips:
        filepath = os.path.join(ROMS_DIR, zip_name)
        info = analyze_zip(filepath, zip_name)
        category = info['type']
        if category in results:
            results[category].append(info)
        else:
            results['unknown'].append(info)

    # Print summary
    print("=" * 70)
    print("Unknown Zip File Analysis")
    print("=" * 70)
    print(f"\n{'Category':<20} {'Count':>6}")
    print("-" * 70)

    total = 0
    for cat, items in results.items():
        count = len(items)
        total += count
        print(f"  {cat:<18} {count:>6}")

    print("-" * 70)
    print(f"  {'TOTAL':<18} {total:>6}")
    print("=" * 70)

    # Print details by category
    for cat, items in results.items():
        if items:
            print(f"\n--- {cat.upper()} ({len(items)} items) ---")
            for item in sorted(items, key=lambda x: x['name']):
                detail = item['details']
                chips = f" [{', '.join(item['chips'])}]" if item.get('chips') else ''
                print(f"  {item['name']:<40} {detail}{chips}")

if __name__ == "__main__":
    main()
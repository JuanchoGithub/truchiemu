#!/usr/bin/env python3
"""Check MAME ROM coverage against known ROM data."""

import json
import os
import sys

ROMS_DIR = "/Users/jayjay/Downloads/roms/mame"
JSON_FILE = "/Users/jayjay/gitrepos/truchiemu/scripts/mame_lookup/mame_rom_data.json"

def get_zip_files(directory):
    """Get all .zip files from directory, return set of names without extension."""
    zip_names = set()
    try:
        for f in os.listdir(directory):
            if f.lower().endswith('.zip'):
                zip_names.add(f[:-4])  # Remove .zip extension
    except FileNotFoundError:
        print(f"Error: Directory {directory} not found")
        sys.exit(1)
    return zip_names

def load_json(filepath):
    """Load JSON file and return roms dict."""
    with open(filepath, 'r') as f:
        data = json.load(f)
    return data.get('roms', {})

def main():
    # Get all zip files
    zip_files = get_zip_files(ROMS_DIR)
    total_zips = len(zip_files)
    print(f"Total zip files found: {total_zips}\n")

    # Load JSON data
    rom_data = load_json(JSON_FILE)
    print(f"Total entries in JSON: {len(rom_data)}\n")

    # Categorize - count ANY entry in JSON as "found"
    found = {"game": [], "bios": [], "mechanical": [], "peripheral": [], "device": [], "unknown": []}
    no_info = []

    for zip_name in sorted(zip_files):
        if zip_name in rom_data:
            entry_type = rom_data[zip_name].get("type", "unknown")
            if entry_type in found:
                found[entry_type].append(zip_name)
            elif entry_type == "game_variant":
                found["game"].append(zip_name)
            elif entry_type == "software":
                found["game"].append(zip_name)
            else:
                # Still found in JSON but uncategorized type
                found["game"].append(zip_name)
        else:
            no_info.append(zip_name)

    # Calculate percentages
    print("=" * 60)
    print("MAME ROM Coverage Report")
    print("=" * 60)
    print(f"\n{'Category':<20} {'Count':>8} {'Percentage':>12}")
    print("-" * 60)

    for category in ["game", "bios", "mechanical"]:
        count = len(found[category])
        pct = (count / total_zips) * 100
        print(f"  {category:<18} {count:>8} {pct:>10.2f}%")

    no_info_count = len(no_info)
    no_info_pct = (no_info_count / total_zips) * 100
    print(f"  {'no info':<18} {no_info_count:>8} {no_info_pct:>10.2f}%")

    print("-" * 60)
    total_found = sum(len(v) for v in found.values())
    total_pct = (total_found / total_zips) * 100
    print(f"  {'TOTAL FOUND':<18} {total_found:>8} {total_pct:>10.2f}%")
    print(f"  {'TOTAL':<18} {total_zips:>8} {100.00:>10.2f}%")
    print("=" * 60)

    # Show some "no info" entries
    if no_info:
        print(f"\n\"No info\" entries ({no_info_count}):")
        print("-" * 60)
        for name in sorted(no_info):
            print(f"  {name}")

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""Fetch additional MAME ROM data sources and merge them into mame_rom_data.json."""

import json
import urllib.request
import sys
from datetime import datetime

JSON_FILE = "/Users/jayjay/gitrepos/truchiemu/scripts/mame_lookup/mame_rom_data.json"

SOURCES = [
    {
        "name": "mame-roms1",
        "url": "https://gist.githubusercontent.com/mrazjava/c3535356eaff3f7f4fd4705919919471/raw/a770e55a2028ecf1c193ba1fcc629b4a62d90a67/mame-roms1.md"
    },
    {
        "name": "mame-roms2",
        "url": "https://gist.githubusercontent.com/vmartins/b7217b5db318b3fa3687e5074fa6ca34/raw/489c6eacc6b2b8345933942f7d80720f34a80068/mame-roms2.md"
    }
]

def fetch_url(url):
    """Fetch content from URL."""
    print(f"  Fetching: {url}")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read().decode('utf-8')
    except Exception as e:
        print(f"  WARNING: Failed to fetch {url}: {e}")
        return None

def parse_markdown_table(content):
    """Parse a markdown table and extract ROM names.
    
    Format: |File|Name|Developer|Date|
    Where File is like: [005.zip](...)
    And Name is like: [005](...) or [10-Yard Fight](...)
    """
    import re
    roms = {}
    if not content:
        return roms

    lines = content.strip().split('\n')
    for line in lines:
        line = line.strip()
        if not line or line.startswith('|---') or line.startswith('+---') or line.startswith('#'):
            continue
        
        # Parse markdown table row: | File | Name | Developer | Date |
        parts = [p.strip() for p in line.split('|')]
        parts = [p for p in parts if p]  # Remove empty strings
        
        if len(parts) >= 1:
            # Extract ROM name from File column: [005.zip](url)
            file_part = parts[0].strip()
            match = re.search(r'\[([^\]]+)\]', file_part)
            if not match:
                continue
            file_name = match.group(1)  # e.g., "005.zip"
            if not file_name.lower().endswith('.zip'):
                continue
            rom_name = file_name[:-4]  # Remove .zip
            
            # Skip header row
            if rom_name.lower() in ('file', 'rom', 'rom name'):
                continue
            
            # Extract display name from Name column: [Display Name](url) or raw text
            description = rom_name
            if len(parts) >= 2:
                name_part = parts[1].strip()
                name_match = re.search(r'\[([^\]]+)\]', name_part)
                if name_match:
                    description = name_match.group(1)
                elif name_part:
                    description = name_part
            
            # Extract developer
            manufacturer = None
            if len(parts) >= 3:
                dev_part = parts[2].strip()
                dev_match = re.search(r'\[([^\]]+)\]', dev_part)
                if dev_match:
                    manufacturer = dev_match.group(1)
                elif dev_part:
                    manufacturer = dev_part
            
            # Extract year
            year = None
            if len(parts) >= 4:
                date_part = parts[3].strip()
                date_match = re.search(r'\d{4}', date_part)
                if date_match:
                    year = date_match.group(0)

            roms[rom_name] = {
                "name": rom_name,
                "description": description,
                "type": "game",
                "isRunnable": True,
                "year": year,
                "manufacturer": manufacturer,
                "parent": None,
                "players": None
            }
    return roms

def main():
    # Load existing data
    print("Loading existing mame_rom_data.json...")
    with open(JSON_FILE, 'r') as f:
        existing_data = json.load(f)

    existing_roms = existing_data.get('roms', {})
    print(f"  Existing ROMs: {len(existing_roms)}")

    new_roms = {}
    new_from_sources = 0

    for source in SOURCES:
        print(f"\nProcessing source: {source['name']}")
        content = fetch_url(source['url'])
        if content:
            parsed = parse_markdown_table(content)
            print(f"  Parsed {len(parsed)} entries from {source['name']}")

            for name, entry in parsed.items():
                if name not in existing_roms:
                    new_roms[name] = entry
                    new_from_sources += 1

    print(f"\n{'='*60}")
    print(f"New ROMs to add: {new_from_sources}")
    print(f"Existing ROMs: {len(existing_roms)}")

    if new_from_sources > 0:
        # Merge
        merged_roms = {**existing_roms, **new_roms}
        existing_data['roms'] = merged_roms

        # Update metadata
        existing_data['metadata']['generatedAt'] = datetime.now().isoformat()
        existing_data['metadata']['totalEntries'] = len(merged_roms)
        existing_data['metadata']['source'] += " + mame-roms1.md + mame-roms2.md"

        # Save
        print(f"\nSaving merged data ({len(merged_roms)} total entries)...")
        with open(JSON_FILE, 'w') as f:
            json.dump(existing_data, f, indent=2, ensure_ascii=False)

        print(f"Done! Added {new_from_sources} new ROMs.")
    else:
        print("No new ROMs to add.")

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
Download all DAT/RDB files from libretro-database and produce a seed SQLite database
that can be shipped with TruchieEmu for first-run game identification.

Usage:
    python3 download_all_dats.py [--output output.sqlite] [--dats-dir ./dats]

This script:
1. Downloads all No-Intro .dat and libretro .rdb files
2. Parses each one for CRC entries
3. Inserts all entries into a SQLite database
4. The resulting DB can be bundled as game_database_seed.sqlite
"""

import argparse
import hashlib
import os
import re
import sqlite3
import sys
import zlib
from pathlib import Path

try:
    import urllib.request
except ImportError:
    print("Error: urllib.request not available", file=sys.stderr)
    sys.exit(1)

# Base URL for libretro-database
BASE_URL = "https://raw.githubusercontent.com/libretro/libretro-database/master/"

# Known system IDs and their DAT/RDB file mappings
# These match LibretroDatabaseLibrary.libretroDatBasenameOverrides in the Swift code
DAT_MAPPINGS = {
    # Nintendo (No-Intro)
    "nes": ("metadat/no-intro", "Nintendo - Nintendo Entertainment System.dat"),
    "snes": ("metadat/no-intro", "Nintendo - Super Nintendo Entertainment System.dat"),
    "n64": ("metadat/no-intro", "Nintendo - Nintendo 64.dat"),
    "nds": ("metadat/no-intro", "Nintendo - Nintendo DS.dat"),
    "gb": ("metadat/no-intro", "Nintendo - Game Boy.dat"),
    "gbc": ("metadat/no-intro", "Nintendo - Game Boy Color.dat"),
    "gba": ("metadat/no-intro", "Nintendo - Game Boy Advance.dat"),
    "vb": ("metadat/no-intro", "Nintendo - Virtual Boy.dat"),
    "fds": ("metadat/no-intro", "Nintendo - Family Computer Disk System.dat"),
    # Sega (No-Intro)
    "genesis": ("metadat/no-intro", "Sega - Mega Drive - Genesis.dat"),
    "sms": ("metadat/no-intro", "Sega - Master System - Mark III.dat"),
    "gamegear": ("metadat/no-intro", "Sega - Game Gear.dat"),
    "32x": ("metadat/no-intro", "Sega - 32X.dat"),
    "sg1000": ("metadat/no-intro", "Sega - SG-1000.dat"),
    # Sony (Redump)
    "psx": ("metadat/redump", "Sony - PlayStation.dat"),
    # Atari (No-Intro)
    "atari2600": ("metadat/no-intro", "Atari - 2600.dat"),
    "atari7800": ("metadat/no-intro", "Atari - 7800.dat"),
    "jaguar": ("metadat/no-intro", "Atari - Jaguar.dat"),
    # NEC (No-Intro)
    "pce": ("metadat/no-intro", "NEC - PC Engine - TurboGrafx 16.dat"),
    # Bandai
    "wonderswan": ("metadat/no-intro", "Bandai - WonderSwan.dat"),
    "wswanc": ("metadat/no-intro", "Bandai - WonderSwan Color.dat"),
    # Other
    "lynx": ("metadat/no-intro", "Atari - Lynx.dat"),
    "ngp": ("metadat/no-intro", "SNK - Neo Geo Pocket.dat"),
    "ngc": ("metadat/no-intro", "SNK - Neo Geo Pocket Color.dat"),
}


def create_seed_database(db_path):
    """Create the SQLite seed database with the game_entries table."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS game_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            system_id TEXT NOT NULL,
            crc TEXT NOT NULL,
            title TEXT NOT NULL,
            stripped_title TEXT NOT NULL,
            year TEXT,
            developer TEXT,
            publisher TEXT,
            genre TEXT,
            thumbnail_system_id TEXT,
            UNIQUE(system_id, crc)
        );

        CREATE INDEX IF NOT EXISTS idx_game_crc ON game_entries(system_id, crc);
        CREATE INDEX IF NOT EXISTS idx_game_stripped_title ON game_entries(system_id, stripped_title);

        CREATE TABLE IF NOT EXISTS resource_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cache_key TEXT NOT NULL UNIQUE,
            resource_type TEXT NOT NULL,
            source_url TEXT NOT NULL,
            response_status INTEGER,
            content_type TEXT,
            file_size INTEGER,
            local_path TEXT,
            etag TEXT,
            last_modified TEXT,
            checksum TEXT,
            expires_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            access_count INTEGER NOT NULL DEFAULT 0,
            last_accessed INTEGER
        );

        CREATE TABLE IF NOT EXISTS dat_ingestion (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resource_cache_id INTEGER NOT NULL,
            system_id TEXT NOT NULL,
            source_name TEXT NOT NULL,
            entries_found INTEGER NOT NULL DEFAULT 0,
            entries_ingested INTEGER NOT NULL DEFAULT 0,
            ingestion_status TEXT NOT NULL DEFAULT 'pending',
            error_message TEXT,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            ingested_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            FOREIGN KEY (resource_cache_id) REFERENCES resource_cache(id)
        );

        CREATE TABLE IF NOT EXISTS box_art_resolutions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rom_path_key TEXT NOT NULL,
            system_id TEXT NOT NULL,
            game_title TEXT,
            resolved_url TEXT NOT NULL,
            source TEXT NOT NULL,
            http_status INTEGER NOT NULL,
            is_valid INTEGER NOT NULL DEFAULT 0,
            resolved_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            UNIQUE(rom_path_key, source)
        );

        CREATE INDEX IF NOT EXISTS idx_resource_cache_key ON resource_cache(cache_key);
        CREATE INDEX IF NOT EXISTS idx_resource_cache_type ON resource_cache(resource_type);
        CREATE INDEX IF NOT EXISTS idx_dat_ingestion_system ON dat_ingestion(system_id);
        CREATE INDEX IF NOT EXISTS idx_box_art_rom_key ON box_art_resolutions(rom_path_key);
    """)

    conn.commit()
    return conn


def strip_parentheses(s):
    """Strip parenthetical content from a title (matching Swift implementation)."""
    result = s
    # Strip (...) patterns
    result = re.sub(r'\s*\([^)]*\)\s*', ' ', result)
    # Strip [...] patterns
    result = re.sub(r'\s*\[[^\]]*\]\s*', ' ', result)
    # Clean up whitespace
    result = ' '.join(result.split()).lower().strip()
    return result


def compute_crc32(data):
    """Compute CRC32 of data as uppercase hex string."""
    return format(zlib.crc32(data) & 0xFFFFFFFF, '08X')


def parse_dat_contents(url, dat_path, system_id):
    """Parse a ClrMamePro .dat file and return entries."""
    entries = []
    current_game = None
    in_game = False

    try:
        with open(dat_path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()

                if line.startswith('game (') or line.startswith('machine ('):
                    current_game = {
                        'name': '',
                        'description': '',
                        'year': None,
                        'developer': None,
                        'publisher': None,
                        'genre': None,
                        'crcs': [],
                    }
                    in_game = True
                elif line == ')' and current_game:
                    # Determine title - prefer description if short, otherwise name
                    name = current_game['description'] if current_game['description'] and len(current_game['description']) < 150 else current_game['name']
                    stripped = strip_parentheses(name)

                    for crc in current_game['crcs']:
                        entries.append({
                            'system_id': system_id,
                            'crc': crc.upper(),
                            'title': name,
                            'stripped_title': stripped,
                            'year': current_game.get('year'),
                            'developer': current_game.get('developer'),
                            'publisher': current_game.get('publisher') or current_game.get('developer'),
                            'genre': current_game.get('genre'),
                            'thumbnail_system_id': None,
                        })
                    current_game = None
                    in_game = False
                elif in_game and current_game:
                    if line.startswith('name '):
                        current_game['name'] = extract_quotes(line) or ''
                    elif line.startswith('description '):
                        current_game['description'] = extract_quotes(line) or ''
                    elif line.startswith('year '):
                        current_game['year'] = extract_quotes(line)
                    elif line.startswith('developer '):
                        current_game['developer'] = extract_quotes(line)
                    elif line.startswith('publisher '):
                        current_game['publisher'] = extract_quotes(line)
                    elif line.startswith('genre ') or line.startswith('category '):
                        current_game['genre'] = extract_quotes(line)
                    elif line.startswith('rom (') or line.startswith('disk ('):
                        crc_match = re.search(r'crc\s+"?([0-9a-fA-F]+)"?', line)
                        if crc_match:
                            current_game['crcs'].append(crc_match.group(1).upper())

    except Exception as e:
        print(f"  Warning: Error parsing {dat_path}: {e}")

    return entries


def extract_quotes(line):
    """Extract quoted string from a line like: name "value"."""
    match = re.search(r'"([^"]*)"', line)
    if match:
        return match.group(1)
    # Try single quotes
    match = re.search(r"'([^']*)'", line)
    return match.group(1) if match else None


def download_file(url, dest):
    """Download a file from URL to dest."""
    try:
        print(f"  Downloading: {url}")
        req = urllib.request.Request(url, headers={'User-Agent': 'TruchieEmu/1.0 (Seed Script)'})
        with urllib.request.urlopen(req, timeout=60) as response:
            data = response.read()

        if len(data) < 100:
            print(f"  Response too small ({len(data)} bytes), skipping")
            return False

        # Check if it's a valid DAT (contains game or machine blocks)
        try:
            text = data.decode('utf-8', errors='replace')
            if 'game (' not in text and 'machine (' not in text:
                print(f"  Not a valid DAT (no game/machine blocks)")
                return False
        except Exception:
            return False

        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, 'wb') as f:
            f.write(data)

        print(f"  Saved: {dest} ({len(data)} bytes)")
        return True
    except Exception as e:
        print(f"  Download failed: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Download DAT files and create seed SQLite database')
    parser.add_argument('--output', default='game_database_seed.sqlite', help='Output SQLite file path')
    parser.add_argument('--dats-dir', default='./downloaded_dats', help='Directory to store downloaded DATs')
    parser.add_argument('--systems', nargs='*', help='Specific system IDs to download (default: all)')
    args = parser.parse_args()

    dats_dir = Path(args.dats_dir)
    dats_dir.mkdir(parents=True, exist_ok=True)

    print(f"Creating seed database: {args.output}")
    conn = create_seed_database(args.output)
    cursor = conn.cursor()

    systems_to_process = args.systems if args.systems else list(DAT_MAPPINGS.keys())
    total_entries = 0

    for system_id in systems_to_process:
        if system_id not in DAT_MAPPINGS:
            print(f"\nUnknown system: {system_id}")
            continue

        dat_dir, filename = DAT_MAPPINGS[system_id]
        file_url = BASE_URL + dat_dir + "/" + filename.replace(' ', '%20')  # Use actual file path with spaces
        local_path = dats_dir / filename

        print(f"\n{'=' * 60}")
        print(f"Processing: {system_id} ({filename})")
        print(f"{'=' * 60}")

        # Download if not exists
        if not local_path.exists():
            if not download_file(file_url, str(local_path)):
                print(f"  Skipping {system_id} - download failed")
                continue
        else:
            print(f"  Using cached: {local_path}")

        # Parse DAT
        entries = parse_dat_contents(file_url, str(local_path), system_id)

        if not entries:
            print(f"  No entries parsed from {system_id}")
            continue

        # Insert into database
        print(f"  Inserting {len(entries)} entries into database...")
        inserted = 0
        for entry in entries:
            try:
                cursor.execute("""
                    INSERT OR REPLACE INTO game_entries
                    (system_id, crc, title, stripped_title, year, developer, publisher, genre, thumbnail_system_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    entry['system_id'],
                    entry['crc'],
                    entry['title'],
                    entry['stripped_title'],
                    entry.get('year'),
                    entry.get('developer'),
                    entry.get('publisher'),
                    entry.get('genre'),
                    entry.get('thumbnail_system_id'),
                ))
                inserted += 1
            except sqlite3.Error as e:
                print(f"  Insert error for {entry['crc']}: {e}")

        conn.commit()
        total_entries += inserted
        print(f"  Inserted {inserted} entries for {system_id}")

    # Record ingestion status for all processed systems
    now = int(__import__('time').time())
    for system_id in systems_to_process:
        if system_id not in DAT_MAPPINGS:
            continue
        _, filename = DAT_MAPPINGS[system_id]
        cursor.execute("SELECT COUNT(*) FROM game_entries WHERE system_id = ?", (system_id,))
        count = cursor.fetchone()[0]
        if count > 0:
            cache_key = f"dat_{system_id}_no-intro"
            # Record resource cache entry
            cursor.execute("""
                INSERT OR REPLACE INTO resource_cache
                (cache_key, resource_type, source_url, response_status, created_at, updated_at, access_count)
                VALUES (?, 'dat', ?, 200, ?, ?, 1)
            """, (cache_key, f"{BASE_URL}metadat/no-intro/{filename}", now, now))

            cursor.execute("SELECT last_insert_rowid()")
            cache_id = cursor.fetchone()[0]

            # Record ingestion
            cursor.execute("""
                INSERT INTO dat_ingestion
                (resource_cache_id, system_id, source_name, entries_found, entries_ingested,
                 ingestion_status, duration_ms, ingested_at)
                VALUES (?, ?, 'no-intro', ?, ?, 'success', 0, ?)
            """, (cache_id, system_id, count, count, now))

    conn.commit()

    # Summary
    print(f"\n{'=' * 60}")
    print(f"SEED DATABASE CREATED: {args.output}")
    print(f"Total game entries: {total_entries}")
    print(f"Systems processed: {len(systems_to_process)}")
    print(f"{'=' * 60}")

    conn.close()


if __name__ == '__main__':
    main()
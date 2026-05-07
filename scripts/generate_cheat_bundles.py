#!/usr/bin/env python3
"""
Generate system-specific cheat bundles from libretro-database.

This script:
1. Downloads the libretro-database repo as a zip
2. Extracts only the cht/ folder
3. Creates system-specific zip bundles (nes-cheats.zip, snes-cheats.zip, etc.)
4. Places them in TruchiEmu/Resources/cheats/

Run this once to generate the initial bundles, then host them as part of TruchiEmu.
"""

import os
import sys
import shutil
import zipfile
import urllib.request
import tempfile
from pathlib import Path

REPO_URL = "https://github.com/libretro/libretro-database/archive/refs/heads/master.zip"
CHEATS_DIR = "libretro-database-master/cht"
OUTPUT_DIR = Path("TruchiEmu/Resources/cheats")
SYSTEM_FOLDER_MAPPING = {
    "nes": "Nintendo - Nintendo Entertainment System",
    "fds": "Nintendo - Family Computer Disk System",
    "snes": "Nintendo - Super Nintendo Entertainment System",
    "satellaview": "Nintendo - Satellaview",
    "n64": "Nintendo - Nintendo 64",
    "n64_unreleased": "Nintendo - Nintendo 64 (Unreleased)",
    "n64_ique": "Nintendo - Nintendo 64 (iQue)",
    "n64_aleck": "Nintendo - Nintendo 64 (Aleck64)",
    "nds": "Nintendo - Nintendo DS",
    "gb": "Nintendo - Game Boy",
    "gba": "Nintendo - Game Boy Advance",
    "gbc": "Nintendo - Game Boy Color",
    "genesis": "Sega - Mega Drive - Genesis",
    "megadrive": "Sega - Mega Drive - Genesis",
    "32x": "Sega - 32X",
    "sms": "Sega - Master System - Mark III",
    "gg": "Sega - Game Gear",
    "saturn": "Sega - Saturn",
    "segacd": "Sega - Mega-CD - Sega CD",
    "dreamcast": "Sega - Dreamcast",
    "psx": "Sony - PlayStation",
    "psp": "Sony - PlayStation Portable",
    "fbneo": "FBNeo - Arcade Games",
    "arcade": "FBNeo - Arcade Games",
    "dos": "DOS",
    "atari2600": "Atari - 2600",
    "atari5200": "Atari - 5200",
    "atari7800": "Atari - 7800",
    "atari800": "Atari - 8-bit Family",
    "jaguar": "Atari - Jaguar",
    "atarilynx": "Atari - Lynx",
    "colecovision": "Coleco - ColecoVision",
    "intellivision": "Mattel - Intellivision",
    "msx": "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R",
    "msx_fmsx": "Microsoft - MSX - MSX2 - MSX2P - MSX Turbo R (fMSX core)",
    "turbografx16": "NEC - PC Engine - TurboGrafx 16",
    "turbografxcd": "NEC - PC Engine CD - TurboGrafx-CD",
    "supergrafx": "NEC - PC Engine SuperGrafx",
    "amstrad": "Amstrad - GX4000",
    "spectrum": "Sinclair - ZX Spectrum +3",
    "tic80": "TIC-80",
    "thomson": "Thomson - MOTO",
    "puzzlescript": "PuzzleScript",
    "prboom": "PrBoom",
    "chailove": "ChaiLove",
}

def download_and_extract(url: str, temp_dir: Path) -> Path:
    """Download zip and extract to temp directory."""
    print(f"Downloading {url}...")
    
    zip_path = temp_dir / "repo.zip"
    
    # Download with redirect following
    request = urllib.request.Request(url, headers={'User-Agent': 'TruchiEmu'})
    with urllib.request.urlopen(request) as response:
        with open(zip_path, 'wb') as f:
            shutil.copyfileobj(response, f)
    
    print(f"Extracting {zip_path}...")
    
    # Extract only the cht directory
    with zipfile.ZipFile(zip_path, 'r') as zf:
        for name in zf.namelist():
            if name.startswith(CHEATS_DIR + "/"):
                zf.extract(name, temp_dir)
    
    cht_path = temp_dir / CHEATS_DIR
    if not cht_path.exists():
        raise FileNotFoundError(f"Expected cht directory not found: {cht_path}")
    
    return cht_path


def create_system_zip(cht_base: Path, system_folder: str, system_key: str, output_dir: Path):
    """Create a zip file for a specific system."""
    system_path = cht_base / system_folder
    
    if not system_path.exists():
        print(f"  System folder not found: {system_folder}")
        return 0
    
    # Get all .cht files in the system folder (including subdirs)
    cht_files = list(system_path.rglob("*.cht"))
    file_count = len(cht_files)
    
    if file_count == 0:
        print(f"  No cheat files found in {system_folder}")
        return 0
    
    print(f"  Found {file_count} cheat files for {system_key}")
    
    # Create zip
    output_file = output_dir / f"{system_key}-cheats.zip"
    
    with zipfile.ZipFile(output_file, 'w', zipfile.ZIP_DEFLATED) as zf:
        for cht_file in cht_files:
            # Store relative to system folder, preserving folder structure
            arcname = cht_file.relative_to(system_path)
            zf.write(cht_file, arcname)
    
    # Get zip size
    size_mb = output_file.stat().st_size / (1024 * 1024)
    print(f"  Created {output_file.name}: {file_count} files, {size_mb:.2f} MB")
    
    return file_count


def main():
    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # Download and extract
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        cht_path = download_and_extract(REPO_URL, temp_path)
        
        # List all folders in cht/
        print(f"\nAvailable systems in cht/:")
        for folder in sorted(cht_path.iterdir()):
            if folder.is_dir():
                count = len(list(folder.glob("*.cht")))
                print(f"  {folder.name}: {count} files")
        
        print(f"\nGenerating system bundles...")
        
        total_files = 0
        for system_key, system_folder in SYSTEM_FOLDER_MAPPING.items():
            count = create_system_zip(cht_path, system_folder, system_key, OUTPUT_DIR)
            total_files += count
        
        print(f"\nDone! Created bundles with {total_files} total cheat files.")
        print(f"Output directory: {OUTPUT_DIR}")
        
        # List created files
        print(f"\nCreated zip files:")
        for f in sorted(OUTPUT_DIR.iterdir()):
            if f.suffix == ".zip":
                size_mb = f.stat().st_size / (1024 * 1024)
                print(f"  {f.name}: {size_mb:.2f} MB")


if __name__ == "__main__":
    main()
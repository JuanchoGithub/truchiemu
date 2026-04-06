#!/usr/bin/env python3
"""
MAME ROM Coverage Analyzer

Scans a MAME ROM folder, matches each ZIP against the downloaded
MAME database, and produces a detailed coverage report.
"""

import json
import os
import sys
import glob
from datetime import datetime
from collections import defaultdict

# Default paths
DEFAULT_ROM_PATH = "/Users/jayjay/Downloads/roms/mame"
DATABASE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mame_rom_data.json")


def load_database() -> dict:
    """Load the MAME ROM database JSON."""
    if not os.path.exists(DATABASE_PATH):
        print(f"ERROR: Database file not found: {DATABASE_PATH}")
        print("Run download_and_parse.py first!")
        sys.exit(1)
    
    with open(DATABASE_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    return data.get("roms", {})


def scan_rom_folder(rom_path: str) -> list:
    """Scan a folder for .zip files and return list of ROM names (without extension)."""
    if not os.path.exists(rom_path):
        print(f"ERROR: ROM folder not found: {rom_path}")
        sys.exit(1)
    
    # Find all .zip files (including subdirectories if needed)
    zip_files = glob.glob(os.path.join(rom_path, "*.zip"))
    
    # Also check subdirectories recursively
    for root, dirs, files in os.walk(rom_path):
        for file in files:
            if file.lower().endswith('.zip'):
                full_path = os.path.join(root, file)
                # Only add if not already found at top level
                if full_path not in zip_files:
                    zip_files.append(full_path)
    
    # Extract just the filename without extension
    rom_names = []
    for zip_path in zip_files:
        rom_name = os.path.splitext(os.path.basename(zip_path))[0]
        rom_names.append({
            "name": rom_name,
            "filename": os.path.basename(zip_path),
            "full_path": zip_path
        })
    
    return rom_names


def analyze_coverage(rom_list: list, database: dict) -> dict:
    """Match ROMs against database and compute stats."""
    results = {
        "total": len(rom_list),
        "identified": 0,
        "not_identified": 0,
        "by_type": defaultdict(int),
        "identified_roms": [],
        "unidentified_roms": [],
        "bios_count": 0,
        "game_count": 0,
        "device_count": 0,
        "mechanical_count": 0,
        "other_count": 0
    }
    
    for rom in rom_list:
        rom_name = rom["name"]
        entry = database.get(rom_name)
        
        if entry:
            results["identified"] += 1
            rom_type = entry.get("type", "unknown")
            results["by_type"][rom_type] += 1
            
            if rom_type == "bios":
                results["bios_count"] += 1
            elif rom_type == "game":
                results["game_count"] += 1
            elif rom_type == "device":
                results["device_count"] += 1
            elif rom_type == "mechanical":
                results["mechanical_count"] += 1
            else:
                results["other_count"] += 1
            
            results["identified_roms"].append({
                "name": rom_name,
                "description": entry.get("description", ""),
                "type": rom_type,
                "isRunnable": entry.get("isRunnable", True),
                "year": entry.get("year"),
                "manufacturer": entry.get("manufacturer")
            })
        else:
            results["not_identified"] += 1
            results["unidentified_roms"].append({
                "name": rom_name,
                "filename": rom["filename"],
                "path": rom["full_path"]
            })
    
    return results


def print_report(results: dict, rom_path: str, db_metadata: dict):
    """Print a detailed coverage report."""
    total = results["total"]
    identified = results["identified"]
    not_identified = results["not_identified"]
    
    identified_pct = (identified / total * 100) if total > 0 else 0
    not_identified_pct = (not_identified / total * 100) if total > 0 else 0
    
    print()
    print("=" * 70)
    print("  MAME ROM COVERAGE REPORT")
    print("=" * 70)
    print(f"  ROM Folder: {rom_path}")
    print(f"  Database: {db_metadata.get('source', 'Unknown')}")
    print(f"  Generated: {db_metadata.get('generatedAt', 'Unknown')}")
    print(f"  Report Date: {datetime.now().isoformat()}")
    print("=" * 70)
    print()
    
    print("  SUMMARY")
    print("  " + "-" * 50)
    print(f"  Total ZIP files found:       {total:>6,}")
    print(f"  Identified in MAME data:     {identified:>6,}  ({identified_pct:.1f}%)")
    print(f"  NOT identified:              {not_identified:>6,}  ({not_identified_pct:.1f}%)")
    print()
    
    print("  IDENTIFIED ROM TYPES")
    print("  " + "-" * 50)
    print(f"  Games:                       {results['game_count']:>6,}  ({results['game_count']/total*100:.1f}%)")
    print(f"  BIOS:                        {results['bios_count']:>6,}  ({results['bios_count']/total*100:.1f}%)")
    print(f"  Devices:                     {results['device_count']:>6,}  ({results['device_count']/total*100:.1f}%)")
    print(f"  Mechanical:                  {results['mechanical_count']:>6,}  ({results['mechanical_count']/total*100:.1f}%)")
    print(f"  Other/Unknown type:          {results['other_count']:>6,}  ({results['other_count']/total*100:.1f}%)")
    print()
    
    # Coverage assessment
    print("  COVERAGE ASSESSMENT")
    print("  " + "-" * 50)
    if identified_pct >= 95:
        status = "EXCELLENT - Coverage target met!"
    elif identified_pct >= 90:
        status = "GOOD - Near target coverage"
    elif identified_pct >= 80:
        status = "FAIR - Some gaps remain"
    else:
        status = "POOR - Significant gaps"
    print(f"  Status: {status}")
    print(f"  Coverage: {identified_pct:.1f}% (target: 90%+)")
    print()
    
    # Unidentified ROMs
    if results["unidentified_roms"]:
        print("  UNIDENTIFIED ROMS (Top 50)")
        print("  " + "-" * 50)
        for i, rom in enumerate(results["unidentified_roms"][:50]):
            print(f"    {i+1:>3}. {rom['name']}")
        if len(results["unidentified_roms"]) > 50:
            print(f"    ... and {len(results['unidentified_roms']) - 50} more")
        print()
    
    # Sample of identified ROMs
    if results["identified_roms"]:
        print("  SAMPLE: IDENTIFIED ROMS (first 20)")
        print("  " + "-" * 50)
        for rom in results["identified_roms"][:20]:
            type_icon = {"game": "🎮", "bios": "📟", "device": "🔌", "mechanical": "⚙️"}.get(rom["type"], "?")
            year = rom.get("year", "")
            mfr = rom.get("manufacturer", "")
            extra = f" ({year}, {mfr})" if year or mfr else ""
            runnable_icon = "✓" if rom.get("isRunnable") else "✗"
            print(f"    {type_icon} {rom['name']}: {rom['description']}{extra} [{runnable_icon}]")
        print()
    
    print("=" * 70)
    print("  END OF REPORT")
    print("=" * 70)


def save_report(results: dict, rom_path: str, db_metadata: dict):
    """Save the report to a JSON file."""
    report_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "coverage_report.json")
    
    report = {
        "reportDate": datetime.now().isoformat(),
        "romPath": rom_path,
        "databaseSource": db_metadata.get("source", "Unknown"),
        "databaseGenerated": db_metadata.get("generatedAt", "Unknown"),
        "summary": {
            "total": results["total"],
            "identified": results["identified"],
            "notIdentified": results["not_identified"],
            "identifiedPercentage": round(results["identified"] / results["total"] * 100, 1) if results["total"] > 0 else 0,
            "coverageStatus": "EXCELLENT" if results["identified"] / results["total"] * 100 >= 95 else \
                              "GOOD" if results["identified"] / results["total"] * 100 >= 90 else \
                              "FAIR" if results["identified"] / results["total"] * 100 >= 80 else "POOR"
        },
        "byType": {
            "games": results["game_count"],
            "bios": results["bios_count"],
            "devices": results["device_count"],
            "mechanical": results["mechanical_count"],
            "other": results["other_count"]
        },
        "unidentifiedRoms": results["unidentified_roms"],
        "identifiedSamples": results["identified_roms"][:50]  # First 50 as sample
    }
    
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    
    print(f"\n  Report saved to: {report_path}")


def main():
    # Parse command line arguments
    rom_path = DEFAULT_ROM_PATH
    if len(sys.argv) > 1:
        rom_path = sys.argv[1]
    
    print("  MAME ROM Coverage Analyzer")
    print("  " + "-" * 40)
    print(f"  ROM Path: {rom_path}")
    print(f"  Database: {DATABASE_PATH}")
    print()
    
    # Step 1: Load database
    print("[1/4] Loading MAME database...")
    database = load_database()
    print(f"  Loaded {len(database):,} ROM entries")
    
    # Step 2: Scan ROM folder
    print("[2/4] Scanning ROM folder...")
    rom_list = scan_rom_folder(rom_path)
    print(f"  Found {len(rom_list):,} ZIP files")
    
    # Step 3: Analyze coverage
    print("[3/4] Analyzing coverage...")
    results = analyze_coverage(rom_list, database)
    
    # Load metadata for report
    with open(DATABASE_PATH, 'r', encoding='utf-8') as f:
        full_data = json.load(f)
    
    # Step 4: Print report
    print("[4/4] Generating report...")
    print_report(results, rom_path, full_data.get("metadata", {}))
    
    # Save report
    save_report(results, rom_path, full_data.get("metadata", {}))
    
    # Exit with code based on coverage
    if results["total"] > 0:
        coverage = results["identified"] / results["total"] * 100
        if coverage < 90:
            sys.exit(2)  # Below target


if __name__ == '__main__':
    main()
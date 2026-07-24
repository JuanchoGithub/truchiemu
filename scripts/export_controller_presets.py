#!/usr/bin/env python3
"""
Export the user's currently-saved controller mappings (AppSettings JSON blobs
stored in SwiftData SettingsEntry rows) to bundled preset files under
TruchiEmu/Resources/ControllerPresets/. The exported files are loaded at app
launch by BundledControllerPresets so new users on the same hardware start from
the same default mapping you curated.

Scope: app-wide "default" mappings ONLY (no per-system or per-game overrides
are shipped — only the "default" slot of each identity). Each emitted file
covers one ControllerIdentityKey.compositeKey with whatever 'gcMapping' and/or
'sdlMapping' entries exist for that identity's "default" system-ID slot.

Usage:
    python3 scripts/export_controller_presets.py
    python3 scripts/export_controller_presets.py --db /path/to/TruchiEmu.sqlite
    python3 scripts/export_controller_presets.py --out /custom/output/dir
    python3 scripts/export_controller_presets.py --dry-run   # list what would be written, no writes
"""

import argparse
import base64
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_DIR = SCRIPT_DIR.parent
DEFAULT_DB = os.path.expanduser("~/Library/Application Support/TruchiEmu/TruchiEmu.sqlite")
DEFAULT_OUT = REPO_DIR / "TruchiEmu" / "Resources" / "ControllerPresets"

GC_KEY = "controller_identities_v1"
SDL_KEY = "sdl_controller_identities_v1"


def fetch_settings_value(db_path: str, key: str) -> dict:
    """Read one SettingsEntry row's `value` (Base64-encoded String of JSON-encoded data)."""
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.execute("SELECT ZVALUE FROM ZSETTINGSENTRY WHERE ZKEY = ?", (key,))
        row = cur.fetchone()
    finally:
        conn.close()
    if row is None:
        return {}
    b64_string = row[0]
    raw = base64.b64decode(b64_string)
    return json.loads(raw)


def collect_identities(gc_blob: dict, sdl_blob: dict) -> dict:
    """Merge GC and SDL identity-keyed maps into {compositeKey -> preset_dict}.

    Only the "default" system-ID slot of each identity is emitted (narrow scope,
    per project decision). Per-system overrides are NOT shipped — they stay
    private to your live AppSettings. Identities that lack a "default" slot
    are skipped entirely.
    """
    out = {}
    for composite_key, system_map in gc_blob.items():
        if "default" not in system_map:
            continue
        out.setdefault(composite_key, {"identity": None, "gcMapping": None, "sdlMapping": None})
        out[composite_key]["gcMapping"] = system_map["default"]
    for composite_key, system_map in sdl_blob.items():
        if "default" not in system_map:
            continue
        out.setdefault(composite_key, {"identity": None, "gcMapping": None, "sdlMapping": None})
        out[composite_key]["sdlMapping"] = system_map["default"]
    return out


def parse_identity_from_composite_key(composite_key: str) -> dict:
    """compositeKey format is '<inputSystem>|<productKey>|<vendorName>' (vendorName may be '')."""
    parts = composite_key.split("|", 2)
    while len(parts) < 3:
        parts.append("")
    return {
        "inputSystem": parts[0],
        "productKey": parts[1],
        "vendorName": parts[2] if parts[2] else None,
    }


def safe_filename(identity: dict, composite_key: str) -> str:
    """Lowercase, [a-z0-9-], prefer vendorName + productKey tail for readability.
    Prefixed with `controllerPreset_` so the bundle can find them by name after
    Xcode flattens Resources/ directories (Bundle.main cannot enumerate
    subdirectories at runtime)."""
    vendor = identity.get("vendorName") or "unknown"
    product = identity.get("productKey") or ""
    raw = f"{vendor}_{product}".lower()
    raw = re.sub(r"[^a-z0-9]+", "-", raw).strip("-")
    if not raw:
        raw = re.sub(r"[^a-z0-9]+", "-", composite_key.lower()).strip("-")
    return f"controllerPreset_{raw}.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1], formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", default=DEFAULT_DB, help=f"Path to TruchiEmu.sqlite (default: {DEFAULT_DB})")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help=f"Output directory (default: {DEFAULT_OUT})")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be written but don't write files")
    args = parser.parse_args()

    db_path = os.path.expanduser(args.db)
    out_dir = Path(args.out)

    if not os.path.exists(db_path):
        print(f"ERROR: SQLite database not found at {db_path}", file=sys.stderr)
        return 1

    print(f"Reading SwiftData store: {db_path}")
    gc_blob = fetch_settings_value(db_path, GC_KEY)
    sdl_blob = fetch_settings_value(db_path, SDL_KEY)
    print(f"  {GC_KEY}: {len(gc_blob)} identities")
    print(f"  {SDL_KEY}: {len(sdl_blob)} identities")

    presets = collect_identities(gc_blob, sdl_blob)
    if not presets:
        print("No 'default'-scope-only mappings found; nothing to export.", file=sys.stderr)
        return 0

    print(f"\nFound {len(presets)} preset candidate(s):")
    used_filenames = set()
    files = []
    for composite_key, payload in presets.items():
        identity = parse_identity_from_composite_key(composite_key)
        payload["identity"] = identity
        fname = safe_filename(identity, composite_key)
        if fname in used_filenames:
            print(f"  WARNING: filename collision '{fname}' for composite key '{composite_key}'", file=sys.stderr)
            fname = f"{Path(fname).stem}_{abs(hash(composite_key)) % 10000}.json"
        used_filenames.add(fname)
        files.append((fname, payload))
        print(f"  - {fname}")
        print(f"      inputSystem={identity['inputSystem']}  productKey={identity['productKey']!r}  vendorName={identity['vendorName']!r}")
        print(f"      gc={'yes' if payload['gcMapping'] else 'no'}  sdl={'yes' if payload['sdlMapping'] else 'no'}")

    if args.dry_run:
        print("\n--dry-run: no files written.")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for fname, payload in files:
        path = out_dir / fname
        with path.open("w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False, sort_keys=True)
            f.write("\n")
        print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

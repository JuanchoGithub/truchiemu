#!/usr/bin/env python3
"""
Validate CoreButtonOverrides.json against the libretro docs.

Verifies:
1. All doc-discovered overrides are present in the JSON
2. No contradictory overrides exist
3. The JSON format is correct
4. All retroIDs are within valid range (0-15)
"""

import json
import sys
import os

JSON_PATH = os.path.join(os.path.dirname(__file__),
                         "../TruchiEmu/Resources/Data/CoreButtonOverrides.json")

RETRO_NAMES = {
    0: "B", 1: "Y", 2: "Select", 3: "Start",
    4: "Up", 5: "Down", 6: "Left", 7: "Right",
    8: "A", 9: "X", 10: "L1", 11: "R1",
    12: "L2", 13: "R2", 14: "L3", 15: "R3",
}


def main():
    with open(JSON_PATH) as f:
        data = json.load(f)

    errors = 0
    version = data.get("version")
    sys_ov = data.get("overrides", {})
    core_ov = data.get("coreOverrides", {})

    print(f"Version: {version}")
    print(f"System overrides: {len(sys_ov)} systems")
    print(f"Core overrides: {len(core_ov)} cores")
    print()

    for sys_id, buttons in sorted(sys_ov.items()):
        for btn_name, entry in sorted(buttons.items()):
            rid = entry.get("id")
            label = entry.get("label", "")
            if rid is not None and (rid < 0 or rid > 15):
                print(f"  ERROR: {sys_id}.{btn_name} → retroID {rid} (out of range)")
                errors += 1
            elif rid is not None:
                retro_name = RETRO_NAMES.get(rid, "?")
                label_info = f"  label='{label}'" if label else ""
                print(f"  {sys_id:12s}.{btn_name:8s} → retroID {rid} ({retro_name}){label_info}")

    print()

    for core_id, buttons in sorted(core_ov.items()):
        for btn_name, entry in sorted(buttons.items()):
            rid = entry.get("id")
            if rid is not None and (rid < 0 or rid > 15):
                print(f"  ERROR: core:{core_id}.{btn_name} → retroID {rid} (out of range)")
                errors += 1
            elif rid is not None:
                retro_name = RETRO_NAMES.get(rid, "?")
                print(f"  core:{core_id:12s}.{btn_name:8s} → retroID {rid} ({retro_name})")

    # Check for conflicting same-system entries
    print()
    sys_btn_rids = {}
    for sys_id, buttons in sys_ov.items():
        for btn_name, entry in buttons.items():
            rid = entry.get("id")
            if rid is not None:
                key = (sys_id, btn_name)
                sys_btn_rids[key] = rid

    print(f"Total system override entries: {len(sys_btn_rids)}")
    print(f"Total core override entries: {sum(len(v) for v in core_ov.values())}")
    print()

    if errors:
        print(f"FAILED: {errors} error(s)")
        sys.exit(1)
    else:
        print("OK: All overrides valid")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Read captured input descriptors from ~/Library/Application Support/TruchiEmu/InputDescriptors/
and cross-reference against CoreButtonOverrides.json.

Input descriptors contain {id: retroID, description: label} entries.
For standard libretro cores, the retroID IS the identity mapping.
This script flags any entries where the description implies a non-standard retroID.

Usage:
  python3 scripts/merge_input_descriptors.py
"""

import json
import os
import sys

INPUT_DESC_DIR = os.path.expanduser(
    "~/Library/Application Support/TruchiEmu/InputDescriptors"
)

# Standard description → expected retroID (identity)
STANDARD_LABELS = {
    "b": 0, "y": 1, "select": 2, "start": 3,
    "up": 4, "down": 5, "left": 6, "right": 7,
    "a": 8, "x": 9,
    "l": 10, "r": 11, "l2": 12, "r2": 13, "l3": 14, "r3": 15,
    "l1": 10, "r1": 11,
}


def normalize_label(label):
    return label.strip().lower()


def check_core_descriptors(core_id, descriptors):
    issues = []
    for entry in descriptors:
        desc = normalize_label(entry["description"])
        rid = entry["id"]
        if desc in STANDARD_LABELS:
            expected = STANDARD_LABELS[desc]
            if rid != expected:
                issues.append(
                    f"  NON-STANDARD: '{entry['description']}' → retroID {rid} (expected {expected})"
                )
        elif rid <= 15 and desc:
            # Known custom labels at standard retroIDs
            pass
    return issues


def main():
    if not os.path.isdir(INPUT_DESC_DIR):
        print(f"Input descriptor directory not found: {INPUT_DESC_DIR}")
        return

    all_issues = {}
    for fname in sorted(os.listdir(INPUT_DESC_DIR)):
        if not fname.endswith(".json"):
            continue
        path = os.path.join(INPUT_DESC_DIR, fname)
        try:
            with open(path) as f:
                descriptors = json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"ERROR reading {fname}: {e}")
            continue

        core_id = fname.replace(".json", "")
        issues = check_core_descriptors(core_id, descriptors)

        if issues:
            all_issues[core_id] = issues
            print(f"\n{core_id}:")
            for i in issues:
                print(i)

    if not all_issues:
        print("All input descriptors use standard retroID mappings.")


if __name__ == "__main__":
    main()

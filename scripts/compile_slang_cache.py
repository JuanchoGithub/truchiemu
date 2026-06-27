#!/usr/bin/env python3
"""
Pre-compile slang shaders to Metal for offline cache.

Scans Resources/slang-shaders/ for .slangp presets, compiles referenced
.slang files to MSL via glslangValidator + spirv-cross, then compiles
to .metallib via xcrun metal.

Output: TruchiEmu_Resources/compiled_slang/<preset_hash>.metallib
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

SLANG_DIR = Path("Resources/slang-shaders")
OUTPUT_DIR = Path("TruchiEmu_Resources/compiled_slang")
CACHE_INDEX = OUTPUT_DIR / "cache_index.json"

REQUIRED_TOOLS = ["glslangValidator", "spirv-cross", "xcrun"]

def check_tools():
    missing = []
    for tool in REQUIRED_TOOLS:
        if not subprocess.run(["which", tool], capture_output=True).returncode == 0:
            missing.append(tool)
    return missing

def find_slangp_files():
    return list(SLANG_DIR.rglob("*.slangp"))

def compute_hash(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:16]

def compile_slang_to_msl(slang_path, output_msl):
    # glslangValidator -> SPIR-V
    spv_path = slang_path.with_suffix(".spv")
    result = subprocess.run(
        ["glslangValidator", "-V", str(slang_path), "-o", str(spv_path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return False, f"glslangValidator failed: {result.stderr}"

    # spirv-cross -> MSL
    with open(output_msl, "w") as f:
        result = subprocess.run(
            ["spirv-cross", "--msl", str(spv_path)],
            capture_output=True, text=True, stdout=f
        )
    spv_path.unlink(missing_ok=True)
    if result.returncode != 0:
        return False, f"spirv-cross failed: {result.stderr}"
    return True, None

def compile_msl_to_metallib(msl_path, metallib_path):
    air_path = msl_path.with_suffix(".air")
    result = subprocess.run(
        ["xcrun", "metal", "-c", str(msl_path), "-o", str(air_path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return False, f"metal -c failed: {result.stderr}"

    result = subprocess.run(
        ["xcrun", "metallib", str(air_path), "-o", str(metallib_path)],
        capture_output=True, text=True
    )
    air_path.unlink(missing_ok=True)
    if result.returncode != 0:
        return False, f"metallib failed: {result.stderr}"
    return True, None

def main():
    missing = check_tools()
    if missing:
        print(f"Missing tools: {', '.join(missing)}")
        print("Install via: brew install glslang spirv-cross")
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    slangp_files = find_slangp_files()
    print(f"Found {len(slangp_files)} .slangp files")

    # Load existing cache index
    cache = {}
    if CACHE_INDEX.exists():
        cache = json.loads(CACHE_INDEX.read_text())

    new_cache = {}
    success = 0
    skipped = 0
    failed = 0

    for slangp in slangp_files:
        preset_hash = compute_hash(slangp)
        metallib_path = OUTPUT_DIR / f"{preset_hash}.metallib"

        # Check cache hit
        if metallib_path.exists() and cache.get(slangp.name) == preset_hash:
            new_cache[slangp.name] = preset_hash
            skipped += 1
            continue

        # Parse .slangp to find referenced .slang files
        slang_refs = []
        try:
            text = slangp.read_text()
            for line in text.splitlines():
                line = line.strip()
                if line.startswith("shader") or "=" in line:
                    parts = line.split("=", 1)
                    if len(parts) == 2:
                        val = parts[1].strip().strip('"')
                        if val.endswith(".slang"):
                            ref = (slangp.parent / val).resolve()
                            if ref.exists():
                                slang_refs.append(ref)
        except Exception as e:
            print(f"  Failed to parse {slangp.name}: {e}")
            failed += 1
            continue

        # Collect unique .slang files
        temp_msl_files = []
        ok = True
        for slang_path in set(slang_refs):
            msl_path = OUTPUT_DIR / f"{slang_path.stem}_{hashlib.sha256(str(slang_path).encode()).hexdigest()[:8]}.metal"
            compiled, err = compile_slang_to_msl(slang_path, msl_path)
            if not compiled:
                print(f"  Failed to compile {slang_path.name}: {err}")
                ok = False
                break
            temp_msl_files.append(msl_path)

        if not ok:
            for p in temp_msl_files:
                p.unlink(missing_ok=True)
            failed += 1
            continue

        # Combine MSL files into a single .metal and compile to .metallib
        combined_msl = OUTPUT_DIR / f"{preset_hash}.metal"
        with open(combined_msl, "w") as out:
            for msl_path in temp_msl_files:
                out.write(f"// {msl_path.name}\n")
                out.write(msl_path.read_text())
                out.write("\n")

        compiled, err = compile_msl_to_metallib(combined_msl, metallib_path)
        combined_msl.unlink(missing_ok=True)
        for p in temp_msl_files:
            p.unlink(missing_ok=True)

        if compiled:
            new_cache[slangp.name] = preset_hash
            success += 1
            print(f"  Compiled: {slangp.name}")
        else:
            print(f"  Failed: {slangp.name}: {err}")
            failed += 1

    CACHE_INDEX.write_text(json.dumps(new_cache, indent=2))
    print(f"\nDone: {success} compiled, {skipped} cached, {failed} failed")

if __name__ == "__main__":
    main()

#!/bin/bash
# Boot-smoke test driver for TruchiEmu.
#
# Runs the built app once per ROM in the manifest below with the env-gated
# BootSmokeRunner harness (TRUCHI_SMOKE_ROM / TRUCHI_SMOKE_CORE), and asserts
# that the libretro core produces its first frame ("First frame received") in
# TruchiEmu.log within a per-case timeout. Exercises the real launch pipeline:
# GameLauncher -> LaunchConfig -> runner -> XPC bridge -> core load.
#
# Usage:
#   scripts/smoke_test.sh [path/to/TruchiEmu.app]
#
# Exit code 0 = all cases passed, 1 = at least one failed.

set -u

APP="${1:-}"
if [ -z "$APP" ]; then
  APP="$HOME/Library/Developer/Xcode/DerivedData/TruchiEmu-gawyppvgjxbeaaebuslnlsaalnra/Build/Products/Debug/TruchiEmu.app"
fi
BIN="$APP/Contents/MacOS/TruchiEmu"
LOG="$HOME/Library/Application Support/TruchiEmu/Logs/TruchiEmu.log"
MARKER_REGEX="First frame received|RF decoder first frame"

if [ ! -x "$BIN" ]; then
  echo "App binary not found: $BIN" >&2
  exit 2
fi

# label|rom-path|core|timeout-seconds  (empty core => auto-resolve via ROMIdentifier + CoreManager)
CASES=(
  "nes|$HOME/Downloads/roms/nes/Plataformas/Donkey Kong.nes|fceumm_libretro|25"
  "gbc|$HOME/Downloads/roms/gbc/Adventure Island (USA, Europe).gb|gambatte_libretro|25"
  "gba|$HOME/Downloads/roms/gba/Plataformas/Super Mario Advance 1 - Super Mario Bros 2.gba|mgba_libretro|25"
  "megadrive|$HOME/Downloads/roms/megadrive/Adventures of Batman & Robin, The (USA).md||25"
  "n64|$HOME/Downloads/roms/n64/007 - GoldenEye (Europe).z64|mupen64plus_next_libretro|45"
  "nds|$HOME/Downloads/roms/nds/Dragon Quest 4 - The Chapters of the Chosen.nds|desmume_libretro|45"
  "psp|$HOME/Downloads/roms/psp/FIFA Soccer 12 (USA) (En,Es).iso|ppsspp_libretro|60"
  "ps2|$HOME/Downloads/roms/ps2/Star Trek - Shattered Universe/Star Trek - Shattered Universe.iso|play_libretro|60"
  "gamecube|$HOME/Downloads/roms/gamecube/FIFA 07 (United Kingdom).iso|dolphin_libretro|60"
  "dos|$HOME/Downloads/roms/dos/Carma.zip|dosbox_pure_libretro|45"
  "mame|$HOME/Downloads/roms/mame/1942.zip|mame_libretro|60"
)

kill_stale() {
  pkill -x TruchiEmu 2>/dev/null
  pkill -x TruchiEmuCoreHost 2>/dev/null
  sleep 3
  pkill -9 -x TruchiEmu 2>/dev/null
  pkill -9 -x TruchiEmuCoreHost 2>/dev/null
  sleep 1
}

pass=0
fail=0

for entry in "${CASES[@]}"; do
  IFS='|' read -r label rom core timeout <<< "$entry"
  printf '%-12s ' "[$label]"
  if [ ! -f "$rom" ]; then
    echo "FAIL (missing ROM: $rom)"
    fail=$((fail + 1))
    continue
  fi
  kill_stale
  # The app also prints its log lines to stdout; capture that to a per-case
  # file so we avoid log-trim races on TruchiEmu.log (the byte-offset approach
  # missed boots when the file was trimmed between cases).
  case_log="$(mktemp -t truchiemu_smoke.XXXXXX)"
  if [ -n "$core" ]; then
    TRUCHI_SMOKE_ROM="$rom" TRUCHI_SMOKE_CORE="$core" "$BIN" --launch >"$case_log" 2>&1 &
  else
    TRUCHI_SMOKE_ROM="$rom" "$BIN" --launch >"$case_log" 2>&1 &
  fi
  app_pid=$!

  ok=0
  for ((i = 0; i < timeout; i++)); do
    sleep 1
    if grep -qE "$MARKER_REGEX" "$case_log"; then
      ok=1
      break
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  done

  if [ "$ok" = 1 ]; then
    frame=$(grep -m1 -E "$MARKER_REGEX" "$case_log")
    echo "PASS $frame"
    pass=$((pass + 1))
  else
    echo "FAIL (no first frame within ${timeout}s)"
    fail=$((fail + 1))
  fi
  rm -f "$case_log"
  kill_stale
done

echo "----------------------------------------"
echo "boot smoke: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
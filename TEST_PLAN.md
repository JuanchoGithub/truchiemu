# TruchiEmu Test Plan

Covers the D1–D4, E1–E7, F-sl audit changes. Two layers:

1. **Automated** — build + boot smoke matrix + slang shader audit.
2. **Manual** — UI/hardware checks that cannot be automated.

## Automated

### 1. Build

```sh
xcodegen generate
xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build
```

### 2. Boot smoke matrix

`scripts/smoke_test.sh` boots real ROMs through the real launch pipeline
(`GameLauncher` → `LaunchConfig` → runner → XPC bridge → libretro core) and
asserts the core produced a first frame. Env-gated harness:
`TruchiEmu/Features/Player/Services/BootSmokeRunner.swift` (only active when
`TRUCHI_SMOKE_ROM` is set; normal launches are unaffected).

```sh
scripts/smoke_test.sh [path/to/TruchiEmu.app]
```

Expected: **11 passed, 0 failed**. Covers:

| Case | Core | Exercises |
|---|---|---|
| nes (Donkey Kong) | fceumm | RF-shader first-frame path |
| gbc (Adventure Island) | gambatte | basic boot |
| gba (Super Mario Advance) | mgba | basic boot |
| megadrive (Batman & Robin) | auto-resolved | **D4** extension→system index + core resolution |
| n64 (GoldenEye) | mupen64plus_next | **D1** HW render |
| nds (Dragon Quest 4) | desmume | **D1** HW render |
| psp (FIFA 12) | ppsspp | **D1** HW render |
| ps2 (Star Trek: Shattered Universe) | play | **D1** HW render |
| gamecube (FIFA 07) | dolphin | **D1** HW render |
| dos (Carma) | dosbox_pure | archive boot |
| mame (1942) | mame | **F-sl** dependency check without mame_fallback |

Every case also exercises **D2/D3** (auto-save on window close, XPC sync calls)
and **E1** (core-options discovery) at launch.

### 3. Slang shader audit

Env-gated harness `SlangAuditRunner.swift`. Renders every curated slang preset
offscreen and checks not-black / not-pass-through / aspect-correct.

```sh
TRUCHI_SLANG_AUDIT=1 /path/to/TruchiEmu.app/Contents/MacOS/TruchiEmu
# then check the report (or use a timeout + kill):
```

Expected: **Healthy 42** (0 load/render/black/pass-through failures).
Covers **E3** (single active slang preset + `SlangCompilerService` pipeline).
Report: `~/Library/Application Support/TruchiEmu/SlangAudit/report.md`.

## Manual checklist

*All 7 rows verified by the user on 2026-08-18.*

| Slice | Change | Check | Status |
|---|---|---|---|
| B3 | Wizard single flag | First-launch onboarding: pick language + ROM folder, complete; verify main UI appears and `has_completed_onboarding` persists across relaunch | ✓ |
| D1 | `CoreCapabilities` | Boot a PSP or PS2 game and verify HW render (no black screen, correct scaling); exit cleanly (no hang, log shows normal shutdown) | ✓ |
| D2 | `GameSaveSet` snapshot | Game Detail → Saved States: save to a slot, verify the sheet list refreshes; load; check most-recent ordering; relaunch with auto-load on | ✓ |
| D3 | XPC sync helper | Launch/pause/rewind/save-state/cheat-toggle/core-option over XPC; watch `TruchiEmu.log` for stuck-sync timeouts | ✓ |
| D4 | extension→system index | Trigger a library rescan; identification results unchanged and scan completes promptly | ✓ |
| E1 | CoreOptions 5-layer walk | Set a per-game override, then a per-system override; verify game value wins; restore works | ✓ |
| E2 | ControllerService collapse | Connect 2–4 controllers; disconnect mid-session; remap a button; assign keyboard slot — no stale slots | ✓ |
| E3 | active slang preset | Pick a slang preset in the shader picker; relaunch the game and confirm the preset is retained | ✓ |
| E4 | Cheat finalize path | Download several cheats for one game, cancel one mid-download; verify the counter is exact | ✓ |
| E5 | raMatchStatus | Log in to RetroAchievements, boot a matched game; match status displays consistently in library + detail | ✓ |
| E6 | PendingThemeSettings | Change theme/accent → confirm relaunch prompt; Cancel → nothing changed; change appearance mode | ✓ |
| E7 | ManualStatusController | Game Detail: run manual action / fetch metadata / fetch box art / RA verification; status shows and auto-dismisses | ✓ |
| F-sl | MAME fallback removed | Boot a MAME game; dependency/verification UI still lists missing files correctly | ✓ |

## Known issues found during automation (pre-existing, not from this work)

- **ScummVM boot is broken in builds**: `ScummVMRunner.ensureDetectionDatabase`
  looks for `ScummVM.dat` at `Bundle.main` `Data/LibretroDats/` subdirectory,
  but resources are flattened to the bundle root, so the file is never found
  and game detection fails (`No valid game files found for auto-detect`).
  ScummVM is excluded from the smoke matrix until fixed.
- **Side effects of the smoke matrix**: each boot auto-saves state + SRAM on
  window close for the tested games. Re-runs may overwrite prior autosaves for
  those exact titles.

## Notes

- No test target exists; the boot/slang harnesses are env-gated test hooks in
  the app (same pattern as `SlangAuditRunner`), inert during normal use.
- `CLILauncher.swift` (CLI game-launch args) is orphaned: nothing calls it and
  the app never parses `--launch` into a game launch — it only uses the flag to
  set accessory mode + terminate-after-last-window. Flagged for follow-up.
# MAME Pipeline Archive

This folder archives the **outdated MAME database build/analysis pipeline** that was
superseded by `scripts/mame_lookup/build_mame_unified.py`. Nothing here is used by the
TruchiEmu app anymore. Files are archived — not deleted — for future reference.

**Archived on:** 2026-08-17
**Retired by:** audit-plan slice F-sl (MAME DAT/XML parser consolidation).

---

## TL;DR — What is still live

- **`../build_mame_unified.py`** (kept, one directory up) is **the definitive MAME
  database builder**. It downloads MAME.dat, MAME BIOS.dat, and the libretro-database
  core XMLs (MAME 2000 / 2003 / 2003-Plus / 2010 / 2015 / 2016-Arcade / 0.287) and emits
  **`mame_unified.json`**, which is copied to
  `TruchiEmu/Resources/Data/mame_unified.json` and bundled with the app.
- **`../mame_unified.json`** is the single source of MAME truth consumed at runtime by
  `MAMEUnifiedService` and by `MAMEDependencyService.loadFromUnifiedDatabase(_:)`.
- The scripts `scripts/download_all_dats.py` (No-Intro seed SQLite) and
  `scripts/rom_matching_tester.py` (matching-algorithm tester) are **separate
  pipelines** — they were NOT part of the MAME unified builder and remain live in
  `scripts/`.

## What is archived here

| File | Former role | Why retired |
|---|---|---|
| `download_and_parse.py` | Downloaded MAME.dat / BIOS.dat / 2015 XML / mame.lst and produced **`mame_rom_data.json`** (`{roms: {shortname: {name, description, type, isRunnable, year, manufacturer, parent, players}}}`) | Superseded by `build_mame_unified.py`. Its output fed the legacy `mame_fallback` database only. |
| `merge_sources.py` | Merged additional MAME data sources into `mame_rom_data.json` (hardcoded dev path) | Same — part of the retired `mame_rom_data` pipeline. |
| `add_missing_entries.py` | Added ROM entries discovered by analysis into `mame_rom_data.json` (hardcoded dev path) | Same. |
| `build_mame_2003_plus.py` | Built a standalone **`mame_2003_plus.json`** with extra fields (cpuClock, soundChannels, driverColor, driverSound, coins) | Output was **never bundled and never consumed** by the app. The 2003-Plus core data is already included in `mame_unified.json` via `build_mame_unified.py`'s `CORE_SOURCES`. |
| `mame_rom_data.json` | 12 MB legacy fallback DB shipped in the app bundle (via the old `scripts/mame_lookup` resources build phase) | Superseded by `mame_unified.json`. Its only consumer was `MAMEDependencyService`'s `mame_fallback` safety net, which was removed as part of this cleanup. |
| `mame_2003_plus.json` | 16 MB standalone output of `build_mame_2003_plus.py` | Never consumed; dead weight. |
| `analyze_coverage.py` | Scanned `~/Downloads/roms/mame`, matched zips against `mame_rom_data.json`, wrote **`coverage_report.json`** | Analysis tool tied to the retired `mame_rom_data.json`. |
| `check_coverage.py` | Printed ROM coverage stats against `mame_rom_data.json` | Same. |
| `analyze_unknown_zips.py` | Inspected zip contents for zips missing from `mame_rom_data.json` | Same. |
| `coverage_report.json` | Stale output of `analyze_coverage.py` | Same. |

## Pipeline history (why these exist)

1. **Early phase** — `download_and_parse.py` (later `merge_sources.py`,
   `add_missing_entries.py`) built `mame_rom_data.json`, a per-shortname map with
   basic description / type / isRunnable / parent. The app bundled it and
   `MAMEDependencyService` loaded it at startup as a `mame_fallback` database to
   provide minimal dependency info for cores with no cached per-core XML DB.
2. **Consolidation phase** — `build_mame_unified.py` was introduced to merge **all**
   libretro MAME core sources into one unified DB (`mame_unified.json`) with richer
   per-core data: compatibleCores, coreDeps (cloneOf/romOf/sampleOf/mergedROMs),
   runnable flags, BIOS detection, and best-source video/input/chip metadata. The app
   switched primary loading to `MAMEUnifiedService` and
   `MAMEUnifiedService`/`loadFromUnifiedDatabase`, making `mame_rom_data.json` a
   superseded fallback.
3. **`build_mame_2003_plus.py`** was a parallel one-off experiment producing a
   standalone richer 2003-Plus file that never shipped.
4. **2026-08 cleanup (this archive)** — with `mame_unified.json` fully covering all
   seven cores, the `mame_rom_data` pipeline and its analysis tools were retired, the
   `scripts/mame_lookup` resources build phase was removed from `project.yml`, and the
   dead `mame_fallback` code path was deleted from `MAMEDependencyService`.

## Notes on parser divergence (from the audit)

The six DAT/XML parsers that used to exist were **not** interchangeable:

- `build_mame_unified.py:parse_xml_data` and `build_mame_2003_plus.py:parse_xml` shared
  ~80% of the element-extraction logic but emitted **different schemas** (the 2003-Plus
  variant added `cpuClock`, `soundChannels`, `driverColor`, `driverSound`, `coins`).
- `download_and_parse.py:parse_dat_block` used a balanced-parenthesis block parser and
  keyed entries by **ROM shortname**, whereas the `.dat` regex parsers keyed by game
  name.
- `download_all_dats.py:parse_dat_contents` and `rom_matching_tester.py:parse_dat_file`
  were line-based ClrMamePro CRC parsers for a different purpose (ROM identification).
- **BIOS parsing diverged:** `build_mame_unified.py:parse_bios_dat` extracted **zip
  stems** from `rom ( name X.zip ...)` because BIOS.dat game names are descriptions,
  while `build_mame_2003_plus.py:parse_bios_dat` used the game `name` directly. The
  unified builder's zip-stem approach is the correct one; the 2003-Plus variant was
  likely buggy. Since the 2003-Plus builder is archived, only the correct parser
  survives in `build_mame_unified.py`.

## How the app loads MAME data today

1. **`MAMEUnifiedService.shared`** loads the bundled `mame_unified.json` and serves
   lookups (description, isBIOS, isRunnableInAnyCore, compatibleCores, coreDeps).
2. **`MAMEDependencyService`** builds per-core `MAMEDependencyDB`s from the unified DB
   via `loadFromUnifiedDatabase(for:)` (or from a cached/persisted per-core XML DB), and
   `lookupGame` prefers the per-core DB, then falls back to `MAMEUnifiedService`. The
   old `mame_fallback` (`mame_rom_data.json`) path was removed.

## How to resurrect (if ever needed)

1. Rebuild the unified DB: run `python3 scripts/mame_lookup/build_mame_unified.py`
   (requires network access to the libretro-database raw URLs and, for MAME 0.287, the
   progettosnaps.net 7z plus a `7z` binary). It writes `scripts/mame_lookup/mame_unified.json`
   and copies it to `TruchiEmu/Resources/Data/mame_unified.json`.
2. If a legacy `mame_rom_data` fallback is ever desired again, restore
   `download_and_parse.py`, run it to regenerate `mame_rom_data.json`, re-add a
   `scripts/mame_lookup` resources build phase in `project.yml`, and re-introduce
   `MAMEDependencyService.loadFallbackFromBundle()`/the `dependencyCache["mame_fallback"]`
   branch (see git history for the removed code).
3. The analysis tools (`analyze_coverage.py` etc.) can be pointed at
   `mame_unified.json` if a coverage pass is wanted — they currently reference
   `mame_rom_data.json`.
# Codebase Audit — Implementation Plan

## Overview

Read-only audit of the full repository (28 subsystems, HEAD `632e0825`) produced 38 confirmed simplification opportunities. This plan sequences them into independent, verifiable slices. Work in slice order; each step below is independently verifiable. Tick the box when the step is done and its validation passed.

**Verification baseline:** Build with `xcodebuild -project TruchiEmu.xcodeproj -scheme TruchiEmu -configuration Debug build`. No test target exists; validation is manual per step. Do not bump `CFBundleVersion`.

**Legend:** Each step lists the finding ID, evidence, scope (affected files), and how to verify.

---

## Slice A — Safety defects (independent, highest value)

### A1. RetroAchievements auth state machine (F2)

- [ ] Replace the six overlapping auth fields with one `AuthState` enum + single token value
- [ ] Single `logout()` that clears token and state
- [ ] `surfaceReloginNeeded` transitions state instead of a boolean

**Evidence:** `RetroAchievementsService.swift:16,74-93` (fields), `:2189-2215` (token-failure path never sets `isLoggedIn=false`), `RetroAchievementsSettingsView.swift:79,272-278` (stale "Logged in" UI; logout doesn't clear `ra_login_token`).
**Scope:** `RetroAchievementsService.swift`, `RetroAchievementsSettingsView.swift`, any reader of the removed fields.
**Verify:** login → invalidate token (settings UI shows logged-out) → logout clears token → relogin works. No stale "Logged in" shown with a dead token.

### A2. Streaming/recording session state (F3)

- [ ] One `SessionState` enum replaces `isRecording`/`isRecordingFlag`/`isUserRecording`/`currentInitiator` lockstep
- [ ] One `resetSession()` called by all five teardown sites
- [ ] Rolling-buffer finalize calls `stopAudioCapture()`

**Evidence:** `StreamRecordingService.swift:111-119,158` (mirror flags), teardown sites `:793-806, 893-910, 920-930, 972-980`; `RollingVideoBufferService.swift:403-412` (finalize without `stopAudioCapture()` → 16 ms audio timer keeps firing).
**Scope:** `StreamRecordingService.swift`, `RollingVideoBufferService.swift`, streaming settings UI.
**Verify:** record→stop; stream→disconnect→reconnect; forced stop mid-stream; no audio timer alive after stop (check via log or Activity Monitor).

### A3. 404 negative-cache TTL honored (F11)

- [ ] 404 entries expire using the stored `expiresAt` (24 h)
- [ ] Reorder checks so expiry precedes the 404 fast path

**Evidence:** `ResourceCacheInterceptor.swift:39-43` (404 branch before expiry), `:45,:59` (expiry), `:287-297` (writes `expiresAt = now + 86400` never consulted); `ResourceCacheModels.swift:75-84`.
**Scope:** `ResourceCacheInterceptor.swift`, `ResourceCacheModels.swift`.
**Verify:** Temporarily set TTL to seconds; request a 404 URL, then a successful fetch; confirm the second is retried (not served the cached 404).

---

## Slice B — Launch/state correctness

### B1. Pause/scrub state machine (F1) — single most impactful behavioral change

- [x] Add one `PauseState` (idle / scrubbing / paused / scrubbingOverPaused) to `BaseRunner`
- [x] `enter/exitTimeMachineMode` preserve prior pause (currently `exitTimeMachineMode` unconditionally `setPaused(false)` → scrubbing over a pause un-pauses)
- [x] Window controller writes only `runner.isPaused`; derive XPC + MTKView state from it (remove ~15 direct triple-writes)
- [x] Remove `isRewindingStorage` manual mirror; keep one published source

**Evidence:** `BaseRunner.swift:324,669,828,841` (state fields), `:916-946` (enter — sets `isRewinding`, not `isPaused`), `:977` (exit — unconditional `setPaused(false)`); triple-writes at `StandaloneGameWindowController.swift:333,663,696-697,964,1169-1170,1353-1354`, `+GamepadNav.swift:39-42,59-62`; read at `GameButtons.swift:239`.
**Scope:** `BaseRunner.swift`, `StandaloneGameWindowController.swift`, `+GamepadNav.swift`, `ExternalDisplayPromptManager.swift`.
**Verify:** pause → rewind while paused → exit scrub keeps the game paused; rewind in fast-forward; toolbar/bezel/streaming reflect pause correctly.

### B2. LaunchConfig dead fields (F9 + F8)

- [x] Delete `slotToLoad`, `coreOptions`, `bezelFileName` from LaunchConfig (never read; only logged)
- [x] Delete no-op write-backs `AppSettings.setBool("saveState_autoLoadOnStart"/"saveState_autoSaveOnExit")` at `GameLauncher.swift:586-587`
- [x] Delete `hardcoreMode` snapshot; enforcement stays on live `HardcoreModeManager` reads

**Evidence:** `GameLauncher.swift:52-143` (config), `:297,:303` (only logged), `:510` (real slot via param, not config), `:586-590` (write-backs); live reads `StandaloneGameWindowController.swift:1046,1126,1232,1971,2077`.
**Scope:** `GameLauncher.swift` (+ any LaunchConfig callers).
**Verify:** Launch with/without auto-save/auto-load — preferences unchanged after launch; hardcore blocks still enforced.

### B3. Setup-wizard dual flags (F10)

- [x] One flag (keep `has_completed_onboarding`), one writer
- [x] Delete dead `completeOnboarding` setter

> **UNTESTED:** B3 code is committed but not yet manually verified. To test: fresh install shows wizard → complete it → relaunch lands on library → Settings "Run setup wizard again" re-shows wizard.

**Evidence:** `SetupWizardState.swift:150-153` vs `ROMLibrary.swift:108,155,387`; both written `SetupWizardView.swift:130-132`; conjunction gate `ContentView.swift:50`; dead setter `ROMLibrary.swift:384-388`.
**Scope:** `SetupWizardState.swift`, `ROMLibrary.swift`, `ContentView.swift`, `SetupWizardView.swift`, `LibrarySettingsViewGroup.swift:195-196`.
**Verify:** Fresh install shows wizard; complete it; relaunch lands on library; settings reset re-shows wizard.

---

## Slice C — Dead-code removal (trivially safe)

- [ ] **C1 (F5):** Delete `SequenceRunner.swift` + `TrainingInputManager.perFrameTick`; keep `TrainingFramePollDriver` as the one frame driver. **Evidence:** `SequenceRunner.swift:80-221` duplicates `TrainingModeManager.swift:652-754`; `perFrameTick` (`TrainingInputManager.swift:124`) has zero callers; live path `LibretroCallbacks.mm:447`. **Verify:** training FMD/delay cards in an arcade game; move list playback.
- [ ] **C2 (F14):** Delete dead ScummVM game-ID detection branch in `ScummVMRunner`. **Verify:** ScummVM games boot normally.
- [ ] **C3 (F23):** Delete dead incremental branch in `ROMLibrary.updateCounts(for:)` (`:305-342`, sole call `:488`). **Verify:** library counts correct after scan/delete.
- [ ] **C4 (F28):** Remove write-only `isVerified` from `MAMEVerificationRecord` (`:13-14,71-97`; never read externally). Add `didSet` compat shim or accept SwiftData auto-migration. **Verify:** MAME verification UI unchanged; rebuild passes.
- [ ] **C5 (F24):** Remove `cachedBezels` mirror in `BezelBrowserView` (`:20,446,450,468-482`); final writes go through `BezelAPIService.swift:366-369,397`. **Verify:** bezel install/remove/uninstall updates the browser list correctly.

---

## Slice D — Hot-path cost

- [ ] **D1 (F6):** One per-launch `CoreCapabilities` struct replaces per-frame substring scans. **Evidence:** `LibretroBridgeImpl.mm:899-906` (7 `containsString` per frame in `readHWRenderedPixels`), plus `:135,195,225-250,281,459-461`, `LibretroCallbacks.mm:306`. **Verify:** boot PSP/PS2/Dolphin/N64/DOS games; HW render + shutdown paths correct.
- [ ] **D2 (F4):** One directory read per refresh → `[GameSaveSet]` snapshot. **Evidence:** `SaveStateManager.swift:159-170,180-202,597-607` (~22 listings), consumers `GameDetailView.swift:27-28,433-438`, `SaveManagerView.swift:700-765`, `BaseRunner.swift:1363-1376`. **Verify:** save/load from detail view + saved-states sheet + auto-load + most-recent.
- [ ] **D3 (F7):** One generic synchronous XPC reply helper; convert `setSpeedMultiplier`. **Evidence:** `XPCBridgeAdapter.swift:622-893` (14 copies), drift `:426-447`. **Verify:** launch, pause, save-state, rewind, cheats, core options over XPC; no stuck-sync timeouts in log.
- [ ] **D4 (F22):** Precompute normalized-extension→systems index in `ROMIdentifier`; reuse `SystemSearchIndex` cache. **Evidence:** `ROMIdentifier.swift:93,131,269,299,509-511,628,914`. **Verify:** library scan performance; identification results unchanged.

---

## Slice E — Data-structure consolidation

- [ ] **E1 (F19):** One 5-layer precedence walk in `CoreOptionsManager`. **Evidence:** `:132-179,450-491,633-675`; 9 call sites `CoreOptionsSection.swift:232-293`. **Verify:** core options override behavior per game/system unchanged.
- [ ] **E2 (F18):** Collapse three parallel device→slot maps in `ControllerService`. **Evidence:** `:15,41,330-343`; 6 near-identical mutation funcs `:402-552`. **Verify:** 4-player connect/disconnect, gamepad remap, keyboard slot assignment.
- [ ] **E3 (F20):** Single source for "active slang preset". **Evidence:** `ShaderManager.swift:21,71-72,152-153` + `SlangCompilerService.swift:7,105`. **Verify:** slang preset switch, shader editor, game relaunch retains preset.
- [ ] **E4 (F21):** One finalization path for per-file cheat-download state. **Evidence:** `CheatDownloadService.swift:801-811` + seven decrement blocks `:836-960`; counter `CheatSettingsView.swift:260-261`. **Verify:** download multiple cheats, cancel one, counter correct.
- [ ] **E5 (F13):** Canonical `raMatchStatus` values (empty/"matched"/"mismatch") instead of `"mismatch:\(hash)"`. **Evidence:** `SwiftDataModels.swift:35`; writes `RetroAchievementsService.swift:1055,1065,1080`; consumers `GameLauncher.swift:410`, `LibraryViewModel.swift:227`, `SystemSidebarView.swift:130`, `CoreAndAchievements.swift:200`, `GameInfoWindow.swift:67`. **Verify:** achievement match status shown correctly after refresh.
- [ ] **E6 (F25):** `PendingThemeSettings` struct for the five-field pending-theme cluster. **Evidence:** `GeneralSettingsView.swift:9-22,299-334`; `SettingsView.swift:236-245,618-628,692-736,769-775`. **Verify:** theme/color/appearance change → relaunch prompt → persists.
- [ ] **E7 (F27):** `ManualStatusController` for the 4× (status + Task) pairs. **Evidence:** `GameDetailView.swift:45-46,59-62,79-80`; `Technical.swift:280-284,297-301,366-370`. **Verify:** delete-ROM, sync, refresh actions show/cancel status correctly.

---

## Slice F — Tooling

- [ ] **F-sl (F12):** One shared MAME DAT/XML parser module under `scripts/mame_lookup/`. **Evidence:** `build_mame_unified.py:240-251` == `build_mame_2003_plus.py:167-178`; four more divergent parsers `download_and_parse.py:260-384`, `download_all_dats.py:167-229`, `rom_matching_tester.py:472-505`; BIOS divergence `build_mame_unified.py:272-291` vs `build_mame_2003_plus.py:199-217`. **Verify:** regenerate `mame_unified.json`; diff against committed file; re-run `rom_matching_tester`.

---

## Slice G — Organizational (lowest value, do not block releases)

- [ ] **G1 (F29):** `AccentColorTheme` as a data table. **Evidence:** `AccentColorTheme.swift:54-140,142-208,210-253` (10 parallel 17-case switches).
- [ ] **G2 (F30):** SystemInfo merge-group tables. **Evidence:** `SystemInfo.swift:468-525`; dup `SystemDatabaseWrapper.swift:14-33`.
- [ ] **G3 (F31):** Session-state collapse in `XPCConnectionManager` (S5-R2).
- [ ] **G4 (F32):** MetalCoordinator end-of-frame capture bookkeeping dedup (S2-R2).
- [ ] **G5 (F33):** Remove `g_hwFBO` global mirror (S3-R2).
- [ ] **G6 (F34):** Slang parameter-resolution helper (3 duplicated resolutions in picker, S15-R2).
- [ ] **G7 (F35):** Typed slot state (S14-R2), Cheat identity single key (S13-R2), runnable short-name collapse (S10-R2).
- [ ] **G8 (F36):** `isLaunching`/`currentLaunchROM` collapse (S25-R2); `initialSection` re-sync (S26-R2).
- [ ] **G9 (F37):** CoreOptions versioned-key derivation (S20-R2); search-keyword drift fix (S21-R2).
- [ ] **G10 (F38):** Library filter/sort collapse (S8-R2); ImageCache key spaces (S24-R2); mame_2003_plus retirement (S27-R2); CoreDownloadPhase payload removal (S1-R2).

---

## Game Guide (optional, independent)

From the S28 coverage gap review — apply anytime, does not depend on other slices:

- [ ] **H1 (F15):** One list row model replaces `currentTopics` + `gamefaqsFAQs`. **Evidence:** `GameGuideViewModel.swift:237-239`; branch sites `GameGuideSidebar.swift:141-159`, `GameGuideViewModel.swift:323,366-371`. **Verify:** UHS topic list + GameFAQs FAQ list + gamepad nav in both modes.
- [ ] **H2 (F16):** One `GuideContent` enum replaces three optionals with contradictory precedence. **Evidence:** `GameGuideSidebar.swift:19-22` vs `GameGuideViewModel.swift:318-319` (reversed precedence); partial clears `:146,154,163`. **Verify:** reveal hints via mouse + gamepad; back-stack; walkthrough back-to-list.

---

## Suggested order

1. **Slice A** (A1 → A2 → A3) — safety defects, all independent.
2. **Slice C** (dead code) — any order; pairs naturally with Slice A as low-risk first work.
3. **B1** (pause) — alone, largest change.
4. **B2 + B3** — launch/state correctness.
5. **Slice D** → **Slice E** → **Slice F** → **Slice G**.
6. **H1/H2** whenever convenient.

**Note on overlap:** F8 and F9 both touch LaunchConfig — do them together in B2. F4 (D2) precedes the typed-slot work in G7.
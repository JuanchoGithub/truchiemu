---
title: Debugging the Invisible: Why Dreamcast Games Couldn't Save
---

# Debugging the Invisible: Why Dreamcast Games Couldn't Save in Our Emulator

We spent the better part of a week tracking down a bug where Dreamcast games in TruchiEmu simply couldn't save. No error message, no crash — just silence. The VMU (Visual Memory Unit, the Dreamcast's memory card) simply didn't exist as far as the games were concerned. What followed was a journey through closed-source binary analysis, libretro API semantics, and a single wrong string that cascaded into total failure. Here's how we found it and fixed it.

---

## The Dreamcast's Memory Problem

The Dreamcast is unusual among consoles in that its memory cards — VMUs — plug into the controller, not the console. Each controller has two expansion slots, and the VMU goes in slot 1. From the emulator's perspective, this means the VMU isn't a simple file on disk — it's a **maple bus device** that has to be explicitly created and attached to a controller port at runtime.

Flycast, the libretro core we use for Dreamcast emulation, handles this through its option system. Core options like `reicast_device_port1_slot1` control what's plugged into each slot. The possible values are: `VMU`, `Purupuru` (a vibration pack), `DreamPotato` (a third-party peripheral), and `None`. If a controller's slot 1 isn't set to `VMU`, games have nowhere to save. That was our problem.

---

## The Setup: How We Thought It Worked

We had a `CoreOverrides.json` file that set default values for core options — things like rendering mode, threading, and device port assignments. For the Dreamcast, we set each controller's slot 1 to `"Visual Memory"`, because that's what the option's UI label says:

```json
"reicast_device_port1_slot1": "Visual Memory"
```

Seems reasonable, right? "Visual Memory" is what Flycast shows in its option menu. That's the name everyone knows the VMU by. It was also completely wrong.

---

## Pitfall #1: Labels vs. Values

The libretro core option API has a concept of **values** and **labels**. Values are what the code compares against. Labels are what humans see in a menu. They're often different, especially for options with special characters, localization concerns, or legacy naming.

We discovered this the hard way by doing a hex dump of the Flycast binary:

```
0x57d4c6: VMU
0x57d4ca: Purupuru
0x57d4d3: DreamPotato
0x57d4df: None
```

These are the **value** strings — what Flycast's `update_variables()` actually passes to `strcmp()`:

```cpp
if (!strcmp("VMU", var.value))
    config::MapleExpansionDevices[port][slot] = MDT_SegaVMU;
else if (!strcmp("Purupuru", var.value))
    config::MapleExpansionDevices[port][slot] = MDT_PurupuruPack;
```

`"Visual Memory"` never matches. Not `VMU`, not `Purupuru`, not anything. It falls through every branch. But it gets worse. Because `var.value` is non-NULL — it's `"Visual Memory"`, a real string — the fallback default that would have set a VMU is also skipped. The code assumes that if the value didn't match any known option, it was intentionally set to something unusual. The result: the expansion device configuration is never updated, and Flycast falls back to its internal default, which is **Purupuru** (a vibration pack). No VMU. No saves. The fix was one line in CoreOverrides.json, but finding it required binary analysis because Flycast's libretro source had drifted from the actual compiled binary we were running.

> **Lesson:** In the libretro API, option values and labels are separate things. Always use the value, not the label, when setting options programmatically. If you're working with a binary you didn't compile, verify the actual strings.

---

## Pitfall #2: The First-Startup Guard

Even after fixing the value to `"VMU"`, there was a timing problem. Flycast's `update_variables()` function has a `first_startup` parameter:

```cpp
static void update_variables(bool first_startup)
{
    config::Settings::instance().load(false);
    // ... process many options ...

    if (!first_startup) {
        // Device port options ONLY processed here
        for (int port = 0; port < 4; port++) {
            // read reicast_device_port*_slot* options
            // set MapleExpansionDevices accordingly
        }
        devices_need_refresh = true;
    }
}
```

During `retro_load_game()`, Flycast calls `update_variables(true)`. Device port options are **skipped entirely** on the first call. The rationale makes sense: during initial startup, the core hasn't fully initialized its hardware emulation, so configuring maple devices prematurely could cause issues. Instead, Flycast creates devices with its internal defaults (Purupuru in slot 1) and defers user-configured device port assignments to a later call.

This means our `"VMU"` override was sitting in `g_optValues`, ready to be returned, but Flycast never asked for it during the only option read that happened before devices were created.

> **Lesson:** Libretro cores don't necessarily read all their options at the same time. Some options are gated behind startup state. You need to understand the core's specific option-reading lifecycle, not just the API contract.

---

## Pitfall #3: The Variable Update Signal

The libretro API provides `RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE` — a callback the core polls to check if option values have changed since the last read. If it returns `true`, the core should re-read its options. Flycast checks this at the start of each `retro_run()`:

```cpp
void retro_run()
{
    bool updated = false;
    if (environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && updated)
        update_variables(false);   // first_startup=false — device ports NOW processed

    if (devices_need_refresh)
        refresh_devices(false);    // calls maple_ReconnectDevices()

    if (first_run)
        emu.start();               // starts emulation with correct devices

    // ... render frame ...
    first_run = false;
}
```

This is the key sequence: `update_variables(false)` → `refresh_devices(false)` → `emu.start()`. If we could signal `GET_VARIABLE_UPDATE = true` after `retro_load_game()` but before the first `retro_run()`, Flycast would re-read options with `first_startup=false`, process the device port assignments, create VMUs, and then start emulation with the correct device configuration.

But TruchiEmu's callback always returned `false`. We had no mechanism to tell Flycast "hey, your options changed." Our fix: a global flag set after `retro_load_game()`:

```objc
// LibretroBridgeImpl.mm — after retro_load_game() for Flycast cores
if (g_coreID && [[g_coreID lowercaseString] containsString:@"flycast"]) {
    g_variablesUpdated = YES;
    [self setControllerPortDevice:1 device:device_type];
    [self setControllerPortDevice:2 device:device_type];
    [self setControllerPortDevice:3 device:device_type];
}
```

```objc
// LibretroCallbacks.mm — GET_VARIABLE_UPDATE handler
case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
{
    bool updated = g_variablesUpdated;
    if (updated) {
        g_variablesUpdated = NO;   // consume the flag — return true once
    }
    if (data)
        *(bool *)data = updated;
    return true;
}
```

The flag is **consumed on read**. It returns `true` exactly once, then resets. This triggers Flycast's `update_variables(false)` on the first frame, which processes device port options, which detects our `"VMU"` value, which sets `MDT_SegaVMU`, which triggers `refresh_devices(false)`, which calls `maple_ReconnectDevices()`, which recreates all maple devices with VMUs in slot 1. Then `emu.start()` runs, and the Dreamcast boots with memory cards.

> **Lesson:** The libretro API is a conversation, not a configuration file. Some cores need to be *told* to re-read options; they won't do it on their own. Understanding which API signals trigger which internal state transitions is critical.

---

## Pitfall #4: Option Values Read Without GET_VARIABLE

As if the timing issues weren't enough, some libretro cores read option values through internal code paths that don't go through `RETRO_ENVIRONMENT_GET_VARIABLE` at all. They access their config system directly. To handle this, we added **preloading** — injecting JSON overrides directly into the `g_optValues` dictionary at core initialization time, before Flycast ever queries anything:

```objc
void core_override_apply_all_to_optvalues(const char* coreID) {
    if (!coreID || !g_optValues) return;
    NSString* coreStr = [NSString stringWithUTF8String:coreID];
    NSDictionary* allOverrides = [CoreOverrideBridge getAllOverridesFor:coreStr];
    if (!allOverrides || allOverrides.count == 0) return;

    for (NSString* key in allOverrides) {
        NSString* value = allOverrides[key];
        if (key.length > 0 && value.length > 0) {
            g_optValues[key] = value;
        }
    }
}
```

This is called from `applyPersistedOverrides()`, which runs during `SET_CORE_OPTIONS`. The override layering is:

1. **JSON overrides** (our defaults) — applied first
2. **.cfg overrides** (user's saved choices) — applied on top, always winning

This ensures our VMU defaults are in place for any code path Flycast uses to read options, while still respecting any explicit user configuration.

> **Lesson:** When bridging two systems (a Swift app and a C++ emulator core), you can't assume all communication goes through the official API. Internal code paths may bypass your callbacks. Defensive preloading ensures consistency regardless of which path the core takes.

---

## Pitfall #5: Missing and Corrupted VMU Files

Even with all the software fixes above, VMUs won't work if the actual save files don't exist on disk. Flycast looks for VMU files in the system directory (`system/dc/`), specifically files like `vmu_save_A1.bin` through `vmu_save_D1.bin`. Each must be exactly 128KB — a properly formatted FAT12 filesystem with 200 free blocks.

We bundled pre-formatted VMU files in `dreamcast.zip` alongside the BIOS files, and extended `DreamcastBIOSService` to extract and validate them:

```swift
private func repairCorruptVMUFiles() {
    for file in vmuFiles {
        let url = dcDirectory.appendingPathComponent(file)
        guard fm.fileExists(atPath: url.path) else { continue }

        // Wrong size? Delete and re-extract
        if size != vmuExpectedSize {
            try? fm.removeItem(at: url)
            continue
        }

        // All zeros? (Flycast can zero out VMUs on bad shutdown)
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           data.allSatisfy({ $0 == 0 }) {
            try? fm.removeItem(at: url)
        }
    }
}
```

The corruption check matters. We discovered that when Flycast shuts down without properly unmounting the VMU filesystem (e.g., if the user force-quits), it can write a zeroed-out file. A 128KB file of all zeros passes the size check but is a corrupted filesystem. Games see it as an unformatted card and can't save. Our repair logic detects this and re-extracts the known-good VMU from the bundle.

> **Lesson:** Emulator cores can corrupt their own save files. Validating file integrity (not just existence) is essential for a reliable experience.

---

## The Inverted Guard Bug

While debugging the VMU extraction, we found a logic error in `ensureExtracted()` that had been silently preventing VMU files from being deployed:

```swift
// BEFORE — inverted logic: returns early when files are MISSING
guard hasAllFiles && hasAllVMUFiles else { return }

// AFTER — correct: returns early only when all files are PRESENT
if hasAllFiles && hasAllVMUFiles { return }
```

The `guard ... else { return }` pattern returns when the condition is **false** — i.e., when files are missing. The function was bailing out exactly when it should have been extracting files. This was a classic Swift foot-gun: `guard` is designed for early return on **failure**, but the logic was written as if it were an `if` statement for **success**.

> **Lesson:** Swift's `guard` statement inverts the control flow compared to `if`. Always double-check the early-return direction when converting between the two.

---

## The Complete Chain

Here's what happens now when a Dreamcast game launches in TruchiEmu:

1. **App launch** — `DreamcastBIOSService.ensureExtracted()` validates and extracts VMU files to `system/dc/`
2. **Core load** — `SET_CORE_OPTIONS` → `parseCoreOptionsV2()` stores option defaults in `g_optValues`
3. **Override preloading** — `core_override_apply_all_to_optvalues()` writes `"VMU"` into `g_optValues` for all device port slot1 entries
4. **`retro_load_game()`** — Flycast calls `update_variables(true)` → device port options **skipped** (first_startup) → devices created with Purupuru defaults
5. **Post-load** — TruchiEmu sets `g_variablesUpdated = YES` + calls `setControllerPortDevice` for ports 1-3
6. **First `retro_run()`** — Flycast polls `GET_VARIABLE_UPDATE` → returns `true` → `update_variables(false)` → device port options **processed** → `strcmp("VMU", "VMU")` matches → `MapleExpansionDevices` set to `MDT_SegaVMU` → `devices_need_refresh = true`
7. **Same frame** — `refresh_devices(false)` → `maple_ReconnectDevices()` → controllers recreated with VMUs in slot 1
8. **Same frame** — `emu.start()` → emulation begins with VMUs equipped
9. **Game saves** → writes to `system/dc/vmu_save_A1.bin`

From the user's perspective, it just works. The game sees memory cards, saves happen, and the files are there next time they boot.

---

## What We Learned

**Binary analysis is sometimes unavoidable.** We couldn't figure out why `"Visual Memory"` wasn't working from the source code alone — the binary we were running had drifted from the latest source. Hex dumps and string searches were the only way to find the actual value strings.

**The libretro API is deceptively simple.** `GET_VARIABLE` looks like a key-value store, but the reality is that cores have complex option-reading lifecycles with startup guards, refresh signals, and internal code paths that bypass the API entirely. You have to understand each core's specific behavior.

**Emulator integration is deep integration.** You're not just passing configuration to a library — you're bridging two runtime environments with different lifecycles, different state management, and different assumptions about who owns what. The bugs live in the gaps between those environments.

**The hardest bugs are the silent ones.** No crash, no error message, no log line. Just a memory card that doesn't exist. The fix was a single string in a JSON file, but finding that string took understanding the entire option-reading lifecycle of a closed-source emulator core.

---

## Files Changed

| File | Change |
|------|--------|
| `TruchiEmu/Resources/Config/CoreOverrides.json` | `"Visual Memory"` → `"VMU"` for all `*_device_port*_slot1` entries |
| `TruchiEmu/Core/Engine/LibretroCallbacks.mm` | `GET_VARIABLE_UPDATE` handler returns `g_variablesUpdated` flag |
| `TruchiEmu/Core/Engine/LibretroGlobals.h` | Added `extern BOOL g_variablesUpdated` declaration |
| `TruchiEmu/Core/Engine/LibretroGlobals.mm` | Added `BOOL g_variablesUpdated = NO` definition |
| `TruchiEmu/Core/Engine/LibretroBridgeImpl.mm` | Set `g_variablesUpdated = YES` + `setControllerPortDevice` for ports 1-3 after `retro_load_game()` (Flycast only) |
| `TruchiEmu/Core/Engine/CoreOverrideBridge.h` | Declared `core_override_apply_all_to_optvalues()` |
| `TruchiEmu/Core/Engine/CoreOverrideBridge.mm` | Implemented `core_override_apply_all_to_optvalues()` — injects JSON overrides into `g_optValues` |
| `TruchiEmu/Resources/System/dreamcast.zip` | Added 4 pre-formatted 128KB VMU files (`vmu_save_A1.bin` through `vmu_save_D1.bin`) |
| `TruchiEmu/Services/DreamcastBIOSService.swift` | VMU extraction, validation, and corruption repair logic |

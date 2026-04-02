# Root-Cause Analysis: MAME/Arcade Games Running 100x Too Fast with Strange Colors

## Summary
MAME and other arcade cores in TruchieEmu exhibit two primary symptoms:
1. **Extreme speedup (100x+):** Games run far faster than their intended native speed
2. **Scrambled/strange colors:** Visual output shows garbled, incorrect colors

Both symptoms share the same root cause: **incomplete libretro frontend compliance** — specifically, missing initialization calls and reactive (rather than proactive) frame pacing.

---

## Part 1: SPEED Issues — Games Running 100x Too Fast

### Root Cause A: `retro_get_system_av_info()` is NEVER called after loading a ROM

**Severity:** CRITICAL  
**Evidence (LibretroBridge.mm, lines 580-581):**

```objc
_avInfo.timing.fps = 60.0;
_avInfo.timing.sample_rate = 44100.0;
```

The `_avInfo.timing.fps` is hardcoded to `60.0` during `launchROM`. The only way this value gets updated is through the `SET_SYSTEM_AV_INFO` environment callback. However:

- **Some cores never send `SET_SYSTEM_AV_INFO`** — they expect the frontend to call `retro_get_system_av_info()` directly to query timing information.
- MAME cores like `mame2003-plus` may set timing info only when queried, not via the environment callback.
- The `fn_retro_get_system_av_info` function pointer is loaded (line 87 of LibretroBridge.mm) but **it is never called after `retro_load_game()`**.

**Result:** If a core's native refresh rate is, say, 57.5 Hz (common in arcade hardware), but the frontend uses 60.0, the game runs ~4% too fast. Worse, if the core returns 0.0 for FPS when never queried, the speedup can be orders of magnitude.

### Root Cause B: Sleep-based frame pacing without audio-driven synchronization

**Severity:** CRITICAL  

The game loop (LibretroBridge.mm, lines ~685-719) uses a simple sleep-based approach:

```objc
double targetFPS = _avInfo.timing.fps;
if (targetFPS <= 0) targetFPS = 60.0;
if (targetFPS > 120.0) targetFPS = 60.0;

double frameTime = 1.0 / targetFPS;

uint64_t start = mach_absolute_time();
_retro_run();

if (elapsed < frameTime) {
    // Only checks audio buffer AFTER retro_run() completes
    size_t availableSamples = _audioBuffer->available();
    float fillRatio = (float)availableSamples / capacity;
    
    if (fillRatio >= 0.05f) {
        [NSThread sleepForTimeInterval:sleepTime];
    }
}
```

| Problem | Description |
|---------|-------------|
| **Reactive, not proactive** | The loop only checks the audio buffer *after* `retro_run()` has already executed. The core was never throttled *before* producing more frames. |
| **No pre-run throttling** | The core is never slowed down before calling `retro_run()`. It runs at maximum CPU speed, and sleep happens *after* the frame is already done. |
| **No dynamic rate control** | Proper libretro frontends use the audio buffer fill level as the primary pacing mechanism (fpsync). This code uses fixed frame timing with a reactive audio buffer check. |
| **NSThread sleep imprecision** | `sleepForTimeInterval:` has ~1-10ms granularity on macOS, which is insufficient for sub-millisecond frame pacing at 60fps (16.67ms/frame). |
| **No vsync/disp_sync** | The loop has no connection to display refresh timing. It uses pure CPU timing without display synchronization. |

**Result:** Without proper frame pacing, a core that renders a frame in 0.5ms on a modern CPU will run at ~2000fps instead of 60fps — roughly 33x too fast. Combined with other issues, this easily produces 100x speedup.

### Root Cause C: No fpsync or audio buffer pre-run throttling

1. **`bridge_audio_sample_batch`** always returns `frames` regardless of buffer state — the core assumes all audio is accepted even when the buffer is full.
2. **No overflow protection:** The buffer write can silently drop samples when full, losing audio-video synchronization entirely.
3. **The fill ratio check only prevents sleeping when <5% full** — it never *adds* extra delay when the buffer is >70% full beyond the normal frameTime sleep.

---

## Part 2: COLOR Issues — Strange/Scrambled Colors

### Root Cause D: Pixel format defaults to 0 (0RGB1555) and is never proactively set

**Severity:** CRITICAL  

The `_pixelFormat` instance variable is a bare `int` (declared at line 109 in LibretroBridge.mm) that is **never explicitly initialized**. In Objective-C, instance variable memory is zero-initialized, so `_pixelFormat` starts at `0`.

The libretro pixel format enum:
```c
enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,  // 16-bit, rarely used for output
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,  // 32-bit, the DEFAULT for most cores
    RETRO_PIXEL_FORMAT_RGB565   = 2,  // 16-bit, common for retro handhelds
};
```

**Most MAME cores use XRGB8888 (format 1) by default.** However, `SET_PIXEL_FORMAT` is an *optional* environment call — many cores don't explicitly send it because XRGB8888 is the assumed default.

**Chain of failure:**
1. Core loads and uses XRGB8888 (32-bit, 4 bytes per pixel)
2. Core never calls `SET_PIXEL_FORMAT` because format 1 is the assumed default
3. Frontend's `_pixelFormat` stays at `0` (0RGB1555, 16-bit, 2 bytes per pixel)
4. `bridge_video_refresh` calls `[g_instance handleVideoData:... format:[g_instance pixelFormat]]` where `pixelFormat` returns `0`
5. `updateFrame` in BaseRunner.swift maps format `0` to `.a1bgr5Unorm` (line 598 of BaseRunner.swift)

### Root Cause E: Swift-side pixel format mapping interprets 32-bit data as 16-bit

**Evidence:** BaseRunner.swift, lines 596-604:

```swift
internal func mapPixelFormat(_ format: Int) -> MTLPixelFormat {
    switch format {
    case 0: return .a1bgr5Unorm // 0RGB1555  <-- WRONG for MAME cores
    case 1: return .bgra8Unorm  // XRGB8888
    case 2: return .b5g6r5Unorm // RGB565
    default: return .bgra8Unorm
    }
}
```

**Visual manifestation:** When 32-bit XRGB8888 pixel data is interpreted as 16-bit 0RGB1555:
- Every two 32-bit source pixels become four 16-bit "pixels"
- Raw color palette indices (which MAME outputs as indices into its internal LUT) are treated as color data
- Colors appear as random noise/garbage because the bit patterns are completely misaligned

### Root Cause F: Hardware rendering readback format mismatch

**Evidence:** LibretroBridge.mm, line 909:
```objc
glReadPixels(0, 0, w, h, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _hwReadbackBuffer);
```

This produces XRGB8888 big-endian data, but the `format` parameter passed to `handleVideoData` is still `[self pixelFormat]`, which may be `0`.

---

## Part 3: Additional Contributing Factors

### Issue: Missing `mame2003-plus_machine_timing` option handling

The MAME2003-plus core has a `machine_timing` option that controls audio skew. If the frontend does not query this via `GET_VARIABLE`, the core defaults to a value that may cause timing anomalies. Currently, `bridge_environment` only hardcodes mupen64plus options — there is no handling for MAME-specific options.

### Issue: FPS clamping masks real values

Some arcade games legitimately run at very low frame rates. Clamping to 60.0 for anything outside the 10-120 range introduces speed errors.

---

## Complete Causal Flow Diagram

```
  EMULATION STARTS
  |
  +-> _avInfo.timing.fps = 60.0 (hardcoded, line 580)
  |
  +-> _pixelFormat = 0 (uninitialized, defaults to 0RGB1555)
  |
  +-> retro_load_game() called
  |    |
  |    +-> Core internally uses XRGB8888 (32-bit, 4 bytes/pixel)
  |    |
  |    +-> Core uses native FPS (e.g., 57.5 Hz for arcade)
  |    |
  |    +-> Core MAY NOT send SET_SYSTEM_AV_INFO -- fps stays at 60.0
  |    |
  |    +-> Core MAY NOT send SET_PIXEL_FORMAT -- format stays at 0
  |
  +-> FRAME LOOP (lines 685-719)
  |    |
  |    +-> retro_run() executes at MAXIMUM CPU speed (unthrottled)
  |    |
  |    +-> Measure elapsed time
  |    |
  |    +-> Sleep only if elapsed < 1/60s (reactive, not proactive)
  |    |
  |    +-> Check audio buffer AFTER frame is already done
  |    |
  |    +-> RESULT: Core runs unthrottled, limited only by NSThread sleep
  |
  +-> VIDEO CALLBACK (line 469)
  |    |
  |    +-> Raw XRGB8888 data (4 bytes/pixel) received from core
  |    |
  |    +-> format=0 passed because _pixelFormat was never set
  |    |
  |    +-> Swift maps format 0 --> .a1bgr5Unorm (2 bytes/pixel)
  |    |
  |    +-> Metal interprets 32-bit data as 16-bit --> SCRAMBLED COLORS
  |
  RESULT: 100x SPEEDUP + GARBAGE COLORS
```

---

## Recommended Fixes (Priority Order)

### Fix 1: Call `retro_get_system_av_info()` after load (SPEED)
After `retro_load_game()` returns successfully, call `_retro_get_system_av_info(&_avInfo)` to query the core's actual timing values. This ensures the FPS and sample rate match the core regardless of whether the core sends `SET_SYSTEM_AV_INFO`.

### Fix 2: Initialize `_pixelFormat` to XRGB8888 as default (COLORS)
Initialize `_pixelFormat = 1` (RETRO_PIXEL_FORMAT_XRGB8888) in the `launchROM` method before `retro_load_game()` is called. Alternatively, explicitly call the environment callback with `RETRO_ENVIRONMENT_SET_PIXEL_FORMAT` from the frontend's side before loading the game.

### Fix 3: Audio-driven frame pacing (SPEED)
Replace the simple sleep-based loop with proper audio-driven pacing. This is the standard libretro "fpsync" approach:
```objc
// BEFORE calling retro_run(), check if we need to wait for audio buffer drain
while (_audioBuffer->available() > threshold) {
    [NSThread sleepForTimeInterval:0.0005]; // Small sleep to avoid busy-wait
}
_retro_run();
```
Let the audio buffer fill level dictate when to produce the next frame.

### Fix 4: Implement pre-run frame delay accumulator (SPEED)
Use a frame time accumulator to control when `retro_run()` is called:
```objc
static double accumulated_error = 0;
double ideal_frame_time = 1.0 / fps;
accumulated_error += ideal_frame_time - (current_time - last_time);
if (accumulated_error >= ideal_frame_time) {
    _retro_run();
    accumulated_error -= ideal_frame_time;
}
```

### Fix 5: Handle MAME-specific core options (SPEED)
Add MAME-specific handling in `bridge_environment` for `mame2003-plus_machine_timing` and similar timing-related options.

---

## Files Affected

| File | Area | Issue |
|------|------|-------|
| TruchieEmu/Engine/LibretroBridge.mm | ~line 109 | `_pixelFormat` declared but never initialized, defaults to 0 |
| TruchieEmu/Engine/LibretroBridge.mm | 402-437 | SET_SYSTEM_AV_INFO callback only updates when core sends it |
| TruchieEmu/Engine/LibretroBridge.mm | 580-581 | FPS hardcoded to 60.0 during launchROM |
| TruchieEmu/Engine/LibretroBridge.mm | 685-719 | Sleep-based loop without proactive throttling |
| TruchieEmu/Engine/LibretroBridge.mm | line 469 | `format:[self pixelFormat]` passes uninitialized value to video callback |
| TruchieEmu/Engine/LibretroBridge.mm | line 909 | glReadPixels with GL_BGRA produces data that may not match pixelFormat |
| TruchieEmu/Engine/Runners/BaseRunner.swift | 596-604 | `mapPixelFormat` maps format 0 to .a1bgr5Unorm |

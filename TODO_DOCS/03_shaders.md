# Design Document: Shader Subsystem & Post-Processing Pipeline

> **Implementation Status**: Phase 1-3 Complete (Core Infrastructure + Custom Shaders)
> - [x] ShaderPreset model system
> - [x] ShaderManager service
> - [x] SLANGP Parser for Libretro presets
> - [x] Custom Metal shaders (CRT, LCD Grid, Vibrant LCD, Edge Smooth, Composite, Passthrough)
> - [x] Shader preset picker UI
> - [x] HUD integration
> - [ ] Multi-pass rendering pipeline
> - [ ] Libretro shader bundling (slang-shaders repo)
> - [ ] SPIRV-Cross integration for Vulkan->Metal conversion

## 1. Objective

To implement a robust post-processing pipeline that supports both custom high-performance shaders (like the provided Metal CRT filter) and the industry-standard **Libretro Shader Preset (.slangp/.glslp)** ecosystem.

---

## 2. Integration of Existing Libretro Shaders

Libretro maintains the gold standard of shaders in the [slang-shaders](https://github.com/libretro/slang-shaders) (Vulkan/Metal/D3D12) and [glsl-shaders](https://github.com/libretro/glsl-shaders) (OpenGL) repositories.

### A. The "Preset" Logic

Libretro shaders aren't just single files; they are **Presets** (`.slangp` or `.glslp`).

- **Multi-pass:** A preset defines a chain of shaders (e.g., Blur -> Glow -> CRT Scanlines).
- **Scaling:** Presets define how each pass scales (e.g., Pass 1 at 2x resolution, Pass 2 at screen resolution).
- **Parameters:** Presets define the float values for uniforms (like `scanlineIntensity`).

### B. Implementation Strategy for your Frontend

1. **Parser:** Write a simple parser for `.slangp` files (it’s essentially a `.ini` format).
2. **Shader Library:** Download the [libretro/slang-shaders](https://github.com/libretro/slang-shaders) repository into your `assets/shaders/` folder.
3. **Cross-Compilation:** If you are strictly using **Metal**, you can use [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) to convert Libretro’s `.slang` (Vulkan) shaders into Metal `.metal` source code at runtime or build time.

---

## 3. Custom Metal Shader Suite (New Designs)

Based on your `fragmentCRT` structure, here are designs for system-specific and general-purpose filters.

### A. The "Handheld Grid" (GB/GBC/GG)

*Specific for: Game Boy, Game Gear.*

- **Logic:** Instead of horizontal scanlines, it needs a 2D "LCD Grid" (small black gaps between pixels) and "Motion Blur" (ghosting).
- **Uniforms:** `gridOpacity`, `ghostingAmount`.
- **Metal Implementation Tip:** Use `fmod(in.position.xy, grid_size)` to drop the brightness of the pixel borders to simulate the classic non-backlit LCD.

### B. The "Vibrant LCD" (GBA/PSP)

*Specific for: Game Boy Advance.*

- **Logic:** The original GBA had a dark screen, so games were mastered with overly bright colors. On modern screens, they look "washed out." This shader should apply a gamma-correction curve and a color matrix to saturate the reds and greens specifically.
- **Uniforms:** `saturationAmount`, `internalGamma`.

### C. The "Smoothing Upscaler" (General/RPG)

*Best for: 2D games like Chrono Trigger or Final Fantasy.*

- **Logic:** Implement an **Edge-Directed Interpolation** (similar to xBRZ or ScaleFX). It detects diagonal edges in the pixel art and smooths them without making the whole image blurry like Bilinear filtering does.

### D. The "Composite/VHS" (NES/Sega Genesis)

*Best for: Games that relied on "dithering" to create colors (like Sonic water).*

- **Logic:** Intentionally blur the horizontal axis significantly more than the vertical axis. This causes dithered patterns (checkerboards) to "bleed" into solid colors, which is how they were intended to look on old 1980s TVs.

---

## 4. Proposed Shader Directory Structure

To keep your frontend organized, use this hierarchy:

```text
/shaders/
    /internal/          <-- Your custom Metal shaders
        CRTFilter.metal
        LCDGrid.metal
        Upscaler.metal
    /slang/             <-- Cloned from libretro/slang-shaders
        /crt/
        /handheld/
        /presets/       <-- The .slangp files users select
```

---

## 5. Uniform Mapping API

Your frontend needs to bridge the Libretro Core to the Metal Shader. You must define a standard `Uniforms` struct that your frontend fills every frame:

| Variable | Description |
| :--- | :--- |
| `u.time` | Incremented every frame (used for "static" or "water ripple" effects). |
| `u.colorBoost` | Global brightness multiplier. |
| `u.barrelAmount` | Curvature for CRT. |
| `u.scanlineIntensity`| Opacity of the scanline overlay. |
| `SourceSize` | (Libretro Standard) A `float4` containing `(width, height, 1/width, 1/height)` of the input texture. |
| `OutputSize` | (Libretro Standard) A `float4` of the viewport/window size. |

---

## 6. UI Implementation: The "Shader Selector"

1. **Global Toggle:** A switch to enable/disable post-processing.
2. **Preset Browser:** A list of folders (`CRT`, `LCD`, `Smoothing`) that lets users select a `.metal` or `.slangp` file.
3. **Live Tweaking:** While the game is running, provide sliders for every `float` in your `Uniforms` struct.
    - *UX Tip:* In Metal, you can use a "Buffer" to update these uniforms instantly without recompiling the shader, providing real-time feedback as the user moves a slider.

## 7. Recommended Libretro Shaders to Include

If you want to bundle "The Best" of Libretro for your users, include these specific presets:

1. **CRT-Geom:** The most balanced, compatible CRT shader.
2. **CRT-Royale:** The most advanced (but heavy) CRT shader for high-end PCs.
3. **LCD-Grid-V2:** Perfect for handheld systems.
4. **xBRZ-Freepass:** The best for making 2D pixel art look "high res."
5. **Bezel-Reflections:** Adds a TV frame around the game and reflects the game light onto the "plastic" bezel.

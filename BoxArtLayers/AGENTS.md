# AGENTS.md — BoxArtLayers

Read this file before the Swift sources. It is the source of truth for intent, invariants, and known failures. Do not reverse-engineer the package unless you are changing behavior.

## What this is

Standalone Swift package (not part of TruchieEmu). **Image in → layer masks out** for game box art, so a compositor can:

1. Freeze the main character (`hero`) and title (`title`) and hardware chrome (`chrome`).
2. Run a holographic / warp shader **only** on the sky (`background`).
3. Run a second effect on secondary objects (`midground` instances) in parallel.

It does **not** produce a usable 3D mesh. It does **not** use physical depth as an alpha.

## Non-negotiable invariants

1. **Heatmap is a ranker, not a cut.** Never threshold `frontnessMap` (or Depth Anything, or Depth Pro) into the hero/title alpha. Photo-depth models treat printed art as a flat poster (see Illustrator’s Depth, CVPR 2026, arXiv 2511.17454). Hard masks come from instances / OCR / heuristics; the heatmap only ranks those regions and may drive warp *amplitude inside* `masks.background`.
2. **Compositor stack, back → front:** `background → midground → title → hero → chrome`. Title sits *under* the hero so overlapping hands/tails are correct without punching a hole in the logo.
3. **All exported images are full-frame**, same pixel size as the source. Transparent PNG cutouts are source RGB with the role’s alpha — they stack with `object-fit: cover` / identical frames.
4. **Pixel origin is top-left**, same as PNG / `CGImage`. Vision `CVPixelBuffer` is also top-left. **Do not** round-trip masks through `CIContext.render(toBitmap:)` — Core Image is Y-up and previously flipped every output (looked like vertical + horizontal flip; spine text appeared mirrored). Rasterization goes through `vImageBuffer_InitWithCGImage` (RGBA) and direct pixel-buffer sampling (masks).
5. **Load path bakes EXIF** via `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceCreateThumbnailWithTransform`. Vision is always called with `orientation: .up`.
6. **Public product is `LayerBundle`.** Swap the analyzer (Vision → SAM2 / LayerD / Core ML depth) without changing `LayerBundle`, `LayerMasks`, `LayerRole`, or `LayerManifest.version` unless the contract actually changes. Bump `manifest.version` if you change JSON meaning.

## Public API (consumer)

```swift
import BoxArtLayers

let bundle = try await BoxArtDecomposer().decompose(cgImage)
// also: NSImage / UIImage / URL via overloads

bundle.masks.hero        // grayscale alpha CGImage
bundle.cutouts.hero      // RGBA, transparent outside role
bundle.frontnessMap      // grayscale 0=back 1=front — NOT an alpha
bundle.masks.frozen      // hero ∪ title ∪ chrome
bundle.instances         // per-object masks + role + frontness
bundle.manifest          // Codable JSON
bundle.preview           // tinted debug: red hero, yellow title, green mid, blue sky, gray chrome

try LayerExporter.write(bundle, to: directory)
```

Platforms: macOS 14, iOS 17, tvOS 17 (`VNGenerateForegroundInstanceMaskRequest`).

CLI: `swift run boxart-layers <image> [out-dir]`  
Fixture: `Fixtures/super-mario-advance-4.png` (GBA SMA4).

## File map

| File | Role |
| --- | --- |
| `BoxArtDecomposer.swift` | Public entry. `Task.detached` → analyze → assign → pack `LayerBundle`. |
| `LayerTypes.swift` | Public types only. |
| `Configuration.swift` | Thresholds: hero area 6–50%, title band y∈[0, 0.55] top-left, chrome left ≤14%, mask threshold 28. |
| `VisionAnalyzer.swift` | Vision: subject lifting, attention + objectness saliency, OCR. Converts Vision bboxes (origin **bottom-left**, normalized) to top-left pixel rects. |
| `ImageIOSupport.swift` | Load/save PNG, RGBA via vImage (`byteOrder32Big` + `premultipliedLast`), masks from `CVPixelBuffer` (bilinear upsample if saliency is ~68×68). |
| `ChromeDetector.swift` | Low-saturation left spine (GBA/DS bar) + OCR keywords (`nintendo`, `game boy`, `esrb`, …) only if the box is in spine / bottom-left / bottom-right badge zones. |
| `InstanceSplitter.swift` | If one Vision instance covers > `heroMaxAreaRatio` (50%), split by frontness percentile so the character is the hot core, not the landscape. |
| `LayerAssigner.swift` | Role assignment (see below). Sky/background = else-bucket: everything not hero/title/chrome/midground, matching the preview blue. |
| `PreviewRenderer.swift` | Debug tint overlay. |
| `LayerExporter.swift` | `source.png`, `frontness.png`, `preview.png`, `masks/*.png`, `cutouts/*.png`, `manifest.json`. |
| `PlatformImage.swift` | NSImage / UIImage wrappers. |
| `BoxArtLayersCLI/main.swift` | Thin CLI. |

Internal working format: `MaskBuffer` — `[UInt8]` grayscale, row 0 = top, index `y * width + x`.

## Pipeline

```
CGImage (EXIF baked, .up)
  ├─ VNGenerateForegroundInstanceMaskRequest  → per-instance full-res masks
  ├─ VNGenerateAttentionBasedSaliencyImageRequest + objectness → frontness heatmap
  ├─ VNRecognizeTextRequest (.accurate, no language correction)
  └─ ChromeDetector (left spine + keyword OCR)
        ↓
  InstanceSplitter.explode oversized blobs using frontness
        ↓
  LayerAssigner
        ↓
  LayerBundle + optional LayerExporter
```

## Role assignment (LayerAssigner)

Order matters:

1. Instances overlapping chrome ≥65% → `chrome`.
2. **Hero** = remaining instance with highest `frontness * 2 + areaRatio`, ignoring specks `< 4%` area. Prefer centroids below the title band so a logo blob does not beat Mario.
3. **Title** = OCR boxes in the top 55% whose text is not chrome and not promotional (`bonus`, `link it up`, `e-reader`, `game pak`, …), dilated, unioned with remaining wide instances in that band.
4. Everything else → `midground`.
5. Subtract chrome, then hero, then title from the layers below them.
6. **Background / sky** = full frame minus hero/title/chrome. Midground is NOT subtracted: we ignore midground and keep it as part of the background, so it shares the background's holo treatment. (This differs from the preview's blue else-bucket, which also excludes midground.)

Hero score is **frontness-dominant**, not largest-area. After a split, the leftover landscape is often 50%+ of the image and would steal `hero` if scored by area.

## Current quality (on-device Vision)

This backend is a **first split**, not production silhouettes.

On `Fixtures/super-mario-advance-4.png` after the orientation fix:

- Chrome (GBA bar, ESRB, Nintendo) is the reliable layer.
- Hero is an ~12% high-saliency **blob** over Mario, not the raccoon outline. Cause: Vision subject-lifting returns **one instance covering most of the painting**; we carve a core from a **low-resolution saliency map**. Edges look blocky.
- Title OCR often gets `SUPER MARIO ADV…` and misses the stylized 3D `SUPER MARIO BROS. 3` logo.
- Midground is “the rest of the painting,” not clean Luigi / hills / pipe instances.
- `manifest.quality.needsReview` is false on that sample (hero area in range, some title pixels exist). That gate does **not** mean the masks are compositor-ready.

Better peelers when you outgrow Vision (keep `LayerBundle`):

- **LayerD** (ICCV 2025, CyberAgent) — graphic-design top-layer matting, text first. Closest open peeler for posters.
- **SAM2 + Grounding DINO** — text prompts `main character`, `game title logo`. Hard instance masks.
- **Illustrator’s Depth** (CVPR 2026) — layer *index*, not meters. Weights were “code coming soon”; replace the ranker when available.

## What to change vs what not to touch

**Safe to change:** `VisionAnalyzer`, `InstanceSplitter`, `LayerAssigner` heuristics, `Configuration` defaults, saliency upsample.

**Do not casually change:** `LayerBundle` / `LayerRole` / exporter filenames / top-left contract / “heatmap is not an alpha.”

**If adding a backend:** introduce a protocol that returns the internal `SceneAnalysis` (instances + text + frontness + chrome hint). `BoxArtDecomposer.run` already has that seam conceptually; it is not yet a public protocol.

## Tests

`swift test` — mask math, chrome spine on a synthetic grey bar, assigner, **orientation** (`ImageOrientationTests`): left column of SMA4 must be desaturated GBA metal, top-center must be warm sky. If that test fails, coordinate space is broken again.

## Integration note (TruchieEmu)

This package must not import the emulator. The host app: add local SPM package → `import BoxArtLayers` → feed box-art `CGImage` → drive hologram with `masks.background` and freeze with `masks.frozen`.

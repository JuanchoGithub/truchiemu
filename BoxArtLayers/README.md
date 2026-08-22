# BoxArtLayers

Independent Swift package: **image in → layer masks out**. Built to drop into a Swift app (for example TruchieEmu) without taking a dependency on that app.

**If you are an LLM inheriting this repo, read [`AGENTS.md`](AGENTS.md) first.** It is the architecture, coordinate-space rules, and known failure modes. Do not spend context reverse-engineering the Swift until you need to change behavior.

It produces hard compositing masks plus a soft frontness heatmap so a holographic shader can warp only the sky, a second effect can run on mid-ground objects, and the main character / title stay frozen.

## What you get

| Output | Use |
| --- | --- |
| `masks.hero` / `cutouts.hero` | Frozen character overlay |
| `masks.title` / `cutouts.title` | Frozen logo, stacked *under* the hero |
| `masks.midground` + `instances` | Per-object FX (Luigi, pipes, hills) |
| `masks.background` | Holographic bus — sky only |
| `masks.chrome` | Hardware bar, ESRB, publisher marks |
| `masks.frozen` | Hero ∪ title ∪ chrome |
| `frontnessMap` | Soft heatmap for ranking / sky amplitude — **not** an alpha |
| `preview` | Tinted debug overlay |
| `manifest.json` | Boxes, roles, quality flags |

Stack back-to-front: `background → midground → title → hero → chrome`.

## Requirements

- macOS 14+, iOS 17+, or tvOS 17+ (`VNGenerateForegroundInstanceMaskRequest`)
- On-device only: Apple Vision subject lifting + saliency + OCR. No Python, no network.

## Add to your app

In Xcode: **File → Add Package Dependencies… → Add Local…** and select this folder. Link the `BoxArtLayers` library to your target.

```swift
import BoxArtLayers
import CoreGraphics

let decomposer = BoxArtDecomposer()
let layers = try await decomposer.decompose(boxArtImage) // CGImage, NSImage, or UIImage

// Hologram samples only the sky:
let skyMask = layers.masks.background
let skyHeat = layers.frontnessMap

// Object FX:
let moving = layers.instances.filter { $0.role == .midground }

// Never warp these:
let frozen = layers.masks.frozen

if layers.manifest.quality.needsReview {
    // hero too small/large, missing title, or no instances
}
```

Write a folder of PNGs (same layout the CLI uses):

```swift
try LayerExporter.write(layers, to: outputDirectory)
```

## Test from the command line

```bash
swift run boxart-layers /path/to/cover.png ./Output
```

Writes `masks/`, `cutouts/`, `frontness.png`, `preview.png`, and `manifest.json`.

A GBA sample lives at `Fixtures/super-mario-advance-4.png`:

```bash
swift run boxart-layers Fixtures/super-mario-advance-4.png ./Output
```

## How it decides front vs back

The heatmap is a **ranker**, not a cut. Vision lifts instances; OCR + a left-spine detector label title and chrome; oversized blobs are split by saliency; hero is the highest-**frontness** instance (not the largest leftover landscape). Sky is low-saliency pixels, not “whatever the instance mask did not cover.”

That matches how a holographic compositor actually works: binary alphas for freeze/warp, a soft map only inside the sky mask.

Physical depth models (Depth Anything, Depth Pro) treat printed art as a flat poster. If you later drop in [Apple’s Depth Anything V2 Core ML model](https://huggingface.co/apple/coreml-depth-anything-v2-small) or a SAM2/LayerD sidecar, keep this `LayerBundle` and only replace the ranker — do not threshold a heatmap into the hero alpha.

## Quality gates

`manifest.quality.needsReview` is set when:

- no instances were lifted
- hero area is under 6% or over 50% of the image
- no title pixels were found

Use that to skip the hologram or queue a cover for inspection when running thousands of box arts.

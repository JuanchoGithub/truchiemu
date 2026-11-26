import SwiftUI
import AppKit
import Foundation
import os.lock

// MARK: - Etch tiles

// The foil's etch texture is a bundled grayscale `holo_*.png` diffraction
// sheet, tiled at a card-relative cell size. `HoloFoilLight.metal` reads its
// luminance as a height field, so the tile only has to be drawn once per
// (pattern, size, cell size) — the cursor never re-renders it.
//
// The image is built with a drawing handler, so it stays resolution
// independent: SwiftUI rasterizes it at the display's scale when it becomes a
// shader layer, and the etch stays crisp on Retina.
@MainActor
final class HoloEtchTileCache {
    static let shared = HoloEtchTileCache()

    private struct Key: Hashable {
        let pattern: HoloPattern
        let width: Int
        let height: Int
        let cell: Int
    }

    private var tiles: [Key: NSImage] = [:]
    private var order: [Key] = []
    private let limit = 12

    func tile(for pattern: HoloPattern, size: CGSize, cellScale: CGFloat) -> NSImage? {
        guard size.width > 4, size.height > 4 else { return nil }
        HoloSwiftCacheCoordinator.shared.noteUsage()

        let key = Key(
            pattern: pattern,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            cell: Int((cellScale * 1000).rounded())
        )
        if let cached = tiles[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return cached
        }

        guard let base = HoloPatternStore.shared.image(for: pattern),
              let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return nil }

        // Cell size relative to the card, keeping the texture's own aspect.
        let cellW = max(6.0, size.width * cellScale)
        let cellH = max(6.0, cellW * CGFloat(cg.height) / CGFloat(cg.width))
        let source = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))

        let image = NSImage(size: NSSize(width: size.width, height: size.height), flipped: true) { rect in
            var y: CGFloat = 0
            while y < rect.height {
                var x: CGFloat = 0
                while x < rect.width {
                    source.draw(
                        in: NSRect(x: x, y: y, width: cellW, height: cellH),
                        from: NSRect(x: 0, y: 0, width: cg.width, height: cg.height),
                        operation: .copy,
                        fraction: 1.0
                    )
                    x += cellW
                }
                y += cellH
            }
            return true
        }

        tiles[key] = image
        order.append(key)
        if order.count > limit { tiles[order.removeFirst()] = nil }
        return image
    }

    func flush() {
        tiles.removeAll()
        order.removeAll()
    }
}

// MARK: - Foil surface

// One physically-lit foil sheet. The view's content is the etch texture; the
// layer effect derives a normal from it and lights it, so the foil reacts to
// the pointer and the card tilt like a real sheet of holographic paper.
struct HoloFoilSurface: View, Equatable {
    let pattern: HoloPattern
    let colourway: HoloFoilColourway
    /// Light direction in tangent space (-1…1 on each axis, +y downward).
    let lightX: Double
    let lightY: Double
    /// Thin-film spectrum phase, moved by the pointer.
    let huePhase: Double
    let w: CGFloat
    let h: CGFloat
    let intensity: Double

    var body: some View {
        Group {
            if let tile = HoloEtchTileCache.shared.tile(
                for: pattern,
                size: CGSize(width: w, height: h),
                cellScale: colourway.etchScale
            ) {
                Image(nsImage: tile)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: w, height: h)
                    .layerEffect(
                        Shader(
                            function: ShaderLibrary.holoFoilLight,
                            arguments: [
                                .float4(
                                    Float(lightX),
                                    Float(lightY),
                                    Float(colourway.specularPower),
                                    Float(intensity)
                                ),
                                .float4(
                                    Float(huePhase),
                                    Float(colourway.hueSpread),
                                    Float(colourway.saturation),
                                    Float(colourway.relief)
                                ),
                                .float4(
                                    Float(w),
                                    Float(h),
                                    Float(colourway.coverage),
                                    Float(colourway.edgeGain)
                                ),
                                .float4(
                                    Float(colourway.glare),
                                    0,
                                    0,
                                    0
                                ),
                                .color(colourway.tint)
                            ]
                        ),
                        maxSampleOffset: CGSize(width: 2, height: 2)
                    )
            }
        }
        .compositingGroup()
    }
}

// MARK: - Holo foil (region stack)

// Composes the foil over the box art. The light model is shared by every
// variant and every region; the variant only changes the material
// (`HoloFoilColourway`) and the reverse holo additionally foils the whole
// card instead of the decomposed regions.
//
// The layers are composited with `.screen`, which can only lighten the art —
// a holographic print reflects light, it never darkens the image below it.
struct HoloFoilLayers: View, Equatable {
    let masks: HoloMaskSet?
    let settings: HoloSettingsSnapshot
    let w: CGFloat
    let h: CGFloat
    /// Normalized cursor X (0…1) within the artwork. Moves the light.
    let pointerX: CGFloat
    /// Normalized cursor Y (0…1) within the artwork. Moves the light.
    let pointerY: CGFloat
    /// Card tilt in degrees about X (top rises when negative).
    var tiltX: Double = 0
    /// Card tilt in degrees about Y (left rises when negative).
    var tiltY: Double = 0
    /// Whether the card is currently hovered. The parent gates the whole
    /// layer off when false, so this only feeds per-card intensity damping.
    var isHovered: Bool = false

    var body: some View {
        let randomization = settings.randomization
        let variant = randomization?.variant ?? .regularHolo
        let colourway = variant.colourway(
            settings: settings,
            hueOffset: randomization?.hueOffset ?? 0
        )
        let light = lightVector
        let hue = huePhase

        ZStack {
            if variant == .reverseHolo {
                // Reverse holo foils the whole card — no region split.
                let pattern = settings.reverseTexturePattern ?? variant.sourceFoilPattern
                HoloFoilSurface(
                    pattern: pattern,
                    colourway: colourway,
                    lightX: light.dx,
                    lightY: light.dy,
                    huePhase: hue,
                    w: w,
                    h: h,
                    intensity: colourway.intensity
                )
                .blendMode(.screen)
            } else if let masks {
                region(.background, mask: masks.background, variant: variant, colourway: colourway, light: light, hue: hue, randomization: randomization)
                region(.title, mask: masks.title, variant: variant, colourway: colourway, light: light, hue: hue, randomization: randomization)
                region(.chrome, mask: masks.chrome, variant: variant, colourway: colourway, light: light, hue: hue, randomization: randomization)
                region(.hero, mask: masks.hero, variant: variant, colourway: colourway, light: light, hue: hue, randomization: randomization)
            }
        }
        .frame(width: w, height: h)
    }

    // One decomposed region's foil, clipped to that region's alpha mask.
    @ViewBuilder
    private func region(
        _ region: HoloRegion,
        mask: NSImage?,
        variant: HoloVariant,
        colourway: HoloFoilColourway,
        light: CGVector,
        hue: Double,
        randomization: HoloCardRandomization?
    ) -> some View {
        if let mask, randomization?.active(region) ?? true {
            HoloFoilSurface(
                pattern: randomization?.pattern(region) ?? variant.sourceFoilPattern,
                colourway: colourway,
                lightX: light.dx,
                lightY: light.dy,
                huePhase: hue,
                w: w,
                h: h,
                intensity: colourway.intensity * (randomization?.intensity(region) ?? 1)
            )
            .mask(maskView(mask, w: w, h: h))
            .blendMode(.screen)
        }
    }

    @ViewBuilder
    private func maskView(_ mask: NSImage, w: CGFloat, h: CGFloat) -> some View {
        Image(nsImage: mask)
            .resizable()
            .scaledToFill()
            .frame(width: w, height: h)
            .clipped()
    }

    /// Directional light for the foil, in tangent space. The pointer pushes
    /// the light sideways; the card tilt tips the sheet into a fixed light,
    /// which is what makes the highlight travel while the card rotates.
    private var lightVector: CGVector {
        let cursorX = (pointerX - 0.5) * 2
        let cursorY = (pointerY - 0.5) * 2
        let tiltLightX = tiltY / 10.0
        let tiltLightY = tiltX / 10.0
        let dx = cursorX * settings.cursorInfluence + tiltLightX * settings.tiltInfluence
        let dy = cursorY * settings.cursorInfluence + tiltLightY * settings.tiltInfluence
        return CGVector(
            dx: min(max(dx, -1.4), 1.4),
            dy: min(max(dy, -1.4), 1.4)
        )
    }

    /// Thin-film phase. `hueCycles` full spectrum rotations happen as the
    /// pointer crosses the card, so the rainbow visibly flows.
    private var huePhase: Double {
        (Double(pointerX) * 0.35 + Double(pointerY) * 0.35) * settings.hueCycles
    }
}

// MARK: - Pointer sheen

// The gloss over the foil: a soft specular bloom that tracks the pointer and
// only ever lightens. Deliberately small and neutral — the etched foil below
// is the effect; this is the wet look of the card's top coat.
struct HoloSheenEffect: View {
    let pointerX: CGFloat
    let pointerY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = min(w, h) * 0.55

            RadialGradient(
                stops: [
                    .init(color: Color.white.opacity(0.16), location: 0.0),
                    .init(color: Color.white.opacity(0.06), location: 0.45),
                    .init(color: Color.white.opacity(0.0), location: 1.0)
                ],
                center: UnitPoint(x: pointerX, y: pointerY),
                startRadius: 0,
                endRadius: radius
            )
            .frame(width: w, height: h)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Simple RNG for glitter

struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    init(seed: UInt32) {
        self.init(seed: UInt64(seed))
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return z
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

// MARK: - Swift-engine cache coordinator

// Bounds the native holo engine's caches. The etch tiles are the largest
// footprint, so they are dropped after a short idle window — peak memory
// returns to near-zero when the user isn't hovering holo cards.
final class HoloSwiftCacheCoordinator {
    static let shared = HoloSwiftCacheCoordinator()

    private let lock = OSAllocatedUnfairLock<Date>(initialState: .distantPast)
    private var timer: DispatchSourceTimer?
    private let checkInterval: TimeInterval = 5
    private let idleThreshold: TimeInterval = 8

    private init() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + checkInterval, repeating: checkInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    // Called from the Swift-engine render hot paths so the "last active"
    // timestamp stays fresh while a card is hovered — preventing a flush
    // mid-hover.
    func noteUsage() {
        lock.withLock { $0 = Date() }
    }

    private func tick() {
        guard Date().timeIntervalSince(lock.withLock { $0 }) >= idleThreshold else { return }
        flushAll()
    }

    // Reclaim every Swift-engine cache. Safe to call from the main thread (the
    // idle timer and the game-launch hook both run there).
    func flushAll() {
        MainActor.assumeIsolated {
            HoloEtchTileCache.shared.flush()
            HoloPatternStore.shared.flush()
        }
        // Largest native-engine footprint: full-res region mask NSImages.
        HoloSaliencyService.shared.flush()
    }
}

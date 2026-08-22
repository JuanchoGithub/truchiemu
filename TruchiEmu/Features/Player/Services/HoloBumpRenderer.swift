import AppKit
import Metal
import simd

/// Swift wrapper around `HoloBump.metal`. Owns its own lazy `MTLDevice` +
/// `MTLCommandQueue` (the renderer runs in the library grid where no game
/// is launched, so it can't borrow from the existing `MetalCoordinator`).
///
/// **Performance model:** every render is dispatched to a serial background
/// queue (`renderQueue`) and the resulting `NSImage` is handed back via a
/// completion closure on the main thread. The SwiftUI view that displays the
/// bump only re-requests a render when the *bucketed* inputs change (see
/// `HoloBumpImageView`), so the main thread is never blocked by the GPU
/// pass, the `waitUntilCompleted()` sync, or the CPU readback — even while
/// the cursor moves across a card at high event rates.
///
/// The bump shader derives per-pixel normals from the mask itself via
/// finite-differences, so no separate normal-map texture/pass is needed.
///
/// The renderer is intentionally NOT `@MainActor`: Metal objects are
/// thread-safe to encode command buffers from, and all renderer state
/// (caches) is touched exclusively on `renderQueue`, so there are no races.
final class HoloBumpRenderer {
    static let shared = HoloBumpRenderer()

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private let renderQueue = DispatchQueue(label: "HoloBump.Render", qos: .userInteractive)

    // Accessed only on `renderQueue`, so no extra locking is required.
    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 48
    private var foilTextureCache: [String: MTLTexture] = [:]
    private let foilCacheLimit = 16

    private init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        rebuildPipeline()
    }

    private func rebuildPipeline() {
        guard let device else { return }
        guard let library = try? device.makeDefaultLibrary(bundle: .main) else { return }
        guard let vfn = library.makeFunction(name: "vertexHoloBump"),
              let ffn = library.makeFunction(name: "fragmentHoloBump") else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "HoloBump"
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Asynchronously renders the bump foil for one region and returns the
    /// result via `completion` on the main thread. The heavy Metal work runs
    /// on `renderQueue`, never blocking the UI. The caller passes the
    /// already-resolved mask `NSImage` (fetched on the main thread from
    /// `HoloPatternStore`) so this method has no MainActor dependency.
    ///
    /// - Parameters:
    ///   - foilNSImage: the pre-rendered holographic foil tile (rainbow +
    ///     diffraction-grating), tiled to `size`. This is the actual foil
    ///    texture; the shader derives both the relief and the colour from it.
    ///   - foilKey: stable key (pattern + variant) used to cache the uploaded
    ///     GPU texture across renders.
    ///   - size: region size in points (the foil is a soft low-frequency
    ///     glow, so it's rendered at a capped resolution and upscaled).
    ///   - cursorX, cursorY: normalised 0..1 cursor within the artwork.
    ///   - tiltX, tiltY: card tilt in degrees.
    ///   - specularPower: 16..64, higher = sharper highlights.
    ///   - intensity: 0..1, multiplied into the shine.
    ///   - hueShiftDegrees: phase offset for the iridescent rainbow.
    ///   - saturation: 0..1, rainbow saturation.
    ///   - cursorInfluence, tiltInfluence: 0..1, light-direction weighting.
    func renderBump(
        foilNSImage: NSImage,
        foilKey: String,
        size: CGSize,
        cursorX: CGFloat,
        cursorY: CGFloat,
        tiltX: Double,
        tiltY: Double,
        specularPower: Double,
        intensity: Double,
        hueShiftDegrees: Double,
        saturation: Double,
        cursorInfluence: Double,
        tiltInfluence: Double,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let device, let commandQueue, let pipelineState else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        // Capture the inputs; the work happens off the calling thread.
        renderQueue.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion(nil) }; return }
            let result = self._render(
                foilNSImage: foilNSImage,
                foilKey: foilKey,
                size: size,
                cursorX: cursorX, cursorY: cursorY,
                tiltX: tiltX, tiltY: tiltY,
                specularPower: specularPower, intensity: intensity,
                hueShiftDegrees: hueShiftDegrees, saturation: saturation,
                cursorInfluence: cursorInfluence, tiltInfluence: tiltInfluence,
                device: device, commandQueue: commandQueue, pipelineState: pipelineState
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Off-queue render core

    private func _render(
        foilNSImage: NSImage,
        foilKey: String,
        size: CGSize,
        cursorX: CGFloat,
        cursorY: CGFloat,
        tiltX: Double,
        tiltY: Double,
        specularPower: Double,
        intensity: Double,
        hueShiftDegrees: Double,
        saturation: Double,
        cursorInfluence: Double,
        tiltInfluence: Double,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState
    ) -> NSImage? {
        // Render at the full display resolution so the foil texture (and its
        // fine rainbow/scanline relief) stays as crisp as the parallax foil it
        // sits under. The previous 200px cap made the bump blurry/low-res
        // next to the sharp parallax layer — the resolution mismatch was
        // visibly wrong. Bound the longest side only to keep the GPU pass
        // sane for very large cards.
        let maxDim = 1024
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        let longest = max(Double(size.width), Double(size.height))
        let scale = min(1.0, Double(maxDim) / longest)
        let width = max(1, Int((size.width * CGFloat(scale)).rounded()))
        let height = max(1, Int((size.height * CGFloat(scale)).rounded()))

        let key = "\(width)x\(height)|" +
            "\(cursorX.coarseBucketed)|\(cursorY.coarseBucketed)|" +
            "\(tiltX.coarseBucketed)|\(tiltY.coarseBucketed)|" +
            "\(specularPower.bucketed)|\(intensity.bucketed)|" +
            "\(hueShiftDegrees.coarseBucketed)|\(saturation.bucketed)|" +
            "\(cursorInfluence.bucketed)|\(tiltInfluence.bucketed)"
        if let cached = cache[key] {
            return cached
        }

        // Reuse the foil texture across renders (its contents depend only on
        // pattern + variant + size), so we don't re-decode + re-upload it.
        let foilKeyStr = "\(foilKey)|\(width)x\(height)"
        let foilTexture: MTLTexture?
        if let cachedFoil = foilTextureCache[foilKeyStr] {
            foilTexture = cachedFoil
        } else {
            guard let foilCG = foilNSImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let tex = makeTexture(from: foilCG, device: device) else { return nil }
            if foilTextureCache.count >= foilCacheLimit { foilTextureCache.removeAll() }
            foilTextureCache[foilKeyStr] = tex
            foilTexture = tex
        }
        guard let foilTexture else { return nil }

        let outDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        outDescriptor.usage = [.renderTarget, .shaderRead]
        outDescriptor.storageMode = .shared
        guard let outTexture = device.makeTexture(descriptor: outDescriptor) else { return nil }

        let ax = Float(tiltX * .pi / 180)
        let ay = Float(tiltY * .pi / 180)
        let r00 = cos(ay)
        let r01 = sin(ay) * sin(ax)
        let r02 = sin(ay) * cos(ax)
        let r10: Float = 0
        let r11 = cos(ax)
        let r12 = -sin(ax)
        let r20 = -sin(ay)
        let r21 = cos(ay) * sin(ax)
        let r22 = cos(ay) * cos(ax)
        let tiltMatrix = simd_float4x4(columns: (
            SIMD4(r00, r01, r02, 0),
            SIMD4(r10, r11, r12, 0),
            SIMD4(r20, r21, r22, 0),
            SIMD4(0, 0, 0, 1)
        ))

        let tiltedLight = SIMD3<Float>(r02, r12, r22)
        let cursorOffset = SIMD3<Float>(
            Float((cursorX - 0.5) * cursorInfluence),
            Float((cursorY - 0.5) * cursorInfluence),
            0
        )
        let tiltedWithCursor = simd_normalize(tiltedLight + cursorOffset)
        let restLight = SIMD3<Float>(0, 0, 1)
        let blendedLight = simd_normalize(
            simd_mix(restLight, tiltedWithCursor, SIMD3<Float>(repeating: Float(tiltInfluence)))
        )

        var uniforms = HoloBumpUniforms(
            tiltMatrix: tiltMatrix,
            lightDir: blendedLight,
            pointerX: Float(cursorX),
            pointerY: Float(cursorY),
            cursorInfluence: Float(cursorInfluence),
            tiltInfluence: Float(tiltInfluence),
            specularPower: Float(specularPower),
            intensity: Float(intensity),
            hueShiftDegrees: Float(hueShiftDegrees),
            saturation: Float(saturation)
        )

        guard let buffer = device.makeBuffer(
            length: MemoryLayout<HoloBumpUniforms>.stride,
            options: .storageModeShared
        ) else { return nil }
        memcpy(buffer.contents(), &uniforms, MemoryLayout<HoloBumpUniforms>.stride)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = outTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let cmd = commandQueue.makeCommandBuffer(),
              let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encoder.setViewport(
            MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1)
        )
        encoder.label = "HoloBumpEncoder"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(foilTexture, index: 0)
        encoder.setFragmentBuffer(buffer, offset: 0, index: 0)

        var artRect = SIMD4<Float>(-1, -1, 2, 2)
        encoder.setVertexBytes(&artRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        guard let result = snapshotCGImage(from: outTexture) else { return nil }
        cache[key] = result
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit { cache[cacheOrder.removeFirst()] = nil }
        return result
    }

    // MARK: - Helpers

    private func makeTexture(from cg: CGImage, device: MTLDevice) -> MTLTexture? {
        let maxDim = 2048
        let srcW = cg.width
        let srcH = cg.height
        // Metal traps (aborts the process) on an invalid texture descriptor
        // rather than returning nil, so reject degenerate inputs up front.
        guard srcW > 0, srcH > 0 else { return nil }
        // Clamp to the device's max 2D dimension. The foil source is a cached
        // holo tile rendered at `scale = 2` over a `2w × 2h` area, so its
        // pixel size can exceed the GPU limit on some machines — that makes
        // `validateWithDevice:` trap and kill the app. Redraw scaled so the
        // descriptor is always valid.
        let scale = min(1.0, Double(maxDim) / Double(max(srcW, srcH)))
        let width = max(1, Int((Double(srcW) * scale).rounded()))
        let height = max(1, Int((Double(srcH) * scale).rounded()))
        #if LOG_DEBUG
        if scale < 1.0 {
            LoggerService.debug("HoloBump: foil \(srcW)x\(srcH) clamped to \(width)x\(height) (maxDim \(maxDim))")
        }
        #endif
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        guard totalBytes > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }

    private func snapshotCGImage(from texture: MTLTexture) -> NSImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            texture.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: region,
                mipmapLevel: 0
            )
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}

// Mirror of `HoloBumpUniforms` in HoloBump.metal — must match field-for-field.
struct HoloBumpUniforms {
    var tiltMatrix: simd_float4x4
    var lightDir: SIMD3<Float>
    var pointerX: Float
    var pointerY: Float
    var cursorInfluence: Float
    var tiltInfluence: Float
    var specularPower: Float
    var intensity: Float
    var hueShiftDegrees: Float
    var saturation: Float
}

// Bucket floating-point values for cache keys. Coarse bucketing (≈⅙ steps)
// means a cursor swipe only crosses a handful of cache buckets instead of
// re-rendering on every sub-pixel move. Internal (not private) because the
// view layer (HoloCardLayers) builds the same bucketed signature.
extension CGFloat {
    var bucketed: String { String(format: "%.2f", self) }
    var coarseBucketed: String { String(format: "%.2f", (self * 6).rounded() / 6) }
}
extension Double {
    var bucketed: String { String(format: "%.2f", self) }
    var coarseBucketed: String { String(format: "%.2f", (self * 6).rounded() / 6) }
}

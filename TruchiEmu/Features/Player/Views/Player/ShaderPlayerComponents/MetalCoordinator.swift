import Cocoa
import SwiftUI
import MetalKit
import CoreMedia
import Accelerate

// MARK: - Metal Coordinator

@MainActor
class MetalCoordinator: NSObject, MTKViewDelegate {
    let runner: EmulatorRunner
    private var commandQueue: MTLCommandQueue?
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var innerDrawCount = 0
    // 5-frame temporal buffer for CRT phosphor persistence (T-1, T-2, T-3, T-4, plus current frame passed directly to texture(0))
    private var temporalTextures: [MTLTexture?] = [nil, nil, nil, nil, nil]
    private var temporalIndex: Int = 0 // Cycles 0-4, points to "current" frame
    private var frameCounter: UInt32 = 0

    // Viewport debouncing to prevent warping during resize
    private var stableViewportSize: CGSize = .zero
    private var resizeTimer: Timer?
    private let resizeSettleInterval: TimeInterval = 0.15 // 150ms

    // Recording support: shared-mode texture for GPU readback
    private var recordingSharedTexture: MTLTexture?
    private var recordingFrameCount: Int64 = 0
    private var recordingStartTime: CFTimeInterval = 0
    // Track the previous frame's isRecording state so we can detect a fresh
    // recording session (e.g., after RollingVideoBufferService rotates a
    // chunk) and re-anchor the video PTS to the new session start. Without
    // this, video PTS keeps advancing from the first recording ever started,
    // making it diverge from the audio side which gets a fresh anchor at each
    // startRecording() call.
    private var wasRecordingFlag: Bool = false

    // Screenshot capture support: shared-mode textures for GPU readback
    private var screenshotDisplayTexture: MTLTexture?
    private var screenshotNativeTexture: MTLTexture?
    private var pendingDisplayURL: URL?
    private var pendingNativeURL: URL?
    private var pendingWantsNative: Bool = false
    private var pendingOnComplete: (([URL]) -> Void)?

    init(runner: EmulatorRunner) {
        self.runner = runner
    }

    func cleanup() {
        temporalTextures = [nil, nil, nil, nil, nil]
        pipelineCache.removeAll()
        commandQueue = nil
        resizeTimer?.invalidate()
        resizeTimer = nil
        aspectStableTimer?.invalidate()
        aspectStableTimer = nil
        frameCounter = 0
        innerDrawCount = 0
        recordingSharedTexture = nil
        screenshotDisplayTexture = nil
        screenshotNativeTexture = nil
        pendingDisplayURL = nil
        pendingNativeURL = nil
        pendingOnComplete = nil
    }

    /// Request a screenshot capture on the next drawn frame.
    /// - Parameters:
    ///   - displayURL: URL for the shader-applied (drawable) capture.
    ///   - nativeURL: Optional URL for the raw native frame capture.
    ///   - onComplete: Called on an arbitrary queue with the saved file URLs (subset of display/native that were requested).
    func requestScreenshotCapture(displayURL: URL,
                                  nativeURL: URL?,
                                  onComplete: @escaping ([URL]) -> Void) {
        pendingDisplayURL = displayURL
        pendingNativeURL = nativeURL
        pendingWantsNative = (nativeURL != nil)
        pendingOnComplete = onComplete
    }

    // MARK: - Viewport Debouncing
    private var lastStableAspect: CGFloat = 0.0
    private var aspectStableTimer: Timer?
    private var lastUsedDrawableSize: CGSize = .zero

    private func shouldUpdateAspect(for view: MTKView) -> Bool {
        // Return true if aspect should update, false if should keep stable
        let currentSize = view.drawableSize

        // If significantly different from last used, update
        if abs(currentSize.width - lastUsedDrawableSize.width) > 50 ||
           abs(currentSize.height - lastUsedDrawableSize.height) > 50 {
            lastUsedDrawableSize = currentSize
            return true
        }

        return false
    }

    private func ensureTemporalTextures(width: Int, height: Int, device: MTLDevice, sourceFormat: MTLPixelFormat) {
        // Check if all textures are valid and match
        var allValid = true
        for tex in temporalTextures {
            if tex == nil || tex!.width != width || tex!.height != height || tex!.pixelFormat != sourceFormat {
                allValid = false
                break
            }
        }
        if allValid { return }

        // Create all 5 temporal textures
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: sourceFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        temporalTextures = [nil, nil, nil, nil, nil]
        for i in 0..<5 {
            if let newTex = device.makeTexture(descriptor: descriptor) {
                temporalTextures[i] = newTex
            }
        }
        temporalIndex = 0
        #if LOG_DEBUG
        LoggerService.debug(category: "Shaders", "Created 5-frame temporal buffer: \(width)x\(height) format:\(sourceFormat)")
        #endif
    }

    private func getTemporalTexture(at index: Int) -> MTLTexture? {
        return temporalTextures[index]
    }

    private func advanceTemporalIndex() {
        temporalIndex = (temporalIndex + 1) % 5
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Apply CATransform3D layer rotation so rotated games display upright
        let rotation = runner.currentFrameRotation
        let angle: Double
        switch rotation {
        case 1: angle = .pi / 2.0      // 90° CW
        case 2: angle = .pi             // 180°
        case 3: angle = -.pi / 2.0     // 270° CW (= -90°)
        default: angle = 0.0
        }
        view.layer?.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
    }

    private func getFragmentFunctionName() -> String {
        return ShaderManager.shared.getCurrentFragmentFunctionName()
    }

    private func getPipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        let fragmentName = getFragmentFunctionName()

        if let cached = pipelineCache[fragmentName] {
            return cached
        }

        // Create new pipeline
        guard let library = loadShaderLibrary(device: device) else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Shaders", "ERROR: Could not create shader library.")
            #endif
            return nil
        }

        guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
              let fragmentFunction = library.makeFunction(name: fragmentName) else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Shaders", "ERROR: Could not find shader function '\(fragmentName)'")
            #endif
            #if LOG_DEBUG
            LoggerService.debug(category: "Shaders", "Available functions: \(library.functionNames.joined(separator: ", "))")
            #endif
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction

        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: desc)
            pipelineCache[fragmentName] = pipeline
            #if LOG_DEBUG
            LoggerService.debug(category: "Shaders", "Created pipeline for '\(fragmentName)'")
            #endif
            return pipeline
        } catch {
            #if LOG_DEBUG
            LoggerService.debug(category: "Shaders", "ERROR: Failed to create pipeline '\(fragmentName)': \(error)")
            #endif
            return nil
        }
    }

    func draw(in view: MTKView) {
        // Reset mouse deltas at start of each frame
        XPCBridgeAdapter.shared.resetMouseDeltas()

        guard let device = view.device,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Transparent background (alpha 0) so bezel shows through
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store

        if commandQueue == nil {
            #if LOG_DEBUG
            LoggerService.debug(category: "Metal", "Initializing Command Queue...")
            #endif
            commandQueue = device.makeCommandQueue()
        }

        guard let cmdQueue = commandQueue,
              let cmdBuffer = cmdQueue.makeCommandBuffer() else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Metal", "Failed to create command buffer")
            #endif
            return
        }

        let fragmentName = getFragmentFunctionName()

        // Early path for slang shaders - use librashader filter chain
        if fragmentName == "slang" {
            if let frameTex = runner.currentFrameTexture {
                let isRotated = (runner.currentFrameRotation == 1 || runner.currentFrameRotation == 3)
                let frameW = CGFloat(frameTex.width)
                let frameH = CGFloat(frameTex.height)
                var targetAspect: CGFloat

                let coreAspect = XPCBridgeAdapter.shared.aspectRatio()
                if coreAspect > 0.0 {
                    targetAspect = isRotated ? (1.0 / CGFloat(coreAspect)) : CGFloat(coreAspect)
                } else {
                    targetAspect = isRotated ? (frameH / frameW) : (frameW / frameH)
                }

                if let systemID = runner.rom?.systemID,
                   SystemDatabase.system(forID: systemID) != nil,
                   targetAspect > 1.7 {
                    targetAspect = 1.6
                }

                let viewWidth = view.drawableSize.width
                let viewHeight = view.drawableSize.height
                var drawWidth = viewWidth
                var drawHeight = viewWidth / targetAspect
                if drawHeight > viewHeight {
                    drawHeight = viewHeight
                    drawWidth = viewHeight * targetAspect
                }
                let slangX = (viewWidth - drawWidth) / 2.0
                let slangY = (viewHeight - drawHeight) / 2.0

                let slangVP = MTLViewport(originX: Double(slangX), originY: Double(slangY),
                                          width: Double(drawWidth), height: Double(drawHeight),
                                          znear: 0.0, zfar: 1.0)
                SlangCompilerService.shared.renderFrame(
                    commandBuffer: cmdBuffer,
                    inputTexture: frameTex,
                    outputTexture: drawable.texture,
                    frameCount: UInt64(frameCounter),
                    viewport: slangVP,
                    aspectRatio: Float(targetAspect)
                )

                // Recording / rolling-buffer capture: built-in-shader path
                // runs in the enc-scope block below; the slang path early-
                // returns, so we capture here. Shares the helper with the
                // built-in path so slang presets also produce a recorded
                // stream (and the centered-sub-rect crop applies the same way,
                // removing the alpha=0 black bars from the encoded frame).
                let isRecording = StreamRecordingService.shared.isRecording
                let needFrameCapture = isRecording || RollingVideoBufferService.shared.isEnabled
                if needFrameCapture {
                    if isRecording && !wasRecordingFlag {
                        recordingStartTime = CACurrentMediaTime()
                        recordingFrameCount = 0
                    }
                    wasRecordingFlag = isRecording
                    recordingFrameCount += 1
                    performFrameCapture(
                        commandBuffer: cmdBuffer,
                        device: device,
                        drawableTexture: drawable.texture,
                        frameTex: frameTex
                    )
                } else {
                    recordingStartTime = 0
                    wasRecordingFlag = false
                }
            }
            cmdBuffer.present(drawable)
            cmdBuffer.commit()
            return
        }

        let pipeline = getPipelineState(device: device)
        if let pipeline = pipeline {
            if let frameTex = runner.currentFrameTexture {
                if let enc = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                    // ASPECT RATIO — multi-tier fallback:
                    // 1. Core-provided aspect ratio from retro_system_av_info (preferred for N64, PS1, etc.)
                    // 2. Pixel dimensions from frame texture (frameW/frameH)
                    // 3. System's known display aspect ratio (final fallback for consoles with fixed display output)
                    // Use current drawable size for viewport (to maintain proper centering and scaling)
                    let viewWidth = view.drawableSize.width
                    let viewHeight = view.drawableSize.height
                    let isRotated = (runner.currentFrameRotation == 1 || runner.currentFrameRotation == 3)
                    let frameW = CGFloat(frameTex.width)
                    let frameH = CGFloat(frameTex.height)
                    var targetAspect: CGFloat

                    // Track drawable size for aspect stability
                    _ = shouldUpdateAspect(for: view)

                    // Try core-provided aspect ratio first (preferred for N64, PS1, etc.)
                    let coreAspect = XPCBridgeAdapter.shared.aspectRatio()
                    if coreAspect > 0.0 {
                        // Core provided a valid aspect ratio — use it directly
                        targetAspect = isRotated ? (1.0 / CGFloat(coreAspect)) : CGFloat(coreAspect)
                    } else {
                        // Fall back to computing from pixel dimensions
                        targetAspect = isRotated ? (frameH / frameW) : (frameW / frameH)
                    }

                    // Final fallback: for known console systems, use the system's canonical display aspect ratio
                    // to prevent incorrect rendering when the core reports wrong or missing aspect info.
                    // This catches cases where PS1 cores report non-4:3 internal resolutions (e.g. 368x240).
                    if let systemID = runner.rom?.systemID,
                       let systemInfo = SystemDatabase.system(forID: systemID) {
                        _ = systemInfo.displayAspectRatio

                        //If the aspect ratio is wider than the Macbook screen, force it to 16:10
                        // FIXME: this should be an option in settings
                        if targetAspect > 1.7 {
                            targetAspect = 1.6
                            #if LOG_EXTREME
                            LoggerService.extreme(category: "Metal", "[Aspect Ratio] Core/pixel ratio \(String(format: "%.3f", targetAspect)) is wider than the macbook screen. Forcing aspect ratio to 16:10")
                            #endif
                        }
                    }
                    var drawWidth = viewWidth
                    var drawHeight = viewWidth / targetAspect

                    if drawHeight > viewHeight {
                        drawHeight = viewHeight
                        drawWidth = viewHeight * targetAspect
                    }

                    let x = (viewWidth - drawWidth) / 2.0
                    let y = (viewHeight - drawHeight) / 2.0

                    let viewport = MTLViewport(originX: Double(x), originY: Double(y),
                                               width: Double(drawWidth), height: Double(drawHeight),
                                               znear: 0.0, zfar: 1.0)
                    enc.setViewport(viewport)

                    let fw = Float(frameTex.width)
                    let fh = Float(frameTex.height)
                    let vpW = Float(view.drawableSize.width)
                    let vpH = Float(view.drawableSize.height)
                    let time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
                    let fragmentName = getFragmentFunctionName()

                    // Helper: get a uniform value from the thread-safe snapshot
                    func getUniform(_ name: String, fallback: Float) -> Float {
                        let snapshot = ShaderManager.shared.getUniformSnapshot()
                        return snapshot[name] ?? fallback
                    }

                    enc.setRenderPipelineState(pipeline)
                    enc.setFragmentTexture(frameTex, index: 0)

                    switch fragmentName {
                    case "fragmentCRT", "fragmentPassthrough":
                        // Use preset defaults for all uniforms - no ROMSettings fallback
                        // Genesis bleeding is quite noticeable.
                        let scanInt = getUniform("scanlineIntensity", fallback: 0.6)
                        let barrelAmt = getUniform("barrelAmount", fallback: 0.05)
                        let colorB = getUniform("colorBoost", fallback: 1.1)
                        var u = CRTUniforms(
                            scanlineIntensity: scanInt,
                            barrelAmount: barrelAmt,
                            colorBoost: colorB,
                            time: time,
                            bleedAmount: getUniform("bleedAmount", fallback: 0.0),
                            texSizeX: Float(frameTex.width),
                            texSizeY: Float(frameTex.height),
                            vignetteStrength: getUniform("vignetteStrength", fallback: 0.45),
                            flickerStrength: getUniform("flickerStrength", fallback: 0.005),
                            bloomStrength: getUniform("bloomStrength", fallback: 1.3),
                            chromaAmount: getUniform("chromaAmount", fallback: 0.0012),
                            softnessAmount: getUniform("softnessAmount", fallback: 0.0008),
                            bezelRounding: getUniform("bezelRounding", fallback: 0.04),
                            bezelGlow: getUniform("bezelGlow", fallback: 0.35),
                            tintR: getUniform("tintR", fallback: 0.96),
                            tintG: getUniform("tintG", fallback: 1.04),
                            tintB: getUniform("tintB", fallback: 0.95),
                            useDistort: getUniform("useDistort", fallback: 1.0),
                            useScan: getUniform("useScan", fallback: 1.0),
                            useBleed: getUniform("useBleed", fallback: 1.0),
                            useSoft: getUniform("useSoft", fallback: 1.0),
                            useChroma: getUniform("useChroma", fallback: 1.0),
                            useWhite: getUniform("useWhite", fallback: 1.0),
                            useVig: getUniform("useVig", fallback: 1.0),
                            useFlick: getUniform("useFlick", fallback: 1.0),
                            useBezel: getUniform("useBezel", fallback: 1.0),
                            useBloom: getUniform("useBloom", fallback: 0.0),

                            // Subpixel mask controls
                            maskPixelSpacingH: getUniform("maskPixelSpacingH", fallback: 3.0),
                            maskPixelSpacingV: getUniform("maskPixelSpacingV", fallback: 3.0),
                            maskSubpixelGap: getUniform("maskSubpixelGap", fallback: 0.3),
useMask: getUniform("useMask", fallback: 0.0),

outputWidth: Float(drawWidth),
outputHeight: Float(drawHeight)
)
                        enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                    case "fragmentDotMatrixLCD":
                        // Use preset defaults for all uniforms
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = DotMatrixLCDUniforms(
                            dotOpacity: getUniform("dotOpacity", fallback: 0.85),
                            metallicIntensity: getUniform("metallicIntensity", fallback: 0.5),
                            specularShininess: getUniform("specularShininess", fallback: 8.0),
                            colorBoost: colorB,
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<DotMatrixLCDUniforms>.stride, index: 0)
                    case "fragmentLottesCRT":
                        let colorB = getUniform("colorBoost", fallback: 1.1)
                        var u = LottesUniforms(
                            scanlineStrength: getUniform("scanlineStrength", fallback: 0.5),
                            maskStrength: getUniform("maskStrength", fallback: 0.3),
                            bloomAmount: getUniform("bloomAmount", fallback: 0.15),
                            curvatureAmount: getUniform("curvatureAmount", fallback: 0.02),
                            colorBoost: colorB,
                            _pad: 0,
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<LottesUniforms>.stride, index: 0)
                    case "fragmentSharpBilinear":
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = SharpBilinearUniforms(
                            sharpness: getUniform("sharpness", fallback: 0.8),
                            colorBoost: colorB,
                            scanlineOpacity: getUniform("scanlineOpacity", fallback: 0.0),
                            _pad: 0,
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<SharpBilinearUniforms>.stride, index: 0)
                    case "fragment8bGameBoy":
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = EightBitGameBoyUniforms(
                            gridStrength: getUniform("gridStrength", fallback: 0.4),
                            pixelSeparation: getUniform("pixelSeparation", fallback: 0.05),
                            brightnessBoost: getUniform("brightnessBoost", fallback: 1.2),
                            colorBoost: colorB,
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0),
                            showShell: getUniform("showShell", fallback: 1.0),
                            showStrip: getUniform("showStrip", fallback: 1.0),
                            showLens: getUniform("showLens", fallback: 1.0),
                            showText: getUniform("showText", fallback: 1.0),
                            showLED: getUniform("showLED", fallback: 1.0),
                            lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0),
                            lightStrength: getUniform("lightStrength", fallback: 1.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<EightBitGameBoyUniforms>.stride, index: 0)
                    case "fragment8BitGBC":
                        // Game Boy Color with 4-frame temporal feedback
                        ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                        let colorB = getUniform("colorBoost", fallback: 1.44)
                        let gw = getUniform("ghostWeights", fallback: 0.45)
                        // Compute flags from enable toggles
                        var flags: UInt32 = 0
                        let ghostEnabled = getUniform("enableGhost", fallback: 1.0) > 0.5
                        let gridEnabled = getUniform("enableGrid", fallback: 1.0) > 0.5
                        let aberrationEnabled = getUniform("enableAberration", fallback: 1.0) > 0.5
                        let bleedEnabled = getUniform("enableBleed", fallback: 1.0) > 0.5
                        let newtonRingsEnabled = getUniform("enableNewtonRings", fallback: 1.0) > 0.5
                        let jitterEnabled = getUniform("enableJitter", fallback: 1.0) > 0.5
                        let reflectionEnabled = getUniform("enableReflection", fallback: 1.0) > 0.5
                        let grainEnabled = getUniform("enableGrain", fallback: 1.0) > 0.5
                        let vignetteEnabled = getUniform("enableVignette", fallback: 1.0) > 0.5
                        let topographyEnabled = getUniform("enableTopography", fallback: 1.0) > 0.5
                        let colorMatrixEnabled = getUniform("enableColorMatrix", fallback: 1.0) > 0.5
                        if ghostEnabled { flags |= 1 << 0 } // FLAG_GHOSTING
                        if gridEnabled { flags |= 1 << 1 } // FLAG_GRID
                        if aberrationEnabled { flags |= 1 << 2 } // FLAG_ABERRATION
                        if bleedEnabled { flags |= 1 << 3 } // FLAG_BLEED
                        if newtonRingsEnabled { flags |= 1 << 4 } // FLAG_NEWTON_RINGS
                        if jitterEnabled { flags |= 1 << 5 } // FLAG_JITTER
                        if reflectionEnabled { flags |= 1 << 6 } // FLAG_REFLECTION
                        if grainEnabled { flags |= 1 << 7 } // FLAG_GRAIN
                        if vignetteEnabled { flags |= 1 << 8 } // FLAG_VIGNETTE
                        if topographyEnabled { flags |= 1 << 9 } // FLAG_TOPOGRAPHY
                        if colorMatrixEnabled { flags |= 1 << 10 } // FLAG_COLOR_MATRIX
                        var u = GBCUniforms(
                            dotOpacity: getUniform("dotOpacity", fallback: 0.85),
                            specularShininess: getUniform("specularShininess", fallback: 8.0),
                            colorBoost: colorB,
                            physicalDepth: getUniform("physicalDepth", fallback: 0.22),
                            ghostingWeight: gw,
                            frameIndex: frameCounter,
                            flags: flags,
                            brightnessBoost: getUniform("brightnessBoost", fallback: 1.0),
                            showShell: getUniform("showShell", fallback: 1.0),
                            lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0),
                            lightStrength: getUniform("lightStrength", fallback: 1.0),
                            shellColorIndex: {
                                let val = getUniform("shellColorIndex", fallback: 0.0)
                                return val
                            }(),
                            gridThicknessDark: getUniform("gridThicknessDark", fallback: 0.2),
                            gridThicknessLight: getUniform("gridThicknessLight", fallback: 0.1),
                            sourceSize: SIMD4<Float>(fw, fh, 0, 0),
                            outputSize: SIMD4<Float>(vpW, vpH, 0, 0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<GBCUniforms>.stride, index: 0)
                        // Set all 5 textures: frame0=current, frame1=T-1, frame2=T-2, frame3=T-3, frame4=T-4
                        enc.setFragmentTexture(frameTex, index: 0)
                        for i in 1...4 {
                            if let tex = getTemporalTexture(at: (temporalIndex - i + 5) % 5) {
                                enc.setFragmentTexture(tex, index: i)
                            }
                        }
                        frameCounter += 1
                    case "fragmentLiteCRT":
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = LiteCRTUniforms(
                            scanlineIntensity: getUniform("scanlineIntensity", fallback: 0.3),
                            phosphorStrength: getUniform("phosphorStrength", fallback: 0.2),
                            brightness: getUniform("brightness", fallback: 1.1),
                            colorBoost: colorB
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<LiteCRTUniforms>.stride, index: 0)
                    case "fragmentScaleSmooth":
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = ScaleSmoothUniforms(
                            smoothness: getUniform("smoothness", fallback: 1.0),
                            colorBoost: colorB,
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<ScaleSmoothUniforms>.stride, index: 0)
                    case "fragmentGBAShader":
                        ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = GBAUniforms(
                            dotOpacity: getUniform("dotOpacity", fallback: 0.8),
                            specularShininess: getUniform("specularShininess", fallback: 1.0),
                            colorBoost: colorB,
                            ghostingWeight: getUniform("ghostingWeight", fallback: 0.25),
                            physicalDepth: getUniform("physicalDepth", fallback: 0.2),
                            frameIndex: UInt32(frameCounter % 60),
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0),
                            lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0)
                        )
                        enc.setFragmentBytes(&u, length: MemoryLayout<GBAUniforms>.stride, index: 0)
                        enc.setFragmentTexture(frameTex, index: 0)
                        for i in 1...2 {
                            if let tex = getTemporalTexture(at: (temporalIndex - i + 5) % 5) {
                                enc.setFragmentTexture(tex, index: i)
                            }
                        }
                        frameCounter += 1
                    case "fragmentPSPShader":
                        ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                        let pspColorB = getUniform("colorBoost", fallback: 1.0)
                        let pspGamut = simd_float3x3(
                            SIMD3<Float>(getUniform("gamutR0C0", fallback: 1.0), getUniform("gamutR1C0", fallback: 0.0), getUniform("gamutR2C0", fallback: 0.0)),
                            SIMD3<Float>(getUniform("gamutR0C1", fallback: 0.0), getUniform("gamutR1C1", fallback: 1.0), getUniform("gamutR2C1", fallback: 0.0)),
                            SIMD3<Float>(getUniform("gamutR0C2", fallback: 0.0), getUniform("gamutR1C2", fallback: 0.0), getUniform("gamutR2C2", fallback: 1.0))
                        )
                        var pspU = PSPUniforms(
                            dotOpacity: getUniform("dotOpacity", fallback: 0.85),
                            specularShininess: getUniform("specularShininess", fallback: 0.8),
                            colorBoost: pspColorB,
                            ghostingWeight: getUniform("ghostingWeight", fallback: 0.15),
                            physicalDepth: getUniform("physicalDepth", fallback: 0.15),
                            frameIndex: UInt32(frameCounter % 60),
                            sourceSize: SIMD4<Float>(fw, fh, 1.0/fw, 1.0/fh),
                            outputSize: SIMD4<Float>(vpW, vpH, 0.0, 0.0),
                            lightPositionIndex: getUniform("lightPositionIndex", fallback: 0.0),
                            physicalLineWidth: getUniform("physicalLineWidth", fallback: 0.8),
                            _pad0: 0.0,
                            _pad1: 0.0,
                            colorGamut: pspGamut
                        )
                        enc.setFragmentBytes(&pspU, length: MemoryLayout<PSPUniforms>.stride, index: 0)
                        enc.setFragmentTexture(frameTex, index: 0)
                        for i in 1...2 {
                            if let tex = getTemporalTexture(at: (temporalIndex - i + 5) % 5) {
                                enc.setFragmentTexture(tex, index: i)
                            }
                        }
                        frameCounter += 1
                    case "fragmentCRTMultipass":
                        ensureTemporalTextures(width: frameTex.width, height: frameTex.height, device: device, sourceFormat: frameTex.pixelFormat)
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = CRTMultipassUniforms(
                            scanlineIntensity: getUniform("scanlineIntensity", fallback: 0.45),
                            barrelAmount: getUniform("barrelAmount", fallback: 0.15),
                            colorBoost: colorB,
                            time: time,
                            ghostingWeight: getUniform("ghostingWeight", fallback: 0.3),
                            bleedAmount: getUniform("bleedAmount", fallback: 0.0),
                            texSizeX: fw,
                            texSizeY: fh,
                            vignetteStrength: getUniform("vignetteStrength", fallback: 0.6),
                            flickerStrength: getUniform("flickerStrength", fallback: 0.05),
                            bloomStrength: getUniform("bloomStrength", fallback: 0.25),
                            chromaAmount: getUniform("chromaAmount", fallback: 0.4),
                            softnessAmount: getUniform("softnessAmount", fallback: 0.2),
                            bezelRounding: getUniform("bezelRounding", fallback: 0.1),
                            bezelGlow: getUniform("bezelGlow", fallback: 0.5),
                            tintR: getUniform("tintR", fallback: 1.0),
                            tintG: getUniform("tintG", fallback: 1.0),
                            tintB: getUniform("tintB", fallback: 1.0),
                            useDistort: getUniform("useDistort", fallback: 1.0),
                            useScan: getUniform("useScan", fallback: 1.0),
                            useBleed: getUniform("useBleed", fallback: 1.0),
                            useSoft: getUniform("useSoft", fallback: 1.0),
                            useChroma: getUniform("useChroma", fallback: 1.0),
                            useWhite: getUniform("useWhite", fallback: 1.0),
                            useVig: getUniform("useVig", fallback: 1.0),
                            useFlick: getUniform("useFlick", fallback: 1.0),
                            useBezel: getUniform("useBezel", fallback: 1.0),
                            useBloom: getUniform("useBloom", fallback: 1.0),

                            // New additions
                            phosphorDecay: getUniform("phosphorDecay", fallback: 0.5),
                            maskPixelSpacingH: getUniform("maskPixelSpacingH", fallback: 3.0),
                            maskPixelSpacingV: getUniform("maskPixelSpacingV", fallback: 3.0),
                            maskSubpixelGap: getUniform("maskSubpixelGap", fallback: 0.3),
useMask: getUniform("useMask", fallback: 1.0),

outputWidth: Float(drawWidth),
outputHeight: Float(drawHeight)
)
                        enc.setFragmentBytes(&u, length: MemoryLayout<CRTMultipassUniforms>.stride, index: 0)
                        enc.setFragmentTexture(frameTex, index: 0)
                        for i in 1...4 {
                            if let tex = getTemporalTexture(at: (temporalIndex - i + 5) % 5) {
                                enc.setFragmentTexture(tex, index: i)
                            }
                        }
                        frameCounter += 1
                    default:
                        // Fallback to basic passthrough/CRT style
                        let colorB = getUniform("colorBoost", fallback: 1.0)
                        var u = CRTUniforms(
                            scanlineIntensity: 0.0,
                            barrelAmount: 0.0,
                            colorBoost: colorB,
                            time: time,
                            bleedAmount: getUniform("bleedAmount", fallback: 0.0),
                            texSizeX: Float(frameTex.width),
                            texSizeY: Float(frameTex.height),
                            vignetteStrength: 0.0,
                            flickerStrength: 0.0,
                            bloomStrength: 0.0,
                            chromaAmount: 0.0,
                            softnessAmount: 0.0,
                            bezelRounding: 0.0,
                            bezelGlow: 0.0,
                            tintR: 1.0,
                            tintG: 1.0,
                            tintB: 1.0,
                            useDistort: 0.0,
                            useScan: 0.0,
                            useBleed: 0.0,
                            useSoft: 0.0,
                            useChroma: 0.0,
                            useWhite: 0.0,
                            useVig: 0.0,
                            useFlick: 0.0,
                            useBezel: 0.0,
                            useBloom: 0.0,

                            // Subpixel mask controls
                            maskPixelSpacingH: 3.0,
                            maskPixelSpacingV: 3.0,
                            maskSubpixelGap: 0.3,
useMask: 0.0,

outputWidth: Float(drawWidth),
outputHeight: Float(drawHeight)
)
                        enc.setFragmentBytes(&u, length: MemoryLayout<CRTUniforms>.stride, index: 0)
                    }

                    enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    enc.endEncoding()

                    // For shaders with temporal feedback: maintain rolling history
                    // Must happen AFTER render encoder ends
                    // Advance first, then write to that slot (becomes T-1 for next frame)
                    if fragmentName == "fragment8BitGBC" || fragmentName == "fragmentGBAShader" || fragmentName == "fragmentPSPShader" || fragmentName == "fragmentCRTMultipass" {
                        advanceTemporalIndex()
                        let blit = cmdBuffer.makeBlitCommandEncoder()
                        if let tex = temporalTextures[temporalIndex] {
                            blit?.copy(from: frameTex, to: tex)
                        }
                        blit?.endEncoding()
                    }

                    // Recording: capture emulator frame for streaming/recording
                    let isRecording = StreamRecordingService.shared.isRecording
                    let needFrameCapture = isRecording || RollingVideoBufferService.shared.isEnabled
                    if needFrameCapture {
                        if isRecording && !wasRecordingFlag {
                            // Fresh recording session — first-ever capture, or
                            // a new writer session after
                            // RollingVideoBufferService rotated a chunk /
                            // user toggled recording. Re-anchor so this frame's
                            // PTS starts at zero, matching the new writer
                            // session and the audio PTS anchor set in
                            // StreamRecordingService.startRecording.
                            recordingStartTime = CACurrentMediaTime()
                            recordingFrameCount = 0
                        }
                        wasRecordingFlag = isRecording
                        let now = CACurrentMediaTime()
                        let pts = CMTime(seconds: now - recordingStartTime, preferredTimescale: 600)
                        recordingFrameCount += 1

                        performFrameCapture(
                            commandBuffer: cmdBuffer,
                            device: device,
                            drawableTexture: drawable.texture,
                            frameTex: frameTex
                        )
                    } else {
                        recordingStartTime = 0
                        wasRecordingFlag = false
                    }

                    // Screenshot capture: copy drawable + (optional) native to shared textures,
                    //  read bytes in completion handler. Requires frameTex to be available.
                    if pendingDisplayURL != nil, let frameTex = runner.currentFrameTexture {
                        let displayURL = pendingDisplayURL
                        let nativeURL = pendingNativeURL
                        performScreenshotCapture(
                            commandBuffer: cmdBuffer,
                            device: device,
                            drawable: drawable.texture,
                            sourceNative: frameTex,
                            displayURL: displayURL,
                            nativeURL: nativeURL
                        )
                        pendingDisplayURL = nil
                        pendingNativeURL = nil
                        pendingWantsNative = false
                        let cb = pendingOnComplete
                        pendingOnComplete = nil
                        if let cb = cb {
                            cmdBuffer.addCompletedHandler { _ in
                                var saved: [URL] = []
                                if let u = displayURL { saved.append(u) }
                                if let u = nativeURL { saved.append(u) }
                                cb(saved)
                            }
                        }
                    }
                    innerDrawCount += 1

                    if innerDrawCount <= 3 {
                        #if LOG_EXTREME
                        LoggerService.extreme(category: "Metal", "Drawing frame \(innerDrawCount) with texture \(frameTex.width)x\(frameTex.height)")
                        #endif
                    }
                }
            } else {
                // No frame texture yet - just present black screen
                if innerDrawCount < 10 {
                    #if LOG_EXTREME
                    LoggerService.extreme(category: "Metal", "No frame texture yet, drawing black")
                    #endif
                }
            }
        } else {
            if innerDrawCount < 5 {
                #if LOG_DEBUG
                LoggerService.debug(category: "Metal", "Failed to get pipeline state for fragment shader")
                #endif
            }
        }

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    /// Capture the displayed Metal drawable + (optional) the native frame.
    /// Reads the data on commandBuffer completion and writes PNGs via ScreenshotService.
    private func performScreenshotCapture(commandBuffer: MTLCommandBuffer,
                                          device: MTLDevice,
                                          drawable: MTLTexture,
                                          sourceNative: MTLTexture,
                                          displayURL: URL?,
                                          nativeURL: URL?) {
        if let displayURL = displayURL {
            ensureSharedTexture(
                target: &screenshotDisplayTexture,
                matching: drawable,
                device: device
            )
            if let dest = screenshotDisplayTexture {
                let blit = commandBuffer.makeBlitCommandEncoder()
                blit?.copy(from: drawable, to: dest)
                blit?.endEncoding()
                let w = dest.width
                let h = dest.height
                let bpp = Self.bytesPerPixel(dest.pixelFormat)
                let bpr = w * bpp
                commandBuffer.addCompletedHandler { _ in
                    var pixels = [UInt8](repeating: 0, count: h * bpr)
                    dest.getBytes(&pixels, bytesPerRow: bpr,
                                  from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    let bgra = Self.convertToBGRA32(pixels, width: w, height: h, srcBPP: bpp, srcPixelFormat: dest.pixelFormat)
                    ScreenshotService.writeBGRA(bgra, width: w, height: h, to: displayURL)
                }
            }
        }
        if let nativeURL = nativeURL {
            ensureSharedTexture(
                target: &screenshotNativeTexture,
                matching: sourceNative,
                device: device
            )
            if let dest = screenshotNativeTexture {
                let blit = commandBuffer.makeBlitCommandEncoder()
                blit?.copy(from: sourceNative, to: dest)
                blit?.endEncoding()
                let w = dest.width
                let h = dest.height
                let bpp = Self.bytesPerPixel(dest.pixelFormat)
                let bpr = w * bpp
                commandBuffer.addCompletedHandler { _ in
                    var pixels = [UInt8](repeating: 0, count: h * bpr)
                    dest.getBytes(&pixels, bytesPerRow: bpr,
                                  from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                    let bgra = Self.convertToBGRA32(pixels, width: w, height: h, srcBPP: bpp, srcPixelFormat: dest.pixelFormat)
                    ScreenshotService.writeBGRA(bgra, width: w, height: h, to: nativeURL)
                }
            }
        }
    }

    private func ensureSharedTexture(target: inout MTLTexture?,
                                     matching source: MTLTexture,
                                     device: MTLDevice) {
        if let existing = target,
           existing.width == source.width,
           existing.height == source.height,
           existing.pixelFormat == source.pixelFormat {
            return
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width, height: source.height, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        target = device.makeTexture(descriptor: desc)
    }

    private func makePixelBuffer(from bgra32Pixels: [UInt8], width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                          kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                                          &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        if let dest = CVPixelBufferGetBaseAddress(pb) {
            let dstBPR = CVPixelBufferGetBytesPerRow(pb)
            let srcBPR = width * 4
            if dstBPR == srcBPR {
                memcpy(dest, bgra32Pixels, height * srcBPR)
            } else {
                bgra32Pixels.withUnsafeBufferPointer { srcBuf in
                    guard let srcBase = srcBuf.baseAddress else { return }
                    for row in 0..<height {
                        memcpy(dest.advanced(by: row * dstBPR),
                               srcBase + row * srcBPR,
                               srcBPR)
                    }
                }
            }
        }
        return pb
    }

    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .bgra8Unorm, .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm_srgb:
            return 4
        case .b5g6r5Unorm, .a1bgr5Unorm, .bgr5A1Unorm:
            return 2
        case .r8Unorm, .r8Unorm_srgb:
            return 1
        default:
            return 4
        }
    }

    private static func convertToBGRA32(_ pixels: [UInt8], width: Int, height: Int, srcBPP: Int, srcPixelFormat: MTLPixelFormat) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let total = width * height
        if srcBPP == 4 {
            memcpy(&out, pixels, min(pixels.count, total * 4))
            return out
        }
        if srcBPP == 2 {
            let src = pixels.withUnsafeBytes { $0.bindMemory(to: UInt16.self).baseAddress! }
            let dst = out.withUnsafeMutableBytes { $0.bindMemory(to: UInt32.self).baseAddress! }
            for i in 0..<total {
                let p = src[i]
                // BGRA32 in little-endian uint32: byte0=B, byte1=G, byte2=R, byte3=A
                if srcPixelFormat == .b5g6r5Unorm {
                    // RGB565: R[15:11] G[10:5] B[4:0] → BGRA32 B@0 G@1 R@2 A@3
                    let b5 = UInt32(p & 0x1F) * 255 / 31
                    let g6 = UInt32((p >> 5) & 0x3F) * 255 / 63
                    let r5 = UInt32((p >> 11) & 0x1F) * 255 / 31
                    dst[i] = b5 | (g6 << 8) | (r5 << 16) | 0xFF000000
                } else if srcPixelFormat == .a1bgr5Unorm {
                    // A1BGR5: A[15] B[14:10] G[9:5] R[4:0] → BGRA32 B@0 G@1 R@2 A@3
                    let b5 = UInt32((p >> 10) & 0x1F) * 255 / 31
                    let g5 = UInt32((p >> 5) & 0x1F) * 255 / 31
                    let r5 = UInt32(p & 0x1F) * 255 / 31
                    dst[i] = b5 | (g5 << 8) | (r5 << 16) | (((p >> 15) & 0x1) != 0 ? 0xFF000000 : 0)
                } else {
                    // BGR5A1: B[15:11] G[10:6] R[5:1] A[0] → BGRA32 B@0 G@1 R@2 A@3
                    let b5 = UInt32((p >> 11) & 0x1F) * 255 / 31
                    let g5 = UInt32((p >> 6) & 0x1F) * 255 / 31
                    let r5 = UInt32((p >> 1) & 0x1F) * 255 / 31
                    dst[i] = b5 | (g5 << 8) | (r5 << 16) | ((p & 0x1) != 0 ? 0xFF000000 : 0)
                }
            }
        } else if srcBPP == 1 {
            let src = pixels.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
            let dst = out.withUnsafeMutableBytes { $0.bindMemory(to: UInt32.self).baseAddress! }
            for i in 0..<total {
                let v = UInt32(src[i])
                dst[i] = v | (v << 8) | (v << 16) | 0xFF000000
            }
        }
        return out
    }

    private var recordingDAR: CGFloat {
        if let systemID = runner.rom?.systemID,
           let info = SystemDatabase.system(forID: systemID) {
            return info.displayAspectRatio
        }
        return 4.0 / 3.0
    }

    /// Capture the current frame into `recordingSharedTexture` and append it
    /// to the active recording (user-initiated record or rolling buffer).
    /// Shared by the built-in-shader path and the slang-shader path so that
    /// slang presets also produce a captured video stream.
    /// - When `useDisplayRes == true`, the baked-in-shader (or slang) drawable
    ///   is the source. We blit only the centered game sub-rect so the encoded
    ///   frame has no opaque-black pillarbox/letterbox bars around the game
    ///   (the drawable's bar region is RGB(0,0,0) alpha=0; H.264/HEVC encoders
    ///   have no alpha channel and would otherwise bake those pixels into
    ///   opaque black).
    /// - When `useDisplayRes == false`, the raw core frame texture is the
    ///   source and is optionally DAR-padded to match the system's display
    ///   aspect ratio.
    private func performFrameCapture(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        drawableTexture: MTLTexture,
        frameTex: MTLTexture
    ) {
        let isRecording = StreamRecordingService.shared.isRecording
        let useDisplayRes = isRecording ? StreamRecordingService.shared.recordWithShaders : RollingVideoBufferService.shared.recordDisplayResolution
        let srcTex = useDisplayRes ? drawableTexture : frameTex
        let cropRect: MTLRegion?
        if useDisplayRes {
            cropRect = Self.computeCenteredGameSubRect(
                drawable: srcTex,
                frameTex: frameTex,
                isRotated: runner.currentFrameRotation == 1 || runner.currentFrameRotation == 3,
                coreAspect: Double(XPCBridgeAdapter.shared.aspectRatio()),
                systemID: runner.rom?.systemID
            )
        } else {
            cropRect = nil
        }
        let recW = cropRect?.size.width ?? srcTex.width
        let recH = cropRect?.size.height ?? srcTex.height
        if recordingSharedTexture == nil ||
            recordingSharedTexture?.width != recW ||
            recordingSharedTexture?.height != recH ||
            recordingSharedTexture?.pixelFormat != srcTex.pixelFormat {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: srcTex.pixelFormat,
                width: recW, height: recH, mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            recordingSharedTexture = device.makeTexture(descriptor: desc)
        }
        guard let destTex = recordingSharedTexture else { return }
        let blit = commandBuffer.makeBlitCommandEncoder()
        if let crop = cropRect {
            blit?.copy(
                from: srcTex,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: crop.origin,
                sourceSize: crop.size,
                to: destTex,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        } else {
            blit?.copy(from: srcTex, to: destTex)
        }
        blit?.endEncoding()

        let capturePTS = CMTime(seconds: CACurrentMediaTime() - recordingStartTime, preferredTimescale: 600)
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self = self else { return }
            let tex = destTex
            let w = tex.width
            let h = tex.height
            let srcBPP = Self.bytesPerPixel(tex.pixelFormat)
            let srcBPR = w * srcBPP
            var pixels = [UInt8](repeating: 0, count: h * srcBPR)
            tex.getBytes(&pixels, bytesPerRow: srcBPR,
                         from: MTLRegionMake2D(0, 0, w, h),
                         mipmapLevel: 0)
            var bgra = Self.convertToBGRA32(pixels, width: w, height: h, srcBPP: srcBPP, srcPixelFormat: tex.pixelFormat)
            var outW = Int(w)
            var outH = Int(h)
            if isRecording && !StreamRecordingService.shared.recordWithShaders {
                let dar = self.recordingDAR
                let pixelAR = CGFloat(w) / CGFloat(h)
                if abs(dar - pixelAR) > 0.01 {
                    let corrW = max(Int(w), Int(ceil(CGFloat(h) * dar)))
                    let corrH = max(Int(h), Int(ceil(CGFloat(w) / dar)))
                    outW = corrW & ~1
                    outH = corrH & ~1
                    if outW != w || outH != h {
                        bgra = Self.resizeBGRA32(bgra, from: Int(w), srcH: Int(h), to: outW, dstH: outH)
                    }
                }
            }
            let pixelBuffer = self.makePixelBuffer(from: bgra, width: outW, height: outH)
            if let pb = pixelBuffer {
                DispatchQueue.main.async {
                    if isRecording {
                        if RollingVideoBufferService.shared.isEnabled {
                            RollingVideoBufferService.shared.ensureRecordingMatches(width: outW, height: outH)
                        }
                        StreamRecordingService.shared.appendVideoFrame(pb, at: capturePTS)
                    }
                }
            }
        }
    }

    /// Compute the centered sub-rect of `drawable` that contains the rendered
    /// game, mirroring the viewport letterboxing logic from the built-in
    /// shader path (`draw(in:)`) so the recorder can crop the black bars out
    /// of the captured frame. Returns a `MTLRegion` in pixel coordinates.
    static func computeCenteredGameSubRect(
        drawable: MTLTexture,
        frameTex: MTLTexture,
        isRotated: Bool,
        coreAspect: Double,
        systemID: String?
    ) -> MTLRegion {
        let viewWidth = CGFloat(drawable.width)
        let viewHeight = CGFloat(drawable.height)
        let frameW = CGFloat(frameTex.width)
        let frameH = CGFloat(frameTex.height)
        var targetAspect: CGFloat
        if coreAspect > 0.0 {
            targetAspect = isRotated ? (1.0 / CGFloat(coreAspect)) : CGFloat(coreAspect)
        } else {
            targetAspect = isRotated ? (frameH / frameW) : (frameW / frameH)
        }
        // Mirror the renderer's safety clamp: if the chosen aspect ratio is
        // wider than 16:10, cap it to 16:10 (see the FIXME-comment block in
        // `draw(in:)`).
        if let sid = systemID,
           SystemDatabase.system(forID: sid) != nil,
           targetAspect > 1.7 {
            targetAspect = 1.6
        }
        var drawWidth = viewWidth
        var drawHeight = viewWidth / targetAspect
        if drawHeight > viewHeight {
            drawHeight = viewHeight
            drawWidth = viewHeight * targetAspect
        }
        let x = ((viewWidth - drawWidth) / 2.0).rounded(.toNearestOrEven)
        let y = ((viewHeight - drawHeight) / 2.0).rounded(.toNearestOrEven)
        let w = drawWidth.rounded(.toNearestOrEven)
        let h = drawHeight.rounded(.toNearestOrEven)
        return MTLRegion(
            origin: MTLOrigin(x: max(0, Int(x)), y: max(0, Int(y)), z: 0),
            size: MTLSize(width: max(1, Int(w)), height: max(1, Int(h)), depth: 1)
        )
    }

    private static func resizeBGRA32(_ pixels: [UInt8], from srcW: Int, srcH: Int, to dstW: Int, dstH: Int) -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: dstW * dstH * 4)
        var srcBuf = vImage_Buffer(data: UnsafeMutablePointer(mutating: pixels),
                                    height: vImagePixelCount(srcH),
                                    width: vImagePixelCount(srcW),
                                    rowBytes: srcW * 4)
        var dstBuf = vImage_Buffer(data: &dst,
                                    height: vImagePixelCount(dstH),
                                    width: vImagePixelCount(dstW),
                                    rowBytes: dstW * 4)
        vImageScale_ARGB8888(&srcBuf, &dstBuf, nil, 0)
        return dst
    }

    // Load the shader library containing all shaders
    private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        // Try to load pre-compiled metallib from bundle
        if let url = Bundle.main.url(forResource: "default", withExtension: "metallib") {
            LoggerService.info(category: "Shaders", "Found metallib at: \(url)")
            do {
                let library = try device.makeLibrary(URL: url)
                return library
            } catch {
                LoggerService.error(category: "Shaders", "Failed to load metallib: \(error)")
            }
        }

        // Fallback: compile all_shaders.metal from bundle resources
        if let bundlePath = Bundle.main.resourcePath {
            let shadersPath = (bundlePath as NSString).appendingPathComponent("all_shaders.metal")
            if let source = try? String(contentsOfFile: shadersPath, encoding: .utf8) {
                do {
                    let library = try device.makeLibrary(source: source, options: nil)
                    LoggerService.info(category: "Shaders", "Compiled all_shaders.metal with functions: \(library.functionNames.joined(separator: ", "))")
                    return library
                } catch {
                    #if LOG_DEBUG
                    LoggerService.debug(category: "Shaders", "Failed to compile all_shaders.metal: \(error)")
                    #endif
                }
            }

            // Try individual shader files as last resort
            let shaderFiles = ["CRTFilter", "CRTTest", "LCDGrid", "VibrantLCD", "DotMatrixLCD", "EdgeSmooth", "Composite", "Passthrough", "8bGameBoyColor"]
            for file in shaderFiles {
                let filePath = (bundlePath as NSString).appendingPathComponent("\(file).metal")
                if let source = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    do {
                        let library = try device.makeLibrary(source: source, options: nil)
                        LoggerService.info(category: "Shaders", "Compiled \(file).metal with functions: \(library.functionNames.joined(separator: ", "))")
                        return library
                    } catch {
                        #if LOG_DEBUG
                        LoggerService.debug(category: "Shaders", "Failed to compile \(file).metal: \(error)")
                        #endif
                    }
                }
            }
        }

        return nil
    }
}

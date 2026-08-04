import Metal
import Foundation

class SlangCompilerService: ObservableObject {
    static let shared = SlangCompilerService()

    @Published private(set) var activePreset: SlangPreset?

    private let chainLock = NSLock()
    private var _filterChain: OpaquePointer?
    private var _queue: MTLCommandQueue?

    /// Cached flag mirroring `activePreset?.usesAbsoluteFinalPass` so the
    /// `nonisolated renderFrame` path can read it without touching the
    /// `@MainActor`-bound `activePreset`. Updated synchronously inside
    /// `loadAndActivatePreset` and `destroyFilterChain`.
    nonisolated(unsafe) private var _finalPassIsAbsolute: Bool = false

    /// Cached flag mirroring `activePreset?.hasPassFeedbackWithSourceScale`.
    /// When true, the Metal coordinator must render the chain into a
    /// source-sized offscreen texture instead of the host drawable, then
    /// upscale to the drawable itself. This works around a librashader
    /// Metal-runtime scissor bug for PassFeedback chains (see
    /// `SlangPreset.hasPassFeedbackWithSourceScale` for details).
    nonisolated(unsafe) private var _needsSourceSizedOutput: Bool = false

    private init() {}

    func loadAndActivatePreset(at url: URL, queue: MTLCommandQueue) throws -> SlangPreset {
        var presetPtr: OpaquePointer?
        var opts = libra_preset_opt_t(
            version: 5,
            original_aspect_uniforms: true,
            frametime_uniforms: true,
            sensor_uniforms: false
        )

        let cpath = url.path
        let errRet = cpath.withCString { cpath in
            withUnsafeMutablePointer(to: &opts) { optPtr in
                withUnsafeMutablePointer(to: &presetPtr) { outPtr in
                    libra_preset_create_with_options(
                        cpath,
                        nil,
                        optPtr,
                        outPtr
                    )
                }
            }
        }

        if errRet != nil {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(errRet, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = errRet
            libra_error_free(&errCopy)
            throw SlangError.presetLoadFailed(msg)
        }
        guard let preset = presetPtr else {
            throw SlangError.presetLoadFailed("nil preset pointer")
        }

        let slangPreset = try SlangPreset.from(librashader: preset, at: url, queue: queue)

        destroyFilterChain()
        chainLock.lock()
        self._queue = queue
        chainLock.unlock()

        var chainOpts = filter_chain_mtl_opt_t(
            version: 5,
            force_no_mipmaps: false
        )
        var chainPtr: OpaquePointer?
        var presetVar: OpaquePointer? = preset
        let createErr = withUnsafeMutablePointer(to: &chainPtr) { outPtr in
            slang_mtl_filter_chain_create(
                &presetVar, queue, &chainOpts, outPtr
            )
        }

        if createErr != nil {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(createErr, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = createErr
            libra_error_free(&errCopy)
            throw SlangError.chainCreateFailed(msg)
        }
        guard let chain = chainPtr else {
            throw SlangError.chainCreateFailed("nil chain pointer")
        }

        chainLock.lock()
        _filterChain = chain
        _queue = queue
        _finalPassIsAbsolute = slangPreset.usesAbsoluteFinalPass
        _needsSourceSizedOutput = slangPreset.hasPassFeedbackWithSourceScale
        chainLock.unlock()
        activePreset = slangPreset
        LoggerService.info(category: "Slang", "Chain created successfully for preset: \(slangPreset.name) (final_pass_absolute=\(slangPreset.usesAbsoluteFinalPass), pass_feedback_source=\(slangPreset.hasPassFeedbackWithSourceScale))")
        return slangPreset
    }

    /// Nonisolated read of the cached `final_pass_is_absolute` flag for the
    /// chain that is currently active. Read by `renderFrame`'s callers to
    /// decide on a viewport strategy without touching `@MainActor` state.
    nonisolated var finalPassIsAbsolute: Bool {
        Self.shared.chainLock.withLock { Self.shared._finalPassIsAbsolute }
    }

    /// Nonisolated read of the cached `needs_source_sized_output` flag.
    /// When true, the Metal coordinator must render the chain into a
    /// source-sized offscreen texture instead of the host drawable (see
    /// `_needsSourceSizedOutput` for the librashader scissor-bug rationale).
    nonisolated var needsSourceSizedOutput: Bool {
        Self.shared.chainLock.withLock { Self.shared._needsSourceSizedOutput }
    }

    nonisolated func renderFrame(commandBuffer: MTLCommandBuffer,
                                  inputTexture: MTLTexture,
                                  outputTexture: MTLTexture,
                                  frameCount: UInt64,
                                  viewport: MTLViewport,
                                  aspectRatio: Float) {
        let chain: OpaquePointer? = Self.shared.chainLock.withLock {
            Self.shared._filterChain
        }
        guard let chain = chain else {
            #if LOG_DEBUG
            LoggerService.debug(category: "Slang", "renderFrame: no chain")
            #endif
            return
        }

        let libraVP = libra_viewport_t(
            x: Float(viewport.originX),
            y: Float(viewport.originY),
            width: UInt32(viewport.width),
            height: UInt32(viewport.height)
        )
        // Visual rotation is applied at the CAMetalLayer level
        // (MetalCoordinator.mtkView:drawableSizeWillChange:), mirroring
        // the built-in shader path. We pass rotation=0 here so librashader
        // does not double-rotate the chain's output texture.
        var frameOpts = frame_mtl_opt_t(
            version: 5,
            clear_history: false,
            frame_direction: 1,
            rotation: 0,
            total_subframes: 1,
            current_subframe: 1,
            aspect_ratio: aspectRatio,
            frames_per_second: 0,
            frametime_delta: 0,
            color_space: LIBRA_COLOR_SPACE_SDR.rawValue,
            brightness_nits: 200.0,
            expand_gamut: 0,
            gyroscope: (Float(0), Float(0), Float(0)),
            accelerometer: (Float(0), Float(0), Float(0)),
            accelerometer_rest: (Float(0), Float(0), Float(0))
        )

        var chainVar: OpaquePointer? = chain
        var libraVPVar = libraVP
        let renderErr = slang_mtl_filter_chain_frame(
            &chainVar, commandBuffer, Int(frameCount),
            inputTexture, outputTexture,
            &libraVPVar,
            nil,
            &frameOpts
        )
        if let err = renderErr {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(err, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = err
            libra_error_free(&errCopy)
            LoggerService.error(category: "Slang", "renderFrame error: \(msg)")
        }
    }

    nonisolated func setParameter(name: String, value: Float) {
        guard let chain = Self.shared.chainLock.withLock({
            Self.shared._filterChain
        }) else { return }
        var chainVar: OpaquePointer? = chain
        var setErr: OpaquePointer?
        name.withCString { cname in
            setErr = slang_mtl_filter_chain_set_param(&chainVar, cname, value)
        }
        if let err = setErr {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(err, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = err
            libra_error_free(&errCopy)
            LoggerService.error(category: "Slang", "setParameter(\(name)=\(value)) error: \(msg)")
        }
    }

    func destroyFilterChain() {
        chainLock.lock()
        let chain = _filterChain
        _filterChain = nil
        _queue = nil
        _finalPassIsAbsolute = false
        _needsSourceSizedOutput = false
        chainLock.unlock()
        if let chain = chain {
            var chainVar: OpaquePointer? = chain
            let freeErr = slang_mtl_filter_chain_free(&chainVar)
            if let err = freeErr {
                var errStr: UnsafeMutablePointer<CChar>?
                libra_error_write(err, &errStr)
                let msg = errStr.map { String(cString: $0) } ?? "unknown error"
                libra_error_free_string(&errStr)
                var errCopy: OpaquePointer? = err
                libra_error_free(&errCopy)
                LoggerService.error(category: "Slang", "destroyFilterChain error: \(msg)")
            }
        }
        activePreset = nil
    }

    deinit {
        chainLock.lock()
        let chain = _filterChain
        _filterChain = nil
        chainLock.unlock()
        if let chain = chain {
            var chainVar: OpaquePointer? = chain
            let freeErr = slang_mtl_filter_chain_free(&chainVar)
            if let err = freeErr {
                var errStr: UnsafeMutablePointer<CChar>?
                libra_error_write(err, &errStr)
                let msg = errStr.map { String(cString: $0) } ?? "unknown error"
                libra_error_free_string(&errStr)
                LoggerService.error(category: "Slang", "deinit chain free error: \(msg)")
            }
        }
    }
}

enum SlangError: LocalizedError {
    case presetLoadFailed(String)
    case chainCreateFailed(String)

    var errorDescription: String? {
        switch self {
        case .presetLoadFailed(let msg): return "Failed to load slang preset: \(msg)"
        case .chainCreateFailed(let msg): return "Failed to create filter chain: \(msg)"
        }
    }
}

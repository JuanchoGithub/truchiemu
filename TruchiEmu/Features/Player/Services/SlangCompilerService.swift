import Metal
import Foundation

class SlangCompilerService: ObservableObject {
    static let shared = SlangCompilerService()

    @Published private(set) var activePreset: SlangPreset?

    private let chainLock = NSLock()
    private var _filterChain: OpaquePointer?
    private var _queue: MTLCommandQueue?

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
        chainLock.unlock()
        activePreset = slangPreset
        LoggerService.info(category: "Slang", "Chain created successfully for preset: \(slangPreset.name)")
        return slangPreset
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
        #if LOG_DEBUG
        LoggerService.debug(category: "Slang", "renderFrame sizes: in=\(inputTexture.width)x\(inputTexture.height) out=\(outputTexture.width)x\(outputTexture.height) vp=\(UInt32(viewport.width))x\(UInt32(viewport.height)) ar=\(aspectRatio)")
        #endif

        let libraVP = libra_viewport_t(
            x: Float(viewport.originX),
            y: Float(viewport.originY),
            width: UInt32(viewport.width),
            height: UInt32(viewport.height)
        )
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
        if renderErr != nil {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(renderErr, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            LoggerService.error(category: "Slang", "renderFrame error: \(msg)")
        }
    }

    nonisolated func setParameter(name: String, value: Float) {
        guard let chain = Self.shared.chainLock.withLock({
            Self.shared._filterChain
        }) else { return }
        var chainVar: OpaquePointer? = chain
        name.withCString { cname in
            slang_mtl_filter_chain_set_param(&chainVar, cname, value)
            return ()
        }
    }

    func destroyFilterChain() {
        chainLock.lock()
        let chain = _filterChain
        _filterChain = nil
        _queue = nil
        chainLock.unlock()
        if let chain = chain {
            var chainVar: OpaquePointer? = chain
            slang_mtl_filter_chain_free(&chainVar)
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
            slang_mtl_filter_chain_free(&chainVar)
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

import Metal
import Foundation

/// A fully parsed and compiled slang filter chain, ready to install.
/// Built off the main thread by `SlangCompilerService.prepareChain` and
/// handed back to the main thread, which installs it, caches it, or
/// frees it.
struct PreparedSlangChain {
    let chain: OpaquePointer
    let preset: SlangPreset
    let queue: MTLCommandQueue
    /// mtime fingerprint captured at prepare time
    /// (see `SlangPreset.chainFingerprint`). Zero when no fingerprint
    /// could be computed.
    let fingerprint: UInt64
}

class SlangCompilerService: ObservableObject {
    static let shared = SlangCompilerService()

    @Published private(set) var activePreset: SlangPreset?

    private let chainLock = NSLock()
    private var _filterChain: OpaquePointer?
    private var _queue: MTLCommandQueue?

    /// Cached flag mirroring `activePreset?.usesAbsoluteFinalPass` so the
    /// `nonisolated renderFrame` path can read it without touching the
    /// `@MainActor`-bound `activePreset`. Updated synchronously inside
    /// `installPreparedChain` and `destroyFilterChain`.
    nonisolated(unsafe) private var _finalPassIsAbsolute: Bool = false
    nonisolated(unsafe) private var _needsSourceSizedIntermediate: Bool = false
    /// Multipliers applied to the input texture to size the source-scaled
    /// intermediate (usually 1x1; source-scaled passes can make it larger or
    /// smaller). Mirrors `SlangPreset.sourceSizedIntermediateScale`.
    nonisolated(unsafe) private var _sourceSizedIntermediateScale: (x: Float, y: Float) = (1, 1)

    /// Set by `requestHistoryClear()` and consumed by the next `renderFrame`.
    nonisolated(unsafe) private var _clearHistoryRequested: Bool = false

    // MARK: - Prepared-chain cache
    //
    // Compiling a chain (parse + GLSL→SPIR-V→MSL + Metal pipeline
    // creation) costs hundreds of milliseconds; installing an already
    // compiled one costs microseconds. The cache keeps recently retired
    // chains alive so switching back to them is instant. Entries are
    // validated against an mtime fingerprint of the .slangp and every
    // referenced shader / include / LUT, so an on-disk edit forces a
    // rebuild.
    //
    // All cache state is guarded by `chainLock`. Chain frees always run
    // outside the lock. `activePreset` (a @Published property) is set
    // outside the lock, matching the previous behavior.
    private struct ChainCacheEntry {
        let fingerprint: UInt64
        let prepared: PreparedSlangChain
        var lastUsed: Date
    }
    private var chainCache: [String: ChainCacheEntry] = [:]
    private let chainCacheCapacity = 4
    /// The prepared chain currently installed as `_filterChain`, with the
    /// disk fingerprint it was built against. Lets a swapped-out chain
    /// return to the cache without re-deriving its metadata.
    private var activePrepared: PreparedSlangChain?

    private init() {}

    /// Parses and compiles a slang preset into a ready-to-install filter
    /// chain without touching any shared state. Safe to run off the main
    /// thread: the previously installed chain keeps rendering (on the
    /// main thread) until `installPreparedChain` swaps this one in.
    nonisolated static func prepareChain(at url: URL, queue: MTLCommandQueue) throws -> PreparedSlangChain {
        #if LOG_DEBUG
        let startedAt = CFAbsoluteTimeGetCurrent()
        var parsedAt = CFAbsoluteTimeGetCurrent()
        #endif

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

        #if LOG_DEBUG
        parsedAt = CFAbsoluteTimeGetCurrent()
        #endif

        let slangPreset = try SlangPreset.from(librashader: preset, at: url, queue: queue)

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

        let fingerprint = SlangPreset.chainFingerprint(at: url) ?? 0

        #if LOG_DEBUG
        let endedAt = CFAbsoluteTimeGetCurrent()
        LoggerService.debug(category: "Slang", "prepareChain '\(url.lastPathComponent)': parse \(Int((parsedAt - startedAt) * 1000))ms, compile \(Int((endedAt - parsedAt) * 1000))ms")
        #endif

        return PreparedSlangChain(chain: chain, preset: slangPreset, queue: queue, fingerprint: fingerprint)
    }

    /// Synchronous prepare + install. Used by the game-launch path
    /// (before the render loop starts), the Apply button, and the slang
    /// audit. Interactive picker selections use
    /// `ShaderManager.reflectSlangPreset` instead, which prepares off the
    /// main thread so the game never stalls.
    func loadAndActivatePreset(at url: URL, queue: MTLCommandQueue) throws -> SlangPreset {
        let prepared = try Self.prepareChain(at: url, queue: queue)
        return installPreparedChain(prepared)
    }

    /// Installs a prepared chain as the active one and returns its
    /// preset. The previously active chain returns to the prepared-chain
    /// cache (capacity permitting) or is freed.
    ///
    /// `clearHistory` asks the next `renderFrame` to clear the chain's
    /// history textures. Pass `true` only when installing a chain that has
    /// rendered before (a cache hit): its history still holds frames from
    /// the previous run. Never pass it for a fresh chain — librashader's
    /// Metal runtime builds the clear render pass from the chain's
    /// history list, which is still EMPTY on a fresh chain, and the empty
    /// render-pass descriptor makes encoder creation fail
    /// (`FailedToCreateCommandBuffer`), dropping the first frame.
    func installPreparedChain(_ prepared: PreparedSlangChain, clearHistory: Bool = false) -> SlangPreset {
        let key = prepared.preset.path.path
        chainLock.lock()
        let oldChain = _filterChain
        _filterChain = prepared.chain
        _queue = prepared.queue
        _finalPassIsAbsolute = prepared.preset.usesAbsoluteFinalPass
        _needsSourceSizedIntermediate = prepared.preset.needsSourceSizedIntermediate
        _sourceSizedIntermediateScale = prepared.preset.sourceSizedIntermediateScale
        _clearHistoryRequested = clearHistory
        let oldPrepared = activePrepared
        activePrepared = prepared
        // A stale cache entry for the same preset (older build) is dead
        // weight now that this build is active; collect it for freeing.
        let staleSameKey = chainCache.removeValue(forKey: key)?.prepared
        chainLock.unlock()

        activePreset = prepared.preset

        if let oldPrepared = oldPrepared {
            storeInChainCache(oldPrepared)
        } else if let oldChain = oldChain {
            // Defensive: a chain pointer without prepared metadata cannot
            // be cached, so free it directly.
            var chainVar: OpaquePointer? = oldChain
            slang_mtl_filter_chain_free(&chainVar)
        }
        if let staleSameKey = staleSameKey {
            freePreparedChain(staleSameKey)
        }

        LoggerService.info(category: "Slang", "Chain activated for preset: \(prepared.preset.name) (final_pass_absolute=\(prepared.preset.usesAbsoluteFinalPass), final_pass_feedback=\(prepared.preset.hasFinalPassFeedback), source_sized_intermediate=\(prepared.preset.needsSourceSizedIntermediate))")
        return prepared.preset
    }

    /// True when the active chain was built from the preset at `url` and
    /// the on-disk fingerprint still matches — re-selecting that preset
    /// then needs no rebuild at all.
    func activeChainIsFresh(at url: URL) -> Bool {
        chainLock.lock()
        let prepared = activePrepared
        chainLock.unlock()
        guard let prepared = prepared,
              prepared.preset.path.path == url.path,
              let current = SlangPreset.chainFingerprint(at: url),
              current == prepared.fingerprint else { return false }
        return true
    }

    /// Returns the cached prepared chain for `url` when its stored
    /// fingerprint still matches disk, removing it from the cache (the
    /// caller installs it). A stale entry is freed instead.
    func takeFreshChainFromCache(at url: URL) -> PreparedSlangChain? {
        chainLock.lock()
        let entry = chainCache.removeValue(forKey: url.path)
        chainLock.unlock()
        guard let entry = entry else { return nil }
        if let current = SlangPreset.chainFingerprint(at: url), current == entry.fingerprint {
            #if LOG_DEBUG
            LoggerService.debug(category: "Slang", "Chain cache hit for '\(url.lastPathComponent)'")
            #endif
            return entry.prepared
        }
        freePreparedChain(entry.prepared)
        return nil
    }

    /// Frees a prepared chain that will not be installed (stale
    /// background completion) or that was evicted from the cache.
    func discardPreparedChain(_ prepared: PreparedSlangChain) {
        freePreparedChain(prepared)
    }

    private func storeInChainCache(_ prepared: PreparedSlangChain) {
        let key = prepared.preset.path.path
        var victims: [PreparedSlangChain] = []
        chainLock.lock()
        if let existing = chainCache.removeValue(forKey: key)?.prepared {
            victims.append(existing)
        }
        while chainCache.count >= chainCacheCapacity,
              let oldestKey = chainCache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            if let evicted = chainCache.removeValue(forKey: oldestKey)?.prepared {
                victims.append(evicted)
            }
        }
        chainCache[key] = ChainCacheEntry(fingerprint: prepared.fingerprint,
                                          prepared: prepared,
                                          lastUsed: Date())
        chainLock.unlock()
        for victim in victims {
            freePreparedChain(victim)
        }
    }

    private func freePreparedChain(_ prepared: PreparedSlangChain) {
        var chainVar: OpaquePointer? = prepared.chain
        let freeErr = slang_mtl_filter_chain_free(&chainVar)
        if let err = freeErr {
            var errStr: UnsafeMutablePointer<CChar>?
            libra_error_write(err, &errStr)
            let msg = errStr.map { String(cString: $0) } ?? "unknown error"
            libra_error_free_string(&errStr)
            var errCopy: OpaquePointer? = err
            libra_error_free(&errCopy)
            LoggerService.error(category: "Slang", "freePreparedChain error: \(msg)")
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "Slang", "Freed uninstalled slang chain for '\(prepared.preset.name)'")
        #endif
    }

    /// Nonisolated read of the cached `final_pass_is_absolute` flag for the
    /// chain that is currently active. Read by `renderFrame`'s callers to
    /// decide on a viewport strategy without touching `@MainActor` state.
    nonisolated var finalPassIsAbsolute: Bool {
        Self.shared.chainLock.withLock { Self.shared._finalPassIsAbsolute }
    }

    /// Asks the next `renderFrame` to clear the chain's history textures.
    /// Call after a save-state load or a core reset, so temporal effects do
    /// not blend frames from before the state change.
    nonisolated func requestHistoryClear() {
        Self.shared.chainLock.withLock {
            Self.shared._clearHistoryRequested = true
        }
    }

    /// Nonisolated read of the cached `needs_source_sized_intermediate` flag.
    /// True only for chains whose final pass explicitly declares
    /// `scale_type = source` on both axes and whose earlier passes are not
    /// viewport/absolute-scaled (see `SlangPreset.needsSourceSizedIntermediate`).
    nonisolated var needsSourceSizedIntermediate: Bool {
        Self.shared.chainLock.withLock { Self.shared._needsSourceSizedIntermediate }
    }

    /// Multipliers the source-sized intermediate applies to the input texture.
    /// `(1, 1)` unless the active chain scales source passes.
    nonisolated var sourceSizedIntermediateScale: (x: Float, y: Float) {
        Self.shared.chainLock.withLock { Self.shared._sourceSizedIntermediateScale }
    }

    nonisolated func renderFrame(commandBuffer: MTLCommandBuffer,
                                  inputTexture: MTLTexture,
                                  outputTexture: MTLTexture,
                                  frameCount: UInt64,
                                  viewport: MTLViewport,
                                  aspectRatio: Float,
                                  frameDirection: Int32 = 1,
                                  framesPerSecond: Float = 0,
                                  frametimeDelta: UInt32 = 0) {
        let (chain, clearHistory): (OpaquePointer?, Bool) = Self.shared.chainLock.withLock {
            let requested = Self.shared._clearHistoryRequested
            Self.shared._clearHistoryRequested = false
            return (Self.shared._filterChain, requested)
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
            clear_history: clearHistory,
            frame_direction: frameDirection,
            rotation: 0,
            total_subframes: 1,
            current_subframe: 1,
            aspect_ratio: aspectRatio,
            frames_per_second: framesPerSecond,
            frametime_delta: frametimeDelta,
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
        _needsSourceSizedIntermediate = false
        _sourceSizedIntermediateScale = (1, 1)
        _clearHistoryRequested = false
        activePrepared = nil
        // Slang was deactivated outright: the prepared-chain cache is dead
        // weight too, so free every retired chain.
        let cached = Array(chainCache.values.map(\.prepared))
        chainCache.removeAll()
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
        for prepared in cached {
            freePreparedChain(prepared)
        }
        activePreset = nil
    }

    deinit {
        chainLock.lock()
        let chain = _filterChain
        _filterChain = nil
        let cached = Array(chainCache.values.map(\.prepared))
        chainCache.removeAll()
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
        for prepared in cached {
            freePreparedChain(prepared)
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

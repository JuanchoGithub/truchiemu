import Metal
import MetalKit
import Foundation

// Manages shader pipeline states, uniform buffers, and shader preset selection.
// Thread-safe singleton that handles dynamic shader switching without recompilation.
@MainActor
class ShaderManager: ObservableObject {
    static let shared = ShaderManager()
    
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    
    // Pipeline state cache keyed by shader function name
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    
    // Current active preset
    @Published var activePreset: ShaderPreset = .defaultPreset
    
    // Currently active slang preset (if any)
    @Published var activeSlangPreset: SlangPreset? = nil
    
    // Current uniform values (updated by UI sliders)
    @Published private(set) var uniformValues: [String: Float] = [:]
    
    // Thread-safe storage for the renderer (nonisolated for thread-safe renderer access)
    private nonisolated(unsafe) static let parameterStore = ShaderParameterStore()
    
    init() {
        setupDevice()
        loadLibrary()
        createVertexBuffer()
        
        // Load saved default shader preset if configured, otherwise use built-in default
        let savedDefaultID = AppSettings.get("display_default_shader_preset", type: String.self) ?? ""
        if !savedDefaultID.isEmpty {
            // Check built-in presets first
            if let preset = ShaderPreset.preset(id: savedDefaultID) {
                activatePreset(preset)
            } else {
                // Check saved custom presets (by UUID string)
                if let savedPreset = ShaderPresetStorageService.shared.savedPresets.first(where: { $0.id.uuidString == savedDefaultID }) {
                    activateSavedPreset(savedPreset)
                } else {
                    loadDefaultUniforms()
                }
            }
        } else {
            loadDefaultUniforms()
        }
    }
    
    // Vertex buffer for fullscreen quad
    private var vertexBuffer: MTLBuffer?
    
    // Texture cache for intermediate passes
    private var texturePool: [MTLTexture] = []
    
    // Metal library reference
    private var library: MTLLibrary?
    
    
    func activateSlangPreset(_ preset: SlangPreset, overrides: [String: Float] = [:]) {
        do {
            let reflected = try SlangCompilerService.shared.loadAndActivatePreset(at: preset.path, queue: commandQueue ?? device!.makeCommandQueue()!)
            activeSlangPreset = reflected
            activePreset = ShaderPreset.defaultPreset
            clearPipelineCache()
            Self.parameterStore.updateFragmentFunctionName("slang")

            var values = reflected.parameterDefaults
            for (name, value) in overrides {
                values[name] = value
                SlangCompilerService.shared.setParameter(name: name, value: value)
            }
            uniformValues = values

            LoggerService.info(category: "ShaderManager", "Activated slang shader preset: \(preset.name) (params=\(reflected.parameters.count))")
        } catch {
            LoggerService.error(category: "ShaderManager", "Failed to activate slang preset: \(error.localizedDescription)")
        }
    }

    func deactivateSlangPreset() {
        SlangCompilerService.shared.destroyFilterChain()
        activeSlangPreset = nil
        resetToDefault()
    }

    func resetToDefault() {
        // Reset to the default preset
        if let defaultPreset = ShaderPreset.preset(id: ShaderPreset.defaultPreset.id) {
            activatePreset(defaultPreset)
        } else {
            // Fallback if even the default preset can't be found
            activePreset = ShaderPreset.defaultPreset
        }
        
        // Reset all uniform values to their defaults
        let defaults = activePreset.globalUniforms
        var newUniforms: [String: Float] = [:]
        defaults.forEach { uniform in
            newUniforms[uniform.name] = uniform.defaultValue
        }
        uniformValues = newUniforms
        Self.parameterStore.update(with: newUniforms)
        
        #if LOG_DEBUG
        LoggerService.debug(category: "ShaderManager", "Shader manager reset to default")
        #endif
    }
    
    
    // MARK: - Setup    
    private func setupDevice() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
    }
    
    private func loadLibrary() {
        library = device?.makeDefaultLibrary()
        if library == nil {
            LoggerService.info(category: "ShaderManager", "WARNING: Could not create default Metal library")
        }
    }
    
    private func createVertexBuffer() {
        // Fullscreen quad vertices: 4 corners, position + texcoord
        struct Vertex {
            var position: SIMD2<Float>
            var texCoord: SIMD2<Float>
        }
        
        let vertices: [Vertex] = [
            Vertex(position: [-1, -1], texCoord: [0, 1]),
            Vertex(position: [ 1, -1], texCoord: [1, 1]),
            Vertex(position: [-1,  1], texCoord: [0, 0]),
            Vertex(position: [ 1,  1], texCoord: [1, 0]),
        ]
        
        let bufferSize = vertices.count * MemoryLayout<Vertex>.stride
        vertexBuffer = device?.makeBuffer(bytes: vertices, length: bufferSize, options: [])
    }
    
    private func loadDefaultUniforms() {
        // Set default values from current preset
        var newUniforms: [String: Float] = [:]
        for uniform in activePreset.globalUniforms {
            newUniforms[uniform.name] = uniform.defaultValue
        }
        uniformValues = newUniforms
        Self.parameterStore.update(with: newUniforms)
    }
    
    // MARK: - Pipeline State Management
    
    // Get or create pipeline state for a shader function
    func getPipelineState(for shaderName: String) -> MTLRenderPipelineState? {
        // Check cache first
        if let cached = pipelineCache[shaderName] {
            return cached
        }
        
        // Create new pipeline
        guard let library = library,
              let device = device else {
            LoggerService.info(category: "ShaderManager", "ERROR: Library or device not available")
            return nil
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
              let fragmentFunction = library.makeFunction(name: shaderName) else {
            LoggerService.info(category: "ShaderManager", "ERROR: Could not find shader function '\(shaderName)'")
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelineCache[shaderName] = pipeline
            #if LOG_DEBUG
            LoggerService.debug(category: "ShaderManager", "Created pipeline for '\(shaderName)'")
            #endif
            return pipeline
        } catch {
            LoggerService.info(category: "ShaderManager", "ERROR: Failed to create pipeline for '\(shaderName)': \(error)")
            return nil
        }
    }
    
    // Clear all cached pipeline states (call when shaders change)
    func clearPipelineCache() {
        pipelineCache.removeAll()
    }
    
    // MARK: - Preset Management
    
    // Switch to a new shader preset
    func activatePreset(_ preset: ShaderPreset) {
        activePreset = preset
        clearPipelineCache()
        
        // Reset uniform values to preset defaults
        var newUniforms: [String: Float] = [:]
        for uniform in preset.globalUniforms {
            newUniforms[uniform.name] = uniform.defaultValue
        }
        uniformValues = newUniforms
        Self.parameterStore.update(with: newUniforms)
        
        // Update cached fragment function name
        let fragmentName = deriveFragmentFunctionName(from: preset)
        Self.parameterStore.updateFragmentFunctionName(fragmentName)
        
        LoggerService.info(category: "ShaderManager", "Activated shader preset: \(preset.name)")
    }
    
    // Activate preset and apply saved uniform overrides (used by saved presets)
    func activatePresetWithOverrides(presetID: String, overrides: [String: Float]) {
        guard let preset = ShaderPreset.preset(id: presetID) else { return }
        activePreset = preset
        clearPipelineCache()

        var merged: [String: Float] = [:]
        for uniform in preset.globalUniforms {
            merged[uniform.name] = overrides[uniform.name] ?? uniform.defaultValue
        }
        uniformValues = merged
        Self.parameterStore.update(with: merged)

        let fragmentName = deriveFragmentFunctionName(from: preset)
        Self.parameterStore.updateFragmentFunctionName(fragmentName)
    }

    // Activate a saved preset whose base may be a built-in Metal preset or a slang .slangp path.
    func activateSavedPreset(_ saved: SavedShaderPreset) {
        if let slangPreset = SlangPresetDiscoveryService.shared.presets.first(where: { $0.path.path == saved.basePresetID }) {
            activateSlangPreset(slangPreset, overrides: saved.uniformValues)
        } else {
            // If the saved base looks like a slang path but the lookup missed,
            // the preset file was moved/deleted between launches or didn't
            // survive a discovery-cache rebuild.
            if saved.basePresetID.contains("slang-shaders") {
                LoggerService.error(category: "ShaderManager", "activateSavedPreset: slang preset at \(saved.basePresetID) is no longer discoverable; falling back to built-in lookup")
            }
            activatePresetWithOverrides(presetID: saved.basePresetID, overrides: saved.uniformValues)
        }
    }

    // Update a uniform value
    func updateUniform(_ name: String, value: Float) {
        uniformValues[name] = value
        Self.parameterStore.update(name: name, value: value)
        
    }
    
    // Get current value for a uniform
    func getUniform(_ name: String) -> Float {
        uniformValues[name] ?? 0.0
    }
    
    // Thread-safe way to get a snapshot of all uniforms for the renderer
    nonisolated func getUniformSnapshot() -> [String: Float] {
        return Self.parameterStore.getSnapshot()
    }

    // Optimized snapshot read for the renderer: returns a fresh dict copy only
    // when the writer has mutated state since the caller's cachedGeneration.
    // Otherwise returns nil (caller keeps its existing copy). The renderer
    // stores the latest generation it has seen and only pays for a full dict
    // copy when a real mutation has occurred (live shader edit slider tick or
    // preset activation). During normal gameplay this means the snapshot is
    // fetched once at the first frame after launch and never copied again.
    nonisolated func getUniformSnapshotIfChanged(cachedGeneration: UInt64) -> (snapshot: [String: Float], generation: UInt64, didChange: Bool)? {
        return Self.parameterStore.getSnapshotIfChanged(cachedGeneration: cachedGeneration)
    }

    // Thread-safe way to get the current fragment function name for the renderer
    nonisolated func getCurrentFragmentFunctionName() -> String {

        return Self.parameterStore.getFragmentFunctionName()
    }
    
    // Internal method to sync snapshot after batch updates (like activatePreset)
    func syncSnapshot() {
        Self.parameterStore.update(with: uniformValues)
    }
    
    // MARK: - Helper Methods
    
    private func deriveFragmentFunctionName(from preset: ShaderPreset) -> String {
        guard let firstPass = preset.passes.first,
              let shaderFile = firstPass.shaderFile.components(separatedBy: ".").first else {
            return "fragmentPassthrough"
        }
        
        let result: String
        switch shaderFile {
        case "CRTFilter": result = "fragmentCRT"
        case "DotMatrixLCD": result = "fragmentDotMatrixLCD"
        case "LottesCRT": result = "fragmentLottesCRT"
        case "SharpBilinear": result = "fragmentSharpBilinear"
        case "LCDGrid": result = "fragmentLCDGrid"
        case "LiteCRT": result = "fragmentLiteCRT"
        case "ScaleSmooth": result = "fragmentScaleSmooth"
        case "Passthrough": result = "fragmentPassthrough"
        case "8bGameBoyColor": result = "fragment8BitGBC"
        case "GBA": result = "fragmentGBAShader"
        case "PSP": result = "fragmentPSPShader"
        case "CRTFilter_multipass": result = "fragmentCRTMultipass"
        case "FamicomRF": result = "fragmentFamicomRF"
        case "RfDecoder": result = "fragmentRfDisplay"
        default: result = "fragment" + shaderFile
        }
        
        #if LOG_EXTREME
        LoggerService.extreme(category: "Shaders", "ShaderFile: '\(shaderFile)' -> Fragment: '\(result)'")
        #endif
        return result
    }
    
// MARK: - Preset Groups for UI

// Get presets grouped by type for organized UI display
static func presetsGroupedByType() -> [(type: ShaderType, presets: [ShaderPreset])] {
var grouped: [ShaderType: [ShaderPreset]] = [:]

for preset in ShaderPreset.allPresets {
if grouped[preset.shaderType] == nil {
grouped[preset.shaderType] = []
}
grouped[preset.shaderType]?.append(preset)
}

return ShaderType.allCases.map { type in
(type: type, presets: grouped[type] ?? [])
}
}

// Get recommended presets for a specific system
func recommendedPresets(for systemID: String) -> [ShaderPreset] {
ShaderPreset.allPresets.filter { preset in
preset.recommendedSystems.contains(systemID)
}
}
    
    // Get a human-readable display name for a preset
    static func displayName(for presetID: String) -> String {
        if let p = ShaderPreset.preset(id: presetID) { return p.name }
        if SlangPresetDiscoveryService.shared.presets.contains(where: { $0.path.path == presetID }) {
            return URL(fileURLWithPath: presetID).deletingPathExtension().lastPathComponent
        }
        return "None"
    }
}

// MARK: - Thread-Safe Parameter Storage

/// A non-isolated storage class to hold shader parameters for the rendering thread.
/// This prevents data races and actor isolation conflicts between the Main Actor (UI)
// and the background rendering thread.
private class ShaderParameterStore {
    private var snapshot: [String: Float] = [:]
    private var currentFragmentFunctionName: String = "fragmentPassthrough"
    // Monotonic version bumped on every mutation. Readers compare their
    // cached generation against this to skip re-copying the snapshot when no
    // change has occurred. During normal gameplay no mutations happen after
    // launch, so the renderer copies the snapshot once and reads it free of
    // cost on every subsequent frame. During live shader editing, mutations
    // bump the generation and the renderer re-copies lazily on the next draw.
    private var generation: UInt64 = 0
    private let lock = NSLock()
    
    func update(with values: [String: Float]) {
        lock.lock()
        snapshot = values
        generation &+= 1
        lock.unlock()
    }
    
    func update(name: String, value: Float) {
        lock.lock()
        snapshot[name] = value
        generation &+= 1
        lock.unlock()
    }

    func updateFragmentFunctionName(_ name: String) {
        lock.lock()
        currentFragmentFunctionName = name
        lock.unlock()
    }
    
    func getSnapshot() -> [String: Float] {
        lock.lock()
        let copy = snapshot
        lock.unlock()
        return copy
    }

    // Returns the current generation (a lock-guarded Int read; effectively a
    // cheap atomic). Readers use this to detect whether their cached snapshot
    // is stale without paying for a full dict copy on every frame.
    func currentGeneration() -> UInt64 {
        lock.lock()
        let gen = generation
        lock.unlock()
        return gen
    }

    // Optimized snapshot read for the renderer: returns the cached snapshot
    // reference if the generation is unchanged since the last call, otherwise
    // takes a fresh copy under lock. The caller stores the returned snapshot
    // and passes the previous generation back in on the next call so we only
    // pay for a dict copy when the writer actually mutated state.
    func getSnapshotIfChanged(cachedGeneration: UInt64) -> (snapshot: [String: Float], generation: UInt64, didChange: Bool) {
        lock.lock()
        if generation == cachedGeneration {
            // No change. We cannot hand back the live internal ref because the
            // caller may read it concurrently with the next writer; callers
            // that want the cheap path must hold their own copy. Fall through
            // to return the caller's existing copy via the didChange=false flag.
            let gen = generation
            lock.unlock()
            return (snapshot: [:], generation: gen, didChange: false)
        }
        let copy = snapshot
        let gen = generation
        lock.unlock()
        return (snapshot: copy, generation: gen, didChange: true)
    }

    func getFragmentFunctionName() -> String {
        lock.lock()
        let name = currentFragmentFunctionName
        lock.unlock()
        return name
    }
}

// MARK: - Shader Uniform Buffer (matches Metal shader expectations)

// Standard uniform buffer structure passed to all fragment shaders
struct ShaderStandardUniforms {
    var SourceSize: SIMD4<Float>   // (width, height, 1/width, 1/height)
    var OutputSize: SIMD4<Float>   // (width, height, 1/width, 1/height)
    var time: Float
    var padding: SIMD3<Float>
}
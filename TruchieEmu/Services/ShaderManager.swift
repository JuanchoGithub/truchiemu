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
    
// Current uniform values (updated by UI sliders)
    @Published private(set) var uniformValues: [String: Float] = [:]
    
    // Thread-safe storage for the renderer
    private let parameterStore = ShaderParameterStore()

    init() {
        setupDevice()
        loadLibrary()
        createVertexBuffer()
        loadDefaultUniforms()
    }
    
    // Vertex buffer for fullscreen quad
    private var vertexBuffer: MTLBuffer?
    
    // Texture cache for intermediate passes
    private var texturePool: [MTLTexture] = []
    
    // Metal library reference
    private var library: MTLLibrary?
    
    
    func resetToDefault() {
        // Reset to the default preset
        if let defaultPreset = ShaderPreset.preset(id: ShaderPreset.defaultPreset.id) {
            activatePreset(defaultPreset)
        } else {
            // Fallback if even the default preset can't be found
            activePreset = ShaderPreset.defaultPreset
        }
        
        // Reset all uniform values to their defaults
        activePreset.globalUniforms.forEach { uniform in
            uniformValues[uniform.name] = uniform.defaultValue
        }
        
        LoggerService.debug(category: "ShaderManager", "Shader manager reset to default")
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
        for uniform in activePreset.globalUniforms {
            uniformValues[uniform.name] = uniform.defaultValue
        }
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
            LoggerService.debug(category: "ShaderManager", "Created pipeline for '\(shaderName)'")
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
        parameterStore.update(with: newUniforms)
        
        LoggerService.info(category: "ShaderManager", "Activated shader preset: \(preset.name)")
    }
    
    // Update a uniform value
    func updateUniform(_ name: String, value: Float) {
        uniformValues[name] = value
        parameterStore.update(name: name, value: value)
        
        LoggerService.debug(category: "ShaderManager", "Updated uniform '\(name)' to \(value)")
    }
    
    // Get current value for a uniform
    func getUniform(_ name: String) -> Float {
        uniformValues[name] ?? 0.0
    }

    // Thread-safe way to get a snapshot of all uniforms for the renderer
    nonisolated func getUniformSnapshot() -> [String: Float] {
        return parameterStore.getSnapshot()
    }

    // Internal method to sync snapshot after batch updates (like activatePreset)
    func syncSnapshot() {
        parameterStore.update(with: uniformValues)
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
        ShaderPreset.preset(id: presetID)?.name ?? "None"
    }
}

// MARK: - Thread-Safe Parameter Storage

/// A non-isolated storage class to hold shader parameters for the rendering thread.
/// This prevents data races and actor isolation conflicts between the Main Actor (UI)
// and the background rendering thread.
private class ShaderParameterStore {
    private var snapshot: [String: Float] = [:]
    private let lock = NSLock()

    func update(with values: [String: Float]) {
        lock.lock()
        snapshot = values
        lock.unlock()
    }

    func update(name: String, value: Float) {
        lock.lock()
        snapshot[name] = value
        lock.unlock()
    }

    func getSnapshot() -> [String: Float] {
        lock.lock()
        let copy = snapshot
        lock.unlock()
        return copy
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
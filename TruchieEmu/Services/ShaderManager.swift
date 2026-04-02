import Metal
import MetalKit
import Foundation

// MARK: - Shader Manager

/// Manages shader pipeline states, uniform buffers, and shader preset selection.
/// Thread-safe singleton that handles dynamic shader switching without recompilation.
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
    @Published var uniformValues: [String: Float] = [:]
    
    // Vertex buffer for fullscreen quad
    private var vertexBuffer: MTLBuffer?
    
    // Texture cache for intermediate passes
    private var texturePool: [MTLTexture] = []
    
    // Metal library reference
    private var library: MTLLibrary?
    
    private init() {
        setupDevice()
        loadLibrary()
        createVertexBuffer()
        loadDefaultUniforms()
    }
    
    // MARK: - Setup
    
    private func setupDevice() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
    }
    
    private func loadLibrary() {
        library = device?.makeDefaultLibrary()
        if library == nil {
            print("[ShaderManager] WARNING: Could not create default Metal library")
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
    
    /// Get or create pipeline state for a shader function
    func getPipelineState(for shaderName: String) -> MTLRenderPipelineState? {
        // Check cache first
        if let cached = pipelineCache[shaderName] {
            return cached
        }
        
        // Create new pipeline
        guard let library = library,
              let device = device else {
            print("[ShaderManager] ERROR: Library or device not available")
            return nil
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertexPassthrough"),
              let fragmentFunction = library.makeFunction(name: shaderName) else {
            print("[ShaderManager] ERROR: Could not find shader function '\(shaderName)'")
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelineCache[shaderName] = pipeline
            print("[ShaderManager] Created pipeline for '\(shaderName)'")
            return pipeline
        } catch {
            print("[ShaderManager] ERROR: Failed to create pipeline for '\(shaderName)': \(error)")
            return nil
        }
    }
    
    /// Clear all cached pipeline states (call when shaders change)
    func clearPipelineCache() {
        pipelineCache.removeAll()
    }
    
    // MARK: - Preset Management
    
    /// Switch to a new shader preset
    func activatePreset(_ preset: ShaderPreset) {
        activePreset = preset
        clearPipelineCache()
        
        // Reset uniform values to preset defaults
        uniformValues.removeAll()
        for uniform in preset.globalUniforms {
            uniformValues[uniform.name] = uniform.defaultValue
        }
        
        print("[ShaderManager] Activated preset: \(preset.name)")
    }
    
    /// Update a uniform value
    func updateUniform(_ name: String, value: Float) {
        uniformValues[name] = value
    }
    
    /// Get current value for a uniform
    func getUniform(_ name: String) -> Float {
        uniformValues[name] ?? 0.0
    }
    
    // MARK: - Rendering
    
    /// Create a texture for intermediate pass output
    func createPassTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        
        return device?.makeTexture(descriptor: descriptor)
    }
    
    /// Execute a single shader pass
    func executePass(
        shaderName: String,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        renderPassDescriptor: MTLRenderPassDescriptor,
        viewportWidth: Double,
        viewportHeight: Double,
        sourceSize: SIMD4<Float>,
        outputSize: SIMD4<Float>,
        additionalUniforms: UnsafeRawPointer? = nil,
        additionalUniformsLength: Int = 0
    ) {
        guard let pipeline = getPipelineState(for: shaderName),
              let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Set up render pass to render into outputTexture
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(inputTexture, index: 0)
        
        // Set fragment uniforms
        setStandardFragmentUniforms(
            encoder: encoder,
            sourceSize: sourceSize,
            outputSize: outputSize
        )
        
        // Set additional custom uniforms if provided
        if let additional = additionalUniforms, additionalUniformsLength > 0 {
            encoder.setFragmentBytes(additional, length: additionalUniformsLength, index: 1)
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    /// Set standard Libretro-style uniform buffers
    private func setStandardFragmentUniforms(
        encoder: MTLRenderCommandEncoder,
        sourceSize: SIMD4<Float>,
        outputSize: SIMD4<Float>
    ) {
        struct StandardUniforms {
            var SourceSize: SIMD4<Float>
            var OutputSize: SIMD4<Float>
            var time: Float
            var padding: SIMD3<Float>  // Align to 16 bytes
        }
        
        var uniforms = StandardUniforms(
            SourceSize: sourceSize,
            OutputSize: outputSize,
            time: Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100)),
            padding: SIMD3<Float>(0, 0, 0)
        )
        
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<StandardUniforms>.stride, index: 2)
    }
    
    // MARK: - Preset Groups for UI
    
    /// Get presets grouped by type for organized UI display
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
    
    /// Get recommended presets for a specific system
    func recommendedPresets(for systemID: String) -> [ShaderPreset] {
        ShaderPreset.allPresets.filter { preset in
            preset.recommendedSystems.contains(systemID)
        }
    }
    
    /// Get a human-readable display name for a preset
    static func displayName(for presetID: String) -> String {
        ShaderPreset.preset(id: presetID)?.name ?? "None"
    }
}

// MARK: - Shader Uniform Buffer (matches Metal shader expectations)

/// Standard uniform buffer structure passed to all fragment shaders
struct ShaderStandardUniforms {
    var SourceSize: SIMD4<Float>   // (width, height, 1/width, 1/height)
    var OutputSize: SIMD4<Float>   // (width, height, 1/width, 1/height)
    var time: Float
    var padding: SIMD3<Float>
}
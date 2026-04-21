import Foundation

/// Service responsible for loading shader parameter metadata from .ui JSON files.
class ShaderMetadataLoader {
    static let shared = ShaderMetadataLoader()
    
    private var cache: [String: [String: ShaderUniform]] = [:]
    private var failedLookups: Set<String> = []
    
    private init() {}
    
    /// Loads metadata for a given shader file.
    /// - Parameter shaderFile: The name of the shader file (without extension, e.g., "CRTFilter").
    /// - Returns: A dictionary of ShaderUniforms keyed by their name.
    func loadMetadata(for shaderFile: String) -> [String: ShaderUniform] {
        if let cached = cache[shaderFile] {
            return cached
        }
        
        if failedLookups.contains(shaderFile) {
            return [:]
        }

        var url: URL?
        
        // 1. Try finding in the main bundle
        url = Bundle.main.url(forResource: shaderFile, withExtension: "ui")
        
        // 2. Try finding in a "Shaders" subdirectory in the bundle
        if url == nil {
            url = Bundle.main.url(forResource: shaderFile, withExtension: "ui", subdirectory: "Shaders")
        }
        
        // 3. Fallback: Try finding relative to the current working directory (useful for local dev)
        if url == nil {
            let currentDir = FileManager.default.currentDirectoryPath
            let fallbackPath = "\(currentDir)/TruchieEmu/Shaders/\(shaderFile).ui"
            if FileManager.default.fileExists(atPath: fallbackPath) {
                url = URL(fileURLWithPath: fallbackPath)
            }
        }
        
        guard let finalUrl = url else {
            if !failedLookups.contains(shaderFile) {
                print("ShaderMetadataLoader: Could not find metadata file for \(shaderFile).ui (tried bundle and local fallback)")
                failedLookups.insert(shaderFile)
            }
            return [:]
        }
        
        guard let data = try? Data(contentsOf: finalUrl) else {
            print("ShaderMetadataLoader: Could not read metadata file at \(finalUrl.path)")
            failedLookups.insert(shaderFile)
            return [:]
        }
        
        do {
            let uniforms = try JSONDecoder().decode([ShaderUniform].self, from: data)
            var metadataMap: [String: ShaderUniform] = [:]
            for uniform in uniforms {
                metadataMap[uniform.name] = uniform
            }
            cache[shaderFile] = metadataMap
            //LoggerService.info(category: "ShaderMetadataLoader", "Decoded metadata for \(shaderFile): \(metadataMap)")
            return metadataMap
        } catch {
            LoggerService.error(category: "ShaderMetadataLoader", "Failed to decode metadata for \(shaderFile): \(error)")
            failedLookups.insert(shaderFile)
            return [:]
        }
    }
}
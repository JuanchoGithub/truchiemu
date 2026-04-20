import Foundation

/// Service responsible for loading shader parameter metadata from .ui JSON files.
class ShaderMetadataLoader {
    static let shared = ShaderMetadataLoader()
    
    private init() {}
    
    /// Loads metadata for a given shader file.
    /// - Parameter shaderFile: The name of the shader file (without extension, e.g., "CRTFilter").
    /// - Returns: A dictionary of ShaderUniforms keyed by their name.
    func loadMetadata(for shaderFile: String) -> [String: ShaderUniform] {
        // Construct the path to the .ui file in the Shaders directory.
        // In a real app, this would use Bundle.main.url(forResource:...)
        // For this environment, we'll use the relative path.
        let url = URL(fileURLWithPath: "TruchieEmu/Shaders/\(shaderFile).ui")
        
        guard let data = try? Data(contentsOf: url) else {
            print("ShaderMetadataLoader: Could not find or read metadata file at \(url.path)")
            return [:]
        }
        
        do {
            let uniforms = try JSONDecoder().decode([ShaderUniform].self, from: data)
            var metadataMap: [String: ShaderUniform] = [:]
            for uniform in uniforms {
                metadataMap[uniform.name] = uniform
            }
            return metadataMap
        } catch {
            print("ShaderMetadataLoader: Failed to decode metadata for \(shaderFile): \(error)")
            return [:]
        }
    }
}
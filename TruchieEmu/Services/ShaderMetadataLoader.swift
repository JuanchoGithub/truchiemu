import Foundation

/// Service responsible for loading shader parameter metadata from .ui JSON files.
class ShaderMetadataLoader {
    static let shared = ShaderMetadataLoader()
    
    private init() {}
    
    /// Loads metadata for a given shader file.
    /// - Parameter shaderFile: The name of the shader file (without extension, e.g., "CRTFilter").
    /// - Returns: A dictionary of ShaderUniforms keyed by their name.
    func loadMetadata(for shaderFile: String) -> [String: ShaderUniform] {
        // Construct the path to the .ui file in the Shaders directory using the app bundle.
        guard let url = Bundle.main.url(forResource: shaderFile, withExtension: "ui") else {
            print("ShaderMetadataLoader: Could not find metadata file for \(shaderFile).ui in bundle")
            return [:]
        }
        
        guard let data = try? Data(contentsOf: url) else {
            print("ShaderMetadataLoader: Could not read metadata file at \(url.path)")
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
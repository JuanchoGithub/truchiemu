import Foundation

// MARK: - SLANGP Parser

/// Parses Libretro .slangp preset files into ShaderPreset objects.
/// Reference: https://github.com/libretro/slang-shaders
class SLANGPParser {
    
    // MARK: - SLANGP Preset Structure
    
    struct SLANGPPreset {
        var shaders: [SLANGPShader] = []
        var parameters: [String: Float] = [:]
        var metadata: SlangpMetadata = SlangpMetadata()
    }
    
    struct SLANGPShader {
        var name: String = ""
        var filter: ShaderFilter = .linear
        var wrapMode: String = "clamp_to_border"
        var scaleTypeX: ShaderScaleType = .source
        var scaleTypeY: ShaderScaleType = .source
        var scaleX: Float = 1.0
        var scaleY: Float = 1.0
    }
    
    struct SlangpMetadata {
        var displayName: String = ""
        var author: String = ""
    }
    
    // MARK: - Parse .slangp File
    
    /// Parse a .slangp file and return a ShaderPreset
    static func parse(url: URL) -> ShaderPreset? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[SLANGPParser] ERROR: Could not read file at \(url.path)")
            return nil
        }
        
        let parsed = parseContent(content)
        return convertToShaderPreset(parsed, sourceURL: url)
    }
    
    /// Parse raw .slangp content string
    static func parseContent(_ content: String) -> SLANGPPreset {
        var preset = SLANGPPreset()
        let lines = content.components(separatedBy: .newlines)
        
        // Count shader passes
        var shaderCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("shaders = ") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count == 2, let count = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    shaderCount = count
                }
                break
            }
        }
        
        // Initialize shader slots
        for _ in 0..<shaderCount {
            preset.shaders.append(SLANGPShader())
        }
        
        // Parse each line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            
            // Parse key = value
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            
            // Remove inline comments
            if let commentRange = value.range(of: " #") ?? value.range(of: " ;") {
                value = String(value[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            
            parseKeyValue(key: key, value: value, preset: &preset)
        }
        
        return preset
    }
    
    // MARK: - Key-Value Parsing
    
    private static func parseKeyValue(key: String, value: String, preset: inout SLANGPPreset) {
        // Metadata
        if key == "name" || key == "alias" {
            preset.metadata.displayName = value.replacingOccurrences(of: "\"", with: "")
        } else if key == "author" {
            preset.metadata.author = value.replacingOccurrences(of: "\"", with: "")
        }
        // Parameters (float uniforms)
        else if key.hasPrefix("parameters") {
            if let floatValue = Float(value) {
                let paramName = key.replacingOccurrences(of: "parameters", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                preset.parameters[paramName] = floatValue
            }
        }
        // Shader-specific settings
        else if key.hasPrefix("shader") {
            parseShaderKey(key: key, value: value, preset: &preset)
        }
        // Global settings
        else if key.hasPrefix("filter") || key.hasPrefix("wrap_mode") ||
                  key.hasPrefix("scale_type") || key.hasPrefix("scale") {
            parseGlobalKey(key: key, value: value, preset: &preset)
        }
    }
    
    private static func parseShaderKey(key: String, value: String, preset: inout SLANGPPreset) {
        // Extract index: "shader0" -> 0
        let numberComponents = key.components(separatedBy: CharacterSet.decimalDigits.inverted)
        guard let index = numberComponents.first(where: { !$0.isEmpty }).flatMap(Int.init) else { return }
        guard index >= 0, index < preset.shaders.count else { return }
        
        let baseKey = key.replacingOccurrences(of: String(index), with: "")
        let shader = preset.shaders[index]
        
        switch baseKey {
        case "shader":
            preset.shaders[index].name = value
        case "filter":
            preset.shaders[index].filter = value == "nearest" ? .nearest : .linear
        case "wrap_mode":
            preset.shaders[index].wrapMode = value
        case "scale_type_x":
            preset.shaders[index].scaleTypeX = ShaderScaleType(slangleName: value) ?? .source
        case "scale_type_y":
            preset.shaders[index].scaleTypeY = ShaderScaleType(slangleName: value) ?? .source
        case "scale_x":
            preset.shaders[index].scaleX = Float(value) ?? 1.0
        case "scale_y":
            preset.shaders[index].scaleY = Float(value) ?? 1.0
        default:
            break
        }
    }
    
    private static func parseGlobalKey(key: String, value: String, preset: inout SLANGPPreset) {
        // These are typically set per-shader in multi-pass, but can have defaults
        // For simplicity, we apply them to all shaders that don't have specific values
        switch key {
        case "filter":
            let filter: ShaderFilter = value == "nearest" ? .nearest : .linear
            for i in 0..<preset.shaders.count {
                if preset.shaders[i].filter == .linear && filter != .linear {
                    preset.shaders[i].filter = filter
                }
            }
        case "scale_type_x":
            let scaleType = ShaderScaleType(slangleName: value) ?? .source
            for i in 0..<preset.shaders.count {
                if preset.shaders[i].scaleTypeX == .source {
                    preset.shaders[i].scaleTypeX = scaleType
                }
            }
        case "scale_type_y":
            let scaleType = ShaderScaleType(slangleName: value) ?? .source
            for i in 0..<preset.shaders.count {
                if preset.shaders[i].scaleTypeY == .source {
                    preset.shaders[i].scaleTypeY = scaleType
                }
            }
        default:
            break
        }
    }
    
    // MARK: - Conversion to ShaderPreset
    
    private static func convertToShaderPreset(_ parsed: SLANGPPreset, sourceURL: URL) -> ShaderPreset? {
        // Determine shader type from name/path
        let lowerPath = sourceURL.path.lowercased()
        let lowerName = parsed.metadata.displayName.lowercased()
        
        let shaderType: ShaderType
        if lowerPath.contains("crt") || lowerName.contains("crt") {
            shaderType = .crt
        } else if lowerPath.contains("lcd") || lowerPath.contains("handheld") || lowerName.contains("lcd") {
            shaderType = .lcd
        } else if lowerPath.contains("xbr") || lowerPath.contains("smooth") || lowerName.contains("smooth") {
            shaderType = .smoothing
        } else if lowerPath.contains("composite") || lowerPath.contains("vhs") || lowerName.contains("composite") {
            shaderType = .composite
        } else {
            shaderType = .custom
        }
        
        // Convert passes
        var passes: [ShaderPass] = []
        for slangShader in parsed.shaders {
            let uniformParams = parsed.parameters.map { key, value in
                ShaderUniform(
                    name: key,
                    defaultValue: value,
                    minValue: value * 0.5,
                    maxValue: value * 2.0
                )
            }
            
            let pass = ShaderPass(
                shaderFile: slangShader.name,
                filter: slangShader.filter,
                wrapMode: slangShader.wrapMode,
                scaleX: slangShader.scaleX,
                scaleY: slangShader.scaleY,
                scaleTypeX: slangShader.scaleTypeX,
                scaleTypeY: slangShader.scaleTypeY,
                uniforms: uniformParams
            )
            passes.append(pass)
        }
        
        // Convert parameters to global uniforms
        let globalUniforms = parsed.parameters.map { key, value in
            ShaderUniform(
                name: key,
                defaultValue: value,
                minValue: max(0, value * 0.5),
                maxValue: value * 2.0
            )
        }
        
        // Generate ID from filename
        let presetID = "libretro-" + sourceURL.deletingPathExtension().lastPathComponent
        
        return ShaderPreset(
            id: presetID,
            name: parsed.metadata.displayName.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : parsed.metadata.displayName,
            shaderType: shaderType,
            isBuiltin: false,
            path: sourceURL,
            passes: passes,
            globalUniforms: globalUniforms,
            description: "Libretro shader preset from \(sourceURL.lastPathComponent)",
            recommendedSystems: []
        )
    }
    
    // MARK: - Scan Directory for Presets
    
    /// Recursively scan a directory for .slangp files
    static func scanPresetDirectory(at url: URL) -> [ShaderPreset] {
        var presets: [ShaderPreset] = []
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return presets
        }
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "slangp" {
                    if let preset = parse(url: fileURL) {
                        presets.append(preset)
                    }
                }
            }
        }
        
        return presets
    }
}

// MARK: - Helper Extensions

extension ShaderScaleType {
    init?(slangleName: String) {
        switch slangleName.lowercased() {
        case "source": self = .source
        case "viewport": self = .viewport
        case "absolute": self = .absolute
        default: return nil
        }
    }
}
import Foundation

// MARK: - Libretro Shader Loader

/// Scans the bundled libretro slang shader directory and catalogs available presets.
/// This service provides a catalog of available shaders for the UI to display.
/// Note: Actual shader execution requires a GLSL-to-Metal translation layer or MoltenVK.
class LibretroShaderLoader {
    
    // MARK: - Shader Category Mapping
    
    /// Maps libretro shader directory names to our ShaderType enum
    private static let categoryMapping: [String: ShaderType] = [
        "crt": .crt,
        "lcd": .lcd,
        "handheld": .lcd,
        "xbrz": .smoothing,
        "xbr": .smoothing,
        "scalefx": .smoothing,
        "nnedi3": .smoothing,
        "anti-aliasing": .smoothing,
        "edge-smoothing": .smoothing,
        "pixel-art-scaling": .smoothing,
        "composite": .composite,
        "ntsc": .composite,
        "pal": .composite,
        "vhs": .composite,
        "scanlines": .crt,
        "blurs": .custom,
        "sharpen": .custom,
        "film": .custom,
        "misc": .custom,
        "reshade": .custom,
        "hdr": .custom,
        "warp": .custom,
        "bezel": .custom,
        "border": .custom,
    ]
    
    // MARK: - System Recommendation Mapping
    
    /// Maps common shader name patterns to recommended systems
    private static let systemRecommendations: [(pattern: String, systems: [String])] = [
        (pattern: "nes", systems: ["nes"]),
        (pattern: "snes", systems: ["snes"]),
        (pattern: "genesis", systems: ["genesis"]),
        (pattern: "mega drive", systems: ["genesis"]),
        (pattern: "game boy", systems: ["gb", "gbc", "gba"]),
        (pattern: "gba", systems: ["gba"]),
        (pattern: "n64", systems: ["n64"]),
        (pattern: "playstation", systems: ["psx"]),
        (pattern: "psx", systems: ["psx"]),
        (pattern: "psp", systems: ["psp"]),
        (pattern: "sms", systems: ["sms"]),
        (pattern: "gamegear", systems: ["gg"]),
        (pattern: "atari", systems: ["atari2600", "atari5200"]),
        (pattern: "dreamcast", systems: ["dreamcast"]),
        (pattern: "saturn", systems: ["saturn"]),
    ]
    
    // MARK: - Load Presets
    
    /// Load all libretro shader presets from the bundled resources
    static func loadAllPresets() -> [ShaderPreset] {
        guard let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("slang") else {
            print("[LibretroShaderLoader] WARNING: Could not find slang shader bundle path")
            return []
        }
        
        return scanDirectory(at: bundleURL)
    }
    
    /// Scan a directory for .slangp preset files
    private static func scanDirectory(at url: URL) -> [ShaderPreset] {
        var presets: [ShaderPreset] = []
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("[LibretroShaderLoader] Directory not found: \(url.path)")
            return presets
        }
        
        // Get the base path for calculating relative paths
        let basePath = url.path
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "slangp" {
                    if let preset = parsePresetFile(at: fileURL, basePath: basePath) {
                        presets.append(preset)
                    }
                }
            }
        }
        
        print("[LibretroShaderLoader] Loaded \(presets.count) libretro shader presets")
        return presets
    }
    
    /// Parse a single .slangp file into a ShaderPreset
    private static func parsePresetFile(at url: URL, basePath: String) -> ShaderPreset? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        
        // Extract metadata
        var name = url.deletingPathExtension().lastPathComponent
        var author = ""
        var shaderCount = 0
        var parameters: [String: Float] = [:]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                // Check for name in comments
                if trimmed.hasPrefix("#name") || trimmed.hasPrefix("#alias") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count == 2 {
                        name = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                    }
                }
                if trimmed.hasPrefix("#author") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count == 2 {
                        author = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                    }
                }
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
            
            switch key {
            case "shaders":
                shaderCount = Int(value) ?? 0
            case "name", "alias":
                name = value.replacingOccurrences(of: "\"", with: "")
            case "author":
                author = value.replacingOccurrences(of: "\"", with: "")
            default:
                // Parse parameters
                if key.hasPrefix("parameters") || (shaderCount > 0 && !key.hasPrefix("shader")) {
                    if let floatValue = Float(value) {
                        let paramName = key.replacingOccurrences(of: "parameters", with: "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                        parameters[paramName] = floatValue
                    }
                }
            }
        }
        
        // Determine shader type from path and name
        let relativePath = url.path.replacingOccurrences(of: basePath + "/", with: "").lowercased()
        let shaderType = determineShaderType(from: relativePath, name: name)
        
        // Determine system recommendations
        let recommendedSystems = determineSystemRecommendations(for: name.lowercased())
        
        // Create global uniforms from parameters
        let globalUniforms = parameters.map { key, value in
            ShaderUniform(
                name: key,
                defaultValue: value,
                minValue: max(0, value * 0.5),
                maxValue: value * 2.0,
                step: 0.01
            )
        }.sorted { $0.name < $1.name }
        
        // Generate a unique ID
        let presetID = "libretro-" + relativePath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".slangp", with: "")
            .lowercased()
        
        // Build description
        var description = "Libretro shader: \(name)"
        if !author.isEmpty {
            description += " by \(author)"
        }
        description += "\nPath: \(relativePath)"
        
        return ShaderPreset(
            id: presetID,
            name: name,
            shaderType: shaderType,
            isBuiltin: false,
            path: url,
            passes: [],
            globalUniforms: globalUniforms,
            description: description,
            recommendedSystems: recommendedSystems
        )
    }
    
    /// Determine shader type from path and name
    private static func determineShaderType(from path: String, name: String) -> ShaderType {
        let lowerPath = path.lowercased()
        let lowerName = name.lowercased()
        let combined = lowerPath + " " + lowerName
        
        // Check category mapping
        for (key, type) in categoryMapping {
            if combined.contains(key) {
                return type
            }
        }
        
        // Check name patterns
        if combined.contains("crt") || combined.contains("geom") || combined.contains("curvature") {
            return .crt
        }
        if combined.contains("lcd") || combined.contains("grid") || combined.contains("pixel") {
            return .lcd
        }
        if combined.contains("smooth") || combined.contains("xbr") || combined.contains("sharpen") {
            return .smoothing
        }
        if combined.contains("composite") || combined.contains("vhs") || combined.contains("blur") {
            return .composite
        }
        
        return .custom
    }
    
    /// Determine system recommendations from shader name
    private static func determineSystemRecommendations(for name: String) -> [String] {
        var systems: Set<String> = []
        
        for (pattern, recommendedSystems) in systemRecommendations {
            if name.contains(pattern) {
                systems.formUnion(recommendedSystems)
            }
        }
        
        return Array(systems)
    }
    
    // MARK: - Preset Count by Category
    
    /// Get count of libretro presets by category
    static func presetCounts() -> [ShaderType: Int] {
        let presets = loadAllPresets()
        var counts: [ShaderType: Int] = [:]
        
        for preset in presets {
            counts[preset.shaderType, default: 0] += 1
        }
        
        return counts
    }
}
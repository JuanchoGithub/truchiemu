import Foundation

// MARK: - Shader Type Classification

enum ShaderType: String, Codable, CaseIterable {
    case crt            // CRT monitor simulation
    case lcd            // LCD grid for handhelds
    case smoothing      // Edge-directed upscaling (xBRZ, etc.)
    case composite      // Composite/VHS blur
    case custom         // User-defined or other
    
    var displayName: String {
        switch self {
        case .crt:      return "CRT"
        case .lcd:      return "LCD / Handheld"
        case .smoothing: return "Smoothing"
        case .composite: return "Composite / VHS"
        case .custom:   return "Custom"
        }
    }
}

// MARK: - Scale Type for Multi-Pass Shaders

enum ShaderScaleType: String, Codable {
    case source      // Scale relative to source texture
    case viewport    // Scale relative to viewport/output
    case absolute    // Fixed pixel dimensions
    
    var slangleName: String {
        switch self {
        case .source:   return "source"
        case .viewport: return "viewport"
        case .absolute: return "absolute"
        }
    }
}

// MARK: - Filter Type for Pass Interpolation

enum ShaderFilter: String, Codable {
    case nearest       // Nearest neighbor (pixelated)
    case linear        // Bilinear interpolation (smooth)
    case mipmap        // Mipmapped sampling
    
    var slangleName: String {
        switch self {
        case .nearest: return "nearest"
        case .linear:  return "linear"
        case .mipmap:  return "mipmap"
        }
    }
}

// MARK: - Shader Uniform Definition

struct ShaderUniform: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var defaultValue: Float
    var minValue: Float
    var maxValue: Float
    var step: Float = 0.01
    var displayName: String?
    
    var displayLabel: String {
        displayName ?? name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Single Shader Pass Definition

struct ShaderPass: Codable, Hashable {
    var shaderFile: String        // Path to .metal or .slang file
    var filter: ShaderFilter
    var wrapMode: String          // "clampToEdge", "repeat", etc.
    
    // Scale configuration
    var scaleX: Float
    var scaleY: Float
    var scaleTypeX: ShaderScaleType
    var scaleTypeY: ShaderScaleType
    
    // Pass-specific uniforms
    var uniforms: [ShaderUniform]
    
    init(shaderFile: String,
         filter: ShaderFilter = .linear,
         wrapMode: String = "clampToEdge",
         scaleX: Float = 1.0,
         scaleY: Float = 1.0,
         scaleTypeX: ShaderScaleType = .source,
         scaleTypeY: ShaderScaleType = .source,
         uniforms: [ShaderUniform] = []) {
        self.shaderFile = shaderFile
        self.filter = filter
        self.wrapMode = wrapMode
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.scaleTypeX = scaleTypeX
        self.scaleTypeY = scaleTypeY
        self.uniforms = uniforms
    }
}

// MARK: - Shader Preset (Complete Shader Configuration)

struct ShaderPreset: Codable, Hashable, Identifiable {
    var id: String                              // Unique identifier
    var name: String                            // Display name
    var shaderType: ShaderType                  // Category
    var isBuiltin: Bool                         // true = bundled .metal, false = external .slangp
    var path: URL?                              // Path to preset file (for .slangp)
    var passes: [ShaderPass]                    // Rendering passes
    var globalUniforms: [ShaderUniform]         // User-tweakable parameters
    var description: String?                    // Optional description
    var recommendedSystems: [String]            // e.g., ["nes", "snes", "genesis"]
    var thumbnailSystemName: String?            // Preview image hint
    
    init(id: String,
         name: String,
         shaderType: ShaderType,
         isBuiltin: Bool = true,
         path: URL? = nil,
         passes: [ShaderPass] = [],
         globalUniforms: [ShaderUniform] = [],
         description: String? = nil,
         recommendedSystems: [String] = [],
         thumbnailSystemName: String? = nil) {
        self.id = id
        self.name = name
        self.shaderType = shaderType
        self.isBuiltin = isBuiltin
        self.path = path
        self.passes = passes
        self.globalUniforms = globalUniforms
        self.description = description
        self.recommendedSystems = recommendedSystems
        self.thumbnailSystemName = thumbnailSystemName
    }
}

// MARK: - Built-in Shader Preset Factory

extension ShaderPreset {
    // All built-in shader presets
    static let builtinPresets: [ShaderPreset] = [
        // CRT Lottes (High Quality)
        ShaderPreset(
            id: "builtin-crt-lottes",
            name: "CRT Lottes",
            shaderType: .crt,
            passes: [
                ShaderPass(
                    shaderFile: "LottesCRT",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "scanlineStrength", defaultValue: 0.5, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "maskStrength", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "bloomAmount", defaultValue: 0.15, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "curvatureAmount", defaultValue: 0.02, minValue: 0.0, maxValue: 0.1),
                ShaderUniform(name: "colorBoost", defaultValue: 1.1, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Advanced CRT simulation by Timothy Lottes. Featuring high-quality scanlines and mask.",
            recommendedSystems: ["nes", "snes", "genesis", "psx", "arcade"]
        ),
        
        // CRT Classic
        ShaderPreset(
            id: "builtin-crt-classic",
            name: "CRT Classic",
            shaderType: .crt,
            passes: [
                ShaderPass(
                    shaderFile: "CRTFilter",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
             globalUniforms: [
                 ShaderUniform(name: "scanlineIntensity", defaultValue: 0.35, minValue: 0.0, maxValue: 1.0),
                 ShaderUniform(name: "barrelAmount", defaultValue: 0.12, minValue: 0.0, maxValue: 0.5),
                 ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
             ],
            description: "Classic CRT scanlines with barrel distortion and vignette.",
            recommendedSystems: ["nes", "snes", "genesis", "psx"]
        ),

        // Sharp Bilinear (Clean & Sharp)
        ShaderPreset(
            id: "builtin-sharp-bilinear",
            name: "Sharp Bilinear",
            shaderType: .smoothing,
            passes: [
                ShaderPass(
                    shaderFile: "SharpBilinear",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "sharpness", defaultValue: 0.8, minValue: 0.1, maxValue: 1.0),
                ShaderUniform(name: "scanlineOpacity", defaultValue: 0.0, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Crisp scaling that avoids shimmering. Ideal for modern displays.",
            recommendedSystems: ["nes", "snes", "genesis", "gb", "gba"]
        ),
        
        // LCD Grid (Classic Handheld)
        ShaderPreset(
            id: "builtin-lcd-grid",
            name: "LCD Grid",
            shaderType: .lcd,
            passes: [
                ShaderPass(
                    shaderFile: "LCDGrid",
                    filter: .nearest,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "gridStrength", defaultValue: 0.4, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "pixelSeparation", defaultValue: 0.05, minValue: 0.0, maxValue: 0.2),
                ShaderUniform(name: "brightnessBoost", defaultValue: 1.2, minValue: 0.5, maxValue: 2.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Standard sub-pixel LCD grid for handheld consoles.",
            recommendedSystems: ["gb", "gbc", "gg", "gba"]
        ),

        // Dot Matrix LCD (Game Boy metallic dot-matrix)
        ShaderPreset(
            id: "builtin-dot-matrix",
            name: "Dot Matrix LCD",
            shaderType: .lcd,
            passes: [
                ShaderPass(
                    shaderFile: "DotMatrixLCD",
                    filter: .nearest,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "dotOpacity", defaultValue: 0.85, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "metallicIntensity", defaultValue: 0.5, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "specularShininess", defaultValue: 8.0, minValue: 1.0, maxValue: 32.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.1, minValue: 0.5, maxValue: 2.0),
            ],
            description: "High-quality metallic dot-matrix LCD for Game Boy systems.",
            recommendedSystems: ["gb", "gbc", "gg", "sms"]
        ),
        
        // Lite CRT (Fast & Clean)
        ShaderPreset(
            id: "builtin-lite-crt",
            name: "Lite CRT",
            shaderType: .crt,
            passes: [
                ShaderPass(
                    shaderFile: "LiteCRT",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "scanlineIntensity", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "phosphorStrength", defaultValue: 0.2, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "brightness", defaultValue: 1.1, minValue: 0.5, maxValue: 2.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Lightweight CRT effect with simple scanlines and phosphors.",
            recommendedSystems: ["nes", "snes", "genesis"]
        ),
        
        // Smooth Upscale (ScaleFX style)
        ShaderPreset(
            id: "builtin-smooth-upscale",
            name: "Smooth Upscale",
            shaderType: .smoothing,
            passes: [
                ShaderPass(
                    shaderFile: "ScaleSmooth",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "smoothness", defaultValue: 1.0, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "High-quality pixel art upscaler that smooths edges while maintaining detail.",
            recommendedSystems: ["nes", "snes", "gba", "arcade"]
        ),

        // No Filter (raw pixels)
        ShaderPreset(
            id: "builtin-none",
            name: "No Shader",
            shaderType: .custom,
            passes: [
                ShaderPass(
                    shaderFile: "Passthrough",
                    filter: .nearest,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [],
            description: "No post-processing. Integer-scaled raw pixels.",
            recommendedSystems: ["nes", "gb", "snes", "genesis", "scummvm"]
        ),
    ]
    
    // All available presets (built-in only)
    static var allPresets: [ShaderPreset] {
        builtinPresets
    }
    
    // Get preset by ID
    static func preset(id: String) -> ShaderPreset? {
        builtinPresets.first(where: { $0.id == id })
    }
    
    // Default preset (no filtering)
    static let defaultPreset = preset(id: "builtin-none")!
}

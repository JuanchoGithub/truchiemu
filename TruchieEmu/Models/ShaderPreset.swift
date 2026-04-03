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
    /// All built-in shader presets
    static let builtinPresets: [ShaderPreset] = [
        // CRT Test Shader
        ShaderPreset(
            id: "builtin-crt-test",
            name: "CRT Test",
            shaderType: .crt,
            passes: [
                ShaderPass(
                    shaderFile: "CRTTest",
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
            description: "Test CRT shader with barrel distortion, phosphor mask, scanlines, and vignette.",
            recommendedSystems: ["nes", "snes", "genesis", "psx"]
        ),
        
        // CRT Shader (existing, enhanced)
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
            description: "Classic CRT scanlines with barrel distortion, phosphor mask, and vignette.",
            recommendedSystems: ["nes", "snes", "genesis", "psx"]
        ),
        
        // LCD Grid for Handhelds
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
                ShaderUniform(name: "gridOpacity", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "ghostingAmount", defaultValue: 0.0, minValue: 0.0, maxValue: 0.5),
                ShaderUniform(name: "gridSize", defaultValue: 3.0, minValue: 1.0, maxValue: 6.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Simulates handheld LCD pixel grid with optional motion ghosting.",
            recommendedSystems: ["gb", "gbc", "gba", "gg", "sms"]
        ),
        
        // Vibrant LCD for GBA/PSP
        ShaderPreset(
            id: "builtin-vibrant-lcd",
            name: "Vibrant LCD",
            shaderType: .lcd,
            passes: [
                ShaderPass(
                    shaderFile: "VibrantLCD",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "saturation", defaultValue: 1.3, minValue: 0.5, maxValue: 3.0),
                ShaderUniform(name: "gamma", defaultValue: 2.2, minValue: 1.0, maxValue: 3.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.2, minValue: 0.5, maxValue: 2.5),
            ],
            description: "Gamma correction and saturation boost for washed-out handheld games.",
            recommendedSystems: ["gba", "psp", "nds"]
        ),
        
        // Edge Smoothing for Pixel Art
        ShaderPreset(
            id: "builtin-edge-smooth",
            name: "Edge Smooth (xBRZ-like)",
            shaderType: .smoothing,
            passes: [
                ShaderPass(
                    shaderFile: "EdgeSmooth",
                    filter: .linear,
                    scaleX: 2.0, scaleY: 2.0,
                    scaleTypeX: .source, scaleTypeY: .source
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "smoothStrength", defaultValue: 0.7, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Edge-directed interpolation that smooths pixel art while preserving sharp diagonals.",
            recommendedSystems: ["snes", "nes", "genesis", "gba", "psx"]
        ),
        
        // Composite/VHS Blur
        ShaderPreset(
            id: "builtin-composite",
            name: "Composite / VHS",
            shaderType: .composite,
            passes: [
                ShaderPass(
                    shaderFile: "Composite",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "horizontalBlur", defaultValue: 1.5, minValue: 0.5, maxValue: 5.0),
                ShaderUniform(name: "verticalBlur", defaultValue: 0.3, minValue: 0.0, maxValue: 2.0),
                ShaderUniform(name: "bleedAmount", defaultValue: 0.4, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Simulates composite video output with horizontal color bleeding. Fixes dithering artifacts.",
            recommendedSystems: ["nes", "genesis", "snes", "sms"]
        ),
        
        // CRT + Scanlines Only (no barrel distortion)
        ShaderPreset(
            id: "builtin-scanlines-only",
            name: "Scanlines Only",
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
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Subtle scanline overlay without curvature or phosphor effects.",
            recommendedSystems: ["nes", "snes", "gba", "psx"]
        ),
        
        // No Filter (raw pixels)
        ShaderPreset(
            id: "builtin-none",
            name: "None (Raw Pixels)",
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
            description: "No post-processing. Integer-scaled raw pixels with nearest-neighbor filtering.",
            recommendedSystems: ["nes", "gb", "snes", "genesis", "scummvm"]
        ),
        
        // Sharp Bilinear
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
                ShaderUniform(name: "sharpness", defaultValue: 0.5, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
                ShaderUniform(name: "scanlineOpacity", defaultValue: 0.0, minValue: 0.0, maxValue: 1.0),
            ],
            description: "Clean bilinear filtering that preserves sharp pixels. Great for pixel art upscaling.",
            recommendedSystems: ["nes", "gb", "gbc", "gba", "snes", "genesis"]
        ),
        
        // Gamma Correct / LCD Enhancement
        ShaderPreset(
            id: "builtin-gamma-correct",
            name: "Gamma Correct",
            shaderType: .lcd,
            passes: [
                ShaderPass(
                    shaderFile: "GammaCorrect",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "gamma", defaultValue: 2.2, minValue: 1.0, maxValue: 3.0),
                ShaderUniform(name: "saturation", defaultValue: 1.2, minValue: 0.5, maxValue: 3.0),
                ShaderUniform(name: "contrast", defaultValue: 1.1, minValue: 0.5, maxValue: 2.0),
                ShaderUniform(name: "brightness", defaultValue: 0.0, minValue: -0.3, maxValue: 0.3),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Gamma correction and color enhancement for washed-out LCD games.",
            recommendedSystems: ["gba", "psp", "nds", "3ds"]
        ),
        
        // Lottes CRT
        ShaderPreset(
            id: "builtin-lottes-crt",
            name: "Lottes CRT",
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
                ShaderUniform(name: "beamMinWidth", defaultValue: 0.5, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "beamMaxWidth", defaultValue: 1.5, minValue: 0.5, maxValue: 3.0),
                ShaderUniform(name: "maskDark", defaultValue: 0.5, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "maskLight", defaultValue: 1.5, minValue: 0.5, maxValue: 2.0),
                ShaderUniform(name: "sharpness", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Clean CRT with scanlines and shadow mask. Good performance.",
            recommendedSystems: ["nes", "snes", "genesis", "psx", "n64"]
        ),
        
        // Flat CRT (no curvature)
        ShaderPreset(
            id: "builtin-flat-crt",
            name: "Flat CRT",
            shaderType: .crt,
            passes: [
                ShaderPass(
                    shaderFile: "FlatCRT",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "scanlineStrength", defaultValue: 0.4, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "maskStrength", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "beamWidth", defaultValue: 1.0, minValue: 0.0, maxValue: 2.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "CRT scanlines and mask without barrel distortion. Clean look.",
            recommendedSystems: ["nes", "snes", "genesis", "psx", "gb", "gba"]
        ),
        
        // Handheld LCD
        ShaderPreset(
            id: "builtin-handheld-lcd",
            name: "Handheld LCD",
            shaderType: .lcd,
            passes: [
                ShaderPass(
                    shaderFile: "HandheldLCD",
                    filter: .nearest,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "gridOpacity", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "gridSize", defaultValue: 3.0, minValue: 1.0, maxValue: 8.0),
                ShaderUniform(name: "ghosting", defaultValue: 0.0, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "gamma", defaultValue: 2.2, minValue: 1.0, maxValue: 3.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "LCD pixel grid with gamma correction and optional motion ghosting.",
            recommendedSystems: ["gb", "gbc", "gg", "sms"]
        ),
        
        // XBRZ Upscaling
        ShaderPreset(
            id: "builtin-xbrz",
            name: "XBRZ Upscaling",
            shaderType: .smoothing,
            passes: [
                ShaderPass(
                    shaderFile: "XBRZ",
                    filter: .linear,
                    scaleX: 2.0, scaleY: 2.0,
                    scaleTypeX: .source, scaleTypeY: .source
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "blendStrength", defaultValue: 0.7, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorTolerance", defaultValue: 0.1, minValue: 0.0, maxValue: 0.5),
                ShaderUniform(name: "sharpness", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Edge-directed upscale with smooth curves. Great for pixel art.",
            recommendedSystems: ["snes", "genesis", "gba", "psx"]
        ),
        
        // Pixellate (AA Nearest-Neighbor)
        ShaderPreset(
            id: "builtin-pixellate",
            name: "Pixellate",
            shaderType: .smoothing,
            passes: [
                ShaderPass(
                    shaderFile: "Pixellate",
                    filter: .linear,
                    scaleX: 1.0, scaleY: 1.0,
                    scaleTypeX: .viewport, scaleTypeY: .viewport
                )
            ],
            globalUniforms: [
                ShaderUniform(name: "antialiasing", defaultValue: 0.3, minValue: 0.0, maxValue: 1.0),
                ShaderUniform(name: "colorBoost", defaultValue: 1.0, minValue: 0.5, maxValue: 2.0),
            ],
            description: "Nearest-neighbor pixels with anti-aliased edges.",
            recommendedSystems: ["nes", "gb", "snes", "genesis", "scummvm"]
        ),
    ]
    
    /// All available presets (built-in only)
    static var allPresets: [ShaderPreset] {
        builtinPresets
    }
    
    /// Get preset by ID
    static func preset(id: String) -> ShaderPreset? {
        builtinPresets.first(where: { $0.id == id })
    }
    
    /// Default preset (no filtering)
    static let defaultPreset = preset(id: "builtin-none")!
}

import Foundation
import simd

// MARK: - Shader Uniforms
// Each Metal shader expects a specific uniform buffer layout.
// We create per-shader layouts that match exactly what Metal expects.

// CRT Filter uniforms - matches CRTUniforms in CRTFilter.metal
struct CRTUniforms {
    var scanlineIntensity: Float
    var barrelAmount: Float
    var colorBoost: Float
    var time: Float
    var bleedAmount: Float
    var texSizeX: Float
    var texSizeY: Float
    var vignetteStrength: Float
    var flickerStrength: Float
    var bloomStrength: Float
    var chromaAmount: Float
    var softnessAmount: Float
    var bezelRounding: Float
    var bezelGlow: Float
    var tintR: Float
    var tintG: Float
    var tintB: Float
    var useDistort: Float
    var useScan: Float
    var useBleed: Float
    var useSoft: Float
    var useChroma: Float
    var useWhite: Float
    var useVig: Float
    var useFlick: Float
    var useBezel: Float
    var useBloom: Float
    var padding: Float
}

// CRT Multipass uniforms - matches CRTMultipassUniforms in CRTFilter_multipass.metal
struct CRTMultipassUniforms {
    var scanlineIntensity: Float
    var barrelAmount: Float
    var colorBoost: Float
    var time: Float
    var ghostingWeight: Float
    var bleedAmount: Float
    var texSizeX: Float
    var texSizeY: Float
    var vignetteStrength: Float
    var flickerStrength: Float
    var bloomStrength: Float
    var chromaAmount: Float
    var softnessAmount: Float
    var bezelRounding: Float
    var bezelGlow: Float
    var tintR: Float
    var tintG: Float
    var tintB: Float
    var useDistort: Float
    var useScan: Float
    var useBleed: Float
    var useSoft: Float
    var useChroma: Float
    var useWhite: Float
    var useVig: Float
    var useFlick: Float
    var useBezel: Float
    var useBloom: Float
    var padding: Float
}

// Dot Matrix LCD uniforms (48 bytes) - matches DotMatrixLCDUniforms in DotMatrixLCD.metal
struct DotMatrixLCDUniforms {
    var dotOpacity: Float
    var metallicIntensity: Float
    var specularShininess: Float
    var colorBoost: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

// Lottes CRT uniforms - matches LottesUniforms in LottesCRT.metal
struct LottesUniforms {
    var scanlineStrength: Float
    var maskStrength: Float
    var bloomAmount: Float
    var curvatureAmount: Float
    var colorBoost: Float
    var _pad: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

// Sharp Bilinear uniforms - matches SharpBilinearUniforms in SharpBilinear.metal
struct SharpBilinearUniforms {
    var sharpness: Float
    var colorBoost: Float
    var scanlineOpacity: Float
    var _pad: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

// Eight Bit Game Boy uniforms - matches EightBitGameBoyUniforms in 8bGameBoy.metal
struct EightBitGameBoyUniforms {
    var gridStrength: Float
    var pixelSeparation: Float
    var brightnessBoost: Float
    var colorBoost: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
    var showShell: Float
    var showStrip: Float
    var showLens: Float
    var showText: Float
    var showLED: Float
    var lightPositionIndex: Float
    var lightStrength: Float
}

// Lite CRT uniforms - matches LiteCRTUniforms in LiteCRT.metal
struct LiteCRTUniforms {
    var scanlineIntensity: Float
    var phosphorStrength: Float
    var brightness: Float
    var colorBoost: Float
}

// Game Boy Color GBC uniforms - matches GBCUniforms in 8bGameBoyColor.metal
struct GBCUniforms {
    var dotOpacity: Float
    var specularShininess: Float
    var colorBoost: Float
    var physicalDepth: Float
    var ghostingWeight: Float
    var frameIndex: UInt32
    var flags: UInt32
    var gridStrength: Float
    var pixelSeparation: Float
    var brightnessBoost: Float
    var showShell: Float
    var showStrip: Float
    var showLens: Float
    var showText: Float
    var showLED: Float
    var lightPositionIndex: Float
    var lightStrength: Float
    var shellColorIndex: Float
   var gridThicknessDark: Float
   var gridThicknessLight: Float
   var sourceSize: SIMD4<Float>
   var outputSize: SIMD4<Float>
   var transparencyControl: Float
}

// ScaleSmooth uniforms - matches ScaleSmoothUniforms in ScaleSmooth.metal
struct ScaleSmoothUniforms {
    var smoothness: Float
    var colorBoost: Float
    var sourceSize: SIMD4<Float>
}

// GBA uniforms - matches GBAUniforms in GBA.metal
struct GBAUniforms {
    var dotOpacity: Float
    var specularShininess: Float
    var colorBoost: Float
    var ghostingWeight: Float
    var physicalDepth: Float
    var frameIndex: UInt32
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
    var lightPositionIndex: Float
}

// Legacy alias for CRT passthrough
typealias ShaderUniforms = CRTUniforms
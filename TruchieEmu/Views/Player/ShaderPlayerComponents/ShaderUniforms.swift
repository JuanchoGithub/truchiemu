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

// LCD Grid uniforms - matches LCDGridUniforms in LCDGrid.metal
struct LCDGridUniforms {
    var gridStrength: Float
    var pixelSeparation: Float
    var brightnessBoost: Float
    var colorBoost: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
}

// Lite CRT uniforms - matches LiteCRTUniforms in LiteCRT.metal
struct LiteCRTUniforms {
    var scanlineIntensity: Float
    var phosphorStrength: Float
    var brightness: Float
    var colorBoost: Float
}

// ScaleSmooth uniforms - matches ScaleSmoothUniforms in ScaleSmooth.metal
struct ScaleSmoothUniforms {
    var smoothness: Float
    var colorBoost: Float
    var sourceSize: SIMD4<Float>
}

// Legacy alias for CRT passthrough
typealias ShaderUniforms = CRTUniforms
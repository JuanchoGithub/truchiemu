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
    var bezelReflectionBlur: Float
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
    
    // Subpixel mask controls
    var maskPixelSpacingH: Float
    var maskPixelSpacingV: Float
    var maskSubpixelGap: Float
    var useMask: Float

    var outputWidth: Float
    var outputHeight: Float
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
    var bezelReflectionBlur: Float
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
    
    // New additions
    var phosphorDecay: Float
    var maskPixelSpacingH: Float
    var maskPixelSpacingV: Float
    var maskSubpixelGap: Float
 var useMask: Float
 
 var outputWidth: Float
 var outputHeight: Float
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
    var showCase: Float
    var showStrip: Float
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
    var brightnessBoost: Float
    var showShell: Float
    var lightPositionIndex: Float
    var lightStrength: Float
    var shellColorIndex: Float
    var gridThicknessDark: Float
    var gridThicknessLight: Float
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
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

// PSP/NDS/3DS uniforms - matches PSPUniforms in PSP.metal
struct PSPUniforms {
    var dotOpacity: Float
    var specularShininess: Float
    var colorBoost: Float
    var ghostingWeight: Float
    var physicalDepth: Float
    var frameIndex: UInt32
    var sourceSize: SIMD4<Float>
    var outputSize: SIMD4<Float>
    var lightPositionIndex: Float
    var physicalLineWidth: Float
    var _pad0: Float
    var _pad1: Float
    var colorGamut: simd_float3x3
}

// Famicom RF (Antenna TV) uniforms - matches FamicomRFUniforms in FamicomRF.metal
struct FamicomRFUniforms {
    var time: Float
    var texSizeX: Float
    var texSizeY: Float
    var outputWidth: Float
    var outputHeight: Float
    var signalStrength: Float
    var snowAmount: Float
    var tuning: Float
    var overscan: Float
    var saturation: Float
    var hue: Float
    var colorMode: Float
    var brightness: Float
    var contrast: Float
    var bleedAmount: Float
    var chromaAmount: Float
    var ntscAmount: Float
    var barrelAmount: Float
    var scanlineIntensity: Float
    var vignetteStrength: Float
    var flickerStrength: Float
    var colorBoost: Float
    var tintR: Float
    var tintG: Float
    var tintB: Float
    var channel: Float
    var showOSD: Float
    var useNtsc: Float
    var useDistort: Float
    var useScan: Float
    var useBleed: Float
    var useChroma: Float
    var useVig: Float
    var useFlick: Float
    var useBezel: Float
    var bezelRounding: Float
    var bezelGlow: Float
    var bezelReflectionBlur: Float
    var interference: Float
    var ghosting: Float
    var tearing: Float
    var colorLoss: Float
    var barsAmount: Float
}

// CRT Pittman (MinorKeyGames CRTSim port) uniforms - matches CRTPittmanUniforms in CRTPittman.metal.
// Field order must match the Metal struct exactly (all Float, sequential layout).
struct CRTPittmanUniforms {
    var tuningSharp: Float
    var persistR: Float
    var persistG: Float
    var persistB: Float
    var tuningBleed: Float
    var tuningArtifacts: Float
    var ntscStable: Float
    var bloomDownspread: Float
    var bloomUpspread: Float
    var bloomPower: Float
    var bloomIntensity: Float
    var tuningSatur: Float
    var maskBrightness: Float
    var maskOpacity: Float
    var overscan: Float
    var barrel: Float
    var pixelRatio: Float
    var dimming: Float
    var time: Float
    var texSizeX: Float
    var texSizeY: Float
    var outputWidth: Float
    var outputHeight: Float
    var frameIndex: Float
    var padding: Float
}

// Pittman Poisson blur uniforms - matches PittmanBlurUniforms in CRTPittman.metal
struct PittmanBlurUniforms {
    var spread: Float
    var aspect: Float
    var swapXY: Float
    var pad: Float
}

// Pittman mesh matrices - matches PittmanMeshUniforms in CRTPittman.metal
struct PittmanMeshUniforms {
    var wvpMat: simd_float4x4
    var worldMat: simd_float4x4
    var camPos: SIMD4<Float>
    var lightPos: SIMD4<Float>
}

// Pittman mesh lighting - matches PittmanLightUniforms in CRTPittman.metal.
// Field order must match exactly (floats, then float4, then floats).
struct PittmanMeshLighting {
    var diffBrightness: Float
    var specBrightness: Float
    var specPower: Float
    var fresBrightness: Float
    var frameColor: SIMD4<Float>
    var reflScalar: Float
    var dimming: Float
    var pad: Float
}

// Legacy alias for CRT passthrough
typealias ShaderUniforms = CRTUniforms

// RF Decoder display pass uniforms - matches RfDisplayUniforms in RfDisplay.metal
struct RfDisplayUniforms {
    var time: Float
    var texSizeX: Float
    var texSizeY: Float
    var outputWidth: Float
    var outputHeight: Float
    var barrelAmount: Float
    var scanlineIntensity: Float
    var vignetteStrength: Float
    var flickerStrength: Float
    var colorBoost: Float
    var tintR: Float
    var tintG: Float
    var tintB: Float
    var channel: Float
    var showOSD: Float
    var useDistort: Float
    var useScan: Float
    var useVig: Float
    var useFlick: Float
    var signalLoss: Float
    var rollOffset: Float
    var rollShear: Float
    var glitch: Float
    var tear: Float
    var hShift: Float
    var vHold: Float
    var hHold: Float
    var vPos: Float
    var hPos: Float
    var useBezel: Float
    var useBezelReflection: Float
    var bezelRounding: Float
    var bezelGlow: Float
    var bezelReflectionBlur: Float
}

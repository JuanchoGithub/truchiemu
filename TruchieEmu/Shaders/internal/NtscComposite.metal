#include <metal_stdlib>
#include "ShaderTypes.h.metal"
using namespace metal;

// MARK: - NTSC Composite Shader (Metal equivalent of slang:ntsc)
// Simulates NTSC composite video encoding/decoding with color artifacts.
// This creates the characteristic color bleeding and dot crawl of NTSC output.
// Best for: NES, SNES, Genesis, Master System
//
// Based on the libretro slang NTSC shader by Themaister
// Single-pass simplified version for Metal rendering

// MARK: - NTSC Encoding Table
// Pre-computed sin/cos values for NTSC color subcarrier (3.579545 MHz)

constant float NTSC_PI = 3.14159265358979323846;
constant float COLOR_FREQ = 3.579545e6;  // NTSC color subcarrier frequency

// NTSC IQ conversion matrix
constant float3x3 YIQ_TO_RGB = float3x3(
    1.0,  1.0,      0.956,
    1.0, -0.272,   -0.647,
    1.0,  1.106,   -1.105
);

constant float3x3 RGB_TO_YIQ = float3x3(
    0.299,   0.587,   0.114,
    0.596,  -0.275,  -0.321,
    0.212,  -0.523,   0.311
);

// MARK: - Uniforms

struct NtscUniforms {
    float resolution;      // Horizontal resolution (pixels per scanline)
    float artifacts;       // Color artifact strength (-1.0 to 1.0)
    float fringing;        // Color fringing amount (0.0 to 1.0)
    float bleed;           // Color bleed amount (0.0 to 1.0)
    float merge;           // Scanline merge amount (0.0 to 1.0)
    float colorBoost;      // Brightness/saturation boost
    float time;            // Frame time
    
    // Standard Libretro uniforms
    float4 SourceSize;     // (width, height, 1/width, 1/height)
    float4 OutputSize;     // viewport dimensions
};

// MARK: - Helper Functions

// Convert RGB to YIQ color space
inline float3 rgbToYiq(float3 rgb) {
    return RGB_TO_YIQ * rgb;
}

// Convert YIQ to RGB color space
inline float3 yiqToRgb(float3 yiq) {
    return YIQ_TO_RGB * yiq;
}

// NTSC encoder - converts YIQ signal to modulated waveform
float ntscEncode(float y, float i, float q, float phase) {
    float angle = phase;
    return y + i * cos(angle) + q * sin(angle);
}

// NTSC decoder - extracts YIQ from modulated waveform
float3 ntscDecode(float signal, float phase, float resolution) {
    float angle = phase;
    
    // Calculate phase offset based on resolution
    float phaseStep = (2.0 * NTSC_PI) / resolution;
    
    // Sample at different phase offsets for decoding
    float sample0 = signal;
    float sample1 = ntscEncode(0.0, cos(angle - phaseStep), sin(angle - phaseStep), phase);
    float sample2 = ntscEncode(0.0, cos(angle + phaseStep), sin(angle + phaseStep), phase);
    
    // Extract I and Q components
    float i = (sample1 - sample2) * 0.5;
    float q = sample0;
    
    return float3(q, i, 0.0);  // Y is returned in first component
}

// MARK: - Fragment Shader

fragment float4 fragmentNtscComposite(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]],
                                       constant NtscUniforms &u [[buffer(0)]]) {
    
    float2 uv = in.texCoord;
    float2 sourceSize = u.SourceSize.xy;
    float2 sourceSizeInv = u.SourceSize.zw;
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    // Original pixel position
    float2 pix = uv * sourceSize;
    int x = int(pix.x);
    int y = int(pix.y);
    
    // NTSC color phase advances each pixel
    // Standard NTSC: 3.579545 MHz, ~3.5 cycles per pixel at 240p
    float phaseOffset = float(x) * (2.0 * NTSC_PI) / u.resolution;
    
    // Also advance phase per scanline (different color framing on odd/even lines)
    float linePhase = float(y) * NTSC_PI;
    float totalPhase = phaseOffset + linePhase;
    
    // Sample source texture
    float3 srcColor = tex.sample(s, uv).rgb;
    
    // Convert to YIQ
    float3 yiq = rgbToYiq(srcColor);
    float Y = yiq.x;
    float I = yiq.y;
    float Q = yiq.z;
    
    // --- NTSC Encoding Stage ---
    // Encode into composite signal
    float compositeSignal = ntscEncode(Y, I, Q, totalPhase);
    
    // --- NTSC Decoding Stage ---
    // Decode with adjacent pixel samples to simulate artifacts
    
    // Sample adjacent pixels for artifact simulation
    float3 leftColor  = tex.sample(s, uv - float2(sourceSizeInv.x, 0.0)).rgb;
    float3 rightColor = tex.sample(s, uv + float2(sourceSizeInv.x, 0.0)).rgb;
    
    // Convert adjacent to YIQ
    float3 leftYIQ  = rgbToYiq(leftColor);
    float3 rightYIQ = rgbToYiq(rightColor);
    
    // Decode using weighted averaging (simulates decoder low-pass filter)
    float blendWeight = u.bleed;
    float decodedY = mix(Y, (leftYIQ.x + rightYIQ.x) * 0.5, blendWeight);
    float decodedI = mix(I, (leftYIQ.y + rightYIQ.y) * 0.5, blendWeight);
    float decodedQ = mix(Q, (leftYIQ.z + rightYIQ.z) * 0.5, blendWeight);
    
    // Color artifact simulation
    // When artifact strength is positive, color bleeds between adjacent pixels
    // When negative, produces sharper colors but with potential dot crawl
    float artifactStrength = u.artifacts;
    
    // Phase-dependent color shift (simulates hue errors from phase mismatch)
    float hueError = sin(totalPhase * 2.0) * artifactStrength * 0.1;
    decodedI += hueError;
    
    // Cross-color artifacts (luma bleeding into chroma)
    float crossColor = sin(totalPhase) * Y * artifactStrength * 0.05;
    decodedQ += crossColor;
    
    // Color fringing (chroma bleeding at edges)
    float edgeDetect = abs(Y - (leftYIQ.x + rightYIQ.x) * 0.5);
    float fringingAmount = edgeDetect * u.fringing * artifactStrength;
    decodedI += fringingAmount * sin(totalPhase);
    decodedQ += fringingAmount * cos(totalPhase);
    
    // --- Scanline Merging ---
    // Merge adjacent scanlines to reduce flicker on some content
    if (u.merge > 0.0) {
        float3 aboveColor = tex.sample(s, uv - float2(0.0, sourceSizeInv.y)).rgb;
        float3 belowColor = tex.sample(s, uv + float2(0.0, sourceSizeInv.y)).rgb;
        
        float3 aboveYIQ = rgbToYiq(aboveColor);
        float3 belowYIQ = rgbToYiq(belowColor);
        
        decodedY = mix(decodedY, (aboveYIQ.x + belowYIQ.x) * 0.5, u.merge * 0.3);
    }
    
    // Convert back to RGB
    float3 outputYIQ = float3(decodedY, decodedI, decodedQ);
    float3 outputColor = yiqToRgb(outputYIQ);
    
    // --- Color Boost ---
    outputColor *= u.colorBoost;
    
    // --- Gamma Correction ---
    // Apply slight gamma to match CRT response
    outputColor = pow(saturate(outputColor), float3(1.0 / 2.2));
    
    // Clamp and return
    outputColor = saturate(outputColor);
    return float4(outputColor, 1.0);
}
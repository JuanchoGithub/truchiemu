#include <metal_stdlib>
#include "ShaderTypes.h.metal"
using namespace metal;

// MARK: - Composite / VHS Shader
// Simulates composite video output with horizontal color bleeding.
// Fixes dithering artifacts by blending horizontal patterns.
// Best for: NES, Genesis, SNES, SMS - games that used dithering for colors

// MARK: - Uniforms
struct CompositeUniforms {
    float horizontalBlur; // 0.5 - 5.0: Amount of horizontal blur
    float verticalBlur;   // 0.0 - 2.0: Amount of vertical blur (much less than horizontal)
    float bleedAmount;    // 0.0 - 1.0: Color bleeding strength
    float colorBoost;     // 0.5 - 2.0: Brightness multiplier
    float time;           // Frame time
    
    // Standard Libretro uniforms
    float4 SourceSize;    // (width, height, 1/width, 1/height)
    float4 OutputSize;    // viewport dimensions
};

// MARK: - Helper Functions

// Gaussian-weighted horizontal blur sample
float4 sampleHorizontal(texture2d<float> tex, sampler s, float2 uv, float offset, float weight) {
    return tex.sample(s, uv + float2(offset, 0.0)) * weight;
}

// MARK: - Fragment Shader

fragment float4 fragmentComposite(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant CompositeUniforms &u [[buffer(0)]]) {
    
    float2 uv = in.texCoord;
    float2 px = u.SourceSize.zw; // 1/width, 1/height
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    float4 color = float4(0.0);
    
    // --- Horizontal Blur (NTSC/PAL style) ---
    // Composite video blurs horizontally due to bandwidth limitations
    // This causes dithered patterns to "bleed" into solid colors
    
    float hKernel[11];
    float hSigma = u.horizontalBlur * 0.5;
    float hSum = 0.0;
    
    // Build Gaussian kernel
    for (int i = -5; i <= 5; i++) {
        float x = float(i);
        float w = exp(-(x * x) / (2.0 * hSigma * hSigma));
        hKernel[i + 5] = w;
        hSum += w;
    }
    
    // Normalize kernel
    for (int i = 0; i < 11; i++) {
        hKernel[i] /= hSum;
    }
    
    // Apply horizontal blur
    for (int i = -5; i <= 5; i++) {
        float offset = float(i) * px.x;
        color += sampleHorizontal(tex, s, uv, offset, hKernel[i + 5]);
    }
    
    // --- Vertical Blur (subtle) ---
    // Much less vertical blur to maintain scanline-like feel
    if (u.verticalBlur > 0.0) {
        float4 blurred = color;
        float vSigma = u.verticalBlur * 0.3;
        float4 vColor = float4(0.0);
        float vSum = 0.0;
        
        for (int i = -3; i <= 3; i++) {
            float x = float(i);
            float w = exp(-(x * x) / (2.0 * vSigma * vSigma));
            vColor += tex.sample(s, uv + float2(0.0, float(i) * px.y)) * w;
            vSum += w;
        }
        
        color = mix(color, vColor / vSum, u.verticalBlur / (u.verticalBlur + 1.0));
    }
    
    // --- Color Bleeding ---
    // Simulates RGB sub-pixel bleeding in composite signal
    float4 bleedLeft  = tex.sample(s, uv - float2(px.x * 0.5, 0.0));
    float4 bleedRight = tex.sample(s, uv + float2(px.x * 0.5, 0.0));
    
    // Blend adjacent pixels into R and B channels only
    color.r = mix(color.r, (bleedLeft.r + bleedRight.r) * 0.5, u.bleedAmount);
    color.b = mix(color.b, (bleedLeft.b + bleedRight.b) * 0.5, u.bleedAmount);
    
    // --- Color Boost ---
    color.rgb *= u.colorBoost;
    
    // --- Subtle VHS Noise ---
    // Add very subtle horizontal noise lines
    float noise = fract(sin(float(int(in.position.y)) * 12.9898) * 43758.5453);
    float noiseLine = step(0.998, noise) * 0.03;
    color.rgb += noiseLine;
    
    // Clamp and return
    color.rgb = saturate(color.rgb);
    color.a = 1.0;
    
    return color;
}
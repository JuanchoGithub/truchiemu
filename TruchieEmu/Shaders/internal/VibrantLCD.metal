#include <metal_stdlib>
#include "ShaderTypes.h.metal"
using namespace metal;

// MARK: - Vibrant LCD Shader
// Gamma correction and saturation boost for washed-out handheld games.
// Target: GBA, PSP, NDS

// MARK: - Uniforms
struct VibrantLCDUniforms {
    float saturation;     // 0.5 - 3.0: Color saturation multiplier
    float gamma;          // 1.0 - 3.0: Gamma correction value
    float colorBoost;     // 0.5 - 2.5: Brightness multiplier
    float time;           // Frame time
    
    // Standard Libretro uniforms
    float4 SourceSize;    // (width, height, 1/width, 1/height)
    float4 OutputSize;    // viewport dimensions
};

// MARK: - Helper Functions

// Convert RGB to HSV
float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Convert HSV to RGB
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, saturate(p - K.xxx), c.y);
}

// Apply gamma correction
float3 applyGamma(float3 color, float gamma) {
    return pow(saturate(color), float3(1.0 / gamma));
}

// MARK: - Fragment Shader

fragment float4 fragmentVibrantLCD(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant VibrantLCDUniforms &u [[buffer(0)]]) {
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float4 color = tex.sample(s, uv);
    
    // --- Gamma Correction ---
    // GBA games were mastered for a dark screen, so they appear washed out on modern displays
    color.rgb = applyGamma(color.rgb, u.gamma);
    
    // --- Saturation Boost ---
    if (u.saturation != 1.0) {
        float3 hsv = rgb2hsv(color.rgb);
        hsv.y = saturate(hsv.y * u.saturation);  // Boost saturation channel
        color.rgb = hsv2rgb(hsv);
    }
    
    // --- Color Boost ---
    color.rgb *= u.colorBoost;
    
    // --- Subtle LCD pixel pattern ---
    // Add very subtle pixel grid to maintain retro feel
    float2 pixelPos = in.position.xy;
    float pixelGrid = (sin(pixelPos.x * 3.14159) * sin(pixelPos.y * 3.14159)) * 0.01;
    color.rgb -= pixelGrid;
    
    // Clamp and return
    color.rgb = saturate(color.rgb);
    color.a = 1.0;
    
    return color;
}
#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// Lottes CRT Shader (Simplified / Lightweight)
// High quality scanlines, shadow mask, and subtle curvature.
// ============================================================
struct LottesUniforms {
    float scanlineStrength;
    float maskStrength;
    float bloomAmount;
    float curvatureAmount;
    float colorBoost;
    float _pad;
    float4 sourceSize;
    float4 outputSize;
};

// Helper for curvature
float2 distort(float2 uv, float curvature) {
    if (curvature == 0.0) return uv;
    float2 centered = uv * 2.0 - 1.0;
    float2 offset = centered.yx * centered.yx;
    centered += centered * offset * curvature;
    return centered * 0.5 + 0.5;
}

fragment float4 fragmentLottesCRT(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant LottesUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    float2 uv = distort(in.texCoord, u.curvatureAmount);
    
    // Bounds check for curvature
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return float4(0, 0, 0, 1);
    }
    
    // Scanline & Beam logic
    float2 pos = uv * u.sourceSize.xy;
    // Sample with slight vertical blur for scanline weighting
    float4 color = tex.sample(s, uv);
    
    // Scanline weight (Gaussian-like)
    float scanWeight = sin(uv.y * u.sourceSize.y * M_PI_F * 2.0) * 0.5 + 0.5;
    float beam = mix(1.0, 1.0 - u.scanlineStrength * scanWeight, u.scanlineStrength);
    color.rgb *= beam;
    
    // Shadow Mask (Aperture Grille style)
    float maskPos = in.position.x;
    int m = int(maskPos) % 3;
    float3 maskColor = float3(1.0);
    if (m == 0) maskColor = float3(1.0, 0.7, 0.7);
    else if (m == 1) maskColor = float3(0.7, 1.0, 0.7);
    else maskColor = float3(0.7, 0.7, 1.0);
    
    color.rgb = mix(color.rgb, color.rgb * maskColor, u.maskStrength);
    
    // Simple Bloom / Halation
    if (u.bloomAmount > 0.0) {
        float brightness = dot(color.rgb, float3(0.299, 0.587, 0.114));
        color.rgb += color.rgb * brightness * u.bloomAmount;
    }
    
    color.rgb *= u.colorBoost;
    color.a = 1.0;
    return color;
}

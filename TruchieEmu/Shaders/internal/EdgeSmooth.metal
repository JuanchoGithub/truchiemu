#include <metal_stdlib>
#include "ShaderTypes.h.metal"
using namespace metal;

// MARK: - Edge Smooth Shader
// Edge-directed interpolation that smooths pixel art while preserving sharp diagonals.
// Similar to xBRZ algorithm but simplified for real-time performance.
// Best for: 2D RPGs (Chrono Trigger, Final Fantasy), pixel art games

// MARK: - Uniforms
struct EdgeSmoothUniforms {
    float smoothStrength; // 0.0 - 1.0: How aggressively to smooth edges
    float colorBoost;     // 0.5 - 2.0: Brightness multiplier
    float time;           // Frame time
    
    // Standard Libretro uniforms
    float4 SourceSize;    // (width, height, 1/width, 1/height)
    float4 OutputSize;    // viewport dimensions
};

// MARK: - Helper Functions

// Sample texture at offset
float4 sampleOffset(texture2d<float> tex, sampler s, float2 uv, float2 offset) {
    return tex.sample(s, uv + offset);
}

// Basic luma calculation
float luma(float3 color) {
    return dot(color, float3(0.299, 0.587, 0.114));
}

// Check if two colors are similar
bool colorsSimilar(float3 a, float3 b, float threshold = 0.12) {
    return distance(a, b) < threshold;
}

// MARK: - Fragment Shader

fragment float4 fragmentEdgeSmooth(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant EdgeSmoothUniforms &u [[buffer(0)]]) {
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float2 px = u.SourceSize.zw; // 1/width, 1/height
    
    // Current pixel
    float4 center = tex.sample(s, uv);
    
    // --- Edge Detection ---
    // Sample 3x3 neighborhood
    float4 tl = sampleOffset(tex, s, uv, -px);         // top-left
    float4 t  = sampleOffset(tex, s, uv, float2(0, -px.y));  // top
    float4 tr = sampleOffset(tex, s, uv, float2(px.x, -px.y)); // top-right
    float4 l  = sampleOffset(tex, s, uv, float2(-px.x, 0));    // left
    float4 r  = sampleOffset(tex, s, uv, float2(px.x, 0));     // right
    float4 bl = sampleOffset(tex, s, uv, float2(-px.x, px.y)); // bottom-left
    float4 b  = sampleOffset(tex, s, uv, float2(0, px.y));     // bottom
    float4 br = sampleOffset(tex, s, uv, px);            // bottom-right
    
    // --- Detect Edges Using Gradients ---
    float lumC = luma(center.rgb);
    float lumL = luma(l.rgb);
    float lumR = luma(r.rgb);
    float lumT = luma(t.rgb);
    float lumB = luma(b.rgb);
    
    float hGrad = abs(lumL - lumR);  // Horizontal gradient
    float vGrad = abs(lumT - lumB);  // Vertical gradient
    
    // --- Smoothing Logic ---
    float4 smoothed = center;
    
    // If both gradients are small, we're in a flat area - smooth it
    if (hGrad < 0.08 && vGrad < 0.08) {
        smoothed = (center * 4.0 + l + r + t + b) / 8.0;
        smoothed = mix(center, smoothed, u.smoothStrength);
    }
    // If one gradient is dominant, we're on an edge - smooth perpendicular to edge
    else if (hGrad > vGrad * 1.5) {
        // Vertical edge - smooth horizontally
        float4 hSmooth = (l + r) * 0.25 + center * 0.5;
        smoothed = mix(center, hSmooth, u.smoothStrength);
    }
    else if (vGrad > hGrad * 1.5) {
        // Horizontal edge - smooth vertically
        float4 vSmooth = (t + b) * 0.25 + center * 0.5;
        smoothed = mix(center, vSmooth, u.smoothStrength);
    }
    // Diagonal edge - check corner pixels
    else {
        // Detect if diagonal pixels match center
        bool matchTL = colorsSimilar(center.rgb, tl.rgb, 0.15);
        bool matchBR = colorsSimilar(center.rgb, br.rgb, 0.15);
        bool matchTR = colorsSimilar(center.rgb, tr.rgb, 0.15);
        bool matchBL = colorsSimilar(center.rgb, bl.rgb, 0.15);
        
        if ((matchTL && matchBR) || (matchTR && matchBL)) {
            // Diagonal match detected - smooth along the diagonal
            float4 diagSmooth = (tl + br + tr + bl) * 0.125 + center * 0.5;
            smoothed = mix(center, diagSmooth, u.smoothStrength * 0.5);
        }
    }
    
    // Apply color boost
    smoothed.rgb *= u.colorBoost;
    
    // Clamp and return
    smoothed.rgb = saturate(smoothed.rgb);
    smoothed.a = 1.0;
    
    return smoothed;
}
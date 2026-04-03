#include <metal_stdlib>
#include "ShaderTypes.h.metal"
using namespace metal;

// MARK: - LCD Grid Shader
// Simulates handheld LCD pixel grid with optional motion ghosting.
// Target: Game Boy, GBC, Game Gear, SMS

// MARK: - Uniforms
struct LCDGridUniforms {
    float gridOpacity;      // 0.0 - 1.0: Opacity of the grid overlay
    float ghostingAmount;   // 0.0 - 0.5: Motion blur/ghosting effect
    float gridSize;         // 1.0 - 6.0: Size of LCD grid cells
    float colorBoost;       // 0.5 - 2.0: Brightness multiplier
    float time;             // Frame time for ghosting
    
    // Standard Libretro uniforms
    float4 SourceSize;      // (width, height, 1/width, 1/height)
    float4 OutputSize;      // viewport dimensions
};

// MARK: - Fragment Shader
// Note: Removed dead buffer(2) parameter - u_time was never bound from Swift
fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    
    // --- Ghosting / Motion Blur ---
    float4 color = tex.sample(s, uv);
    
    if (u.ghostingAmount > 0.0) {
        // Sample previous frame positions (simulated with UV offset)
        float ghostUV = 0.002 * u.ghostingAmount;
        float4 ghost1 = tex.sample(s, uv - float2(ghostUV, 0.0));
        float4 ghost2 = tex.sample(s, uv + float2(0.0, ghostUV));
        float4 ghost3 = tex.sample(s, uv - float2(ghostUV, ghostUV));
        
        color = mix(color, (color + ghost1 + ghost2 + ghost3) / 4.0, u.ghostingAmount);
    }
    
    // Apply color boost
    color.rgb *= u.colorBoost;
    
    // --- LCD Grid Pattern ---
    if (u.gridOpacity > 0.0) {
        // Calculate grid coordinates
        float2 gridUV = in.position.xy / u.gridSize;
        float2 gridCell = fract(gridUV);
        
        // Create grid lines (dark borders around each cell)
        float2 gridLine = smoothstep(0.0, 0.05, gridCell) * smoothstep(1.0, 0.95, gridCell);
        float gridMask = gridLine.x * gridLine.y;
        
        // Apply grid with opacity
        float3 gridColor = float3(gridMask);
        color.rgb = mix(color.rgb, color.rgb * gridColor, u.gridOpacity);
        
        // Subtle LCD reflection effect
        float reflection = sin(in.position.y * 0.1) * 0.02;
        color.rgb += reflection;
    }
    
    // Clamp color
    color.rgb = saturate(color.rgb);
    color.a = 1.0;
    
    return color;
}
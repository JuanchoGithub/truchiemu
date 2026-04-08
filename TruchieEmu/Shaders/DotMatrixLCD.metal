#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// Dot Matrix LCD Shader (Game Boy metallic dot-matrix display)
// ============================================================
struct DotMatrixLCDUniforms {
    float dotOpacity;
    float metallicIntensity;
    float specularShininess;
    float colorBoost;
    float4 sourceSize;
    float4 outputSize;
};

fragment float4 fragmentDotMatrixLCD(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]],
                                       constant DotMatrixLCDUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float4 color = tex.sample(s, uv);
    
    // Scale position by source pixel size to get dot-level coordinates
    float2 srcTexelSize = u.sourceSize.zw;
    float2 pixelPos = uv / srcTexelSize;  // position in source pixel units
    
    // Dot matrix grid - each source pixel becomes a visible dot
    float2 dotUV = fract(pixelPos);   // position within each dot [0,1)
    float2 dotID = floor(pixelPos);   // which dot we're on
    
    // Create round dot shape with soft edges
    float2 dotCenter = dotUV - 0.5;
    float dotDist = length(dotCenter * 1.6);        // scale to make dots slightly smaller
    float dotShape = 1.0 - smoothstep(0.35, 0.45, dotDist);
    
    // Metal grid between dots
    // Metallic sheen - directional highlight based on dot position
    float sheenAngle = fract(dotID.x * 0.31 + dotID.y * 0.17);
    float metallicSheen = pow(sheenAngle, 3.0) * u.metallicIntensity;
    
    // Specular highlight (sharp bright spot on dot grid)
    float2 specUV = dotUV - float2(0.35, 0.35);    // offset highlight
    float specDist = length(specUV * 2.5);
    float specular = pow(max(1.0 - specDist, 0.0), u.specularShininess);
    
    // Sub-grid horizontal lines (LCD row separators)
    float rowLine = smoothstep(0.44, 0.48, abs(dotCenter.y));
    
    // Build metallic grid color
    float3 gridColor = float3(0.15, 0.18, 0.20);     // dark metallic base
    gridColor += float3(0.35, 0.38, 0.40) * metallicSheen;  // sheen variation
    gridColor += float3(0.6, 0.63, 0.65) * specular;        // specular highlight
    gridColor += float3(0.05, 0.06, 0.06) * rowLine;        // row separator
    
    // Apply dot matrix effect
    if (u.dotOpacity > 0.0) {
        // Darken grid areas
        float3 withGrid = mix(gridColor, color.rgb, dotShape);
        
        // Add subtle LCD backlight tint (slight warm cast like original Game Boy)
        float backlight = 1.0 + dotShape * 0.05;
        withGrid *= backlight;
        
        // Blend between original and dot matrix based on opacity
        color.rgb = mix(color.rgb, withGrid, u.dotOpacity);
        
        // Subtle vignette on each dot for depth
        float vignette = 1.0 - dotDist * 0.3;
        color.rgb *= vignette;
    }
    
    color.rgb *= u.colorBoost;
    color.rgb = saturate(color.rgb);
    color.a = 1.0;
    return color;
}

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct LCDGridUniforms {
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float colorBoost;
    float4 sourceSize; // 160x144
    float4 outputSize; // Current window size
};

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    // 1. CALCULATE COORDINATE ANCHORS
    float targetAspect = u.sourceSize.x / u.sourceSize.y;
    float windowAspect = u.outputSize.x / u.outputSize.y;
    
    float scale;
    float2 offset = float2(0.0);

    // Calculate scaling and centering offsets based on window shape
    if (windowAspect > targetAspect) {
        // Window is wider: Pillarbox (Black bars on sides)
        scale = u.outputSize.y / u.sourceSize.y;
        offset.x = (u.outputSize.x - (u.sourceSize.x * scale)) * 0.5;
    } else {
        // Window is taller: Letterbox (Black bars on top/bottom)
        scale = u.outputSize.x / u.sourceSize.x;
        offset.y = (u.outputSize.y - (u.sourceSize.y * scale)) * 0.5;
    }

    // 2. COORDINATE TRANSFORM (The "Safe Zone" Fix)
    // We normalize the current fragment position relative to our centered offset
    float2 pixelCoord = (in.position.xy - offset) / scale;

    // 3. BOUNDARY GUARD (Prevents clipping and ensures full visibility)
    // This ensures every game pixel from (0,0) to (160,144) is checked
    if (pixelCoord.x < 0.0 || pixelCoord.x >= u.sourceSize.x ||
        pixelCoord.y < 0.0 || pixelCoord.y >= u.sourceSize.y) {
        return float4(0.0, 0.0, 0.0, 1.0); // Render black for anything outside the game
    }

    // 4. PIXEL-PERFECT ALIGNMENT
    float2 texelCenter = floor(pixelCoord) + 0.5;
    float2 alignedUV = texelCenter / u.sourceSize.xy;

    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 rawColor = tex.sample(s, alignedUV).rgb;
    
    // Color Targets: Background (149, 147, 110) & Solid Red (128, 48, 44)
    float3 physicalBase = float3(0.584, 0.576, 0.431);
    float3 color = pow(rawColor, 1.8) * float3(0.85, 0.55, 0.50);

    // 5. THE UNIFORM GRID
    float2 gridFract = fract(pixelCoord);
    float2 gridLines = step(u.pixelSeparation, gridFract) * step(gridFract, 1.0 - u.pixelSeparation);
    float gridMask = gridLines.x * gridLines.y;

    // Rounded Corners (Trapezoidal Gap)
    float2 distToEdge = abs(gridFract - 0.5);
    float cornerMask = smoothstep(0.47, 0.42, length(max(distToEdge - 0.35, 0.0)));
    gridMask *= cornerMask;

    // 6. FINAL OUTPUT & SUBPIXEL
    float3 finalColor = mix(physicalBase, color, gridMask * u.gridStrength);

    uint xPos = uint(in.position.x);
    float3 subMask = float3(1.0);
    if (xPos % 3 == 0)      subMask = float3(1.02, 0.98, 0.98);
    else if (xPos % 3 == 1) subMask = float3(0.98, 1.02, 0.98);
    else                    subMask = float3(0.98, 0.98, 1.02);
    
    finalColor *= subMask;
    finalColor *= u.brightnessBoost;
    finalColor *= u.colorBoost;

    return float4(finalColor, 1.0);
}

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct LCDGridUniforms {
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float colorBoost;
    float4 sourceSize; // 160x144
    float4 outputSize; // Your window size
};

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    // 1. CALCULATE TRUE SCALE
    // We use the reported 160x144 to ensure we stay inside the buffer
    float2 ratio = u.outputSize.xy / u.sourceSize.xy;
    float2 pixelCoord = in.position.xy / ratio;

    // 2. THE CLAMP (Fixes the "Outside Drawing Area" issue)
    // If we are outside the 160x144 range, return black bars
    if (pixelCoord.x < 0.0 || pixelCoord.x >= u.sourceSize.x ||
        pixelCoord.y < 0.0 || pixelCoord.y >= u.sourceSize.y) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // 3. PIXEL-PERFECT SAMPLING
    float2 texelCenter = floor(pixelCoord) + 0.5;
    float2 alignedUV = texelCenter / u.sourceSize.xy;

    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 rawColor = tex.sample(s, alignedUV).rgb;
    
    // Target Colors: Physical Background (149, 147, 110) & Heart Red (128, 48, 44)
    float3 physicalBase = float3(0.584, 0.576, 0.431);
    float3 color = pow(rawColor, 1.8) * float3(0.85, 0.55, 0.50);

    // 4. UNIFORM GRID MASK
    float2 gridFract = fract(pixelCoord);
    float2 gridLines = step(u.pixelSeparation, gridFract) * step(gridFract, 1.0 - u.pixelSeparation);
    float gridMask = gridLines.x * gridLines.y;

    // Organic Intersections (Trapezoidal feel)
    float2 distToEdge = abs(gridFract - 0.5);
    float cornerMask = smoothstep(0.47, 0.42, length(max(distToEdge - 0.35, 0.0)));
    gridMask *= cornerMask;

    // 5. BLEND & SUBPIXEL OPTIMIZATION
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

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct LCDGridUniforms {
    float gridStrength;
    float pixelSeparation; // Use this for the gap width (e.g., 0.1 to 0.2)
    float brightnessBoost;
    float colorBoost;
    float4 sourceSize;
    float4 outputSize;
};

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    // 1. PHYSICAL GRID COORDINATES
    float2 gameRes = float2(160.0, 144.0);
    float scale = min(u.outputSize.x / gameRes.x, u.outputSize.y / gameRes.y);
    float intScale = max(1.0, floor(scale));
    float2 offset = (u.outputSize.xy - (gameRes * intScale)) * 0.5;

    float2 fragCoord = in.position.xy;
    float2 relativePos = fragCoord - offset;
    float2 modPos = fmod(relativePos, intScale);

    // Boundary check for black bars
    if (relativePos.x < 0.0 || relativePos.x >= (gameRes.x * intScale) ||
        relativePos.y < 0.0 || relativePos.y >= (gameRes.y * intScale)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // 2. THE BACKGROUND (The "Paper" layer)
    // This color is visible in the gaps AND through transparent pixels
    float3 targetGrid = float3(0.608, 0.635, 0.490);

    // 3. THE GAP STENCIL
    float gapWidth = max(1.0, u.pixelSeparation);
    bool isGap = (modPos.x < gapWidth || modPos.y < gapWidth);

    if (isGap) {
        return float4(targetGrid, 1.0);
    }

    // 4. SAMPLING THE DIGITAL IMAGE
    float2 pixelCoord = floor(relativePos / intScale);
    float2 uv = (pixelCoord + 0.5) / gameRes;
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 sourceCol = tex.sample(s, uv).rgb;

    // 5. COLOR INJECTION (The "Ink" layer)
    float3 targetRed    = float3(0.536, 0.155, 0.148);
    float3 targetGreen  = float3(0.227, 0.412, 0.220);
    float3 targetYellow = float3(0.590, 0.580, 0.404);

    // Detection
    bool isRed    = (sourceCol.r > 0.65 && sourceCol.g < 0.35 && sourceCol.b < 0.35);
    bool isGreen  = (sourceCol.g > 0.55 && sourceCol.r < 0.45 && sourceCol.b < 0.45);
    bool isYellow = (sourceCol.r > 0.60 && sourceCol.g > 0.50 && sourceCol.b < 0.45 && abs(sourceCol.r - sourceCol.g) < 0.2);

    float3 pixelInk;
    if (isRed) {
        pixelInk = targetRed;
    } else if (isGreen) {
        pixelInk = targetGreen;
    } else if (isYellow) {
        pixelInk = targetYellow;
    } else {
        // For everything else, treat the source color as the ink color
        pixelInk = sourceCol;
    }

    // 6. THE MASK BLEND (Subtractive/Multiplicative Logic)
    // White (1.0) makes the mask fully transparent -> shows targetGrid.
    // Black (0.0) makes the mask opaque -> shows a very dark version of the ink.
    // We use a base opacity of 0.05 for blacks as you suggested.
    
    // We calculate "how much to reveal the background" based on the luminance of the ink
    float luminance = dot(pixelInk, float3(0.299, 0.587, 0.114));
    float alpha = mix(0.05, 1.0, luminance);

    // Final Blend: Result = Ink * alpha + Grid * (1 - alpha)
    // But to get that "White is Transparent" look, we simply lerp:
    float3 finalColor = mix(pixelInk, targetGrid, alpha);

    return float4(finalColor * u.brightnessBoost * u.colorBoost, 1.0);
}

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct LCDGridUniforms {
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float colorBoost;
    float4 sourceSize;
    float4 outputSize;
};

struct PixelData {
    float3 ink;
    float alpha;
};

// 1. PSEUDO-RANDOM NOISE FUNCTION
float grain(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

// 2. GBC COLOR CORRECTION (The "Hue Fix")
float3 applyGBCMatrix(float3 color) {
    // This matrix desaturates and shifts "Neon" emulator colors
    // to match the limited gamut of the real GBC LCD.
    float3 corrected;
    corrected.r = dot(color, float3(0.84, 0.16, 0.00));
    corrected.g = dot(color, float3(0.14, 0.68, 0.18));
    corrected.b = dot(color, float3(0.04, 0.28, 0.68));
    return saturate(corrected);
}

PixelData getGBPixel(float2 coord, texture2d<float> tex, float2 gameRes) {
    float2 uv = (floor(coord) + 0.5) / gameRes;
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float3 rawCol = tex.sample(s, uv).rgb;
    
    // APPLY COLOR CORRECTION IMMEDIATELY
    float3 col = applyGBCMatrix(rawCol);

    float3 tRed    = float3(0.536, 0.155, 0.148);
    float3 tGreen  = float3(0.227, 0.412, 0.220);
    float3 tYellow = float3(0.590, 0.580, 0.404);

    // Detection (using corrected colors for better accuracy)
    bool isRed    = (col.r > 0.55 && col.g < 0.40 && col.b < 0.40);
    bool isGreen  = (col.g > 0.45 && col.r < 0.45 && col.b < 0.45);
    bool isYellow = (col.r > 0.50 && col.g > 0.45 && col.b < 0.40 && abs(col.r - col.g) < 0.25);
    bool isWhite  = (col.r > 0.90 && col.g > 0.90 && col.b > 0.90);

    PixelData p;
    if (isWhite) { p.ink = float3(1.0); p.alpha = 1.0; }
    else if (isRed)    { p.ink = tRed;   p.alpha = 0.20; }
    else if (isGreen)  { p.ink = tGreen; p.alpha = 0.30; }
    else if (isYellow) { p.ink = tYellow; p.alpha = 0.45; }
    else {
        p.ink = col;
        float lum = dot(col, float3(0.299, 0.587, 0.114));
        p.alpha = mix(0.03, 1.0, lum);
    }
    return p;
}

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
    float2 gameRes = float2(160.0, 144.0);
    float scale = min(u.outputSize.x / gameRes.x, u.outputSize.y / gameRes.y);
    float intScale = max(1.0, floor(scale));
    float2 offset = (u.outputSize.xy - (gameRes * intScale)) * 0.5;

    float2 fragCoord = in.position.xy;
    float2 relativePos = fragCoord - offset;

    if (relativePos.x < 0.0 || relativePos.x >= (gameRes.x * intScale) ||
        relativePos.y < 0.0 || relativePos.y >= (gameRes.y * intScale)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // 3. BACKGROUND + GRAIN
    float3 backgroundBase = float3(0.608, 0.635, 0.490);
    // Add a very subtle (2%) noise texture to the background
    float noise = grain(fragCoord);
    backgroundBase *= (0.98 + 0.04 * noise);

    // 4. SHADOW LAYER
    float2 shadowSampleCoord = (relativePos - 1.5) / intScale;
    PixelData shadowSource = getGBPixel(shadowSampleCoord, tex, gameRes);
    float shadowFactor = mix(0.80, 1.0, shadowSource.alpha);
    float3 shadowedBackground = backgroundBase * shadowFactor;

    // 5. INK LAYER
    float2 modPos = fmod(relativePos, intScale);
    float2 currentPixelPos = floor(relativePos / intScale);
    float gapSize = max(1.0, u.pixelSeparation);
    bool isInsideSquare = (modPos.x >= gapSize && modPos.y >= gapSize);

    float3 finalColor;
    if (isInsideSquare) {
        PixelData current = getGBPixel(currentPixelPos, tex, gameRes);
        finalColor = mix(current.ink, shadowedBackground, current.alpha);
    } else {
        finalColor = shadowedBackground;
    }

    // Apply global boosts at the very end
    return float4(finalColor * u.brightnessBoost * u.colorBoost, 1.0);
}

/*
 * TruchieEmu: 8bit Game Boy Color Hardware Simulation (Dandelion Edition)
 * VERSION HISTORY:
 * v20.9: Shadow moved to Top-Right/Top-Bottom to simulate physical recess.
 * Added dark inner bezel line. Perfectly parallel vertical lens sides.
 */

#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct GBCUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float physicalDepth;
    float ghostingWeight;
    uint  frameIndex;
    uint  flags;
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float showShell;
    float showStrip;
    float showLens;
    float showText;
    float showLED;
    float lightPositionIndex;
    float lightStrength;
    float4 sourceSize;
    float4 outputSize;
};

// --- FONT SYSTEM ---
uint getCharBlockGBC(int c) {
    switch(c) {
        case 0: return 11245; case 1: return 27566; case 2: return 31015;
        case 3: return 31143; case 4: return 14699; case 5: return 18727;
        case 6: return 24429; case 7: return 15211; case 8: return 27556;
        case 9: return 27565; case 10: return 23421; case 11: return 23186;
        default: return 0;
    }
}

constant int TEXT_GAMEBOY_LOGO[8] = {4,0,6,3, -1, 1,7,11};
constant int TEXT_COLOR_LOGO[5]   = {2,7,5,7,9};

float drawStringGBC(float2 p, constant int* textArray, int len) {
    int charIndex = int(floor(p.x / 4.0));
    if (charIndex < 0 || charIndex >= len) return 0.0;
    float2 charP = float2(fmod(max(p.x, 0.0), 4.0), p.y);
    if (charP.x >= 3.0 || charP.y < 0.0 || charP.y >= 5.0) return 0.0;
    int c = textArray[charIndex];
    if (c == -1) return 0.0;
    uint glyph = getCharBlockGBC(c);
    int bit = 14 - (int(floor(charP.y)) * 3 + int(floor(charP.x)));
    return (glyph & (1u << bit)) != 0 ? 1.0 : 0.0;
}

float sdRoundRectGBC(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + float2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

// --- SHELL RENDERING ---
float4 renderGBCShell(float2 p, constant GBCUniforms &u) {
    float2 screenCenter = float2(0.0, -8.0);
    float2 screenSize = float2(70.0, 52.0);
    float2 lensCenter = float2(0.0, 3.0);
    float2 lensSize = float2(83.0, 72.0);

    float2 lensP = p - lensCenter;
    float lensSDF = sdRoundRectGBC(lensP, lensSize, 10.0);
    
    // Independent Bottom Chin
    if (lensP.y > 45.0) {
        float flare = 12.0 * smoothstep(45.0, 72.0, lensP.y);
        float2 flareP = lensP;
        flareP.x = abs(flareP.x) - flare;
        float flareSDF = sdRoundRectGBC(float2(flareP.x, lensP.y - 65.0), float2(15.0, 8.0), 8.0);
        lensSDF = min(lensSDF, flareSDF);
    }
    
    float screenSDF = sdRoundRectGBC(p - screenCenter, screenSize, 1.0);
    float3 col = float3(0.98, 0.85, 0.0);

    if (lensSDF < 0.0 && screenSDF > 0.0) {
        col = float3(0.16, 0.16, 0.18);
        
        // Dark Inner Bezel Line
        if (screenSDF < 0.6) col = float3(0.04, 0.04, 0.05);

        float2 ledPos = float2(-78.0, -8.0);
        if (length(p - ledPos) < 2.2) col = float3(1.0, 0.2, 0.1);
        
        float2 logoP = p - float2(-34.0, 52.0);
        if (drawStringGBC(logoP, TEXT_GAMEBOY_LOGO, 8) > 0.5) col = float3(0.65);
        float2 colorP = logoP - float2(36.0, 0.0);
        if (drawStringGBC(colorP, TEXT_COLOR_LOGO, 5) > 0.5) {
            float3 cCols[5] = {float3(0.5,0.2,0.7), float3(0.3,0.8,0.2), float3(0.9,0.8,0.1), float3(0.1,0.4,0.9), float3(0.9,0.1,0.2)};
            col = cCols[clamp(int(floor(colorP.x/4.0)), 0, 4)];
        }
    }
    return float4(col, 1.0);
}

fragment float4 fragment8BitGBC(VertexOut in [[stage_in]],
                                texture2d<float> frame0 [[texture(0)]],
                                texture2d<float> frame1 [[texture(1)]],
                                constant GBCUniforms &u [[buffer(0)]]) {

    float scale = min(u.outputSize.x / 165.0, u.outputSize.y / 155.0);
    float2 p = (in.position.xy - (u.outputSize.xy * 0.5)) / scale;

    float2 screenCenter = float2(0.0, -8.0);
    float2 screenSize = float2(70.0, 52.0);
    float screenSDF = sdRoundRectGBC(p - screenCenter, screenSize, 1.0);

    if (screenSDF < 0.0) {
        constexpr sampler samp(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 uv = (p - (screenCenter - screenSize)) / (screenSize * 2.0);
        
        float3 c0 = frame0.sample(samp, uv).rgb;
        float3 c1 = frame1.sample(samp, uv).rgb;
        float3 color = mix(c0, c1, u.ghostingWeight);
        
        // Dot Matrix Grid
        float2 grid = abs(fract(uv * u.sourceSize.xy - 0.5) - 0.5) / fwidth(uv * u.sourceSize.xy);
        color *= mix(1.0, 0.85, (1.0 - smoothstep(0.0, 1.0, min(grid.x, grid.y))) * u.dotOpacity);
        
        // RECESSED SHADOW: Cast to Top and Right
        // Calculated by taking the inverse of the top-left edges
        float shadowTop = smoothstep(-52.0, -47.0, p.y - screenCenter.y);
        float shadowRight = smoothstep(70.0, 65.0, p.x - screenCenter.x);
        float shadow = shadowTop * shadowRight;
        
        color = color * float3x3(0.85, 0.1, 0.05, 0.05, 0.85, 0.1, 0.1, 0.05, 0.85);
        return float4(color * mix(0.74, 1.0, shadow) * u.brightnessBoost, 1.0);
    }

    return renderGBCShell(p, u);
}

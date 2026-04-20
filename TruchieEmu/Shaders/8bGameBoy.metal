#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct EightBitGameBoyUniforms {
    float gridStrength;
    float pixelSeparation;
    float brightnessBoost;
    float colorBoost;
    float4 sourceSize;
    float4 outputSize;
    float showShell;
    float showStrip;
    float showLens;
    float showText;
    float showLED;
    float lightPositionIndex;
    float lightStrength;
};

// --- FONT SYSTEM ---
uint getCharBlock(int c) {
    switch(c) {
        case 0:  return 11245; // A
        case 1:  return 27566; // B
        case 2:  return 14627; // C
        case 3:  return 27502; // D
        case 4:  return 31207; // E
        case 5:  return 23533; // H
        case 6:  return 29847; // I
        case 7:  return 24429; // M
        case 8:  return 24557; // N
        case 9:  return 11114; // O
        case 10: return 27565; // R
        case 11: return 14478; // S
        case 12: return 29842; // T
        case 13: return 23403; // U
        case 14: return 23421; // W
        case 15: return 23213; // X
        case 16: return 23186; // Y
        default: return 0;
    }
}

constant int TEXT_MAIN[28] = {3,9,12,-1, 7,0,12,10,6,15,-1, 14,6,12,5,-1, 11,12,4,10,4,9,-1, 11,9,13,8,3};
constant int TEXT_BATT[7] = {1,0,12,12,4,10,16};

float drawString(float2 p, constant int* textArray, int len) {
    int charIndex = int(floor(p.x / 4.0));
    if (charIndex < 0 || charIndex >= len) return 0.0;
    
    float2 charP = float2(fmod(max(p.x, 0.0), 4.0), p.y);
    if (charP.x >= 3.0 || charP.y < 0.0 || charP.y >= 5.0) return 0.0;
    
    int c = textArray[charIndex];
    if (c == -1) return 0.0;
    
    uint glyph = getCharBlock(c);
    int bit = 14 - (int(floor(charP.y)) * 3 + int(floor(charP.x)));
    return (glyph & (1u << bit)) != 0 ? 1.0 : 0.0;
}

// --- SDF PRIMITIVES ---
float sdRoundRect(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + float2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

float sdLensBox(float2 p, float2 b, float4 r) {
    float rad = (p.x > 0.0) ? ((p.y > 0.0) ? r.y : r.x) : ((p.y > 0.0) ? r.z : r.w);
    float2 q = abs(p) - b + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

fragment float4 fragment8bGameBoy(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant EightBitGameBoyUniforms &u [[buffer(0)]]) {
    
    // 1. PHYSICAL DIMENSIONS
    float2 gameRes = float2(160.0, 144.0);
    float stripW = 2.2;
    float2 lensPadding = float2(42.0, 24.0);
    float2 shellMargin = float2(32.0, 16.0);
    
    // 2. ABSOLUTE SCALING
    float2 assemblySize = gameRes + (lensPadding + shellMargin) * 2.0;
    float scale = min(u.outputSize.x / assemblySize.x, u.outputSize.y / assemblySize.y);
    float intScale = max(1.0, floor(scale));
    float2 p = (in.position.xy - (u.outputSize.xy * 0.5)) / intScale;
    float2 gb = p + (gameRes * 0.5);

    // 3. MASKS
    float screenSDF = sdRoundRect(p, gameRes * 0.5, 1.2);
    float stripSDF  = sdRoundRect(p, (gameRes * 0.5) + stripW, 2.8);
    float lensSDF   = sdLensBox(p, (gameRes * 0.5) + stripW + lensPadding, float4(8.0, 35.0, 8.0, 8.0));

// 4. BEZEL COMPOSITING
    if (screenSDF > 0.0) {
        float3 col = float3(0.1, 0.1, 0.1); // Default background (hidden)
        bool renderedBezel = false;

        // --- LAYER 1: THE BEZEL (Grey Area) ---
        // This is the area outside the strip but inside the lens
        if (u.showShell > 0.5) {
            col = float3(0.38, 0.39, 0.40);
            float noise = fract(sin(dot(gb, float2(12.9898, 78.233))) * 43758.5453);
            col += (noise - 0.5) * 0.012;
            renderedBezel = true;
        }

        // --- LAYER 2: THE INNER STRIP (Greenish Ring) ---
        // Original logic: If screenSDF > 0 AND stripSDF <= 0
        if (u.showStrip > 0.5 && stripSDF <= 0.0) {
            col = float3(0.51, 0.50, 0.12);
            float shadow = max(smoothstep(0.0, -3.0, gb.y), smoothstep(160.0, 163.0, gb.x));
            col *= mix(1.0, 0.25, shadow);
            renderedBezel = true;
        }

        // --- LAYER 3: THE GLASS LENS (Outer Border) ---
        if (u.showLens > 0.5 && lensSDF > 0.0) {
            float borderMix = smoothstep(1.5, 0.0, lensSDF);
            // Light grey shell vs Dark grey border
            col = mix(float3(0.88, 0.88, 0.84), float3(0.18, 0.16, 0.14), borderMix);
            renderedBezel = true;
        }

        // --- LAYER 4: TEXT & LED ---
        if (u.showText > 0.5 && renderedBezel) {
            // Main Text (only if in the grey bezel area)
            if (stripSDF > 0.0 && lensSDF <= 0.0) {
                float textMain = drawString(float2(gb.x - 48.0, gb.y - (-18.0)), TEXT_MAIN, 28);
                if (textMain > 0.0) {
                    col = mix(col, float3(0.68, 0.69, 0.65), textMain);
                } else {
                    // Purple/Blue accent lines
                    if (gb.y > -18.0 && gb.y < -12.5) {
                        bool isLeft = (gb.x >= -34.0 && gb.x <= 42.0);
                        bool isRight = (gb.x >= 166.0 && gb.x <= 192.0);
                        if (isLeft || isRight) {
                            if (gb.y < -16.5) col = mix(col, float3(0.68, 0.10, 0.30), 0.9);
                            else if (gb.y > -14.0) col = mix(col, float3(0.10, 0.15, 0.45), 0.9);
                        }
                    }
                }
            }

            // Battery Text
            float textBatt = drawString(float2(gb.x - (-36.0), gb.y - 57.0), TEXT_BATT, 7);
            if (textBatt > 0.0) col = mix(col, float3(0.65, 0.66, 0.65), textBatt);
        }

        if (u.showLED > 0.5 && renderedBezel) {
            float2 ledP = gb - float2(-28.5, 45.0);
            float ledD = length(ledP);
            if (ledD < 4.5) {
                float glow = pow(1.0 - clamp(ledD / 4.5, 0.0, 1.0), 2.0);
                col = mix(col, float3(0.8, 0.05, 0.02), glow);
                if (ledD < 1.6) col = mix(col, float3(1.0, 0.8, 0.6), 0.9);
            }
        }
        
        return float4(col, 1.0);
    }

    // 5. INTERNAL SCREEN
    float2 snappedGb = floor(gb);
    float2 f = fract(gb); 
    
    float3 src = pow(tex.sample(sampler(filter::linear), (snappedGb + 0.5) / gameRes).rgb, 1.15);
    
    float3 baseLCD = float3(0.35, 0.45, 0.15); 
    src.g += 0.05;
    src.b -= 0.2;

    float g = mix(u.pixelSeparation * 0.45 + 0.08 + sin(snappedGb.y * 0.25) * 0.02, -0.3, smoothstep(0.05, 0.6, dot(src, float3(0.3, 0.6, 0.1))));
    float2 m = smoothstep(0.5 - g + fwidth(f), 0.5 - g - fwidth(f), abs(f - 0.5));
    
    float3 final = mix(baseLCD, src, mix(1.0, m.x * m.y, u.gridStrength)); 
    final.g = clamp(final.g - 0.1, 0.0, 1.0);
    final.b = clamp(final.b + 0.35, 0.0, 1.0);
    final = mix(final, float3(0.5, 0.55, 0.45), 0.2);

    float screenEdgeShadow = smoothstep(-2.0, 5.0, screenSDF);
    final *= mix(0.82, 1.0, screenEdgeShadow);

    // --- DYNAMIC METALLIC REFLECTOR ---
    // Map lightPositionIndex (0-8) to discrete positions:
    // 0: Center, 1: TL, 2: T, 3: TR, 4: L, 5: R, 6: BL, 7: B, 8: BR
    float2 lightPos;
    int idx = int(u.lightPositionIndex);
    if (idx == 0)      lightPos = float2(160.0, 0.0); // Default to Top-Right
    else if (idx == 1) lightPos = float2(0.0, 0.0);
    else if (idx == 2) lightPos = float2(80.0, 0.0);
    else if (idx == 3) lightPos = float2(80.0, 72.0);
    else if (idx == 4) lightPos = float2(0.0, 72.0);
    else if (idx == 5) lightPos = float2(160.0, 72.0);
    else if (idx == 6) lightPos = float2(0.0, 144.0);
    else if (idx == 7) lightPos = float2(80.0, 144.0);
    else               lightPos = float2(160.0, 144.0);

    float distToLight = length(gb - lightPos);
    
    float wave1 = sin(gb.x * 5.0 - gb.y * 2.5);
    float wave2 = sin(gb.x * 2.1 + gb.y * 4.8);
    float metallicGrain = (wave1 * wave2) * 0.5 + 0.5;
    
    float sheen = smoothstep(-100.0, 180.0, gb.x - gb.y);
    float glare = smoothstep(140.0, 0.0, distToLight);
    
    float luma = dot(final, float3(0.299, 0.587, 0.114));
    float reflectionMask = smoothstep(0.05, 0.5, luma); 
    
    float3 reflectionColor = float3(0.88, 0.95, 0.75); 
    
    float glareWeight = 0.35;   
    float sheenWeight = 0.12;   
    float grainWeight = 0.03;   
    
    final += (glare * glareWeight + sheen * sheenWeight + metallicGrain * grainWeight) 
             * reflectionColor * reflectionMask * u.lightStrength;

    return float4(max(final, 0.0) * u.brightnessBoost * u.colorBoost, 1.0);
}
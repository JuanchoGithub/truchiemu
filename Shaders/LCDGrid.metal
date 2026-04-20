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

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    
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
        float3 col;
        if (stripSDF > 0.0) {
            if (lensSDF > 0.0) {
                float borderMix = smoothstep(1.5, 0.0, lensSDF);
                col = mix(float3(0.88, 0.88, 0.84), float3(0.18, 0.16, 0.14), borderMix);
            } else {
                col = float3(0.38, 0.39, 0.40);
                float noise = fract(sin(dot(gb, float2(12.9898, 78.233))) * 43758.5453);
                col += (noise - 0.5) * 0.012;
                
                float textMain = drawString(float2(gb.x - 48.0, gb.y - (-18.0)), TEXT_MAIN, 28);
                if (textMain > 0.0) {
                    col = mix(col, float3(0.68, 0.69, 0.65), textMain);
                } else {
                    if (gb.y > -18.0 && gb.y < -12.5) {
                        bool isLeft = (gb.x >= -34.0 && gb.x <= 42.0);
                        bool isRight = (gb.x >= 166.0 && gb.x <= 192.0);
                        if (isLeft || isRight) {
                            if (gb.y < -16.5) col = mix(col, float3(0.68, 0.10, 0.30), 0.9);
                            else if (gb.y > -14.0) col = mix(col, float3(0.10, 0.15, 0.45), 0.9);
                        }
                    }
                }

                float textBatt = drawString(float2(gb.x - (-36.0), gb.y - 57.0), TEXT_BATT, 7);
                col = mix(col, float3(0.65, 0.66, 0.65), textBatt);
                
                float2 ledP = gb - float2(-28.5, 45.0);
                float ledD = length(ledP);
                if (ledD < 4.5) {
                    float glow = pow(1.0 - clamp(ledD / 4.5, 0.0, 1.0), 2.0);
                    col = mix(col, float3(0.8, 0.05, 0.02), glow);
                    if (ledD < 1.6) col = mix(col, float3(1.0, 0.8, 0.6), 0.9);
                }
            }
        } else {
            col = float3(0.51, 0.50, 0.12);
            float shadow = max(smoothstep(0.0, -3.0, gb.y), smoothstep(160.0, 163.0, gb.x));
            col *= mix(1.0, 0.25, shadow);
        }
        return float4(col, 1.0);
    }

    // 5. INTERNAL SCREEN
    // FIX: Snap gb to floor to ensure every LCD pixel is identical in size
    float2 snappedGb = floor(gb);
    float2 f = fract(gb); 
    
    float3 src = pow(tex.sample(sampler(filter::linear), (snappedGb + 0.5) / gameRes).rgb, 1.15);
    
    float3 baseLCD = float3(0.35, 0.45, 0.15); 
    src.g += 0.05;
    src.b -= 0.2;

    // Use snappedGb for the horizontal grid calculation to prevent "jitter"
    float g = mix(u.pixelSeparation * 0.45 + 0.08 + sin(snappedGb.y * 0.25) * 0.02, -0.3, smoothstep(0.05, 0.6, dot(src, float3(0.3, 0.6, 0.1))));
    float2 m = smoothstep(0.5 - g + fwidth(f), 0.5 - g - fwidth(f), abs(f - 0.5));
    
    float3 final = mix(baseLCD, src, mix(1.0, m.x * m.y, u.gridStrength)); 
    final.g = clamp(final.g - 0.1, 0.0, 1.0);
    final.b = clamp(final.b + 0.35, 0.0, 1.0);
    final = mix(final, float3(0.5, 0.55, 0.45), 0.2);

    // Physical Depth Shadow
    float screenEdgeShadow = smoothstep(-2.0, 5.0, screenSDF);
    final *= mix(0.82, 1.0, screenEdgeShadow);

    // --- METALLIC "SIN" REFLECTOR ---
    
    // Testing variables
    float reflectionStrength = 1.0;    
    float glareWeight        = 0.35;   
    float sheenWeight        = 0.12;   
    float grainWeight        = 0.03;   
    
    float2 lightPos = float2(170.0, -20.0);
    float distToLight = length(gb - lightPos);
    
    // NEW BRUSHED TEXTURE: Dual interference waves to hide the "lines"
    // Wave 1: Tight diagonal lines
    float wave1 = sin(gb.x * 5.0 - gb.y * 2.5);
    // Wave 2: Slower intersecting lines to break up the pattern
    float wave2 = sin(gb.x * 2.1 + gb.y * 4.8);
    // Combine for a non-linear texture
    float metallicGrain = (wave1 * wave2) * 0.5 + 0.5;
    
    // Lighting components
    float sheen = smoothstep(-100.0, 180.0, gb.x - gb.y);
    float glare = smoothstep(140.0, 0.0, distToLight);
    
    // Refined mask to allow subtle texture in midtones
    float luma = dot(final, float3(0.299, 0.587, 0.114));
    float reflectionMask = smoothstep(0.05, 0.5, luma); 
    
    float3 reflectionColor = float3(0.88, 0.95, 0.75); 
    
    // Composite the reflection
    final += (glare * glareWeight + sheen * sheenWeight + metallicGrain * grainWeight) 
             * reflectionColor * reflectionMask * reflectionStrength;

    return float4(max(final, 0.0) * u.brightnessBoost * u.colorBoost, 1.0);
}
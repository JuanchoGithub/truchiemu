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

// Encoded text values
constant int TEXT_MAIN[28] = {3,9,12,-1, 7,0,12,10,6,15,-1, 14,6,12,5,-1, 11,12,4,10,4,9,-1, 11,9,13,8,3};
constant int TEXT_BATT[7] = {1,0,12,12,4,10,16};

float drawString(float2 p, constant int* textArray, int len) {
    int charIndex = int(floor(p.x / 4.0));
    if (charIndex < 0 || charIndex >= len) return 0.0;
    
    float2 charP = float2(fmod(max(p.x, 0.0), 4.0), p.y);
    if (charP.x >= 3.0 || charP.y < 0.0 || charP.y >= 5.0) return 0.0;
    
    int c = textArray[charIndex];
    if (c == -1) return 0.0; // Space
    
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
                // Outer Console Shell + Thin Darkish Brown Border
                float borderMix = smoothstep(1.5, 0.0, lensSDF);
                col = mix(float3(0.90, 0.90, 0.88), float3(0.22, 0.19, 0.16), borderMix);
            } else {
                // Glass Lens Main Area
                col = float3(0.40, 0.41, 0.42);
                
                // Subtle Noise Texture (±0.007 variation)
                float noise = fract(sin(dot(gb, float2(12.9898, 78.233))) * 43758.5453);
                col += (noise - 0.5) * 0.014;
                
                // --- TOP BEZEL TEXT & LINES ---
                // Text completely aligned to the right. 28 chars * 4px = 112 width. Starts at 48. Ends precisely at 160.
                float textMain = drawString(float2(gb.x - 48.0, gb.y - (-18.0)), TEXT_MAIN, 28);
                if (textMain > 0.0) {
                    col = mix(col, float3(0.68, 0.69, 0.65), textMain);
                } else {
                    // Magenta & Blue Flanking Lines
                    // Lines separated further. Gap is now larger (2.5px) and lines are thinner (1.5px)
                    if (gb.y > -18.0 && gb.y < -12.5) {
                        // Margin strictly 6.0px on both sides! Text[48.0 to 160.0]
                        bool isLeft = (gb.x >= -34.0 && gb.x <= 42.0); // Ends 6px before text
                        bool isRight = (gb.x >= 166.0 && gb.x <= 192.0); // Starts 6px after text. Naturally much shorter!
                        if (isLeft || isRight) {
                            if (gb.y < -16.5) col = mix(col, float3(0.68, 0.10, 0.30), 0.9);
                            else if (gb.y > -14.0) col = mix(col, float3(0.10, 0.15, 0.45), 0.9);
                        }
                    }
                }

                // --- LEFT BEZEL BATTERY ---
                // "BATTERY" Text perfectly aligned. A-T gap is perfectly centered on -28.5
                float textBatt = drawString(float2(gb.x - (-36.0), gb.y - 57.0), TEXT_BATT, 7);
                col = mix(col, float3(0.65, 0.66, 0.65), textBatt);
                
                // Red LED Indicator - Shifted to the left of the grey area (-28.5 rather than center -23.2)
                float2 ledP = gb - float2(-28.5, 45.0);
                float ledD = length(ledP);
                if (ledD < 4.5) {
                    float glow = pow(1.0 - clamp(ledD / 4.5, 0.0, 1.0), 2.0);
                    col = mix(col, float3(0.9, 0.1, 0.05), glow);
                    if (ledD < 1.8) col = mix(col, float3(1.0, 0.9, 0.7), 0.8); // Bulb Core
                }
            }
        } else {
            // Reflective Strip
            col = float3(0.53, 0.52, 0.15);
            
            // Shadows strictly locked to Top and Right edges ONLY, dropped to 20% brightness
            float shadow = max(smoothstep(0.0, -4.0, gb.y), smoothstep(160.0, 164.0, gb.x));
            col *= mix(1.0, 0.20, shadow);
        }
        return float4(col, 1.0);
    }

    // 5. INTERNAL SCREEN
    float2 f = fract(gb);
    float3 src = pow(tex.sample(sampler(filter::linear), (floor(gb)+0.5)/gameRes).rgb, 1.1);
    float3 comp = float3(0.43, 0.516, 0.188) - float3(0.0, -0.1, 0.35);
    src.b -= 0.35; src.g += 0.1;

    float g = mix(u.pixelSeparation*0.45 + 0.08 + sin(floor(gb.y)*0.25)*0.02, -0.4, smoothstep(0.05, 0.5, dot(src, float3(0.3,0.6,0.1))));
    float2 m = smoothstep(0.5-g+fwidth(f), 0.5-g-fwidth(f), abs(f-0.5));
    
    float3 final = mix(comp, src, mix(1.0, m.x*m.y, u.gridStrength));
    final.b = clamp(final.b + 0.44, 0.0, 1.0);
    final.g = clamp(final.g - 0.175, 0.0, 1.0);

    final = mix(final, float3(0.55, 0.60, 0.50), 0.30);

    // --- DOT MATRIX LIGHTING EFFECT ---
    // Super subtle diagonal gradient: 1.5% at Top-Right mapping down to 0% at Bottom-Left
    float lightGrad = clamp((gb.x + (144.0 - gb.y)) / 304.0, 0.0, 1.0);
    final += lightGrad * 0.015;

    return float4(max(final, 0.0) * u.brightnessBoost * u.colorBoost, 1.0);
}
